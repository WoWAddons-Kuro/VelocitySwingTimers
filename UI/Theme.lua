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
  -- SPEC 15.7: the shot history strip sits OUTSIDE the border (owner 2026-11-26); the backdrop does not grow for it
  backdrop:ClearAllPoints()
  backdrop:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", -inset, inset)
  backdrop:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", inset, -inset)
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
-- VWST_HistoryStrip = { frame, cols = { Texture... }, width, height, count }
-- created by Theme.NewHistoryStrip(parent) and laid out by Theme.LayoutHistoryStrip(strip, bar, s, width).
-- SPEC 15.7 (owner 2026-11-26): no spark. The head is implied by the FADE: every column's alpha falls with its age
-- behind the head and reaches zero one shot period before the head comes round to overwrite it. So the newest
-- writing is brightest, the ring dissolves behind the head, and there is a clean empty gap ahead of it.
Theme.HISTORY_HEIGHT = 2
Theme.HISTORY_GAP = 2      -- px between the group backdrop's OUTER edge and the strip (the strip is outside the border)
function Theme.NewHistoryStrip(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetClipsChildren(false)
  local strip = { frame = f, cols = {}, width = 1, height = Theme.HISTORY_HEIGHT, count = 0 }
  f:Hide()
  return strip
end

-- position = "bottom" | "top"; the strip sits OUTSIDE the group backdrop: bar edge + BackdropInset + HISTORY_GAP
function Theme.LayoutHistoryStrip(strip, barFrame, position, width, count)
  local f = strip.frame
  strip.width, strip.count = width, count
  local off = Theme.BackdropInset + Theme.HISTORY_GAP
  f:ClearAllPoints()
  if position == "top" then
    f:SetPoint("BOTTOMLEFT", barFrame, "TOPLEFT", 0, off)
  else
    f:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", 0, -off)
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
end

-- hist = VWST_ShotHistorySnapshot { columns, head, headFrac, count, periods }; s = shot settings
-- Column states (SPEC 15.7): 0 nothing | 1 normal cycling (medium grey) | 2 lost (castWindowColor)
--                            3 out of range (dark grey) | 4 melee range (white)
-- Alpha = base alpha of the state x fade(age), where age = how far behind the head the column is, in fractions of
-- the ring; fade is 1 at the head and 0 at (1 - 1/periods) - i.e. one shot period ahead of the head is already gone.
local HISTORY_BASE = {
  [1] = { r = 0.55, g = 0.55, b = 0.55, a = 0.55 },
  [3] = { r = 0.30, g = 0.30, b = 0.30, a = 0.70 },
  [4] = { r = 1.00, g = 1.00, b = 1.00, a = 0.80 },
}
function Theme.PaintHistoryStrip(strip, hist, s)
  local lost = s.castWindowColor
  local count = math.min(hist.count, strip.count)
  local cols = strip.cols
  local headFrac = hist.headFrac or ((hist.head - 1) / count)
  local periods = hist.periods or 6
  local fadeSpan = math.max(0.05, 1 - 1 / periods)     -- fraction of the ring over which a column fades to nothing
  for i = 1, count do
    local st = hist.columns[i] or 0
    local t = cols[i]
    if st == 0 then
      t:Hide()
    else
      local colFrac = (i - 0.5) / count
      local age = (headFrac - colFrac) % 1                 -- 0 = just written, -> 1 = about to be overwritten
      local fade = 1 - age / fadeSpan
      if fade <= 0 then
        t:Hide()
      else
        local c = st == 2 and lost or HISTORY_BASE[st] or HISTORY_BASE[1]
        t:SetVertexColor(c.r, c.g, c.b, (st == 2 and 0.85 or c.a) * fade); t:Show()
      end
    end
  end
end

function Theme.HideHistoryStrip(strip) strip.frame:Hide() end
function Theme.ShowHistoryStrip(strip) strip.frame:Show() end