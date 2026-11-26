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

## 14. Range-entry weapon sound (owner 2026-11-24) — do BEFORE M3

**Reference behaviour: WoW Forever.** Blizzard deliberately restored this with the 0.5 s Auto Shot delay (Sept–Oct
2026 dev notes and forum confirmation): when a hostile target comes **into Auto Shot range from out of range** the
client plays the bow-draw / gun-cock. Searched every addon in the owner's Forever install (519 Lua files, 2026-11-24):
nothing emits a weapon sound on a range edge, and the only `IsSpellInRange` caller is ForeverAuras' aura-condition
code. It is the game.

Owner: *"my single most favourite improvement of Forever so far — I don't have to stare at my bar waiting for numbers
to go from red to grey to know something is in range, I just listen for it. It makes hunter play so smooth."* That is
the design goal in one sentence: **move the "can I act yet?" question from the eyes to the ears.**

Era does not do this (Classic plays the draw on every shot, not on range entry). So this feature exists to make Era
sound like Forever. **Default: ON on Classic Era / Anniversary, OFF on Forever** (owner 2026-11-24) — Forever has it
natively and we must not double it. The Forever tooltip says so. The checkbox is still available there for anyone
who wants ours instead (e.g. a different sound).

**Direction (owner):** the same cue for **casters** — "it's more complicated when they have multiple ranges." §14.8
keeps the architecture open for it: the trigger is a *configurable spell per class*, not a hardwired Auto Shot 75.

### 14.1 Trigger

```
VWST_RangeBand = "none" | "out" | "in"        -- "none": no attackable hostile target
VWST_RangeCueSpell = spellID                  -- the spell whose range defines "in". Hunter: AUTO_SHOT 75 (8-35 yd).
                                              --   Casters (§14.8): the class's primary nuke; later configurable.
poll every RANGE_POLL_SECONDS = 0.2 while a hostile attackable target exists (EverAuras samples 5 Hz; cheap)
band = IsSpellInRange(VWST_RangeCueSpell, "target") == true  and "in"  or "out"
play when:   previousBand == "out"  and  band == "in"
             and the previous band was observed on the SAME target GUID (target swap -> silent; UPDOG does the same)
             and not channeling, not dead, player has a ranged weapon
never when:  previousBand == "none" (new target already in range: silent - that is a target change, not an approach)
```

`IsSpellInRange` is a plain boolean on both clients, in combat too (`_EXTERNAL_APIS\wow_swing_timer_api.md`, range
table). It answers "8–35 yd"; the deadzone (5–8) and too-far (>35) both read `false`, which is correct here — leaving
either into shooting range is the moment to cue. Melee ↔ deadzone transitions do not play (no shot possible either side).

### 14.2 Sound

**Decided 2026-11-24: the cue is derived from the equipped ranged weapon, never searched.** There is no API to
enumerate or search game sounds by name — `SOUNDKIT` is UI chrome only (quest log, backpack; verified against the
Classic Blizzard source) and weapon sounds are bare file IDs under `sound\item\weapons\` known only from community
lists. A "search sounds" box would search nothing. So: `GetInventoryItemID` slot 18 → `GetItemInfo` subclass →
**Bow / Crossbow → bow draw; Gun → gun cock**; Thrown → silent. Zero configuration; the player hears what they hold.

The file IDs are **TBD-A, chosen by ear, not from memory**: a **Preview** button per weapon class beside the checkbox
plays the current candidate; the owner confirms or we try the next. Candidates come from community file-ID lists
(HSS's in-game sample set "bow / hunter bow / hunter crossbow / gun" is the same files). Chosen IDs land in
`SpellData.RANGE_SOUND = { bow = id, gun = id }`. Casters' sounds (§14.8) are the same mechanism, per class.

### 14.2a The trigger spell — WeakAuras-style text box (decided 2026-11-24)

A text box + **OK**: accepts a **spell ID**, a **spell link** pasted from chat, or a **spell name**. Resolution, in
that order, via `C_Spell.GetSpellInfo` / `GetSpellInfo`. Honest limit, same as WeakAuras' own `CorrectSpellName` and
stated by its maintainer ("there's no API for that"): **a name resolves only if the spell is in your spellbook**
(`SpellIdentifier` doc). For "which spell defines *my* range" that is the right limit — you can only pick spells you
know. On success the box shows `Arcane Shot (3044)` with the icon; on failure it shows red "not in your spellbook /
unknown" and keeps the previous value. No 80k-ID brute-force cache (WeakAuras' fallback); not worth it here.

**Localized clients (owner 2026-11-24): the spell must ALWAYS be configurable by name.** If our per-class default ID is
wrong for a locale, the player types the spell name exactly as their client shows it and we produce the number. So
after the `GetSpellInfo(name)` lookups, `Resolve` scans the player's spellbook (Classic `GetSpellBookItemName` tabs,
Mainline `C_SpellBook` skill lines) for a case-insensitive name match. Still spellbook-bound: you can only pick spells you know.

Hunters are **prepopulated with `75` (Auto Shot)**. Per profile, per class: `profile.rangeCue.spellID`. The §14.8
caster defaults will prepopulate their class's nuke the same way.

**What this means for the spec'd Preview buttons:** they stay (sound by ear); the *spell* is the text box. Two
controls, two concerns.

Channel: `"SFX"` (follows the player's effects slider; `"Master"` as a fallback option later if asked). Throttle: at
most once per `RANGE_SOUND_MIN_GAP = 1.0 s`, so a mob jittering on the 35 yd line does not machine-gun the cue.

### 14.3 Settings

- Global `rangeEntrySound` — checkbox **"Play weapon sound when target comes into range"** in Visibility Timeouts,
  directly under "Show spell icon…". Default **on on Era, off on Forever** (`Client.flavour`); Forever tooltip:
  *"WoW Forever already plays this itself; turn on to use our sound instead."*
- `profile.rangeCue.spellID` — the §14.2a text box, prepopulated 75 for hunters, beneath the checkbox, indented.
- Hidden for non-hunters (the section already greys class-inapplicable controls via `availableFn`).
- Preview buttons (Bow / Gun) beside the checkbox; greyed when the checkbox is off.
- Global `rangeEntrySoundInCombat` — "...also while in combat", default off (see §14.5 revision).

### 14.4 Where it lives

```
Core\RangeCue.lua        (MODEL/controller: the poller, band state per target GUID, the edge rule, the throttle)
  RangeCue.Init()        starts the 0.2 s ticker only while a target exists (PLAYER_TARGET_CHANGED arms/disarms it)
  RangeCue.Band()        -> VWST_RangeBand (also exposed to /vwst status: "range: in (bow)")
  RangeCue.Preview(kind) -> plays the configured sound for "bow" | "gun"
Client                   += "IsAutoShotInRange() -> bool|nil", "RangedWeaponKind() -> 'bow'|'gun'|'thrown'|nil"
                            (IsSpellInRange / GetItemInfo behind the flavour wall; Forever: PlainNumber-guarded)
SpellData                += RANGE_SOUND_BOW, RANGE_SOUND_GUN (file IDs, after TBD-A)
```

No view, no bar change. The poller is independent of `ShotTracker`; it only reads `ShotTracker.IsChanneling()` and
`HasRangedWeapon()` for the suppressions.

### 14.5 Edge cases decided

**Revised 2026-11-25 (owner, after Era testing).** The misfire in practice was *targeting a yellow mob and walking past it*:
the 2-band `out → in` rule cued on every re-entry, including deadzone → bow range. Decisions:

- Two switches: `rangeEntrySound` (**out of combat**, nil = Era on / Forever off) and `rangeEntrySoundInCombat` (**in
  combat**, default **off**). Checkbox "...also while in combat" sits under the first.
- **Neutral (yellow, `UnitReaction` 4) target, out of combat → suppressed mode:** bands `far | near | in` using
  `Client.IsTargetNear()` (`CheckInteractDistance` duel ≈ 10 yd, reliable OOC) plus the melee probe
  (`SpellData.RANGE_MELEE_SPELL`, Raptor Strike 2973). Only `far → in` plays, **once per target GUID**.
- **Hostile (red) target, or any target in combat → no suppression:** bands `out | in`; every `out → in` plays (1 s throttle).
  Deadzone vs far is **unreadable in combat** (`CheckInteractDistance` is nil there, 10.1.5+ restriction incl. Era 1.15),
  and Tame / Scare Beast cannot probe it (nil on non-beasts); the only 8–35 yd hunter spell is Scatter Shot (talent). We
  do not pretend, which is why the in-combat switch defaults off.

| Case | Behaviour |
|---|---|
| Target swap to a mob already in range | silent (band history is per GUID; new GUID starts at `"none"`) |
| Red mob walks out then back in | plays again — subject to the 1 s throttle |
| Yellow mob, out of combat, walked past repeatedly | at most one cue (the first far → in) |
| Player moves into range (mob stationary) | plays — the edge is the same from the shot's point of view |
| In the deadzone, mob steps back to 8 yd | red / in combat: plays (indistinguishable from far); yellow OOC: silent |
| Target dies / cleared | band → `"none"`, ticker stops |
| Channeling (Tame Beast) | suppressed |
| No ranged weapon / wand | poller never starts |
| Forever `IsSpellInRange` returns nil (secret) | treat as `"none"`: never play on uncertainty |

### 14.6 Steps

- [x] 1. `Client.IsSpellInRangeOfTarget` / `IsTargetNear` / `RangedWeaponKind` (Era + Forever)
- [x] 2. `Core\RangeCue.lua`: poller armed by `PLAYER_TARGET_CHANGED`, per-GUID band, edge + throttle, `Preview`
- [x] 3. DB `rangeEntrySound` / `rangeEntrySoundInCombat`; checkboxes + spell box + Bow/Gun preview; `/vwst status` line
- [x] 4. TBD-A: file IDs from the listfile (567677 / 567719), confirmed by ear 2026-11-25
- [x] 5. Hunter test on Era 2026-11-25: yellow walk-by → one cue; deadzone crossing → silent (OOC); committed `4b0955e`.
        Remaining to observe: Forever hunter (doubling with the native cue), wand character.

### 14.7 Open questions

- **TBD-A** the file IDs: RESOLVED 2026-11-24 from the wowdev community listfile — `bow = 567677` BowPullback.ogg,
  `gun = 567719` GunLoad01.ogg (the first guesses 567513/567575 were LFG_RoleCheck and PutDownRocks_Ore01). Alternative
  takes are listed in `SpellData.lua` next to the table; the Preview buttons remain the way to choose between them.
  Era `IsSpellInRange(spellID)` returning nil falls back to the spell NAME form inside the client (name is authoritative).
- Should the cue also fire on the **first** target acquisition if the mob is already in range? Owner's modern-Forever
  memory may include that; UPDOG stays silent on swap. Default: silent; flip if it feels wrong.
- A second, quieter cue for **entering melee** (Raptor Strike weave) is cheap once the poller exists — out of scope now.
- **Forever doubling:** does Forever's built-in cue fire on the same edge we detect? If yes, on Forever we either stay
  silent for hunters (the game has it) or let the owner choose which. Needs one Forever hunter test; not blocking Era.

### 14.8 Casters — the follow-on (owner's direction, not in this slice)

The hunter case is the easy one: one spell, one band. A caster has several ranges (30 yd nuke, 20 yd Frost Nova-ish
utilities, 40 yd with talents), and "in range" of *which* is the question. Decisions deferred, but the shape is:

- `VWST_RangeCueSpell` becomes **per class, per profile**: a default primary nuke (Mage Frostbolt 116, Warlock Shadow
  Bolt 686, Priest Smite 585 / Mind Blast, Druid Wrath 5176, Shaman Lightning Bolt 403) with a dropdown to change it.
  `IsSpellInRange` honours talents (Arcane Reach etc.) automatically because it asks the game, not a table.
- One cue per profile by default. A **second** cue (different sound) for a shorter-range spell is the "multiple ranges"
  answer if it earns its keep — two distinct sounds for two bands, never more.
- Sound per class: casters have no weapon draw; candidates are the class's own cast-start sound or a neutral chime.
  Owner picks by ear with the same Preview buttons.
- The poller, band state, edge rule and throttle are **identical**; only the spell ID and the sound differ. That is why
  §14.4 keys `RangeCue` on a spell ID from the start.

- [ ] decide default spell per class (table above is a proposal)
- [ ] decide caster sound(s)
- [ ] build on top of the hunter slice

---

## 13. MVC restructure of the bar groups (owner 2026-11-24) — do BEFORE M3

### 13.1 Why

`UI\ShotGroup.lua` grew one `Bar` + one shared `VWST_ShotBarParts` bundle that BOTH styles time-share, with `RenderBar`
switching on `s.style` every frame and each branch hiding the other's leftovers. That is discipline standing in for
structure, and it failed (2026-11-24: one-bar showed mirrored's centre-out green after a style switch). The same
pattern is latent in `MeleeGroup` (MH/OH on one frame) and would triple with M3's target/focus groups. The preview cards
in `Options.lua` already do it right by accident — one bar per card — and never bled.

Owner's framing: **the simulator holds raw data; each view has its own view logic driving its own panel.**

### 13.2 Layers

```
Core\  (MODEL - no frames, no colours, no pixels)
  SwingTracker        VWST_SwingSnapshot(now)  per hand: { remaining, speed, progress }            (exists; keep)
  ShotTracker         VWST_ShotSnapshot(now)   { phase, charge, channelState, blockFrac, drawBlockFrac,
                                                 castFrac, flashFrac, remaining, cycle, window, moving, gcdBlind }
                                                 (exists; stays the ONLY source of truth about the shot cycle)
  Activity            per group visibility      (exists; keep)

UI\Views\  (VIEW - one file per presentation; owns its frame tree; pure function of (snapshot, settings) -> pixels)
  ShotView_OneBar.lua      VWST_ShotView interface, YaHT one-bar + the SPEC 12 GCD region
  ShotView_Mirrored.lua    VWST_ShotView interface, upstream mirrored + the SPEC 12.8 brick
  MeleeView_Hands.lua      VWST_MeleeView, MH (+OH) bars                   (M3 reuses it for target / focus, one hand)

UI\  (CONTROLLER - picks the view, owns placement / backdrop / activity / Edit Mode registration)
  ShotGroup.lua       creates ALL ShotViews once, parents them to the group frame, Show()s the selected one, Hide()s
                      the rest; per frame: snap = ShotTracker.Snapshot(now); activeView:Render(snap, s)
  MeleeGroup.lua      same shape; M3 instantiates it three times (player / target / focus)
  Options.lua         preview cards instantiate the SAME view classes with a scripted snapshot (no more RenderBar
                      shims, no more copy of the parts bundle)
  EditMode.lua        unchanged (registers group frames)
```

### 13.3 The view interface

```lua
-- VWST_ShotView  (one instance per style per host; created by ShotView_<Style>.New(parentFrame))
view.frame                      -- the view's own Frame, sized by Layout; the controller anchors THIS, nothing inside it
view:Layout(s, width, height)   -- (re)skin from VWST_ShotGroupSettings: texture, colours, font, rails/brick geometry.
                                --  Called on settings change / profile switch / Edit Mode enter-exit. May create textures
                                --  lazily on first call. MUST be idempotent.
view:Render(snap, s)            -- per frame. Pure: draws exactly what VWST_ShotSnapshot says. No tracker access.
view:RenderIdle()               -- no cycle in flight (snap == nil)
view:SetLabel(text)             -- "Auto Shot" / "Shoot"
view:Show() / view:Hide()
```

`VWST_MeleeView` is the same shape with `Render(handSnaps, s)` where `handSnaps = { mainhand = {remaining, speed,
progress} | nil, offhand = ... | nil }`.

**Rule:** a view never reads `DB`, `ShotTracker`, `NS.editModeActive`, or `GetTime()`. Everything it needs arrives in
`(snap, s)`. That is what makes the Options preview trivially correct: it hands the view a scripted snapshot and the
same settings table, and gets the same pixels as the live bar.

### 13.4 What moves where (no behaviour change)

| Today | Becomes |
|---|---|
| `ShotGroup.StyleBar(parts, s, w, h)` | `ShotView_OneBar:Layout` / `ShotView_Mirrored:Layout` (each only its own geometry) |
| `ShotGroup.RenderBar(parts, s, w, snap)` one-bar branch | `ShotView_OneBar:Render(snap, s)` |
| `ShotGroup.RenderBar` mirrored branch + brick | `ShotView_Mirrored:Render(snap, s)` |
| `ShotGroup.NewParts` | gone — each view creates its own textures in `New`/`Layout` |
| `Bar.lua` `centerGap` / `fillR` / `fill2` / `SetSplitColor` | **stay in `Bar`** — they are bar primitives both views use; `Bar` is a widget, not a view |
| Edit Mode sample snapshot in `ShotGroup.OnUpdate` | `ShotTracker.SampleSnapshot()` (model supplies the sample; controller passes it to the view) |
| `Options.lua` `ShotStyle`/`ShotRender`/`MeleeStyle`/`MeleeRender` shims + per-card parts bundle | preview card does `view = ShotView_<style>.New(card)`; `Update` → `view:Layout(overlay, w, h)`; `OnUpdate` → `view:Render(scriptedSnap, overlay)` |
| `ShotGroup` style switch hides the other style's textures | controller `Show()`s the selected view, `Hide()`s the others — whole frame, nothing to forget |

### 13.5 Scripted snapshots live in the model

`ShotTracker.ScriptedSnapshot(t, cycle, window, stall)` — the preview's fake-cycle generator moves out of `Options.lua`
into the model next to `Snapshot`, so the preview sequence is defined once, in terms of model state names, and can be
unit-reasoned against the real one. `ShotTracker.SampleSnapshot()` for Edit Mode likewise.

### 13.6 Steps (each a committable, behaviour-neutral slice)

- [x] 1. `UI\Views\` folder; `ShotView_OneBar.lua` + `ShotView_Mirrored.lua` extracted verbatim from `RenderBar`/`StyleBar`
        (one-bar branch → one file, mirrored branch → the other). TOC load order: `Bar.lua`, `Views\*`, groups.
- [x] 2. `ShotGroup` becomes the controller: creates both views on `Create`, `Layout` shows/hides by `s.style`, `OnUpdate`
        calls `activeView:Render`. Delete `StyleBar`/`RenderBar`/`NewParts`. Live bar pixel-identical.
- [x] 3. `ShotTracker.ScriptedSnapshot` + `SampleSnapshot`; `Options.lua` preview cards host a view instance each; delete the
        shims. Previews pixel-identical.
- [x] 4. `MeleeView_Hands.lua` extracted from `MeleeGroup.Layout`/`DrawHand`; `MeleeGroup` becomes the controller; the melee
        preview cards host it.
- [ ] 5. Spec §3 file layout + §12.5 updated (done); `luac -p` (clean); publish; owner verifies both shot styles, style switching, melee,
        Edit Mode samples, previews; commit.

Also in this slice (owner 2026-11-24): the §12.9/§12.11 misprediction announcements are gated behind
`DB.Global().debugTimerPrediction` (default **off**), surfaced as **Extras → "Enable Timer Prediction Debug Messages"**;
the "Reset" section is renamed **"Extras"**. The diagnostics stay in the code.

Then M3 (§10) builds target/focus on `MeleeGroup` + `MeleeView_Hands` with one hand each.

### 13.7 Non-goals

No visual change. No settings change. No new features. `Bar.lua` keeps its primitives. If a step is found to need a
visual change to be clean, stop and ask.

---

## 12. Shot bar: "Show shot GCD" (owner 2026-11-24) — do BEFORE M3

Supersedes the earlier "channel" third-style draft of this section (2026-11-24, same day). **Not a new style.** A global
checkbox that layers the engine's Auto Shot retry block onto the EXISTING presentations (one-bar, mirrored), plus the
render rule that the charge fill never runs through the stand-still window unaided. Rendering contract and tracker
state (`ShotTracker.Snapshot`) already landed in commit `734b95e`; this section is what gets drawn on top.

### 12.1 Why

Both upstream presentations draw *one* fill meaning two things: "where am I in the charge" and "when will the delayed
shot go off". When the player moves inside the stand-still window the engine re-schedules the shot and the fill
**retreated** (observed 2026-11-24). Fixed in `734b95e`: `FAILED_QUIET 75` never moves `shotEnd`; the charge fill parks
at the window boundary and only proceeds while the cast actually runs. What is still missing is *why* it is parked:
1. you are **moving** (you are the wall), or
2. you are still but the engine's **~0.5 s retry block** ("GCD") has not elapsed yet.

### 12.2 The visual (one-bar shown; mirrored is the same around its centre line)

```
charging                        ready, MOVING                    ready, STILL, block draining     ready, STILL, clear → casting
┌────────────────┬──────┐        ┌────────────────┬──────┐        ┌────────────────┬──────┐        ┌────────────────┬──────┐
│████████        │      │        │████████████████│▓▓▓▓▓▓│        │████████████████│      │        │████████████████│▒▒▒   │
│████████        │      │        │████████████████│▓▓▓▓▓▓│        │████████████████│▓▓▓▓▓▓│        │████████████████│▒▒▒   │
│████████        │      │        │████████████████│▓▓▓▓▓▓│        │████████████████│▓▓▓▓▓▓│        │████████████████│▒▒▒   │
└────────────────┴──────┘        └────────────────┴──────┘        └────────────────┴──────┘        └────────────────┴──────┘
 red LINE at the boundary          region SOLID red                 red box anchored at the BOTTOM,    region empty; castFillColor
 region empty                      ("you are the wall")             height = blockFrac (wall lowering)  (green) fills L→R over `window`
```

| Element | Drawn as | Meaning |
|---|---|---|
| **Boundary line** | 1–2 px vertical line in `castWindowColor` at the start of the window region; always visible when `window > 0` | "the charge parks here" |
| **Charge fill** | `cooldownColor` (white), left → right over `speed − window`; parks at the boundary | pulling the string; move freely |
| **Region, moving** | whole window region solid `castWindowColor` | the player is the wall; nothing counts down |
| **Region, still + blocked** | `castWindowColor` box **anchored at the bottom**, height = `blockFrac · regionHeight`; lowers over the 0.5 s retry block; a new `FAILED_QUIET` raises it to full | the engine's retry clock |
| **Region, still + clear** | empty; the fill continues through it in **`castFillColor`** (default green) over `window` | the cast is running; hold still |
| Numeric | charging: time to shot. blocked: `blockFrac·0.5 + window` (restarts upward on each failed retry). casting: remaining cast | time until the shot can fire from NOW (landed in `734b95e`) |

Wands (`window = 0`): no boundary, no region; plain fill. Checkbox **off**: the region is the static red block one-bar
already has (mirrored: the red-growing-from-centre cast phase), fill parks at the boundary until casting — i.e. exactly
`734b95e` behaviour. Mirrored with the checkbox on: the boundary is the existing centre line; "region" = the fill area
beyond `charge == 1`; moving = region solid red grown to full; still+blocked = red height lowering; clear = `castFillColor`
grows from the centre.

### 12.3 Shot event

**TBD-B (owner):** keep the 0.25 s whole-bar flash in `shotFlashColor` on `SUCCEEDED 75` / `PLAYER_SWING ranged`, or
drop it now that the cast phase is already a distinct colour? `flashUntil` / `flashFrac` are already in the snapshot;
dropping it is deleting one swatch. Recommended: **keep**, default `shotFlashColor = {1, 1, 1, 0.8}` — the event registers
even when the eye is elsewhere.

### 12.4 State (already landed, `Core\ShotTracker.lua` `Snapshot(now)`)

```
VWST_ShotPhase        = "charging" | "ready"
VWST_ShotChannelState = "idle" | "blocked_moving" | "blocked_still" | "casting"
blockedUntil  = FAILED_QUIET 75 → now + AUTO_SHOT_RECAST_DELAY (0.5).  Never touches shotEnd.
moving        = GetUnitSpeed("player") > 0   (Era readable; Forever PlainNumber → nil → still)
blockFrac     = (blockedUntil − now) / 0.5 clamped; moving with no event yet → 1 (engine WILL refuse at next tick)
castStartAt   = first tick in "casting"; cleared on any other state and on anchor
castFrac      = (now − castStartAt) / window
```

`VWST_ShotSnapshot = { phase, charge, channelState, blockFrac, castFrac, flashFrac, remaining, cycle, window }`.

### 12.5 Drawing (`UI\ShotGroup.lua`)

- `VWST_ShotBarParts += { boundary = Texture, regionBlock = Texture }`; `windowBlock` stays as the checkbox-off static
  block (one-bar) and is hidden when the checkbox is on. `centerLine` doubles as the mirrored boundary.
- `StyleBar`: size `boundary` (`boundaryWidth` px, full bar height) and `regionBlock` (anchored `BOTTOMLEFT`/`BOTTOMRIGHT`
  of the region, width = region width) from `window / speed`.
- `RenderBar`, checkbox on, by `channelState`:
  - `idle`: boundary shown, regionBlock hidden, fill = `charge · chargeFrac` in `cooldownColor`
  - `blocked_moving`: regionBlock height = full
  - `blocked_still`: regionBlock height = `blockFrac · regionHeight`
  - `casting`: regionBlock hidden; fill = `chargeFrac + castFrac · windowFrac`, the part past the boundary in `castFillColor`
    (implementation: a second status-bar texture / `Bar:SetSplitColor(atFrac, colorA, colorB)` so one fill shows two colours)
  - `flashFrac > 0`: whole bar lerps toward `shotFlashColor` (TBD-B)

### 12.6 Settings and options

- `DB.DEFAULT_GLOBAL.showShotGCD = true` — **TBD-A (owner)**: default on? Recommended **on**.
- `DB.DEFAULT_SHOT.castFillColor = { r = 0.2, g = 0.85, b = 0.2, a = 1 }` — **TBD-A**: name/default OK?
- `DB.DEFAULT_SHOT.shotFlashColor` per TBD-B; `boundaryWidth` constant 2 (not a setting).
- Options → Visibility Timeouts section gains the checkbox **"Show shot GCD"** (global; it is a visibility concern, not
  a per-bar one) with tip *"While Auto Shot is ready: the window turns solid red while you move, shows the game's
  half-second retry timer as a lowering red box while you stand still, and fills green while the shot is casting."*
- Shot swatch row: Text · Border · Charge · Window · **Casting** (`castFillColor`) · Shot (`shotFlashColor`, TBD-B).
- The two preview cards already play charge → blocked-moving → blocked-still → casting → flash; they pick up the new
  drawing for free. No third card.

### 12.7 Steps

- [x] 1. DB: `showShotGCD`, `castFillColor`, `shotFlashColor` (commit 7dc5a7e)
- [x] 2. `Bar`: two-colour fill (`SetSplitColor`) for one-bar; `centerGap` + `fillR` for the mirrored brick
- [x] 3. `ShotGroup`: boundary + regionBlock textures; `RenderBar` per §12.5; checkbox-off path unchanged
- [x] 4. Options: checkbox in Visibility Timeouts; Casting + Shot swatches
- [x] 5. Hunter test one-bar: confirmed by owner 2026-11-24 ("AWESOME")
- [ ] 6. Hunter test mirrored brick (§12.8); then commit

### 12.8 Mirrored: the GCD brick (owner 2026-11-24, after one-bar shipped)

Mirrored had no spatial window region, so the centre line becomes a **brick**: a centred region `windowFrac · width`
wide (same proportion as one-bar's red region) bounded by two 2 px `castWindowColor` lines. The white charge shrinks from
both ends and **parks at the brick's edges** (`Bar.centerGap` splits the centre fill into two slabs). Everything GCD
lives inside the brick: **solid red ANY time the player is moving, in every phase** (owner: "the brick is the do-not-move
region"); bottom-anchored red box with height `blockFrac` while still+blocked; green (`castFillColor`) grows out of the
brick's centre to its edges while casting; **only the brick flashes** on the shot. Checkbox off → upstream mirrored.
`snap.moving` is exposed in every phase for this. One-bar's region still reacts only once ready (unchanged).

### 12.9 The brick IS the GCD clock — "blind" vs "cycling" (owner 2026-11-24, NOT YET BUILT)

Correction to §12.2 / §12.8 after in-game review. The brick's appearance is keyed on **one axis only: do we currently
hold a reference to the engine's Auto Shot retry phase?** Movement is **not** that axis and must never freeze the brick.

| GCD reference held? | Brick draws | Why |
|---|---|---|
| **No** — blind | **stuck full `castWindowColor`** | we cannot show a timer we do not have; a wall is the honest default |
| **Yes** | **continuously cycling**: height = remaining fraction of the current 0.5 s retry block, snapping back to full at each tick — whether the player is moving or still, charging or ready | the engine's retry metronome is free-running and this is what it looks like |

What was wrong in `dedddf2`: "solid red whenever moving" tied full-red to *movement*; and the synthetic `blockFrac = 1`
when no event had arrived tied full-red to *this stall* rather than to *blindness*. Both conflated the two axes.

**Acquiring the reference:** the first `UNIT_SPELLCAST_FAILED_QUIET 75` seen. It fires at a failed retry tick, so it
gives the metronome's phase exactly: `VWST_RetryPhase = (eventTime) mod AUTO_SHOT_RECAST_DELAY`. Every later
`FAILED_QUIET` re-syncs it (drift correction, free).

**Predicting ticks from the reference:** next tick after `now` = smallest `t > now` with `t ≡ VWST_RetryPhase (mod 0.5)`.
`blockFrac = (nextTick − now) / 0.5`. This is what the brick height draws, every frame, in every phase.

**Losing the reference (TBD-A, owner to decide / test):** which of these re-seed the engine's metronome, i.e. make our
phase stale and drop us back to blind?
- `START_/STOP_AUTOREPEAT_SPELL` (autorepeat toggle, e.g. the `!Auto Shot` macro, target swap) — **almost certainly yes**
- `PLAYER_EQUIPMENT_CHANGED` ranged slot, `PLAYER_ENTERING_WORLD` — **yes**
- a **landed shot** (`SUCCEEDED 75` / `PLAYER_SWING ranged`) — **UNKNOWN**. If the metronome free-runs across shots we keep
  the phase and the brick cycles from the first frame of the next window. If a shot re-seeds the first retry at `readyAt`
  we must drop the reference on anchor and the brick is full until that shot's first `FAILED_QUIET`.
  **Test:** retain the phase across a shot; on the next stall, log `predictedTick − actualFAILED_QUIET`. ~0 → free-running
  (keep). Consistently off → re-seeded (drop on anchor, OR seed `VWST_RetryPhase = readyAt mod 0.5` on anchor if the
  offset is exactly `readyAt`-aligned).

**Movement on a cycling brick — DECIDED (owner 2026-11-24):** the brick itself is purely the clock (height =
`blockFrac`, bottom-anchored). Movement is shown on the brick's **vertical edge lines**: **red while moving, white while
still**. (One-bar: its single boundary line, same rule.)

**TBD-A — DECIDED: instrument it, don't guess.** `ShotTracker` keeps `VWST_RetryPhase` across a landed shot (does NOT
drop it on anchor) and records, on every `FAILED_QUIET 75`, the offset between the tick we *predicted* from the carried
phase and the tick that *actually* fired: `gcdDrift = actual − predicted` (normalised into ±0.25). `/vwst status` prints
the last 8 drifts and their mean; `/vwst trace` prints each one as `GCD drift +0.012` inline. Reading the result:
- drifts ≈ 0 across shots → the metronome free-runs; keep the phase across shots (current behaviour, nothing to change)
- drifts jump to a consistent non-zero value right after each shot and then ≈ 0 within that shot → a landed shot
  re-seeds the metronome; change `Anchor` to drop the phase (or seed it from `readyAt` if the first-drift value equals
  `readyAt mod 0.5`). The diagnostic output tells us which.
The reference IS dropped on `START_/STOP_AUTOREPEAT_SPELL`, ranged-slot `PLAYER_EQUIPMENT_CHANGED`, `PLAYER_ENTERING_WORLD`,
`PLAYER_DEAD` — those re-seed for certain.

**Interaction with charge:** the brick cycles even while the white is still charging (if we hold a reference). The white
parks at the brick edges at `charge == 1`; the green starts at the first tick after that where the player is still.

**Numeric while ready** stays as landed in `734b95e`: `blockFrac·0.5 + window` while blocked, cast remaining while casting.

**Implementation:** `ShotTracker.state.retryPhase` (seconds mod 0.5) replaces `blockedUntil`; `state.gcdDrift[]` ring of 8;
`ShotTracker.HasGCDReference()`; `Snapshot` emits `blockFrac` from the phase in every phase and `gcdBlind = true` when no
reference; `RenderBar` draws the full brick when `gcdBlind`, else bottom-anchored height = `blockFrac`; edge lines
`castWindowColor` when `snap.moving`, `cooldownColor` when still. One-bar region + boundary identical. Previews: the
scripted sequence starts blind for the first 0.5 s of the stall so the full-red state is demonstrated.

- [x] TBD-A decided: instrument, keep phase across shots, read the drift
- [x] TBD-B decided: edge lines red moving / white still
- [x] build (tracker phase + drift ring; render; status/trace output) — commits `6f20a22`
- [x] hunter test + drift read, 2026-11-24 — see §12.10 / §12.11

### 12.10 The brick drains ONCE — latch, don't cycle (owner 2026-11-24, built, `6f20a22`)

Visually the continuous cycling was "information, but not worth it". Replaced by one latch: `stopWaitTick` = the retry
tick we predict from the carried phase, set the moment the player stops. **Moving → brick full. Stop → brick drains
once to `stopWaitTick` and stays at the bottom. Past the tick → `casting`, brick hidden, green grows; stays casting
until a `FAILED_QUIET` (re-latch one period from it; brick refills + drains once more) or the shot lands.** The free-
running phase is never consulted after the latch (the first build consulted it and re-blocked on every 0.5 s wrap, so
green never appeared). Edge lines: red moving / white still.

### 12.11 TBD-A measured: a landed shot DOES re-seed the retry clock

Two in-game logs (2026-11-24). Within one shot, consecutive `FAILED_QUIET` phases agree to ±0.04 s (free-running
~0.5 s). Across an `ANCHOR shot` the next failure is **0.11–0.14 s off** every time (+0.114, +0.114, −0.135). The
re-seed target is not yet derivable: the first failure after a shot arrived at `readyAt − 0.21 s` once and is not a
clean multiple of 0.5 from the shot either. Decision: **drop the reference on anchor** (brick full until that shot's
first `FAILED_QUIET`, ≤ 0.5 s) and keep logging `firstFailureAfterShot − readyAt` so the re-seed rule can be learned.

Also found: (a) `FAILED_QUIET 75` arrives **twice** per failure on Era (same timestamp) — de-dupe within 5 ms; (b) the
"tick missed" announcement false-fires when `moving` flips for a frame after the latch clears — require `moving` for the
whole predicted interval.

- [ ] drop reference on anchor; de-dupe; fix missed-tick false alarm; log first-failure-after-shot offset

### 12.12 Measured 2026-11-24 (second session, debug on) — what the retry clock actually is

Two `FIRST FAILURE this shot` lines: `0.252` and `0.264 periods after shot`, i.e. **the first retry after a landed shot
is at `shot + ~0.13 s`**, repeatable, independent of `readyAt`. Consecutive retries were `0.369 s` apart in one case, so
the interval jitters **0.37–0.6 s**, not a clean 0.5. Consequences, all landed in the working tree:

1. `GCD_DRIFT_TOLERANCE` 0.08 → **0.2**: under that is the engine's own jitter, not our model. Mispredict lines seen
   today were engine noise.
2. **`!Auto Shot` re-assert**: the macro delivers `STOP` then `START` at the same timestamp while already shooting;
   each pair dropped the reference twice, leaving the tracker blind nearly the whole fight. A START within 50 ms of a
   STOP (`AUTOREPEAT_REASSERT_WINDOW`) is now a re-assert: `isShooting` back on, reference KEPT, logged as
   `AUTOREPEAT re-assert`. A lone STOP no longer drops; only a genuine START does.
3. Instant-green blip (mirrored, stop exactly at charge-complete): blind latch was `max(readyAt, now)` → `now` → one
   frame of casting. Now `max(readyAt, now, lastMovedAt + period)`.
4. `OnAutoRepeat(true)` sets `lastShotTime` so the bar shows on an opener (upstream parity). Trace confirmed an Arcane
   Shot opener fires `OnAutoRepeat(true)`, the `3044`, then a real `75` immediately — the auto is not lost.

**Next, pending more `FIRST FAILURE` samples:** if `~0.25 periods after shot` holds, seed `retryPhase` from the shot on
anchor instead of going blind, and the brick never needs a full-red moment after a landed shot.

- [x] items 1–4 above (uncommitted; owner testing)
- [x] first-retry offset measured over more shots: `0.25, 0.26, 0.82, 3.27, 2.50` periods — **no fixed offset**. Seed-from-shot is DEAD.

### 12.13 DECIDED 2026-11-24: there is no cast-prediction. The brick shows only what we know.

Third session of dumps settled it. Observed retry intervals: 0.37, 0.50, 0.50, 0.52, 0.58, 0.88, 1.19 s. First retry
after a shot: anywhere from 0.25 to 3.27 periods. `FAILED_QUIET` with `moving false` (the engine refuses a stationary
player — range, facing, GCD from an instant, server-side position lag). Conclusion: **we have no positive signal that an
Auto Shot cast has begun.** Every pre-shot green we drew was a guess and the dumps showed it wrong often (0.08 s, 0.38 s
of false "casting" before a refusal).

The owner's call: "the solid red brick while moving is already a visual-cue revolution; let's try it." The live
ready-phase model is now only the three things we KNOW:

| Signal | Brick |
|---|---|
| moving (`GetUnitSpeed > 0`) | **solid red** — you are the wall |
| `FAILED_QUIET 75` (a refusal) | fills, then **drains once over one typical period (0.5 s)** — "the engine will try again soon" — then empty |
| otherwise (ready, still, no recent refusal) | **empty**. Nothing claimed about a cast. |
| `SUCCEEDED 75` / `PLAYER_SWING ranged` | **flash** — the only moment we know it fired |

There is **no `casting` state in the live snapshot**. `stopWaitTick`, `CAST_CONFIRM_GRACE`, the latch logic, and the
"cast mispredicted" announcement are gone. The retry-phase reference (`retryPhase`, drift ring) stays as a *diagnostic
only* — the debug line is now `GCD retry irregular` (how irregular the engine is), not a claim that *we* were wrong.

The green `castFillColor` and the `casting` channel state remain in the **views** and in `ScriptedSnapshot` so the
options preview still demonstrates the full colour vocabulary; the live bar simply never emits that state. If a
positive cast signal is ever found (e.g. a Forever-only event), `Snapshot` can emit `casting` again and the views
already draw it. Edge lines (red moving / white still) unchanged. Numeric while ready: `drain · 0.5 + window`.

- [x] built; `luac -p` clean
- [ ] owner test: brick is solid red while moving; a refusal shows one drain; stationary and clean = empty brick; flash on shot; no red debug lines unless the engine is irregular

### 12.14 Action blocks — "this is what THAT press cost you" (owner 2026-11-24, NOT YET BUILT)

Replaces the idea of static clip ticks (rejected: "we are not putting ticks all over the damn thing"). Feedback is
drawn **per action, at the moment of the action, on the bar's own timeline**, so the consequence is obvious for that
spell and the idle bar stays clean.

#### 12.14.1 Mechanics (facts, all readable at press time — no prediction)

| Action | Blocks Auto Shot for | Start signal | Length source |
|---|---|---|---|
| GCD instant: Arcane Shot 3044.., Serpent Sting 1978.., Hunter's Mark 1130.., Concussive 5116.., Scatter 19503, Distracting 20736.., Scare Beast, Tranq 19801, Viper Sting, Wing Clip (ranged-stance instants) | the **1.5 s GCD** it starts — Auto Shot's cast cannot *begin* while the GCD runs | `UNIT_SPELLCAST_SUCCEEDED` (player, spellID) | `ShotTracker.GCDRemaining()` sampled on the event (Attack 6603/6803 cooldown = the GCD; readable on Era; Forever: `PlainNumber`, fall back to 1.5) |
| Real cast: Multi-Shot 2643.. (0.5 s), Aimed Shot 19434.. (3 s) | its **cast duration** — no Auto Shot while casting | `UNIT_SPELLCAST_START` (player) | `UnitCastingInfo("player")` endTime; Era fallback `SpellData` table. `FAILED` / `INTERRUPTED` → block cut at that instant |
| Multi-Shot in Classic/Era/TBC is a 0.5 s cast (instant only from Wrath 3.0). Aimed Shot is a 3 s cast. Both confirmed in upstream's spell table. | | | |

Melee has **no** equivalent (no cast on a white swing; melee swings are not GCD-gated). This is shot-bar only.

#### 12.14.2 The drawing

The bar is a timeline: `x = 0` ↔ `shotStart`, `x = boundary` ↔ `readyAt`, `x = W` ↔ `shotEnd`. Time-to-x is linear
at `W / cycle`. **One red block per action**, placed at `x(now)` and extending `x(duration)`:

```
                boundary                                  boundary
┌───────────────┬──────┐             ┌───────────────┬──────┐
│████████░░░    │▓▓▓▓▓▓│  harmless   │███████████████│▓▓▓▓▓▓│▓▓▓▓▓▓▓▓▓▓▓   "what the hell are you doing"
└───────────────┴──────┘             └───────────────┴──────┘            (Aimed Shot at 85 % charge)
  block ends in the white              block runs past the right edge: drawn UNCLIPPED, outside the bar
```

- Block colour: `actionBlockColor` (new, default the window red; swatch "Action").
- Block carries a small label (the spell name or icon) so it reads "for THAT spell". `showText` alpha governs it.
- **Overlap with the GCD region** = the cost: the auto's cast moves to `blockEnd`. Nothing extra is drawn; the
  overlap IS the message.
- **Overrun past `W`**: the block is drawn outside the bar, to its full length, no clipping. Z-order above the backdrop.
- **The white fill continues along the same timeline until it reaches the END of the block**, wherever that is.
  When it gets there the block **flashes** (`shotFlashColor`, 0.25 s) and is **removed**; the bar returns to the
  normal shot/brick model. Rationale: the engine's auto fires at `max(shotEnd, blockEnd)`; "white reaches block end"
  is exactly the moment the auto is allowed again.
- Multiple blocks (instant then Aimed): each is its own span; they may overlap; each flashes/clears on its own end.
- `SUCCEEDED 75` (the auto actually fired) clears every live block — the cycle reset is the ground truth.

**DECIDED (owner 2026-11-24) — fill during an overrun: (a) brutal honesty.** The white fill is drawn **past the bar's
right edge too**, chasing the red outside the frame until it catches it. Same timeline, same `W / cycle` scale, no
clipping. The `Bar` fill texture therefore must be allowed to exceed `W` (one-bar: `SetValue` cannot; the view draws
the overrun portion with its own texture continuing from the bar's right edge. Mirrored: the slabs already meet at the
brick; the overrun continues *out of the brick's centre* — see 12.14.4).

**DECIDED — brick while a block is live:** the refusal **drain is suppressed** (the block *is* the reason for the
refusal; both at once double-counts). **Moving = solid red** still applies (a separate, concurrent cause).

**DECIDED — label:** a **compact spell icon at the START of the block**, square, sized to the **best fit of the block's
own height AND width**: `iconSize = min(barHeight, blockWidthPx, ACTION_ICON_MAX)` with `ACTION_ICON_MAX = 16` so a
tall bar does not get a huge icon and a short GCD block on a fast bow does not get an icon wider than itself. Below
`ACTION_ICON_MIN = 8` the icon is omitted (block too short to label). Texture from `C_Spell.GetSpellTexture(id)` /
Era `GetSpellTexture`, `SetTexCoord(0.08, 0.92, 0.08, 0.92)` to trim the stock border. No text. Vertically centred in
the bar; follows `actionBlockColor.a`, not `showText`.

#### 12.14.3 Model (`Core\ShotTracker.lua`)

```lua
-- VWST_ActionBlock = { kind = "gcd" | "cast", spellID, label, startAt, endAt }     (GetTime() seconds)
state.actionBlocks = {}                      -- live blocks, cleared on anchor("shot")
sink:OnSpellSucceeded(id)  -> if SpellData.SHOT_BLOCKING_INSTANTS[id] then push { kind="gcd", startAt=now, endAt=now+GCDRemaining()|1.5 }
sink:OnSpellCastStart(id)  -> if SpellData.SHOT_BLOCKING_CASTS[id]   then push { kind="cast", startAt=now, endAt=UnitCastingInfo end }
sink:OnSpellCastStop(id, reason) -> reason failed/interrupted: cut the matching cast block at now (endAt = now)
Snapshot(now).actionBlocks = { { xStartFrac, xEndFrac, label, flashFrac } ... }   -- fractions of the bar width, may exceed 1
Snapshot(now).fillFrac     = charge mapped to the SAME timeline; may exceed 1 while chasing an overrun (TBD-A a)
-- block lifecycle: live while now < endAt; then flashUntil = endAt + SHOT_FLASH_SECONDS; removed after
```

`SpellData.SHOT_BLOCKING_INSTANTS` / `SHOT_BLOCKING_CASTS` = the ID sets above (all ranks). Classic IDs; Forever reuses.

#### 12.14.4 Views

Both `ShotView_OneBar` and `ShotView_Mirrored` gain `actionBlocks` rendering: a pool of `{ tex, label }` pairs on the
bar frame, `SetClipsChildren(false)` on the bar frame so overruns draw outside. One-bar: block from `xStart·W` to
`xEnd·W` on the single axis. Mirrored: the timeline is folded — the charge runs from both ends toward the brick, so a
block at time-fraction `f` is drawn **on both slabs mirrored** (two textures per block), and an overrun past
`readyAt` grows **out of the brick's centre** past the brick edges (mirrored's "right edge" is the centre). The flash
uses the block's own rect.

#### 12.14.5 Settings / options

- `DB.DEFAULT_SHOT.actionBlockColor = { r = 0.8, g = 0.0, b = 0.0, a = 0.85 }`; swatch **Action** in the shot row.
- Global `showShotActions = true` next to "Show shot GCD" in Visibility Timeouts: *"Draw the GCD / cast of each shot
  ability on the bar from the moment you use it, so you can see when it pushes your Auto Shot."*
- Global `showShotActionIcon = true` (owner 2026-11-24), checkbox **"Show spell icon on blocking cast inset"** directly
  under the one above, indented; greyed when `showShotActions` is off. Off → blocks draw without the icon.
- `ScriptedSnapshot` gains one instant pressed late (overlapping the window) so the preview demonstrates it.

#### 12.14.6 Steps

- [ ] 1. `SpellData` ID sets; `ShotTracker` action-block state + sink hooks + `Snapshot.actionBlocks` / `fillFrac`
- [ ] 2. `ShotView_OneBar` blocks + overrun + flash + label
- [ ] 3. `ShotView_Mirrored` folded blocks + centre overrun
- [ ] 4. DB default, swatch, global checkbox, scripted preview
- [ ] 5. Hunter test: Arcane Shot early → block in the white, no cost; Arcane Shot inside the window → block eats the red,
        white chases it; Aimed Shot at 85 % → block way outside the bar, white follows it out (TBD-A a), flash, reset;
        interrupted Aimed → block cut short; wand unaffected

#### 12.14.7 Open questions

- Does the GCD read 1.5 for all hunter instants on Era, or do some (Wing Clip? Feign Death?) have shorter/none? Measure
  with `GCDRemaining()` on the event before trusting the fallback; log it in the event ring.
- Overrun geometry edge case: a block that starts *before* `readyAt` and ends *after* `shotEnd` spans the boundary, the
  red region and the outside — one texture, three zones. Draw as one continuous rect; the region underneath shows through
  wherever the block is translucent (`actionBlockColor.a` default 0.85).

#### 12.14.8 CORRECTED 2026-11-24 after web research — the GCD does not block Auto Shot

Built, tested, and the owner's logic falsified the model: *"if the 1.5 s GCD blocked the auto, weaving would be
impossible on any bow faster than 1.5 s."* Research (`_EXTERNAL_APIS\wow_swing_timer_api.md`, "What actually delays
Auto Shot") confirms: the auto is on its own clock; only **real casts**, **instants pressed in the auto's last ~0.5 s**,
**movement**, and **`!Auto Shot` re-asserts** delay it — all by ~0.5 s via the engine's retry/cast. The 1.5 s read from
`GCDRemaining()` was real but irrelevant.

Owner's design principle, which the first build violated: **draw on the bar only what the cast UI cannot tell you.**
- **Aimed Shot** — you see its 3 s cast bar; what you cannot see is where it sits against the red. Block as built. The
  decision it supports is *when to cancel*: cancel before the block reaches the red → the auto still fires on time; keep
  casting into the red → auto delayed; cancel after that → lost both. "Proactive Aimed; move before the red."
- **Instants** — no cast bar at all, so the cost is invisible unless drawn. **Fixed 0.5 s block from every press**, not
  1.5, and always (the player reads "is my block in the red?" at press time). If it bleeds into the red it is delaying
  the auto; a later step may make it *push* the red by the overlap (pending the 12.15 data).
- **Multi-Shot** — 0.5 s cast bar already shows itself; the block coincides. Forever's Multi (cast or instant?) is
  unverified; both event paths produce the right 0.5 s block, so no special case is needed.
- Cast blocks also carry a **faint 0.5 s retry tail** (`tailEndAt`, drawn at 40 % alpha): the engine's retry timer runs
  during a cast, so the auto may wait up to one more period after the cast ends ("Retry Timer" item 2).
- `!Auto Shot` re-assert inside the red → its own 0.5 s block with the Auto Shot icon, so the macro's cost is visible.

Status: built (`SpellData.GCD_FALLBACK_SECONDS` now unused by the block path; kept for the GCD read), both views draw
the tail; `luac -p` clean; owner testing.

### 12.15 Measuring the instant-press cost (owner 2026-11-24, built)

The mechanism behind "an instant in the last 0.5 s delays the auto ~0.5 s" is unverified (cancel-and-restart vs retry
tick; two anecdotes, no source). Instead of guessing, measure: at every shot-blocking instant press record
`lead = expectedShotEnd − now`; when that shot lands record `delay = actual − expected` (clamped ≥ 0) into a bucket by
lead. **10 buckets × 0.25 s** (0–2.5 s before the shot) + an overflow bucket. Each bucket `{ n, sum, max }`.
Persisted in `NS.db.instantStats` across sessions.

**Clean-sample rule** — a cycle is dropped (reason counted, shown in the output) if: two instants in one cycle; a real
cast in the same cycle; moving at the press or at the shot; the shot landed *earlier* than expected (re-anchor); or
**the `!Auto Shot` macro re-asserted in the same frame as the press** (a re-assert starts its own retry timer, so the
cost is unattributable — owner must use a bare keybind for clean data). A lone `AUTOREPEAT stop` (target gone) discards
the pending sample and drops the retry reference after 100 ms so neither can produce garbage (fixed a false "missed
tick" seen 2026-11-24).

`/vwst instants` prints the histogram (lead bucket, n, avg delay, max) and the dropped-reason counts;
`/vwst instants reset` clears. With debug on, each closed sample prints one cyan line.

**What the data decides:** the lead at which avg delay jumps from ~0 to ~0.5 = the true no-cast width (0.47 window?
0.5? other?). The *shape* inside the window — ramp `0.5 − lead` (cancel-and-restart) vs flat ~0.5 with jitter (retry
tick) — decides whether an in-red instant block should *push* the red by the overlap or by a fixed 0.5.

- [x] built, `luac -p` clean
- [ ] owner: play a hunter session with a BARE Arcane Shot keybind; paste `/vwst instants`

#### 12.15.1 First dataset (2026-11-24, macro still on) and the sample-hygiene fixes it forced

20 samples, 18 dropped `moving at press`, 5 `two instants`. Readable through the noise: leads > 0.75 s sit at
0–0.3 s delay; `0.25–0.75` jump to ~0.8–1.0 s — a step near 0.5–0.75 s, consistent with the forum's "just over
0.5 s". Two artefacts exposed and fixed:
- **`0.00–0.25` bucket: avg 9.8 s, max 18.8 s** — the "next shot" was a different engagement. Fix: a shot landing more
  than **1.5 × cycle** after the expected one is dropped as `stale`; **leaving combat** drops any pending instant
  sample and wipes pending presses (`ShotTracker.OnLeaveCombat` ← `PLAYER_REGEN_ENABLED`).
- **Cost in the 2 s-lead buckets** (0.3–0.7 s, which no instant could cause) — the `!Auto Shot` macro's own retry
  timer smeared across every cycle. Fix: any re-assert anywhere in the cycle taints the sample (`macro re-assert in
  cycle`), not only one in the press frame. Consequence: **with the macro on, nearly every sample drops** — the
  truthful answer. Clean data needs a bare keybind.

### 12.16 The post-anchor heartbeat `FAILED_QUIET` (measured, built)

The engine fires one `FAILED_QUIET 75` **~0.13 s after every anchor and every autorepeat start**, stationary, with the
auto having just fired (0.25–0.28 periods in every clean cycle across five sessions; later ones only when moving). It is
the first-check heartbeat of the new cycle, not a refusal. Treating it as one acquired a bogus retry phase, drained the
brick after every shot, and produced every false `missed tick` / `retry irregular`. `FIRST_CHECK_HEARTBEAT_WINDOW = 0.3`:
a `FAILED_QUIET` inside it is logged `heartbeat - ignored` and dropped before anything downstream sees it.

### 12.17 Press tracking via `UNIT_SPELLCAST_SENT` (researched, built)

`SUCCEEDED` is resolution, not press. `UNIT_SPELLCAST_SENT` fires at the press ("player" only, earliest point in a
cast's life; Era 1.13.2+ and Forever) and its **castGUID threads to the outcome event** (`SUCCEEDED` / `FAILED` /
`FAILED_QUIET` / `INTERRUPTED`). Routed through `Client` as `sink.OnSpellSent(spellID, castGUID)`; the outcome sinks
now also receive the GUID. `/vwst presses` histogram per lead bucket: **ok** (+ avg press→resolve latency — a queued
instant shows up as long latency), **cancel moving**, **cancel still**, **lost** (no outcome in 2 s, announced by a
timer at the moment it is known, red `instant CANCELLED (silent)`). Persisted `NS.db.pressStats`. **Not macro-sensitive**
(SENT fires for the press regardless of the STOP/START churn), so it fills even on the macro bar.

What the two tables decide together: if in-red instants are *queued behind the auto* (owner's observation: press,
then move → the instant is cancelled), `ok` latency climbs toward ~0.5 s as lead → 0 and `cancel moving` clusters in
the last buckets, while `/vwst instants` shows little auto delay. If instead the instant fires first and *delays the
auto*, `ok` latency stays flat and `/vwst instants` carries the cost. The push rule for the in-red block follows.

### 12.18 Shot bar hidden while channeling (owner, built)

`UNIT_SPELLCAST_CHANNEL_START/_STOP` → `sink.OnChannel(isOn)` → `ShotTracker.IsChanneling()`; `ShotGroup`'s
`settingsFn` returns `enabled = false` while channeling (Edit Mode exempt), so Tame Beast / Volley / Eagle Eye fade
the bar out and back in via Activity rather than showing a cycling brick. Melee bar unaffected.

### 12.19 The `!Auto Shot` macro's own `FAILED_QUIET` (measured, built)

Every `/cast !Auto Shot` press while already shooting lands a `FAILED_QUIET 75` **in the same frame as its
`AUTOREPEAT stop`**, stationary — the macro's "already on" rejection ("Retry Timer" item 4), not the auto being
refused. It re-synced the retry phase from a non-event. A `FAILED_QUIET` within `AUTOREPEAT_REASSERT_WINDOW` of a stop
is now logged `macro 'already on' rejection - ignored`. The same dump showed the macro's real cost: stationary retries
at 0.50 s spacing with `readyAt −0.99 s` — **whole autos lost**, measured as `auto delayed 1.220s`. Advice to the owner:
drop `/cast !Auto Shot` from instant macros (any offensive ranged ability auto-starts Auto Shot anyway); keep a plain
`Auto Shot` key for re-engaging. There is no `[autorepeat]` macro conditional to gate it.

- [x] 12.16–12.19 built, `luac -p` clean; uncommitted with 12.13–12.15
- [ ] owner: next session → `/vwst instants` + `/vwst presses`; then commit the batch; then M3

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
