-- Velocity Swing Timers: the settings panel. Pattern: VelocityQuestTracker\UI\Options.lua (Section / Check /
-- Slider helpers on a scrolling canvas, Settings.RegisterCanvasLayoutCategory). Global settings live in
-- DB.Global(); per-bar-group settings in the active profile record (DB.Profile()). Texture picker lands in M7.
local ADDON_NAME, NS = ...
local Util, DB = NS.Util, NS.DB

local Options = {}
NS.Options = Options

local optionsFrame, optionsCategory
local widgets = {}

function Options.Refresh()
  for _, w in ipairs(widgets) do if w.Update then w:Update() end end
end

function Options.Open()
  if Settings and Settings.OpenToCategory and optionsCategory then Settings.OpenToCategory(optionsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory and optionsFrame then InterfaceOptionsFrame_OpenToCategory(optionsFrame); InterfaceOptionsFrame_OpenToCategory(optionsFrame) end
end

-- Every setting change re-skins the groups and wakes their activity model so a change is seen immediately.
local function Apply()
  if NS.MeleeGroup and NS.MeleeGroup.Refresh then NS.MeleeGroup.Refresh() end
  if NS.ShotGroup and NS.ShotGroup.Refresh then NS.ShotGroup.Refresh() end
end

function Options.Create()
  if optionsFrame then return end
  optionsFrame = CreateFrame("Frame", "VelocitySwingTimersOptions", UIParent)
  optionsFrame.name = "Velocity Swing Timers"
  optionsFrame:Hide()

  local scroll = CreateFrame("ScrollFrame", "VelocitySwingTimersOptionsScroll", optionsFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4); scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(620, 900)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(math.max(620, w)) end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
  end)

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16); title:SetText("Velocity Swing Timers")
  local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); sub:SetWidth(560); sub:SetJustifyH("LEFT")
  sub:SetText("Swing and shot bars that appear only while you are actually swinging or shooting, and fade once you stop. Position the bars with Edit Mode.")

  local BOX_W, PAD = 580, 10
  local last, lastDy = sub, -14
  local function Place(w, dy, dx) w:SetPoint("TOPLEFT", last, "BOTTOMLEFT", dx or 0, dy or lastDy); last = w; lastDy = -6 end

  -- tableFn() -> the settings table the key lives in (global or a profile group), resolved at access time
  local function Check(parent, tableFn, key, label, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText(label)
    cb.tooltipText = tip
    cb:SetScript("OnClick", function(self) tableFn()[key] = self:GetChecked() and true or false; Apply() end)
    cb.Update = function(self) self:SetChecked(tableFn()[key] and true or false) end
    widgets[#widgets + 1] = cb
    return cb
  end

  local function Slider(parent, name, tableFn, key, minV, maxV, step, labelFn)
    local holder = CreateFrame("Frame", nil, parent); holder:SetSize(BOX_W - 2 * PAD, 44)
    local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); label:SetPoint("TOPLEFT", 4, 0)
    local s = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -6); s:SetWidth(220)
    s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText(tostring(minV)); _G[name .. "High"]:SetText(tostring(maxV)); _G[name .. "Text"]:SetText("")
    s:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v / step + 0.5) * step
      if tableFn()[key] == v then return end
      tableFn()[key] = v; label:SetText(labelFn(v)); Apply()
    end)
    holder.Update = function() local v = tableFn()[key]; s:SetValue(v); label:SetText(labelFn(v)) end
    widgets[#widgets + 1] = holder
    return holder
  end

  local function Section(header)
    local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetWidth(BOX_W)
    if box.SetBackdrop then
      box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      box:SetBackdropColor(0, 0, 0, 0.25); box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)
    end
    local h = box:CreateFontString(nil, "ARTWORK", "GameFontNormal"); h:SetPoint("TOPLEFT", PAD, -PAD); h:SetText(header)
    box.inner_last, box.inner_h = h, PAD + 14
    function box:Add(w, height, dy, dx)
      dy = dy or -6
      w:SetPoint("TOPLEFT", self.inner_last, "BOTTOMLEFT", dx or 0, dy)
      self.inner_last, self.inner_h = w, self.inner_h - dy + height
      return w
    end
    function box:Finish() self:SetHeight(self.inner_h + PAD) end
    Place(box, -14)
    return box
  end

  local G = DB.Global
  local function Player() return DB.Profile().player end
  local function Shot() return DB.Profile().shot end

  -- Visibility: the feature. Global.
  local vis = Section("Visibility")
  vis:Add(Slider(vis, "VelocitySwingTimersOptInactivity", G, "inactivitySeconds", 1, 30, 1,
    function(v) return string.format("A bar hides after %d s without a swing or shot", v) end), 44, -10)
  vis:Add(Slider(vis, "VelocitySwingTimersOptFade", G, "fadeSeconds", 0, 1, 0.1,
    function(v) return string.format("Show / hide fade: %.1f s", v) end), 44, -10)
  vis:Add(Slider(vis, "VelocitySwingTimersOptFont", G, "fontSize", 8, 16, 1,
    function(v) return string.format("Bar text size: %d", v) end), 44, -10)
  vis:Finish()

  -- One section per bar group; the same set of controls.
  local function GroupSection(header, tableFn, prefix, extraFn)
    local sec = Section(header)
    sec:Add(Check(sec, tableFn, "enabled", "Enable", "Hard off switch for this bar group."), 26, -10)
    sec:Add(Slider(sec, prefix .. "Width", tableFn, "width", 100, 500, 10, function(v) return string.format("Width: %d", v) end), 44, -6)
    sec:Add(Slider(sec, prefix .. "Height", tableFn, "height", 6, 30, 1, function(v) return string.format("Bar height: %d", v) end), 44, -10)
    sec:Add(Slider(sec, prefix .. "OOC", tableFn, "oocAlpha", 0, 1, 0.05,
      function(v) if v <= 0 then return "Out of combat: hidden" end return string.format("Out of combat opacity (while recently active): %d%%", v * 100) end), 44, -10)
    sec:Add(Slider(sec, prefix .. "Backdrop", tableFn, "backdropAlpha", 0, 1, 0.05, function(v) return string.format("Backdrop opacity: %d%%", v * 100) end), 44, -10)
    sec:Add(Check(sec, tableFn, "showBorder", "Show border", nil), 26, -10)
    sec:Add(Check(sec, tableFn, "showText", "Show text", "The hand label on the left and the countdown on the right."), 26)
    if extraFn then extraFn(sec) end
    sec:Finish()
    return sec
  end

  GroupSection("Player melee bars", Player, "VelocitySwingTimersOptPlayer", function(sec)
    sec:Add(Check(sec, Player, "showOffhand", "Show off-hand bar", "When a weapon is equipped in the off hand."), 26)
    -- fill direction as a pair of radios
    local radios = {}
    local function Radio(mode, label, tip)
      local r = CreateFrame("CheckButton", nil, sec, "UIRadioButtonTemplate"); r:SetSize(16, 16)
      r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", r, "RIGHT", 4, 0); r.text:SetText(label)
      r.tooltipText = tip
      r:SetScript("OnClick", function() Player().fillDirection = mode; for _, o in ipairs(radios) do o:SetChecked(o.mode == mode) end; Apply() end)
      r.mode = mode
      r.Update = function(self) self:SetChecked((Player().fillDirection or "fill") == mode) end
      widgets[#widgets + 1] = r; radios[#radios + 1] = r
      return r
    end
    local lbl = sec:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); lbl:SetText("Bar direction")
    sec:Add(lbl, 14, -10, 4)
    sec:Add(Radio("fill", "fills up toward the next swing", "Empty right after a swing, full when the next one is ready."), 16, -4, 4)
    sec:Add(Radio("empty", "drains toward the next swing", "Full right after a swing, empty when the next one is ready."), 16, -4, 4)
  end)

  GroupSection("Shot bar (Auto Shot and wand)", Shot, "VelocitySwingTimersOptShot", function(sec)
    sec:Add(Check(sec, Shot, "oneBar", "One bar (YaHT style)", "One bar fills over the whole shot cycle and the stand-still window is marked at its end. Unticked: the bar drains while you are free to move, then turns red and refills while you must stand still."), 26)
  end)

  -- Reset
  StaticPopupDialogs["VELOCITYSWINGTIMERS_RESET_ALL"] = {
    text = "Reset ALL Velocity Swing Timers settings?\n\nEvery setting and every layout profile is wiped and the UI reloads.",
    button1 = "Reset everything", button2 = CANCEL or "Cancel", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, showAlert = true,
    OnAccept = function() VelocitySwingTimersDB = nil; ReloadUI() end,
  }
  local rs = Section("Reset")
  local resetAll = CreateFrame("Button", nil, rs, "UIPanelButtonTemplate"); resetAll:SetSize(160, 22); resetAll:SetText("Reset all settings...")
  resetAll:SetScript("OnClick", function() StaticPopup_Show("VELOCITYSWINGTIMERS_RESET_ALL") end)
  rs:Add(resetAll, 22, -10, 4)
  rs:Finish()

  content:SetHeight(-select(5, last:GetPoint(1)) + last:GetHeight() + 60)
  optionsFrame:SetScript("OnShow", function()
    Options.Refresh()
    local top = content:GetTop(); local bottom = last:GetBottom()
    if top and bottom then content:SetHeight(top - bottom + 40) end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsFrame, "Velocity Swing Timers")
    Settings.RegisterAddOnCategory(optionsCategory)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(optionsFrame)
  end
end