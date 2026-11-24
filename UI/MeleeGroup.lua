-- Velocity Swing Timers: the player's melee group CONTROLLER (SPEC 13). Owns the group frame, backdrop, placement,
-- Activity and the off-hand visibility DECISION; all pixels live in UI\Views\MeleeView_Hands.lua. Bound to
-- Core\SwingTracker for timing. M3 instantiates this shape again for the target and focus groups.
local ADDON_NAME, NS = ...
local Util, Theme, SwingTracker, DB = NS.Util, NS.Theme, NS.SwingTracker, NS.DB

local MeleeGroup = {}
NS.MeleeGroup = MeleeGroup

local frame, backdrop, view, activity
local driver = CreateFrame("Frame")   -- OnUpdate lives here: a hidden frame never ticks, and the group frame IS hidden when idle
local ticking = false

local function Settings() return DB.Profile().player end

-- SPEC 10.9: in Edit Mode the off-hand bar renders whenever the option is on, so it can be placed with nothing
-- equipped; in play it also needs a real off-hand weapon. This is a controller decision, not the view's.
local function ShowOffhand(s) return s.showOffhand and (NS.editModeActive or SwingTracker.HasOffhand()) end

local function Layout()
  local s = Settings()
  view:Layout(s, s.width, s.height, ShowOffhand(s))
  frame:SetSize(view.frame:GetWidth(), view.frame:GetHeight())
  view.frame:ClearAllPoints(); view.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  Theme.ApplyGroupBackdrop(backdrop, frame, s)
end

-- Position is owned by the profile record; Edit Mode (M6) writes it, this reads it.
local function Place()
  local s = Settings()
  frame:ClearAllPoints()
  frame:SetPoint(s.point or "CENTER", UIParent, s.point or "CENTER", s.x or 0, s.y or 0)
end

local function HandSnap(handName, now)
  local remaining, speed, progress = SwingTracker.Hand(handName, now)
  if remaining == nil then return nil end
  return { remaining = remaining, speed = speed, progress = progress }
end

local function OnUpdate(_, dt)
  local now = GetTime()
  local visible = activity:Tick(now, dt)
  if visible or NS.editModeActive then
    local s = Settings()
    if NS.editModeActive then
      -- frozen samples so the bars can be placed: MH half way, OH 30 %
      local mh = SwingTracker.hands.mainhand.speed or 2
      local oh = SwingTracker.hands.offhand.speed or 1.5
      view:Render({ mainhand = { remaining = mh / 2, speed = mh, progress = 0.5 },
                    offhand  = { remaining = oh * 0.7, speed = oh, progress = 0.3 } }, s)
    else
      view:Render({ mainhand = HandSnap("mainhand", now), offhand = HandSnap("offhand", now) }, s)
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
  view = NS.MeleeView_Hands.New(frame)
  view.frame:SetFrameLevel(frame:GetFrameLevel() + 1)

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