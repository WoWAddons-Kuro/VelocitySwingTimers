-- Velocity Swing Timers: the melee hands view - main-hand bar plus, when wanted, an off-hand bar under it.
-- SPEC 13: a VIEW owns its own frame tree and is a pure function of (hand snapshots, settings) -> pixels. It never
-- reads DB, the tracker, GetTime() or Edit Mode state. The controller (UI\MeleeGroup) decides whether the off-hand
-- bar is shown (option + weapon present, or Edit Mode) and passes that in to Layout. M3 reuses this view with one
-- hand for the target and focus groups.
--
-- VWST_MeleeHandSnaps = { mainhand = VWST_HandSnap | nil, offhand = VWST_HandSnap | nil }
-- VWST_HandSnap       = { remaining = seconds, speed = seconds, progress = 0..1 }   (nil hand = idle track)
local ADDON_NAME, NS = ...
local Bar = NS.Bar

local MeleeView_Hands = {}
NS.MeleeView_Hands = MeleeView_Hands
MeleeView_Hands.__index = MeleeView_Hands

local BAR_GAP = 2

-- VWST_MeleeView interface (SPEC 13.3): .frame, :Layout(s, w, h, showOff), :Render(handSnaps, s), :RenderIdle(), :SetLabels, :Show, :Hide
function MeleeView_Hands.New(parent)
  local self = setmetatable({}, MeleeView_Hands)
  self.frame = CreateFrame("Frame", nil, parent)
  self.mainBar = Bar.New(self.frame)
  self.offBar = Bar.New(self.frame)
  self.mainBar:SetLabel("Main-Hand")
  self.offBar:SetLabel("Off-Hand")
  self.showOff = false
  return self
end

-- showOff: the controller's decision (option on AND (weapon present OR Edit Mode)); the view just honours it
function MeleeView_Hands:Layout(s, width, height, showOff)
  self.showOff = showOff and true or false
  local style = {
    width = width, height = height, texture = s.texture, textColor = s.textColor,
    fillDirection = s.fillDirection, fontSize = s.fontSize,
  }
  style.color = s.mainColor or s.color
  self.mainBar:ApplyStyle(style)
  style.color = s.offColor or s.mainColor or s.color
  self.offBar:ApplyStyle(style)
  self.offBar:SetShown(self.showOff)

  local total = self.showOff and (height * 2 + BAR_GAP) or height
  self.frame:SetSize(width, total)
  self.mainBar:ClearAllPoints(); self.mainBar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
  self.offBar:ClearAllPoints();  self.offBar:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
end

function MeleeView_Hands:SetLabels(mainLabel, offLabel)
  self.mainBar:SetLabel(mainLabel or "Main-Hand")
  self.offBar:SetLabel(offLabel or "Off-Hand")
end
function MeleeView_Hands:Show() self.frame:Show() end
function MeleeView_Hands:Hide() self.frame:Hide() end

local function DrawHand(bar, snap)
  if snap then bar:SetProgress(snap.progress, snap.remaining) else bar:SetIdle() end
end

function MeleeView_Hands:Render(handSnaps, s)
  DrawHand(self.mainBar, handSnaps and handSnaps.mainhand)
  if self.showOff then DrawHand(self.offBar, handSnaps and handSnaps.offhand) end
end

function MeleeView_Hands:RenderIdle()
  self.mainBar:SetIdle()
  if self.showOff then self.offBar:SetIdle() end
end