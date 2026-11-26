-- Velocity Swing Timers: Classic Era / Anniversary client (WOW_PROJECT_CLASSIC).
-- Swing anchors come from COMBAT_LOG_EVENT_UNFILTERED; weapon speeds are always readable.
local ADDON_NAME, NS = ...
local Client, Util = NS.Client, NS.Util

local impl = {}
NS.ClientFlavours.classic_era = impl

function impl.PlayerKey() return UnitGUID("player") end
function impl.PlayerDisplayName() return UnitName("player") end
function impl.PlayerFirstName() return UnitName("player") end
function impl.PlayerClass() return select(2, UnitClass("player")) end

function impl.AttackSpeeds()
  local mh, oh = UnitAttackSpeed("player")
  local ranged = UnitRangedDamage("player")
  if oh == 0 then oh = nil end
  if ranged == 0 then ranged = nil end
  return mh, oh, ranged
end

function impl.SpeedsReadable() return true end

function impl.SpellInfo(spellID)
  if not spellID then return nil end
  local name, _, _, castTime = GetSpellInfo(spellID)
  return name, castTime
end

function impl.PlayerAuraSpellIDs()
  local out = {}
  for i = 1, 40 do
    local name, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
    if not name then break end
    if spellID then out[spellID] = true end
  end
  return out
end

function impl.RangedWeaponItemID() return GetInventoryItemID("player", INVSLOT_RANGED or 18) end

function impl.IsAutoRepeatSpell(spellID)
  if C_Spell and C_Spell.IsRangedAutoAttackSpell then
    local ok, r = pcall(C_Spell.IsRangedAutoAttackSpell, spellID)
    if ok and r ~= nil then return r == true end
  end
  return NS.SpellData.RANGED_AUTO[spellID] == true
end

function impl.AttackToggleSpellID() return 6603 end
function impl.SupportsTargetSwings() return true end

-- SPEC 14.1: band test only (no numeric distance API exists). Era: plain 1/0/nil from IsSpellInRange. The spell-ID
-- form is a later addition to this API; if it yields nil for an ID, retry by name (the spell is in the book, so the
-- name form is authoritative). nil from both = genuinely unknown, and RangeCue never cues on unknown.
function impl.IsSpellInRangeOfTarget(spellID)
  if not spellID or not UnitExists("target") then return nil end
  local r = IsSpellInRange(spellID, "target")
  if r == nil then
    local name = GetSpellInfo(spellID)
    if name then r = IsSpellInRange(name, "target") end
  end
  if r == 1 or r == true then return true elseif r == 0 or r == false then return false end
  return nil
end

-- SPEC 14.1 near-test: is the target inside ~10 yd? CheckInteractDistance index 3 (duel) is 9.9 yd on Classic, works on
-- any unit and in combat. The 5-8 yd deadzone lies wholly inside it, so "Auto Shot out of range AND near" = deadzone /
-- melee, "out AND not near" = far. Only far -> in plays the cue.
function impl.IsTargetNear()
  if not UnitExists("target") then return nil end
  local ok, r = pcall(CheckInteractDistance, "target", 3)
  if not ok or r == nil then return nil end
  return r == true or r == 1
end

-- SPEC 14.2: the cue is derived from the equipped ranged weapon's subclass, never configured.
local RANGED_KIND_BY_SUBCLASS = { [LE_ITEM_WEAPON_BOWS or 2] = "bow", [LE_ITEM_WEAPON_CROSSBOW or 18] = "bow",
                                  [LE_ITEM_WEAPON_GUNS or 3] = "gun", [LE_ITEM_WEAPON_THROWN or 16] = "thrown" }
function impl.RangedWeaponKind()
  local itemID = impl.RangedWeaponItemID()
  if not itemID then return nil end
  local _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = GetItemInfo(itemID)
  if classID ~= (LE_ITEM_CLASS_WEAPON or 2) then return nil end
  return RANGED_KIND_BY_SUBCLASS[subclassID]
end
function impl.HasEditMode() return C_EditMode ~= nil and C_EditMode.GetLayouts ~= nil end
function impl.OpenSettings(id) if Settings and Settings.OpenToCategory then Settings.OpenToCategory(id) end end

-- CLEU payload positions (CombatLogGetCurrentEventInfo):
--   1 ts, 2 subEvent, 3 hideCaster, 4 sourceGUID, 5 sourceName, 6 sourceFlags, 7 sourceRaidFlags,
--   8 destGUID, 9 destName, 10 destFlags, 11 destRaidFlags, then per-event:
--   SWING_DAMAGE: 12 amount ... 21 isOffHand
--   SWING_MISSED: 12 missType, 13 isOffHand
function impl.StartSwingSource(sink)
  local f = CreateFrame("Frame")
  local playerGUID = UnitGUID("player")
  Client.RegisterCommonEvents(f)
  f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")

  -- SPEC 12.17 press anchor on Era. Measured 2026-11-24: UNIT_SPELLCAST_SENT registers and parses fine but fires
  -- ONLY for an opener - once Auto Shot is active the client treats the pending auto as "already casting" and emits
  -- no SENT for instants pressed during it, which is exactly the press we need. Upstream WeaponSwingTimer hooked the
  -- cast API calls instead; so do we. hooksecurefunc fires AFTER the secure call, at the press, for keybinds and
  -- macros alike (a macro button goes through UseAction). The castGUID is not known here; a press is keyed by
  -- spellID and the outcome pairs to the most recent unresolved press of that spell (ShotTracker.ResolvePressBySpell).
  -- Dedup: the same press can hit two of these (CastSpellByName inside UseAction); PRESS_DEDUP_WINDOW collapses it.
  local lastPress = {}   -- spellID -> GetTime()
  local PRESS_DEDUP_WINDOW = 0.05
  local function Press(spellID)
    spellID = NS.Util.PlainNumber(spellID, nil)
    if not spellID then return end
    local now = GetTime()
    if lastPress[spellID] and now - lastPress[spellID] < PRESS_DEDUP_WINDOW then return end
    lastPress[spellID] = now
    Client.Emit(sink, "OnSpellSent", spellID, nil)   -- nil castGUID: pair by spellID downstream
  end
  local function SpellIDFromName(name)
    if not name then return nil end
    local info = GetSpellInfo and { GetSpellInfo(name) }
    return info and info[7] or nil
  end
  if hooksecurefunc then
    pcall(hooksecurefunc, "CastSpellByName", function(name) Press(SpellIDFromName(name)) end)
    pcall(hooksecurefunc, "CastSpellByID",   function(id)   Press(id) end)
    pcall(hooksecurefunc, "CastSpell",       function(index, bookType)
      local _, _, id = GetSpellBookItemName and GetSpellBookItemName(index, bookType)
      if not id and GetSpellBookItemInfo then local _, sid = GetSpellBookItemInfo(index, bookType); id = sid end
      Press(id)
    end)
    pcall(hooksecurefunc, "UseAction", function(slot)
      local kind, id = GetActionInfo(slot)
      if kind == "spell" then Press(id)
      elseif kind == "macro" then
        -- the macro's first castable spell is what fires; GetMacroSpell resolves conditionals for the current state
        local sid = GetMacroSpell and GetMacroSpell(id)
        if sid then Press(sid) end
      end
    end)
    NS.features["PressHook"] = true
  end
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      local _, sub, _, src, _, _, _, dst = CombatLogGetCurrentEventInfo()
      if sub == "SWING_DAMAGE" and src == playerGUID then
        local isOff = select(21, CombatLogGetCurrentEventInfo())
        local mh, oh = impl.AttackSpeeds()
        Client.Emit(sink, "OnSwing", isOff and "offhand" or "mainhand", isOff and oh or mh)
      elseif sub == "SWING_MISSED" then
        local missType, isOff = select(12, CombatLogGetCurrentEventInfo())
        if src == playerGUID then
          local mh, oh = impl.AttackSpeeds()
          Client.Emit(sink, "OnSwing", isOff and "offhand" or "mainhand", isOff and oh or mh)
        end
        if missType == "PARRY" and dst == playerGUID then Client.Emit(sink, "OnPlayerParried") end
      end
    elseif event == "PLAYER_ENTERING_WORLD" then
      playerGUID = UnitGUID("player")
    else
      Client.RouteCommonEvent(sink, event, ...)
    end
  end)
  NS.features["SwingSource.CLEU"] = true
  return f
end