-- Velocity Swing Timers: textures, fonts, backdrop. Blizzard stock art only (SPEC section 9.2).
-- Statusbar textures: a built-in set that exists on every client we ship to, plus LibSharedMedia-3.0's
-- statusbar list when that library happens to be loaded by another addon (optional dependency, not embedded).
local ADDON_NAME, NS = ...

local Theme = {}
NS.Theme = Theme

Theme.Font = "Fonts\\FRIZQT__.TTF"
Theme.Spark = "Interface\\CastingBar\\UI-CastingBar-Spark"
Theme.Backdrop = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
Theme.BackdropNoBorder = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  tile = true, tileSize = 16,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
Theme.BackdropInset = 4   -- backdrop frame extends this far beyond the bars

-- VWST_TextureKey -> path. Order matters for the picker.
Theme.BUILTIN_TEXTURES = {
  { key = "Blizzard",                      path = "Interface\\TargetingFrame\\UI-StatusBar" },
  { key = "Blizzard Character Skills Bar", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
  { key = "Blizzard Raid Bar",             path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { key = "Blizzard Cast Bar",             path = "Interface\\CastingBar\\UI-CastingBar-Bar" },
  { key = "Solid",                         path = "Interface\\Buttons\\WHITE8X8" },
}
Theme.DEFAULT_TEXTURE = "Blizzard"

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- Path for a key; falls back to the default when the key is unknown (e.g. a SharedMedia pack was removed).
function Theme.TexturePath(key)
  for _, t in ipairs(Theme.BUILTIN_TEXTURES) do if t.key == key then return t.path end end
  local lsm = LSM()
  if lsm then
    local p = lsm:Fetch("statusbar", key, true)
    if p then return p end
  end
  return Theme.BUILTIN_TEXTURES[1].path
end

-- Every selectable texture: { {key, path}, ... } built-ins first, then SharedMedia sorted by name.
function Theme.TextureList()
  local out, seen = {}, {}
  for _, t in ipairs(Theme.BUILTIN_TEXTURES) do out[#out + 1] = t; seen[t.key] = true end
  local lsm = LSM()
  if lsm then
    local names = {}
    for name, path in pairs(lsm:HashTable("statusbar")) do
      if not seen[name] then names[#names + 1] = { key = name, path = path } end
    end
    table.sort(names, function(a, b) return a.key < b.key end)
    for _, t in ipairs(names) do out[#out + 1] = t end
  end
  return out
end

function Theme.Text(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Theme.Font, size or 10, "OUTLINE")   -- real size comes from Bar:ApplyStyle (per-group fontSize)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

function Theme.ApplyColor(obj, c)
  if obj.SetTextColor then obj:SetTextColor(c.r, c.g, c.b, c.a or 1)
  elseif obj.SetStatusBarColor then obj:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
  elseif obj.SetVertexColor then obj:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
end

-- The backdrop frame every bar group draws behind its bars (and the options previews copy). SPEC 11.1:
-- backdropAlpha is the fill; borderColor is the border, alpha 0 = no border at all.
-- VWST_GroupBackdropSettings = { backdropAlpha, borderColor = {r,g,b,a} }
function Theme.ApplyGroupBackdrop(backdrop, anchorFrame, s)
  local inset = Theme.BackdropInset
  local bc = s.borderColor or { r = 1, g = 1, b = 1, a = 1 }
  local hasBorder = (bc.a or 1) > 0.001
  -- SPEC 15: when the shot history strip is on, the backdrop grows on that side so the strip sits inside the border
  local extraTop, extraBottom = 0, 0
  if s.showHistory ~= false and s.historyPosition ~= nil then
    local grow = (Theme.HISTORY_HEIGHT or 2) + (Theme.HISTORY_GAP or 1)
    if s.historyPosition == "top" then extraTop = grow else extraBottom = grow end
  end
  backdrop:ClearAllPoints()
  backdrop:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", -inset, inset + extraTop)
  backdrop:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", inset, -inset - extraBottom)
  backdrop:SetBackdrop(hasBorder and Theme.Backdrop or Theme.BackdropNoBorder)
  backdrop:SetBackdropColor(0, 0, 0, s.backdropAlpha or 0)
  if hasBorder then backdrop:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a) end
end

-- SPEC 12.20 action-block tri-colour (free / invading / blocked). Pre-12.20 records carried one actionBlockColor;
-- it is used as the blocked colour when the new keys are absent so an old profile still draws.
-- VWST_ActionBlockColorTriple = cFree, cInvading, cBlocked (each {r,g,b,a})
local DEFAULT_FREE, DEFAULT_INVADING, DEFAULT_BLOCKED =
  { r = 0.2, g = 0.85, b = 0.2, a = 0.6 }, { r = 1.0, g = 0.85, b = 0.0, a = 0.6 }, { r = 0.8, g = 0.0, b = 0.0, a = 0.6 }
function Theme.ActionBlockColors(s)
  return s.actionFreeColor or DEFAULT_FREE,
         s.actionInvadingColor or DEFAULT_INVADING,
         s.actionBlockedColor or s.actionBlockColor or s.castWindowColor or DEFAULT_BLOCKED
end

-- SPEC 15 shot history strip: shared painter so both shot views draw the same oscilloscope. The view owns a
-- VWST_HistoryStrip = { frame, cols = { Texture... }, spark = Texture, lastPainted = { state... }, width, height }
-- created by Theme.NewHistoryStrip(parent) and laid out by Theme.LayoutHistoryStrip(strip, bar, s, width).
-- Theme.PaintHistoryStrip(strip, hist, s) only touches columns whose state changed since the last paint.
Theme.HISTORY_HEIGHT = 2
Theme.HISTORY_GAP = 1      -- px between the bar edge and the strip
function Theme.NewHistoryStrip(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetClipsChildren(false)
  local strip = { frame = f, cols = {}, lastPainted = {}, width = 1, height = Theme.HISTORY_HEIGHT, count = 0 }
  strip.spark = f:CreateTexture(nil, "OVERLAY", nil, 2); strip.spark:SetColorTexture(1, 1, 1, 1); strip.spark:Hide()
  f:Hide()
  return strip
end

-- position = "bottom" | "top"; anchors the strip to the bar frame's edge with HISTORY_GAP
function Theme.LayoutHistoryStrip(strip, barFrame, position, width, count)
  local f = strip.frame
  strip.width, strip.count = width, count
  f:ClearAllPoints()
  if position == "top" then
    f:SetPoint("BOTTOMLEFT", barFrame, "TOPLEFT", 0, Theme.HISTORY_GAP)
  else
    f:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", 0, -Theme.HISTORY_GAP)
  end
  f:SetSize(width, Theme.HISTORY_HEIGHT)
  -- one texture per column, laid out once; a column is width/count wide (sub-pixel is fine, textures accumulate)
  local colW = width / count
  for i = 1, count do
    local t = strip.cols[i]
    if not t then t = f:CreateTexture(nil, "ARTWORK"); t:SetColorTexture(1, 1, 1, 1); strip.cols[i] = t end
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * colW, 0); t:SetSize(math.max(colW, 1), Theme.HISTORY_HEIGHT)
    t:Hide()
  end
  for i = count + 1, #strip.cols do strip.cols[i]:Hide() end
  strip.spark:ClearAllPoints(); strip.spark:SetSize(1, Theme.HISTORY_HEIGHT)
  wipe(strip.lastPainted)   -- force a full repaint after relayout
end

-- hist = VWST_ShotHistorySnapshot { columns, head, count }; s = shot settings (cooldownColor / castWindowColor)
function Theme.PaintHistoryStrip(strip, hist, s)
  local dim, lost = s.cooldownColor, s.castWindowColor
  local count = math.min(hist.count, strip.count)
  local cols, last = strip.cols, strip.lastPainted
  for i = 1, count do
    local st = hist.columns[i] or 0
    if last[i] ~= st then
      last[i] = st
      local t = cols[i]
      if st == 2 then t:SetVertexColor(lost.r, lost.g, lost.b, 0.8); t:Show()
      elseif st == 1 then t:SetVertexColor(dim.r, dim.g, dim.b, 0.25); t:Show()
      else t:Hide() end
    end
  end
  -- the spark glides on the exact time fraction (headFrac), not the column index: column-quantised it hopped once
  -- per column (~60 ms on a 6-shot span) and read as jitter next to the per-frame cast bar (owner 2026-11-26)
  strip.spark:ClearAllPoints()
  strip.spark:SetPoint("TOPLEFT", strip.frame, "TOPLEFT", (hist.headFrac or ((hist.head - 1) / count)) * strip.width, 0)
  strip.spark:SetVertexColor(dim.r, dim.g, dim.b, 1); strip.spark:Show()
end

function Theme.HideHistoryStrip(strip) strip.frame:Hide() end
function Theme.ShowHistoryStrip(strip) strip.frame:Show() end