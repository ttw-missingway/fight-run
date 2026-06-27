extends Node2D
class_name CharacterAnimator
## Plays the right anim on the character sprite from the parent Fighter's state.
## Character-agnostic: differences live in the SpriteFrames (which anim names
## exist) and the sprite Offset, never here. * Facing is FacingPivot's job.


#region Onready

@onready var _sprite: AnimatedSprite2D = $Sprite

#endregion


#region Privatestate

var _fighter: Fighter
var _current: StringName = &""
var _attack_serial: int = -1

#endregion


#region Lifecycle

func _ready() -> void:
	var node := get_parent()
	while node != null and not (node is Fighter):
		node = node.get_parent()
	_fighter = node as Fighter


func _process(_delta: float) -> void:
	if _fighter == null or _fighter.state_machine == null or _sprite.sprite_frames == null:
		return
	
	var sm := _fighter.state_machine
	var target := _resolve(_candidates())
	
	var restart := false
	if sm.current_state == FighterStateMachine.State.ATTACK and sm.attack_hit_serial != _attack_serial:
		_attack_serial = sm.attack_hit_serial
		restart = true
	
	if target != _current or restart:
		_current = target
		_sprite.play(target)
		_sprite.speed_scale = _attack_speed_scale() if target == &"attack" else 1.0

#endregion


#region Privatehelpers

func _resolve(candidates: Array) -> StringName:
	for candidate in candidates:
		if _sprite.sprite_frames.has_animation(candidate):
			return candidate
	return &"idle"


func _candidates() -> Array:
	var sm := _fighter.state_machine
	var airborne := not _fighter.is_on_floor()
	match sm.current_state:
		FighterStateMachine.State.MOVE:
			return _air() if airborne else [&"run", &"idle"]
		FighterStateMachine.State.IDLE:
			return _air() if airborne else [&"idle"]
		FighterStateMachine.State.DASH:
			return [&"dash", &"run", &"idle"]
		FighterStateMachine.State.ATTACK:
			return [&"attack", &"idle"]
		FighterStateMachine.State.BLOCK, FighterStateMachine.State.CROUCH_BLOCK:
			return [&"block", &"idle"]
		FighterStateMachine.State.CROUCH:
			return [&"crouch", &"idle"]
		FighterStateMachine.State.STAGGER, FighterStateMachine.State.STUN:
			return [&"hit", &"idle"]
		FighterStateMachine.State.KNOCKDOWN:
			return [&"knockdown", &"hit", &"idle"]
		FighterStateMachine.State.GETUP_INVINCIBLE, FighterStateMachine.State.SLOW_GETUP:
			return [&"getup", &"idle"]
		FighterStateMachine.State.WAKEUP_ROLL:
			return [&"roll", &"run", &"idle"]
		FighterStateMachine.State.LEDGE_RECOVERY:
			return [&"ledge", &"idle"]
		FighterStateMachine.State.DEAD:
			return [&"death", &"idle"]
		FighterStateMachine.State.RESPAWN:
			return _air() if sm.is_respawn_falling() else [&"idle"]
		_:
			return [&"idle"]


func _air() -> Array:
	if _fighter.velocity.y < 0.0:
		return [&"jump", &"fall", &"idle"]
	else:
		return [&"fall", &"jump", &"idle"]

# Scales the attack clip so the whole swing plays across the attack's real
# frame-data duration. Without this, the clip's fixed FPS means fast attacks
# (jab, forward) end before the animation finishes — you only see the startup —
# while a slow one (back overhead) happens to last long enough to show it all.
func _attack_speed_scale() -> float:
	var attack := _fighter.state_machine.current_attack as AttackData
	if attack == null:
		return 1.0
	var frame_count := _sprite.sprite_frames.get_frame_count(&"attack")
	var fps := _sprite.sprite_frames.get_animation_speed(&"attack")
	if frame_count <= 0 or fps <= 0.0:
		return 1.0
	var clip_seconds := float(frame_count) / fps
	var attack_frames := attack.startup_frames + attack.active_frames + attack.recovery_frames_whiff
	var attack_seconds := CombatTiming.frames_to_seconds(attack_frames)
	if attack_seconds <= 0.0:
		return 1.0
	return clip_seconds / attack_seconds

#endregion
