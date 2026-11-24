-- Velocity Swing Timers: the shot group - Auto Shot / wand Shoot bar. Bound to Core\ShotTracker and Core\Activity.
--
-- Two presentations, VWST_ShotBarStyle (upstream WeaponSwingTimer parity, see its Images\*Explained*.png):
--   "mirrored" : fill anchored at the CENTRE. cooldownColor (white) shrinks into the middle over the cooldown part
--                of the cycle ("can move or cast"); then castWindowColor (red) grows out of the middle over the
--                stand-still window ("don't move or cast"). Wands have no window, so they only ever shrink.
--   "onebar"   : YaHT style - fills left to right over the whole cycle; the window is a fixed castWindowColor block
--                at the right end so you see it coming.
-- The hunter cast bar (Aimed / Multi-Shot) is M5 and hangs under this frame.
local ADDON_NAME, NS = ...
local Util, Theme, Bar, ShotTracker, DB = NS.Util, NS.Theme, NS.Bar, NS.ShotTracker, NS.DB

local ShotGroup = {}
NS.ShotGroup = ShotGroup

local frame, backdrop, shotBar, windowBlock, activity
local driver = CreateFrame("Frame")   -- OnUpdate lives here: a hidden frame never ticks, and the group frame IS hidden when idle
local ticking = false

local function Settings() return DB.Profile().shot end

-- Style a Bar + its window block for shot settings s. Shared with the options-panel preview, hence module level.
-- VWST_ShotBarParts = { bar = Bar, block = Texture }
function ShotGroup.StyleBar(parts, s, width, height)
  local style = s.style or "mirrored"
  parts.bar:ApplyStyle({
    width = width, height = height, texture = s.texture, color = s.cooldownColor,
    textColor = s.textColor or { r = 1, g = 1, b = 1, a = 1 }, fillDirection = "fill",
    fillAnchor = style == "mirrored" and "center" or "left", fontSize = s.fontSize,
  })
  local block, centerLine = parts.block, parts.centerLine
  block:ClearAllPoints()
  block:SetPoint("TOPRIGHT", parts.bar:GetFrame(), "TOPRIGHT", 0, 0)
  block:SetHeight(height)
  Theme.ApplyColor(block, s.castWindowColor)
  block:SetAlpha(0.6)
  -- mirrored only: a thin castWindowColor line at the centre, the point the fill shrinks into / grows out of
  if centerLine then
    centerLine:ClearAllPoints()
    centerLine:SetPoint("TOP", parts.bar:GetFrame(), "TOP", 0, 0)
    centerLine:SetPoint("BOTTOM", parts.bar:GetFrame(), "BOTTOM", 0, 0)
    centerLine:SetWidth(1)
    Theme.ApplyColor(centerLine, s.castWindowColor)
    centerLine:SetShown(style == "mirrored")
  end
end

-- Draw one instant of a shot cycle from a VWST_ShotSnapshot (ShotTracker.Snapshot). Pure, so the options preview
-- can feed scripted snapshots. Rule for every style (owner 2026-11-24): the charge fill reaches the window boundary
-- and STOPS there; the window part only advances while the cast is actually running (snap.channelState == "casting").
-- Moving or GCD-blocked while ready -> the fill sits at the boundary.
-- SPEC 12 (Global().showShotGCD): the window region additionally shows WHY it is parked - solid red while moving,
-- a bottom-anchored red box whose height is the remaining 0.5 s retry block while still, and the fill continues
-- through the region in castFillColor while the cast runs. The whole bar flashes shotFlashColor when the shot lands.
function ShotGroup.RenderBar(parts, s, width, snap)
  local bar, block, boundary, regionBlock, flash = parts.bar, parts.block, parts.boundary, parts.regionBlock, parts.flash
  local style = s.style or "mirrored"
  local cycle, window, remaining = snap.cycle, snap.window, snap.remaining
  local windowFrac = (cycle > 0 and window > 0) and math.min(1, window / cycle) or 0
  local chargeFrac = 1 - windowFrac
  local casting = snap.channelState == "casting"
  local showGCD = DB.Global().showShotGCD ~= false and windowFrac > 0
  local state = snap.channelState
  local height = bar:GetFrame():GetHeight()
  -- fill position over the whole track: charge part, then the window part only while casting
  local trackProgress = snap.charge * chargeFrac + (casting and snap.castFrac * windowFrac or 0)
  if style == "onebar" then
    bar:SetColor(s.cooldownColor)
    bar:SetProgress(trackProgress, remaining)
    local regionW = math.max(1, width * windowFrac)
    if not showGCD then
      -- checkbox off: the static red block, exactly as before
      if windowFrac > 0 then block:SetWidth(regionW); block:Show() else block:Hide() end
      boundary:Hide(); regionBlock:Hide(); bar:SetSplitColor(nil)
    else
      block:Hide()
      -- boundary line at the start of the region
      boundary:ClearAllPoints()
      boundary:SetPoint("TOPRIGHT", bar:GetFrame(), "TOPRIGHT", -regionW, 0)
      boundary:SetSize(2, height)
      Theme.ApplyColor(boundary, s.castWindowColor); boundary:Show()
      -- region block: solid while moving, lowering while still+blocked, gone while casting / charging
      regionBlock:ClearAllPoints()
      regionBlock:SetPoint("BOTTOMRIGHT", bar:GetFrame(), "BOTTOMRIGHT", 0, 0)
      Theme.ApplyColor(regionBlock, s.castWindowColor)
      if state == "blocked_moving" then
        regionBlock:SetSize(regionW, height); regionBlock:Show()
      elseif state == "blocked_still" then
        local h = math.max(1, height * snap.blockFrac)
        regionBlock:SetSize(regionW, h); regionBlock:Show()
      else
        regionBlock:Hide()
      end
      -- the part of the fill past the boundary is the cast, in castFillColor
      bar:SetSplitColor(chargeFrac, s.castFillColor or s.castWindowColor)
    end
  else
    block:Hide()
    -- mirrored: the centre line is the boundary; region = everything beyond charge == 1
    boundary:Hide()
    if snap.phase == "ready" and window > 0 then
      if showGCD then
        -- GCD on: cast grows from the centre in castFillColor; red box = block state (full width, height = blockFrac)
        bar:SetColor(s.castFillColor or s.castWindowColor)
        bar:SetProgress(casting and snap.castFrac or 0, remaining)
        regionBlock:ClearAllPoints()
        regionBlock:SetPoint("BOTTOM", bar:GetFrame(), "BOTTOM", 0, 0)
        Theme.ApplyColor(regionBlock, s.castWindowColor)
        if state == "blocked_moving" then regionBlock:SetSize(width, height); regionBlock:Show()
        elseif state == "blocked_still" then regionBlock:SetSize(width, math.max(1, height * snap.blockFrac)); regionBlock:Show()
        else regionBlock:Hide() end
      else
        -- window: red grows out of the centre ONLY while the cast runs; stalled/blocked sits at zero
        bar:SetColor(s.castWindowColor)
        bar:SetProgress(casting and snap.castFrac or 0, remaining)
        regionBlock:Hide()
      end
    else
      -- free to move: white shrinks into the centre over the cooldown part
      bar:SetColor(s.cooldownColor)
      bar:SetProgress(1 - snap.charge, remaining)
      regionBlock:Hide()
    end
    bar:SetSplitColor(nil)
  end
  -- shot event flash (SPEC 12.3), both styles
  if flash then
    if snap.flashFrac and snap.flashFrac > 0 and s.shotFlashColor then
      local c = s.shotFlashColor
      flash:SetVertexColor(c.r, c.g, c.b, (c.a or 1) * snap.flashFrac); flash:Show()
    else flash:Hide() end
  end
end

local parts   -- VWST_ShotBarParts for the live bar

-- Build the VWST_ShotBarParts bundle around a Bar: the static one-bar window block, the mirrored centre line, and the
-- SPEC 12 GCD textures (boundary line + region block). Used by the live bar and by each options preview card.
function ShotGroup.NewParts(bar, block, centerLine)
  local sb = bar:GetFrame()
  block = block or sb:CreateTexture(nil, "ARTWORK", nil, 1)
  centerLine = centerLine or sb:CreateTexture(nil, "OVERLAY")
  local boundary = sb:CreateTexture(nil, "OVERLAY", nil, 1); boundary:SetColorTexture(1, 1, 1, 1)
  local regionBlock = sb:CreateTexture(nil, "ARTWORK", nil, 3); regionBlock:SetColorTexture(1, 1, 1, 1)
  -- the flash sits on top of everything and is faded by alpha
  local flash = sb:CreateTexture(nil, "OVERLAY", nil, 7); flash:SetColorTexture(1, 1, 1, 1); flash:SetAllPoints(sb); flash:Hide()
  return { bar = bar, block = block, centerLine = centerLine, boundary = boundary, regionBlock = regionBlock, flash = flash }
end

local function Layout()
  local s = Settings()
  ShotGroup.StyleBar(parts, s, s.width, s.height)
  frame:SetSize(s.width, s.height)
  shotBar:ClearAllPoints(); shotBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  shotBar:SetLabel(ShotTracker.IsHunter() and "Auto Shot" or "Shoot")

  Theme.ApplyGroupBackdrop(backdrop, frame, s)
end

local function Place()
  local s = Settings()
  frame:ClearAllPoints()
  frame:SetPoint(s.point or "CENTER", UIParent, s.point or "CENTER", s.x or 0, s.y or 0)
end

local function Draw(now)
  local s = Settings()
  local snap = ShotTracker.Snapshot(now)
  if not snap then
    shotBar:SetIdle(); windowBlock:Hide()
    return
  end
  ShotGroup.RenderBar(parts, s, s.width, snap)
end

local function OnUpdate(_, dt)
  local now = GetTime()
  local visible = activity:Tick(now, dt)
  if visible or NS.editModeActive then
    if NS.editModeActive then
      -- a frozen sample: 60% charged on a 2.5 s cycle, no window
      local s = Settings()
      local cycle = ShotTracker.state.speed or 2.5
      ShotGroup.RenderBar(parts, s, s.width, { phase = "charging", channelState = "idle", charge = 0.6,
        blockFrac = 0, castFrac = 0, flashFrac = 0, remaining = cycle * 0.4, cycle = cycle, window = 0 })
    else
      Draw(now)
    end
  elseif not activity:IsActive(now) then
    ShotGroup.StopTicking()
  end
end

function ShotGroup.StartTicking()
  if ticking then return end
  ticking = true
  driver:SetScript("OnUpdate", OnUpdate)
end

function ShotGroup.StopTicking()
  if not ticking then return end
  ticking = false
  driver:SetScript("OnUpdate", nil)
end

local function OnTrackerChanged(what)
  if what == "clear" then return end
  if what == "reset" then Layout() end
  ShotGroup.StartTicking()
end

function ShotGroup.Create()
  frame = CreateFrame("Frame", "VWST_ShotFrame", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  backdrop:SetFrameLevel(frame:GetFrameLevel())
  shotBar = Bar.New(frame)
  shotBar:GetFrame():SetFrameLevel(frame:GetFrameLevel() + 1)
  windowBlock = shotBar:GetFrame():CreateTexture(nil, "ARTWORK", nil, 1)
  windowBlock:SetColorTexture(1, 0, 0, 1)
  local centerLine = shotBar:GetFrame():CreateTexture(nil, "OVERLAY")
  centerLine:SetColorTexture(1, 1, 1, 1)
  parts = ShotGroup.NewParts(shotBar, windowBlock, centerLine)

  activity = NS.Activity.New({
    frame = frame,
    lastActivityFn = ShotTracker.LastActivity,
    settingsFn = function()
      local s = Settings()
      -- no ranged weapon: never show in play, whatever the setting says. Edit Mode is exempt: an enabled
      -- group must be placeable even with nothing in the ranged slot (sample fill, fallback speed).
      if not NS.editModeActive and not ShotTracker.HasRangedWeapon() then return { enabled = false } end
      return s
    end,
  })
  ShotGroup.activity = activity
  ShotGroup.frame = frame

  Layout()
  Place()
  ShotTracker.OnChanged(OnTrackerChanged)
  NS.features["ShotGroup"] = true
end

function ShotGroup.Refresh()
  if not frame then return end
  Layout(); Place()
  ShotGroup.StartTicking()
end

function ShotGroup.Status()
  if not frame then return "shot group: not created" end
  return string.format("shot group: ticking %s | %s", tostring(ticking), activity:Status())
end