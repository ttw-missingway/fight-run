extends Node
class_name AiController

enum BehaviorMode {
	BLOCK,
	DASH,
	JUMP,
	DUCK_BLOCK,
	DUCK,
	ATTACK,
	GRAB,
	PROJECTILE,
	ZONER,
	RUSHDOWN,
	COUNTER,
	SHOTO,
	GRAPPLER,
}

const SIMPLE_MODES: Array[BehaviorMode] = [
	BehaviorMode.BLOCK,
	BehaviorMode.DASH,
	BehaviorMode.JUMP,
	BehaviorMode.DUCK_BLOCK,
	BehaviorMode.DUCK,
	BehaviorMode.ATTACK,
	BehaviorMode.GRAB,
	BehaviorMode.PROJECTILE,
]

const COMPLEX_MODES: Array[BehaviorMode] = [
	BehaviorMode.ZONER,
	BehaviorMode.RUSHDOWN,
	BehaviorMode.COUNTER,
	BehaviorMode.SHOTO,
	BehaviorMode.GRAPPLER,
]

const MODE_LABELS := {
	BehaviorMode.BLOCK: "Block",
	BehaviorMode.DASH: "Dash",
	BehaviorMode.JUMP: "Jump",
	BehaviorMode.DUCK_BLOCK: "Duck Block",
	BehaviorMode.DUCK: "Duck",
	BehaviorMode.ATTACK: "Attack",
	BehaviorMode.GRAB: "Grab",
	BehaviorMode.PROJECTILE: "Projectile",
	BehaviorMode.ZONER: "Zoner",
	BehaviorMode.RUSHDOWN: "Rushdown",
	BehaviorMode.COUNTER: "Counter",
	BehaviorMode.SHOTO: "Shoto",
	BehaviorMode.GRAPPLER: "Grappler",
}

const MODE_CATEGORY := {
	BehaviorMode.BLOCK: "Simple",
	BehaviorMode.DASH: "Simple",
	BehaviorMode.JUMP: "Simple",
	BehaviorMode.DUCK_BLOCK: "Simple",
	BehaviorMode.DUCK: "Simple",
	BehaviorMode.ATTACK: "Simple",
	BehaviorMode.GRAB: "Simple",
	BehaviorMode.PROJECTILE: "Simple",
	BehaviorMode.ZONER: "Complex",
	BehaviorMode.RUSHDOWN: "Complex",
	BehaviorMode.COUNTER: "Complex",
	BehaviorMode.SHOTO: "Complex",
	BehaviorMode.GRAPPLER: "Complex",
}

@export var enabled: bool = false
@export var behavior_mode: BehaviorMode = BehaviorMode.BLOCK
@export var think_interval: float = 0.27
@export var attack_range: float = 90.0
@export var close_range: float = 45.0
@export var zoner_ideal_min_range: float = 130.0
@export var zoner_ideal_max_range: float = 230.0
@export var zoner_panic_range: float = 75.0
@export var shoto_center_band: float = 120.0
@export var shoto_edge_margin: float = 140.0

var _fighter: Fighter
var _think_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _move_direction: int = 0
var _engaged: bool = false
var _wakeup_triggered: bool = false

var _virtual_jump: bool = false
var _virtual_throw: bool = false
var _virtual_guard: bool = false
var _virtual_crouch: bool = false
var _virtual_projectile_charge: float = -1.0
var _virtual_projectile_low: bool = false
var _pending_attack_name: String = ""
var _hold_guard: bool = false
var _hold_crouch: bool = false


func _ready() -> void:
	_fighter = get_parent() as Fighter
	set_physics_process(false)
	_reset_mode_state()


func get_mode_label() -> String:
	return MODE_LABELS.get(behavior_mode, "Unknown")


func get_mode_category() -> String:
	return MODE_CATEGORY.get(behavior_mode, "")


func set_behavior_mode(mode: BehaviorMode) -> void:
	behavior_mode = mode
	_reset_mode_state()


func _reset_mode_state() -> void:
	_move_direction = 0
	_think_timer = 0.0
	_attack_cooldown = 0.0
	_wakeup_triggered = false
	_hold_guard = false
	_hold_crouch = false
	_engaged = _is_complex_mode()


func _is_simple_mode() -> bool:
	return behavior_mode in SIMPLE_MODES


func _is_complex_mode() -> bool:
	return behavior_mode in COMPLEX_MODES


func _survival_active() -> bool:
	return _is_complex_mode() or _engaged


func notify_took_damage() -> void:
	_engaged = true


func notify_blocked_hit() -> void:
	_engaged = true


func update_input(delta: float) -> void:
	if not enabled or _fighter == null:
		return
	if _fighter.opponent == null:
		return
	if not _fighter.state_machine.is_active_in_match():
		_fighter.clear_virtual_input()
		_move_direction = 0
		_wakeup_triggered = false
		return

	if _handle_recovery_input():
		return

	if not _survival_active():
		_hold_guard = false
		_hold_crouch = false
		_fighter.set_virtual_input(false, false, false, false, false, "", false, 0, -1.0, false)
		return

	_apply_stance_holds()

	_think_timer -= delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	if _think_timer <= 0.0:
		_think_timer = think_interval
		_decide_action()

	_emit_virtual_input()


func _emit_virtual_input() -> void:
	_fighter.set_virtual_input(
		_move_direction < 0,
		_move_direction > 0,
		_virtual_jump,
		_hold_guard or _virtual_guard,
		_hold_crouch or _virtual_crouch,
		_pending_attack_name,
		_virtual_throw,
		_throw_direction_for_hold(),
		_virtual_projectile_charge,
		_virtual_projectile_low
	)
	_virtual_jump = false
	_virtual_throw = false
	_virtual_guard = false
	_virtual_crouch = false
	_virtual_projectile_charge = -1.0
	_virtual_projectile_low = false
	_pending_attack_name = ""


func _apply_stance_holds() -> void:
	match behavior_mode:
		BehaviorMode.BLOCK:
			if _fighter.is_on_floor() and _fighter.state_machine.can_hold_guard():
				_hold_guard = true
				_hold_crouch = false
		BehaviorMode.DUCK_BLOCK:
			if _fighter.is_on_floor() and _fighter.state_machine.can_hold_guard():
				_hold_guard = true
				_hold_crouch = true
		BehaviorMode.DUCK:
			if _fighter.is_on_floor():
				_hold_guard = false
				_hold_crouch = true
		BehaviorMode.COUNTER:
			if _fighter.is_on_floor() and _fighter.state_machine.can_hold_guard():
				_hold_guard = true


func _handle_recovery_input() -> bool:
	if _fighter.state_machine.is_on_ledge():
		if _fighter.state_machine.can_use_ledge_wakeup_options():
			if not _wakeup_triggered:
				_trigger_mode_wakeup(true)
				_wakeup_triggered = true
			_emit_virtual_input()
			return true
		_update_ledge_hang_wait()
		_emit_virtual_input()
		return true

	if (
		_fighter.state_machine.is_knocked_down()
		and _fighter.state_machine.knockdown_landed
		and _fighter.state_machine.can_use_knockdown_wakeup_options()
	):
		if _fighter.state_machine.is_knockdown_forced_ground():
			if not _wakeup_triggered:
				_trigger_mode_wakeup(false)
				_wakeup_triggered = true
		elif _fighter.state_machine.has_buffered_prone_wakeup:
			_fighter.state_machine.try_execute_buffered_prone_wakeup()
			_wakeup_triggered = false
		elif not _wakeup_triggered:
			_trigger_mode_wakeup(false)
			_wakeup_triggered = true
		_emit_virtual_input()
		return true

	_wakeup_triggered = false
	return false


func _update_ledge_hang_wait() -> void:
	_move_direction = 0


func _trigger_mode_wakeup(from_ledge: bool) -> void:
	if _is_simple_mode() and not _engaged:
		_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.NEUTRAL)
		return
	match behavior_mode:
		BehaviorMode.BLOCK, BehaviorMode.DUCK_BLOCK:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.BLOCK)
		BehaviorMode.DUCK:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.CROUCH)
		BehaviorMode.DASH, BehaviorMode.COUNTER, BehaviorMode.SHOTO:
			_start_center_roll_wakeup(from_ledge)
		BehaviorMode.JUMP, BehaviorMode.PROJECTILE:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.JUMP)
		BehaviorMode.ATTACK, BehaviorMode.RUSHDOWN:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.ATTACK)
		BehaviorMode.GRAB, BehaviorMode.GRAPPLER:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.GRAB)
		BehaviorMode.ZONER:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.JUMP)


func _start_wakeup(from_ledge: bool, option: FighterStateMachine.WakeupOption) -> void:
	if from_ledge:
		_fighter.perform_ledge_wakeup(option)
	else:
		_fighter.state_machine.begin_knockdown_wakeup(option)


func _start_center_roll_wakeup(from_ledge: bool) -> void:
	var roll := _center_roll_option(from_ledge)
	_start_wakeup(from_ledge, roll)


func _center_roll_option(from_ledge: bool) -> FighterStateMachine.WakeupOption:
	var fm := _fighter.fight_manager
	var x := _fighter.global_position.x
	if from_ledge and _fighter.state_machine.ledge_side != 0:
		if _fighter.state_machine.ledge_side < 0:
			return FighterStateMachine.WakeupOption.ROLL_RIGHT
		return FighterStateMachine.WakeupOption.ROLL_LEFT
	if fm != null:
		if x > fm.platform_left + 80.0:
			return FighterStateMachine.WakeupOption.ROLL_LEFT
		if x < fm.platform_right - 80.0:
			return FighterStateMachine.WakeupOption.ROLL_RIGHT
	return FighterStateMachine.WakeupOption.ROLL_LEFT if x > 0.0 else FighterStateMachine.WakeupOption.ROLL_RIGHT


func _apply_getup_followup_input() -> void:
	if _is_simple_mode() and not _engaged:
		return
	match behavior_mode:
		BehaviorMode.BLOCK:
			_hold_guard = true
			_hold_crouch = false
		BehaviorMode.DUCK_BLOCK:
			_hold_guard = true
			_hold_crouch = true
		BehaviorMode.DUCK:
			_hold_crouch = true
			_hold_guard = false
		BehaviorMode.GRAB, BehaviorMode.GRAPPLER:
			if _fighter.state_machine.can_buffer_wakeup_followup():
				_fighter.state_machine.set_wakeup_followup(FighterStateMachine.WakeupOption.GRAB)
		BehaviorMode.ATTACK, BehaviorMode.RUSHDOWN:
			if _fighter.state_machine.can_buffer_wakeup_followup():
				_fighter.state_machine.set_wakeup_followup(FighterStateMachine.WakeupOption.ATTACK)
		BehaviorMode.PROJECTILE, BehaviorMode.JUMP, BehaviorMode.ZONER:
			if _fighter.state_machine.can_buffer_wakeup_followup():
				_fighter.state_machine.set_wakeup_followup(FighterStateMachine.WakeupOption.JUMP)


func _throw_direction_for_hold() -> int:
	if _fighter.state_machine.is_holding_grab():
		if behavior_mode == BehaviorMode.COUNTER:
			return -_fighter.facing
		return 1 if randf() > 0.35 else -1
	return 0


func _decide_action() -> void:
	_move_direction = 0
	var target := _fighter.opponent
	var distance := absf(target.global_position.x - _fighter.global_position.x)
	var target_left := target.global_position.x < _fighter.global_position.x

	match behavior_mode:
		BehaviorMode.BLOCK:
			_decide_simple_block()
		BehaviorMode.DASH:
			_decide_simple_dash(distance, target_left)
		BehaviorMode.JUMP:
			_decide_simple_jump()
		BehaviorMode.DUCK_BLOCK:
			_decide_simple_duck_block()
		BehaviorMode.DUCK:
			_decide_simple_duck()
		BehaviorMode.ATTACK:
			_decide_simple_attack(distance)
		BehaviorMode.GRAB:
			_decide_simple_grab(distance)
		BehaviorMode.PROJECTILE:
			_decide_simple_projectile(distance)
		BehaviorMode.ZONER:
			_decide_zoner_behavior(distance, target_left)
		BehaviorMode.RUSHDOWN:
			_decide_rushdown_behavior(distance, target_left)
		BehaviorMode.COUNTER:
			_decide_counter_behavior(distance, target_left, target)
		BehaviorMode.SHOTO:
			_decide_shoto_behavior(distance, target_left, target)
		BehaviorMode.GRAPPLER:
			_decide_grappler_behavior(distance, target_left)


func _decide_simple_block() -> void:
	pass


func _decide_simple_duck_block() -> void:
	pass


func _decide_simple_duck() -> void:
	pass


func _decide_simple_jump() -> void:
	if _fighter.is_on_floor() and randf() < 0.45:
		_virtual_jump = true


func _decide_simple_dash(distance: float, target_left: bool) -> void:
	if not _fighter.is_on_floor() or _attack_cooldown > 0.0:
		return
	if distance < attack_range * 1.2:
		if randf() < 0.55:
			var orbit := -1 if not target_left else 1
			if randf() < 0.5:
				orbit *= -1
			_fighter.request_dash(orbit)
			_attack_cooldown = CombatTiming.scale_time(0.45)
	elif randf() < 0.25:
		_fighter.request_dash(-1 if target_left else 1)
		_attack_cooldown = CombatTiming.scale_time(0.55)


func _decide_simple_attack(distance: float) -> void:
	if distance < attack_range and _attack_cooldown <= 0.0 and _fighter.is_on_floor():
		_pick_random_attack()
		_attack_cooldown = CombatTiming.scale_time(randf_range(0.45, 0.75))


func _decide_simple_grab(distance: float) -> void:
	if distance < close_range + 20.0 and _attack_cooldown <= 0.0 and _fighter.is_on_floor():
		_virtual_throw = true
		_attack_cooldown = CombatTiming.scale_time(randf_range(0.55, 0.9))


func _decide_simple_projectile(_distance: float) -> void:
	if _attack_cooldown > 0.0:
		return
	if randf() < 0.2 and _fighter.is_on_floor():
		_virtual_jump = true
	_attack_cooldown = CombatTiming.scale_time(randf_range(0.35, 0.65))
	_virtual_projectile_charge = randf_range(0.0, 0.55)
	_virtual_projectile_low = randf() < 0.4


func _decide_zoner_behavior(distance: float, target_left: bool) -> void:
	_apply_zoner_movement(distance, target_left)
	if _attack_cooldown > 0.0:
		return
	if distance < zoner_panic_range:
		if _fighter.is_on_floor() and randf() < 0.35:
			_fighter.request_dash(-1 if not target_left else 1)
			_attack_cooldown = CombatTiming.scale_time(0.45)
		elif randf() < 0.4:
			_virtual_guard = true
		return
	if distance >= zoner_ideal_min_range * 0.75:
		_queue_zoner_shot()
	elif distance > close_range and randf() < 0.6:
		_queue_zoner_shot()


func _queue_zoner_shot() -> void:
	_virtual_projectile_charge = _random_zoner_charge()
	_virtual_projectile_low = randf() < 0.35
	_attack_cooldown = CombatTiming.scale_time(randf_range(0.55, 1.1))


func _decide_rushdown_behavior(distance: float, target_left: bool) -> void:
	_move_toward_target(distance, target_left)
	if _attack_cooldown > 0.0:
		return
	if distance <= close_range + 8.0 and _fighter.is_on_floor() and randf() < 0.35:
		_virtual_throw = true
		_attack_cooldown = CombatTiming.scale_time(0.65)
	elif distance < attack_range and _fighter.is_on_floor():
		if randf() < 0.55:
			_pending_attack_name = "forward"
		else:
			_pick_random_attack()
		_attack_cooldown = CombatTiming.scale_time(0.42)
	elif distance < attack_range * 1.4 and _fighter.is_on_floor() and randf() < 0.35:
		_fighter.request_dash(1 if not target_left else -1)
		_attack_cooldown = CombatTiming.scale_time(0.35)


func _decide_counter_behavior(distance: float, target_left: bool, target: Fighter) -> void:
	if distance < close_range + 10.0:
		if target.state_machine.is_attack_in_landing_lag() or target.state_machine.is_attack_active():
			if _attack_cooldown <= 0.0 and _fighter.is_on_floor():
				_virtual_throw = true
				_attack_cooldown = CombatTiming.scale_time(0.75)
				return
		return
	if distance < attack_range and randf() < 0.2 and _fighter.is_on_floor():
		_fighter.request_dash(-1 if target_left else 1)
		_attack_cooldown = CombatTiming.scale_time(0.5)


func _decide_shoto_behavior(distance: float, target_left: bool, target: Fighter) -> void:
	_apply_shoto_spacing(distance, target_left)
	if _attack_cooldown > 0.0 or not _fighter.is_on_floor():
		return
	if distance < close_range and target.state_machine.is_blocking() and randf() < 0.25:
		_virtual_throw = true
		_attack_cooldown = CombatTiming.scale_time(0.7)
	elif distance > zoner_ideal_min_range and randf() < 0.35:
		_virtual_projectile_charge = randf_range(0.15, 0.65)
		_attack_cooldown = CombatTiming.scale_time(0.75)
	elif distance < attack_range:
		if randf() < 0.5:
			_pending_attack_name = "neutral"
		else:
			_pending_attack_name = "forward"
		_attack_cooldown = CombatTiming.scale_time(0.5)


func _decide_grappler_behavior(distance: float, target_left: bool) -> void:
	_move_toward_target(distance, target_left)
	if _attack_cooldown > 0.0 or not _fighter.is_on_floor():
		return
	if distance < attack_range and distance > close_range and randf() < 0.45:
		_fighter.request_dash(1 if not target_left else -1)
		_attack_cooldown = CombatTiming.scale_time(0.35)
	elif distance < close_range + 24.0 and randf() < 0.65:
		_virtual_throw = true
		_attack_cooldown = CombatTiming.scale_time(0.55)


func _apply_shoto_spacing(distance: float, target_left: bool) -> void:
	var fm := _fighter.fight_manager
	if fm == null:
		return
	var x := _fighter.global_position.x
	if absf(x) > shoto_edge_margin:
		_move_direction = -1 if x > 0.0 else 1
	elif distance > attack_range + 40.0:
		_set_move_toward_target(target_left)
	elif distance < close_range - 8.0:
		_set_move_away_from_target(target_left)


func _apply_zoner_movement(distance: float, target_left: bool) -> void:
	if distance < zoner_ideal_min_range:
		_set_move_away_from_target(target_left)
	elif distance > zoner_ideal_max_range:
		if randf() < 0.4:
			_set_move_toward_target(target_left)


func _random_zoner_charge() -> float:
	return pow(randf(), 0.65)


func _set_move_away_from_target(target_left: bool) -> void:
	var fm := _fighter.fight_manager
	if fm != null:
		if target_left and _fighter.global_position.x < fm.platform_right - 36.0:
			_move_direction = 1
		elif not target_left and _fighter.global_position.x > fm.platform_left + 36.0:
			_move_direction = -1
	elif target_left:
		_move_direction = 1
	else:
		_move_direction = -1


func _move_toward_target(distance: float, target_left: bool) -> void:
	if distance <= 28.0:
		return
	_set_move_toward_target(target_left)


func _set_move_toward_target(target_left: bool) -> void:
	var fm := _fighter.fight_manager
	if fm != null:
		if target_left and _fighter.global_position.x > fm.platform_left + 36.0:
			_move_direction = -1
		elif not target_left and _fighter.global_position.x < fm.platform_right - 36.0:
			_move_direction = 1
	elif target_left:
		_move_direction = -1
	else:
		_move_direction = 1


func _pick_random_attack() -> void:
	var roll := randi() % 3
	match roll:
		0:
			_pending_attack_name = "neutral"
		1:
			_pending_attack_name = "forward"
		2:
			_pending_attack_name = "down"
