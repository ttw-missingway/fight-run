extends ProjectileConfig
class_name MimicProjectileConfig

## Adds Mimic's arc-and-linger tunables on top of the base straight-line
## projectile config. Consumed by MimicProjectile.


#region Exports

## Downward acceleration applied to the lob each second (px/s²). Controls arc snappiness.
@export var gravity: float = 900.0

## Knockback the coin applies on hit; overrides the inherited base ProjectileConfig
## knockback for Mimic only.
@export var knockback_strength: float = 175.0

## Base arc peak height in px, before charge scaling.
@export var arc_base_height: float = 150.0

## Base arc horizontal distance in px, before charge scaling.
@export var arc_base_distance: float = 200.0

## Charge stage multiplier for arc height AND distance per charge stage above base.
## 1.1 = +10% at half charge, +20% at full (applied additively, not compounding).
@export var charge_stage_multiplier: float = 1.45

## Linger at full charge: how long the coin spins as an active hitbox before toppling.
@export var ground_linger_seconds: float = 8.0

## Linger at half charge (time held in [half_charge_threshold, full_charge_threshold)).
@export var linger_half_seconds: float = 4.0

## Linger below half charge.
@export var linger_min_seconds: float = 2.0

## Charge TIME fraction at/above which the coin gets the full linger.
@export var full_charge_threshold: float = 0.99

## Charge TIME fraction at/above which the coin gets the half linger.
@export var half_charge_threshold: float = 0.5

## Degrees the sprite rotates when it topples over at the end of the linger.
@export var landing_spin_degrees: float = 90.0

## Uniform sprite scale once landed. 2.0 = twice the source art size.
@export var sprite_scale: float = 2.0

## Length of the visibility-flash warning at the tail of the linger.
@export var flash_seconds: float = 3.0

## Seconds the coin spends shown, then hidden, during each flash blink.
@export var flash_interval: float = 0.15

## Seconds to fade the toppled coin to invisible before it despawns.
@export var fade_out_seconds: float = 0.25

## Fine-tune nudge added on top of the automatic sprite-bottom snap.
## Positive lifts the coin, negative sinks it. Leave at 0 unless the snap looks off.
@export var ground_rest_nudge: float = 0.0

#endregion
