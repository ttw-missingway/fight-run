# GDScript Style Guide

A consistent, foldable, well-documented structure for every script in the project.

## Why regions

Every script follows the same top-to-bottom shape, with each part wrapped in a
foldable `#region`. The payoff:

- **Predictable files.** Any script opens to the same structure, so you always
  know where signals, state, lifecycle, and helpers live — no hunting.
- **Fast navigation.** Collapse every region to read a file as a table of
  contents, then expand only the part you need.
- **Cleaner reviews.** Related members stay grouped, so changes land in one
  place instead of scattering across the file.
- **A built-in size check.** When a region starts begging for sub-regions,
  that's the signal the class is doing too much and should be split.

## Section order

Wrap each section that's present in its own `#region`, in this exact order.
Omit any section that's empty — never leave an empty region behind.

```gdscript
extends X
class_name Y

## One-line summary of what this class is.
## Longer note if needed.

#region Signals
#region Enums
#region Constants
#region Exports
#region Onready
#region Public state
#region Private state
#region Lifecycle        # _ready, _process, _physics_process
#region Public API
#region Private helpers
```

## Region rules

- **Exact, spaced names** from the list above — `Private state`, `Public API`,
  `Private helpers` (not `Privatestate` / `PublicAPI` / `Privatehelpers`).
- **One section per region.** No sub-regions, and never nest a `#region` inside
  a function.
- **Omit empty sections** entirely — an empty region is just noise.
- **Lifecycle is a table of contents.** `_ready` / `_process` /
  `_physics_process` call named private helpers; they don't inline the work.
- **Split, don't subdivide.** If a section grows large enough to want internal
  regions, that's a smell the class is doing too much — split the class instead.

## Documentation

- **`##` docstring above every `class_name`** — the *header docstring*: a
  one-line summary of what the class is, sitting right under the `extends` /
  `class_name` lines (longer note on following `##` lines if needed).
- **`##` docstring above every public method** — what it does / when to call it.
- **`#` comments inside a method explain *why*, never *what*.** If a line needs a
  comment to say what it does, the names probably aren't carrying their weight.
- **Non-obvious constants get a short `#` note;** self-explaining names don't.

```gdscript
extends Area2D
class_name MimicProjectile

## Mimic's arcing coin: lobs under gravity, lands as a grounded hitbox,
## flashes a despawn warning, then topples and fades.

# Good — the name carries the meaning, no comment needed
var current_hp: int = 0

# Good — a non-obvious tuning value earns a why
const BURN_LOCK_GRACE := 0.1  # avoids flicker when burn + boost end the same frame

## Extends the base spawn: seeds the arc velocity and starts the spin.
func setup(...) -> void:
    ...
```

## Signals

- **Past tense** — a signal announces something that *happened*: `died`,
  `lives_changed`, `match_over`. (`open_menu` reads like a command — that's a
  method, not a signal.)
- **Minimal payload.** Pass only what listeners can't easily ask the sender for;
  wide payloads ossify the API.
- **`##` doc above each signal** describing the payload.
- **Connect in code, not the editor** — connections in `_ready()` (or a
  dedicated `_connect_signals()`) are greppable; editor wiring is invisible
  until it breaks.
- **Connect once.** If a node's lifecycle can re-enter a connection path, guard
  with `is_connected()` or disconnect on exit.

```gdscript
## Emitted when an enemy is defeated. payload: enemy that died, source (may be null).
signal died(fighter: Fighter, source: Fighter)
```

## Conventions already in force

These match the existing codebase; documented here so the guide is the single
source of truth.

- **Static typing, always.** Type vars, params, and returns; typed arrays
  (`Array[Fighter]`, not `Array`). Inferred `:=` is fine when the right-hand side
  makes the type obvious (`var n := 0`); don't infer ambiguous literals.
- **Naming.** File `snake_case.gd`; `class_name` PascalCase; vars/funcs
  `snake_case`; constants `SCREAMING_SNAKE_CASE`; private members leading `_`;
  enum types PascalCase, values `SCREAMING_SNAKE_CASE`; scene nodes PascalCase.
- **No magic numbers in logic.** Tunable gameplay values live in `@export`s,
  `Resource`s, or named `const`s — not inline literals. Loop counters and
  obvious local literals are fine.
- **Private by default.** If it isn't called from outside the class, prefix `_`.
  Keep each class's public surface as small as the job allows.
- **Header order:** `extends` first, then `class_name` (project convention).
```

## Debug overlay colors

All collision debug fills use the same palette and opacity. Apply these to `ColorRect` debug nodes in fighter scenes and `Polygon2D` `DebugFill` children of `CollisionShape2D` nodes in rig scenes.

| Role | Color constant | RGBA |
|---|---|---|
| Hitbox (offensive) | `HITBOX_DEBUG_COLOR` | `Color(0.91, 0.0, 0.73, 0.42)` — magenta |
| Hurtbox (vulnerable) | `HURTBOX_DEBUG_COLOR` | `Color(0.2, 0.9, 0.2, 0.42)` — green |
| Grabbox | `GRABBOX_DEBUG_COLOR` | `Color(0.96, 0.65, 0.14, 0.42)` — amber |
| I-frames (invincible) | — | `Color(0.15, 0.82, 1.0, 0.8)` — cyan, pulsing |
| V-frames (vulnerable state) | — | `Color(1.0, 0.05, 0.45, 0.85)` — pink, pulsing |

Rules:
- Hitboxes are always **magenta**. Hurtboxes are always **green**. Grabboxes are always **amber**.
- All fills use **0.42 alpha** (i-frame/v-frame overlays pulse and use higher alpha by design).
- `DebugFill` `Polygon2D` nodes live as direct children of their `CollisionShape2D` so they inherit position and scale automatically.
