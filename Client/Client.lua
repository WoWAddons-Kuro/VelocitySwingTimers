-- Velocity Swing Timers: the client interface. Flavour files (Client_*.lua) implement every
-- method in Client.INTERFACE; Client_Select.lua binds the chosen one onto NS.Client.
-- No use site may call UnitAttackSpeed / GetSpellInfo / UnitAura / CLEU directly: it goes through here.
--
-- Ground truth for the two flavours: AddonManagement\_EXTERNAL_APIS\wow_swing_timer_api.md.
-- The decisive difference: on Classic Era swings arrive via COMBAT_LOG_EVENT_UNFILTERED; on WoW Forever the
-- combat log is refused and weapon speeds are secret in combat, so swings arrive via PLAYER_SWING.
-- The trackers therefore never read speeds themselves: the flavour pushes anchors through the sink below.
--
-- VWST_SwingSink (what Client.StartSwingSource(sink) delivers to; every callback optional):
--   sink.OnSwing(hand, speedSeconds)        hand = "mainhand" | "offhand" | "ranged"; a swing/shot just happened,
--                                           the next one is speedSeconds away (plain number, always readable)
--   sink.OnPlayerParried()                  the PLAYER parried an incoming attack (parry haste applies to the player)
--   sink.OnSpellSent(spellID, castGUID)     player's UNIT_SPELLCAST_SENT: the PRESS, before any outcome (SPEC 12.17)
--   sink.OnSpellSucceeded(spellID, castGUID) player's UNIT_SPELLCAST_SUCCEEDED (spellID may be nil if secret)
--   sink.OnSpellCastStart(spellID)          player's UNIT_SPELLCAST_START
--   sink.OnSpellCastStop(spellID, reason)   reason = "failed" | "interrupted" | "stop"
--   sink.OnSpellFailedQuiet(spellID)        UNIT_SPELLCAST_FAILED_QUIET (Auto Shot movement cancel)
--   sink.OnChannel(isOn, spellID)           UNIT_SPELLCAST_CHANNEL_START / _STOP (Tame Beast, Volley...) - SPEC 12.18
--   sink.OnAutoRepeat(isOn)                 START/STOP_AUTOREPEAT_SPELL
--   sink.OnAutoAttack(isOn)                 PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT (melee auto-attack toggle)
--   sink.OnAttackSpeedChanged()             UNIT_ATTACK_SPEED for the player (Era: rescale; Forever: speeds secret)
--   sink.OnWeaponChanged(slot)              PLAYER_EQUIPMENT_CHANGED for slots 16/17/18
local ADDON_NAME, NS = ...

local Client = {}
NS.Client = Client
NS.ClientFlavours = {}

Client.INTERFACE = {
  "PlayerKey",            -- -> UnitGUID("player")  (the only per-character key)
  "PlayerDisplayName",    -- -> "Kuro" (Era) | "Kuro Oakheart" (Forever)
  "PlayerFirstName",      -- -> UnitName("player")
  "PlayerClass",          -- -> "WARRIOR" | "HUNTER" | ... (the non-localised class token)
  "AttackSpeeds",         -- () -> mh, oh|nil, ranged|nil  seconds; nil when secret (Forever in combat) or absent
  "SpeedsReadable",       -- () -> bool  false while UnitAttackSpeed returns secret values (Forever in combat)
  "SpellInfo",            -- (spellID) -> name|nil, castTimeMs|nil
  "PlayerAuraSpellIDs",   -- () -> { [spellID] = true } for the player's current buffs (empty if secret)
  "RangedWeaponItemID",   -- () -> itemID|nil of INVSLOT_RANGED
  "IsAutoRepeatSpell",    -- (spellID) -> bool  Auto Shot / Shoot / Shoot Wand
  "AttackToggleSpellID",  -- () -> 6603 (Era) | 6803 (Forever): the auto-attack toggle seen on UNIT_SPELLCAST_SUCCEEDED
  "SupportsTargetSwings", -- () -> bool  false on Forever (no target swing source exists)
  "IsSpellInRangeOfTarget", -- (spellID) -> true | false | nil   nil = no target / unknown / secret (SPEC 14.1)
  "IsTargetNear",         -- () -> true | false | nil   target within ~10 yd (CheckInteractDistance duel); splits "out" into far | near (SPEC 14.1)
  "RangedWeaponKind",     -- () -> "bow" | "gun" | "thrown" | nil   from the equipped ranged weapon's subclass (SPEC 14.2)
  "StartSwingSource",     -- (sink) register the flavour's events and deliver VWST_SwingSink callbacks
  "HasEditMode",          -- () -> bool
  "OpenSettings",         -- (categoryID)
}

-- Shared helpers for the flavour files ----------------------------------------------------

function Client.DisplayNameFromParts(name, surname)
  if surname and surname ~= "" then return name .. " " .. surname end
  return name
end

-- Dispatch helper: call sink[name](...) if present.
function Client.Emit(sink, name, ...)
  local fn = sink and sink[name]
  if fn then fn(...) end
end

-- The UNIT_SPELLCAST_* / autorepeat / equipment / attack-speed events are identical on both flavours;
-- each flavour registers them on its own frame and routes them here. Only the swing anchor differs.
-- arg4 only matters for UNIT_SPELLCAST_SENT, whose payload is (unit, target, castGUID, spellID)
function Client.RouteCommonEvent(sink, event, unit, arg2, arg3, arg4)
  if event == "UNIT_SPELLCAST_SENT" then
    Client.ProbeOnce(event, unit, arg2, arg3, arg4)
    -- SPEC 12.17: press time. Payload is (unit, target, castGUID, spellID); the GUID threads to the outcome events.
    if unit == "player" then Client.Emit(sink, "OnSpellSent", NS.Util.PlainNumber(arg4, nil), arg3) end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if unit == "player" then Client.Emit(sink, "OnSpellSucceeded", NS.Util.PlainNumber(arg3, nil), arg2) end
  elseif event == "UNIT_SPELLCAST_START" then
    if unit == "player" then Client.Emit(sink, "OnSpellCastStart", NS.Util.PlainNumber(arg3, nil)) end
  elseif event == "UNIT_SPELLCAST_FAILED" then
    if unit == "player" then Client.Emit(sink, "OnSpellCastStop", NS.Util.PlainNumber(arg3, nil), "failed", arg2) end
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
    if unit == "player" then Client.Emit(sink, "OnSpellCastStop", NS.Util.PlainNumber(arg3, nil), "interrupted", arg2) end
  elseif event == "UNIT_SPELLCAST_STOP" then
    if unit == "player" then Client.Emit(sink, "OnSpellCastStop", NS.Util.PlainNumber(arg3, nil), "stop", arg2) end
  elseif event == "UNIT_SPELLCAST_FAILED_QUIET" then
    if unit == "player" then Client.Emit(sink, "OnSpellFailedQuiet", NS.Util.PlainNumber(arg3, nil), arg2) end
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
    if unit == "player" then Client.Emit(sink, "OnChannel", true, NS.Util.PlainNumber(arg3, nil)) end
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if unit == "player" then Client.Emit(sink, "OnChannel", false, NS.Util.PlainNumber(arg3, nil)) end
  elseif event == "START_AUTOREPEAT_SPELL" then Client.Emit(sink, "OnAutoRepeat", true)
  elseif event == "STOP_AUTOREPEAT_SPELL" then Client.Emit(sink, "OnAutoRepeat", false)
  elseif event == "PLAYER_ENTER_COMBAT" then Client.Emit(sink, "OnAutoAttack", true)
  elseif event == "PLAYER_LEAVE_COMBAT" then Client.Emit(sink, "OnAutoAttack", false)
  elseif event == "UNIT_ATTACK_SPEED" then
    if unit == "player" then Client.Emit(sink, "OnAttackSpeedChanged") end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    local slot = unit  -- first payload arg
    if slot == 16 or slot == 17 or slot == 18 then Client.Emit(sink, "OnWeaponChanged", slot) end
  end
end

Client.COMMON_EVENTS = {
  "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
  "PLAYER_EQUIPMENT_CHANGED",
}
Client.COMMON_UNIT_EVENTS = {
  "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_ATTACK_SPEED",
}

function Client.RegisterCommonEvents(frame)
  for _, e in ipairs(Client.COMMON_EVENTS) do pcall(frame.RegisterEvent, frame, e) end
  for _, e in ipairs(Client.COMMON_UNIT_EVENTS) do
    -- Record HOW each event registered (unit / plain / FAILED) in NS.features so /vwst status shows it. A pcall that
    -- swallows both attempts is a silent failure (2026-11-24: UNIT_SPELLCAST_SENT produced no presses all session).
    local okUnit, retUnit = pcall(frame.RegisterUnitEvent, frame, e, "player")
    if okUnit and retUnit ~= false then
      NS.features["Event." .. e] = "unit"
    else
      local okPlain, retPlain = pcall(frame.RegisterEvent, frame, e)
      NS.features["Event." .. e] = (okPlain and retPlain ~= false) and "plain" or "FAILED"
    end
  end
end

-- One-shot raw payload probe for an event, printed the first time it arrives (debug aid; SPEC 12.17 SENT).
local probed = {}
function Client.ProbeOnce(event, ...)
  if probed[event] or not (NS.DB and NS.DB.Global().debugTimerPrediction) then return end
  probed[event] = true
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  NS.Util.Print("|cff40c0ffprobe|r %s(%s)", event, table.concat(parts, ", "))
end