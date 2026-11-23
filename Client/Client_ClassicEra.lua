-- Velocity Weapon Swing Timers: Classic Era / Anniversary client (WOW_PROJECT_CLASSIC).
-- Swing anchors come from COMBAT_LOG_EVENT_UNFILTERED; weapon speeds are always readable.
local ADDON_NAME, NS = ...
local Client, Util = NS.Client, NS.Util

local impl = {}
NS.ClientFlavours.classic_era = impl

function impl.PlayerKey() return UnitGUID("player") end
function impl.PlayerDisplayName() return UnitName("player") end
function impl.PlayerFirstName() return UnitName("player") end
function impl.PlayerClass() return select(2, UnitClass("player")) end

function impl.AttackSpeeds()
  local mh, oh = UnitAttackSpeed("player")
  local ranged = UnitRangedDamage("player")
  if oh == 0 then oh = nil end
  if ranged == 0 then ranged = nil end
  return mh, oh, ranged
end

function impl.SpellInfo(spellID)
  if not spellID then return nil end
  local name, _, _, castTime = GetSpellInfo(spellID)
  return name, castTime
end

function impl.PlayerAuraSpellIDs()
  local out = {}
  for i = 1, 40 do
    local name, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
    if not name then break end
    if spellID then out[spellID] = true end
  end
  return out
end

function impl.RangedWeaponItemID() return GetInventoryItemID("player", INVSLOT_RANGED or 18) end

function impl.IsAutoRepeatSpell(spellID)
  if C_Spell and C_Spell.IsRangedAutoAttackSpell then
    local ok, r = pcall(C_Spell.IsRangedAutoAttackSpell, spellID)
    if ok and r ~= nil then return r == true end
  end
  return NS.SpellData.RANGED_AUTO[spellID] == true
end

function impl.AttackToggleSpellID() return 6603 end
function impl.SupportsTargetSwings() return true end
function impl.HasEditMode() return C_EditMode ~= nil and C_EditMode.GetLayouts ~= nil end
function impl.OpenSettings(id) if Settings and Settings.OpenToCategory then Settings.OpenToCategory(id) end end

-- CLEU payload positions (CombatLogGetCurrentEventInfo):
--   1 ts, 2 subEvent, 3 hideCaster, 4 sourceGUID, 5 sourceName, 6 sourceFlags, 7 sourceRaidFlags,
--   8 destGUID, 9 destName, 10 destFlags, 11 destRaidFlags, then per-event:
--   SWING_DAMAGE: 12 amount ... 21 isOffHand
--   SWING_MISSED: 12 missType, 13 isOffHand
function impl.StartSwingSource(sink)
  local f = CreateFrame("Frame")
  local playerGUID = UnitGUID("player")
  Client.RegisterCommonEvents(f)
  f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      local _, sub, _, src, _, _, _, dst = CombatLogGetCurrentEventInfo()
      if sub == "SWING_DAMAGE" and src == playerGUID then
        local isOff = select(21, CombatLogGetCurrentEventInfo())
        local mh, oh = impl.AttackSpeeds()
        Client.Emit(sink, "OnSwing", isOff and "offhand" or "mainhand", isOff and oh or mh)
      elseif sub == "SWING_MISSED" then
        local missType, isOff = select(12, CombatLogGetCurrentEventInfo())
        if src == playerGUID then
          local mh, oh = impl.AttackSpeeds()
          Client.Emit(sink, "OnSwing", isOff and "offhand" or "mainhand", isOff and oh or mh)
        end
        if missType == "PARRY" and dst == playerGUID then Client.Emit(sink, "OnPlayerParried") end
      end
    elseif event == "PLAYER_ENTERING_WORLD" then
      playerGUID = UnitGUID("player")
    else
      Client.RouteCommonEvent(sink, event, ...)
    end
  end)
  NS.features["SwingSource.CLEU"] = true
  return f
end