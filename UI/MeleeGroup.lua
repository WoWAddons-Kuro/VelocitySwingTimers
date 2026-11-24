-- Velocity Swing Timers: the player's melee group - a backdrop frame holding the main-hand bar and,
-- when a weapon is in the off hand, the off-hand bar. Bound to Core\SwingTracker for timing and to
-- Core\Activity for whether it is on screen at all.
local ADDON_NAME, NS = ...
local Util, Theme, Bar, SwingTracker, DB = NS.Util, NS.Theme, NS.Bar, NS.SwingTracker, NS.DB

local MeleeGroup = {}
NS.MeleeGroup = MeleeGroup

local BAR_GAP = 2
local frame, backdrop, mainBar, offBar, activity
local driver = CreateFrame("Frame")   -- OnUpdate lives here: a hidden frame never ticks, and the group frame IS hidden when idle
local ticking = false

local function Settings() return DB.Profile().player end

local function Layout()
  local s = Settings()
  -- SPEC 10.9: in Edit Mode the off-hand bar renders whenever the option is on, so it can be placed with nothing
  -- equipped; in play it also needs a real off-hand weapon
  local showOff = s.showOffhand and (NS.editModeActive or SwingTracker.HasOffhand())
  local style = {
    width = s.width, height = s.height, texture = s.texture, textColor = s.textColor,
    fillDirection = s.fillDirection, fontSize = s.fontSize,
  }
  style.color = s.mainColor
  mainBar:ApplyStyle(style)
  style.color = s.offColor
  offBar:ApplyStyle(style)
  offBar:SetShown(showOff)

  local height = showOff and (s.height * 2 + BAR_GAP) or s.height
  frame:SetSize(s.width, height)
  mainBar:ClearAllPoints(); mainBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  offBar:ClearAllPoints(); offBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

  Theme.ApplyGroupBackdrop(backdrop, frame, s)
end

-- Position is owned by the profile record; Edit Mode (M6) writes it, this reads it.
local function Place()
  local s = Settings()
  frame:ClearAllPoints()
  frame:SetPoint(s.point or "CENTER", UIParent, s.point or "CENTER", s.x or 0, s.y or 0)
end

local function DrawHand(bar, handName, now)
  local remaining, speed, progress = SwingTracker.Hand(handName, now)
  if remaining == nil then
    bar:SetIdle()
  else
    bar:SetProgress(progress, remaining)
  end
end

local function OnUpdate(_, dt)
  local now = GetTime()
  local visible = activity:Tick(now, dt)
  if visible or NS.editModeActive then
    if NS.editModeActive then
      mainBar:SetProgress(0.5, (SwingTracker.hands.mainhand.speed or 2) / 2)
      offBar:SetProgress(0.3, (SwingTracker.hands.offhand.speed or 1.5) * 0.7)
    else
      DrawHand(mainBar, "mainhand", now)
      DrawHand(offBar, "offhand", now)
    end
  elseif not activity:IsActive(now) then
    MeleeGroup.StopTicking()
  end
end

function MeleeGroup.StartTicking()
  if ticking then return end
  ticking = true
  driver:SetScript("OnUpdate", OnUpdate)
end

function MeleeGroup.StopTicking()
  if not ticking then return end
  ticking = false
  driver:SetScript("OnUpdate", nil)
end

-- Any change from the tracker wakes the group; the activity model decides whether that shows anything.
local function OnTrackerChanged(what, hand)
  if what == "clear" then return end
  if hand == "offhand" and (what == "reset" or what == "haste") then Layout() end
  MeleeGroup.StartTicking()
end

function MeleeGroup.Create()
  frame = CreateFrame("Frame", "VWST_PlayerMeleeFrame", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  backdrop:SetFrameLevel(frame:GetFrameLevel())
  mainBar = Bar.New(frame)
  mainBar:GetFrame():SetFrameLevel(frame:GetFrameLevel() + 1)
  mainBar:SetLabel("Main-Hand")
  offBar = Bar.New(frame)
  offBar:GetFrame():SetFrameLevel(frame:GetFrameLevel() + 1)
  offBar:SetLabel("Off-Hand")

  activity = NS.Activity.New({
    frame = frame,
    lastActivityFn = SwingTracker.LastActivity,
    settingsFn = Settings,
  })
  MeleeGroup.activity = activity
  MeleeGroup.frame = frame

  Layout()
  Place()
  SwingTracker.OnChanged(OnTrackerChanged)
  NS.features["MeleeGroup"] = true
end

-- Settings or profile changed: re-skin, re-place, and let the activity model re-evaluate.
function MeleeGroup.Refresh()
  if not frame then return end
  Layout()
  Place()
  MeleeGroup.StartTicking()
end

function MeleeGroup.Status()
  if not frame then return "melee group: not created" end
  return string.format("melee group: ticking %s | %s | size %dx%d at %s", tostring(ticking), activity:Status(),
    frame:GetWidth(), frame:GetHeight(), tostring((select(1, frame:GetPoint(1)))))
end