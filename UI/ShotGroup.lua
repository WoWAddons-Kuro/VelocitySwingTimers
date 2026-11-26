-- Velocity Swing Timers: the shot group CONTROLLER (SPEC 13) - Auto Shot / wand Shoot. Owns the group frame,
-- backdrop, placement, Activity and Edit Mode registration. Creates one instance of EVERY shot view once, shows the
-- one the profile selects (VWST_ShotBarStyle) and hides the rest, and per frame hands the active view a
-- VWST_ShotSnapshot from Core\ShotTracker. It draws nothing itself: all pixels live in UI\Views\ShotView_*.lua.
-- The hunter cast bar (Aimed / Multi-Shot) is M5 and hangs under this frame.
local ADDON_NAME, NS = ...
local Util, Theme, ShotTracker, DB = NS.Util, NS.Theme, NS.ShotTracker, NS.DB

local ShotGroup = {}
NS.ShotGroup = ShotGroup

local frame, backdrop, activity
local views = {}            -- VWST_ShotBarStyle -> VWST_ShotView
local activeView
local driver = CreateFrame("Frame")   -- OnUpdate lives here: a hidden frame never ticks, and the group frame IS hidden when idle
local ticking = false

local function Settings() return DB.Profile().shot end
local function ShowGCD() return DB.Global().showShotGCD ~= false end
local function ShowActions() return DB.Global().showShotActions ~= false end
local function ShowActionIcon() return DB.Global().showShotActionIcon ~= false end
local CHANNEL_FADE_SECONDS = 0.08   -- SPEC 12.18: fade out/in while channeling (Tame Beast etc.) much faster than fadeSeconds

-- VWST_ShotBarStyle -> view class. Adding a style = one file in UI\Views + one row here.
local VIEW_CLASSES = {
  onebar   = function() return NS.ShotView_OneBar end,
  mirrored = function() return NS.ShotView_Mirrored end,
}

local function Layout()
  local s = Settings()
  local style = s.style or "mirrored"
  if not VIEW_CLASSES[style] then style = "mirrored" end
  frame:SetSize(s.width, s.height)
  -- SPEC 15: the history ring spans historyPeriods cycles; the tracker owns the ring, the setting is a profile value
  ShotTracker.SetHistoryPeriods(s.historyPeriods)
  local label = ShotTracker.IsHunter() and "Auto Shot" or "Shoot"
  local windowFrac = ShotTracker.WindowFrac()
  for key, v in pairs(views) do
    v.frame:ClearAllPoints(); v.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    v:Layout(s, s.width, s.height, windowFrac, ShowGCD())
    v:SetLabel(label)
    if key == style then v:Show() else v:Hide() end
  end
  activeView = views[style]
  Theme.ApplyGroupBackdrop(backdrop, frame, s)
end

local function Place()
  local s = Settings()
  frame:ClearAllPoints()
  frame:SetPoint(s.point or "CENTER", UIParent, s.point or "CENTER", s.x or 0, s.y or 0)
end

local function OnUpdate(_, dt)
  local now = GetTime()
  local visible = activity:Tick(now, dt)
  if visible or NS.editModeActive then
    local s = Settings()
    -- SPEC 15: the write head moves even between cycles (overdue auto, target gone) so the gap is written as empty
    if not NS.editModeActive then ShotTracker.HistoryTick(now) end
    local snap = NS.editModeActive and ShotTracker.SampleSnapshot() or ShotTracker.Snapshot(now)
    if snap then activeView:Render(snap, s, ShowGCD(), ShowActions(), ShowActionIcon()) else activeView:RenderIdle() end
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
  for key, classFn in pairs(VIEW_CLASSES) do
    local cls = classFn()
    if cls then
      views[key] = cls.New(frame)
      views[key].frame:SetFrameLevel(frame:GetFrameLevel() + 1)
    end
  end

  activity = NS.Activity.New({
    frame = frame,
    lastActivityFn = ShotTracker.LastActivity,
    -- SPEC 12.18 (owner): a channel should take the bar away QUICKLY, not at the leisurely global fade. Also
    -- returns quickly when the channel ends so the next auto is not hidden behind a slow fade-in.
    fadeSecondsFn = function()
      if not NS.editModeActive and ShotTracker.IsChanneling() then return CHANNEL_FADE_SECONDS end
    end,
    settingsFn = function()
      local s = Settings()
      -- no ranged weapon: never show in play, whatever the setting says. Edit Mode is exempt: an enabled
      -- group must be placeable even with nothing in the ranged slot (sample fill, fallback speed).
      if not NS.editModeActive and not ShotTracker.HasRangedWeapon() then return { enabled = false } end
      -- SPEC 12.18 (owner 2026-11-24): a channel (Tame Beast, Volley, Eagle Eye...) means no Auto Shot for its
      -- whole duration, so the bar - and the cycling brick in particular - is noise. Hide it while channeling.
      -- Activity fades it out and back in over fadeSeconds, so a short channel does not snap the bar.
      if not NS.editModeActive and ShotTracker.IsChanneling() then return { enabled = false } end
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
  return string.format("shot group: ticking %s | view %s | %s", tostring(ticking), tostring(Settings().style), activity:Status())
end