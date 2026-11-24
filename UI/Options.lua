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
  if Options.Reflow then Options.Reflow() end
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
  local sections = {}
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
      Options.Refresh()   -- preview cards redraw at the new size and the sections reflow
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
    box.inner_last, box.inner_h, box.items = h, PAD + 14, {}
    -- Add(w, height, dy, dx): height may be a number (fixed) or a function() -> number (re-measured by Finish)
    function box:Add(w, height, dy, dx)
      dy = dy or -6
      w:SetPoint("TOPLEFT", self.inner_last, "BOTTOMLEFT", dx or 0, dy)
      self.items[#self.items + 1] = { height = height, dy = dy }
      self.inner_last = w
      return w
    end
    -- Re-callable: cards with a live preview bar change height when the user drags the size sliders.
    function box:Finish()
      local total = PAD + 14
      for _, it in ipairs(self.items) do
        local hgt = type(it.height) == "function" and it.height() or it.height
        total = total - it.dy + hgt
      end
      self:SetHeight(total + PAD)
    end
    sections[#sections + 1] = box
    Place(box, -14)
    return box
  end

  -- After any Update() pass the sections re-measure (card heights follow the size sliders) and the canvas re-fits.
  local function Reflow()
    for _, s in ipairs(sections) do s:Finish() end
    local top = content:GetTop(); local bottom = last:GetBottom()
    if top and bottom then content:SetHeight(top - bottom + 40) end
  end
  Options.Reflow = Reflow

  local G = DB.Global
  local function Player() return DB.Profile().player end
  local function Shot() return DB.Profile().shot end

  -- Visibility: the feature. Global.
  local vis = Section("Visibility")
  vis:Add(Slider(vis, "VelocitySwingTimersOptInactivity", G, "inactivitySeconds", 1, 30, 1,
    function(v) return string.format("A bar is inactive after %d s without a swing or shot", v) end), 44, -10)
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
    sec:Add(Slider(sec, prefix .. "Inactive", tableFn, "inactiveAlpha", 0, 1, 0.05,
      function(v) if v <= 0 then return "Inactive opacity: hidden" end return string.format("Inactive opacity: %d%%", v * 100) end), 44, -10)
    sec:Add(Slider(sec, prefix .. "OOC", tableFn, "oocAlpha", 0, 1, 0.05,
      function(v) if v <= 0 then return "Out of combat opacity: hidden" end return string.format("Out of combat opacity: %d%%", v * 100) end), 44, -10)
    sec:Add(Slider(sec, prefix .. "Backdrop", tableFn, "backdropAlpha", 0, 1, 0.05, function(v) return string.format("Backdrop opacity: %d%%", v * 100) end), 44, -10)
    sec:Add(Check(sec, tableFn, "showBorder", "Show border", nil), 26, -10)
    sec:Add(Check(sec, tableFn, "showText", "Show text", "The hand label on the left and the countdown on the right."), 26)
    if extraFn then extraFn(sec) end
    sec:Finish()
    return sec
  end

  -- A clickable "radio card": radio + caption + wrapped description + a live, looping preview bar drawn by the
  -- caller's render function. Several cards for the same setting form the picker; clicking one writes its value.
  -- VWST_PreviewCardSpec = {
  --   section, tableFn, key, default, value, caption, desc,
  --   style(parts, settingsOverlay, width, height)       -- one-time styling, called from Update()
  --   render(parts, settingsOverlay, width, t, cycle)    -- per-frame; t = seconds into the fake cycle
  -- }
  local PREVIEW_W, PREVIEW_H, PREVIEW_CYCLE = 260, 12, 3.0
  local cardGroups = {}   -- key -> { cards } so siblings refresh together on click
  local function PreviewCard(spec)
    local sec, tableFn, key, value = spec.section, spec.tableFn, spec.key, spec.value
    local holder = CreateFrame("Button", nil, sec, BackdropTemplateMixin and "BackdropTemplate" or nil)
    local holderW = BOX_W - 2 * PAD - 8
    holder:SetWidth(holderW)
    if holder.SetBackdrop then
      holder:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      holder:SetBackdropColor(0, 0, 0, 0.25)
    end
    local radio = CreateFrame("CheckButton", nil, holder, "UIRadioButtonTemplate"); radio:SetSize(16, 16)
    radio:SetPoint("TOPLEFT", 8, -8); radio:EnableMouse(false)
    local cap = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); cap:SetPoint("LEFT", radio, "RIGHT", 4, 0); cap:SetText(spec.caption)
    local desc = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); desc:SetPoint("TOPLEFT", radio, "BOTTOMLEFT", 0, -2)
    desc:SetWidth(holderW - 16); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true); desc:SetText(spec.desc); desc:SetTextColor(0.8, 0.8, 0.8)
    local bar = NS.Bar.New(holder)
    local inset = NS.Theme.BackdropInset
    bar:GetFrame():SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 2 + inset, -8 - inset)
    bar:GetFrame():EnableMouse(false)
    -- same backdrop frame the live groups draw around their bars (MeleeGroup / ShotGroup Layout), so the
    -- preview shows the real border / backdrop opacity settings
    local backdrop = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    backdrop:SetFrameLevel(bar:GetFrame():GetFrameLevel())
    bar:GetFrame():SetFrameLevel(backdrop:GetFrameLevel() + 1)
    backdrop:SetPoint("TOPLEFT", bar:GetFrame(), "TOPLEFT", -inset, inset)
    backdrop:SetPoint("BOTTOMRIGHT", bar:GetFrame(), "BOTTOMRIGHT", inset, -inset)
    local block = bar:GetFrame():CreateTexture(nil, "ARTWORK", nil, 1); block:SetColorTexture(1, 0, 0, 1)
    local centerLine = bar:GetFrame():CreateTexture(nil, "OVERLAY"); centerLine:SetColorTexture(1, 1, 1, 1)
    local parts = { bar = bar, block = block, centerLine = centerLine }
    holder.t = 0
    -- the preview is drawn at the group's REAL width/height (width capped to what fits in the card), so the sizing
    -- sliders show their effect here too; the card re-fits its height to the bar
    local maxBarW = holderW - 24
    local function FitSize(s)
      holder.previewW = math.min(s.width or PREVIEW_W, maxBarW - 2 * inset)
      holder.previewH = s.height or PREVIEW_H
      holder:SetHeight(8 + 16 + 2 + desc:GetStringHeight() + 8 + holder.previewH + 2 * inset + 10)
    end
    FitSize(tableFn())
    holder.Update = function(self)
      local s = tableFn()
      local selected = (s[key] or spec.default) == value
      radio:SetChecked(selected)
      FitSize(s)
      -- the card previews ITS value with the user's other settings (colours, texture)
      self.overlay = setmetatable({ [key] = value }, { __index = s })
      spec.style(parts, self.overlay, self.previewW, self.previewH)
      backdrop:SetBackdrop(s.showBorder and NS.Theme.Backdrop or NS.Theme.BackdropNoBorder)
      backdrop:SetBackdropColor(0, 0, 0, s.backdropAlpha or 0)
      backdrop:SetBackdropBorderColor(1, 1, 1, (s.backdropAlpha or 0) > 0 and 1 or 0)
      if self.SetBackdropBorderColor then
        if selected then self:SetBackdropBorderColor(1, 0.82, 0, 1) else self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6) end
      end
    end
    holder:SetScript("OnClick", function()
      tableFn()[key] = value
      for _, c in ipairs(cardGroups[key]) do c:Update() end
      Apply()
    end)
    holder:SetScript("OnEnter", function(self) if self.SetBackdropColor then self:SetBackdropColor(0.2, 0.2, 0.2, 0.4) end end)
    holder:SetScript("OnLeave", function(self) if self.SetBackdropColor then self:SetBackdropColor(0, 0, 0, 0.25) end end)
    -- looping fake cycle; only ticks while the panel is on screen
    holder:SetScript("OnUpdate", function(self, dt)
      self.t = (self.t + dt) % PREVIEW_CYCLE
      if self.overlay then spec.render(parts, self.overlay, self.previewW, self.t, PREVIEW_CYCLE) end
    end)
    widgets[#widgets + 1] = holder
    cardGroups[key] = cardGroups[key] or {}
    table.insert(cardGroups[key], holder)
    -- the first card indents 4 under the header label; later cards anchor to the previous card, so no extra dx
    local dx = #cardGroups[key] == 1 and 4 or 0
    sec:Add(holder, function() return holder:GetHeight() end, -6, dx)
    return holder
  end

  GroupSection("Player melee bars", Player, "VelocitySwingTimersOptPlayer", function(sec)
    sec:Add(Check(sec, Player, "showOffhand", "Show off-hand bar", "When a weapon is equipped in the off hand."), 26)
    local lbl = sec:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); lbl:SetText("Bar direction (click one)")
    sec:Add(lbl, 14, -10, 4)
    local function MeleeStyle(parts, s, w, h)
      parts.bar:ApplyStyle({
        width = w, height = h, texture = s.texture, color = s.mainColor, textColor = s.textColor,
        showText = s.showText, fillDirection = s.fillDirection, fillAnchor = "left", fontSize = DB.Global().fontSize,
      })
      parts.bar:SetLabel("Main-Hand")
      parts.block:Hide(); parts.centerLine:Hide()
    end
    local function MeleeRender(parts, s, w, t, cycle)
      parts.bar:SetProgress(t / cycle, cycle - t)
    end
    PreviewCard({ section = sec, tableFn = Player, key = "fillDirection", default = "fill", value = "fill",
      caption = "Fills up toward the next swing", desc = "Empty right after a swing, full when the next one is ready.",
      style = MeleeStyle, render = MeleeRender })
    PreviewCard({ section = sec, tableFn = Player, key = "fillDirection", default = "fill", value = "empty",
      caption = "Drains toward the next swing", desc = "Full right after a swing, empty when the next one is ready.",
      style = MeleeStyle, render = MeleeRender })
  end)

  GroupSection("Shot bar (Auto Shot and wand)", Shot, "VelocitySwingTimersOptShot", function(sec)
    local lbl = sec:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); lbl:SetText("Bar style (click one)")
    sec:Add(lbl, 14, -10, 4)
    local PREVIEW_WINDOW = 0.7
    local function ShotStyle(parts, s, w, h)
      NS.ShotGroup.StyleBar(parts, s, w, h)
      parts.bar:SetLabel("Auto Shot")
    end
    local function ShotRender(parts, s, w, t, cycle)
      NS.ShotGroup.RenderBar(parts, s, w, cycle - t, cycle, PREVIEW_WINDOW)
    end
    PreviewCard({ section = sec, tableFn = Shot, key = "style", default = "mirrored", value = "mirrored",
      caption = "Mirrored (WeaponSwingTimer)",
      desc = "Grows from the centre. White shrinks inward while you can move or cast; red grows outward while you must stand still for the shot.",
      style = ShotStyle, render = ShotRender })
    PreviewCard({ section = sec, tableFn = Shot, key = "style", default = "mirrored", value = "onebar",
      caption = "One bar (YaHT)",
      desc = "Fills left to right over the whole cycle. The red block at the right end is the stand-still window coming up.",
      style = ShotStyle, render = ShotRender })
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