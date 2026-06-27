extends Node
class_name AiController

enum BehaviorMode {
	IDLE,
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
	BehaviorMode.IDLE,
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
	BehaviorMode.IDLE: "Idle",
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
	BehaviorMode.IDLE: "Simple",
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
	_engaged = behavior_mode != BehaviorMode.IDLE


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

	if behavior_mode == BehaviorMode.IDLE:
		_fighter.clear_virtual_input()
		return

	if _handle_combo_break_reaction():
		_emit_virtual_input()
		return

	_apply_stance_holds()

	_think_timer -= delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	if _think_timer <= 0.0:
		_think_timer = think_interval
		_decide_action()

	_emit_virtual_input()


func _handle_combo_break_reaction() -> bool:
	if not _fighter.state_machine.current_state in [
		FighterStateMachine.State.STAGGER,
		FighterStateMachine.State.GRABBED,
	]:
		return false
	if _fighter.state_machine.current_state == FighterStateMachine.State.GRABBED:
		var thrower := _fighter.state_machine.grabbed_by
		if thrower == null or not thrower.state_machine.is_holding_grab():
			return false
	if not _has_mana(_fighter.stats.combo_break_mana_cost):
		return false
	var should_break := false
	match behavior_mode:
		BehaviorMode.IDLE, BehaviorMode.BLOCK, BehaviorMode.DUCK_BLOCK:
			should_break = false
		BehaviorMode.COUNTER, BehaviorMode.RUSHDOWN, BehaviorMode.GRAPPLER:
			should_break = true
		BehaviorMode.ZONER, BehaviorMode.SHOTO:
			should_break = _engaged and randf() < 0.7
		_:
			should_break = randf() < 0.45
	if not should_break:
		return false
	_fighter.pulse_virtual_combo_break()
	return true


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
	match behavior_mode:
		BehaviorMode.IDLE:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.NEUTRAL)
		BehaviorMode.BLOCK, BehaviorMode.DUCK_BLOCK:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.BLOCK)
		BehaviorMode.DUCK:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.CROUCH)
		BehaviorMode.DASH, BehaviorMode.COUNTER, BehaviorMode.SHOTO:
			_start_center_roll_wakeup(from_ledge)
		BehaviorMode.JUMP, BehaviorMode.PROJECTILE, BehaviorMode.ZONER:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.JUMP)
		BehaviorMode.ATTACK, BehaviorMode.RUSHDOWN:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.ATTACK)
		BehaviorMode.GRAB, BehaviorMode.GRAPPLER:
			_start_wakeup(from_ledge, FighterStateMachine.WakeupOption.GRAB)


func _start_wakeup(from_ledge: bool, option: FighterStateMachine.WakeupOption) -> void:
	if from_ledge:
		_fighter.perform_ledge_wakeup(option)
	else:
		_fighter.state_machine.begin_knockdown_wakeup(option)


func _start_center_roll_wakeup(from_ledge: bool) -> void:
	_start_wakeup(from_ledge, _center_roll_option(from_ledge))


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
		BehaviorMode.IDLE:
			pass
		BehaviorMode.BLOCK:
			_decide_simple_block(distance, target_left)
		BehaviorMode.DASH:
			_decide_simple_dash(distance, target_left)
		BehaviorMode.JUMP:
			_decide_simple_jump(distance, target_left)
		BehaviorMode.DUCK_BLOCK:
			_decide_simple_duck_block(distance)
		BehaviorMode.DUCK:
			_decide_simple_duck()
		BehaviorMode.ATTACK:
			_decide_simple_attack(distance, target_left)
		BehaviorMode.GRAB:
			_decide_simple_grab(distance, target_left)
		BehaviorMode.PROJECTILE:
			_decide_simple_projectile(distance, target_left)
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


func _decide_simple_block(_distance: float, target_left: bool) -> void:
	if _fighter.is_on_floor() and randf() < 0.12:
		_set_move_toward_target(target_left)


func _decide_simple_duck_block(distance: float) -> void:
	if distance < close_range and _attack_cooldown <= 0.0 and randf() < 0.2:
		_queue_attack("down")


func _decide_simple_duck() -> void:
	if _attack_cooldown > 0.0 or not _fighter.is_on_floor():
		return
	if randf() < 0.18:
		_queue_attack("down")
		_attack_cooldown = CombatTiming.scale_time(randf_range(0.5, 0.85))


func _decide_simple_jump(distance: float, target_left: bool) -> void:
	if not _fighter.is_on_floor():
		return
	if distance < attack_range and _attack_cooldown <= 0.0 and randf() < 0.35:
		_queue_attack("neutral")
		_attack_cooldown = CombatTiming.scale_time(randf_range(0.45, 0.75))
		return
	if randf() < 0.4:
		_virtual_jump = true
	if distance > attack_range * 0.8:
		_set_move_toward_target(target_left)


func _decide_simple_dash(distance: float, target_left: bool) -> void:
	if not _fighter.is_on_floor() or _attack_cooldown > 0.0:
		return
	if distance < attack_range and randf() < 0.45:
		_request_forward_dash(target_left)
		_attack_cooldown = CombatTiming.scale_time(0.4)
	elif distance > attack_range * 1.35 and randf() < 0.35:
		_request_forward_dash(target_left)
		_attack_cooldown = CombatTiming.scale_time(0.45)
	elif distance < attack_range * 0.8 and randf() < 0.3:
		_request_back_dash(target_left)
		_attack_cooldown = CombatTiming.scale_time(0.55)


func _decide_simple_attack(distance: float, target_left: bool) -> void:
	var target := _fighter.opponent
	if not _fighter.is_on_floor():
		if distance < attack_range and _attack_cooldown <= 0.0 and randf() < 0.35:
			_queue_attack("air_neutral")
			_attack_cooldown = CombatTiming.scale_time(0.55)
		return
	if distance > attack_range * 0.95:
		_set_move_toward_target(target_left)
		if distance > attack_range * 1.25 and randf() < 0.25:
			_request_forward_dash(target_left)
		return
	if _attack_cooldown > 0.0:
		return
	_pick_offensive_attack(distance, target)
	_attack_cooldown = CombatTiming.scale_time(randf_range(0.38, 0.72))


func _decide_simple_grab(distance: float, target_left: bool) -> void:
	if not _fighter.is_on_floor():
		return
	if distance > close_range + 16.0:
		_set_move_toward_target(target_left)
		if distance > attack_range and randf() < 0.3:
			_request_forward_dash(target_left)
		return
	if _attack_cooldown > 0.0:
		return
	_virtual_throw = true
	_attack_cooldown = CombatTiming.scale_time(randf_range(0.55, 0.9))


func _decide_simple_projectile(distance: float, target_left: bool) -> void:
	if _attack_cooldown > 0.0:
		return
	if _try_answer_crouch_block(distance):
		return
	if distance < zoner_panic_range and randf() < 0.35:
		_request_back_dash(target_left)
		_attack_cooldown = CombatTiming.scale_time(0.55)
		return
	if distance > attack_range:
		_set_move_away_from_target(target_left)
	if randf() < 0.18 and _fighter.is_on_floor():
		_virtual_jump = true
	_queue_projectile(randf_range(0.3, 0.75), randf() < 0.35)
	_attack_cooldown = CombatTiming.scale_time(randf_range(0.65, 1.05))


func _decide_zoner_behavior(distance: float, target_left: bool) -> void:
	_apply_zoner_movement(distance, target_left)
	if _attack_cooldown > 0.0:
		return
	if _try_answer_crouch_block(distance):
		return
	if distance < zoner_panic_range:
		if _fighter.is_on_floor() and randf() < 0.5:
			_request_back_dash(target_left)
			_attack_cooldown = CombatTiming.scale_time(0.45)
		elif randf() < 0.35:
			_virtual_guard = true
		return
	if distance >= zoner_ideal_min_range * 0.7:
		_queue_zoner_shot()
	elif distance > close_range and randf() < 0.65:
		_queue_zoner_shot()


func _queue_zoner_shot() -> void:
	_queue_projectile(_random_zoner_charge(), randf() < 0.35)
	_attack_cooldown = CombatTiming.scale_time(randf_range(0.7, 1.2))


func _decide_rushdown_behavior(distance: float, target_left: bool) -> void:
	var target := _fighter.opponent
	_move_toward_target(distance, target_left)
	if _attack_cooldown > 0.0 or not _fighter.is_on_floor():
		return
	if _try_answer_crouch_block(distance):
		return
	if distance <= close_range + 8.0 and randf() < 0.45:
		_virtual_throw = true
		_attack_cooldown = CombatTiming.scale_time(0.65)
	elif distance < attack_range:
		if randf() < 0.45:
			_queue_attack("forward")
		else:
			_pick_offensive_attack(distance, target)
		_attack_cooldown = CombatTiming.scale_time(0.42)
	elif distance < attack_range * 1.5 and randf() < 0.45:
		_request_forward_dash(target_left)
		_attack_cooldown = CombatTiming.scale_time(0.35)


func _decide_counter_behavior(distance: float, target_left: bool, target: Fighter) -> void:
	if distance < close_range + 12.0:
		if target.state_machine.is_attack_in_landing_lag() or target.state_machine.is_attack_active():
			if _attack_cooldown <= 0.0 and _fighter.is_on_floor():
				if randf() < 0.55:
					_virtual_throw = true
				else:
					_queue_attack("forward")
				_attack_cooldown = CombatTiming.scale_time(0.75)
		return
	if distance < attack_range and randf() < 0.25 and _fighter.is_on_floor():
		_request_back_dash(target_left)
		_attack_cooldown = CombatTiming.scale_time(0.5)


func _decide_shoto_behavior(distance: float, target_left: bool, target: Fighter) -> void:
	_apply_shoto_spacing(distance, target_left)
	if _attack_cooldown > 0.0 or not _fighter.is_on_floor():
		return
	if _try_answer_crouch_block(distance):
		return
	if distance < close_range and target.state_machine.is_blocking() and randf() < 0.3:
		_virtual_throw = true
		_attack_cooldown = CombatTiming.scale_time(0.7)
	elif distance > zoner_ideal_min_range and randf() < 0.4:
		_queue_projectile(randf_range(0.25, 0.75), randf() < 0.25)
		_attack_cooldown = CombatTiming.scale_time(0.85)
	elif distance < attack_range:
		if not target.is_on_floor() and randf() < 0.4:
			_queue_attack("anti_air")
		elif randf() < 0.45:
			_queue_attack("neutral")
		else:
			_queue_attack("forward")
		_attack_cooldown = CombatTiming.scale_time(0.5)
	elif distance < attack_range * 1.35 and randf() < 0.2:
		_request_forward_dash(target_left)
		_attack_cooldown = CombatTiming.scale_time(0.45)


func _decide_grappler_behavior(distance: float, target_left: bool) -> void:
	var target := _fighter.opponent
	_move_toward_target(distance, target_left)
	if _attack_cooldown > 0.0 or not _fighter.is_on_floor():
		return
	if _try_answer_crouch_block(distance):
		return
	if distance < attack_range and distance > close_range and randf() < 0.5:
		_request_forward_dash(target_left)
		_attack_cooldown = CombatTiming.scale_time(0.35)
	elif distance < close_range + 24.0:
		if randf() < 0.7:
			_virtual_throw = true
		else:
			_queue_attack("forward")
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
		if not _request_back_dash(target_left):
			_set_move_away_from_target(target_left)


func _apply_zoner_movement(distance: float, target_left: bool) -> void:
	if distance < zoner_ideal_min_range:
		_set_move_away_from_target(target_left)
	elif distance > zoner_ideal_max_range:
		if randf() < 0.45:
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


func _dash_toward_dir(target_left: bool) -> int:
	return -1 if target_left else 1


func _dash_away_dir(target_left: bool) -> int:
	return 1 if target_left else -1


func _request_forward_dash(target_left: bool) -> void:
	_fighter.request_dash(_dash_toward_dir(target_left))


func _request_back_dash(target_left: bool) -> bool:
	if not _has_mana(_fighter.stats.back_dash_mana_cost):
		return false
	_fighter.request_dash(_dash_away_dir(target_left))
	return true


func _has_mana(cost: int) -> bool:
	return _fighter.can_spend_mana(cost)


func _queue_attack(attack_name: String) -> void:
	_pending_attack_name = attack_name


func _queue_projectile(charge: float, low_angle: bool) -> void:
	_virtual_projectile_charge = charge
	_virtual_projectile_low = low_angle


func _try_answer_crouch_block(distance: float) -> bool:
	if _fighter.opponent == null:
		return false
	if (
		_fighter.opponent.state_machine.current_state
		!= FighterStateMachine.State.CROUCH_BLOCK
	):
		return false
	if _attack_cooldown > 0.0:
		return false
	if distance <= attack_range * 1.2 and _fighter.is_on_floor():
		if randf() < 0.55:
			_queue_attack("back_overhead")
		else:
			_virtual_jump = true
			_pending_attack_name = "air_overhead"
		_attack_cooldown = CombatTiming.scale_time(randf_range(0.5, 0.85))
		return true
	if _fighter.is_on_floor() and distance <= attack_range * 1.7 and randf() < 0.5:
		_virtual_jump = true
		_pending_attack_name = "air_overhead"
		_attack_cooldown = CombatTiming.scale_time(randf_range(0.55, 0.95))
		return true
	return false


func _pick_offensive_attack(distance: float, target: Fighter) -> void:
	if _try_answer_crouch_block(distance):
		return
	if not target.is_on_floor() and distance < attack_range * 1.1 and randf() < 0.5:
		_queue_attack("anti_air")
		return
	_pick_close_range_attack()


func _pick_close_range_attack() -> void:
	var roll := randi() % 5
	match roll:
		0, 1:
			_queue_attack("neutral")
		2:
			_queue_attack("forward")
		3:
			_queue_attack("down")
		_:
			_queue_attack("forward")


func _pick_random_attack() -> void:
	_pick_close_range_attack()
