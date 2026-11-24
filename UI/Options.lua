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
  -- availableFn() -> false makes the box "not applicable" (SPEC 10.9): disabled, greyed label, red X instead of a
  -- check mark, and unavailableTip (string or function) as the tooltip.
  local RED_X = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
  local function Check(parent, tableFn, key, label, tip, availableFn, unavailableTip)
    local cb = CreateFrame("CheckButton", nil, parent or UIParent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText(label)
    cb.tooltipText = tip
    local xTex = cb:CreateTexture(nil, "OVERLAY"); xTex:SetTexture(RED_X); xTex:SetAllPoints(cb); xTex:Hide()
    cb:SetScript("OnClick", function(self) tableFn()[key] = self:GetChecked() and true or false; Apply() end)
    cb.Update = function(self)
      local available = not availableFn or availableFn()
      if available then
        self:SetEnabled(true)
        self.Text:SetTextColor(1, 1, 1)
        xTex:Hide()
        self.tooltipText = tip
        self:SetChecked(tableFn()[key] and true or false)
      else
        self:SetEnabled(false)
        self.Text:SetTextColor(0.5, 0.5, 0.5)
        self:SetChecked(false)
        xTex:Show()
        self.tooltipText = type(unavailableTip) == "function" and unavailableTip() or unavailableTip or tip
      end
    end
    widgets[#widgets + 1] = cb
    return cb
  end

  -- Colour swatch (SPEC 11.2): label + a 16x16 colour square over a checkerboard so alpha reads; click opens
  -- ColorPickerFrame with opacity. Writes RGBA into tableFn()[key] live while dragging; cancel restores.
  -- VWST_ColorPickerInfo is the table ColorPickerFrame:SetupColorPickerAndShow expects (same on Era and Mainline).
  local CHECKER = "Interface\\Buttons\\WHITE8X8"
  local function Swatch(parent, tableFn, key, label)
    local holder = CreateFrame("Button", nil, parent)
    local text = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); text:SetPoint("LEFT", holder, "LEFT", 0, 0); text:SetText(label .. ":")
    local frame = holder:CreateTexture(nil, "BACKGROUND"); frame:SetPoint("LEFT", text, "RIGHT", 6, 0); frame:SetSize(18, 18)
    frame:SetColorTexture(0.3, 0.3, 0.3, 1)
    local checker = holder:CreateTexture(nil, "BORDER"); checker:SetPoint("CENTER", frame); checker:SetSize(16, 16)
    checker:SetTexture(CHECKER); checker:SetVertexColor(0.6, 0.6, 0.6, 1)
    local color = holder:CreateTexture(nil, "ARTWORK"); color:SetAllPoints(checker); color:SetTexture(CHECKER)
    holder:SetSize(text:GetStringWidth() + 6 + 18, 20)
    local function Paint() local c = tableFn()[key]; color:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
    holder.Update = Paint
    holder:SetScript("OnClick", function()
      local c = tableFn()[key]
      local prev = { r = c.r, g = c.g, b = c.b, a = c.a or 1 }
      local function Write(r, g, b, a)
        local t = tableFn()[key]; t.r, t.g, t.b, t.a = r, g, b, a
        Paint(); Apply(); Options.Refresh()
      end
      local info = {
        r = c.r, g = c.g, b = c.b, opacity = c.a or 1, hasOpacity = true,
        swatchFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); Write(r, g, b, ColorPickerFrame:GetColorAlpha()) end,
        opacityFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); Write(r, g, b, ColorPickerFrame:GetColorAlpha()) end,
        cancelFunc = function() Write(prev.r, prev.g, prev.b, prev.a) end,
      }
      if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
      else
        -- very old API shape: fields on the frame itself
        ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = true, 1 - (c.a or 1)
        ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = info.swatchFunc, info.opacityFunc, info.cancelFunc
        ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
        ColorPickerFrame:Show()
      end
    end)
    holder:SetScript("OnEnter", function() frame:SetColorTexture(1, 0.82, 0, 1) end)
    holder:SetScript("OnLeave", function() frame:SetColorTexture(0.3, 0.3, 0.3, 1) end)
    widgets[#widgets + 1] = holder
    Paint()
    return holder
  end

  local function Slider(parent, name, tableFn, key, minV, maxV, step, labelFn)
    local holder = CreateFrame("Frame", nil, parent); holder:SetSize((BOX_W - 2 * PAD) / 2, 44)
    local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); label:SetPoint("TOPLEFT", 4, 0)
    local s = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -6); s:SetWidth(200)
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
    -- Two-column row (SPEC 11.3): left at the usual indent, right at the half-width mark. Either may be nil.
    -- Widgets created with a nil parent are reparented here.
    function box:AddRow(leftW, rightW, height, dy)
      dy = dy or -6
      local row = CreateFrame("Frame", nil, self); row:SetSize(BOX_W - 2 * PAD, height)
      local half = (BOX_W - 2 * PAD) / 2
      if leftW then
        if leftW:GetParent() ~= row then leftW:SetParent(row) end
        leftW:ClearAllPoints(); leftW:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
      end
      if rightW then
        if rightW:GetParent() ~= row then rightW:SetParent(row) end
        rightW:ClearAllPoints(); rightW:SetPoint("TOPLEFT", row, "TOPLEFT", half, 0)
      end
      return self:Add(row, height, dy)
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

  -- Visibility timeouts: the feature. Global.
  local vis = Section("Visibility Timeouts")
  vis:Add(Slider(vis, "VelocitySwingTimersOptInactivity", G, "inactivitySeconds", 1, 30, 1,
    function(v) return string.format("A bar is inactive after %d s without a swing or shot", v) end), 44, -10)
  vis:Add(Slider(vis, "VelocitySwingTimersOptFade", G, "fadeSeconds", 0, 1, 0.1,
    function(v) return string.format("Show / hide fade: %.1f s", v) end), 44, -10)
  vis:Finish()

  -- One section per bar group (SPEC section 11): Enable row, two slider columns, swatch row, then the
  -- group-specific preview cards (extraFn). VWST_GroupSectionSpec = { header, tableFn, prefix,
  --   enableRight = Check|nil (the right-hand Enable checkbox), swatches = { {label, key}, ... }, extraFn }
  local function GroupSection(spec)
    local sec, tableFn, prefix = Section(spec.header), spec.tableFn, spec.prefix
    -- Enable row
    sec:AddRow(Check(sec, tableFn, "enabled", "Enable", "Hard off switch for this bar group."), spec.enableRight, 26, -10)
    -- two columns: size left, opacities right
    local L1 = Slider(sec, prefix .. "Width", tableFn, "width", 100, 500, 10, function(v) return string.format("Width: %d", v) end)
    local L2 = Slider(sec, prefix .. "Height", tableFn, "height", 6, 30, 1, function(v) return string.format("Bar height: %d", v) end)
    local L3 = Slider(sec, prefix .. "Font", tableFn, "fontSize", 8, 16, 1, function(v) return string.format("Text size: %d", v) end)
    local R1 = Slider(sec, prefix .. "Inactive", tableFn, "inactiveAlpha", 0, 1, 0.05,
      function(v) if v <= 0 then return "Inactive opacity: hidden" end return string.format("Inactive opacity: %d%%", v * 100) end)
    local R2 = Slider(sec, prefix .. "OOC", tableFn, "oocAlpha", 0, 1, 0.05,
      function(v) if v <= 0 then return "Out of combat opacity: hidden" end return string.format("Out of combat opacity: %d%%", v * 100) end)
    local R3 = Slider(sec, prefix .. "Backdrop", tableFn, "backdropAlpha", 0, 1, 0.05, function(v) return string.format("Backdrop opacity: %d%%", v * 100) end)
    sec:AddRow(L1, R1, 44, -6)
    sec:AddRow(L2, R2, 44, -10)
    sec:AddRow(L3, R3, 44, -10)
    -- swatch row, immediately above the preview cards
    local row = CreateFrame("Frame", nil, sec); row:SetSize(BOX_W - 2 * PAD, 20)
    local x = 4
    for _, sw in ipairs(spec.swatches) do
      local w = Swatch(row, tableFn, sw.key, sw.label)
      w:SetPoint("LEFT", row, "LEFT", x, 0)
      x = x + w:GetWidth() + 18
    end
    sec:Add(row, 20, -10)
    if spec.extraFn then spec.extraFn(sec) end
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
      NS.Theme.ApplyGroupBackdrop(backdrop, bar:GetFrame(), s)
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

  local function MeleeStyle(parts, s, w, h)
    parts.bar:ApplyStyle({
      width = w, height = h, texture = s.texture, color = s.mainColor, textColor = s.textColor,
      fillDirection = s.fillDirection, fillAnchor = "left", fontSize = s.fontSize,
    })
    parts.bar:SetLabel("Main-Hand")
    parts.block:Hide(); parts.centerLine:Hide()
  end
  local function MeleeRender(parts, s, w, t, cycle) parts.bar:SetProgress(t / cycle, cycle - t) end

  GroupSection({
    header = "Player melee bars", tableFn = Player, prefix = "VelocitySwingTimersOptPlayer",
    enableRight = Check(nil, Player, "showOffhand", "Enable Off-hand",
      "Show a second bar for the off-hand weapon. In Edit Mode it is shown whenever this is on, so it can be placed.",
      function() return NS.SpellData.DUAL_WIELD_CLASSES[NS.Client.PlayerClass() or ""] == true end,
      function()
        local token = NS.Client.PlayerClass() or ""
        return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token) .. " cannot dual-wield."
      end),
    swatches = { { label = "Text", key = "textColor" }, { label = "Border", key = "borderColor" },
                 { label = "Main-hand", key = "mainColor" }, { label = "Off-hand", key = "offColor" } },
    extraFn = function(sec)
      PreviewCard({ section = sec, tableFn = Player, key = "fillDirection", default = "fill", value = "fill",
        caption = "Fills up toward the next swing", desc = "Empty right after a swing, full when the next one is ready.",
        style = MeleeStyle, render = MeleeRender })
      PreviewCard({ section = sec, tableFn = Player, key = "fillDirection", default = "fill", value = "empty",
        caption = "Drains toward the next swing", desc = "Full right after a swing, empty when the next one is ready.",
        style = MeleeStyle, render = MeleeRender })
    end,
  })

  local PREVIEW_WINDOW = 0.7
  local function ShotStyle(parts, s, w, h) NS.ShotGroup.StyleBar(parts, s, w, h); parts.bar:SetLabel("Auto Shot") end
  local function ShotRender(parts, s, w, t, cycle) NS.ShotGroup.RenderBar(parts, s, w, cycle - t, cycle, PREVIEW_WINDOW) end

  GroupSection({
    header = "Shot bar (Auto Shot and wand)", tableFn = Shot, prefix = "VelocitySwingTimersOptShot",
    swatches = { { label = "Text", key = "textColor" }, { label = "Border", key = "borderColor" },
                 { label = "Cooldown", key = "cooldownColor" }, { label = "Stand-still", key = "castWindowColor" } },
    extraFn = function(sec)
      PreviewCard({ section = sec, tableFn = Shot, key = "style", default = "mirrored", value = "mirrored",
        caption = "Mirrored (WeaponSwingTimer)",
        desc = "Grows from the centre. White shrinks inward while you can move or cast; red grows outward while you must stand still for the shot.",
        style = ShotStyle, render = ShotRender })
      PreviewCard({ section = sec, tableFn = Shot, key = "style", default = "mirrored", value = "onebar",
        caption = "One bar (YaHT)",
        desc = "Fills left to right over the whole cycle. The red block at the right end is the stand-still window coming up.",
        style = ShotStyle, render = ShotRender })
    end,
  })

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