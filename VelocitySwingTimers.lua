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
  Util.Print("target swings %s | attack toggle %d | %s",
    Client.SupportsTargetSwings() and "supported" or "not on this client",
    Client.AttackToggleSpellID(), NS.EditMode and NS.EditMode.Status() or "")
  local p = DB.Profile()
  Util.Print("player melee %s | shot bar %s | inactivity %ss | active alpha %.2f/%.2f | inactive alpha %.2f/%.2f | ooc alpha %.2f/%.2f",
    p.player.enabled and "on" or "off", p.shot.enabled and "on" or "off", tostring(DB.Global().inactivitySeconds),
    p.player.activeAlpha or 0.7, p.shot.activeAlpha or 0.7, p.player.inactiveAlpha, p.shot.inactiveAlpha, p.player.oocAlpha, p.shot.oocAlpha)
  local feats = {}
  for k, v in pairs(NS.features) do feats[#feats + 1] = k .. "=" .. tostring(v) end
  table.sort(feats)
  Util.Print("features: %s", table.concat(feats, ", "))
  if NS.SwingTracker and NS.SwingTracker.Status then Util.Print(NS.SwingTracker.Status()) end
  if NS.MeleeGroup and NS.MeleeGroup.Status then Util.Print(NS.MeleeGroup.Status()) end
  if NS.TargetSwingTracker then Util.Print(NS.TargetSwingTracker.Status()) end
  if NS.TargetGroup then Util.Print(NS.TargetGroup.Status()) end
  if NS.ShotTracker and NS.ShotTracker.Status then Util.Print(NS.ShotTracker.Status()) end
  if NS.ShotGroup and NS.ShotGroup.Status then Util.Print(NS.ShotGroup.Status()) end
  if NS.RangeCue and NS.RangeCue.Status then Util.Print(NS.RangeCue.Status()) end
  Util.DumpFooter("/vwst status")
end

-- Command help: printed by a bare /vwst (alongside opening the settings) and by any unknown command.
local function Help()
  Util.DumpHeader("/vwst commands")
  Util.Print("/vwst                 open settings (and print this)")
  Util.Print("/vwst status          versions, speeds, features, tracker and group state")
  Util.Print("/vwst trace           toggle printing every swing/shot event to chat")
  Util.Print("/vwst instants        histogram: auto-shot delay by where an instant was pressed   (reset: clears)")
  Util.Print("/vwst presses         histogram: what became of each instant press                 (reset: clears)")
  Util.Print("/vwst events          the last 10 s of shot events (what the mispredict dumps print)")
  Util.Print("Diagnostics are also buttons under Extras in the settings panel.")
  Util.DumpFooter("/vwst commands")
end

-- The dump commands as callables so the Extras buttons share them exactly. VWST_Commands = { name -> function() }
NS.Commands = {
  status   = Status,
  help     = Help,
  instants = function() if NS.ShotTracker.PrintInstantStats then NS.ShotTracker.PrintInstantStats() end end,
  presses  = function() if NS.ShotTracker.PrintPressStats then NS.ShotTracker.PrintPressStats() end end,
  events   = function() if NS.ShotTracker.DumpShotEventLog then NS.ShotTracker.DumpShotEventLog("/vwst events") end end,
  instantsReset = function() if NS.ShotTracker.ResetInstantStats then NS.ShotTracker.ResetInstantStats() end Util.Print("instant stats cleared") end,
  pressesReset  = function() if NS.ShotTracker.ResetPressStats then NS.ShotTracker.ResetPressStats() end Util.Print("press stats cleared") end,
}

local function Slash(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cmd = msg:match("^(%S*)")
  if cmd == "" then
    Help()
    if NS.Options and NS.Options.Open then NS.Options.Open() else Util.Print("options panel not built yet; try /vwst status") end
  elseif cmd == "options" or cmd == "config" then
    if NS.Options and NS.Options.Open then NS.Options.Open() else Util.Print("options panel not built yet; try /vwst status") end
  elseif cmd == "status" then Status()
  elseif cmd == "help" then Help()
  elseif cmd == "trace" then
    NS.trace = not NS.trace
    Util.Print("event trace %s", NS.trace and "on" or "off")
  elseif cmd == "instants" then
    if msg:match("^instants%s+reset") then NS.Commands.instantsReset() else NS.Commands.instants() end
  elseif cmd == "presses" then
    if msg:match("^presses%s+reset") then NS.Commands.pressesReset() else NS.Commands.presses() end
  elseif cmd == "events" then NS.Commands.events()
  else
    Util.Print("unknown command '%s'", cmd); Help()
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
    Stage("Options", NS.Options.Create)
  elseif event == "PLAYER_LOGIN" then
    NS.inCombat = UnitAffectingCombat("player") == true
    Stage("LayoutProfile", function()
      NS.LayoutProfile.Init(DB.DEFAULT_PROFILE)
      NS.LayoutProfile.OnChanged(function()
        if NS.EditMode and NS.EditMode.OnProfileChanged then NS.EditMode.OnProfileChanged() end
        if NS.Options and NS.Options.Refresh then NS.Options.Refresh() end
      end)
    end)
    Stage("SwingTracker", NS.SwingTracker.Init)
    -- SPEC 10.1: Era only - the module left NS.TargetSwingTracker nil when the client has no enemy swing source
    if NS.TargetSwingTracker then Stage("TargetSwingTracker", NS.TargetSwingTracker.Init) end
    Stage("ShotTracker", NS.ShotTracker.Init)
    Stage("MeleeGroup", NS.MeleeGroup.Create)
    if NS.TargetGroup then Stage("TargetGroup", NS.TargetGroup.Create) end
    Stage("ShotGroup", NS.ShotGroup.Create)
    Stage("EditMode", NS.EditMode.Setup)
    Stage("SwingSource", function() NS.swingSourceFrame = Client.StartSwingSource(sink) end)
    Stage("RangeCue", NS.RangeCue.Init)   -- SPEC 14: the range-entry weapon sound poller
    Util.Print("loaded (%s). /vwst status", Client.flavour)
  elseif event == "PLAYER_REGEN_DISABLED" then
    NS.inCombat = true
    -- SPEC 15: a fresh fight starts with an empty history ring so the last mob's lap never reads as current
    if NS.ShotTracker.ClearHistory then NS.ShotTracker.ClearHistory() end
    if NS.MeleeGroup.StartTicking then NS.MeleeGroup.StartTicking() end
    if NS.TargetGroup then NS.TargetGroup.StartTicking() end
    if NS.ShotGroup.StartTicking then NS.ShotGroup.StartTicking() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    NS.inCombat = false
    -- SPEC 12.15/12.17: an engagement is over; pending instant / press samples must not match a later fight's shot
    if NS.ShotTracker.OnLeaveCombat then NS.ShotTracker.OnLeaveCombat() end
    -- the groups' Tick reads NS.inCombat each frame, so the fade to oocAlpha begins on the next frame
    if NS.MeleeGroup.StartTicking then NS.MeleeGroup.StartTicking() end
    if NS.TargetGroup then NS.TargetGroup.StartTicking() end
    if NS.ShotGroup.StartTicking then NS.ShotGroup.StartTicking() end
  end
end)