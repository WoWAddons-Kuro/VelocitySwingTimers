-- Velocity Weapon Swing Timers: the player's melee swing clock (main hand + off hand).
-- Pure state, no frames. Fed by the client's VWST_SwingSink callbacks (Client.lua); read by UI\MeleeGroup.
--
-- VWST_HandState = { speed = seconds|nil, swingEnd = GetTime()|nil, swingStart = GetTime()|nil }
--   swingEnd == nil means no swing in flight (nothing to draw). speed is the last known weapon speed.
--
-- Rules (AddonManagement\_EXTERNAL_APIS\wow_swing_timer_api.md):
--   * a swing anchors the hand: swingStart = now, swingEnd = now + speed
--   * a completed cast-time spell resets BOTH hands (Classic rule) unless the spell is in NO_RESET_SWING
--   * instant RESET_SWING spells reset both hands too
--   * on-next-swing abilities (NEXT_MELEE) ARE the main-hand swing; Era anchors here, Forever gets PLAYER_SWING
--   * defensive parry by the player: MH remaining >60% of speed -> minus 40% of speed; 20..60% -> 20%; else nothing
--   * attack speed change (Era): remaining scales by newSpeed/oldSpeed; Forever speeds are secret -> ignore
--   * weapon swap: reset the hand with the new speed
local ADDON_NAME, NS = ...
local Util, Client, SpellData = NS.Util, NS.Client, NS.SpellData

local SwingTracker = {}
NS.SwingTracker = SwingTracker

local hands = {
  mainhand = { speed = nil, swingStart = nil, swingEnd = nil },
  offhand  = { speed = nil, swingStart = nil, swingEnd = nil },
}
SwingTracker.hands = hands

local casting = false            -- a cast-time spell is in progress
local castingNoReset = false     -- ...and it is flagged "do not reset combat timers"
local autoAttacking = false
local lastActivity = 0           -- GetTime() of the last melee swing anchor; drives the activity model
local listeners = {}

local function Fire(what, hand)
  for _, fn in ipairs(listeners) do fn(what, hand) end
end

-- Public read API -----------------------------------------------------------------------------
function SwingTracker.OnChanged(fn) listeners[#listeners + 1] = fn end
function SwingTracker.LastActivity() return lastActivity end
function SwingTracker.IsAutoAttacking() return autoAttacking end
function SwingTracker.HasOffhand() return hands.offhand.speed ~= nil end

-- remaining seconds, total speed, 0..1 progress (1 = ready); nil when no swing is in flight
function SwingTracker.Hand(handName, now)
  local h = hands[handName]
  if not h or not h.swingEnd or not h.speed then return nil end
  now = now or GetTime()
  local remaining = h.swingEnd - now
  if remaining <= 0 then return 0, h.speed, 1 end
  local total = h.swingEnd - h.swingStart
  if total <= 0 then total = h.speed end
  return remaining, h.speed, Util.Clamp(1 - remaining / total, 0, 1)
end

-- Internals -----------------------------------------------------------------------------------
-- Client.AttackSpeeds returns nil for an absent off hand AND for a secret (Forever in-combat) read; the two
-- are told apart by Client.SpeedsReadable(): only a readable nil clears the cached off-hand speed.
local function RefreshSpeeds()
  local mh, oh = Client.AttackSpeeds()
  if mh then hands.mainhand.speed = mh end
  if oh ~= nil or Client.SpeedsReadable() then hands.offhand.speed = oh end
end

local function Anchor(handName, speed, reason)
  local h = hands[handName]
  if speed then h.speed = speed end
  if not h.speed then return end
  local now = GetTime()
  h.swingStart = now
  h.swingEnd = now + h.speed
  if reason == "swing" then lastActivity = now end
  Fire(reason, handName)
end

local function ResetBoth(reason)
  RefreshSpeeds()
  Anchor("mainhand", nil, reason)
  if hands.offhand.speed then Anchor("offhand", nil, reason) end
end

local function ApplyParryHaste()
  local h = hands.mainhand
  if not h.swingEnd or not h.speed then return end
  local now = GetTime()
  local remaining = h.swingEnd - now
  if remaining <= SpellData.PARRY_FLOOR * h.speed then return end
  if remaining > SpellData.PARRY_FULL_CUT_THRESHOLD * h.speed then
    remaining = remaining - SpellData.PARRY_CUT * h.speed
  else
    remaining = SpellData.PARRY_FLOOR * h.speed
  end
  h.swingEnd = now + remaining
  Fire("parry", "mainhand")
end

-- Sink listener (registered on NS.sinkListeners by Init) -------------------------------------------
local sink = {}

function sink:OnSwing(hand, speed)
  if hand == "ranged" then return end
  Anchor(hand, speed, "swing")
end

function sink:OnPlayerParried() ApplyParryHaste() end

function sink:OnSpellCastStart(spellID)
  casting = true
  castingNoReset = spellID ~= nil and (SpellData.NO_RESET_SWING[spellID] == true
    or (Client.flavour == "forever" and SpellData.NO_RESET_SWING_FOREVER[spellID] == true))
end

function sink:OnSpellCastStop(spellID, reason)
  -- "stop" also fires after a successful cast; the SUCCEEDED handler has already consumed `casting` then
  casting = false
  castingNoReset = false
end

function sink:OnSpellSucceeded(spellID)
  if spellID == Client.AttackToggleSpellID() then return end   -- the auto-attack toggle is not a cast
  if spellID and SpellData.NEXT_MELEE[spellID] then
    -- Era: the ability is the swing. Forever: PLAYER_SWING already anchored it; a second anchor would drift it.
    if Client.flavour ~= "forever" then RefreshSpeeds(); Anchor("mainhand", nil, "swing") end
    casting = false
    return
  end
  local reset = (spellID and SpellData.RESET_SWING[spellID]) or (casting and not castingNoReset)
  casting = false
  castingNoReset = false
  if reset then ResetBoth("reset") end
end

function sink:OnAutoAttack(isOn)
  autoAttacking = isOn
  if isOn then
    RefreshSpeeds()
    lastActivity = GetTime()        -- the bar appears when you START attacking, not only at the first hit
    -- Classic: the first off-hand swing lands half a cycle after the toggle (LibClassicSwingTimerAPI, verified)
    local oh = hands.offhand
    if oh.speed and (not oh.swingEnd or oh.swingEnd - GetTime() < oh.speed / 2) then
      local now = GetTime()
      oh.swingStart = now - oh.speed / 2
      oh.swingEnd = now + oh.speed / 2
      Fire("attack", "offhand")
    end
    Fire("attack", "mainhand")
  end
end

function sink:OnAttackSpeedChanged()
  if Client.flavour == "forever" then return end        -- speeds are secret in combat; PLAYER_SWING re-anchors
  local now = GetTime()
  local mh, oh = Client.AttackSpeeds()
  for name, new in pairs({ mainhand = mh, offhand = oh }) do
    local h = hands[name]
    if new and h.speed and new ~= h.speed then
      if h.swingEnd and h.swingEnd > now then
        local factor = new / h.speed
        local remaining = (h.swingEnd - now) * factor
        local total = (h.swingEnd - h.swingStart) * factor
        h.swingEnd = now + remaining
        h.swingStart = h.swingEnd - total
      end
      h.speed = new
      Fire("haste", name)
    end
  end
  if oh == nil and Client.SpeedsReadable() then hands.offhand.speed = nil end
end

function sink:OnWeaponChanged(slot)
  if slot == 18 then return end
  RefreshSpeeds()
  if slot == 16 then Anchor("mainhand", nil, "reset") end
  if slot == 17 then
    if hands.offhand.speed then Anchor("offhand", nil, "reset") else hands.offhand.swingEnd = nil; Fire("reset", "offhand") end
  end
end

function SwingTracker.Init()
  RefreshSpeeds()
  NS.sinkListeners[#NS.sinkListeners + 1] = sink
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_DEAD")
  f:SetScript("OnEvent", function()
    hands.mainhand.swingEnd, hands.offhand.swingEnd = nil, nil
    casting, castingNoReset, autoAttacking = false, false, false
    RefreshSpeeds()
    Fire("clear", "mainhand"); Fire("clear", "offhand")
  end)
end

function SwingTracker.Status()
  local function H(n)
    local r, s = SwingTracker.Hand(n)
    if not hands[n].speed then return n .. " none" end
    return string.format("%s speed %.2f %s", n, hands[n].speed, r and string.format("remaining %.2f", r) or "idle")
  end
  return string.format("melee: %s | %s | attacking %s | casting %s | last activity %.1fs ago",
    H("mainhand"), H("offhand"), tostring(autoAttacking), tostring(casting), GetTime() - lastActivity)
end