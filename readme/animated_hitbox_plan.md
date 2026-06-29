# Animated attack hitbox (Mimic-first)

> Decoupled, AnimationPlayer-keyframed attack hitbox. Implemented; Mimic's `attack`
> animation is authored in the editor.

## Why

An attack's hitbox used to be a single static rect baked into `AttackData`
(`hitbox_offset`/`hitbox_size`), toggled by the state machine counting frames. There
was no per-frame box authoring and nothing to see in the editor. We decouple the box
into its own animation-driven thing: an `AnimationPlayer` on the rig keyframes the
hitbox per sprite-frame (position + on/off), authored visually over the sprite.
`AttackData` keeps only the hit payload + the move's state timing. Scoped to **Mimic**,
with an automatic fallback so Knight/Minotaur keep the old system.

## Design (final)

The rig's `Hitbox` is a **plain, scriptless `Area2D`** (+ `CollisionShape2D`). Keeping
it scriptless matters: a hitbox *script* in the rig scene would drag the whole
`Fighter ↔ Hitbox ↔ Projectile` class web into `mimic.tscn`'s load and **deadlock the
editor's concurrent importer** (`ERR_BUSY` on the shared `character_animator.gd`).

- **The `AnimationPlayer`** keyframes built-in properties only: `Hitbox:monitoring`
  (on/off) and `Hitbox/CollisionShape2D:position` (movement). No script, no Call Method
  track.
- **The `Fighter`** owns detection: on rig instance it wires the plain Area2D
  (`fighter.gd:_setup_animation_driven_hitbox` → sets layer 8 / mask 4|16, connects
  `area_entered` → `_on_rig_hitbox_area_entered`). That handler runs the projectile /
  hurtbox / dedup logic and calls `_on_hit_landed` — it lives on the Fighter because the
  Fighter already has the full type context (no cycle).
- **State machine:** `start_attack` calls `Fighter.on_attack_started()` (clears the
  per-move dedup). `set_hitbox_active()` is a no-op for animated rigs (the animation owns
  `monitoring`), except it force-closes `monitoring` on recovery.
- **Sync:** `character_animator.gd` plays the rig `AnimationPlayer`'s `attack` in lockstep
  with the sprite clip (same start, same `speed_scale`), so box keys align to sprite frames.
- **Fallback:** rigs without an `AnimationPlayer` + `attack` animation use the shared
  `$FacingPivot/Hitbox` + `AttackData` geometry, exactly as before.

## Files

- `scenes/characters/mimic.tscn` — `AnimationPlayer` + plain `Hitbox` Area2D + CollisionShape2D + the `attack` animation.
- `scripts/fight/fighter.gd` — `_setup_animation_driven_hitbox`, `_on_rig_hitbox_area_entered`, `set_hitbox_active` seam, `on_attack_started`.
- `scripts/fight/fighter_state_machine.gd` — `on_attack_started()` call in `start_attack`.
- `scripts/characters/character_animator.gd` — plays the rig AnimationPlayer in lockstep.
- `scripts/fight/hitbox.gd` — unchanged shared box (fallback path).

## Editor authoring workflow

1. Open `mimic.tscn`. Select `Sprite`, set Animation to `attack` to scrub frames.
2. Select `AnimationPlayer` → the `attack` animation (length `0.875`, snap/step `0.125`, loop off).
3. Per frame (`t = frame * 0.125`): set the Sprite's **Frame** to match, drag
   `Hitbox/CollisionShape2D` over the strike, key its **`position`** (set the track to
   Discrete / Nearest).
4. **On/off:** keyframe **`Hitbox:monitoring`** (a bool) — `true` on the first active
   frame, `false` after the last. (Built-in property — no Call Method track needed.)
5. Run `scenes/fight/fight_arena.tscn`, enable **Debug ▸ Visible Collision Shapes**, pick
   Mimic, and watch the box move/toggle per frame.

## Verification

- Fresh import (`godot --headless --editor --quit`) loads with no errors.
- Arena boots clean; Knight/Minotaur unchanged (fallback path).
- Mimic attack: box appears/moves per frame, correct when facing left, lands hits, one
  hit per victim per move. Two-Mimic mirror match: both boxes animate independently.
