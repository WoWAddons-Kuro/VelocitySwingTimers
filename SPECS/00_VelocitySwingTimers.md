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
  an on-next-swing ability landing, `UNIT_SPELLCAST_SUCCEEDED` for Auto Shot / Shoot. **Toggling auto-attack on is
  NOT activity** (tried and reverted 2026-11-22: a druid at range casting Wrath has the toggle on and never swings;
  the bar appeared anyway). Cast-completion swing *resets* are not activity either. Only a landed swing/shot is.
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
  show_border = true, texture = VWST_TextureKey, show_text = true, style = VWST_ShotBarStyle ("mirrored" | "onebar"),
  show_cast_bar = true,            -- Aimed + Multi together (upstream had two toggles)
  show_latency = false, show_multishot_clip = false,
  cooldown_color, cast_window_color, clip_color,
}
```

**`VWST_ShotBarStyle`** (was `one_bar` bool before 2026-11-24; `DB.Profile()` migrates). Upstream's own explainer images
are in the reference zip, `Images\HunterBarExplainedFullAlpha.png` and `HunterOneBarExplainedAlpha.png`:

| style | fill anchor | cooldown part ("can move or cast") | stand-still window ("don't move or cast") |
|---|---|---|---|
| `mirrored` (default, upstream default) | **centre** — the fill texture is anchored `TOP`, so a width change grows/shrinks symmetrically out of the middle | `cooldown_color` (white), width `W·(remaining−window)/(cycle−window)`: **shrinks into the centre** | `cast_window_color` (red), width `W·(1 − remaining/window)`: **grows out of the centre** to full as the shot fires; moving restarts it |
| `onebar` (YaHT) | left | `cooldown_color` fills left→right over the **whole** cycle | fixed `cast_window_color` block at the right end, width `W·window/cycle`, so you see the window coming |

Wands have `window = 0`, so `mirrored` only ever shrinks and `onebar` shows no block. The options panel shows both styles
as **live looping preview bars** (3 s cycle, 0.7 s window, in the user's colours/texture); click one to select it
(`UI\Options.lua`). `ShotGroup.StyleBar` / `ShotGroup.RenderBar` are the shared pure drawing functions used by both
the live bar and the previews, so the preview can never drift from the real thing.

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
- [ ] **M3 Enemy swing bars (Era only)** — see §10. SwingTracker instances per unit token (target, focus), merged melee+ranged anchor, target/focus-change reset, enemy-side parry haste, "why not here" paragraph on Forever.
- [x] **M4 ShotTracker + ShotGroup** — Auto Shot/wand cycle, move-restart, two-bar and one-bar, Activity.
- [ ] **M5 Hunter cast bar** — Aimed/Multi cast bar, latency slice, clip marker, aura-ID haste.
- [x] **M6 Edit Mode + LayoutProfile** — placement via Edit Mode on both clients; profile follows layout.
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

---

## 12. Shot bar redesign — the "channel" model (owner 2026-11-24) — do BEFORE M3

### 12.1 Why

Both upstream presentations (mirrored, YaHT one-bar) draw *one* fill that means two things: "where am I in the charge"
and "when will the delayed shot go off". When the player moves inside the stand-still window the engine re-schedules the
shot (`shotEnd = now + 0.5 + window`) and the fill **retreats** — observed 2026-11-24 as "the bar backs up ~15 % past the
red". The red-as-bar-colour phase also ends as a solid red bar at `0.0` that reads as "still stand still" when in fact the
shot is loaded and only *the player* is delaying it. The information a hunter actually needs is:
1. **is the charge done** (may I stop moving now), and
2. **am I wasting it** (ready, but I am moving / GCD-locked so the cast cannot run).

### 12.2 The visual

```
charging (moving or not)          ready, moving (stalling)           ready, standing still (casting)
┌──────────────────────┬──────┐   ┌──────────────────────┬──────┐   ┌──────────────────────┬──────┐
│██████████            │▓▓▓▓▓▓│   │██████████████████████│▓▓▓▓▓▓│   │██████████████████████│▓▓▓▓▓▓│  red rail (top)
│██████████            │      │   │██████████████████████│      │   │██████████████████████│███   │  centre channel
│██████████            │▓▓▓▓▓▓│   │██████████████████████│▓▓▓▓▓▓│   │██████████████████████│▓▓▓▓▓▓│  red rail (bottom)
└──────────────────────┴──────┘   └──────────────────────┴──────┘   └──────────────────────┴──────┘
 white fills over (speed − window)  white LOCKED at the window edge    channel fills white over `window`
```

| Region | Drawn as | Meaning |
|---|---|---|
| **Charge fill** | `cooldownColor` (white), left → right over the charge part `speed − window`; **never moves backwards** | "pulling the string". Move freely. |
| **Window rails** | `castWindowColor` (red) **top and bottom rails only**, each `railHeight` px, spanning the last `window / speed` of the track; the middle `height − 2·railHeight` px is an open channel | the stand-still window, as a fixed landmark |
| **Channel fill** | `cooldownColor` white inside the channel, left → right over `window` | the Auto Shot cast actually running. Fills **only while the engine is letting the cast run** (standing still, off GCD, in range). Moving → channel stays empty and the charge fill sits locked at the rail start. |
| Numeric (right) | charging: seconds to ready. ready: **`+stall`** counting up, seconds the shot has been held past its earliest possible time (`0.0` while casting cleanly) | the lost-DPS number |

Wands (`window = 0`): no rails, no channel; just the charge fill. Nothing else changes for them.

### 12.3 State and arithmetic (`Core\ShotTracker.lua`)

```
VWST_ShotPhase        = "charging" | "ready"
VWST_ShotChannelState = "idle" | "blocked_moving" | "blocked_still" | "casting"     -- only meaningful when ready
shotStart, shotEnd      -- as today: lastShot, lastShot + speed. shotEnd is NEVER moved by FAILED_QUIET (fix 2026-11-24)
readyAt     = shotEnd − window          -- earliest instant the cast may begin
blockedUntil = nil | GetTime()          -- the engine's next retry tick; set on every FAILED_QUIET 75 (now + 0.5)
castStartAt  = nil | GetTime()          -- when the CURRENT cast attempt began (see 12.4)
moving       = GetUnitSpeed("player") > 0   -- Era: readable. Forever: PlainNumber → nil → treated as not moving

Charge(now)  = clamp((now − shotStart) / (readyAt − shotStart), 0, 1)
Phase(now)   = now < readyAt and "charging" or "ready"
BlockFrac(now) = blockedUntil and clamp((blockedUntil − now) / 0.5, 0, 1) or 0      -- remaining fraction of the 0.5 s block
ChannelState(now) =
    Phase ~= "ready"      → "idle"
    BlockFrac > 0, moving → "blocked_moving"
    BlockFrac > 0         → "blocked_still"
    moving                → "blocked_moving" (BlockFrac treated as 1: the engine WILL refuse at the next tick; the event re-syncs)
    otherwise             → "casting"
CastFrac(now) = ChannelState == "casting" and clamp((now − castStartAt) / window, 0, 1) or 0
Stall(now)    = max(0, now − readyAt − (castStartAt and (now − castStartAt) or 0))   -- seconds ready but not casting
```

### 12.4 Driving the channel — the cast has no START event

Era has no `UNIT_SPELLCAST_START` for Auto Shot; the only signal is the inverse: `UNIT_SPELLCAST_FAILED_QUIET 75` every
~0.5 s while the retry cannot go off (moving, GCD, range). That event fires at the END of a 0.5 s block, and the next
retry is 0.5 s later — so each one is an exact, knowable deadline. Rules:

- `FAILED_QUIET 75` while `ready`: `blockedUntil = now + AUTO_SHOT_RECAST_DELAY`; `castStartAt = nil`
- first tick where `ChannelState` becomes `"casting"`: `castStartAt = now`
- `ChannelState` leaves `"casting"` (player moved): `castStartAt = nil` (the engine cancelled; the FAILED_QUIET will follow)
- `SUCCEEDED 75` / `PLAYER_SWING ranged`: anchor as today; `blockedUntil = nil`, `castStartAt = nil`
- **Movement gate is mandatory** (decided 2026-11-24, was TBD-A): `moving` is what tells `blocked_moving` from
  `blocked_still`, and it floods the channel the instant the player moves instead of ~0.5 s later when the event lands.

`OnSpellFailedQuiet` never re-anchors `shotEnd` (replaces the "only inside the window" rule from the earlier fix): the
clock stays truthful and the charge fill can never retreat. Forever (`PLAYER_SWING` anchors) behaves identically.

### 12.4a The block in the channel — anchor side = your input, drain = the engine's clock (owner 2026-11-24)

The 0.5 s block is drawn **inside the channel as a red (`castWindowColor`) block whose width is `BlockFrac`**. Which wall
it hugs tells the player whether they are currently obeying; its shrinking tells them how long until the engine retries:

```
blocked_moving                            blocked_still                               casting
┌─────────────────────┬──────┐            ┌─────────────────────┬──────┐            ┌─────────────────────┬──────┐
│█████████████████████│▓▓▓▓▓▓│            │█████████████████████│▓▓▓▓▓▓│            │█████████████████████│▓▓▓▓▓▓│
│█████████████████████│████  │            │█████████████████████│  ████│            │█████████████████████│███   │
│█████████████████████│▓▓▓▓▓▓│            │█████████████████████│▓▓▓▓▓▓│            │█████████████████████│▓▓▓▓▓▓│
└─────────────────────┴──────┘            └─────────────────────┴──────┘            └─────────────────────┴──────┘
 red anchored LEFT, drains rightward:      red anchored RIGHT, drains leftward:       white fills L→R over `window`
 "it is in your way and you are not        "the gate is opening from your side;
  allowed in yet"                           be still when it clears"
```

- **`blocked_moving`**: red block anchored at the channel's **left** wall, width `BlockFrac · channelWidth`, so it sits
  against the charge fill's entry point and recedes to the right as the block burns. Hits zero while still moving → the
  next `FAILED_QUIET` refloods it from the left.
- **`blocked_still`**: the same block **anchored at the right wall**, draining from the left — the gate opens from the
  white's side. When it reaches zero the state becomes `casting` and white flows in.
- **Flipping sides preserves the remaining width.** Moving→still or still→moving mid-drain re-anchors the block but does
  not touch `blockedUntil`: the engine's clock does not care about the player's feet, only the anchor side changes. This
  continuity is what makes it read as ONE block changing attitude rather than two events.
- **`casting`**: no red in the channel; white fills left → right over `window`; `SUCCEEDED 75` ends it.
- Red and white never overlap: red occupies `[0, BlockFrac]` or `[1 − BlockFrac, 1]` of the channel, white `[0, CastFrac]`,
  and `CastFrac` is 0 whenever `BlockFrac > 0`.

### 12.5 Drawing (`UI\ShotGroup.lua`)

`VWST_ShotBarParts = { bar, railTop, railBottom, channelFill, channelBlock }` (`windowBlock` and `centerLine` go away).
`ShotGroup.StyleBar` sizes the rails and channel from `s.width`, `s.height`, `railHeight`, and `window / speed`;
`ShotGroup.RenderBar(parts, s, width, snapshot)` takes a
`VWST_ShotSnapshot = { phase, charge, channelState, blockFrac, castFrac, stall, remaining }` so the options preview can
feed a scripted sequence. The main `Bar` fill width is `charge · (width · (1 − window/speed))` — capped at the rail start,
so it can never enter or retreat from the window. `channelBlock` is one texture: `SetPoint("LEFT")` for `blocked_moving`,
`SetPoint("RIGHT")` for `blocked_still`, width `blockFrac · channelWidth`.

### 12.6 Settings and options

- **DECIDED 2026-11-24 (was TBD-B): the channel model is a THIRD style, `VWST_ShotBarStyle = "mirrored" | "onebar" |
  "channel"`, and becomes the default.** Mirrored and one-bar stay as they are for players who want upstream parity;
  `DB.Profile()` leaves existing `style` values alone and new records get `"channel"`. A third preview card is added,
  looping charge → `blocked_moving` drain (0.5 s) → flip to `blocked_still` drain (0.5 s) → casting fill → **green
  flash** → repeat, so the panel demonstrates every state including the side flip and the shot event.
- New `railHeight` (default **2** px, slider 1–4) in the left column under Text size (channel style only; greyed otherwise).
- New `shotFlashColor` RGBA (default green `{0.2, 0.9, 0.2, 1}`) and `shotFlashSeconds` (constant 0.25, not a setting).
- Swatch row: Text · Border · Charge (`cooldownColor`) · Window (`castWindowColor`) · **Shot (`shotFlashColor`)**.
- Spec §5 table for `VWST_ShotBarStyle` gains the `channel` row pointing here.

### 12.6a The shot event — green flash of the window region (owner 2026-11-24)

When the shot actually fires (`SUCCEEDED 75` / `PLAYER_SWING ranged`), the **whole window region** — both rails and the
channel, i.e. the red area — flashes `shotFlashColor` for `shotFlashSeconds` (0.25 s), fading linearly back to its normal
colours while the new cycle's charge fill starts from the left. The red region *is* the shot event: it is where the shot
was fought for, and the flash closes the loop. Implementation: `flashUntil = now + shotFlashSeconds` on anchor; in
`RenderBar`, `flashFrac = clamp((flashUntil − now) / shotFlashSeconds, 0, 1)` lerps rails + channel vertex colour from
`shotFlashColor` toward `castWindowColor` / channel-empty. `VWST_ShotSnapshot` gains `flashFrac`.

Lost-shot-time display and counting (the `+stall` numeric and any totals) is **DEFERRED** by the owner until the visual
above is confirmed in game; the numeric shows `remaining` while charging and `0.0` while ready for now.

### 12.7 Steps

- [ ] 1. `ShotTracker`: `readyAt`, `blockedUntil`, `castStartAt`, `moving`; `Snapshot(now)` returning `VWST_ShotSnapshot`; `OnSpellFailedQuiet` → `blockedUntil`, never touches `shotEnd`; `/vwst status` prints phase + channel state + stall
- [ ] 2. `ShotGroup.StyleBar/RenderBar` on `VWST_ShotSnapshot`; rails + channelFill + channelBlock (side-anchored); numeric rules
- [ ] 3. Options: single preview card with the scripted sequence; `railHeight` slider; swatch labels; drop `style` (TBD-B)
- [ ] 4. DB: `railHeight` default; delete `style`; spec §5 note
- [ ] 5. In-game: hunter — move through the window and confirm the white never retreats, the channel only fills while still, `+stall` counts; wand — plain fill unchanged; Forever load test

---

## 11. Options panel compaction (owner 2026-11-24) — do BEFORE M3

Each bar group section becomes:

```
[x] Enable            [ ] Enable Off-hand                 ← player melee ("Enable Focus Target" for the Enemy section)
┌ left column ───────────────┐  ┌ right column ──────────────────┐
│ Width: 200                 │  │ Inactive opacity: hidden       │
│ Bar height: 12             │  │ Out of combat opacity: hidden  │
│ Text size: 10              │  │ Backdrop opacity: 50%          │
└────────────────────────────┘  └────────────────────────────────┘
Text: [■]   Border: [■]   Main-hand: [■]   Off-hand: [■]    ← swatch row, IMMEDIATELY above the preview cards
[ direction / style preview cards, full width ]
```

The top section is renamed **"Visibility Timeouts"** and keeps only the two global sliders (inactivity seconds,
fade seconds). **Text size moves out of it and becomes per group**: `fontSize` leaves `DB.DEFAULT_GLOBAL` and is added to
every group record (default 10; migration copies the old global value into each existing record, then deletes it from
`global`). `Bar:ApplyStyle` already takes `fontSize` from the style table, so the groups just pass `s.fontSize`.

### 11.1 Removed controls → RGBA colours (alpha 0 = gone)

| Old | New | Semantics |
|---|---|---|
| `showText` checkbox | `textColor` RGBA (already exists) | alpha 0 → the left label and right numeric are hidden |
| `showBorder` checkbox | **`borderColor` RGBA** (new, default `{1,1,1,1}`) | alpha 0 → `Theme.BackdropNoBorder`; otherwise `Theme.Backdrop` with `SetBackdropBorderColor(rgba)` |
| `backdropAlpha` slider | unchanged | fill behind the bar only; no longer linked to the border colour |

`DB.Profile()` migration: `showText == false` → `textColor.a = 0`; `showBorder == false` → `borderColor.a = 0`; then
the two booleans are deleted from the record. `Bar:ApplyStyle` reads `textColor.a` (drop `showText`); group `Layout`
reads `borderColor`.

### 11.2 Swatch row per group

| Group | Swatches (left → right) | Profile keys |
|---|---|---|
| Player melee | Text · Border · Main-hand · Off-hand | `textColor` `borderColor` `mainColor` `offColor` |
| Shot | Text · Border · Cooldown · Stand-still | `textColor` `borderColor` `cooldownColor` `castWindowColor` |
| Enemy (M3, Era) | Text · Border · Target · Focus | `textColor` `borderColor` `color` on the target and focus records |

Widget `Options.Swatch(parent, tableFn, key, label)`: a 16×16 colour square (`Interface\ChatFrame\ChatFrameColorSwatch`
for the frame look, inner texture set to the colour) with a checkerboard under it so alpha reads, label to its left.
Click → `ColorPickerFrame:SetupColorPickerAndShow(VWST_ColorPickerInfo)`. Verified present on **both** clients
(`_ref\blizzard\FloatingChatFrame.lua` and `_ref\blizzard\classic_era\FloatingChatFrame.lua`), so no `Client` surface:

```lua
-- VWST_ColorPickerInfo
{ r, g, b, opacity = a, hasOpacity = true,
  swatchFunc  = function() local r,g,b = ColorPickerFrame:GetColorRGB(); write r,g,b; Apply() end,
  opacityFunc = function() write a = ColorPickerFrame:GetColorAlpha(); Apply() end,
  cancelFunc  = function(prev) write prev.r,g,b,a (captured before opening); Apply() end }
```

Alpha convention: on Era 11509 `GetColorAlpha()` returns **alpha** directly (the Era FCF source applies `1.0 -` only
because chat frames store *transparency*); Mainline is the same. We store alpha as-is on both. Verify the first time
in game by setting the slider to 0 and confirming the element disappears (log result in §9).

Live update: `swatchFunc`/`opacityFunc` fire continuously while dragging; `Apply()` re-skins the live bars and
`Options.Refresh()` redraws the preview cards, so the cards double as the colour preview.

### 11.3 Two-column slider layout

`Section` gains `AddRow(leftWidget, rightWidget, height, dy)`: anchors `left` at `TOPLEFT` of the row and `right` at
`TOPLEFT + (BOX_W − 2·PAD)/2`, advances by one `height`. `Slider` width shrinks from 220 → **200** so two fit in 560.
The Enable row is a `AddRow(Check enable, Check offhand|focus)`. Section height drops from ~9 rows to 5.

### 11.4 Enable row per group

| Group | Left | Right |
|---|---|---|
| Player melee | Enable | **Enable Off-hand** (§10.9 class gating: greyed + red X for non-dual-wield classes; default off) |
| Shot | Enable | — (Hunter cast bar toggle lands here in M5) |
| Enemy (Era) | Enable | **Enable Focus Target** |

### 11.5 Files

`UI\Options.lua` (Swatch, AddRow, section rebuild, remove Check for showText/showBorder), `UI\Bar.lua` (`textColor.a`
gates text), `UI\MeleeGroup.lua` + `UI\ShotGroup.lua` (`borderColor`), `Core\DB.lua` (`borderColor` default, migration,
`showOffhand = false`), `Core\SpellData.lua` (`DUAL_WIELD_CLASSES`), spec §5.

### 11.6 Steps

- [ ] 1. DB: `borderColor` + `fontSize` defaults on melee/shot; migrate `showText`/`showBorder`/global `fontSize`; `showOffhand` default false
- [ ] 2. Bar/Groups consume `textColor.a`, `borderColor`, per-group `fontSize`; previews follow via StyleBar/ApplyStyle
- [ ] 3. `Options.Swatch` + ColorPickerFrame wiring; verify alpha direction in game (§11.2)
- [ ] 4. `Section:AddRow`; "Visibility Timeouts" section (2 sliders); rebuild the group sections to the §11 layout
        (Width / Bar height / Text size left, opacities right); swatch row directly above the cards
- [ ] 5. Off-hand checkbox class gating (§10.9) in the Enable row
- [ ] 6. In-game pass: every control still round-trips; Edit Mode OH sample per §10.9

---

## 10. M3 — Enemy swing bars (Classic Era only)

Decided 2026-11-24 with the owner. Upstream had a "Target" module (MH/OH off `UnitAttackSpeed("target")`, CLEU anchors);
we generalise it to **enemy units** = `target` always, `focus` optional, and one bar per unit.

### 10.1 Why Era only, and what Forever sees

`_EXTERNAL_APIS\wow_swing_timer_api.md` §20: on Forever CLEU registration is refused and `PLAYER_SWING` is
player-only. `UNIT_COMBAT("target", …)` fires for the *player's* defensive events, not the mob's swings, so there is
**no enemy swing anchor** on Forever. `Client.SupportsTargetSwings()` is the switch.

- **Era**: the Enemy group frame, tracker(s), Edit Mode registration and a full options section exist.
- **Forever / any client where `SupportsTargetSwings()` is false**: **nothing is created or registered** — no frame, no
  Edit Mode entry, no tracker. The options panel still shows the **"Enemy swing bars"** section, containing only a
  paragraph: *"Not available on this client. WoW Forever (and other modern-UI clients) do not expose the combat log to
  addons and only report the player's own swings, so there is no way to know when an enemy attacks. Enemy swing bars
  work on Classic Era / Anniversary."* No controls.

### 10.2 One bar per enemy, melee and ranged merged

There is **no enemy ranged-speed API** (`UnitRangedDamage` is player-only; upstream never tracked enemy ranged). CLEU does
report an enemy's ranged auto as `RANGE_DAMAGE` / `RANGE_MISSED` (source = enemy GUID). Decision (owner): **one bar per
enemy**, anchored on *either* `SWING_*` *or* `RANGE_*` from that GUID, speed = `UnitAttackSpeed(unit)` MH. For a ranged
mob the melee speed is only an approximation of its shot cycle — accept and document; no second bar. No off-hand bar for
enemies (mobs' OH speed is rarely meaningful; upstream showed it, we don't).

### 10.3 Units

`VWST_EnemyUnitToken = "target" | "focus"`. **Each unit is its own bar group: own frame, own Edit Mode entry, own saved
position** (owner 2026-11-24: the focus bar must be placeable next to the focus unit frame, not stacked under the
target bar). Profile keys `target` and `focus`; Edit Mode labels "Target Timer" / "Focus Timer". The target group is
enabled by the Enemy section's Enable checkbox; the focus group by its own "Show focus bar" checkbox (default **false**).
Each has one `SwingTracker` instance and one `Bar`, label `"Target"` / `"Focus"` on the left, countdown on the right.
If focus GUID == target GUID the focus group stays hidden in play (it would duplicate the target bar); in Edit Mode
both always render so they can be placed.

### 10.4 SwingTracker becomes instance-based

Today `Core\SwingTracker.lua` is a singleton. Refactor to `SwingTracker.New(cfg)`; **`NS.SwingTracker` stays the player
instance** so `MeleeGroup`, `EditMode`, `/vwst status` are untouched.

```lua
-- VWST_SwingTrackerConfig
{ unit = "player" | "target" | "focus",
  kind = "player" | "enemy" }       -- enemy: no cast-reset / NEXT_MELEE / autorepeat / weapon-swap logic, MH only
```

| Rule | player | enemy |
|---|---|---|
| Anchor | `OnSwing(hand, speed)` | `OnEnemySwing(unit, speed)` (SWING_* or RANGE_* from that unit's GUID) |
| Speed | `Client.AttackSpeeds()` | `Client.UnitAttackSpeed(unit)` → mh |
| Cast-time reset, NEXT_MELEE, RESET_SWING, autorepeat, weapon swap | yes | **no** |
| Parry haste | player parried (CLEU dest = player) → player MH | **enemy parried our swing** (CLEU `SWING_MISSED PARRY`, dest = enemy GUID) → that enemy's MH, same 40 % / 20 % rule (owner: parry *visuals* to be discussed separately) |
| Haste rescale | `UNIT_ATTACK_SPEED "player"` | `UNIT_ATTACK_SPEED unit` |
| Clear | `PLAYER_DEAD`, entering world | **`PLAYER_TARGET_CHANGED`** / **`PLAYER_FOCUS_CHANGED`** (GUID changed → clear and re-read speed), `UNIT_DIED` with that GUID, entering world |
| Activity | landed player swing | landed **enemy** swing on anyone — a mob that is casting or chasing someone else shows nothing until it actually swings |

### 10.5 Client surface additions

`Client.INTERFACE` += `"UnitAttackSpeed"` `(unit) -> mh|nil` and `"UnitKey"` `(unit) -> GUID|nil`. Era: real; Forever:
`UnitAttackSpeed` returns `Util.PlainNumber` (secret → nil), `UnitKey` = `UnitGUID` (both harmless, never used there).

New `VWST_SwingSink` callbacks (Era `StartSwingSource` emits; Forever never does):
- `OnEnemySwing(unit, speed)` — CLEU `SWING_DAMAGE|SWING_MISSED|RANGE_DAMAGE|RANGE_MISSED`, `src == UnitGUID(unit)`; if both target and focus match the same GUID, emit for `"target"` only
- `OnEnemyParried(unit)` — CLEU `SWING_MISSED` `PARRY`, `dst == UnitGUID(unit)`, `src == player`
- `OnEnemyChanged(unit)` — `PLAYER_TARGET_CHANGED` / `PLAYER_FOCUS_CHANGED`
- `OnEnemyDied(guid)` — CLEU `UNIT_DIED`
- `OnEnemyAttackSpeedChanged(unit)` — `UNIT_ATTACK_SPEED` for `target` / `focus` (register as unit events)

The Era CLEU handler caches `targetGUID` / `focusGUID` on the change events rather than calling `UnitGUID` per CLEU line.

### 10.6 Settings and UI

```lua
DB.DEFAULT_ENEMY = {              -- VWST_EnemyGroupSettings; profile keys "target" and "focus", one record each
  enabled = false,                -- target: the section's Enable; focus: its "Show focus bar" checkbox
  width = 200, height = 12, point = "CENTER", x = 0, y = -140,     -- focus default: y = -110 so they don't overlap
  inactiveAlpha = 0, oocAlpha = 0, backdropAlpha = 0.5, showBorder = true,
  texture = "Blizzard", fillDirection = "fill", showText = true,
  color = { r = 0.85, g = 0.2, b = 0.2, a = 1 },                   -- focus default: { 0.85, 0.5, 0.2 }
  textColor = { r = 1, g = 1, b = 1, a = 1 },
}
```

- `UI\MeleeGroup.lua` → generalise to `MeleeGroup.New(cfg)` with `{ key, frameName, bars = { {label, trackerFn, colorKey, shownFn} } }`
  and instantiate three times: `NS.MeleeGroup` (player; MH/OH), `NS.TargetGroup` (one bar), `NS.FocusGroup` (one bar).
  Era-only creation in `VelocitySwingTimers.lua`: `if Client.SupportsTargetSwings() then Stage("TargetGroup", …); Stage("FocusGroup", …) end`.
- `UI\EditMode.lua` GROUPS += `target = { label = "Target Timer" }`, `focus = { label = "Focus Timer" }`; `Register`
  already no-ops when the module/frame is absent (Forever). The focus frame is registered only while its group is
  enabled (nothing to place otherwise); `Register` re-runs on Edit Mode enter, so ticking the box then opening Edit Mode works.
- `UI\Options.lua`: one `GroupSection("Enemy swing bars", Target, …)` with Enable, **Show focus bar** (writes
  `profile.focus.enabled`), the standard sliders and direction preview cards (label "Target"). Size / opacity / border /
  text / direction sliders write to **both** records — target and focus share everything except position and colour.
  On `not SupportsTargetSwings()` the section is the §10.1 paragraph only.
- `/vwst status` prints target and focus tracker + group lines when present.

### 10.7 Files

`Core\SwingTracker.lua` (instances), `Client\Client.lua` + `Client_ClassicEra.lua` + `Client_Forever.lua`, `Core\DB.lua`,
`UI\MeleeGroup.lua` (instances), `UI\EditMode.lua`, `UI\Options.lua`, `VelocitySwingTimers.lua`, this spec §3/§5/§6.

### 10.8 Steps

- [ ] 1. `SwingTracker.New(cfg)`; player instance bound to `NS.SwingTracker`; behaviour identical (regression check: `/vwst status`, melee bar side by side)
- [ ] 2. Client surface + Era CLEU emission of the enemy callbacks (`/vwst trace` shows `OnEnemySwing("target", 2.0)` on a mob hit)
- [ ] 3. Enemy tracker instances (target, focus) wired to the sink; status line
- [ ] 4. `MeleeGroup.New(cfg)`; `NS.EnemyGroup`; Era-only creation; DB defaults
- [ ] 5. Edit Mode "Enemy Timer"; options section (Era controls / Forever paragraph); preview cards
- [ ] 6. Side-by-side test vs upstream Target bar on Era; Forever load test shows paragraph only, no frame
- [ ] 7. §10.9 off-hand checkbox: class gating, default off, Edit Mode sample

### 10.9 "Show off-hand bar" — class gating and Edit Mode (owner 2026-11-24)

Current defects: `showOffhand` defaults **true** and the melee group's Edit Mode sample only shows the OH bar when a
weapon happens to be equipped in the off hand (`Layout`: `showOff = s.showOffhand and SwingTracker.HasOffhand()`), so
the checkbox has no visible effect in Edit Mode and is meaningless for classes that can never dual-wield.

| Rule | Behaviour |
|---|---|
| Default | `showOffhand = false` (DB default; `ApplyDefaults` leaves existing records alone, so only new profiles change) |
| Class gating | `SpellData.DUAL_WIELD_CLASSES = { WARRIOR, ROGUE, HUNTER, SHAMAN }` (Classic Era / Forever vanilla ruleset — Shaman dual wield is a talent but the class *can*; DK/Monk/Demon Hunter don't exist on our target clients) |
| Class can never dual-wield | checkbox **disabled**, label greyed, and the check texture replaced by a **red X** (`Interface\Buttons\UI-GroupLoot-Pass-Up`) so it reads as "not applicable" rather than "unchecked"; tooltip *"<Class> cannot dual-wield."* |
| Class can dual-wield, checkbox on | OH bar appears in **Edit Mode** whenever the option is on, with the sample fill, **even with nothing in the off hand** — the point of Edit Mode is to place it. The group frame grows to two bars. |
| Class can dual-wield, checkbox off | OH bar never shown, Edit Mode or not; frame is one bar tall |
| In play | unchanged: OH bar only draws when `SwingTracker.HasOffhand()` AND the option is on |

Implementation: `MeleeGroup.Layout` computes `showOff = s.showOffhand and (NS.editModeActive or SwingTracker.HasOffhand())`
and `Layout()` is re-run on Edit Mode enter/exit (`EditMode.ApplyAll` already calls `Refresh`). `Options.Check` grows an
optional `availableFn` → when false: `SetEnabled(false)`, grey label, swap `GetCheckedTexture`/`GetNormalTexture` to the
red X atlas, tooltip from `unavailableTip`. `Client.PlayerClass()` drives it; no new client surface.

The same `availableFn` hook is what the Enemy section's controls will use on Forever if we ever want greyed controls
instead of the paragraph — today the paragraph stands (§10.1).