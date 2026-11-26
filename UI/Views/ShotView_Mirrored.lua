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
  -- SPEC 12.14: blocks and the chasing white may extend past the bar; nothing here may clip
  self.frame:SetClipsChildren(false); sb:SetClipsChildren(false)
  self.fillOverrun = sb:CreateTexture(nil, "ARTWORK", nil, 2); self.fillOverrun:SetColorTexture(1, 1, 1, 1); self.fillOverrun:Hide()
  self.actionPool = {}
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
  self.fillOverrun:Hide()
  for _, slot in ipairs(self.actionPool) do slot.texL:Hide(); slot.texR:Hide(); slot.icon:Hide(); slot.flashL:Hide(); slot.flashR:Hide(); slot.tailL:Hide(); slot.tailR:Hide() end
end

function ShotView_Mirrored:Render(snap, s, showGCD, showActions, showActionIcon)
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

  self:RenderActionBlocks(snap, s, showGCD, windowFrac, showActions, showActionIcon)
end

-- SPEC 12.14 action blocks on the FOLDED timeline. The mirrored bar runs time from both outer ends toward the
-- centre: charge fraction c (0..1 of the charge part) sits at x = c*slabMax from the left edge and mirrored from the
-- right. The brick (window) is the centre; time past readyAt grows OUT of the centre, so an overrun past shotEnd
-- continues past the brick edges over the (already full) white slabs - and past the bar ends if it is long enough.
-- Each block is therefore TWO textures (left/right mirror); the icon sits on the left copy only.
local ACTION_ICON_MAX, ACTION_ICON_MIN = 16, 8
function ShotView_Mirrored:RenderActionBlocks(snap, s, showGCD, windowFrac, showActions, showActionIcon)
  local pool = self.actionPool
  local blocks = (showActions ~= false) and snap.actionBlocks or nil
  local sb = self.bar:GetFrame()
  local width, height = self.width, self.height
  local chargeFrac = 1 - windowFrac
  local brickW = showGCD and math.max(2, width * windowFrac) or 0
  local slabMax = (width - brickW) / 2
  -- timeline fraction f (of the whole cycle) -> distance from the LEFT edge on the left slab (mirrored on the right).
  -- Charge part: f/chargeFrac * slabMax. Window/overrun part: slabMax + (f - chargeFrac)/windowFrac * (brickW/2) ...
  -- i.e. past readyAt the geometry continues out of the centre at the window's own scale.
  local function X(f)
    if f <= chargeFrac or windowFrac <= 0 then
      return (chargeFrac > 0 and f / chargeFrac or 1) * slabMax
    end
    return slabMax + ((f - chargeFrac) / windowFrac) * (brickW / 2)
  end
  -- white chase past the brick: fillFrac > chargeFrac means the slabs are full and the white continues out of the
  -- centre over the brick (and beyond), drawn as one centred texture
  local overrun = self.fillOverrun
  if blocks and snap.fillFrac and snap.fillFrac > chargeFrac then
    local half = X(snap.fillFrac) - slabMax
    overrun:ClearAllPoints(); overrun:SetPoint("CENTER", sb, "CENTER", 0, 0)
    overrun:SetSize(math.max(1, half * 2), height)
    Theme.ApplyColor(overrun, s.cooldownColor); overrun:Show()
  else
    overrun:Hide()
  end
  local n = blocks and #blocks or 0
  for i = 1, math.max(n, #pool) do
    local slot = pool[i]
    if i <= n then
      if not slot then
        slot = { texL = sb:CreateTexture(nil, "BACKGROUND", nil, 5), texR = sb:CreateTexture(nil, "BACKGROUND", nil, 5),
                 tex2L = sb:CreateTexture(nil, "BACKGROUND", nil, 5), tex2R = sb:CreateTexture(nil, "BACKGROUND", nil, 5),
                 icon = sb:CreateTexture(nil, "OVERLAY", nil, 2),
                 flashL = sb:CreateTexture(nil, "OVERLAY", nil, 6), flashR = sb:CreateTexture(nil, "OVERLAY", nil, 6),
                 tailL = sb:CreateTexture(nil, "BACKGROUND", nil, 4), tailR = sb:CreateTexture(nil, "BACKGROUND", nil, 4) }
        for _, t in pairs({ slot.texL, slot.texR, slot.tex2L, slot.tex2R, slot.flashL, slot.flashR, slot.tailL, slot.tailR }) do t:SetColorTexture(1, 1, 1, 1) end
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pool[i] = slot
      end
      local b = blocks[i]
      local x0, x1 = X(b.xStart), X(b.xEnd)
      local w = math.max(1, x1 - x0)
      -- SPEC 12.20 tri-colour, folded: head [x0, xr) in free / invading, tail [max(x0, xr), x1) in blocked; each
      -- segment is a left copy growing rightward from its start and a right copy growing leftward from the mirror
      local cFree, cInv, cBlk = Theme.ActionBlockColors(s)
      local xr = X(b.xReady or chargeFrac)
      local c = b.verdict == "free" and cFree or (b.verdict == "invading" and cInv or cBlk)
      local splitAt = b.verdict == "free" and x1 or math.max(x0, math.min(x1, xr))   -- SPEC 12.22: free = whole span in the head colour, no red tail
      local wHead, wTail = splitAt - x0, x1 - splitAt
      local function Place(tL, tR, xs, ws, col)
        tL:ClearAllPoints(); tL:SetPoint("TOPLEFT",  sb, "TOPLEFT",  xs, 0);  tL:SetSize(ws, height)
        tR:ClearAllPoints(); tR:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -xs, 0); tR:SetSize(ws, height)
        tL:SetVertexColor(col.r, col.g, col.b, col.a or 0.6); tR:SetVertexColor(col.r, col.g, col.b, col.a or 0.6)
        tL:Show(); tR:Show()
      end
      if b.live then
        if wHead > 0.5 then Place(slot.texL, slot.texR, x0, wHead, c) else slot.texL:Hide(); slot.texR:Hide() end
        if wTail > 0.5 then Place(slot.tex2L, slot.tex2R, splitAt, wTail, cBlk) else slot.tex2L:Hide(); slot.tex2R:Hide() end
        slot.flashL:Hide(); slot.flashR:Hide()
        -- cast blocks: the faint 0.5 s retry tail after the cast, folded like the block itself
        if b.xTailEnd and b.xTailEnd > b.xEnd then
          local tx1 = X(b.xTailEnd)
          local tw = math.max(1, tx1 - x1)
          local ct = x1 >= xr and cBlk or c
          slot.tailL:ClearAllPoints(); slot.tailL:SetPoint("TOPLEFT",  sb, "TOPLEFT",  x1, 0);  slot.tailL:SetSize(tw, height)
          slot.tailR:ClearAllPoints(); slot.tailR:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -x1, 0); slot.tailR:SetSize(tw, height)
          local ta = (ct.a or 0.6) * 0.4
          slot.tailL:SetVertexColor(ct.r, ct.g, ct.b, ta); slot.tailR:SetVertexColor(ct.r, ct.g, ct.b, ta)
          slot.tailL:Show(); slot.tailR:Show()
        else
          slot.tailL:Hide(); slot.tailR:Hide()
        end
      else
        slot.texL:Hide(); slot.texR:Hide(); slot.tex2L:Hide(); slot.tex2R:Hide(); slot.tailL:Hide(); slot.tailR:Hide()
        local f = s.shotFlashColor or c
        local a = (f.a or 1) * (b.flashFrac or 0)
        slot.flashL:ClearAllPoints(); slot.flashL:SetPoint("TOPLEFT",  sb, "TOPLEFT",  x0, 0);  slot.flashL:SetSize(w, height)
        slot.flashR:ClearAllPoints(); slot.flashR:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -x0, 0); slot.flashR:SetSize(w, height)
        slot.flashL:SetVertexColor(f.r, f.g, f.b, a); slot.flashR:SetVertexColor(f.r, f.g, f.b, a)
        slot.flashL:Show(); slot.flashR:Show()
      end
      local iconSize = math.min(height, w, ACTION_ICON_MAX)
      if b.live and showActionIcon ~= false and iconSize >= ACTION_ICON_MIN then
        local texID = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spellID))
          or (GetSpellTexture and GetSpellTexture(b.spellID))
        if texID then
          slot.icon:SetTexture(texID)
          slot.icon:ClearAllPoints(); slot.icon:SetPoint("LEFT", sb, "LEFT", x0 + 1, 0)
          slot.icon:SetSize(iconSize, iconSize); slot.icon:SetAlpha(c.a or 0.6); slot.icon:Show()
        else slot.icon:Hide() end
      else
        slot.icon:Hide()
      end
    elseif slot then
      slot.texL:Hide(); slot.texR:Hide(); slot.tex2L:Hide(); slot.tex2R:Hide(); slot.icon:Hide(); slot.flashL:Hide(); slot.flashR:Hide(); slot.tailL:Hide(); slot.tailR:Hide()
    end
  end
end