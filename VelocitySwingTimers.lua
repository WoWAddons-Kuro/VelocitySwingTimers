-- Velocity Swing Timers: bootstrap. Saved variables, slash commands, staged init.
local ADDON_NAME, NS = ...
local Util, Client, DB = NS.Util, NS.Client, NS.DB

_G.VelocitySwingTimers = NS

-- Combat state, shared by the activity model (M2).
NS.inCombat = false

-- Slash -------------------------------------------------------------------------------
local function Status()
  Util.DumpHeader("/vwst status")
  local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version")
  local ci = Util.ClientInfo()
  Util.Print("version %s | client %s %s (build %s, interface %s, project %s) | character %s (%s)",
    tostring(version), Client.flavour, ci.Version, ci.Build, tostring(ci.Interface), tostring(ci.Project),
    tostring(Client.PlayerDisplayName()), tostring(Client.PlayerClass()))
  local mh, oh, ranged = Client.AttackSpeeds()
  Util.Print("attack speeds: mh %s | oh %s | ranged %s%s", tostring(mh), tostring(oh), tostring(ranged),
    NS.inCombat and " (in combat)" or "")
  Util.Print("edit mode %s | target swings %s | attack toggle %d | profile %q",
    Client.HasEditMode() and "available" or "absent", Client.SupportsTargetSwings() and "supported" or "not on this client",
    Client.AttackToggleSpellID(), DB.ProfileName())
  local p = DB.Profile()
  Util.Print("player melee %s | shot bar %s | inactivity %ss | ooc alpha %.2f/%.2f",
    p.player.enabled and "on" or "off", p.shot.enabled and "on" or "off", tostring(DB.Global().inactivitySeconds),
    p.player.oocAlpha, p.shot.oocAlpha)
  local feats = {}
  for k, v in pairs(NS.features) do feats[#feats + 1] = k .. "=" .. tostring(v) end
  table.sort(feats)
  Util.Print("features: %s", table.concat(feats, ", "))
  if NS.SwingTracker and NS.SwingTracker.Status then Util.Print(NS.SwingTracker.Status()) end
  if NS.MeleeGroup and NS.MeleeGroup.Status then Util.Print(NS.MeleeGroup.Status()) end
  if NS.ShotTracker and NS.ShotTracker.Status then Util.Print(NS.ShotTracker.Status()) end
  Util.DumpFooter("/vwst status")
end

local function Slash(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cmd = msg:match("^(%S*)")
  if cmd == "" or cmd == "options" or cmd == "config" then
    if NS.Options and NS.Options.Open then NS.Options.Open() else Util.Print("options panel not built yet; try /vwst status") end
  elseif cmd == "status" then Status()
  elseif cmd == "trace" then
    NS.trace = not NS.trace
    Util.Print("event trace %s", NS.trace and "on" or "off")
  else
    Util.Print("/vwst - options | status | trace")
  end
end

-- Swing source wiring ---------------------------------------------------------------------
-- A sink that fans each callback out to the trackers (M2/M4) and, with /vwst trace, to chat.
local sink = {}
NS.sink = sink
local SINK_CALLBACKS = {
  "OnSwing", "OnPlayerParried", "OnSpellSucceeded", "OnSpellCastStart", "OnSpellCastStop", "OnSpellFailedQuiet",
  "OnAutoRepeat", "OnAutoAttack", "OnAttackSpeedChanged", "OnWeaponChanged",
}
NS.sinkListeners = {}
for _, name in ipairs(SINK_CALLBACKS) do
  sink[name] = function(...)
    if NS.trace then
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      Util.Print("%s(%s)", name, table.concat(parts, ", "))
    end
    for _, l in ipairs(NS.sinkListeners) do
      local fn = l[name]
      if fn then
        local ok, err = pcall(fn, l, ...)
        if not ok then Util.Raise(name, err) end
      end
    end
  end
end

-- Events ------------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")

local function Stage(name, fn)
  local ok, err = pcall(fn)
  if not ok then Util.Raise("init stage " .. name, err) end
end

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end
    Stage("DB", DB.Init)
    Stage("Slash", function()
      SLASH_VELOCITYSWINGTIMERS1 = "/vwst"
      SLASH_VELOCITYSWINGTIMERS2 = "/swingtimers"
      SlashCmdList.VELOCITYSWINGTIMERS = Slash
    end)
  elseif event == "PLAYER_LOGIN" then
    NS.inCombat = UnitAffectingCombat("player") == true
    Stage("SwingTracker", NS.SwingTracker.Init)
    Stage("MeleeGroup", NS.MeleeGroup.Create)
    Stage("SwingSource", function() NS.swingSourceFrame = Client.StartSwingSource(sink) end)
    Util.Print("loaded (%s). /vwst status", Client.flavour)
  elseif event == "PLAYER_REGEN_DISABLED" then
    NS.inCombat = true
    if NS.MeleeGroup.StartTicking then NS.MeleeGroup.StartTicking() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    NS.inCombat = false
    if NS.MeleeGroup.StartTicking then NS.MeleeGroup.StartTicking() end
  end
end)