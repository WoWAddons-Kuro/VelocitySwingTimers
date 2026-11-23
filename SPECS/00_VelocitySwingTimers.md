# Velocity Swing Timers (VWST) — spec

A clean-room rewrite of **WeaponSwingTimer 4.1.1** (LeftHandedGlove, Classic Era) in the Velocity addon
structure. Upstream archived at `_ref\WeaponSwingTimer_upstream_reference.zip` (2026-11-22). Credit upstream in
README and TOC (`## X-Credits`).

The one *behavioural* change that motivates the fork: **bars that nobody is using are invisible.** A priest spamming
Smite today sees a melee bar AND a wand bar sitting at "ready" for the whole fight (see screenshot in chat 2026-11-22).
Everything else is structure: all client flavours via `Client_*` adaptors, Edit Mode placement, Edit-Mode-layout
profiles, a settings panel a third its current size.

Upstream must keep working **side by side** during testing: no global name, frame name, slash command, SavedVariable
or texture path may collide with `WeaponSwingTimer`.

**Scope per client (decided 2026-11-22, after research in `_EXTERNAL_APIS\wow_swing_timer_api.md`):**

| Bar group | Classic Era / Anniversary | WoW Forever |
|---|---|---|
| Player melee (MH/OH) | yes — CLEU anchors | yes — `PLAYER_SWING` anchors |
| Shot bar (Auto Shot / wand Shoot) + hunter cast bar | yes | yes |
| Target melee | **DEFERRED** — later milestone, Era-only, default OFF | **not available** (no data source) |

Forever also has Blizzard's built-in `Blizzard_SwingTimer`; ours coexists. Our value-add there is the activity-based
hiding, textures/colours, and the hunter/wand extras. README tells Forever users to set Blizzard's bars to Hidden in Edit Mode.

---

## 1. What upstream does (reference behaviour to preserve)

| Module | Behaviour we keep |
|---|---|
| Player melee | MH and OH countdown bars. Timer resets to `UnitAttackSpeed()` on the player's `SWING_DAMAGE` / `SWING_MISSED` (offhand flag selects the bar). Haste change mid-swing rescales remaining time by `newSpeed/oldSpeed`. **On-next-swing abilities** (Heroic Strike, Cleave, Slam, Maul, Raptor Strike) reset MH on `SPELL_DAMAGE`/`SPELL_MISSED`. Weapon swap resets the hand. |
| Target melee | Same tracker keyed on `UnitGUID("target")`; zeroed on `PLAYER_TARGET_CHANGED`. |
| Parry haste | When the **defender parries**, the attacker's remaining swing is clamped to `<= 0.2 * speed` (i.e. the parrier's next swing comes sooner). Upstream has this backwards in places (it clamps the *parrier* on `unit=="player"`); we implement the real rule: parry by X → X's remaining MH timer `= min(timer, 0.2*speed)`... **TBD §9 Q1** — verify Classic parry-haste rule before coding. |
| Shot bar (hunter + wand) | Auto Shot (75) / Shoot (5019) cycle: `shot_timer` resets on `UNIT_SPELLCAST_SUCCEEDED`; the last `auto_cast_time = 0.7s` (hunter) of the cycle is the "must stand still" window and restarts if the player moves (`GetUnitSpeed > 0`). Ranged haste rescales the cooldown part only. Two-bar (cooldown + cast) or YaHT one-bar presentation. |
| Hunter cast bar | Aimed Shot / Multi-Shot cast bar under the shot bar, optional latency slice and Multi-Shot-clip marker. Cast start detected by `hooksecurefunc` on `UseAction` / `CastSpellByName` / `CastSpell`. |
| Visuals | Bar / Spark / Border / Background textures; left label + right numeric; backdrop alpha; combat vs OOC alpha. |

Upstream defects we do **not** carry over (listed so nobody "fixes" them back in):
- `UnitClass("player")[2]` indexes a string → class is always nil. Use `select(2, UnitClass(...))`.
- ~20 implicit globals (`main_width`, `point`, `name`, `new_width`, ...). The whole addon is `local` + `NS`.
- Ranged-haste auras matched by **English name**. We match **spell IDs** through the client adaptor.
- `GetSpellInfo` / `UnitAura` direct calls: removed on Mainline-code clients. Client adaptor only.
- Player and Target modules are copy-paste. One `SwingTracker` module, two instances.
- Starting timers at `0.0001` so bars render "ready" forever. Replaced by the visibility model below.
- Settings per-character only. Replaced by layout profiles.
- A 500-line spell table with 95% commented out. Ship only the live IDs, by class, with names in comments.

---

## 2. Visibility model (the feature)

Each bar group (**Player melee**, **Target melee**, **Shot**) has an independent *activity* state. The rule is
the same for all three: **a bar is shown only while its unit is actually using that attack.**

```
state: Hidden ──(swing/shot event for this group)──> Active
       Active ──(no swing/shot event for inactivity_seconds)──> Hidden
       Active ──(PLAYER_REGEN_ENABLED and ooc_alpha == 0)──> Hidden   (immediate on leaving combat)
       any    ──(PLAYER_TARGET_CHANGED, target group only)──> Hidden
```

- **"Swing/shot event"** = the same combat-log / spellcast events that reset the timer: `SWING_DAMAGE`, `SWING_MISSED`,
  an on-next-swing ability landing, `UNIT_SPELLCAST_SUCCEEDED` for Auto Shot / Shoot. **Starting** auto-attack
  (`PLAYER_ENTER_COMBAT` / `START_AUTOREPEAT_SPELL`) also counts as activity, so the bar appears at the first
  swing's *start* for the player, not only at its landing. (Target: we cannot see its auto-attack toggle; first landed
  swing it is.)
- **`inactivity_seconds`** (default **5**, slider 1–30, global): a group that sees no swing/shot event for this long
  hides. When the timer has run out and nothing happened, the swing *is* ready — showing a full idle bar carries no
  information. Implemented as `lastActivityTime` per group checked in `OnUpdate`.
- **OOC**: `ooc_alpha` kept, **default 0** (fully transparent). `ooc_alpha > 0` shows the group at that alpha out of
  combat **only if it is Active** (recent activity); an OOC bar that has been idle `inactivity_seconds` still hides.
- Hide/show uses a short alpha fade (0.2s) so the target bar doesn't flicker when tab-targeting mid-fight.
- **Edit Mode** forces all enabled groups visible (static, timer at half) regardless of state.
- Per-group `enabled` remains as the hard off switch. Shot group default `enabled` = class ∈ {HUNTER, MAGE, PRIEST,
  WARLOCK} (as upstream); melee groups default on for every class — the visibility model makes them harmless.

No "always show" mode is needed: `inactivity_seconds = 30` + `ooc_alpha > 0` approximates it; if a user asks, add a
`Visibility: Always / When active` dropdown later.

---

## 3. Repository and file layout

```
VelocitySwingTimers\                        git repo, origin WoWAddons-Kuro/VelocitySwingTimers
├── VelocitySwingTimers.toc                 ## Interface: 16001 (Forever)
├── VelocitySwingTimers_Vanilla.toc         ## Interface: 11509 (Era)
├── VelocitySwingTimers_Camelot.toc         ## Interface: (Anniversary) — same list, as other Velocity addons
├── .pkgmeta                                      package-as: VelocitySwingTimers; ignore: *.md, SPECS
├── README.md, LICENSE (MIT), SPECS\00_VelocitySwingTimers.md (this)
├── Assets\   VelocitySwingTimers_Icon.tga (+ png/jpg per workspace convention)
├── Media\    Bar.blp Spark.blp Border.blp Background.blp   -- our own paths, see §9 Q2 on licence
├── Libs\LibStub\LibStub.lua
├── Libs\LibEditMode\embed.xml                    vendored, same copy as VelocityQuestTracker
├── Core\Util.lua                                 NS.Print, NS.WarnOnce, NS.Round, NS.features
├── Core\LayoutProfile.lua                        COPY of VelocityQuestTracker\Core\LayoutProfile.lua (NS-local)
├── Client\Client.lua                             Client.INTERFACE + NS.ClientFlavours = {}
├── Client\Client_ClassicEra.lua
├── Client\Client_Forever.lua
├── Client\Client_Select.lua                      COPY of QuestAutomator pattern
├── Core\DB.lua                                   defaults, VelocitySwingTimersDB, profile record access
├── Core\SpellData.lua                            on-next-swing IDs by class, shot spell IDs, ranged-haste aura IDs
├── Core\SwingTracker.lua                         SwingTracker.New(unitToken) -> melee MH/OH timer object
├── Core\ShotTracker.lua                          Auto Shot / Shoot cycle + hunter cast tracking
├── Core\Activity.lua                             the §2 state machine, one instance per group
├── UI\Theme.lua                                  textures, fonts, colours, backdrop builder
├── UI\Bar.lua                                    Bar widget: fill texture + spark + left/right text; SetProgress(0..1)
├── UI\MeleeGroup.lua                             frame with 1–2 Bars bound to a SwingTracker + Activity
├── UI\ShotGroup.lua                              frame with shot bar (+ cast bar) bound to ShotTracker + Activity
├── UI\EditMode.lua                               lib:AddFrame for each group frame; reset-position buttons
├── UI\Options.lua                                Settings canvas panel, /vwst
└── VelocitySwingTimers.lua                 event frame, OnUpdate pump, slash commands, load order glue
```

Naming (collision-free with upstream): namespace prefix `VWST`; frames `VWST_PlayerMeleeFrame`, `VWST_TargetMeleeFrame`,
`VWST_ShotFrame`; SavedVariables `VelocitySwingTimersDB` (account) — **no** per-character SV (profiles cover it);
slash `/vwst`, `/swingtimers`; scan tooltip `VWST_ScanTip`; Settings category "Velocity Swing Timers".

---

## 4. Client adaptor surface

`Client.INTERFACE` (every flavour implements all; `Client_Select` warns on gaps/extras):

| Method | Era (11509) | Forever (16001, Mainline code) |
|---|---|---|
| `PlayerKey()` | `UnitGUID("player")` | same |
| `PlayerDisplayName()` | `UnitName` | `UnitNameUnmodified` name+surname |
| `PlayerFirstName()` | `UnitName` | `UnitName` |
| `PlayerClass()` | `select(2, UnitClass("player"))` | same |
| `SpellInfo(spellIDorName) -> name, castTimeMs, spellID` | `GetSpellInfo` | `C_Spell.GetSpellInfo(...)` table → fields (`castTime`, `spellID`) |
| `PlayerAuraSpellIDs() -> set` | `UnitAura("player", i)` loop, `select(10)` spellId | `C_UnitAuras.GetAuraDataByIndex` / `AuraUtil.ForEachAura` |
| `AttackSpeeds(unit) -> mh, oh|nil` | `UnitAttackSpeed` | same (verify on Forever) |
| `RangedSpeed() -> seconds` | `UnitRangedDamage("player")` first return | same (verify) |
| `InventoryItemID(unit, slot)` | `GetInventoryItemID` | same |
| `Latency() -> ms` | `select(4, GetNetStats())` | same |
| `OpenSettings(categoryID)` | `Settings.OpenToCategory` | same |
| `HasEditMode() -> bool` | `EditModeManagerFrame ~= nil` | same |

Rule from `AddonManagement\PROJECT_STRUCTURE.md`: no flavour branch at any use site; `Client.lua` holds shared
helpers. **Research phase item:** confirm `UnitAttackSpeed`, `UnitRangedDamage`, `START_AUTOREPEAT_SPELL`,
`UNIT_SPELLCAST_SUCCEEDED` payload shapes and the `hooksecurefunc('UseAction')` viability on Forever 16001 — write
findings to `AddonManagement\_EXTERNAL_APIS\wow_swing_timer_api.md`.

---

## 5. Data model

```lua
VelocitySwingTimersDB = {
  version  = 1,
  global   = { inactivity_seconds = 5, fade_seconds = 0.2, font_size = 10 },
  profiles = {            -- keyed by Edit Mode layout name (LayoutProfile)
    ["Modern"] = VWST_ProfileRecord,
  },
}
VWST_ProfileRecord = {
  player = VWST_MeleeGroupSettings, target = VWST_MeleeGroupSettings, shot = VWST_ShotGroupSettings,
}
VWST_MeleeGroupSettings = {
  enabled = true, width = 200, height = 10, point = "CENTER", x = 0, y = -200,   -- position written by EditMode
  ooc_alpha = 0, backdrop_alpha = 0.5, show_border = true, texture = VWST_TextureKey, fill_direction = "fill"|"empty",
  show_offhand = true, show_text = true,
  main_color = {r,g,b,a}, off_color = {r,g,b,a}, text_color = {r,g,b,a},
}
VWST_ShotGroupSettings = {
  enabled = <by class>, width = 300, height = 12, point, x, y = -260, ooc_alpha = 0, backdrop_alpha = 0.5,
  show_border = true, texture = VWST_TextureKey, show_text = true, one_bar = false,
  show_cast_bar = true,            -- Aimed + Multi together (upstream had two toggles)
  show_latency = false, show_multishot_clip = false,
  cooldown_color, cast_window_color, clip_color,
}
```

Settings removed vs upstream: `is_locked` (Edit Mode), `in_combat_alpha` (always 1; alpha is the visibility model's
job), `show_left_text`/`show_right_text` → `show_text`, `show_aimedshot_cast_bar`/`show_multishot_cast_bar` →
`show_cast_bar`, `one_frame` (dead upstream). Options panel: one page, three collapsible group sections + a
"Visibility" header (inactivity slider, OOC alpha per group) + "Layout profile" status line as in VQT.

---

## 6. Core algorithms (pseudo)

```
SwingTracker.New(unit):
  mh = { speed, timer, lastSpeed }, oh = {...} or nil
  OnUpdate(dt): speeds = Client.AttackSpeeds(unit); if speed changed: timer *= new/old; timer = max(0, timer - dt)
  OnSwing(isOffhand): hand.timer = hand.speed; Activity:Touch()
  OnParriedBy(defenderTracker): defender.mh.timer = min(defender.mh.timer, 0.2 * defender.mh.speed)  -- see §9 Q1
  OnNextSwingAbility(spellID): if SpellData.onNextSwing[class][spellID] then OnSwing(false)
  Progress(hand) -> timer / speed (0 = ready)

ShotTracker:
  cycle = Client.RangedSpeed(); castWindow = 0.7 (hunter) | 0.5 (wand) -- TBD verify wand value, upstream uses 0.7 for both
  OnShotSucceeded (75|5019): lastShot = now; timer = cycle; Activity:Touch()
  OnUpdate: if moving and timer <= castWindow: timer = castWindow (restart the stand-still window)
  cast bar: as upstream, via hooksecurefunc + scan tooltip; UNIT_SPELLCAST_START/STOP/FAILED/INTERRUPTED drive colour

Activity (per group):
  Touch(): lastActivity = now
  OnUpdate: active = (now - lastActivity) < global.inactivity_seconds
           targetAlpha = active and (inCombat and 1 or settings.ooc_alpha) or 0
           if editMode then targetAlpha = 1
           frame alpha eases toward targetAlpha over fade_seconds; frame:Hide() when alpha hits 0
```

`OnUpdate` runs on **one** frame for the whole addon and is unregistered (`SetScript(nil)`) when every group is Hidden
and not in Edit Mode — zero cost while questing on a caster.

---

## 7. Edit Mode and profiles

- `UI\EditMode.lua`: for each group frame, `lib:AddFrame(frame, OnMoved, defaultPos, "Velocity Swing Timers: Player")`.
  `OnMoved` writes `point,x,y` into the **active profile record**. Settings buttons: "Reset position".
- `Core\LayoutProfile.lua` verbatim from VQT (namespace/DB names swapped): active Edit Mode layout = profile; create
  copies the active record, rename moves, delete drops. `LayoutProfile.OnChanged` → re-apply all group settings.
- If `Client.HasEditMode()` is false (should not happen on our targets) frames are static at saved/default
  positions; `/vwst status` says so. No drag code of our own.

---

## 8. Milestones

- [x] **M0 Scaffold** — repo, TOCs, `.pkgmeta`, LICENSE, README, icon, Libs, `Core\Util.lua`, `Client\*` skeleton with
  `/vwst status` printing flavour + Client interface check. Loads clean on Era and Forever next to upstream.
- [x] **M1 Research → `_EXTERNAL_APIS\wow_swing_timer_api.md`** — done 2026-11-22 (desk research from Blizzard_SwingTimer
  source + LibClassicSwingTimerAPI live probes). Remaining in-game checks listed in that doc §8; fold into M2/M4 tests.
- [x] **M2 SwingTracker + MeleeGroup (player)** — timer correct vs upstream side by side; haste rescale; on-next-swing
  resets; Activity model with hide/fade; OOC alpha default 0.
- [ ] **M3 Target group (Era only)** — second SwingTracker instance, target-change reset, parry haste both directions.
- [ ] **M4 ShotTracker + ShotGroup** — Auto Shot/wand cycle, move-restart, two-bar and one-bar, Activity.
- [ ] **M5 Hunter cast bar** — Aimed/Multi cast bar, latency slice, clip marker, aura-ID haste.
- [ ] **M6 Edit Mode + LayoutProfile** — placement via Edit Mode on both clients; profile follows layout.
- [ ] **M7 Options panel** — §5 settings only; live preview; defaults button per group.
- [ ] **M8 Release prep** — `PROJECT_STRUCTURE.md` row, `webhooks.cs` table row, CurseForge project, first tag.

Each milestone ends with a side-by-side test against upstream on Era (both installed) and a Forever load test.

---

## 9. Open questions / TBD

Research done 2026-11-22 → `AddonManagement\_EXTERNAL_APIS\wow_swing_timer_api.md` (read it before coding). Verdicts:

1. **Parry haste — RESOLVED.** Defender's MH swing: `remaining > 0.6·speed → remaining − 0.4·speed`; `0.2·speed <
   remaining ≤ 0.6·speed → 0.2·speed`; `≤ 0.2·speed → unchanged`. Era source: CLEU `SWING_MISSED` `PARRY` with
   **destGUID** = parrier. Forever: `UNIT_COMBAT("player","PARRY")`, back-dated 0.65 s. Upstream's version is inverted
   and wrong-shaped; not ported.
2. **Textures — DECIDED 2026-11-22: Blizzard stock only, no copied upstream art.** `Media\` folder is dropped.
   Bar fill is a **visual texture picker** (EasyFrames-style dropdown: each row is a swatch of the texture with its name
   over it) over a curated `VWST_TextureKey -> path` table in `UI\Theme.lua`, Blizzard paths that exist on **every**
   client we ship to (verify in M1 on Era + Forever), e.g. `Interface\TargetingFrame\UI-StatusBar`,
   `Interface\RaidFrame\Raid-Bar-Hp-Fill`, `Interface\PaperDollInfoFrame\UI-Character-Skills-Bar`,
   `Interface\Buttons\WHITE8x8` (flat), `Interface\CastingBar\UI-CastingBar-Bar`. Spark =
   `Interface\CastingBar\UI-CastingBar-Spark`; border = `Interface\Tooltips\UI-Tooltip-Border`; background =
   `Interface\Tooltips\UI-Tooltip-Background`. If **LibSharedMedia-3.0** is present (optional dep, not embedded) its
   `statusbar` list is appended to the picker so users with SharedMedia packs see their textures too — missing SM
   texture at load falls back to the default key.
   **Verified** (LSM 12000005 defaults): `Blizzard`, `Blizzard Character Skills Bar`, `Blizzard Raid Bar`, `Solid` are
   the built-in set; the player's Era install already has LSM + EasyFrames textures, so the picker populates.
3. **Wand — RESOLVED.** Shoot 5019 is a 0.5 s-cast auto-repeat ranged attack on its own cycle (`UnitRangedDamage`),
   **independent of the melee clock**. No documented stand-still window; LibClassicSwingTimerAPI treats it like Auto
   Shot's movement model. Ship: same ranged cycle bar; cast-window colouring is **hunter-only**.
   Auto Shot window = `0.52 · rangedSpeed / rangedBaseSpeed` (base from the weapon tooltip), not upstream's flat 0.7.
4. **Hunter on Forever — RESOLVED.** `START/STOP_AUTOREPEAT_SPELL` fire; `UNIT_SPELLCAST_FAILED_QUIET 75` = movement
   cancel; `PLAYER_SWING` type 2 anchors the shot. Cast bar via **`UNIT_SPELLCAST_START` + `UnitCastingInfo`**, no
   `hooksecurefunc`/scan-tooltip (upstream only hooked because its START handler was commented out).
6. **Forever anchors — NEW, decisive.** CLEU registration is **refused** on Forever; `UnitAttackSpeed`/`UnitRangedDamage`
   are **secret in any combat**. Player swings come from `PLAYER_SWING(swingDuration, swingType)` (plain number, MH=0
   OH=1 Ranged=2). **No target swing source exists on Forever → target group is Era-only** (hidden + greyed in options
   on Forever). No haste rescale on Forever; re-anchor from the next `PLAYER_SWING`. `UnitAttackSpeed("player")` has a
   3rd `ranged` return on Forever. Attack toggle ID is 6803 (Era 6603).
7. **Forever ships Blizzard_SwingTimer** (three Edit-Mode bars, CVar `showSwingTimer`). Ours coexists; README tells the
   user to set Blizzard's to Hidden in Edit Mode if they want only ours. Their atlases are Forever-only — not used.
8. **Flavour detection**: `WOW_PROJECT_ID` is `MAINLINE` on Forever → `Client_Select` keys on
   `select(4, GetBuildInfo())` ∈ [16000, 20000) for `forever`, `WOW_PROJECT_CLASSIC` for `classic_era`.
5. **Camelot TOC** — include from M0 like other Velocity addons, or add when an Anniversary client exists on disk?
   (Default: include; publish.cmd skips absent flavours.)