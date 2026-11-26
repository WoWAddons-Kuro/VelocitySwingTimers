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
  -- SPEC 12.14: blocks and the chasing white may extend past the bar; nothing here may clip
  self.frame:SetClipsChildren(false); sb:SetClipsChildren(false)
  self.fillOverrun = sb:CreateTexture(nil, "ARTWORK", nil, 2); self.fillOverrun:SetColorTexture(1, 1, 1, 1); self.fillOverrun:Hide()
  self.actionPool = {}
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
  self.fillOverrun:Hide()
  for _, slot in ipairs(self.actionPool) do slot.tex:Hide(); slot.icon:Hide(); slot.flash:Hide(); slot.tail:Hide() end
end

-- showGCD: the controller passes Global().showShotGCD (a view does not read DB)
function ShotView_OneBar:Render(snap, s, showGCD, showActions, showActionIcon)
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

  self:RenderActionBlocks(snap, s, showActions, showActionIcon)
end

-- SPEC 12.14 action blocks. Each VWST_ActionBlockDraw is a span in bar-width fractions, drawn at xStart*W .. xEnd*W
-- on the bar frame with NO clipping - an overrun past 1.0 sticks out of the right edge ("what the hell are you
-- doing"). The white charge chases the furthest live block via snap.fillFrac (> 1 = past the edge): the StatusBar
-- cannot exceed its own width, so the overrun part of the white is a second texture continuing from the right edge.
-- A spell icon sits at the block's start, sized min(barHeight, blockWidth, ACTION_ICON_MAX), omitted under the min.
local ACTION_ICON_MAX, ACTION_ICON_MIN = 16, 8
function ShotView_OneBar:RenderActionBlocks(snap, s, showActions, showActionIcon)
  local pool = self.actionPool
  local blocks = (showActions ~= false) and snap.actionBlocks or nil
  local sb = self.bar:GetFrame()
  local width, height = self.width, self.height
  -- white chase past the right edge
  local overrun = self.fillOverrun
  if blocks and snap.fillFrac and snap.fillFrac > 1 then
    overrun:ClearAllPoints()
    overrun:SetPoint("TOPLEFT", sb, "TOPRIGHT", 0, 0)
    overrun:SetSize(math.max(1, (snap.fillFrac - 1) * width), height)
    Theme.ApplyColor(overrun, s.cooldownColor); overrun:Show()
  else
    overrun:Hide()
  end
  local n = blocks and #blocks or 0
  for i = 1, math.max(n, #pool) do
    local slot = pool[i]
    if i <= n then
      if not slot then
        slot = { tex = sb:CreateTexture(nil, "BACKGROUND", nil, 5), icon = sb:CreateTexture(nil, "OVERLAY", nil, 2),
                 flash = sb:CreateTexture(nil, "OVERLAY", nil, 6), tail = sb:CreateTexture(nil, "BACKGROUND", nil, 4) }
        slot.tex:SetColorTexture(1, 1, 1, 1); slot.flash:SetColorTexture(1, 1, 1, 1)
        slot.tail:SetColorTexture(1, 1, 1, 1)
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pool[i] = slot
      end
      local b = blocks[i]
      local x0, x1 = b.xStart * width, b.xEnd * width
      local w = math.max(1, x1 - x0)
      slot.tex:ClearAllPoints()
      slot.tex:SetPoint("TOPLEFT", sb, "TOPLEFT", x0, 0)
      slot.tex:SetSize(w, height)
      local c = s.actionBlockColor or s.castWindowColor
      if b.live then
        slot.tex:SetVertexColor(c.r, c.g, c.b, c.a or 0.85); slot.tex:Show()
        slot.flash:Hide()
        -- cast blocks: the 0.5 s retry tail the engine MAY add after the cast, drawn at 40 % of the block alpha
        if b.xTailEnd and b.xTailEnd > b.xEnd then
          local tw = (b.xTailEnd - b.xEnd) * width
          slot.tail:ClearAllPoints(); slot.tail:SetPoint("TOPLEFT", sb, "TOPLEFT", x1, 0); slot.tail:SetSize(math.max(1, tw), height)
          slot.tail:SetVertexColor(c.r, c.g, c.b, (c.a or 0.85) * 0.4); slot.tail:Show()
        else
          slot.tail:Hide()
        end
      else
        -- ended: the block itself is gone; its rect flashes shotFlashColor and fades
        slot.tex:Hide()
        slot.tail:Hide()
        local f = s.shotFlashColor or c
        slot.flash:ClearAllPoints(); slot.flash:SetPoint("TOPLEFT", sb, "TOPLEFT", x0, 0); slot.flash:SetSize(w, height)
        slot.flash:SetVertexColor(f.r, f.g, f.b, (f.a or 1) * (b.flashFrac or 0)); slot.flash:Show()
      end
      -- icon: best fit of block height/width, capped; omitted when the block is too short to label
      local iconSize = math.min(height, w, ACTION_ICON_MAX)
      if b.live and showActionIcon ~= false and iconSize >= ACTION_ICON_MIN then
        local texID = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spellID))
          or (GetSpellTexture and GetSpellTexture(b.spellID))
        if texID then
          slot.icon:SetTexture(texID)
          slot.icon:ClearAllPoints()
          slot.icon:SetPoint("LEFT", sb, "LEFT", x0 + 1, 0)
          slot.icon:SetSize(iconSize, iconSize)
          slot.icon:SetAlpha(c.a or 0.85); slot.icon:Show()
        else slot.icon:Hide() end
      else
        slot.icon:Hide()
      end
    elseif slot then
      slot.tex:Hide(); slot.icon:Hide(); slot.flash:Hide(); slot.tail:Hide()
    end
  end
end