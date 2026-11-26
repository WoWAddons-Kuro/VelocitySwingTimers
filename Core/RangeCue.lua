-- Velocity Swing Timers: the range-entry weapon sound (SPEC 14). Reference behaviour is WoW Forever, which plays the
-- bow-draw / gun-cock when a hostile target comes INTO Auto Shot range from out of range - the "can I act yet?"
-- question moved from the eyes to the ears. Era does not do this; this module makes Era sound like Forever.
--
-- Trigger (14.1): a 0.2 s poller while a hostile attackable target exists. band = in | out of range of the cue spell
-- (hunter: Auto Shot 75; casters later, SPEC 14.8). Play on out -> in, on the SAME target GUID, throttled, never on a
-- target swap (a new GUID starts at "none"), never while channeling, never on an uncertain (nil) range read.
-- Sound (14.2): derived from the equipped ranged weapon - bow/crossbow -> draw, gun -> cock. No sound search exists.
local ADDON_NAME, NS = ...
local Util, Client, SpellData, DB = NS.Util, NS.Client, NS.SpellData, NS.DB

local RangeCue = {}
NS.RangeCue = RangeCue

local RANGE_POLL_SECONDS = 0.2
local RANGE_SOUND_MIN_GAP = 1.0     -- s; a mob jittering on the 35 yd line must not machine-gun the cue
local SOUND_CHANNEL = "SFX"

-- VWST_RangeBand = "none" | "out" | "far" | "near" | "in"   (out: not in range, unsplit; far: > 35 yd; near: < ~10 yd = deadzone / melee)
local state = {
  band = "none",            -- VWST_RangeBand for the current target
  targetGUID = nil,         -- the GUID the band was observed on; a new GUID resets band to "none"
  lastPlayedAt = 0,
  ticker = nil,
}
RangeCue.state = state

-- SPEC 14.3: two switches. Out of combat: nil = flavour default (Era on, Forever off). In combat: plain boolean, default off.
function RangeCue.EnabledOutOfCombat()
  local g = DB.Global()
  if g.rangeEntrySound == nil then return Client.flavour == "classic_era" end
  return g.rangeEntrySound == true
end
function RangeCue.EnabledInCombat()
  return DB.Global().rangeEntrySoundInCombat == true
end
local function Enabled() return RangeCue.EnabledOutOfCombat() or RangeCue.EnabledInCombat() end

local function CueSpellID()
  local p = DB.Profile()
  local rc = p.rangeCue
  return rc and rc.spellID or SpellData.AUTO_SHOT
end

-- SPEC 14.2: the sound for the weapon in hand. nil = no cue for this weapon (thrown, wand, none).
function RangeCue.SoundFor(kind)
  kind = kind or Client.RangedWeaponKind()
  if not kind then return nil end
  local s = SpellData.RANGE_SOUND
  return s and s[kind] or nil, kind
end

local function Play(reason)
  local fileID, kind = RangeCue.SoundFor()
  if not fileID then return false end
  local ok = pcall(PlaySoundFile, fileID, SOUND_CHANNEL)
  if NS.trace or (DB.Global().debugTimerPrediction == true) then
    Util.Print("|cff40c0ffrange cue|r %s  (%s, file %s) %s", kind, reason or "in range", tostring(fileID), ok and "" or "- PlaySoundFile failed")
  end
  return ok
end

-- Options "Preview" buttons (SPEC 14.2 TBD-A): hear the current candidate for a weapon kind regardless of what is equipped.
function RangeCue.Preview(kind)
  local fileID = RangeCue.SoundFor(kind)
  if not fileID then Util.Print("no range-cue sound configured for %s", tostring(kind)) return end
  local ok = pcall(PlaySoundFile, fileID, SOUND_CHANNEL)
  Util.Print("preview %s: file %s%s", kind, tostring(fileID), ok and "" or " (PlaySoundFile failed - wrong ID?)")
end

local function Tick()
  if not Enabled() then return end
  if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDeadOrGhost("target") then
    state.band, state.targetGUID = "none", nil
    return
  end
  local guid = UnitGUID("target")
  if guid ~= state.targetGUID then
    -- SPEC 14.5: a target swap is not an approach. Start the new GUID at "none" so its first band is silent.
    state.targetGUID, state.band, state.playedForGUID = guid, "none", false
  end
  local inRange = Client.IsSpellInRangeOfTarget(CueSpellID())
  if inRange == nil then state.band = "none" return end   -- unknown / secret: never cue on uncertainty
  -- Owner 2026-11-25: the cue is the APPROACH cue - "it came INTO shooting range". Two switches, one suppression:
  --   out of combat (default on) / in combat (default OFF): which situations may play at all.
  --   NEUTRAL (yellow) target, out of combat: the only case that misfires in practice - you target a yellow and walk
  --     past it, in and out of range, never meaning to fight. For those: only far -> in (the near-test is certain out
  --     of combat: far (> 35) | near (< ~10, melee or deadzone) | in), and AT MOST ONCE PER TARGET.
  --   HOSTILE (red) target, or any target in combat: NO suppression. Every out -> in plays (throttled). Deadzone vs
  --     far is unreadable in combat anyway (CheckInteractDistance is nil), and a red that is coming at you is exactly
  --     the cue the owner wants.
  local now = GetTime()
  local inCombat = UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown())
  local reaction = UnitReaction("player", "target")        -- 1..3 hostile, 4 neutral, 5+ friendly (not attackable)
  local suppressed = (not inCombat) and reaction ~= nil and reaction >= 4   -- yellow, out of combat
  local band
  if inRange then
    band = "in"
  elseif not suppressed then
    band = "out"                          -- red or in combat: we do not split it
  else
    local meleeSpell = SpellData.RANGE_MELEE_SPELL[Client.PlayerClass() or ""]
    local inMelee = meleeSpell and Client.IsSpellInRangeOfTarget(meleeSpell) == true
    local near = Client.IsTargetNear()   -- certain out of combat
    if inMelee or near == true then band = "near"
    elseif near == false then band = "far"
    else band = "near" end                -- unknown while suppressed: the side that does not play
  end
  local prev = state.band
  state.band = band
  if band ~= "in" or prev == "in" or prev == "none" then return end
  if inCombat and not RangeCue.EnabledInCombat() then return end
  if not inCombat and not RangeCue.EnabledOutOfCombat() then return end
  if suppressed and (prev ~= "far" or state.playedForGUID) then return end
  if now - state.lastPlayedAt < RANGE_SOUND_MIN_GAP then return end
  if NS.ShotTracker and NS.ShotTracker.IsChanneling and NS.ShotTracker.IsChanneling() then return end
  if NS.ShotTracker and NS.ShotTracker.HasRangedWeapon and not NS.ShotTracker.HasRangedWeapon() then return end
  if UnitIsDeadOrGhost("player") then return end
  local reason = string.format("%s -> in (%s%s)", prev, inCombat and "combat" or "ooc", suppressed and ", neutral: once" or "")
  if Play(reason) then
    state.lastPlayedAt = now
    if suppressed then state.playedForGUID = true end
  end
end

local function Arm()
  if state.ticker then return end
  state.ticker = C_Timer.NewTicker(RANGE_POLL_SECONDS, Tick)
end

local function Disarm()
  if state.ticker then state.ticker:Cancel(); state.ticker = nil end
  state.band, state.targetGUID = "none", nil
end

-- The ticker runs only while a target exists (PLAYER_TARGET_CHANGED arms / disarms it): zero cost otherwise.
local function OnTargetChanged()
  if UnitExists("target") and UnitCanAttack("player", "target") then Arm() else Disarm() end
end

function RangeCue.Init()
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_TARGET_CHANGED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", OnTargetChanged)
  OnTargetChanged()
  NS.features["RangeCue"] = true
end

-- The band is also useful text for /vwst status.
function RangeCue.Status()
  local fileID, kind = RangeCue.SoundFor()
  local meleeSpell = SpellData.RANGE_MELEE_SPELL[Client.PlayerClass() or ""]
  return string.format("range cue: out-of-combat %s, in-combat %s | band %s | played for this target %s | spell %d | melee probe %s | weapon %s%s | ticker %s",
    RangeCue.EnabledOutOfCombat() and "on" or "off", RangeCue.EnabledInCombat() and "on" or "off", state.band, tostring(state.playedForGUID), CueSpellID(), tostring(meleeSpell),
    tostring(kind), fileID and (" file " .. tostring(fileID)) or " (no sound)",
    state.ticker and "armed" or "idle")
end