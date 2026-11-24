-- Velocity Swing Timers: the mirrored shot view (upstream WeaponSwingTimer parity + the SPEC 12.8 GCD brick).
-- SPEC 13: a VIEW owns its own frame tree and is a pure function of (VWST_ShotSnapshot, VWST_ShotGroupSettings)
-- -> pixels. It never reads DB, the tracker, GetTime() or Edit Mode state.
--
-- GCD off: the fill is anchored at the centre; white shrinks into the centre line over the charge; red grows out of
--   the centre while the cast runs (upstream).
-- GCD on (SPEC 12.8): a centred BRICK the width of the window, bounded by two edge lines (red while moving, white
--   while still). White slabs fill from the OUTER ends inward and park at the brick edges. Inside the brick: the
--   retry box (moving -> full; stopped -> drains once; blind -> full; hidden while casting) and the green cast fill
--   growing out of the brick's centre to its edges. Only the brick flashes on the shot event.
local ADDON_NAME, NS = ...
local Theme, Bar = NS.Theme, NS.Bar

local ShotView_Mirrored = {}
NS.ShotView_Mirrored = ShotView_Mirrored
ShotView_Mirrored.__index = ShotView_Mirrored

-- VWST_ShotView interface (SPEC 13.3)
function ShotView_Mirrored.New(parent)
  local self = setmetatable({}, ShotView_Mirrored)
  self.frame = CreateFrame("Frame", nil, parent)
  self.bar = Bar.New(self.frame)
  self.bar:GetFrame():SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
  local sb = self.bar:GetFrame()
  self.centerLine  = sb:CreateTexture(nil, "OVERLAY");         self.centerLine:SetColorTexture(1, 1, 1, 1)   -- GCD off
  self.edgeL       = sb:CreateTexture(nil, "OVERLAY", nil, 1); self.edgeL:SetColorTexture(1, 1, 1, 1)        -- GCD on: brick edges
  self.edgeR       = sb:CreateTexture(nil, "OVERLAY", nil, 1); self.edgeR:SetColorTexture(1, 1, 1, 1)
  self.regionBlock = sb:CreateTexture(nil, "ARTWORK", nil, 3); self.regionBlock:SetColorTexture(1, 1, 1, 1)  -- GCD on: retry box
  self.castFill    = sb:CreateTexture(nil, "ARTWORK", nil, 4); self.castFill:SetColorTexture(1, 1, 1, 1)     -- GCD on: green
  self.flash       = sb:CreateTexture(nil, "OVERLAY", nil, 7); self.flash:SetColorTexture(1, 1, 1, 1); self.flash:Hide()
  self.width, self.height, self.windowFrac = 1, 1, 0
  return self
end

-- windowFrac and showGCD are LAYOUT inputs here (they decide the brick gap the Bar is built with), so the controller
-- passes them: a view does not read the tracker or DB.
function ShotView_Mirrored:Layout(s, width, height, windowFrac, showGCD)
  self.width, self.height, self.windowFrac = width, height, windowFrac or 0
  self.frame:SetSize(width, height)
  local gap = (showGCD and self.windowFrac > 0) and math.max(2, width * self.windowFrac) or 0
  self.bar:ApplyStyle({
    width = width, height = height, texture = s.texture, color = s.cooldownColor,
    textColor = s.textColor or { r = 1, g = 1, b = 1, a = 1 }, fillDirection = "fill",
    fillAnchor = "center", centerGap = gap, fontSize = s.fontSize,
  })
  local cl = self.centerLine
  cl:ClearAllPoints()
  cl:SetPoint("TOP", self.bar:GetFrame(), "TOP", 0, 0)
  cl:SetPoint("BOTTOM", self.bar:GetFrame(), "BOTTOM", 0, 0)
  cl:SetWidth(1)
  Theme.ApplyColor(cl, s.castWindowColor)
end

function ShotView_Mirrored:SetLabel(text) self.bar:SetLabel(text) end
function ShotView_Mirrored:Show() self.frame:Show() end
function ShotView_Mirrored:Hide() self.frame:Hide() end

function ShotView_Mirrored:RenderIdle()
  self.bar:SetIdle()
  self.edgeL:Hide(); self.edgeR:Hide(); self.regionBlock:Hide(); self.castFill:Hide(); self.flash:Hide()
  self.bar:SetSplitColor(nil)
end

function ShotView_Mirrored:Render(snap, s, showGCD)
  local bar = self.bar
  local width, height = self.width, self.height
  local cycle, window, remaining = snap.cycle, snap.window, snap.remaining
  local windowFrac = (cycle > 0 and window > 0) and math.min(1, window / cycle) or 0
  local casting = snap.channelState == "casting"
  showGCD = showGCD and windowFrac > 0
  local sb = bar:GetFrame()
  bar:SetSplitColor(nil)

  if not showGCD then
    -- upstream mirrored: centre line; white shrinks to it; red grows out of it while casting
    self.edgeL:Hide(); self.edgeR:Hide(); self.regionBlock:Hide(); self.castFill:Hide()
    self.centerLine:SetShown(windowFrac > 0)
    if snap.phase == "ready" and window > 0 then
      bar:SetColor(s.castWindowColor)
      bar:SetProgress(casting and snap.castFrac or 0, remaining)
    else
      bar:SetColor(s.cooldownColor)
      bar:SetProgress(1 - snap.charge, remaining)
    end
  else
    -- SPEC 12.8 brick
    self.centerLine:Hide()
    local brickW = math.max(2, width * windowFrac)
    local edge = snap.moving and s.castWindowColor or s.cooldownColor      -- SPEC 12.9: red moving / white still
    self.edgeL:ClearAllPoints(); self.edgeL:SetPoint("TOP", sb, "TOP", -brickW / 2, 0); self.edgeL:SetSize(2, height)
    self.edgeR:ClearAllPoints(); self.edgeR:SetPoint("TOP", sb, "TOP",  brickW / 2, 0); self.edgeR:SetSize(2, height)
    Theme.ApplyColor(self.edgeL, edge); Theme.ApplyColor(self.edgeR, edge)
    self.edgeL:Show(); self.edgeR:Show()
    -- white slabs fill from the outer ends toward the brick and stay full until the shot lands
    bar:SetColor(s.cooldownColor)
    bar:SetProgress(snap.charge, remaining)
    -- retry box inside the brick (SPEC 12.10): drawBlockFrac carries the moving/stopped/blind rule
    local rb = self.regionBlock
    rb:ClearAllPoints(); rb:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
    Theme.ApplyColor(rb, s.castWindowColor)
    if casting then
      rb:Hide()
    else
      local f = snap.drawBlockFrac or 0
      if f <= 0.001 then rb:Hide() else rb:SetSize(brickW, math.max(1, height * f)); rb:Show() end
    end
    -- casting: green grows out of the brick's centre to its edges
    local cf = self.castFill
    if casting and snap.castFrac > 0 then
      cf:ClearAllPoints(); cf:SetPoint("CENTER", sb, "CENTER", 0, 0)
      cf:SetSize(math.max(1, brickW * snap.castFrac), height)
      Theme.ApplyColor(cf, s.castFillColor or s.castWindowColor); cf:Show()
    else
      cf:Hide()
    end
  end

  -- shot event flash (SPEC 12.3): the brick only when GCD is on, else the whole bar
  local flash = self.flash
  if snap.flashFrac and snap.flashFrac > 0 and s.shotFlashColor then
    local c = s.shotFlashColor
    flash:ClearAllPoints()
    if showGCD then
      flash:SetPoint("CENTER", sb, "CENTER", 0, 0)
      flash:SetSize(math.max(2, width * windowFrac), height)
    else
      flash:SetAllPoints(sb)
    end
    flash:SetVertexColor(c.r, c.g, c.b, (c.a or 1) * snap.flashFrac); flash:Show()
  else
    flash:Hide()
  end
end