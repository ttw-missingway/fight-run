extends Resource
class_name ProjectileConfig

## Tuning data for chargeable projectiles: charge curve, stagger/health scaling,
## speed, frame timing, spawn offsets, and the projectile/hit-effect scenes.

#region Exports

@export var min_stagger: int = 4
@export var max_stagger: int = 100
@export var auto_kill_stagger: int = 100
@export var min_health: int = 4
@export var max_health: int = 18
@export var max_charge_time: float = 2.7
@export var charge_log_speed: float = 3.0
@export var speed: float = 420.0
@export var knockback: float = 175.0
@export var startup_frames: int = 10
@export var recovery_frames: int = 28
@export var min_size: Vector2 = Vector2(14.0, 14.0)
@export var max_size: Vector2 = Vector2(40.0, 40.0)
@export var spawn_offset: Vector2 = Vector2(38.0, -28.0)
@export var air_spawn_offset: Vector2 = Vector2(38.0, -28.0)
@export var low_spawn_offset: Vector2 = Vector2(38.0, -10.0)
@export var air_low_spawn_offset: Vector2 = Vector2(38.0, -10.0)
@export var max_lifetime: float = 2.5
@export var size_similarity_ratio: float = 0.72
@export var projectile_scene: PackedScene = preload("res://scenes/fight/projectile.tscn")
@export var hit_effect_scene: PackedScene = preload("res://scenes/animations/projectile_hit.tscn")

#endregion


#region Public API

## Normalized 0..1 charge level for a held duration, following a log curve.
func get_charge_ratio(charge_time: float) -> float:
	var scaled_max := CombatTiming.scale_time(max_charge_time)
	if scaled_max <= 0.0:
		return 0.0
	if charge_time >= scaled_max:
		return 1.0
	var log_cap := log(1.0 + scaled_max * charge_log_speed)
	if log_cap <= 0.0:
		return clampf(charge_time / scaled_max, 0.0, 1.0)
	return log(1.0 + charge_time * charge_log_speed) / log_cap

#endregion
