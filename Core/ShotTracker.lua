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
}
ShotTracker.state = state
local listeners = {}
local tooltip
local baseSpeedCache = {}   -- itemID -> base speed

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
  state.shotStart = now
  state.shotEnd = now + state.speed
  state.movedInWindow = false
  if reason == "shot" then state.lastShotTime = now end
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

-- Movement cancelled the pending Auto Shot; the engine retries ~0.5 s later plus the cast window.
function sink:OnSpellFailedQuiet(spellID)
  if not spellID or not Client.IsAutoRepeatSpell(spellID) or not state.isShooting then return end
  local delay = SpellData.AUTO_SHOT_RECAST_DELAY
  if Client.flavour ~= "forever" then delay = delay + ShotTracker.CastWindow() end
  local now = GetTime()
  if not state.shotStart then state.shotStart = now end
  state.shotEnd = now + delay
  state.movedInWindow = true
  Fire("movement")
end

function sink:OnAutoRepeat(isOn)
  state.isShooting = isOn
  if isOn then
    RefreshSpeed(); RefreshBaseSpeed()
    state.lastShotTime = GetTime()      -- show the bar when shooting STARTS
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
    state.shotEnd = nil; state.isShooting = false
    RefreshSpeed(); RefreshBaseSpeed()
    Fire("clear")
  end)
end

function ShotTracker.Status()
  local r = ShotTracker.Cycle()
  return string.format("shot: speed %s (base %s) window %.2f | %s | shooting %s | last shot %.1fs ago",
    state.speed and string.format("%.2f", state.speed) or "none", state.baseSpeed and string.format("%.2f", state.baseSpeed) or "?",
    ShotTracker.CastWindow(), r and string.format("remaining %.2f", r) or "idle", tostring(state.isShooting),
    GetTime() - state.lastShotTime)
end