-- Velocity Swing Timers: the shot group - Auto Shot / wand Shoot bar. Bound to Core\ShotTracker and Core\Activity.
--
-- Two presentations (upstream WeaponSwingTimer parity):
--   default  : one bar in cooldownColor that drains over the cycle, turning castWindowColor and refilling during
--              the stand-still window (hunter). "Bar is white: free to move. Bar is red: stand still."
--   oneBar   : YaHT style - a single bar fills left to right over the whole cycle; the cast window is a
--              castWindowColor block at the right end so you see the window coming.
-- The hunter cast bar (Aimed / Multi-Shot) is M5 and hangs under this frame.
local ADDON_NAME, NS = ...
local Util, Theme, Bar, ShotTracker, DB = NS.Util, NS.Theme, NS.Bar, NS.ShotTracker, NS.DB

local ShotGroup = {}
NS.ShotGroup = ShotGroup

local frame, backdrop, shotBar, windowBlock, activity
local ticking = false

local function Settings() return DB.Profile().shot end

local function Layout()
  local s = Settings()
  shotBar:ApplyStyle({
    width = s.width, height = s.height, texture = s.texture, color = s.cooldownColor,
    textColor = { r = 1, g = 1, b = 1, a = 1 }, showText = s.showText, fillDirection = "fill", fontSize = DB.Global().fontSize,
  })
  frame:SetSize(s.width, s.height)
  shotBar:ClearAllPoints(); shotBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  shotBar:SetLabel(ShotTracker.IsHunter() and "Auto Shot" or "Shoot")

  -- the YaHT window block sits on the right end of the track, sized from the window/cycle ratio
  windowBlock:ClearAllPoints()
  windowBlock:SetPoint("TOPRIGHT", shotBar:GetFrame(), "TOPRIGHT", 0, 0)
  windowBlock:SetHeight(s.height)
  Theme.ApplyColor(windowBlock, s.castWindowColor)
  windowBlock:SetAlpha(0.6)

  local inset = Theme.BackdropInset
  backdrop:ClearAllPoints()
  backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", -inset, inset)
  backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset, -inset)
  backdrop:SetBackdrop(s.showBorder and Theme.Backdrop or Theme.BackdropNoBorder)
  backdrop:SetBackdropColor(0, 0, 0, s.backdropAlpha)
  backdrop:SetBackdropBorderColor(1, 1, 1, s.backdropAlpha > 0 and 1 or 0)
end

local function Place()
  local s = Settings()
  frame:ClearAllPoints()
  frame:SetPoint(s.point or "CENTER", UIParent, s.point or "CENTER", s.x or 0, s.y or 0)
end

local function Draw(now)
  local s = Settings()
  local remaining, cycle, progress, inWindow = ShotTracker.Cycle(now)
  local window = ShotTracker.CastWindow()
  if remaining == nil then
    shotBar:SetIdle(); windowBlock:Hide()
    return
  end
  if s.oneBar then
    -- fills over the whole cycle; window block marks the tail
    Theme.ApplyColor(shotBar.sb, s.cooldownColor)
    shotBar:SetProgress(progress, remaining)
    if window > 0 and cycle > 0 then
      windowBlock:SetWidth(math.max(1, s.width * math.min(1, window / cycle)))
      windowBlock:Show()
    else windowBlock:Hide() end
  else
    windowBlock:Hide()
    if window > 0 and inWindow then
      -- stand still: red bar fills over the window
      Theme.ApplyColor(shotBar.sb, s.castWindowColor)
      shotBar:SetProgress(1 - remaining / window, remaining)
    else
      -- free to move: white bar drains over the cooldown part
      Theme.ApplyColor(shotBar.sb, s.cooldownColor)
      local cd = math.max(cycle - window, 0.01)
      shotBar:SetProgress(Util.Clamp((remaining - window) / cd, 0, 1), remaining)
    end
  end
end

local function OnUpdate(_, dt)
  local now = GetTime()
  local visible = activity:Tick(now, dt)
  if visible or NS.editModeActive then
    if NS.editModeActive then
      Theme.ApplyColor(shotBar.sb, Settings().cooldownColor)
      shotBar:SetProgress(0.6, (ShotTracker.state.speed or 2.5) * 0.4)
      windowBlock:Hide()
    else
      Draw(now)
    end
  elseif not activity:IsActive(now) then
    ShotGroup.StopTicking()
  end
end

function ShotGroup.StartTicking()
  if ticking then return end
  ticking = true
  frame:SetScript("OnUpdate", OnUpdate)
end

function ShotGroup.StopTicking()
  if not ticking then return end
  ticking = false
  frame:SetScript("OnUpdate", nil)
end

local function OnTrackerChanged(what)
  if what == "clear" then return end
  if what == "reset" then Layout() end
  ShotGroup.StartTicking()
end

function ShotGroup.Create()
  frame = CreateFrame("Frame", "VWST_ShotFrame", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  backdrop:SetFrameLevel(frame:GetFrameLevel())
  shotBar = Bar.New(frame)
  shotBar:GetFrame():SetFrameLevel(frame:GetFrameLevel() + 1)
  windowBlock = shotBar:GetFrame():CreateTexture(nil, "ARTWORK", nil, 1)
  windowBlock:SetColorTexture(1, 0, 0, 1)

  activity = NS.Activity.New({
    frame = frame,
    lastActivityFn = ShotTracker.LastActivity,
    settingsFn = function()
      local s = Settings()
      -- no ranged weapon: never show, whatever the setting says
      if not ShotTracker.HasRangedWeapon() then return { enabled = false } end
      return s
    end,
  })
  ShotGroup.activity = activity
  ShotGroup.frame = frame

  Layout()
  Place()
  ShotTracker.OnChanged(OnTrackerChanged)
  NS.features["ShotGroup"] = true
end

function ShotGroup.Refresh()
  if not frame then return end
  Layout(); Place()
  ShotGroup.StartTicking()
end

function ShotGroup.Status()
  if not frame then return "shot group: not created" end
  return string.format("shot group: %s, alpha %.2f, ticking %s", frame:IsShown() and "shown" or "hidden", activity.alpha, tostring(ticking))
end