# Velocity Weapon Swing Timers

Swing and shot timers that **only appear while you are actually swinging or shooting**.

A priest spamming Smite does not need a melee bar and a wand bar sitting at "ready" for the whole fight. Each bar
shows up on your first swing or shot, stays while you keep attacking, and fades a few seconds after you stop
(configurable). Out of combat the bars are invisible by default.

- **Melee bars** - main hand and off hand, with parry haste and on-next-swing abilities (Heroic Strike, Cleave,
  Maul, Raptor Strike) handled.
- **Shot bar** - Hunter Auto Shot (with the stand-still window) and caster wand Shoot.
- **Hunter cast bar** - Aimed Shot / Multi-Shot under the shot bar.
- **Edit Mode** placement; settings follow your Edit Mode layout, so each layout is a profile.
- Blizzard's own bar textures, plus any SharedMedia textures you have installed, in a visual picker.

Works on Classic Era / Anniversary and WoW Forever. On Forever, Blizzard's built-in swing timer bars also exist;
set them to *Hidden* in Edit Mode if you want only these. A target swing bar (Classic Era only) is planned.

`/vwst` opens the options, `/vwst status` prints diagnostics.

Inspired by [WeaponSwingTimer](https://github.com/LeftHandedGlove/WeaponSwingTimerAddon) by LeftHandedGlove; this
is a from-scratch rewrite with a different visibility model. MIT licensed.