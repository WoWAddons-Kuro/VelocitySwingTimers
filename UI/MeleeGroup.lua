-- Velocity Swing Timers: melee group CONTROLLERS (SPEC 13, instance-based since M3 / SPEC 10.6). Owns the group
-- frame, backdrop, placement, Activity and the off-hand visibility DECISION; all pixels live in
-- UI\Views\MeleeView_Hands.lua. Bound to a SwingTracker instance for timing.
--   NS.MeleeGroup  = the player's group (MH/OH), frame VWST_PlayerMeleeFrame - the pre-M3 API, unchanged
--   NS.TargetGroup = the target's group (one bar, label = the target's NAME), frame VWST_TargetMeleeFrame; Era only
-- VWST_MeleeGroupConfig = { key = "player"|"target", frameName, tracker = SwingTracker instance,
--                           settingsFn = () -> VWST_MeleeGroupSettings, labelFn = () -> mainLabel|nil, singleBar = bool }
local ADDON_NAME, NS = ...
local Util, Theme, DB = NS.Util, NS.Theme, NS.DB

local MeleeGroup = {}

function MeleeGroup.New(cfg)
  local self = { cfg = cfg }
  local tracker, Settings = cfg.tracker, cfg.settingsFn
  local frame, backdrop, view, activity
  local driver = CreateFrame("Frame")   -- OnUpdate lives here: a hidden frame never ticks, and the group frame IS hidden when idle
  local ticking = false

  -- SPEC 10.9: in Edit Mode the off-hand bar renders whenever the option is on, so it can be placed with nothing
  -- equipped; in play it also needs a real off-hand weapon. This is a controller decision, not the view's.
  -- A single-bar group (target) never shows an off hand.
  local function ShowOffhand(s)
    if cfg.singleBar then return false end
    return s.showOffhand and (NS.editModeActive or tracker.HasOffhand())
  end

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
    local remaining, speed, progress = tracker.Hand(handName, now)
    if remaining == nil then return nil end
    return { remaining = remaining, speed = speed, progress = progress }
  end

  -- SPEC 10.8 revised: the target bar's label is the target's name ("Main-hand is just stupid"). Re-read each
  -- frame - it is a string compare inside Bar:SetLabel, cheap, and the target changes under us.
  -- No target (Edit Mode with nothing selected, or between pulls): "Target". lastLabel starts at a sentinel so the
  -- very first frame always writes a label - a nil-equals-nil first compare left the view's "Main-Hand" default
  -- showing (owner's screenshot 2026-11-26).
  self.lastLabel = false
  local function RefreshLabels()
    if not cfg.labelFn then return end
    local label = cfg.labelFn() or "Target"
    if label ~= self.lastLabel then
      self.lastLabel = label
      view:SetLabels(label, nil)
    end
  end

  local function OnUpdate(_, dt)
    local now = GetTime()
    local visible = activity:Tick(now, dt)
    if visible or NS.editModeActive then
      local s = Settings()
      RefreshLabels()
      if NS.editModeActive then
        -- frozen samples so the bars can be placed: MH half way, OH 30 %
        local mh = tracker.hands.mainhand.speed or 2
        local oh = tracker.hands.offhand.speed or 1.5
        view:Render({ mainhand = { remaining = mh / 2, speed = mh, progress = 0.5 },
                      offhand  = { remaining = oh * 0.7, speed = oh, progress = 0.3 } }, s)
      else
        view:Render({ mainhand = HandSnap("mainhand", now), offhand = HandSnap("offhand", now) }, s)
      end
    elseif not activity:IsActive(now) then
      self.StopTicking()
    end
  end

  function self.StartTicking()
    if ticking then return end
    ticking = true
    driver:SetScript("OnUpdate", OnUpdate)
  end

  function self.StopTicking()
    if not ticking then return end
    ticking = false
    driver:SetScript("OnUpdate", nil)
  end

  -- Any change from the tracker wakes the group; the activity model decides whether that shows anything.
  local function OnTrackerChanged(what, hand)
    if what == "clear" then return end
    if hand == "offhand" and (what == "reset" or what == "haste") then Layout() end
    self.StartTicking()
  end

  function self.Create()
    frame = CreateFrame("Frame", cfg.frameName, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    backdrop:SetFrameLevel(frame:GetFrameLevel())
    view = NS.MeleeView_Hands.New(frame)
    view.frame:SetFrameLevel(frame:GetFrameLevel() + 1)
    if cfg.key == "target" then view:SetLabels("Target", nil) end

    activity = NS.Activity.New({
      frame = frame,
      lastActivityFn = tracker.LastActivity,
      settingsFn = Settings,
    })
    self.activity = activity
    self.frame = frame

    Layout()
    Place()
    tracker.OnChanged(OnTrackerChanged)
    NS.features[cfg.key == "player" and "MeleeGroup" or ("MeleeGroup." .. cfg.key)] = true
  end

  -- Settings or profile changed: re-skin, re-place, and let the activity model re-evaluate.
  function self.Refresh()
    if not frame then return end
    Layout()
    Place()
    self.StartTicking()
  end

  function self.Status()
    if not frame then return cfg.key .. " group: not created" end
    return string.format("%s group: ticking %s | %s | size %dx%d at %s", cfg.key, tostring(ticking), activity:Status(),
      frame:GetWidth(), frame:GetHeight(), tostring((select(1, frame:GetPoint(1)))))
  end

  return self
end

-- The player group keeps the pre-M3 module shape (NS.MeleeGroup.Create / Refresh / Status / StartTicking ...).
NS.MeleeGroup = MeleeGroup.New({
  key = "player", frameName = "VWST_PlayerMeleeFrame", tracker = NS.SwingTracker,
  settingsFn = function() return DB.Profile().player end,
})
NS.MeleeGroup.New = MeleeGroup.New

-- Era only (SPEC 10.1): nothing is created on a client with no enemy swing source.
if NS.TargetSwingTracker then
  NS.TargetGroup = MeleeGroup.New({
    key = "target", frameName = "VWST_TargetMeleeFrame", tracker = NS.TargetSwingTracker, singleBar = true,
    settingsFn = function() return DB.Profile().target end,
    labelFn = function() return NS.Client.UnitDisplayName("target") end,
  })
end