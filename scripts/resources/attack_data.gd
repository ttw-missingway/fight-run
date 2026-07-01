extends Resource
class_name AttackData

## Data for a single attack: hitbox geometry, frame timing, knockback, and the
## combo/juggle properties that drive how it resolves on whiff, hit, and block.

#region Enums

enum RecoveryOutcome {
	WHIFF,
	HIT,
	BLOCK,
}

enum HitType {
	STAGGER,
	STUN,
	KNOCKDOWN,
	KILL,
}

#endregion


#region Exports

@export var id: String = "attack"
@export var knockback: float = 200.0
@export var hit_type: HitType = HitType.STAGGER
@export_range(1, 30) var stagger_value: int = 6
@export var keeps_crouch: bool = false
@export var is_overhead: bool = false
@export var is_anti_air: bool = false
@export var is_dash_attack: bool = false
@export var is_retreat_jump: bool = false
@export var retreat_hop_velocity: Vector2 = Vector2(240.0, -360.0)
@export var startup_frames: int = 4
@export var active_frames: int = 5
@export var recovery_frames_whiff: int = 12
@export var recovery_frames_hit: int = 8
@export var recovery_frames_block: int = 15
@export var hitbox_offset: Vector2 = Vector2(36.0, -8.0)
@export var hitbox_size: Vector2 = Vector2(28.0, 36.0)
@export var ground_advance_speed: float = 0.0
@export var air_advance_speed: float = 0.0
@export var launch_velocity: float = 0.0
@export var hitstun_seconds: float = -1.0
@export var is_wakeup_attack: bool = false
@export var landing_lag_frames: int = -1
@export var combo_follow_up: AttackData
@export var combo_link_frame: int = -1
@export var auto_combo_on_hit: bool = false
@export var auto_chain_follow_up: bool = false
@export var combo_requires_contact: bool = false
@export var is_juggle_attack: bool = false
@export var juggle_suspend_frames: int = 0
@export var hitstop_frames: int = 0
@export var juggle_pop_velocity: float = 0.0
@export_range(0.0, 1.0) var juggle_knockback_scale: float = 0.0
@export var attacker_juggle_pop_velocity: float = 0.0
@export var attacker_juggle_pop_forward: float = 0.0
@export var juggle_spike_velocity: float = 0.0
@export var is_projectile: bool = false

#endregion


#region Public state

# World X the knockback pushes away from. Only used when is_projectile; melee uses the
# attacker's position instead.
var source_x: float = 0.0

# When false, this hit staggers but can never trigger a knockdown (e.g. a not-fully-charged
# coin). Melee and default attacks leave it true.
var can_knock_down: bool = true

#endregion


#region Public API

## Recovery frame count for the given resolution (whiff, hit, or block).
func get_recovery_frames(outcome: RecoveryOutcome) -> int:
	match outcome:
		RecoveryOutcome.HIT:
			return recovery_frames_hit
		RecoveryOutcome.BLOCK:
			return recovery_frames_block
		_:
			return recovery_frames_whiff


## Frame at which a combo follow-up can link, defaulting past the active window.
func get_combo_link_frame() -> int:
	if combo_link_frame >= 0:
		return combo_link_frame
	return startup_frames + active_frames

#endregion
