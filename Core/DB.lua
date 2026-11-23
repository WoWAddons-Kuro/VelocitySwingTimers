-- Velocity Swing Timers: saved variables and defaults.
-- VelocitySwingTimersDB = { version, global = VWST_GlobalSettings, profiles = { [layoutName] = VWST_ProfileRecord } }
-- Profiles are keyed by the active Edit Mode layout name (Core\LayoutProfile.lua, M6). Until that lands,
-- DB.Profile() returns the record under PROFILE_PLACEHOLDER.
local ADDON_NAME, NS = ...
local Util = NS.Util

local DB = {}
NS.DB = DB

local DB_VERSION = 1
local PROFILE_PLACEHOLDER = "Default"

-- VWST_GlobalSettings: not part of a layout.
DB.DEFAULT_GLOBAL = {
  inactivitySeconds = 5,     -- a bar with no swing/shot for this long hides (the feature)
  fadeSeconds = 0.2,
  fontSize = 10,
}

-- VWST_MeleeGroupSettings
DB.DEFAULT_MELEE = {
  enabled = true,
  width = 200, height = 12,
  point = "CENTER", x = 0, y = -200,
  oocAlpha = 0,              -- out of combat: fully transparent by default
  backdropAlpha = 0.5, showBorder = true,
  texture = "Blizzard",      -- VWST_TextureKey (UI\Theme.lua)
  fillDirection = "fill",    -- "fill" (grows toward ready) | "empty" (drains)
  showOffhand = true, showText = true,
  mainColor = { r = 0.1, g = 0.1, b = 0.9, a = 1 },
  offColor  = { r = 0.1, g = 0.1, b = 0.9, a = 1 },
  textColor = { r = 1, g = 1, b = 1, a = 1 },
}

-- VWST_ShotGroupSettings
DB.DEFAULT_SHOT = {
  enabled = nil,             -- nil = decide by class at first load (SpellData.SHOT_BAR_CLASSES)
  width = 300, height = 12,
  point = "CENTER", x = 0, y = -260,
  oocAlpha = 0,
  backdropAlpha = 0.5, showBorder = true,
  texture = "Blizzard",
  showText = true, oneBar = false,
  showCastBar = true, showLatency = false, showMultishotClip = false,
  cooldownColor   = { r = 0.95, g = 0.95, b = 0.95, a = 1 },
  castWindowColor = { r = 0.8,  g = 0.0,  b = 0.0,  a = 1 },
  clipColor       = { r = 1.0,  g = 0.0,  b = 0.0,  a = 0.7 },
}

-- VWST_ProfileRecord
DB.DEFAULT_PROFILE = {
  player = DB.DEFAULT_MELEE,
  shot = DB.DEFAULT_SHOT,
  -- target = DB.DEFAULT_MELEE with enabled=false  (deferred milestone, Era only)
}

function DB.Init()
  VelocitySwingTimersDB = type(VelocitySwingTimersDB) == "table" and VelocitySwingTimersDB or {}
  local db = VelocitySwingTimersDB
  db.version = db.version or DB_VERSION
  db.global = Util.ApplyDefaults(db.global or {}, DB.DEFAULT_GLOBAL)
  db.profiles = type(db.profiles) == "table" and db.profiles or {}
  NS.db = db
end

function DB.Global() return NS.db.global end

function DB.ProfileName()
  if NS.LayoutProfile and NS.LayoutProfile.Name then return NS.LayoutProfile.Name() end
  return PROFILE_PLACEHOLDER
end

-- The active profile record, created from defaults on demand. Shot bar default-on is class based.
function DB.Profile()
  local name = DB.ProfileName()
  local recs = NS.db.profiles
  local p = recs[name]
  if not p then
    p = Util.DeepCopy(DB.DEFAULT_PROFILE)
    recs[name] = p
  else
    Util.ApplyDefaults(p, DB.DEFAULT_PROFILE)
  end
  if p.shot.enabled == nil then
    p.shot.enabled = NS.SpellData.SHOT_BAR_CLASSES[NS.Client.PlayerClass() or ""] == true
  end
  return p
end