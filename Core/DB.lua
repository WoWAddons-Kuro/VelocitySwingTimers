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
  showShotGCD = true,        -- SPEC 12: draw the Auto Shot retry block (solid red while moving, lowering box while still)
  showShotActions = true,    -- SPEC 12.14: draw each shot ability's GCD / cast on the bar from the moment you use it
  showShotActionIcon = true, -- SPEC 12.14: spell icon at the start of that block
  rangeEntrySound = nil,         -- SPEC 14.3 OUT of combat: nil = flavour default (Era on, Forever off - Forever plays this natively)
  rangeEntrySoundInCombat = false, -- SPEC 14.3 IN combat: off by default (deadzone vs far is unreadable in combat; owner 2026-11-25)
  debugTimerPrediction = false,  -- SPEC 12.9/12.11 chat announcements when a retry tick / cast prediction was wrong
}

-- VWST_MeleeGroupSettings
DB.DEFAULT_MELEE = {
  enabled = true,
  width = 200, height = 12, fontSize = 10,
  point = "CENTER", x = 0, y = -200,
  inactiveAlpha = 0,         -- no swing for inactivitySeconds: fully transparent by default
  oocAlpha = 0,              -- out of combat (but recently active): fully transparent by default
  backdropAlpha = 0.5,       -- the fill behind the bars; the border is borderColor (alpha 0 = none)
  texture = "Blizzard",      -- VWST_TextureKey (UI\Theme.lua)
  fillDirection = "fill",    -- "fill" (grows toward ready) | "empty" (drains)
  showOffhand = false,       -- SPEC 10.9: off by default; greyed for classes that cannot dual-wield
  mainColor = { r = 0.1, g = 0.1, b = 0.9, a = 1 },
  offColor  = { r = 0.1, g = 0.1, b = 0.9, a = 1 },
  textColor   = { r = 1, g = 1, b = 1, a = 1 },   -- alpha 0 hides label + countdown
  borderColor = { r = 1, g = 1, b = 1, a = 1 },   -- alpha 0 = no border
}

-- VWST_ShotGroupSettings
DB.DEFAULT_SHOT = {
  enabled = nil,             -- nil = decide by class at first load (SpellData.SHOT_BAR_CLASSES)
  width = 300, height = 12, fontSize = 10,
  point = "CENTER", x = 0, y = -260,
  inactiveAlpha = 0, oocAlpha = 0,
  backdropAlpha = 0.5,
  texture = "Blizzard",
  textColor   = { r = 1, g = 1, b = 1, a = 1 },
  borderColor = { r = 1, g = 1, b = 1, a = 1 },
  -- VWST_ShotBarStyle: "mirrored" = upstream WeaponSwingTimer: fill anchored at the centre; white shrinks into the
  --   middle over the cooldown, red grows out of it over the stand-still window.
  --   "onebar" = YaHT: fills left to right over the whole cycle, red block fixed at the right end marks the window.
  style = "mirrored",
  showCastBar = true, showLatency = false, showMultishotClip = false,
  cooldownColor   = { r = 0.95, g = 0.95, b = 0.95, a = 1 },
  castWindowColor = { r = 0.8,  g = 0.0,  b = 0.0,  a = 1 },
  castFillColor   = { r = 0.2,  g = 0.85, b = 0.2,  a = 1 },   -- SPEC 12: the fill past the boundary while the shot casts
  shotFlashColor  = { r = 1.0,  g = 1.0,  b = 1.0,  a = 0.8 }, -- SPEC 12.3: whole-bar flash when the shot lands
  actionBlockColor = { r = 0.8, g = 0.0,  b = 0.0,  a = 0.45 }, -- SPEC 12.14: the GCD / cast block drawn when you use a shot ability
  clipColor       = { r = 1.0,  g = 0.0,  b = 0.0,  a = 0.7 },
}
-- SPEC 14.2a: the spell whose range defines "in" for the range cue. Hunter default Auto Shot 75; casters per class later.
DB.DEFAULT_RANGE_CUE = { spellID = 75 }

-- VWST_ProfileRecord
DB.DEFAULT_PROFILE = {
  player = DB.DEFAULT_MELEE,
  shot = DB.DEFAULT_SHOT,
  rangeCue = DB.DEFAULT_RANGE_CUE,
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
  -- pre-2026-11-24 records stored the presentation as oneBar = bool
  if p.shot.oneBar ~= nil then
    p.shot.style = p.shot.oneBar and "onebar" or "mirrored"
    p.shot.oneBar = nil
  end
  -- SPEC section 11.1: the showText / showBorder booleans became alpha on textColor / borderColor (alpha 0 = gone);
  -- fontSize moved from global into every group record
  local legacyFont = NS.db.global.fontSize
  for _, g in pairs(p) do
    if type(g) == "table" then
      if g.showText == false and g.textColor then g.textColor.a = 0 end
      if g.showBorder == false and g.borderColor then g.borderColor.a = 0 end
      g.showText, g.showBorder = nil, nil
      if legacyFont and g.fontSize == nil then g.fontSize = legacyFont end
    end
  end
  NS.db.global.fontSize = nil
  return p
end