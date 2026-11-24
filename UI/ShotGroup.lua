-- Velocity Swing Timers: the shot group - Auto Shot / wand Shoot bar. Bound to Core\ShotTracker and Core\Activity.
--
-- Two presentations, VWST_ShotBarStyle (upstream WeaponSwingTimer parity, see its Images\*Explained*.png):
--   "mirrored" : fill anchored at the CENTRE. cooldownColor (white) shrinks into the middle over the cooldown part
--                of the cycle ("can move or cast"); then castWindowColor (red) grows out of the middle over the
--                stand-still window ("don't move or cast"). Wands have no window, so they only ever shrink.
--   "onebar"   : YaHT style - fills left to right over the whole cycle; the window is a fixed castWindowColor block
--                at the right end so you see it coming.
-- The hunter cast bar (Aimed / Multi-Shot) is M5 and hangs under this frame.
local ADDON_NAME, NS = ...
local Util, Theme, Bar, ShotTracker, DB = NS.Util, NS.Theme, NS.Bar, NS.ShotTracker, NS.DB

local ShotGroup = {}
NS.ShotGroup = ShotGroup

local frame, backdrop, shotBar, windowBlock, activity
local driver = CreateFrame("Frame")   -- OnUpdate lives here: a hidden frame never ticks, and the group frame IS hidden when idle
local ticking = false

local function Settings() return DB.Profile().shot end

-- Style a Bar + its window block for shot settings s. Shared with the options-panel preview, hence module level.
-- VWST_ShotBarParts = { bar = Bar, block = Texture }
function ShotGroup.StyleBar(parts, s, width, height)
  local style = s.style or "mirrored"
  parts.bar:ApplyStyle({
    width = width, height = height, texture = s.texture, color = s.cooldownColor,
    textColor = { r = 1, g = 1, b = 1, a = 1 }, showText = s.showText, fillDirection = "fill",
    fillAnchor = style == "mirrored" and "center" or "left", fontSize = DB.Global().fontSize,
  })
  local block, centerLine = parts.block, parts.centerLine
  block:ClearAllPoints()
  block:SetPoint("TOPRIGHT", parts.bar:GetFrame(), "TOPRIGHT", 0, 0)
  block:SetHeight(height)
  Theme.ApplyColor(block, s.castWindowColor)
  block:SetAlpha(0.6)
  -- mirrored only: a thin castWindowColor line at the centre, the point the fill shrinks into / grows out of
  if centerLine then
    centerLine:ClearAllPoints()
    centerLine:SetPoint("TOP", parts.bar:GetFrame(), "TOP", 0, 0)
    centerLine:SetPoint("BOTTOM", parts.bar:GetFrame(), "BOTTOM", 0, 0)
    centerLine:SetWidth(1)
    Theme.ApplyColor(centerLine, s.castWindowColor)
    centerLine:SetShown(style == "mirrored")
  end
end

-- Draw one instant of a shot cycle. Pure function of its inputs so the options preview can animate a fake cycle.
--   remaining: seconds to the shot; cycle: full cycle length; window: stand-still window (0 for wands)
function ShotGroup.RenderBar(parts, s, width, remaining, cycle, window)
  local bar, block = parts.bar, parts.block
  local style = s.style or "mirrored"
  local progress = cycle > 0 and Util.Clamp(1 - remaining / cycle, 0, 1) or 1
  if style == "onebar" then
    bar:SetColor(s.cooldownColor)
    bar:SetProgress(progress, remaining)
    if window > 0 and cycle > 0 then
      block:SetWidth(math.max(1, width * math.min(1, window / cycle)))
      block:Show()
    else block:Hide() end
  else
    block:Hide()
    if window > 0 and remaining <= window then
      -- stand still: red grows out of the centre over the window
      bar:SetColor(s.castWindowColor)
      bar:SetProgress(Util.Clamp(1 - remaining / window, 0, 1), remaining)
    else
      -- free to move: white shrinks into the centre over the cooldown part
      bar:SetColor(s.cooldownColor)
      local cd = math.max(cycle - window, 0.01)
      bar:SetProgress(Util.Clamp((remaining - window) / cd, 0, 1), remaining)
    end
  end
end

local parts   -- VWST_ShotBarParts for the live bar

local function Layout()
  local s = Settings()
  ShotGroup.StyleBar(parts, s, s.width, s.height)
  frame:SetSize(s.width, s.height)
  shotBar:ClearAllPoints(); shotBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  shotBar:SetLabel(ShotTracker.IsHunter() and "Auto Shot" or "Shoot")

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
  local remaining, cycle = ShotTracker.Cycle(now)
  local window = ShotTracker.CastWindow()
  if remaining == nil then
    shotBar:SetIdle(); windowBlock:Hide()
    return
  end
  ShotGroup.RenderBar(parts, s, s.width, remaining, cycle, window)
end

local function OnUpdate(_, dt)
  local now = GetTime()
  local visible = activity:Tick(now, dt)
  if visible or NS.editModeActive then
    if NS.editModeActive then
      -- a frozen sample: 40% of a 2.5 s cycle still to go, outside any window
      local s = Settings()
      local cycle = ShotTracker.state.speed or 2.5
      ShotGroup.RenderBar(parts, s, s.width, cycle * 0.4, cycle, 0)
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
  driver:SetScript("OnUpdate", OnUpdate)
end

function ShotGroup.StopTicking()
  if not ticking then return end
  ticking = false
  driver:SetScript("OnUpdate", nil)
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
  local centerLine = shotBar:GetFrame():CreateTexture(nil, "OVERLAY")
  centerLine:SetColorTexture(1, 1, 1, 1)
  parts = { bar = shotBar, block = windowBlock, centerLine = centerLine }

  activity = NS.Activity.New({
    frame = frame,
    lastActivityFn = ShotTracker.LastActivity,
    settingsFn = function()
      local s = Settings()
      -- no ranged weapon: never show in play, whatever the setting says. Edit Mode is exempt: an enabled
      -- group must be placeable even with nothing in the ranged slot (sample fill, fallback speed).
      if not NS.editModeActive and not ShotTracker.HasRangedWeapon() then return { enabled = false } end
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
  return string.format("shot group: ticking %s | %s", tostring(ticking), activity:Status())
end