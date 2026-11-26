-- Velocity Swing Timers: Classic-engine spell tables (Forever reuses Classic IDs).
-- Source: LibClassicSwingTimerAPI (Ralgathor) isClassic/isForever block, cross-checked with Wowhead Classic.
-- Ground truth notes: AddonManagement\_EXTERNAL_APIS\wow_swing_timer_api.md section 2.
local ADDON_NAME, NS = ...

local SpellData = {}
NS.SpellData = SpellData

local function Set(list) local s = {} for _, id in ipairs(list) do s[id] = true end return s end

-- On-next-swing abilities: the ability IS the main-hand swing. Era anchors MH on UNIT_SPELLCAST_SUCCEEDED;
-- Forever already fires PLAYER_SWING for the consumed swing, so the flavour must not double-anchor.
SpellData.NEXT_MELEE = Set({
  78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286,          -- Heroic Strike r1-r9
  845, 7369, 11608, 11609, 20569,                                  -- Cleave r1-r5
  2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266,          -- Raptor Strike r1-r8
  6807, 6808, 6809, 8972, 9745, 9880, 9881,                        -- Maul r1-r7
})

-- Instant spells that nonetheless reset both melee swings when they succeed.
SpellData.RESET_SWING = Set({
  16589,                                   -- Noggenfogger Elixir
  2645,                                    -- Ghost Wolf
  5384,                                    -- Feign Death
  20066,                                   -- Repentance
  2893, 8946,                              -- Abolish Poison, Cure Poison
  339, 1062, 5195, 5196, 9852, 9853,       -- Entangling Roots
  770,                                     -- Faerie Fire
  21849, 21850,                            -- Gift of the Wild
  5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297,   -- Healing Touch
  2637, 18657, 18658,                      -- Hibernate
  1126, 5232, 6756, 5234, 8907, 9884, 9885,                              -- Mark of the Wild
  8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835,            -- Moonfire
  20484, 20739, 20742, 20747, 20748,       -- Rebirth
  8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858,                  -- Regrowth
  774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299,      -- Rejuvenation
  2782,                                    -- Remove Curse
  2908, 8955, 9901,                        -- Soothe Animal
  467, 782, 1075, 8914, 9756, 9910,        -- Thorns
  5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912,                        -- Wrath
})

-- Cast-time spells flagged "do not reset combat timers": completing them leaves the swing alone.
SpellData.NO_RESET_SWING = Set({
  4054, 4061, 4062, 4064, 4065, 4066, 4067, 4068, 4069, 8331, 12421, 12543, 12562,
  19769, 19784, 19821, 23000, 23063, 30216,                              -- bombs / dynamite
  16914, 17401, 17402,                     -- Hurricane
  12051,                                   -- Evocation
  1510, 14294, 14295,                      -- Volley
})
-- Forever turns these shots into no-reset cast-time spells as well (Wowhead Forever 2026-10-14).
SpellData.NO_RESET_SWING_FOREVER = Set({ 2643, 19434, 20900, 20901, 20902, 20903, 20904 })

-- Ranged auto-repeat attacks. Shoot Wand runs its own cycle independent of the melee clock.
SpellData.AUTO_SHOT = 75
SpellData.SHOOT_WAND = 5019
SpellData.RANGED_AUTO = Set({ 75, 3018, 5019 })   -- Auto Shot, Shoot (bow/gun/xbow), Shoot Wand
SpellData.THROW = 2764                            -- one-shot ranged, not auto-repeat

-- Hunter cast-time shots shown on the cast bar.
SpellData.AIMED_SHOT = Set({ 19434, 20900, 20901, 20902, 20903, 20904 })
SpellData.MULTI_SHOT = Set({ 2643, 14288, 14289, 14290, 25294 })
SpellData.MULTI_SHOT_BASE_CAST = 0.5
SpellData.AIMED_SHOT_BASE_CAST = 3.0

-- SPEC 12.14 action blocks. Abilities that stop Auto Shot's cast from beginning, and for how long.
-- Real casts (Classic: Multi-Shot is a 0.5 s cast until Wrath 3.0; Aimed Shot 3 s): block = the cast.
SpellData.SHOT_BLOCKING_CASTS = {}
for id in pairs(SpellData.AIMED_SHOT) do SpellData.SHOT_BLOCKING_CASTS[id] = SpellData.AIMED_SHOT_BASE_CAST end
for id in pairs(SpellData.MULTI_SHOT) do SpellData.SHOT_BLOCKING_CASTS[id] = SpellData.MULTI_SHOT_BASE_CAST end
-- Instants on the GCD: block = the GCD they start (read live from the Attack toggle's cooldown; 1.5 fallback).
SpellData.SHOT_BLOCKING_INSTANTS = Set({
  3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287,          -- Arcane Shot r1-r8
  1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295,   -- Serpent Sting r1-r9
  3034, 14279, 14280,                                            -- Viper Sting r1-r3
  3043, 14275, 14276, 14277,                                      -- Scorpid Sting r1-r4
  1130, 14323, 14324, 14325,                                      -- Hunter's Mark r1-r4
  5116,                                                          -- Concussive Shot
  19503,                                                         -- Scatter Shot
  20736, 14274, 15629, 15630, 15631, 15632,                       -- Distracting Shot r1-r6
  1513, 14326, 14327,                                             -- Scare Beast r1-r3 (cast in Classic; included as GCD trigger - verify)
  19801,                                                         -- Tranquilizing Shot
  2974, 14267, 14268,                                             -- Wing Clip r1-r3 (melee-range instant, still a GCD)
})
SpellData.GCD_FALLBACK_SECONDS = 1.5

-- Auto Shot stand-still window: 0.52 s scaled by current/base ranged speed (lib, measured).
SpellData.AUTO_SHOT_CAST_BASE = 0.52
-- Recast delay after a movement cancel (UNIT_SPELLCAST_FAILED_QUIET 75).
SpellData.AUTO_SHOT_RECAST_DELAY = 0.5
-- SPEC 12.6a: the window region flashes shotFlashColor for this long when the shot lands.
SpellData.SHOT_FLASH_SECONDS = 0.25

-- SPEC 14.2 range-entry weapon sound, keyed by Client.RangedWeaponKind(). File IDs under Sound\Item\Weapons\, looked
-- up 2026-11-24 in the wowdev community listfile (parts/sound.csv) - the earlier guesses 567513 / 567575 were
-- LFG_RoleCheck.ogg and PutDownRocks_Ore01.ogg. Alternatives if the owner prefers another take by ear (Preview buttons):
--   bow: 567675 BowPullback02, 567676 BowPullback03, 567678 BowPullBack1, 567683 BowPullBack2, 567679 BowPullBack3
--   gun: 567720 GunLoad02, 567723 GunLoad03
SpellData.RANGE_SOUND = {
  bow = 567677,   -- Sound/Item/Weapons/Bow/BowPullback.ogg
  gun = 567719,   -- Sound/Item/Weapons/Gun/GunLoad01.ogg
}
-- SPEC 14.1 melee probe per class: a MELEE-range spell whose IsSpellInRange is legal in combat. CheckInteractDistance is
-- NOT (10.1.5+ restriction, Era 1.15 included: nil on a hostile in combat) - that is why the first near-test read every
-- deadzone as "far" and the cue played on deadzone -> in (owner 2026-11-25). true = melee (<= 5 yd).
SpellData.RANGE_MELEE_SPELL = { HUNTER = 2973 }   -- Raptor Strike r1 (level 1)
-- Deadzone probes: spells with 8 < range < 35 yd - true in the deadzone, false far. None is baseline for a hunter (no
-- trained spell has such a range; Tame / Scare Beast read nil on non-beasts), so these are talents, used when known.
SpellData.RANGE_NEAR_SPELLS = { HUNTER = { 19503 } }   -- Scatter Shot (15 yd, talent)
-- The deadzone (5-8 yd) and far (> 35 yd) BOTH read "cue spell false, melee spell false". RangeCue tells them apart by
-- history: an out that follows "in" or melee is the deadzone until it has lasted this long (a deadzone crossing is a
-- step; a kite-out to > 35 and back is a multi-second walk), after which it is treated as far and the next "in" cues.
-- A mob parked in the deadzone is normally closing to melee anyway, where the melee probe takes over.
SpellData.RANGE_DEADZONE_CROSS_SECONDS = 3.0

-- Parry haste (defender's main hand): >60% remaining -> minus 40% of speed; 20..60% -> floor at 20%; <=20% unchanged.
SpellData.PARRY_FULL_CUT_THRESHOLD = 0.6
SpellData.PARRY_CUT = 0.4
SpellData.PARRY_FLOOR = 0.2

-- Classes whose shot bar is on by default (ranged auto-attack users).
SpellData.SHOT_BAR_CLASSES = { HUNTER = true, MAGE = true, PRIEST = true, WARLOCK = true }

-- Classes that can ever dual-wield on the Classic ruleset (SPEC 10.9). Shaman via talent; the class still qualifies.
-- Drives the "Enable Off-hand" checkbox: other classes get it disabled with a red X.
SpellData.DUAL_WIELD_CLASSES = { WARRIOR = true, ROGUE = true, HUNTER = true, SHAMAN = true }