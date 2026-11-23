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
local GROUPS = {
  player = { label = "Velocity Swing Timers: Melee", module = function() return NS.MeleeGroup end },
  shot   = { label = "Velocity Swing Timers: Shot",  module = function() return NS.ShotGroup end },
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
  lib:AddFrameSettingsButtons(frame, {
    { text = "Reset position", click = function()
        local s = GroupSettings(key)
        s.point, s.x, s.y = d.point, d.x, d.y
        if m.Refresh then m.Refresh() end
      end },
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