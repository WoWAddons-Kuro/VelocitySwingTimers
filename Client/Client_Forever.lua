-- Velocity Swing Timers: WoW Forever client (interface 16001, Mainline UI code).
-- The combat log is refused and UnitAttackSpeed / UnitRangedDamage return SECRET values in any combat.
-- Swing anchors come from PLAYER_SWING(swingDuration, swingType) - payload is a plain number even in
-- restricted content. Parry haste from UNIT_COMBAT("player", "PARRY"). No target swing source exists.
-- See AddonManagement\_EXTERNAL_APIS\wow_swing_timer_api.md.
local ADDON_NAME, NS = ...
local Client, Util = NS.Client, NS.Util

local impl = {}
NS.ClientFlavours.forever = impl

local HAND_BY_SWINGTYPE = { [0] = "mainhand", [1] = "offhand", [2] = "ranged" }

function impl.PlayerKey() return UnitGUID("player") end
function impl.PlayerDisplayName()
  local name, surname = UnitNameUnmodified("player")
  return Client.DisplayNameFromParts(name, surname)
end
function impl.PlayerFirstName() return UnitName("player") end
function impl.PlayerClass() return select(2, UnitClass("player")) end

-- Three returns on Forever (Blizzard_SwingTimer relies on the third). Secret in combat -> nil.
function impl.AttackSpeeds()
  local mh, oh, ranged = UnitAttackSpeed("player")
  mh = Util.PlainNumber(mh, nil)
  oh = Util.PlainNumber(oh, nil)
  ranged = Util.PlainNumber(ranged, nil)
  if oh == 0 then oh = nil end
  if ranged == 0 then ranged = nil end
  return mh, oh, ranged
end

function impl.SpeedsReadable() return not Util.IsSecret((UnitAttackSpeed("player"))) end

function impl.SpellInfo(spellID)
  if not spellID or not (C_Spell and C_Spell.GetSpellInfo) then return nil end
  local info = C_Spell.GetSpellInfo(spellID)
  if not info then return nil end
  return info.name, Util.PlainNumber(info.castTime, nil)
end

function impl.PlayerAuraSpellIDs()
  local out = {}
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return out end
  for i = 1, 40 do
    local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
    if not a then break end
    local id = Util.PlainNumber(a.spellId, nil)
    if id then out[id] = true end
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

function impl.AttackToggleSpellID() return 6803 end
function impl.SupportsTargetSwings() return false end

-- SPEC 14.1: C_Spell.IsSpellInRange is a plain boolean on Forever, in combat too (EverAuras verified). Guard the
-- result anyway: a secret value here must read as "unknown", never as a cue.
function impl.IsSpellInRangeOfTarget(spellID)
  if not spellID or not UnitExists("target") then return nil end
  local r
  if C_Spell and C_Spell.IsSpellInRange then r = C_Spell.IsSpellInRange(spellID, "target")
  elseif IsSpellInRange then r = IsSpellInRange(spellID, "target") end
  if Util.IsSecret(r) then return nil end
  if r == true or r == 1 then return true elseif r == false or r == 0 then return false end
  return nil
end

-- SPEC 14.1 near-test (~10 yd, CheckInteractDistance duel). May be restricted / secret in combat on this client: any
-- failure or secret reads nil, and RangeCue treats nil as "not near" (= today's behaviour, far). Forever defaults off anyway.
function impl.IsTargetNear()
  if not UnitExists("target") or not CheckInteractDistance then return nil end
  local ok, r = pcall(CheckInteractDistance, "target", 3)
  if not ok or Util.IsSecret(r) or r == nil then return nil end
  return r == true or r == 1
end

local RANGED_KIND_BY_SUBCLASS = { [Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Bows or 2] = "bow",
  [Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Crossbow or 18] = "bow",
  [Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Guns or 3] = "gun",
  [Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Thrown or 16] = "thrown" }
function impl.RangedWeaponKind()
  local itemID = impl.RangedWeaponItemID()
  if not itemID then return nil end
  local classID, subclassID = select(12, (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID))
  if classID ~= (Enum.ItemClass and Enum.ItemClass.Weapon or 2) then return nil end
  return RANGED_KIND_BY_SUBCLASS[subclassID]
end
function impl.HasEditMode() return C_EditMode ~= nil and C_EditMode.GetLayouts ~= nil end
function impl.OpenSettings(id) if Settings and Settings.OpenToCategory then Settings.OpenToCategory(id) end end

function impl.StartSwingSource(sink)
  local f = CreateFrame("Frame")
  Client.RegisterCommonEvents(f)
  local okSwing = pcall(f.RegisterEvent, f, "PLAYER_SWING")
  local okCombat = pcall(f.RegisterEvent, f, "UNIT_COMBAT")
  if not okSwing then Util.WarnOnce("player_swing", "PLAYER_SWING is not available; swing bars will not anchor") end
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_SWING" then
      local duration, swingType = ...
      duration = Util.PlainNumber(duration, nil)
      local hand = HAND_BY_SWINGTYPE[swingType]
      if hand and duration and duration > 0 then Client.Emit(sink, "OnSwing", hand, duration) end
    elseif event == "UNIT_COMBAT" then
      local unit, action = ...
      if unit == "player" and action == "PARRY" then Client.Emit(sink, "OnPlayerParried") end
    else
      Client.RouteCommonEvent(sink, event, ...)
    end
  end)
  NS.features["SwingSource.PLAYER_SWING"] = okSwing
  NS.features["SwingSource.UNIT_COMBAT"] = okCombat
  return f
end