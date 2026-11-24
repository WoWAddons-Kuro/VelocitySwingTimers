-- Velocity Swing Timers: the one-bar (YaHT) shot view. SPEC 13: a VIEW owns its own frame tree and is a pure
-- function of (VWST_ShotSnapshot, VWST_ShotGroupSettings) -> pixels. It never reads DB, the tracker, GetTime() or
-- Edit Mode state; the controller (UI\ShotGroup) and the options preview both drive it the same way.
--
-- Presentation: white charge fills left -> right over the charge part of the track and PARKS at the window
-- boundary; the window part advances only while the cast runs (snap.channelState == "casting").
-- Global showShotGCD on (SPEC 12): boundary line (red moving / white still), region block (moving -> full; stopped ->
-- drains once to the bottom and stays; blind -> full; hidden while casting), cast-through in castFillColor, and a
-- whole-bar shotFlashColor flash when the shot lands. Off: the static 60 % red window block.
local ADDON_NAME, NS = ...
local Theme, Bar = NS.Theme, NS.Bar

local ShotView_OneBar = {}
NS.ShotView_OneBar = ShotView_OneBar
ShotView_OneBar.__index = ShotView_OneBar

-- VWST_ShotView interface (SPEC 13.3): .frame, :Layout(s, w, h), :Render(snap, s, showGCD), :RenderIdle(), :SetLabel, :Show, :Hide
function ShotView_OneBar.New(parent)
  local self = setmetatable({}, ShotView_OneBar)
  self.frame = CreateFrame("Frame", nil, parent)
  self.bar = Bar.New(self.frame)
  self.bar:GetFrame():SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
  local sb = self.bar:GetFrame()
  self.block       = sb:CreateTexture(nil, "ARTWORK", nil, 1); self.block:SetColorTexture(1, 1, 1, 1)        -- GCD off: static window block
  self.boundary    = sb:CreateTexture(nil, "OVERLAY", nil, 1); self.boundary:SetColorTexture(1, 1, 1, 1)     -- GCD on: region start line
  self.regionBlock = sb:CreateTexture(nil, "ARTWORK", nil, 3); self.regionBlock:SetColorTexture(1, 1, 1, 1)  -- GCD on: the retry box
  self.flash       = sb:CreateTexture(nil, "OVERLAY", nil, 7); self.flash:SetColorTexture(1, 1, 1, 1)
  self.flash:SetAllPoints(sb); self.flash:Hide()
  self.width, self.height = 1, 1
  return self
end

function ShotView_OneBar:Layout(s, width, height)
  self.width, self.height = width, height
  self.frame:SetSize(width, height)
  self.bar:ApplyStyle({
    width = width, height = height, texture = s.texture, color = s.cooldownColor,
    textColor = s.textColor or { r = 1, g = 1, b = 1, a = 1 }, fillDirection = "fill",
    fillAnchor = "left", fontSize = s.fontSize,
  })
  local block = self.block
  block:ClearAllPoints()
  block:SetPoint("TOPRIGHT", self.bar:GetFrame(), "TOPRIGHT", 0, 0)
  block:SetHeight(height)
  Theme.ApplyColor(block, s.castWindowColor)
  block:SetAlpha(0.6)
end

function ShotView_OneBar:SetLabel(text) self.bar:SetLabel(text) end
function ShotView_OneBar:Show() self.frame:Show() end
function ShotView_OneBar:Hide() self.frame:Hide() end

function ShotView_OneBar:RenderIdle()
  self.bar:SetIdle()
  self.block:Hide(); self.boundary:Hide(); self.regionBlock:Hide(); self.flash:Hide()
  self.bar:SetSplitColor(nil)
end

-- showGCD: the controller passes Global().showShotGCD (a view does not read DB)
function ShotView_OneBar:Render(snap, s, showGCD)
  local bar, block, boundary, regionBlock, flash = self.bar, self.block, self.boundary, self.regionBlock, self.flash
  local width, height = self.width, self.height
  local cycle, window, remaining = snap.cycle, snap.window, snap.remaining
  local windowFrac = (cycle > 0 and window > 0) and math.min(1, window / cycle) or 0
  local chargeFrac = 1 - windowFrac
  local casting = snap.channelState == "casting"
  showGCD = showGCD and windowFrac > 0
  local trackProgress = snap.charge * chargeFrac + (casting and snap.castFrac * windowFrac or 0)

  bar:SetColor(s.cooldownColor)
  bar:SetProgress(trackProgress, remaining)
  local regionW = math.max(1, width * windowFrac)
  if not showGCD then
    if windowFrac > 0 then block:SetWidth(regionW); block:Show() else block:Hide() end
    boundary:Hide(); regionBlock:Hide(); bar:SetSplitColor(nil)
  else
    block:Hide()
    -- boundary line at the start of the region: red while moving, white while still (SPEC 12.9)
    boundary:ClearAllPoints()
    boundary:SetPoint("TOPRIGHT", bar:GetFrame(), "TOPRIGHT", -regionW, 0)
    boundary:SetSize(2, height)
    Theme.ApplyColor(boundary, snap.moving and s.castWindowColor or s.cooldownColor); boundary:Show()
    -- region block (SPEC 12.10): drawBlockFrac carries the moving/stopped/blind rule from the tracker
    regionBlock:ClearAllPoints()
    regionBlock:SetPoint("BOTTOMRIGHT", bar:GetFrame(), "BOTTOMRIGHT", 0, 0)
    Theme.ApplyColor(regionBlock, s.castWindowColor)
    if casting then
      regionBlock:Hide()
    else
      local f = snap.drawBlockFrac or 0
      if f <= 0.001 then regionBlock:Hide() else regionBlock:SetSize(regionW, math.max(1, height * f)); regionBlock:Show() end
    end
    -- the part of the fill past the boundary is the cast, in castFillColor
    bar:SetSplitColor(chargeFrac, s.castFillColor or s.castWindowColor)
  end

  -- shot event flash (SPEC 12.3): the whole bar
  if snap.flashFrac and snap.flashFrac > 0 and s.shotFlashColor then
    local c = s.shotFlashColor
    flash:ClearAllPoints(); flash:SetAllPoints(bar:GetFrame())
    flash:SetVertexColor(c.r, c.g, c.b, (c.a or 1) * snap.flashFrac); flash:Show()
  else
    flash:Hide()
  end
end