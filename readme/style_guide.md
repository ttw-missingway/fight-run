# GDScript Region & Layout Style

A consistent, foldable structure for every script in the project.

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

## Documentation that pairs with it

- `##` docstring above every `class_name` and every public method.
- `#` comments inside a method explain **why**, never **what**.
- A constant whose name doesn't fully explain itself gets a short `#` note.

```gdscript
# Good — the name carries the meaning, no comment needed
var current_hp: int = 0

# Good — a non-obvious tuning value earns a why
const BURN_LOCK_GRACE := 0.1  # avoids flicker when burn + boost end the same frame
```

## Skeleton

```gdscript
extends Area2D
class_name MimicProjectile

## Mimic's arcing coin: lobs under gravity, lands as a grounded hitbox,
## flashes a despawn warning, then topples and fades.

#region Constants
const WORLD_LAYER: int = 1
#endregion

#region Private state
var _velocity: Vector2 = Vector2.ZERO
#endregion

#region Lifecycle
func _ready() -> void:
    ...
#endregion

#region Public API
## Extends the base spawn: seeds the arc and starts the spin.
func setup(...) -> void:
    ...
#endregion

#region Private helpers
func _apply_motion(delta: float) -> void:
    ...
#endregion
```
