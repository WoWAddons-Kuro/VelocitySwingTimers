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
  channeling = false,   -- SPEC 12.18: UNIT_SPELLCAST_CHANNEL_START .. _STOP; the shot bar hides while true
  retryPhase = nil,     -- SPEC 12.9: engine retry metronome phase = GetTime() mod AUTO_SHOT_RECAST_DELAY; nil = blind
  lastRetryAt = nil,    -- GetTime() of the last FAILED_QUIET 75
  gcdDrift = {},        -- SPEC 12.9 TBD-A diagnostic ring: { drift = s, sinceShot = s }
  gcdDriftIdx = 0,
  castStartAt = nil,    -- when the current clean cast attempt began (channel "casting")
  flashUntil = nil,     -- SPEC 12.6a: shot-event flash end time
  actionBlocks = {},    -- SPEC 12.14: live/flashing VWST_ActionBlock spans, newest last
  lastMovedAt = nil,    -- GetTime() of the last frame GetUnitSpeed > 0 while ready (SPEC 12.20: "moved recently" explains a refusal)
}
local GCD_DRIFT_RING = 8
local AUTOREPEAT_REASSERT_WINDOW = 0.05  -- s; STOP then START closer than this is the `!Auto Shot` macro re-asserting, not a restart
local GCD_DUPLICATE_WINDOW = 0.005 -- s; two FAILED_QUIET closer than this are the same failure delivered twice
local FIRST_CHECK_HEARTBEAT_WINDOW = 0.3 -- s; a FAILED_QUIET this soon after an anchor / autorepeat start is the engine's first check, not a refusal

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

-- SPEC 12.9/12.11 misprediction announcements are noisy by design; they are gated behind the owner's
-- "Enable Timer Prediction Debug Messages" checkbox (Extras section). Off by default; the logic stays in.
local function DebugTimerPrediction() return NS.DB and NS.DB.Global().debugTimerPrediction == true end

-- SPEC 12.3: is the player moving? Era: GetUnitSpeed readable. Forever: may be secret in combat -> treat as still.
-- Lives UP HERE, above every caller: a `local function` resolves to a GLOBAL (nil) in any closure compiled before its
-- declaration (third time this file was bitten - DropGCDReference, AttachActionBlocks, and now the 12.15 helpers).
local function IsMoving()
  local v = Util.PlainNumber((GetUnitSpeed("player")), nil)
  return v ~= nil and v > 0
end

-- SPEC 12.15 instant-delay measurement (owner 2026-11-24). We do NOT know the mechanism by which an instant pressed
-- late delays the auto (cancel-and-restart vs retry tick) - two anecdotes say "~0.5 s", nothing says why. So measure
-- it: at each shot-blocking instant press, remember how long before the EXPECTED shot it landed; when that shot
-- actually lands, bucket the press position and accumulate (actual - expected). Average delay per bucket is the
-- answer. Persisted in SavedVariables (NS.db.instantStats) so several sessions add up. /vwst instants prints it.
-- A cycle is a clean sample only if exactly ONE instant was pressed in it, the player was still at the press and at
-- the expected shot time, and no real cast ran: anything else is dropped, not averaged in.
-- VWST_InstantDelayBucket = { n = count, sum = total delay s, max = worst delay s }
-- VWST_InstantStats       = { bucketWidth = s, buckets = { [i] = VWST_InstantDelayBucket }, dropped = { reason = n } }
local INSTANT_BUCKET_WIDTH = 0.25    -- s before the expected shot
local INSTANT_BUCKETS = 10           -- 0..2.5 s; index 0 = pressed more than 2.5 s early (overflow)
local pendingInstant = nil           -- VWST_PendingInstantSample for the cycle in flight
-- declared here, ABOVE OnLeaveCombat which clears it: a `local` placed below its first closure is a nil upvalue there
-- (2026-11-24: "bad argument #1 to 'next' (table expected, got nil)" on leaving combat)
local pendingPresses = {}            -- castGUID -> VWST_PendingPress  (SPEC 12.17, defined in that section below)
-- VWST_PendingInstantSample = { pressAt, expectedShotEnd, leadSeconds, spellID, tainted = reason|nil, count }

local function InstantStats()
  local db = NS.db
  if not db then return nil end
  if not db.instantStats or db.instantStats.bucketWidth ~= INSTANT_BUCKET_WIDTH then
    db.instantStats = { bucketWidth = INSTANT_BUCKET_WIDTH, buckets = {}, dropped = {} }
  end
  return db.instantStats
end

local function InstantBucketIndex(leadSeconds)
  if leadSeconds > INSTANT_BUCKET_WIDTH * INSTANT_BUCKETS then return 0 end
  return math.max(1, math.min(INSTANT_BUCKETS, math.ceil(leadSeconds / INSTANT_BUCKET_WIDTH)))
end

local function RecordInstantPress(spellID, now)
  if not state.shotEnd then return end
  if pendingInstant then
    pendingInstant.count = pendingInstant.count + 1
    pendingInstant.tainted = pendingInstant.tainted or "two instants in one cycle"
    return
  end
  -- the owner's `/cast !Auto Shot` macro re-asserts autorepeat in the same frame as the instant, and a re-assert
  -- starts its own 0.5 s retry timer: that cycle cannot tell the instant's cost from the macro's. Keep it out.
  local macro = state.lastReassertAt and (now - state.lastReassertAt) < AUTOREPEAT_REASSERT_WINDOW
  pendingInstant = { pressAt = now, expectedShotEnd = state.shotEnd, leadSeconds = state.shotEnd - now,
                     spellID = spellID, count = 1,
                     tainted = (macro and "macro re-assert at press") or (IsMoving() and "moving at press") or nil }
end

local function TaintPendingInstant(reason)
  if pendingInstant and not pendingInstant.tainted then pendingInstant.tainted = reason end
end

-- called from Anchor("shot"): close the sample for the cycle that just ended
local function CloseInstantSample(shotLandedAt)
  local p = pendingInstant
  pendingInstant = nil
  if not p then return end
  local stats = InstantStats()
  if not stats then return end
  -- a shot that lands EARLIER than expected is a different cycle (re-anchor from autorepeat etc.): drop
  if shotLandedAt < p.expectedShotEnd - 0.05 then p.tainted = p.tainted or "shot earlier than expected" end
  -- a shot that lands more than 1.5 cycles LATE is not this cycle either: the target died / was swapped and the
  -- "next shot" is a different engagement (first dataset 2026-11-24: a 18.8 s "delay" in the 0-0.25 bucket). Owner: 1.5x.
  if state.speed and shotLandedAt > p.expectedShotEnd + state.speed * 1.5 then p.tainted = p.tainted or "stale (next shot was a different engagement)" end
  -- any `!Auto Shot` re-assert during the cycle (not just the press frame) starts the retry timer and smears its
  -- own ~0.3 s across the sample; the first dataset showed cost in 2 s-lead buckets that no instant could cause
  if state.lastReassertAt and state.lastReassertAt > p.pressAt - 0.05 and state.lastReassertAt < shotLandedAt then p.tainted = p.tainted or "macro re-assert in cycle" end
  if IsMoving() then p.tainted = p.tainted or "moving at shot" end
  if p.tainted then
    stats.dropped[p.tainted] = (stats.dropped[p.tainted] or 0) + 1
    LogShotEvent("INSTANT sample dropped: %s", p.tainted)
    return
  end
  local delay = math.max(0, shotLandedAt - p.expectedShotEnd)
  local idx = InstantBucketIndex(p.leadSeconds)
  local b = stats.buckets[idx]
  if not b then b = { n = 0, sum = 0, max = 0 }; stats.buckets[idx] = b end
  b.n = b.n + 1; b.sum = b.sum + delay; if delay > b.max then b.max = delay end
  LogShotEvent("INSTANT sample: lead %.2fs -> delay %.3fs (bucket %d, n=%d)", p.leadSeconds, delay, idx, b.n)
  if DebugTimerPrediction() then
    -- same columns as the press line (SPEC 12.20): "instant N  lead X" then the outcome
    Util.Print("|cff40c0ffinstant|r %d  lead %.2fs  -> auto landed %+.3fs vs expected", p.spellID, p.leadSeconds, shotLandedAt - p.expectedShotEnd)
  end
end

function ShotTracker.ResetInstantStats()
  if NS.db then NS.db.instantStats = nil end
  pendingInstant = nil
end

-- /vwst instants : the histogram. Bucket i covers (i-1)*w .. i*w seconds BEFORE the expected shot at press time.
function ShotTracker.PrintInstantStats()
  local stats = InstantStats()
  if not stats then Util.Print("instant stats: no DB") return end
  local w = stats.bucketWidth
  Util.DumpHeader("/vwst instants - auto-shot delay by instant press position")
  Util.Print("lead = seconds before the EXPECTED shot when the instant was pressed; delay = how late the shot landed")
  local total = 0
  for i = INSTANT_BUCKETS, 0, -1 do
    local b = stats.buckets[i]
    local label = i == 0 and string.format(">%.2fs early", w * INSTANT_BUCKETS)
      or string.format("%.2f-%.2fs", (i - 1) * w, i * w)
    if b and b.n > 0 then
      total = total + b.n
      Util.Print("  lead %-12s  n=%3d  avg delay %.3fs  max %.3fs", label, b.n, b.sum / b.n, b.max)
    else
      Util.Print("  lead %-12s  n=  0", label)
    end
  end
  local dropped = {}
  for reason, n in pairs(stats.dropped) do dropped[#dropped + 1] = string.format("%s x%d", reason, n) end
  table.sort(dropped)
  Util.Print("samples %d | dropped: %s", total, #dropped > 0 and table.concat(dropped, ", ") or "none")
  Util.Print("/vwst instants reset  clears the table")
  Util.DumpFooter("/vwst instants")
end

-- SPEC 12.15/12.17: leaving combat ends every engagement. Any instant sample or press still pending belongs to a
-- fight that is over; the "next shot" after this would be a different fight and must not be matched (owner
-- 2026-11-24). Called from the bootstrap on PLAYER_REGEN_ENABLED.
function ShotTracker.OnLeaveCombat()
  if pendingInstant then
    local stats = InstantStats()
    if stats then stats.dropped["left combat"] = (stats.dropped["left combat"] or 0) + 1 end
    LogShotEvent("INSTANT sample dropped: left combat")
    pendingInstant = nil
  end
  if next(pendingPresses) then
    LogShotEvent("PRESS tracking cleared: left combat")
    wipe(pendingPresses)
  end
end

-- SPEC 12.17 instant PRESS tracking (owner 2026-11-24). UNIT_SPELLCAST_SENT fires at the button press, before any
-- outcome, and its castGUID threads to the outcome event (SUCCEEDED / FAILED / FAILED_QUIET / INTERRUPTED). So for
-- every shot-blocking instant we can record WHERE in the cycle it was pressed and WHAT became of it:
--   resolved         SUCCEEDED arrived; latency = resolve - press  (a queued instant shows up here as long latency)
--   cancelled_moving an outcome of FAILED/INTERRUPTED/FAILED_QUIET while the player was moving at the press or now
--   cancelled_still  same outcomes while still (range, LoS, "another action in progress", ...)
--   lost             no outcome within PRESS_OUTCOME_TIMEOUT - the press was swallowed silently
-- Bucketed by lead (seconds before the expected shot at press), same buckets as 12.15. Persisted: NS.db.pressStats.
-- VWST_PressOutcomeBucket = { resolved = n, latencySum = s, cancelled_moving = n, cancelled_still = n, lost = n }
-- VWST_PendingPress        = { pressAt, lead, spellID, movingAtPress, castGUID }
local PRESS_OUTCOME_TIMEOUT = 2.0

local function PressStats()
  local db = NS.db
  if not db then return nil end
  if not db.pressStats or db.pressStats.bucketWidth ~= INSTANT_BUCKET_WIDTH then
    db.pressStats = { bucketWidth = INSTANT_BUCKET_WIDTH, buckets = {} }
  end
  return db.pressStats
end

local function PressBucket(lead)
  local stats = PressStats()
  if not stats then return nil end
  local idx = InstantBucketIndex(lead)
  local b = stats.buckets[idx]
  if not b then b = { resolved = 0, latencySum = 0, cancelled_moving = 0, cancelled_still = 0, lost = 0 }; stats.buckets[idx] = b end
  return b
end

local function RecordPress(spellID, castGUID, now)
  if not state.shotEnd then return end
  -- Era's press hook (Client_ClassicEra) has no castGUID; key those presses by spellID so an outcome event (which
  -- does carry the GUID on SUCCEEDED, but we match it by spell) can still find them. SENT-origin presses keep the GUID.
  castGUID = castGUID or ("press:" .. tostring(spellID) .. ":" .. string.format("%.3f", now))
  pendingPresses[castGUID] = { pressAt = now, lead = state.shotEnd - now, spellID = spellID, movingAtPress = IsMoving(), castGUID = castGUID }
  LogShotEvent("PRESS %d  lead %.2fs  moving %s", spellID, state.shotEnd - now, tostring(IsMoving()))
  if DebugTimerPrediction() then Util.Print("|cff40c0ffinstant PRESSED|r %d  lead %.2fs%s", spellID, state.shotEnd - now, IsMoving() and "  (moving)" or "") end
  -- a press with NO outcome event is the case the owner is chasing (a queued instant the client threw away leaves
  -- no FAILED/INTERRUPTED). Announce it on a timer, not lazily on the next press, so it is seen when it happens.
  C_Timer.After(PRESS_OUTCOME_TIMEOUT, function()
    local p = pendingPresses[castGUID]
    if not p then return end
    pendingPresses[castGUID] = nil
    local b = PressBucket(p.lead)
    if b then b.lost = b.lost + 1 end
    LogShotEvent("PRESS %d LOST - no outcome event in %.1fs  (lead %.2fs, moving at press %s)", p.spellID, PRESS_OUTCOME_TIMEOUT, p.lead, tostring(p.movingAtPress))
    if DebugTimerPrediction() then
      Util.Print("|cffff4040instant CANCELLED (silent)|r %d pressed %.2fs before the shot - no success, no failure event in %.1fs%s",
        p.spellID, p.lead, PRESS_OUTCOME_TIMEOUT, p.movingAtPress and "  (you were moving at the press)" or "")
    end
  end)
end

-- outcome = "resolved" | "failed" | "interrupted" | "failed_quiet"
local function ResolvePress(castGUID, outcome, now, spellID)
  local p = castGUID and pendingPresses[castGUID]
  if not p and spellID then
    -- hook-origin press: the most recent unresolved press of this spell
    local bestKey, bestT
    for key, q in pairs(pendingPresses) do
      if q.spellID == spellID and (not bestT or q.pressAt > bestT) then bestKey, bestT = key, q.pressAt end
    end
    if bestKey then castGUID, p = bestKey, pendingPresses[bestKey] end
  end
  if not p then return end
  pendingPresses[castGUID] = nil
  local b = PressBucket(p.lead)
  if not b then return end
  if outcome == "resolved" then
    local latency = now - p.pressAt
    b.resolved = b.resolved + 1; b.latencySum = b.latencySum + latency
    LogShotEvent("PRESS %d resolved  %.3fs after press  (lead %.2fs)", p.spellID, latency, p.lead)
    if DebugTimerPrediction() then Util.Print("|cff40c0ffpress|r %d resolved %.3fs after press (lead %.2fs)", p.spellID, latency, p.lead) end
  else
    local moving = p.movingAtPress or IsMoving()
    if moving then b.cancelled_moving = b.cancelled_moving + 1 else b.cancelled_still = b.cancelled_still + 1 end
    LogShotEvent("PRESS %d %s %s  %.3fs after press  (lead %.2fs)", p.spellID, outcome, moving and "MOVING" or "still", now - p.pressAt, p.lead)
    if DebugTimerPrediction() then Util.Print("|cffff4040instant CANCELLED|r %d  %s %.3fs after the press  (lead %.2fs, %s)", p.spellID, outcome, now - p.pressAt, p.lead, moving and "MOVING" or "still") end
  end
end

function ShotTracker.ResetPressStats()
  if NS.db then NS.db.pressStats = nil end
  wipe(pendingPresses)
end

-- /vwst presses : what became of each instant press, by where in the cycle it was pressed
function ShotTracker.PrintPressStats()
  local stats = PressStats()
  if not stats then Util.Print("press stats: no DB") return end
  local w = stats.bucketWidth
  Util.DumpHeader("/vwst presses - instant press outcomes by press position")
  Util.Print("lead = seconds before the EXPECTED shot when pressed | ok = resolved (avg press->resolve) | cancelled while moving / still | lost = no outcome")
  local tot = { resolved = 0, cancelled_moving = 0, cancelled_still = 0, lost = 0 }
  for i = INSTANT_BUCKETS, 0, -1 do
    local b = stats.buckets[i]
    local label = i == 0 and string.format(">%.2fs early", w * INSTANT_BUCKETS) or string.format("%.2f-%.2fs", (i - 1) * w, i * w)
    if b then
      for k in pairs(tot) do tot[k] = tot[k] + (b[k] or 0) end
      Util.Print("  lead %-12s  ok %3d (%.3fs)  cancel moving %3d  still %3d  lost %3d", label,
        b.resolved, b.resolved > 0 and b.latencySum / b.resolved or 0, b.cancelled_moving, b.cancelled_still, b.lost)
    else
      Util.Print("  lead %-12s  -", label)
    end
  end
  Util.Print("totals: ok %d | cancelled moving %d | cancelled still %d | lost %d   (/vwst presses reset clears)",
    tot.resolved, tot.cancelled_moving, tot.cancelled_still, tot.lost)
  Util.DumpFooter("/vwst presses")
end
local listeners = {}
local tooltip
local baseSpeedCache = {}   -- itemID -> base speed
local DropGCDReference      -- defined below Anchor, which calls it: forward-declare so the upvalue binds
local AttachActionBlocks    -- defined below Snapshot, which calls it: same forward-declare pattern
local NoteActionBlock             -- SPEC 12.20: stamps a block's free/invading/blocked verdict; defined with AttachActionBlocks
local ActionBlockInvadingWindow   -- SPEC 12.20: the live block reaching into the window, if any; same place
local NoteCycleBlock, NoteCycleMovement, NoteCycleRefusal, JudgeCycleOutcome, BeginCycleOutcome   -- SPEC 12.21 judge; defined above Anchor

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

-- SPEC 12.9: remaining fraction of the current retry block, from the carried metronome phase. 0 when blind.
-- The metronome free-runs: next tick = smallest t > now with t = retryPhase (mod period).
local function BlockFrac(now)
  if not state.retryPhase then return 0 end
  local period = SpellData.AUTO_SHOT_RECAST_DELAY
  local untilTick = (state.retryPhase - now) % period
  return untilTick / period
end

function ShotTracker.HasGCDReference() return state.retryPhase ~= nil end

-- SPEC 15 shot history ring (owner 2026-11-26): an oscilloscope under the bar. The trace is FIXED in x; only the
-- write head (the spark) moves, left -> right, wrapping. Behind the head each column records what the auto was
-- doing at that moment; ahead of the head is the previous lap until overwritten. One glance = how much red is on
-- the ring = how much Auto Shot time was lost over the last `periods` cycles.
-- VWST_ShotHistoryColumnState = 0 (nothing: not shooting, or late beyond the travel cap) | 1 (occupied) | 2 (lost)
-- VWST_ShotHistoryRing = { columns = { [1..HISTORY_COLUMNS] = state }, head = column index of `now`,
--                          lapStart = GetTime() at column 1 of the current lap, span = seconds across the ring }
local HISTORY_COLUMNS = 240
local HISTORY_PERIODS_MIN, HISTORY_PERIODS_MAX, HISTORY_PERIODS_DEFAULT = 3, 10, 6
local HISTORY_LOST_CAP_SECONDS = 1.5      -- same cut as DELAY_REPORT_MAX_SECONDS: later than this is travel, not loss
local history = { columns = {}, head = 1, lapStart = nil, span = nil, periods = HISTORY_PERIODS_DEFAULT, dirty = true }
for i = 1, HISTORY_COLUMNS do history.columns[i] = 0 end
ShotTracker.HISTORY_COLUMNS = HISTORY_COLUMNS
ShotTracker.HISTORY_PERIODS_MIN, ShotTracker.HISTORY_PERIODS_MAX = HISTORY_PERIODS_MIN, HISTORY_PERIODS_MAX

function ShotTracker.ClearHistory()
  for i = 1, HISTORY_COLUMNS do history.columns[i] = 0 end
  history.head, history.lapStart, history.span = 1, nil, nil
  history.dirty = true
end

-- periods: 3..10 cycles across the ring (from settings; the controller passes it each frame)
function ShotTracker.SetHistoryPeriods(periods)
  periods = math.max(HISTORY_PERIODS_MIN, math.min(HISTORY_PERIODS_MAX, tonumber(periods) or HISTORY_PERIODS_DEFAULT))
  if periods ~= history.periods then history.periods = periods; history.span = nil end   -- re-span from the head
end

-- SPEC 15.6 (owner 2026-11-26, after seeing it live: "a little busy"): the normal cycle draws NOTHING. The ring only
-- carries the exceptions. Column states:
--   0 nothing       the auto was cycling normally (or we had no cycle)
--   2 lost (red)    the auto was late, up to the travel cap
--   3 out (grey)    a hostile target exists but Auto Shot is not in range and we are not in melee: deadzone or too
--                   far - the two read identically in combat (SpellData notes), so one colour
--   4 melee (white) the target is in melee range (Raptor Strike probe true) - the deadzone is about to begin
-- Range is sampled per tick from the same probes RangeCue uses; nil (secret / no target) draws nothing.
-- VWST_ShotHistoryColumnState = 0 | 2 | 3 | 4
local function HistoryRangeState()
  if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDeadOrGhost("target") then return nil end
  local inRange = Client.IsSpellInRangeOfTarget(SpellData.AUTO_SHOT)
  if inRange == nil then return nil end
  if inRange then return 0 end
  local meleeSpell = SpellData.RANGE_MELEE_SPELL[Client.PlayerClass() or ""]
  if meleeSpell and Client.IsSpellInRangeOfTarget(meleeSpell) == true then return 4 end
  return 3
end

local function HistoryStateAt(now)
  -- a late auto is the first thing to show, whatever the range says (movement is the usual cause)
  if state.isShooting and state.shotEnd and now > state.shotEnd and now - state.shotEnd <= HISTORY_LOST_CAP_SECONDS then
    -- ...unless the lateness IS the range: out / melee explain it better than red
    local r = HistoryRangeState()
    if r == 3 or r == 4 then return r end
    return 2
  end
  -- SPEC 15.7: normal cycling writes 1 (medium grey, fading); not shooting / no cycle writes nothing
  local r = HistoryRangeState()
  if r and r ~= 0 then return r end
  return (state.isShooting and state.shotEnd) and 1 or 0
end

-- Called from Snapshot every frame (and from the controller when there is no cycle, so the head keeps moving).
-- Advances the head to the column for `now`, writing every column crossed since the last tick.
function ShotTracker.HistoryTick(now)
  if not state.speed or state.speed <= 0 then return end
  local span = state.speed * history.periods
  if not history.span or not history.lapStart then
    -- (re)seed: keep the current head where it is, re-derive lapStart so that column `head` == now
    history.span = span
    history.lapStart = now - (history.head - 1) / HISTORY_COLUMNS * span
  elseif math.abs(span - history.span) > 0.001 then
    history.span = span
    history.lapStart = now - (history.head - 1) / HISTORY_COLUMNS * span
  end
  local colOf = math.floor((now - history.lapStart) / span * HISTORY_COLUMNS) + 1
  if colOf <= history.head then return end        -- same column as last tick: nothing to write yet
  local s = HistoryStateAt(now)
  -- write every column between the old head (exclusive) and the new one (inclusive), wrapping
  local steps = math.min(colOf - history.head, HISTORY_COLUMNS)
  for _ = 1, steps do
    history.head = history.head + 1
    if history.head > HISTORY_COLUMNS then history.head = 1; history.lapStart = history.lapStart + span end
    history.columns[history.head] = s
  end
  history.dirty = true
end

-- The view's input. VWST_ShotHistorySnapshot = { columns (shared table, read-only), head, headFrac, count, dirty }
-- headFrac = exact 0..1 position of `now` across the span, so the spark glides instead of hopping a column at a time
-- `dirty` is cleared by the caller that painted it (the view) via AcknowledgeHistory, so unchanged frames cost nothing.
function ShotTracker.History(now)
  local frac = (history.span and history.lapStart) and (((now or GetTime()) - history.lapStart) / history.span) % 1 or (history.head - 1) / HISTORY_COLUMNS
  return { columns = history.columns, head = history.head, headFrac = frac, count = HISTORY_COLUMNS, periods = history.periods, dirty = history.dirty }
end
function ShotTracker.AcknowledgeHistory() history.dirty = false end

-- Edit Mode / options preview: a canned ring - mostly nothing (normal cycling), one red stretch (late), one grey
-- stretch (out of range), one white tick (melee), head at 60 %
function ShotTracker.SampleHistory()
  local cols = {}
  for i = 1, HISTORY_COLUMNS do
    local f = i / HISTORY_COLUMNS
    cols[i] = (f > 0.30 and f < 0.36) and 2 or ((f > 0.72 and f < 0.80) and 3 or ((f > 0.80 and f < 0.82) and 4 or 0))
  end
  return { columns = cols, head = math.floor(HISTORY_COLUMNS * 0.6), count = HISTORY_COLUMNS, dirty = true }
end

-- SPEC 12.3 / 12.5. One frame of the channel model, pure from state + now. nil when no cycle is in flight.
-- VWST_ShotSnapshot = { phase = VWST_ShotPhase, charge = 0..1, channelState = VWST_ShotChannelState,
--                       blockFrac = 0..1, castFrac = 0..1, flashFrac = 0..1, remaining = seconds, cycle, window }
function ShotTracker.Snapshot(now)
  if not state.shotEnd or not state.speed then return nil end
  now = now or GetTime()
  ShotTracker.HistoryTick(now)   -- SPEC 15: advance the history write head every rendered frame
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
    if snap.moving then state.lastMovedAt = now end   -- SPEC 12.20: a step just before readyAt explains a refusal just after it
    -- SPEC 12.10: while charging the brick is full only while moving. SPEC 12.18: ...or channeling - a Tame Beast
    -- started mid-charge took THIS early return and never saw the channeling guard below (owner: "cycles ~4 times").
    snap.drawBlockFrac = (snap.moving or state.channeling) and 1 or 0
    AttachActionBlocks(snap, now, readyAt)
    snap.history = ShotTracker.History(now)   -- SPEC 15
    return snap
  end
  snap.phase = "ready"
  local moving = snap.moving
  snap.gcdBlind = state.retryPhase == nil
  -- SPEC 12.20: the "GCD tick missed" check that used to live here is gone. It predicted retry ticks from the
  -- carried phase, and SPEC 12.13 established the engine's retry interval is not predictable (0.37..1.25 s). The
  -- model's only expectation is now checked in OnSpellFailedQuiet ("unexplained refusal").
  -- SPEC 12.13 (owner 2026-11-24, after three sessions of dumps). We have NO positive signal that a cast has begun:
  -- the engine's retry interval is not a clock (0.37..1.19 s observed), the first retry after a shot has no fixed
  -- offset, and the engine refuses even when GetUnitSpeed says still. Every pre-shot "casting" we drew was a guess,
  -- and the dumps showed it wrong often. So the ready-phase model is now only what we KNOW:
  --   moving                      -> brick full (you are the wall)
  --   FAILED_QUIET (refusal)      -> brick fills and drains ONCE over one typical period: "it will try again soon"
  --   otherwise                   -> brick empty; nothing claimed about a cast
  --   SUCCEEDED 75                -> flash (the only moment we know it fired)
  -- There is no "casting" state in the live snapshot any more. The green cast-fill remains in the views for the
  -- scripted preview only (ScriptedSnapshot), so the colour vocabulary is still demonstrated.
  local period = SpellData.AUTO_SHOT_RECAST_DELAY
  if state.channeling then
    -- SPEC 12.18 (owner): during a channel the auto cannot fire for the whole duration. The retry heartbeat and
    -- refusals keep arriving, but drawing them as a draining box reads as "it will try again soon" - a lie. Hold the
    -- brick solid red for the channel; ShotGroup fades the bar out fast while this is set.
    snap.drawBlockFrac = 1
    snap.channelState = "blocked_still"
  elseif moving then
    state.lastMovedAt = now
    NoteCycleMovement(now)   -- SPEC 12.21: movement in the window is the first thing the outcome judge checks
    snap.drawBlockFrac = 1
    snap.channelState = "blocked_moving"
  elseif state.lastRetryAt and now - state.lastRetryAt < period then
    -- a refusal within the last period: the engine said no and will try again; show the one-shot drain
    snap.drawBlockFrac = 1 - (now - state.lastRetryAt) / period
    snap.channelState = "blocked_still"
  else
    snap.drawBlockFrac = 0
    snap.channelState = "blocked_still"    -- "ready, still, nothing claimed" - the brick is simply empty
  end
  snap.blockFrac = snap.drawBlockFrac
  state.castStartAt = nil
  -- Numeric while ready: the only honest number is the window (the cast the engine will run when it gets to it),
  -- plus whatever drain is showing. Moving: period + window.
  snap.remaining = snap.drawBlockFrac * period + window
  AttachActionBlocks(snap, now, readyAt)
  snap.history = ShotTracker.History(now)   -- SPEC 15
  return snap
end

-- SPEC 12.14 action blocks. Every block is a time span [startAt, endAt] in GetTime() seconds; the snapshot maps it
-- onto the bar's timeline (x = 0 at shotStart, x = 1 at shotEnd; fractions may EXCEED 1 - overruns are drawn outside
-- the bar, owner: "brutal honesty"). The white fill follows the same timeline out to the end of the latest live block.
-- A block flashes for SHOT_FLASH_SECONDS after it ends, then is removed; a landed shot clears them all.
-- SPEC 12.20 (owner 2026-11-25): a block is coloured by whether it INVADES the window (the last `window` seconds
-- before shotEnd, where the engine needs the player still and un-busy). readyAt is the window start.
-- VWST_ActionBlockVerdict = "free" (ends before readyAt) | "invading" (crosses readyAt) | "blocked" (starts inside)
-- SPEC 12.22 (owner 2026-11-26, two in-game surprises): an INSTANT never delays the auto. The auto fires on time and
-- the instant is queued behind it (press inside the window -> instant resolves at the start of the next cycle; move
-- while queued -> the instant is cancelled and no block ever appears). So instants are ALWAYS "free": drawn green
-- in every position, never counted as red by the outcome judge. The only blocks that hold the auto are real CASTS
-- (Aimed, Multi) and the `!Auto Shot` re-assert, which keep the three-way rule. If an instant ever does delay the
-- auto, the judge sees a delay with nothing drawn and prints SURPRISE - that is the expectation, stated once.
-- VWST_ActionBlock      = { kind = "instant"|"cast"|"reassert", spellID, startAt, endAt, tailEndAt?, verdict }
-- VWST_ActionBlockDraw  = { xStart, xEnd, xReady (fractions of bar width, may be > 1), spellID, kind, flashFrac,
--                           live, verdict }   -- views paint [xStart, xReady) in the free/invading colour and
--                                             -- [max(xStart, xReady), xEnd) in the blocked colour
--                                             -- (a "free" verdict paints the whole span green; xReady is ignored)
local function ActionBlockHoldsAuto(block) return block.kind ~= "instant" end
local function ActionBlockVerdict(block)
  if not state.shotEnd then return "free" end
  if not ActionBlockHoldsAuto(block) then return "free" end
  local readyAt = state.shotEnd - ShotTracker.CastWindow()
  if block.endAt <= readyAt then return "free" end
  if block.startAt >= readyAt then return "blocked" end
  return "invading"
end

-- Called where a block is created: stamps the verdict and returns it for the log line.
-- Assigned (not `local function`): callers above this point captured the forward-declared upvalue.
NoteActionBlock = function(block, now)
  block.verdict = ActionBlockVerdict(block)
  if NoteCycleBlock then NoteCycleBlock(block) end   -- SPEC 12.21: the outcome judge wants the deepest invader
  return block.verdict
end

-- The live auto-holding block (if any) whose span reaches into the window at `now`: the "red on the bar" that
-- explains a refusal. Instants are never red (SPEC 12.22).
ActionBlockInvadingWindow = function(now)
  if not state.shotEnd then return nil end
  local readyAt = state.shotEnd - ShotTracker.CastWindow()
  for i = #state.actionBlocks, 1, -1 do
    local b = state.actionBlocks[i]
    local reach = b.tailEndAt or b.endAt
    if ActionBlockHoldsAuto(b) and now < reach and reach > readyAt then return b end
  end
  return nil
end

-- Assigned, not `local function`: Snapshot above captured the forward-declared upvalue (see DropGCDReference).
AttachActionBlocks = function(snap, now, readyAt)
  local blocks = state.actionBlocks
  if #blocks == 0 then snap.actionBlocks, snap.fillFrac = nil, nil return end
  local cycle = state.speed
  local t0 = state.shotStart
  local out, latestEnd = {}, state.shotEnd
  for i = #blocks, 1, -1 do
    local b = blocks[i]
    if now > b.endAt + SpellData.SHOT_FLASH_SECONDS then
      table.remove(blocks, i)
    else
      local live = now < b.endAt
      out[#out + 1] = {
        xStart = (b.startAt - t0) / cycle, xEnd = (b.endAt - t0) / cycle,
        xReady = (readyAt - t0) / cycle, verdict = b.verdict or ActionBlockVerdict(b),
        -- cast blocks carry the 0.5 s retry tail the engine may add after the cast (drawn fainter by the views)
        xTailEnd = b.tailEndAt and (b.tailEndAt - t0) / cycle or nil,
        spellID = b.spellID, kind = b.kind, live = live,
        flashFrac = live and 0 or Util.Clamp(1 - (now - b.endAt) / SpellData.SHOT_FLASH_SECONDS, 0, 1),
      }
      -- The white chases a block that extends PAST shotEnd ("you pushed your auto"). A block that STARTED after
      -- shotEnd is not that: the auto is already overdue (melee deadzone, fleeing target, no range refusal event)
      -- and the press is just happening late. Letting it extend the chase ran the white to 2x the bar width
      -- (owner 2026-11-26) - the mirrored X() scale past readyAt is brickW/2 per window-fraction, very steep.
      local reach = b.tailEndAt or b.endAt
      if live and b.startAt <= state.shotEnd and reach > latestEnd then latestEnd = reach end
    end
  end
  if #out == 0 then snap.actionBlocks, snap.fillFrac = nil, nil return end
  snap.actionBlocks = out
  -- the white chases the furthest live block end along the same timeline; > 1 means past the bar's right edge
  snap.fillFrac = Util.Clamp((now - t0) / cycle, 0, math.max(1, (latestEnd - t0) / cycle))
  -- SPEC 12.14 decided: while a block is live the brick's refusal drain is suppressed (the block IS the reason);
  -- moving = solid red still applies
  if snap.phase == "ready" and not snap.moving and snap.channelState == "blocked_still" and latestEnd > now then
    snap.drawBlockFrac, snap.blockFrac = 0, 0
  end
end

function ShotTracker.HasLiveActionBlock(now)
  now = now or GetTime()
  for _, b in ipairs(state.actionBlocks) do if now < b.endAt then return true end end
  return false
end

-- SPEC 13.5: the model supplies the sample snapshots too, so no view or controller invents one.
-- Edit Mode: a frozen 60 % charge on the player's real cycle (or 2.5 s), no window.
function ShotTracker.SampleSnapshot()
  local cycle = state.speed or 2.5
  return { phase = "charging", channelState = "idle", charge = 0.6, blockFrac = 0, drawBlockFrac = 0, castFrac = 0,
           flashFrac = 0, remaining = cycle * 0.4, cycle = cycle, window = 0, moving = false, gcdBlind = true,
           history = ShotTracker.SampleHistory() }   -- SPEC 15: Edit Mode shows the canned ring
end

-- Options preview: one CLEAN cycle in the LIVE model's state names (SPEC 12.13 / 12.20 / 12.21), so it never shows
-- anything the real bar does not. Owner 2026-11-26: no stall choreography (the moving-full / drain states only
-- happen when the player causes them) and no "casting" fill (we have no cast signal).
--   t in [0, cycle):  white charges over (cycle - window) and parks at the brick; the brick stays EMPTY through the
--   window (ready, still, nothing claimed); the shot lands at t = cycle and the brick FLASHES (flash spills into the
--   start of the next loop). One Arcane Shot at 35 % charge: its block ends before readyAt = all green.
-- VWST_ScriptedShotParams = { cycle, window }   (the stall argument is accepted and ignored for call-site compat)
function ShotTracker.ScriptedSnapshot(t, cycle, window, stall)
  local chargeLen = cycle - window
  local snap = { cycle = cycle, window = window, blockFrac = 0, drawBlockFrac = 0, castFrac = 0, flashFrac = 0,
                 moving = false, gcdBlind = false }
  -- the shot landed at the END of the previous loop: flash fades over the first SHOT_FLASH_SECONDS of this one
  if t < SpellData.SHOT_FLASH_SECONDS then snap.flashFrac = 1 - t / SpellData.SHOT_FLASH_SECONDS end
  if t < chargeLen then
    snap.phase, snap.channelState = "charging", "idle"
    snap.charge, snap.remaining = t / chargeLen, cycle - t
  else
    -- ready, still, no refusal: white parked at the brick, brick empty, nothing claimed until the shot lands
    snap.phase, snap.charge, snap.channelState = "ready", 1, "blocked_still"
    snap.remaining = window
  end
  -- SPEC 12.20 preview (owner 2026-11-26: keep it green until the invasion threshold is understood): one Arcane
  -- Shot at 35 % charge; its 0.5 s block ends well before readyAt, so it draws all green and flashes when it ends.
  local cost = SpellData.AUTO_SHOT_RECAST_DELAY
  local pressAt = chargeLen * 0.35
  if t >= pressAt and t < pressAt + cost + SpellData.SHOT_FLASH_SECONDS then
    local live = t < pressAt + cost
    snap.actionBlocks = { {
      xStart = pressAt / cycle, xEnd = (pressAt + cost) / cycle, xReady = chargeLen / cycle, verdict = "free",
      spellID = 3044, kind = "instant", live = live,
      flashFrac = live and 0 or Util.Clamp(1 - (t - pressAt - cost) / SpellData.SHOT_FLASH_SECONDS, 0, 1),
    } }
    snap.fillFrac = Util.Clamp(t / cycle, 0, math.max(1, (pressAt + cost) / cycle))
  end
  snap.history = ShotTracker.SampleHistory()   -- SPEC 15: the preview shows a canned ring
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

-- SPEC 12.21 cycle outcome judge (owner 2026-11-26). ONE debug line per Auto Shot cycle, verdict first:
--   auto-shot clean    - expected | SURPRISE - the shot landed on time. Surprise = we drew red (moved in the window,
--                                                or a block reached into it) and it cost nothing: we over-claimed.
--   auto-shot delayed  - expected | SURPRISE - landed late. Expected = something red explains it (moving wins; else
--                                                the block that reached furthest into the window). Surprise = nothing
--                                                drawn: a stall cause we are missing.
--   auto-shot blocked  - expected | SURPRISE - never landed (a full cycle overdue, or autorepeat stopped). Same rule.
-- Threshold for "red counts" is ZERO (owner): a 0.03 s invasion that cost nothing IS the data that finds the real one.
-- Movement in the window is checked first so a moving player's delay never blames the instant.
-- VWST_CycleOutcome = { expectedShotEnd, readyAt, movedInWindowAt = t|nil, refusals = n, lastRefusalAt = t|nil,
--                       deepestBlock = { spellID, pastReady } | nil, judged = bool, overdueTimer }
local CLEAN_TOLERANCE = 0.1          -- s; landing within this of expected is "clean"
local DELAY_REPORT_MAX_SECONDS = 1.5 -- s; SPEC 12.23: the delay breakdown line only for delays up to this (longer = the player was running, not losing DPS)
local cycleOutcome = nil
-- The five judge functions are forward-declared with the other upvalues near Fire(); they MUST be assigned here, not
-- re-declared `local` (that bound the definitions to fresh locals and left Snapshot's captured upvalue nil - 2026-11-26).

BeginCycleOutcome = function(now)
  if cycleOutcome and cycleOutcome.overdueTimer then cycleOutcome.overdueTimer:Cancel() end
  local window = ShotTracker.CastWindow()
  local o = { expectedShotEnd = state.shotEnd, readyAt = state.shotEnd - window, refusals = 0, judged = false }
  cycleOutcome = o
  -- never-landed case: one full cycle past the expected shot with no anchor = blocked
  if state.speed then
    o.overdueTimer = C_Timer.NewTimer(state.speed + (state.shotEnd - now), function()
      if cycleOutcome == o and not o.judged then JudgeCycleOutcome("overdue", GetTime()) end
    end)
  end
end

NoteCycleMovement = function(now)
  local o = cycleOutcome
  if not o or now < o.readyAt then return end
  if not o.movedInWindowAt then o.movedInWindowAt = now end
  o.lastMovedInWindowAt = now   -- SPEC 12.23: the delay line splits "moving" from "retry wait after you stopped"
end

NoteCycleRefusal = function(now)
  local o = cycleOutcome
  if o then o.refusals = o.refusals + 1; o.lastRefusalAt = now end
end

NoteCycleBlock = function(block)
  local o = cycleOutcome
  if not o then return end
  if block.kind == "instant" then return end   -- SPEC 12.22: an instant is never "red"; if it delays the auto that is a SURPRISE
  local reach = (block.tailEndAt or block.endAt) - o.readyAt
  if reach > 0 and (not o.deepestBlock or reach > o.deepestBlock.pastReady) then
    o.deepestBlock = { spellID = block.spellID, pastReady = reach, kind = block.kind }
  end
end

-- how = "landed" (Anchor shot) | "overdue" (timer) | "stopped" (autorepeat stop / left combat)
JudgeCycleOutcome = function(how, now)
  local o = cycleOutcome
  if not o or o.judged then return end
  o.judged = true
  if o.overdueTimer then o.overdueTimer:Cancel() end
  if not state.isShooting and how ~= "landed" then return end   -- not shooting: nothing was expected of the auto
  local late = now - o.expectedShotEnd
  local verdict
  if how ~= "landed" then verdict = "blocked"
  elseif late <= CLEAN_TOLERANCE then verdict = "clean"
  else verdict = "delayed" end
  -- what was red in the window, in priority order
  local cause
  if o.movedInWindowAt then
    cause = string.format("moving in window (%.2fs after readyAt)", o.movedInWindowAt - o.readyAt)
  elseif o.deepestBlock then
    cause = string.format("%s %d reached %.2fs into window", o.deepestBlock.kind, o.deepestBlock.spellID, o.deepestBlock.pastReady)
  elseif state.channeling then
    cause = "channeling"
  end
  local drewRed = cause ~= nil
  local expected = (verdict == "clean") == (not drewRed)
  local refusals = o.refusals > 0
    and string.format("refusals %d (last %.2fs before %s)", o.refusals, now - (o.lastRefusalAt or now), how)
    or "refusals 0"
  local timing = verdict == "clean" and string.format("landed %+.3fs", late)
    or verdict == "delayed" and string.format("late %+.3fs", late)
    or string.format("overdue %+.2fs, %s", late, how)
  LogShotEvent("OUTCOME %s %s  %s  %s  %s", verdict, expected and "expected" or "SURPRISE", timing, cause or "nothing drawn", refusals)
  if not DebugTimerPrediction() then return end
  local tag = expected and "|cff40c0ffexpected|r" or "|cffff4040SURPRISE|r"
  local vcol = verdict == "clean" and "|cff40ff40" or (verdict == "delayed" and "|cffffc040" or "|cffff4040")
  Util.Print("%sauto-shot %s|r - %s - %s - %s - %s", vcol, verdict, tag, timing, cause or "nothing drawn", refusals)
  if not expected then DumpShotEventLog("auto-shot " .. verdict .. " surprise") end
  -- SPEC 12.23 (owner 2026-11-26): the player-facing delay breakdown. How much of the delay was the cause itself
  -- and how much was the engine's retry wait after the cause ended. Only for a SHORT delay: a player who moved for
  -- four seconds was running, not losing DPS, and does not need a line about it.
  if verdict == "delayed" and late <= DELAY_REPORT_MAX_SECONDS then
    local parts = {}
    if o.movedInWindowAt then
      local movingFor = (o.lastMovedInWindowAt or o.movedInWindowAt) - o.movedInWindowAt
      local stoppedBefore = now - (o.lastMovedInWindowAt or o.movedInWindowAt)
      parts[#parts + 1] = string.format("moving %.2fs in window, stopped %.2fs before shot", movingFor, stoppedBefore)
      parts[#parts + 1] = string.format("retry wait %.2fs", math.max(0, stoppedBefore))
    elseif o.deepestBlock then
      -- the block reached pastReady into the window; the auto could fire from (readyAt + pastReady); the rest is retry wait
      local blockEndedBefore = now - (o.readyAt + o.deepestBlock.pastReady)
      parts[#parts + 1] = string.format("%s %d held the auto %.2fs into window", o.deepestBlock.kind, o.deepestBlock.spellID, o.deepestBlock.pastReady)
      parts[#parts + 1] = string.format("retry wait %.2fs", math.max(0, blockEndedBefore))
    elseif state.channeling then
      parts[#parts + 1] = "channeling"
    else
      parts[#parts + 1] = "cause not drawn (range / facing / server lag?)"
    end
    parts[#parts + 1] = o.refusals > 0
      and string.format("%d refusal%s, last %.2fs before shot", o.refusals, o.refusals == 1 and "" or "s", now - (o.lastRefusalAt or now))
      or "0 refusals"
    Util.Print("|cff60a0ffauto-shot delay|r %+.2fs - %s", late, table.concat(parts, " - "))
  end
end

function ShotTracker.AbandonCycle(why)
  if cycleOutcome and not cycleOutcome.judged then JudgeCycleOutcome("stopped", GetTime()) end
  if cycleOutcome and cycleOutcome.overdueTimer then cycleOutcome.overdueTimer:Cancel() end
  cycleOutcome = nil
end

local function Anchor(speed, reason)
  if speed then state.speed = speed end
  if not state.speed then return end
  local now = GetTime()
  LogShotEvent("ANCHOR %s  speed %.2f  window %.2f  retryPhase %s", reason, state.speed, ShotTracker.CastWindow(),
    state.retryPhase and string.format("%.3f (dropped below if this is a shot)", state.retryPhase) or "blind")
  -- SPEC 12.21: judge the cycle that just ended BEFORE shotStart/shotEnd move (needs the old expected time)
  if reason == "shot" then JudgeCycleOutcome("landed", now) end
  state.shotStart = now
  state.shotEnd = now + state.speed
  state.movedInWindow = false
  state.castStartAt = nil
  state.stopWaitTick = nil
  state.firstFailureLogged = false
  BeginCycleOutcome(now)
  -- SPEC 12.14: the auto actually fired - every action block is now history
  if reason == "shot" then wipe(state.actionBlocks) end
  -- SPEC 12.11: measured 2026-11-24 - a landed shot DOES re-seed the engine's retry clock (phases agree to ~0.04 s
  -- within a shot, jump 0.11-0.14 s across an anchor). The carried phase is therefore wrong for the new shot; drop it.
  -- The brick is full until this shot's first FAILED_QUIET (<= one period), which is the honest state.
  if reason == "shot" then DropGCDReference("shot landed (re-seeds the retry clock)") end
  if reason == "shot" then
    CloseInstantSample(now)   -- SPEC 12.15: the sample for the cycle that just ended, before shotStart moves
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

-- SPEC 12.17: the press. Fires before any outcome; the GUID lets us find out what became of it.

-- SPEC 12.18: while the player channels (Tame Beast, Volley, Eagle Eye, Mend Pet...) Auto Shot cannot fire at all,
-- so the shot bar is hidden for the duration (ShotGroup's settingsFn consults IsChanneling). Both edges wake the
-- group so Activity fades it out and back in instead of waiting for the next tick.
function sink:OnChannel(isOn, spellID)
  state.channeling = isOn and true or false
  LogShotEvent("CHANNEL %s %s", isOn and "start" or "stop", tostring(spellID))
  Fire("channel")
end
function ShotTracker.IsChanneling() return state.channeling == true end

function sink:OnSpellSent(spellID, castGUID)
  if not spellID or not SpellData.SHOT_BLOCKING_INSTANTS[spellID] then return end
  RecordPress(spellID, castGUID, GetTime())
end

function sink:OnSpellSucceeded(spellID, castGUID)
  if not spellID then return end
  if SpellData.SHOT_BLOCKING_INSTANTS[spellID] then ResolvePress(castGUID, "resolved", GetTime(), spellID) end
  -- SPEC 12.14 CORRECTED 2026-11-24 (web research, _EXTERNAL_APIS\wow_swing_timer_api.md "What actually delays Auto
  -- Shot"): the GCD does NOT block Auto Shot (owner's disproof: weaving would be impossible). An instant costs the
  -- auto 0.5 s - the auto's own cast restarting - and ONLY if it lands in the red. So draw it as a fixed 0.5 s block
  -- from the press, ALWAYS: the player reads "is my block in the red?" at press time, which is the whole point.
  -- Gate on "a cycle is in flight" (shotEnd), not isShooting (the `!Auto Shot` macro toggles isShooting around the press).
  if SpellData.SHOT_BLOCKING_INSTANTS[spellID] and state.shotEnd then
    local now = GetTime()
    RecordInstantPress(spellID, now)   -- SPEC 12.15 measurement
    state.lastInstantAt, state.lastInstantSpellID = now, spellID   -- SPEC 12.20: same-frame FAILED_QUIET = assert rejection
    local cost = SpellData.AUTO_SHOT_RECAST_DELAY
    local block = { kind = "instant", spellID = spellID, startAt = now, endAt = now + cost }
    state.actionBlocks[#state.actionBlocks + 1] = block
    local verdict = NoteActionBlock(block, now)
    -- SPEC 12.20 debug line shape (owner): one line per press, same columns as the closing "landed" line below, so
    -- the pair reads press -> result. "block -> readyAt +X" is how far the block's end reaches past the window
    -- start: negative = ends before it (free); the size of the positive number is how much red was drawn.
    local lead = state.shotEnd - now
    local pastReady = block.endAt - (state.shotEnd - ShotTracker.CastWindow())
    LogShotEvent("ACTION instant %d  lead %.2fs  block -> readyAt %+.2fs  %s", spellID, lead, pastReady, verdict)
    if DebugTimerPrediction() then Util.Print("|cff40c0ffinstant|r %d  lead %.2fs  block -> readyAt %+.2fs  %s", spellID, lead, pastReady, verdict) end
    Fire("action")
  end
  if Client.flavour == "forever" then return end        -- PLAYER_SWING owns the anchor there
  if Client.IsAutoRepeatSpell(spellID) then
    RefreshSpeed()
    Anchor(nil, "shot")
  end
end

-- SPEC 12.14: a real cast (Multi-Shot 0.5 s, Aimed Shot 3 s) blocks Auto Shot for its duration, AND the 0.5 s retry
-- timer runs in the background during the cast, so the auto can wait up to one more period after the cast ends
-- ("Classic Hunter: The Retry Timer" item 2). The block carries that as a faint tail the views draw lighter.
function sink:OnSpellCastStart(spellID)
  if not spellID or not SpellData.SHOT_BLOCKING_CASTS[spellID] or not state.shotEnd then return end
  local now = GetTime()
  TaintPendingInstant("real cast in the same cycle")   -- SPEC 12.15: a cast muddies the instant's delay
  local endAt
  if UnitCastingInfo then
    local _, _, _, startMs, endMs = UnitCastingInfo("player")
    endMs = Util.PlainNumber(endMs, nil)
    if endMs then endAt = endMs / 1000 end
  end
  if not endAt then endAt = now + SpellData.SHOT_BLOCKING_CASTS[spellID] end
  state.actionBlocks[#state.actionBlocks + 1] = { kind = "cast", spellID = spellID, startAt = now, endAt = endAt,
    tailEndAt = endAt + SpellData.AUTO_SHOT_RECAST_DELAY }
  LogShotEvent("ACTION cast %d  %.2fs", spellID, endAt - now)
  if DebugTimerPrediction() then Util.Print("|cff40c0ffaction block|r cast %d  %.2fs (+%.1fs retry tail)", spellID, endAt - now, SpellData.AUTO_SHOT_RECAST_DELAY) end
  Fire("action")
end

-- A cast that failed or was interrupted stops blocking at that instant: cut its block short.
function sink:OnSpellCastStop(spellID, reason, castGUID)
  if spellID and SpellData.SHOT_BLOCKING_INSTANTS[spellID] and reason ~= "stop" then ResolvePress(castGUID, reason, GetTime(), spellID) end
  if not spellID or not SpellData.SHOT_BLOCKING_CASTS[spellID] then return end
  if reason ~= "failed" and reason ~= "interrupted" then return end   -- "stop" after success keeps the full block
  local now = GetTime()
  for i = #state.actionBlocks, 1, -1 do
    local b = state.actionBlocks[i]
    if b.kind == "cast" and b.spellID == spellID and b.endAt > now then
      b.endAt = now
      LogShotEvent("ACTION cast %d cut (%s)", spellID, reason)
      break
    end
  end
  Fire("action")
end

-- UNIT_SPELLCAST_FAILED_QUIET 75: the engine's ~0.5 s Auto Shot retry failed (moving, GCD, range). SPEC 12.4: this
-- NEVER moves shotEnd - the charge clock stays truthful and the fill can never retreat.
-- SPEC 12.9: it is our ONLY source for the engine's retry metronome phase. The first one acquires the reference
-- (retryPhase); each later one re-syncs it AND, when we already held a phase, records how far the real tick was from
-- the one we predicted (gcdDrift). That drift log is how the owner decides TBD-A (does a landed shot re-seed the clock).
function sink:OnSpellFailedQuiet(spellID, castGUID)
  -- SPEC 12.17: an instant's press that the server quietly refused
  if spellID and SpellData.SHOT_BLOCKING_INSTANTS[spellID] then ResolvePress(castGUID, "failed_quiet", GetTime(), spellID); return end
  if not spellID or not Client.IsAutoRepeatSpell(spellID) or not state.isShooting then return end
  local now = GetTime()
  local period = SpellData.AUTO_SHOT_RECAST_DELAY
  -- SPEC 12.11(a): Era delivers FAILED_QUIET 75 twice per failure at the same timestamp (both the unit-event and
  -- the plain registration land). One failure = one tick; the duplicate would record a bogus 0-drift and re-latch.
  if state.lastRetryAt and now - state.lastRetryAt < GCD_DUPLICATE_WINDOW then return end
  -- SPEC 12.16 (measured 2026-11-24, five sessions): the engine fires ONE FAILED_QUIET ~0.13 s after every anchor
  -- and every autorepeat start, on a stationary player, with the auto having JUST fired (0.25-0.28 periods, every
  -- clean cycle; later ones only when moving). That is its first-check heartbeat for the new cycle, not a refusal.
  -- Treating it as a refusal acquired a bogus retry phase, drained the brick after every shot, and produced every
  -- false "missed tick" / "retry irregular". It carries no information: drop it before anything else sees it.
  local sinceAnchor = now - (state.shotStart or 0)
  local sinceStart  = state.lastAutoRepeatStartAt and (now - state.lastAutoRepeatStartAt) or math.huge
  if sinceAnchor < FIRST_CHECK_HEARTBEAT_WINDOW or sinceStart < FIRST_CHECK_HEARTBEAT_WINDOW then
    LogShotEvent("FAILED_QUIET 75 heartbeat (%.3fs after %s) - ignored", math.min(sinceAnchor, sinceStart),
      sinceAnchor <= sinceStart and "anchor" or "autorepeat start")
    return
  end
  -- SPEC 12.19 (dump 2026-11-24 19:30): every `/cast !Auto Shot` macro press lands a FAILED_QUIET 75 in the SAME
  -- frame as its AUTOREPEAT stop, stationary - three times in one dump. That is the macro's own "Auto Shot is already
  -- on" rejection ("Retry Timer" item 4), not the auto being refused by anything the player did. It acquired and
  -- re-synced our retry phase from a non-event, which is where the remaining false "missed tick" / "irregular" came
  -- from. It carries no information about the shot clock: ignore it like the heartbeat.
  if state.lastAutoRepeatStopAt and now - state.lastAutoRepeatStopAt < AUTOREPEAT_REASSERT_WINDOW then
    LogShotEvent("FAILED_QUIET 75 = !Auto Shot macro 'already on' rejection - ignored")
    return
  end
  -- SPEC 12.20 (dump 2026-11-25): Concussive Shot SUCCEEDED and a FAILED_QUIET 75 landed in the SAME frame. Any
  -- offensive ranged ability asserts Auto Shot; asserting while already shooting yields the same "already on"
  -- rejection the macro does (12.19), just triggered by the instant itself. Not a refusal of the auto: ignore.
  if state.lastInstantAt and now - state.lastInstantAt < AUTOREPEAT_REASSERT_WINDOW then
    LogShotEvent("FAILED_QUIET 75 in the frame of instant %d = Auto Shot assert rejection - ignored", state.lastInstantSpellID or 0)
    return
  end
  -- SPEC 12.11: first failure of this shot - log where the engine's re-seeded clock actually landed, relative to
  -- readyAt, so the re-seed rule can be learned from a few shots' worth of data
  if not state.firstFailureLogged and state.shotEnd then
    state.firstFailureLogged = true
    local readyAt = state.shotEnd - ShotTracker.CastWindow()
    LogShotEvent("FIRST FAILURE this shot: readyAt %+.3fs  shot %+.3fs  (%.3f periods after shot)",
      now - readyAt, now - state.lastShotTime, (now - state.lastShotTime) / period)
  end
  if state.retryPhase then
    -- SPEC 12.13: diagnostic only (how irregular the engine's retry interval is); /vwst trace prints it, /vwst status
    -- shows the ring. Nothing here is an expectation any more, so nothing here is announced as a surprise.
    local drift = (now - state.retryPhase) % period
    if drift > period / 2 then drift = drift - period end
    state.gcdDriftIdx = (state.gcdDriftIdx % GCD_DRIFT_RING) + 1
    state.gcdDrift[state.gcdDriftIdx] = { drift = drift, sinceShot = now - state.lastShotTime }
    if NS.trace then Util.Print("GCD drift %+.3f (%.2fs after shot)", drift, now - state.lastShotTime) end
  end
  -- SPEC 12.20: the ONE expectation the model makes. A refusal is explained by (a) movement now or within the last
  -- period (server-side position lag), or (b) a live action block that has invaded the window (red on the bar).
  -- Any other refusal while READY contradicts "no red = the auto fires on time" and is the surprise to print.
  local moving = IsMoving()
  local movedRecently = moving or (state.lastMovedAt ~= nil and now - state.lastMovedAt < period)
  local redBlock = ActionBlockInvadingWindow(now)
  local ready = state.shotEnd ~= nil and now >= state.shotEnd - ShotTracker.CastWindow()
  local explained = (not ready) or movedRecently or (redBlock ~= nil) or state.channeling
  NoteCycleRefusal(now)   -- SPEC 12.21: counted into the cycle's outcome line
  LogShotEvent("FAILED_QUIET 75  moving %s  red block %s  GCD %s%s", tostring(moving),
    redBlock and tostring(redBlock.spellID) or "none", tostring(ShotTracker.GCDRemaining()),
    explained and "" or "  UNEXPLAINED")
  if not explained and DebugTimerPrediction() then
    Util.Print("|cffff4040unexplained refusal|r FAILED_QUIET 75 while still, ready, no invading block  [shot +%.2fs | readyAt %+.2fs | last moved %s | GCD %s | speed %.2f win %.2f]",
      now - state.lastShotTime, (state.shotEnd - ShotTracker.CastWindow()) - now,
      state.lastMovedAt and string.format("%.2fs ago", now - state.lastMovedAt) or "never",
      tostring(ShotTracker.GCDRemaining()), state.speed or 0, ShotTracker.CastWindow())
    DumpShotEventLog("unexplained refusal")
  end
  state.retryPhase = now % period
  state.lastRetryAt = now
  state.castStartAt = nil
  state.movedInWindow = true
  Fire("movement")
end

-- The player's real GCD remaining (seconds), for the mis-prediction context (diagnostic only).
-- 2026-11-24: the previous probe read the cooldown of Attack (6603), which does NOT carry the GCD on Era - every dump
-- printed "GCD 0" 0.5 s into a Serpent Sting GCD. The probe now reads a spell that is really on the GCD category and
-- has NO cooldown of its own (so its cooldown IS the GCD): 61304 (the GCD dummy, Forever / Mainline) first, else the
-- first rank-1 class spell below that the character knows. Rank 1 is always in the Classic spellbook once learned.
local GCD_PROBE_SPELLS_BY_CLASS = {
  HUNTER  = { 1130, 1978 },   -- Hunter's Mark r1, Serpent Sting r1
  PRIEST  = { 585, 2050 },    -- Smite r1, Lesser Heal r1
  MAGE    = { 133, 116 },     -- Fireball r1, Frostbolt r1
  WARLOCK = { 686, 348 },     -- Shadow Bolt r1, Immolate r1
  WARRIOR = { 772, 6343 },    -- Rend r1, Thunder Clap r1 (has a CD: last resort)
  ROGUE   = { 1752, 53 },     -- Sinister Strike r1, Backstab r1
  DRUID   = { 5176, 8921 },   -- Wrath r1, Moonfire r1
  PALADIN = { 635, 19740 },   -- Holy Light r1, Blessing of Might r1
  SHAMAN  = { 403, 331 },     -- Lightning Bolt r1, Healing Wave r1
}
local gcdProbeSpellID = nil   -- resolved once; nil until a probe spell is found
local function ResolveGCDProbeSpell()
  if gcdProbeSpellID then return gcdProbeSpellID end
  -- a known class spell first (verifiable on both flavours); the 61304 GCD dummy only as a Mainline-API fallback
  for _, id in ipairs(GCD_PROBE_SPELLS_BY_CLASS[Client.PlayerClass() or ""] or {}) do
    if (IsSpellKnown and IsSpellKnown(id)) or (IsPlayerSpell and IsPlayerSpell(id)) then gcdProbeSpellID = id return id end
  end
  if C_Spell and C_Spell.GetSpellCooldown and Client.flavour == "forever" then
    gcdProbeSpellID = 61304
    return 61304
  end
  return nil
end
function ShotTracker.GCDProbeSpellID() return ResolveGCDProbeSpell() end

function ShotTracker.GCDRemaining()
  local id = ResolveGCDProbeSpell()
  if not id then return nil end
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
  local now = GetTime()
  -- A `/cast !Auto Shot` press while already shooting delivers STOP then START at the same instant (log
  -- 2026-11-24: pairs at identical timestamps). That is a re-assert, not a restart: the engine's retry clock is
  -- untouched, so keep our reference. Only a START that was not immediately preceded by a STOP (or a lone STOP)
  -- is a real transition.
  if isOn and state.isShooting == false and state.lastAutoRepeatStopAt and now - state.lastAutoRepeatStopAt < AUTOREPEAT_REASSERT_WINDOW then
    state.isShooting = true
    state.lastReassertAt = now
    LogShotEvent("AUTOREPEAT re-assert (stop+start %.0f ms apart) - reference kept", (now - state.lastAutoRepeatStopAt) * 1000)
    -- SPEC 12.14 / research 2026-11-24 ("Retry Timer" item 4): re-asserting an already-running Auto Shot starts the
    -- 0.5 s retry timer in the background -> the next auto can be delayed up to one period. A `!Auto Shot` macro does
    -- this on EVERY press. Draw it as an action block with the Auto Shot icon so the player can see their macro cost.
    if state.shotEnd then
      local window = ShotTracker.CastWindow()
      if now >= state.shotEnd - window then
        local block = { kind = "reassert", spellID = SpellData.AUTO_SHOT, startAt = now,
          endAt = now + SpellData.AUTO_SHOT_RECAST_DELAY }
        state.actionBlocks[#state.actionBlocks + 1] = block
        NoteActionBlock(block, now)
        LogShotEvent("ACTION !Auto Shot re-assert inside auto cast  +%.2fs", SpellData.AUTO_SHOT_RECAST_DELAY)
        if DebugTimerPrediction() then Util.Print("|cff40c0ffaction block|r !Auto Shot re-assert inside the auto's cast  +%.2fs", SpellData.AUTO_SHOT_RECAST_DELAY) end
      end
    end
    Fire("autorepeat")
    return
  end
  if not isOn then state.lastAutoRepeatStopAt = now end
  if isOn then state.lastAutoRepeatStartAt = now end   -- SPEC 12.16: the heartbeat window is measured from here too
  state.isShooting = isOn
  LogShotEvent("AUTOREPEAT %s", isOn and "start" or "stop")
  -- a lone STOP keeps the reference too: if START follows within the window we want it; a real stop is followed by
  -- a real START later, which drops it then
  if isOn then DropGCDReference("autorepeat start") end
  if not isOn then
    -- a genuine stop (target died, out of range): the cycle in flight is over. Drop the instant sample so a stale
    -- expectedShotEnd never lands in the histogram, and forget the retry phase so the missed-tick check cannot fire
    -- on a target that is gone (2026-11-24 dump: "missed tick" 2.2 s after a lone AUTOREPEAT stop).
    pendingInstant = nil
    ShotTracker.AbandonCycle("autorepeat stop")   -- SPEC 12.21: judge "blocked" now rather than waiting for the overdue timer
    C_Timer.After(AUTOREPEAT_REASSERT_WINDOW * 2, function()
      if not state.isShooting then DropGCDReference("autorepeat stopped (no re-assert followed)") end
    end)
  end
  if isOn then
    RefreshSpeed(); RefreshBaseSpeed()
    -- Owner 2026-11-24: starting Auto Shot IS activity for the shot bar - a hunter who opens with Arcane Shot /
    -- Serpent Sting has committed to shooting and upstream shows the bar at once. (The melee rule that the
    -- auto-ATTACK toggle is not activity still stands: a caster at range has that on and never swings.)
    state.lastShotTime = GetTime()
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
    ShotTracker.AbandonCycle("world / death")
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
  local probe = ShotTracker.GCDProbeSpellID()
  line = line .. string.format(" | GCD probe spell %s", probe and tostring(probe) or "NONE (GCD column reads nil)")
  return line
end