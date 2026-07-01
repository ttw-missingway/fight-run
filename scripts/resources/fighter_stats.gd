class_name FighterStats
extends Resource

## All tunable per-character data: movement, jumps, dashes, block/knockdown
## scaling, juggle and wakeup timing, plus the move set (attacks, grab,
## projectile config) that defines a fighter's identity purely as data.

#region Exports

## The character's visual rig: a Node2D scene with an AnimatedSprite2D and the
## CharacterAnimator script. Instanced under the Fighter's FacingPivot at spawn.
## Leave null to fall back to the placeholder BodyRect.
@export var visual_scene: PackedScene

@export var max_lives: int = 3
@export var max_mana: int = 3
@export var back_dash_mana_cost: int = 1
@export var combo_break_mana_cost: int = 1
@export var combo_break_push_knockback: float = 780.0
@export var combo_break_slide_duration: float = 0.48
@export var combo_break_close_range: float = 96.0
@export var weight: float = 1.0
@export var body_push_factor: float = 22.0
@export var move_speed: float = 220.0
@export var air_move_speed: float = 190.0
@export var jump_velocity: float = -480.0
@export var short_hop_velocity: float = -320.0
@export var super_jump_velocity: float = -580.0
@export var dash_speed: float = 560.0
@export var dash_duration: float = 0.09
@export var dash_ground_duration: float = 0.12
@export var dash_recovery_duration: float = 0.07
@export var dash_air_momentum_carry: float = 0.35
@export var block_knockback_multiplier: float = 1.8
@export var crouch_block_knockback_multiplier: float = 0.35
@export var projectile_block_knockback_multiplier: float = 1.05
@export var knockdown_launch_velocity: float = -320.0
@export var knockdown_gravity_scale: float = 0.82
@export var air_knockdown_pop_velocity: float = -440.0
@export var air_knockdown_horizontal_scale: float = 0.72
@export var stagger_hitstun_duration: float = 0.48
@export var stagger_knockback_multiplier: float = 1.0
@export var stagger_meter_knockdown: int = 30
@export var juggle_gravity_scale: float = 0.62
@export var fast_fall_gravity_scale: float = 4.25
@export var fast_fall_max_velocity: float = 1350.0
@export var air_attack_landing_lag_frames: int = 10
@export var stun_hitstun_duration: float = 0.62
@export var stun_air_spike_velocity: float = 520.0
@export var crouch_move_scale: float = 0.55
@export var ledge_hang_offset_y: float = 22.0
@export var ledge_grab_range: float = 64.0
@export var wakeup_roll_distance: float = 192.0
@export var wakeup_roll_duration: float = 0.50
@export var slow_getup_duration: float = 0.68
@export var slow_getup_invincible_duration: float = 0.45
@export var gravity: float = 980.0
@export var projectile_config: ProjectileConfig = preload("res://data/resources/default_projectile_config.tres")
# Per-character move set. Leave any field empty to inherit the shared default
# (see DEFAULT_* consts in fighter.gd). This is what makes a fighter's identity
# pure data: swap the .tres, swap the moves — no code changes.
# attacks maps an action name (e.g. "neutral", "forward", "air_up") -> AttackData.
@export var attacks: Dictionary = {}
@export var dash_attack: AttackData
@export var grab_data: GrabData
@export var wakeup_attack: AttackData

#endregion
