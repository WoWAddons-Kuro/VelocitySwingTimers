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
  vis:Add(Check(vis, G, "showShotGCD", "Show shot GCD",
    "While Auto Shot is ready: the window turns solid red while you move, shows the game's half-second retry timer as a lowering red box while you stand still, and fills green while the shot is casting."), 26, -6)
  vis:Add(Check(vis, G, "showShotActions", "Show shot ability blocks",
    "Draw the GCD or cast of each shot ability (Arcane Shot, Serpent Sting, Aimed Shot, Multi-Shot...) on the bar from the moment you use it, so you can see when it pushes your Auto Shot. Overruns are drawn past the end of the bar on purpose."), 26, -2)
  vis:Add(Check(vis, G, "showShotActionIcon", "Show spell icon on blocking cast inset",
    "A small spell icon at the start of each ability block.",
    function() return G().showShotActions ~= false end, "Turn on \"Show shot ability blocks\" first."), 26, -2, 20)

  -- SPEC 14: range-entry weapon sound. Checkbox default is per flavour (Era on, Forever off - Forever has it natively)
  -- so nil in the DB means "flavour default"; the Check widget needs a real boolean, hence the resolver table.
  local isForever = NS.Client.flavour == "forever"
  local rangeG = setmetatable({}, { __index = function(_, k)
      if k == "rangeEntrySound" then local v = G().rangeEntrySound; if v == nil then return not isForever end return v end
      return G()[k]
    end, __newindex = function(_, k, v) G()[k] = v end })
  local function RangeG() return rangeG end
  vis:Add(Check(vis, RangeG, "rangeEntrySound", "Play weapon sound when target comes into range (out of combat)",
    (isForever and "WoW Forever already plays the bow-draw / gun-cock itself when a target comes into range. Turn this on to use our sound instead. "
                or "Bow-draw / gun-cock when a hostile target comes into Auto Shot range from far away - the same cue WoW Forever plays. Hear that you can shoot instead of watching the bar. ")
    .. "Plays once per target while you are out of combat."), 26, -6)
  vis:Add(Check(vis, G, "rangeEntrySoundInCombat", "...also while in combat",
    "Also play the cue during combat, every time the target comes back into range from far away (kiting). Off by default: in combat the game cannot tell "
    .. "\"just outside 35 yards\" from \"inside the 8-yard deadzone\", so a mob stepping out of melee and back can trigger it too."), 26, -2, 20)
  -- the cue spell: WeakAuras-style text box + OK (SPEC 14.2a). Accepts an ID, a chat link, or a name you KNOW.
  local row = CreateFrame("Frame", nil, vis); row:SetSize(BOX_W - 2 * PAD, 24)
  local lbl = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); lbl:SetPoint("LEFT", row, "LEFT", 24, 0); lbl:SetText("Range spell:")
  local icon = row:CreateTexture(nil, "ARTWORK"); icon:SetSize(18, 18); icon:SetPoint("LEFT", lbl, "RIGHT", 6, 0); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate"); box:SetSize(170, 20); box:SetPoint("LEFT", icon, "RIGHT", 8, 0); box:SetAutoFocus(false)
  local ok = CreateFrame("Button", nil, row, "UIPanelButtonTemplate"); ok:SetSize(40, 20); ok:SetText("OK"); ok:SetPoint("LEFT", box, "RIGHT", 6, 0)
  local note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); note:SetPoint("LEFT", ok, "RIGHT", 8, 0); note:SetWidth(170); note:SetJustifyH("LEFT")
  local function RangeCueTable() local p = DB.Profile(); p.rangeCue = p.rangeCue or { spellID = 75 }; return p.rangeCue end
  local function ShowSpell(id)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    local name, tex = info and info.name, info and info.iconID
    if not name and GetSpellInfo then local n, _, t = GetSpellInfo(id); name, tex = n, t end
    icon:SetTexture(tex or 134400); box:SetText(name and string.format("%s (%d)", name, id) or tostring(id))
    note:SetText(""); box:SetCursorPosition(0)
  end
  local function Resolve(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    local id = tonumber(text) or tonumber(text:match("spell:(%d+)") or "")
    if id then return id end
    local n = text:match("^(.-)%s*%(%d+%)$") or text   -- "Arcane Shot (3044)" back to the name
    if n == "" then return nil end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(n)
    if info and info.spellID then return info.spellID end
    if GetSpellInfo then local _, _, _, _, _, _, sid = GetSpellInfo(n); if sid then return sid end end
    -- SPEC 14.2a: the name form must work on ANY localized client - the player types the name as their client shows
    -- it and we produce the number. Scan the spellbook (case-insensitive) when the lookup APIs do not take a name.
    local want = n:lower()
    local function ScanClassic()
      if not GetNumSpellTabs or not GetSpellBookItemName then return nil end
      for tab = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for i = offset + 1, offset + count do
          local name, _, sid = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
          if not sid and GetSpellBookItemInfo then local _, s2 = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell"); sid = s2 end
          if name and name:lower() == want and sid then return sid end
        end
      end
    end
    local function ScanMainline()
      if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then return nil end
      for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if li then
          for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
            local si = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
            if si and si.name and si.name:lower() == want and si.spellID then return si.spellID end
          end
        end
      end
    end
    local sid = ScanClassic() or ScanMainline()
    if sid then return sid end
    return nil
  end
  local function Commit()
    local id = Resolve(box:GetText())
    if id then RangeCueTable().spellID = id; ShowSpell(id)
    else note:SetText("|cffff4040not in your spellbook / unknown|r"); ShowSpell(RangeCueTable().spellID) end
    box:ClearFocus()
  end
  ok:SetScript("OnClick", Commit); box:SetScript("OnEnterPressed", Commit); box:SetScript("OnEscapePressed", function() ShowSpell(RangeCueTable().spellID); box:ClearFocus() end)
  row.Update = function() ShowSpell(RangeCueTable().spellID) end
  widgets[#widgets + 1] = row
  vis:Add(row, 24, -4)
  -- preview buttons (SPEC 14.2 TBD-A): hear the candidate sound for each weapon kind
  local pv = CreateFrame("Frame", nil, vis); pv:SetSize(BOX_W - 2 * PAD, 22)
  local pl = pv:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); pl:SetPoint("LEFT", pv, "LEFT", 24, 0); pl:SetText("Preview sound:")
  local pb = CreateFrame("Button", nil, pv, "UIPanelButtonTemplate"); pb:SetSize(70, 22); pb:SetText("Bow"); pb:SetPoint("LEFT", pl, "RIGHT", 8, 0)
  local pg = CreateFrame("Button", nil, pv, "UIPanelButtonTemplate"); pg:SetSize(70, 22); pg:SetText("Gun"); pg:SetPoint("LEFT", pb, "RIGHT", 6, 0)
  pb:SetScript("OnClick", function() NS.RangeCue.Preview("bow") end); pg:SetScript("OnClick", function() NS.RangeCue.Preview("gun") end)
  vis:Add(pv, 22, -4)
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
    -- owner 2026-11-26: active / inactive / out-of-combat opacity, defaults 70 % / hidden / hidden
    local function Pct(name) return function(v) if v <= 0 then return name .. ": hidden" end return string.format("%s: %d%%", name, v * 100) end end
    local R0 = Slider(sec, prefix .. "Active", tableFn, "activeAlpha", 0.05, 1, 0.05, Pct("Active opacity"))
    local R1 = Slider(sec, prefix .. "Inactive", tableFn, "inactiveAlpha", 0, 1, 0.05, Pct("Inactive opacity"))
    local R2 = Slider(sec, prefix .. "OOC", tableFn, "oocAlpha", 0, 1, 0.05, Pct("Out of combat opacity"))
    local R3 = Slider(sec, prefix .. "Backdrop", tableFn, "backdropAlpha", 0, 1, 0.05, function(v) return string.format("Backdrop opacity: %d%%", v * 100) end)
    sec:AddRow(L1, R0, 44, -6)
    sec:AddRow(L2, R1, 44, -10)
    sec:AddRow(L3, R2, 44, -10)
    sec:AddRow(nil, R3, 44, -10)
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

  -- A clickable "radio card": radio + caption + wrapped description + a live, looping preview drawn by a REAL view
  -- instance (SPEC 13) - the same class the live bar uses - so the preview can never drift from the live pixels.
  -- Several cards for the same setting form the picker; clicking one writes its value.
  -- VWST_PreviewCardSpec = {
  --   section, tableFn, key, default, value, caption, desc,
  --   viewClass                                          -- NS.ShotView_* / NS.MeleeView_*; .New(parent) -> view
  --   layout(view, settingsOverlay, width, height)       -- called from Update(); wraps view:Layout with preview inputs
  --   render(view, settingsOverlay, width, t, cycle)     -- per-frame; t = seconds into the fake cycle
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
    local view = spec.viewClass.New(holder)
    local vf = view.frame
    local inset = NS.Theme.BackdropInset
    vf:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 2 + inset, -8 - inset)
    vf:EnableMouse(false)
    -- same backdrop frame the live groups draw around their bars (MeleeGroup / ShotGroup Layout), so the
    -- preview shows the real border / backdrop opacity settings
    local backdrop = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    backdrop:SetFrameLevel(vf:GetFrameLevel())
    vf:SetFrameLevel(backdrop:GetFrameLevel() + 1)
    backdrop:SetPoint("TOPLEFT", vf, "TOPLEFT", -inset, inset)
    backdrop:SetPoint("BOTTOMRIGHT", vf, "BOTTOMRIGHT", inset, -inset)
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
      spec.layout(view, self.overlay, self.previewW, self.previewH)
      NS.Theme.ApplyGroupBackdrop(backdrop, vf, s)
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
      if self.overlay then spec.render(view, self.overlay, self.previewW, self.t, PREVIEW_CYCLE) end
    end)
    widgets[#widgets + 1] = holder
    cardGroups[key] = cardGroups[key] or {}
    table.insert(cardGroups[key], holder)
    -- the first card indents 4 under the header label; later cards anchor to the previous card, so no extra dx
    local dx = #cardGroups[key] == 1 and 4 or 0
    sec:Add(holder, function() return holder:GetHeight() end, -6, dx)
    return holder
  end

  -- melee preview: one hand, a plain looping swing
  local function MeleeLayout(view, s, w, h) view:Layout(s, w, h, false) end
  local function MeleeRender(view, s, w, t, cycle)
    view:Render({ mainhand = { remaining = cycle - t, speed = cycle, progress = t / cycle } }, s)
  end

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
        viewClass = NS.MeleeView_Hands, layout = MeleeLayout, render = MeleeRender })
      PreviewCard({ section = sec, tableFn = Player, key = "fillDirection", default = "fill", value = "empty",
        caption = "Drains toward the next swing", desc = "Full right after a swing, empty when the next one is ready.",
        viewClass = NS.MeleeView_Hands, layout = MeleeLayout, render = MeleeRender })
    end,
  })

  -- SPEC 13: the shot preview cards host a real ShotView each and feed it ShotTracker.ScriptedSnapshot - the same
  -- view code and the same snapshot vocabulary as the live bar. One clean cycle per loop (SPEC 12.21): white charges,
  -- parks at the brick, shot lands at the wrap, brick flashes.
  local PREVIEW_WINDOW = 0.7
  local function ShotRender(view, s, w, t, cycle)
    view:Render(NS.ShotTracker.ScriptedSnapshot(t, cycle, PREVIEW_WINDOW), s, DB.Global().showShotGCD ~= false)
  end
  local function ShotLayout(view, s, w, h)
    view:Layout(s, w, h, PREVIEW_WINDOW / PREVIEW_CYCLE, DB.Global().showShotGCD ~= false)
    view:SetLabel("Auto Shot")
  end

  GroupSection({
    header = "Shot bar (Auto Shot and wand)", tableFn = Shot, prefix = "VelocitySwingTimersOptShot",
    swatches = { { label = "Text", key = "textColor" }, { label = "Border", key = "borderColor" },
                 { label = "Charge", key = "cooldownColor" }, { label = "Window", key = "castWindowColor" },
                 { label = "Casting", key = "castFillColor" }, { label = "Shot", key = "shotFlashColor" },
                 -- SPEC 12.20: an instant / cast block is green when it ends before the window, yellow+red when it crosses it
                 { label = "Free", key = "actionFreeColor" }, { label = "Invading", key = "actionInvadingColor" }, { label = "Blocked", key = "actionBlockedColor" } },
    extraFn = function(sec)
      PreviewCard({ section = sec, tableFn = Shot, key = "style", default = "mirrored", value = "mirrored",
        caption = "Mirrored (WeaponSwingTimer)",
        desc = "Grows from the centre. White shrinks inward while you can move or cast; red grows outward while you must stand still for the shot.",
        viewClass = NS.ShotView_Mirrored, layout = ShotLayout, render = ShotRender })
      PreviewCard({ section = sec, tableFn = Shot, key = "style", default = "mirrored", value = "onebar",
        caption = "One bar (YaHT)",
        desc = "Fills left to right over the whole cycle. The red block at the right end is the stand-still window coming up.",
        viewClass = NS.ShotView_OneBar, layout = ShotLayout, render = ShotRender })
    end,
  })

  -- Reset
  StaticPopupDialogs["VELOCITYSWINGTIMERS_RESET_ALL"] = {
    text = "Reset ALL Velocity Swing Timers settings?\n\nEvery setting and every layout profile is wiped and the UI reloads.",
    button1 = "Reset everything", button2 = CANCEL or "Cancel", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, showAlert = true,
    OnAccept = function() VelocitySwingTimersDB = nil; ReloadUI() end,
  }
  local rs = Section("Extras")
  rs:Add(Check(rs, G, "debugTimerPrediction", "Enable Timer Prediction Debug Messages",
    "Prints to chat whenever the shot bar's prediction of the game's Auto Shot retry tick or cast was wrong, with a short log of the preceding shot events. Noisy; for diagnosing timer drift."), 26, -10)
  -- Diagnostic dumps as buttons, sharing the exact /vwst command callables (VWST_Commands) so chat and panel agree.
  -- VWST_DumpButtonSpec = { label, command = key into NS.Commands, tip }
  local DUMPS = {
    { label = "Status",         command = "status",   tip = "/vwst status - versions, speeds, features, tracker and group state" },
    { label = "Shot events",    command = "events",   tip = "/vwst events - the last 10 seconds of shot events" },
    { label = "Instants",       command = "instants", tip = "/vwst instants - auto-shot delay by where an instant was pressed" },
    { label = "Presses",        command = "presses",  tip = "/vwst presses - what became of each instant press" },
    { label = "Reset instants", command = "instantsReset", tip = "Clear the /vwst instants histogram" },
    { label = "Reset presses",  command = "pressesReset",  tip = "Clear the /vwst presses histogram" },
  }
  local dumpRow = CreateFrame("Frame", nil, rs); dumpRow:SetSize(BOX_W - 2 * PAD, 22)
  local dx = 4
  for _, d in ipairs(DUMPS) do
    local b = CreateFrame("Button", nil, dumpRow, "UIPanelButtonTemplate"); b:SetSize(92, 22); b:SetText(d.label)
    b:SetPoint("LEFT", dumpRow, "LEFT", dx, 0); dx = dx + 96
    b.tooltipText = d.tip
    b:SetScript("OnClick", function() local fn = NS.Commands and NS.Commands[d.command]; if fn then fn() end end)
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  rs:Add(dumpRow, 22, -10)
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