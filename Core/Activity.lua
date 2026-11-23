-- Velocity Swing Timers: the visibility model (SPEC section 2). One instance per bar group.
--
-- A group is Active while its attack has happened recently (lastActivity within inactivitySeconds),
-- Hidden otherwise. Target alpha: Active -> 1 in combat, settings.oocAlpha out of combat; Hidden -> 0.
-- Edit Mode forces 1. The frame eases toward the target alpha over fadeSeconds and is Hide()n at 0 so an
-- invisible group costs nothing.
local ADDON_NAME, NS = ...
local Util = NS.Util

local Activity = {}
NS.Activity = Activity
Activity.__index = Activity

NS.editModeActive = false      -- set by UI\EditMode (M6)

-- VWST_ActivityConfig = { frame, lastActivityFn = function() -> GetTime(), settingsFn = function() -> group settings }
function Activity.New(cfg)
  local self = setmetatable({}, Activity)
  self.frame = cfg.frame
  self.lastActivityFn = cfg.lastActivityFn
  self.settingsFn = cfg.settingsFn
  self.alpha = 0
  self.frame:SetAlpha(0)
  self.frame:Hide()
  return self
end

function Activity:IsActive(now)
  local last = self.lastActivityFn()
  return last > 0 and (now - last) < NS.DB.Global().inactivitySeconds
end

function Activity:TargetAlpha(now)
  local s = self.settingsFn()
  if not s.enabled then return 0 end
  if NS.editModeActive then return 1 end
  if not self:IsActive(now) then return 0 end
  if NS.inCombat then return 1 end
  return s.oocAlpha or 0
end

-- Returns true while the frame is (or is becoming) visible, so the owner knows whether to keep ticking.
function Activity:Tick(now, dt)
  local target = self:TargetAlpha(now)
  local fade = NS.DB.Global().fadeSeconds
  if fade <= 0 or NS.editModeActive then
    self.alpha = target
  else
    local step = dt / fade
    if self.alpha < target then self.alpha = math.min(target, self.alpha + step)
    elseif self.alpha > target then self.alpha = math.max(target, self.alpha - step) end
  end
  if self.alpha <= 0.001 then
    self.alpha = 0
    if self.frame:IsShown() then self.frame:Hide() end
    return false
  end
  if not self.frame:IsShown() then self.frame:Show() end
  self.frame:SetAlpha(self.alpha)
  return true
end

-- Force a re-evaluation on the next tick (settings changed, edit mode toggled).
function Activity:Poke() self.poked = true end

-- Diagnostics for /vwst status.
function Activity:Status()
  local now = GetTime()
  local s = self.settingsFn()
  return string.format("active %s target %.2f alpha %.2f enabled %s inCombat %s ooc %s shown %s",
    tostring(self:IsActive(now)), self:TargetAlpha(now), self.alpha, tostring(s.enabled), tostring(NS.inCombat),
    tostring(s.oocAlpha), tostring(self.frame:IsShown()))
end