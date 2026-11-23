-- Velocity Weapon Swing Timers: one timer bar. A StatusBar (0..1) with a spark at the fill edge, a left label
-- and a right numeric. SetProgress(p) takes 0 = swing just happened, 1 = ready; fillDirection decides
-- whether the bar grows toward ready ("fill") or drains toward it ("empty").
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

  self.spark = sb:CreateTexture(nil, "OVERLAY")
  self.spark:SetTexture(Theme.Spark)
  self.spark:SetBlendMode("ADD")
  self.spark:SetPoint("CENTER", sb:GetStatusBarTexture(), "RIGHT", 0, 0)

  self.left = Theme.Text(sb, nil, "LEFT")
  self.left:SetPoint("LEFT", sb, "LEFT", 3, 0)
  self.right = Theme.Text(sb, nil, "RIGHT")
  self.right:SetPoint("RIGHT", sb, "RIGHT", -3, 0)

  self.fillDirection = "fill"
  return self
end

-- VWST_BarStyle = { width, height, texture = VWST_TextureKey, color = {r,g,b,a}, textColor = {r,g,b,a},
--                   showText = bool, fillDirection = "fill"|"empty", fontSize }
function Bar:ApplyStyle(st)
  self.sb:SetSize(st.width, st.height)
  self.sb:SetStatusBarTexture(Theme.TexturePath(st.texture))
  Theme.ApplyColor(self.sb, st.color)
  local tex = self.sb:GetStatusBarTexture()
  if tex then tex:SetHorizTile(false); tex:SetVertTile(false) end
  self.spark:SetSize(st.height * 1.6, st.height * 2.2)
  self.spark:ClearAllPoints()
  self.spark:SetPoint("CENTER", self.sb:GetStatusBarTexture(), "RIGHT", 0, 0)
  for _, fs in ipairs({ self.left, self.right }) do
    fs:SetFont(Theme.Font, st.fontSize or NS.DB.Global().fontSize, "OUTLINE")
    Theme.ApplyColor(fs, st.textColor)
    fs:SetShown(st.showText ~= false)
  end
  self.fillDirection = st.fillDirection or "fill"
end

function Bar:SetLabel(text) self.left:SetText(text or "") end

-- progress 0..1 (1 = ready), remaining seconds for the numeric
function Bar:SetProgress(progress, remaining)
  local v = self.fillDirection == "empty" and (1 - progress) or progress
  self.sb:SetValue(v)
  self.right:SetFormattedText("%.1f", remaining or 0)
  self.spark:SetShown(v > 0.005 and v < 0.995)
end

-- No swing in flight: show an empty track (or full, when draining) with no spark and a blank numeric.
function Bar:SetIdle()
  self.sb:SetValue(self.fillDirection == "empty" and 0 or 1)
  self.right:SetText("")
  self.spark:Hide()
end

function Bar:SetPoint(...) self.sb:SetPoint(...) end
function Bar:ClearAllPoints() self.sb:ClearAllPoints() end
function Bar:SetShown(v) self.sb:SetShown(v) end
function Bar:GetFrame() return self.sb end