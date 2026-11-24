-- Velocity Swing Timers: the ranged auto-attack clock - Hunter Auto Shot (75) and caster wand Shoot (5019).
-- Pure state, no frames. Fed by the client's VWST_SwingSink; read by UI\ShotGroup.
--
-- Cycle model (AddonManagement\_EXTERNAL_APIS\wow_swing_timer_api.md section 3):
--   shot lands        -> shotStart = now, shotEnd = now + rangedSpeed
--   the last autoShotCastTime seconds of the cycle are the stand-still window (hunter only); moving
--   inside it cancels the shot: UNIT_SPELLCAST_FAILED_QUIET 75 -> shotEnd = now + 0.5 + autoShotCastTime
--   autoShotCastTime  = 0.52 * rangedSpeed / rangedBaseSpeed   (base speed from the weapon tooltip)
--   wand Shoot        = same cycle, no stand-still window
--   isShooting (START/STOP_AUTOREPEAT_SPELL) decides whether an expired cycle means another shot is pending.
-- Era anchors on UNIT_SPELLCAST_SUCCEEDED 75/5019 (Client routes OnSpellSucceeded); Forever anchors on
-- PLAYER_SWING type Ranged (Client routes OnSwing("ranged")). Both arrive here; the flavour that has
-- PLAYER_SWING never also anchors on SUCCEEDED (double anchor would drift the clock).
local ADDON_NAME, NS = ...
local Util, Client, SpellData = NS.Util, NS.Client, NS.SpellData

local ShotTracker = {}
NS.ShotTracker = ShotTracker

local state = {
  speed = nil,          -- hasted ranged cycle, seconds
  baseSpeed = nil,      -- unhasted weapon speed from the tooltip
  shotStart = nil, shotEnd = nil,
  isShooting = false,
  lastShotTime = 0,     -- GetTime() of the last landed shot (or autorepeat start); activity model
  movedInWindow = false,
  retryPhase = nil,     -- SPEC 12.9: engine retry metronome phase = GetTime() mod AUTO_SHOT_RECAST_DELAY; nil = blind
  lastRetryAt = nil,    -- GetTime() of the last FAILED_QUIET 75
  gcdDrift = {},        -- SPEC 12.9 TBD-A diagnostic ring: { drift = s, sinceShot = s }
  gcdDriftIdx = 0,
  castStartAt = nil,    -- when the current clean cast attempt began (channel "casting")
  flashUntil = nil,     -- SPEC 12.6a: shot-event flash end time
}
local GCD_DRIFT_RING = 8
local GCD_DRIFT_TOLERANCE = 0.08   -- s; a predicted tick further off than this is announced as a misprediction
local GCD_DUPLICATE_WINDOW = 0.005 -- s; two FAILED_QUIET closer than this are the same failure delivered twice

-- SPEC 12.9 diagnostic event log: every shot-related event with its time, so a misprediction can dump the causal chain
-- ("what reset the GCD that we did not honour"). Ring of the last 24 events; dumped by DumpShotEventLog on failure.
-- VWST_ShotEventLogEntry = { t = GetTime(), what = string }
local SHOT_EVENT_LOG_SIZE = 24
local shotEventLog, shotEventLogIdx = {}, 0
local function LogShotEvent(fmt, ...)
  shotEventLogIdx = (shotEventLogIdx % SHOT_EVENT_LOG_SIZE) + 1
  shotEventLog[shotEventLogIdx] = { t = GetTime(), what = select("#", ...) > 0 and string.format(fmt, ...) or fmt }
end
local function DumpShotEventLog(title)
  local now = GetTime()
  Util.Print("|cffff4040%s|r - last shot events (newest first):", title)
  for i = 1, SHOT_EVENT_LOG_SIZE do
    local idx = ((shotEventLogIdx - i) % SHOT_EVENT_LOG_SIZE) + 1
    local e = shotEventLog[idx]
    if not e then break end
    -- stop at 10 s back: older than that is a different fight
    if now - e.t > 10 then break end
    Util.Print("  %6.2fs ago  %s", now - e.t, e.what)
  end
end
ShotTracker.DumpShotEventLog = DumpShotEventLog
ShotTracker.state = state
local listeners = {}
local tooltip
local baseSpeedCache = {}   -- itemID -> base speed
local DropGCDReference      -- defined below Anchor, which calls it: forward-declare so the upvalue binds

local function Fire(what) for _, fn in ipairs(listeners) do fn(what) end end

function ShotTracker.OnChanged(fn) listeners[#listeners + 1] = fn end
function ShotTracker.LastActivity() return state.lastShotTime end
function ShotTracker.IsShooting() return state.isShooting end
function ShotTracker.IsHunter() return Client.PlayerClass() == "HUNTER" end
function ShotTracker.HasRangedWeapon() return state.speed ~= nil end

-- The stand-still window length; 0 for wands.
function ShotTracker.CastWindow()
  if not ShotTracker.IsHunter() or not state.speed then return 0 end
  local base = state.baseSpeed or state.speed
  return SpellData.AUTO_SHOT_CAST_BASE * state.speed / base
end

-- Window as a fraction of the cycle (0..1); 0 when there is no window or no speed. SPEC 12: sizes the GCD region.
function ShotTracker.WindowFrac()
  if not state.speed or state.speed <= 0 then return 0 end
  return math.min(1, ShotTracker.CastWindow() / state.speed)
end

-- remaining, cycle, progress (1 = shot fires), inWindow; nil when no shot cycle is in flight
function ShotTracker.Cycle(now)
  if not state.shotEnd or not state.speed then return nil end
  now = now or GetTime()
  local remaining = state.shotEnd - now
  if remaining <= 0 then return 0, state.speed, 1, false end
  local total = state.shotEnd - state.shotStart
  if total <= 0 then total = state.speed end
  return remaining, state.speed, Util.Clamp(1 - remaining / total, 0, 1), remaining <= ShotTracker.CastWindow()
end

-- SPEC 12.3: is the player moving? Era: GetUnitSpeed readable. Forever: may be secret in combat -> treat as still.
local function IsMoving()
  local v = Util.PlainNumber((GetUnitSpeed("player")), nil)
  return v ~= nil and v > 0
end

-- SPEC 12.9: remaining fraction of the current retry block, from the carried metronome phase. 0 when blind.
-- The metronome free-runs: next tick = smallest t > now with t = retryPhase (mod period).
local function BlockFrac(now)
  if not state.retryPhase then return 0 end
  local period = SpellData.AUTO_SHOT_RECAST_DELAY
  local untilTick = (state.retryPhase - now) % period
  return untilTick / period
end

function ShotTracker.HasGCDReference() return state.retryPhase ~= nil end

-- SPEC 12.3 / 12.5. One frame of the channel model, pure from state + now. nil when no cycle is in flight.
-- VWST_ShotSnapshot = { phase = VWST_ShotPhase, charge = 0..1, channelState = VWST_ShotChannelState,
--                       blockFrac = 0..1, castFrac = 0..1, flashFrac = 0..1, remaining = seconds, cycle, window }
function ShotTracker.Snapshot(now)
  if not state.shotEnd or not state.speed then return nil end
  now = now or GetTime()
  local window = ShotTracker.CastWindow()
  local readyAt = state.shotEnd - window
  local chargeLen = math.max(readyAt - state.shotStart, 0.01)
  local snap = {
    cycle = state.speed, window = window,
    remaining = math.max(state.shotEnd - now, 0),   -- charging: time to the shot; overwritten per channel state below
    charge = Util.Clamp((now - state.shotStart) / chargeLen, 0, 1),
    flashFrac = state.flashUntil and Util.Clamp((state.flashUntil - now) / SpellData.SHOT_FLASH_SECONDS, 0, 1) or 0,
    blockFrac = 0, castFrac = 0,
    moving = IsMoving(),   -- SPEC 12: exposed in every phase so the GCD region can go solid red while charging too
  }
  if now < readyAt or window <= 0 then
    snap.phase = "charging"; snap.channelState = "idle"
    snap.gcdBlind = state.retryPhase == nil
    snap.blockFrac = BlockFrac(now)
    snap.drawBlockFrac = snap.moving and 1 or 0   -- SPEC 12.10: while charging the brick is full only while moving
    return snap
  end
  snap.phase = "ready"
  local moving = snap.moving
  snap.gcdBlind = state.retryPhase == nil
  local blockFrac = BlockFrac(now)
  -- SPEC 12.9 misprediction, the other direction: we hold a phase and PREDICTED a tick while the player was moving
  -- for the WHOLE interval leading up to it (so the engine MUST have failed and fired FAILED_QUIET), but no event
  -- came. SPEC 12.11(b): the earlier version false-fired when `moving` flipped for a single frame after a cast; we
  -- now require continuous movement since before the predicted tick (movingSince tracks the current movement run).
  if moving then state.movingSince = state.movingSince or now else state.movingSince = nil end
  if state.retryPhase and moving and state.lastRetryAt and state.movingSince then
    local period = SpellData.AUTO_SHOT_RECAST_DELAY
    local predicted = now - ((now - state.retryPhase) % period)      -- the most recent predicted tick <= now
    if predicted > state.lastRetryAt + period / 2 and now - predicted > GCD_DRIFT_TOLERANCE
       and predicted ~= state.lastMissedTick
       and state.movingSince < predicted - GCD_DRIFT_TOLERANCE then
      state.lastMissedTick = predicted
      Util.Print("|cffff4040GCD tick missed|r predicted %+.3fs ago, no FAILED_QUIET  [shot +%.2fs | lastRetry %.2fs ago | readyAt %+.2fs | GCD %s | speed %.2f win %.2f]",
        now - predicted, now - state.lastShotTime, now - state.lastRetryAt, readyAt - now,
        tostring(ShotTracker.GCDRemaining()), state.speed or 0, window)
      DumpShotEventLog("missed tick")
    end
  end
  -- SPEC 12.10 (owner 2026-11-24). ONE latch decides everything once the player is still: stopWaitTick = the retry
  -- tick we believe the engine will take next, latched the moment the player stops (from the carried phase). Before
  -- it: blocked, brick drains toward the bottom. After it: CASTING, brick gone, green grows - and it STAYS casting
  -- until a FAILED_QUIET (engine said no -> re-latch from the new phase) or the shot lands. The free-running phase is
  -- never consulted again after the latch, so the brick cannot recycle and the green cannot be reset by a wrap.
  -- (Bug fixed 2026-11-24: `blocked` used the cycling BlockFrac, so every 0.5 s wrap re-blocked and wiped castStartAt;
  -- the brick cycled forever and green never appeared.)
  local period = SpellData.AUTO_SHOT_RECAST_DELAY
  local blocked
  if moving then
    state.stopWaitTick = nil
    snap.drawBlockFrac = 1
    blocked = true
  else
    -- SPEC 12.11(c), bug 2026-11-24 "green filled once then never again": since Anchor drops the reference on every
    -- shot, a CLEAN player (still, never refused) is blind on every shot and never receives a FAILED_QUIET to
    -- re-acquire one. Treating blind as "blocked" therefore starved the cast forever. Blind + still is NOT a wall:
    -- the engine's first attempt is at readyAt, so latch there (or now, if readyAt is already past). If the engine
    -- refuses, FAILED_QUIET acquires the phase and re-latches one period out - the normal correction path.
    if not state.stopWaitTick then
      if snap.gcdBlind then
        state.stopWaitTick = math.max(readyAt, now)
      else
        state.stopWaitTick = now + ((state.retryPhase - now) % period)
      end
    end
    snap.drawBlockFrac = Util.Clamp((state.stopWaitTick - now) / period, 0, 1)
    blocked = now < state.stopWaitTick
  end
  -- Numeric while ready = seconds until the shot can actually go off from THIS instant (owner 2026-11-24):
  --   blocked:  time to the latched tick (or a full block if moving/blind) + the full cast window
  --   casting:  the rest of the cast window
  if blocked then
    snap.blockFrac = snap.drawBlockFrac
    snap.channelState = moving and "blocked_moving" or "blocked_still"
    state.castStartAt = nil
    snap.remaining = snap.drawBlockFrac * period + window
  else
    -- the latched tick has passed and the player is still: the cast is running from that tick
    snap.blockFrac = 0
    snap.channelState = "casting"
    state.castStartAt = state.castStartAt or state.stopWaitTick
    snap.castFrac = Util.Clamp((now - state.castStartAt) / math.max(window, 0.01), 0, 1)
    snap.remaining = math.max(window - (now - state.castStartAt), 0)
  end
  return snap
end

-- Internals -------------------------------------------------------------------------------
local function RefreshBaseSpeed()
  local itemID = Client.RangedWeaponItemID()
  if not itemID then state.baseSpeed = nil return end
  if baseSpeedCache[itemID] then state.baseSpeed = baseSpeedCache[itemID] return end
  tooltip = tooltip or CreateFrame("GameTooltip", "VWST_ScanTip", nil, "GameTooltipTemplate")
  tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
  tooltip:ClearLines()
  tooltip:SetItemByID(itemID)
  local pattern = (SPEED or "Speed") .. "%s*(%d+[%.,]%d+)"
  for i = 1, tooltip:NumLines() do
    local fs = _G["VWST_ScanTipTextRight" .. i]
    local text = fs and fs:GetText()
    local m = text and text:match(pattern)
    if m then
      local v = tonumber((m:gsub(",", ".")))
      if v and v > 0 then baseSpeedCache[itemID] = v; state.baseSpeed = v; return end
    end
  end
  state.baseSpeed = nil
end

local function RefreshSpeed()
  local _, _, ranged = Client.AttackSpeeds()
  if ranged ~= nil or Client.SpeedsReadable() then state.speed = ranged end
end

local function Anchor(speed, reason)
  if speed then state.speed = speed end
  if not state.speed then return end
  local now = GetTime()
  LogShotEvent("ANCHOR %s  speed %.2f  window %.2f  retryPhase %s", reason, state.speed, ShotTracker.CastWindow(),
    state.retryPhase and string.format("%.3f (kept)", state.retryPhase) or "blind")
  state.shotStart = now
  state.shotEnd = now + state.speed
  state.movedInWindow = false
  state.castStartAt = nil
  state.stopWaitTick = nil
  state.firstFailureLogged = false
  -- SPEC 12.11: measured 2026-11-24 - a landed shot DOES re-seed the engine's retry clock (phases agree to ~0.04 s
  -- within a shot, jump 0.11-0.14 s across an anchor). The carried phase is therefore wrong for the new shot; drop it.
  -- The brick is full until this shot's first FAILED_QUIET (<= one period), which is the honest state.
  if reason == "shot" then DropGCDReference("shot landed (re-seeds the retry clock)") end
  if reason == "shot" then
    state.lastShotTime = now
    state.flashUntil = now + SpellData.SHOT_FLASH_SECONDS   -- SPEC 12.6a: the window region flashes on the shot event
  end
  Fire(reason)
end

local sink = {}

function sink:OnSwing(hand, speed)
  if hand ~= "ranged" then return end
  Anchor(speed, "shot")
end

function sink:OnSpellSucceeded(spellID)
  if not spellID then return end
  if Client.flavour == "forever" then return end        -- PLAYER_SWING owns the anchor there
  if Client.IsAutoRepeatSpell(spellID) then
    RefreshSpeed()
    Anchor(nil, "shot")
  end
end

-- UNIT_SPELLCAST_FAILED_QUIET 75: the engine's ~0.5 s Auto Shot retry failed (moving, GCD, range). SPEC 12.4: this
-- NEVER moves shotEnd - the charge clock stays truthful and the fill can never retreat.
-- SPEC 12.9: it is our ONLY source for the engine's retry metronome phase. The first one acquires the reference
-- (retryPhase); each later one re-syncs it AND, when we already held a phase, records how far the real tick was from
-- the one we predicted (gcdDrift). That drift log is how the owner decides TBD-A (does a landed shot re-seed the clock).
function sink:OnSpellFailedQuiet(spellID)
  if not spellID or not Client.IsAutoRepeatSpell(spellID) or not state.isShooting then return end
  local now = GetTime()
  local period = SpellData.AUTO_SHOT_RECAST_DELAY
  -- SPEC 12.11(a): Era delivers FAILED_QUIET 75 twice per failure at the same timestamp (both the unit-event and
  -- the plain registration land). One failure = one tick; the duplicate would record a bogus 0-drift and re-latch.
  if state.lastRetryAt and now - state.lastRetryAt < GCD_DUPLICATE_WINDOW then return end
  -- SPEC 12.11: first failure of this shot - log where the engine's re-seeded clock actually landed, relative to
  -- readyAt, so the re-seed rule can be learned from a few shots' worth of data
  if not state.firstFailureLogged and state.shotEnd then
    state.firstFailureLogged = true
    local readyAt = state.shotEnd - ShotTracker.CastWindow()
    LogShotEvent("FIRST FAILURE this shot: readyAt %+.3fs  shot %+.3fs  (%.3f periods after shot)",
      now - readyAt, now - state.lastShotTime, (now - state.lastShotTime) / period)
  end
  if state.retryPhase then
    -- predicted tick nearest to now, from the carried phase; drift normalised into (-period/2, period/2]
    local drift = (now - state.retryPhase) % period
    if drift > period / 2 then drift = drift - period end
    state.gcdDriftIdx = (state.gcdDriftIdx % GCD_DRIFT_RING) + 1
    state.gcdDrift[state.gcdDriftIdx] = { drift = drift, sinceShot = now - state.lastShotTime }
    if NS.trace then Util.Print("GCD drift %+.3f (%.2fs after shot)", drift, now - state.lastShotTime) end
    -- SPEC 12.9 failure announcements (always on, not only with /vwst trace): these are the facts needed to
    -- understand a wrong prediction after the fact.
    local sinceShot = now - state.lastShotTime
    local sinceLastRetry = state.lastRetryAt and (now - state.lastRetryAt) or nil
    local window = ShotTracker.CastWindow()
    local readyAt = state.shotEnd and (state.shotEnd - window) or nil
    local ctx = string.format("shot +%.2fs | lastRetry %s | readyAt %s | moving %s | GCD %s | speed %.2f win %.2f",
      sinceShot,
      sinceLastRetry and string.format("%+.3fs ago", sinceLastRetry) or "none",
      readyAt and string.format("%+.2fs", readyAt - now) or "?",
      tostring(IsMoving()), tostring(ShotTracker.GCDRemaining()), state.speed or 0, window)
    if math.abs(drift) > GCD_DRIFT_TOLERANCE then
      Util.Print("|cffff4040GCD tick mispredicted|r drift %+.3fs  [%s]", drift, ctx)
      DumpShotEventLog("tick misprediction")
    end
    if state.castStartAt then
      -- we were drawing green ("the cast is running") and the engine says it failed: our casting call was wrong
      Util.Print("|cffff4040GCD cast mispredicted|r showed casting for %.2fs then FAILED_QUIET  [%s]", now - state.castStartAt, ctx)
      DumpShotEventLog("cast misprediction")
    end
  end
  LogShotEvent("FAILED_QUIET 75  phase %.3f  moving %s  GCD %s%s", now % period, tostring(IsMoving()),
    tostring(ShotTracker.GCDRemaining()), state.retryPhase and "" or "  (acquired reference)")
  state.retryPhase = now % period
  state.lastRetryAt = now
  state.castStartAt = nil
  -- SPEC 12.10: the engine just refused; whatever tick we were waiting for is wrong. Re-latch from this failure:
  -- the next attempt is one period from now. (A still player sees the brick refill and drain once more - correct.)
  state.stopWaitTick = now + period
  state.movedInWindow = true
  Fire("movement")
end

-- The player's real GCD remaining (seconds), for the mis-prediction context. Spell 6603/6803 (Attack) is on the GCD
-- category, so its cooldown IS the GCD. nil when unreadable (Forever in combat) or no API.
function ShotTracker.GCDRemaining()
  local id = Client.AttackToggleSpellID()
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(id)
    if info then start, duration = Util.PlainNumber(info.startTime, nil), Util.PlainNumber(info.duration, nil) end
  elseif GetSpellCooldown then
    start, duration = GetSpellCooldown(id)
    start, duration = Util.PlainNumber(start, nil), Util.PlainNumber(duration, nil)
  end
  if not start or not duration or duration == 0 then return 0 end
  return math.max(0, Util.RoundTo(start + duration - GetTime(), 0.001))
end

-- SPEC 12.9: when we lose the metronome reference. NOT on a landed shot (TBD-A: measured by the drift log instead).
-- Assigned (not `local function`) on purpose: that form would declare a NEW local and leave the forward-declared
-- upvalue that Anchor captured permanently nil (the 2026-11-24 "attempt to call a nil value" at Anchor).
DropGCDReference = function(why)
  if NS.trace and state.retryPhase then Util.Print("GCD reference dropped (%s)", why) end
  LogShotEvent("DROP GCD reference: %s%s", why, state.retryPhase and "" or " (was already blind)")
  state.retryPhase, state.lastRetryAt = nil, nil
end

function sink:OnAutoRepeat(isOn)
  state.isShooting = isOn
  LogShotEvent("AUTOREPEAT %s", isOn and "start" or "stop")
  DropGCDReference(isOn and "autorepeat start" or "autorepeat stop")
  if isOn then
    RefreshSpeed(); RefreshBaseSpeed()
    -- NOT activity (see SwingTracker.OnAutoAttack): only a landed shot shows the bar.
    -- the first shot is a full cast window away if nothing is in flight
    if state.speed and (not state.shotEnd or state.shotEnd < GetTime()) then
      local now = GetTime()
      local w = math.max(ShotTracker.CastWindow(), 0.5)
      state.shotStart = now - (state.speed - w)
      state.shotEnd = now + w
    end
  end
  Fire("autorepeat")
end

function sink:OnAttackSpeedChanged()
  if Client.flavour == "forever" then return end
  local _, _, new = Client.AttackSpeeds()
  if not new or not state.speed or new == state.speed then
    if new == nil and Client.SpeedsReadable() then state.speed = nil end
    return
  end
  local now = GetTime()
  if state.shotEnd and state.shotEnd > now then
    local factor = new / state.speed
    local remaining = (state.shotEnd - now) * factor
    local total = (state.shotEnd - state.shotStart) * factor
    state.shotEnd = now + remaining
    state.shotStart = state.shotEnd - total
  end
  state.speed = new
  Fire("haste")
end

function sink:OnWeaponChanged(slot)
  if slot ~= 18 then return end
  DropGCDReference("ranged weapon changed")
  baseSpeedCache = {}
  RefreshSpeed(); RefreshBaseSpeed()
  if state.speed then Anchor(nil, "reset") else state.shotEnd = nil; Fire("reset") end
end

function ShotTracker.Init()
  RefreshSpeed(); RefreshBaseSpeed()
  NS.sinkListeners[#NS.sinkListeners + 1] = sink
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_DEAD")
  f:SetScript("OnEvent", function()
    DropGCDReference("world / death")
    state.shotEnd = nil; state.isShooting = false
    RefreshSpeed(); RefreshBaseSpeed()
    Fire("clear")
  end)
end

function ShotTracker.Status()
  local r = ShotTracker.Cycle()
  local line = string.format("shot: speed %s (base %s) window %.2f | %s | shooting %s | last shot %.1fs ago",
    state.speed and string.format("%.2f", state.speed) or "none", state.baseSpeed and string.format("%.2f", state.baseSpeed) or "?",
    ShotTracker.CastWindow(), r and string.format("remaining %.2f", r) or "idle", tostring(state.isShooting),
    GetTime() - state.lastShotTime)
  -- SPEC 12.9 drift log: read this after ~10 shots to decide TBD-A
  local n, sum, parts = 0, 0, {}
  for i = 1, GCD_DRIFT_RING do
    local idx = ((state.gcdDriftIdx - i) % GCD_DRIFT_RING) + 1
    local d = state.gcdDrift[idx]
    if d then n = n + 1; sum = sum + math.abs(d.drift); parts[#parts + 1] = string.format("%+.3f@%.1fs", d.drift, d.sinceShot) end
  end
  line = line .. string.format("\n  GCD ref %s | drift (newest first, |mean| %s): %s",
    state.retryPhase and string.format("phase %.3f", state.retryPhase) or "BLIND",
    n > 0 and string.format("%.3f", sum / n) or "-", n > 0 and table.concat(parts, "  ") or "none yet")
  return line
end