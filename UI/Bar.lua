-- Velocity Swing Timers: one timer bar. A StatusBar (0..1) with a spark at the fill edge, a left label
-- and a right numeric. SetProgress(p) takes 0 = swing just happened, 1 = ready; fillDirection decides
-- whether the bar grows toward ready ("fill") or drains toward it ("empty").
-- fillAnchor "left" (default) grows from the left edge like any status bar; "center" grows symmetrically
-- out of the middle (upstream WeaponSwingTimer's shot bar) - the fill is then a plain texture we size ourselves.
local ADDON_NAME, NS = ...
local Theme = NS.Theme

local Bar = {}
NS.Bar = Bar
Bar.__index = Bar

function Bar.New(parent)
  local self = setmetatable({}, Bar)
  local sb = CreateFrame("StatusBar", nil, parent)
  sb:SetMinMaxValues(0, 1)
  sb:SetValue(0)
  self.sb = sb

  self.fill = sb:CreateTexture(nil, "ARTWORK")   -- centre-anchored fill; hidden unless fillAnchor == "center"
  self.fill:Hide()

  self.spark = sb:CreateTexture(nil, "OVERLAY")
  self.spark:SetTexture(Theme.Spark)
  self.spark:SetBlendMode("ADD")
  self.spark:SetPoint("CENTER", sb:GetStatusBarTexture(), "RIGHT", 0, 0)

  self.left = Theme.Text(sb, nil, "LEFT")
  self.left:SetPoint("LEFT", sb, "LEFT", 3, 0)
  self.right = Theme.Text(sb, nil, "RIGHT")
  self.right:SetPoint("RIGHT", sb, "RIGHT", -3, 0)

  self.fillDirection = "fill"
  self.fillAnchor = "left"
  self.width = 1
  return self
end

-- VWST_BarStyle = { width, height, texture = VWST_TextureKey, color = {r,g,b,a}, textColor = {r,g,b,a},
--                   fillDirection = "fill"|"empty", fillAnchor = "left"|"center", fontSize }  (textColor.a == 0 hides text)
function Bar:ApplyStyle(st)
  self.width = st.width
  self.fillAnchor = st.fillAnchor or "left"
  self.sb:SetSize(st.width, st.height)
  local path = Theme.TexturePath(st.texture)
  self.sb:SetStatusBarTexture(path)
  local tex = self.sb:GetStatusBarTexture()
  if tex then tex:SetHorizTile(false); tex:SetVertTile(false) end
  self.fill:SetTexture(path)
  self.fill:SetHorizTile(false); self.fill:SetVertTile(false)
  self.fill:ClearAllPoints()
  self.fill:SetPoint("TOP", self.sb, "TOP", 0, 0)
  self.fill:SetHeight(st.height)
  if self.fillAnchor == "center" then
    self.sb:SetValue(0)          -- the StatusBar's own texture stays empty; self.fill does the drawing
    self.fill:Show()
  else
    self.fill:Hide()
  end
  self:SetColor(st.color)
  self.spark:SetSize(st.height * 1.6, st.height * 2.2)
  self.spark:ClearAllPoints()
  self.spark:SetPoint("CENTER", self.sb:GetStatusBarTexture(), "RIGHT", 0, 0)
  for _, fs in ipairs({ self.left, self.right }) do
    fs:SetFont(Theme.Font, st.fontSize or 10, "OUTLINE")
    Theme.ApplyColor(fs, st.textColor)
    -- SPEC 11.1: text visibility is the alpha of textColor (showText was removed)
    fs:SetShown((st.textColor.a or 1) > 0.001)
  end
  self.fillDirection = st.fillDirection or "fill"
end

-- Colour the active fill (StatusBar texture or the centre texture).
function Bar:SetColor(c)
  Theme.ApplyColor(self.sb, c)
  Theme.ApplyColor(self.fill, c)
end

function Bar:SetLabel(text) self.left:SetText(text or "") end

-- progress 0..1 (1 = ready), remaining seconds for the numeric
function Bar:SetProgress(progress, remaining)
  local v = self.fillDirection == "empty" and (1 - progress) or progress
  self.right:SetFormattedText("%.1f", remaining or 0)
  if self.fillAnchor == "center" then
    self.fill:SetWidth(math.max(0.001, v * self.width))
    self.spark:Hide()
  else
    self.sb:SetValue(v)
    self.spark:SetShown(v > 0.005 and v < 0.995)
  end
end

-- No swing in flight: show an empty track (or full, when draining) with no spark and a blank numeric.
function Bar:SetIdle()
  local v = self.fillDirection == "empty" and 0 or 1
  if self.fillAnchor == "center" then
    self.fill:SetWidth(math.max(0.001, v * self.width))
  else
    self.sb:SetValue(v)
  end
  self.right:SetText("")
  self.spark:Hide()
end

function Bar:SetPoint(...) self.sb:SetPoint(...) end
function Bar:ClearAllPoints() self.sb:ClearAllPoints() end
function Bar:SetShown(v) self.sb:SetShown(v) end
function Bar:GetFrame() return self.sb end