-- Velocity Swing Timers: the bar groups in Edit Mode, through vendored LibEditMode.
-- Each group frame is registered directly (they are UIParent-parented and movable). Position is saved
-- into the ACTIVE LAYOUT PROFILE record (Core\LayoutProfile.lua = the game's active Edit Mode layout):
-- VWST_GroupPlacement = { point, x, y } on the group's settings table (player / shot). While Edit Mode is
-- open every enabled group is forced visible with a sample fill so you can see what you are placing.
local ADDON_NAME, NS = ...
local Util, DB = NS.Util, NS.DB

local EditMode = {}
NS.EditMode = EditMode

local lib
local editing = false
local registered = {}     -- groupKey -> { frame, default }

-- VWST_GroupKey = "player" | "shot" ; each group module exposes .frame and .Refresh()
-- label = the Edit Mode dialog title; LibEditMode renders it in GameFontHighlightLarge, so keep it short.
-- target (SPEC 10): the module is nil on Forever; Register already no-ops on a missing module / frame.
local GROUPS = {
  player = { label = "Melee Timer", module = function() return NS.MeleeGroup end },
  target = { label = "Target Timer", module = function() return NS.TargetGroup end },
  shot   = { label = "Shot Timer",  module = function() return NS.ShotGroup end },
}

local function GroupSettings(key) return DB.Profile()[key] end

-- Apply the saved placement of every group (profile switch, login, exit edit mode).
function EditMode.ApplyAll()
  for key, g in pairs(GROUPS) do
    local m = g.module()
    if m and m.Refresh then m.Refresh() end
  end
end

local function OnMoved(frame)
  local key = frame.vwstGroupKey
  local point, _, _, x, y = frame:GetPoint(1)
  if not point then return end
  local s = GroupSettings(key)
  s.point, s.x, s.y = point, math.floor(x + 0.5), math.floor(y + 0.5)
  -- the library anchors relative to UIParent with the same point on both sides; keep our Place() in step
  local m = GROUPS[key].module()
  if m and m.Refresh then m.Refresh() end
end

local function Register(key)
  if registered[key] then return end
  local m = GROUPS[key].module()
  if not m or not m.frame then return end
  local frame = m.frame
  frame.vwstGroupKey = key
  frame:SetMovable(true)
  local d = DB.DEFAULT_PROFILE[key]
  local default = { point = d.point, x = d.x, y = d.y }
  lib:AddFrame(frame, OnMoved, default, GROUPS[key].label)
  -- Sizing lives in the Edit Mode dialog too (same profile fields the options panel edits). The lib's
  -- "Reset To Default" button writes each setting's default back through set(); position reset is the lib's own.
  local function SliderSetting(name, field, minV, maxV, step, desc)
    return {
      kind = lib.SettingType.Slider, name = name, desc = desc,
      default = d[field], minValue = minV, maxValue = maxV, valueStep = step,
      formatter = function(v) return string.format("%d", v) end,
      get = function() return GroupSettings(key)[field] end,
      set = function(_, value)
        GroupSettings(key)[field] = value
        if m.Refresh then m.Refresh() end
        if NS.Options and NS.Options.Refresh then NS.Options.Refresh() end
      end,
    }
  end
  lib:AddFrameSettings(frame, {
    SliderSetting("Width", "width", 100, 500, 10, "Bar width in pixels."),
    SliderSetting("Bar height", "height", 6, 30, 1, "Height of each bar in pixels."),
  })
  registered[key] = { frame = frame, default = default }
end

local function OnEnter()
  editing = true
  NS.editModeActive = true
  for key in pairs(GROUPS) do Register(key) end
  -- wake every group so the forced-visible sample renders
  EditMode.ApplyAll()
  for key, g in pairs(GROUPS) do local m = g.module(); if m and m.StartTicking then m.StartTicking() end end
end

local function OnExit()
  editing = false
  NS.editModeActive = false
  EditMode.ApplyAll()
end

function EditMode.IsActive() return editing end

-- Profile switched (layout change in the game's dropdown, create, rename): re-place everything.
function EditMode.OnProfileChanged()
  EditMode.ApplyAll()
end

function EditMode.Setup()
  if lib then return true end
  local found = LibStub and LibStub("LibEditMode", true)
  if not found or type(found.AddFrame) ~= "function" or type(found.RegisterCallback) ~= "function" then
    NS.features["EditMode"] = false
    return false
  end
  lib = found
  lib:RegisterCallback("enter", OnEnter)
  lib:RegisterCallback("exit", OnExit)
  -- register now so the frames are known to the library before the first enter
  for key in pairs(GROUPS) do Register(key) end
  NS.features["EditMode"] = true
  return true
end

function EditMode.Status()
  local profile = NS.LayoutProfile and NS.LayoutProfile.Status() or "no layout profile"
  if not lib then return "LibEditMode not found; bars are fixed at their saved positions | " .. profile end
  return "LibEditMode minor " .. tostring(lib.hookVersion or "?") .. (editing and " (editing now)" or "") .. " | " .. profile
end