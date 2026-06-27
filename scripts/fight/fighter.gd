extends CharacterBody2D
class_name Fighter

signal died(fighter: Fighter)
signal respawned(fighter: Fighter)
signal state_changed(fighter: Fighter, state_name: String)

@export var stats: FighterStats
@export var body_color: Color = Color(0.2, 0.45, 0.95)
@export var block_color: Color = Color(0.55, 0.62, 0.78)
@export var guard_color: Color = Color(0.92, 0.96, 1.0, 0.95)
@export var grab_color: Color = Color(0.98, 0.72, 0.18, 0.95)
@export var iframe_color: Color = Color(0.15, 0.82, 1.0, 0.8)
@export var vframe_color: Color = Color(1.0, 0.05, 0.45, 0.85)
@export var is_player_controlled: bool = true

const STATE_MACHINE_SCRIPT := preload("res://scripts/fight/fighter_state_machine.gd")
const PROJECTILE_SCENE := preload("res://scenes/fight/projectile.tscn")

var facing: int = 1
var opponent: Fighter
var lives: int = 3
var air_dash_used: bool = false
var _last_move_tap_direction: int = 0
var _last_move_tap_time: float = -1.0

const DOUBLE_TAP_WINDOW := 0.28 * CombatTiming.FIGHT_TIMING_SCALE
const BODY_HALF_WIDTH := 16.0
const STANDING_HURTBOX_SIZE := Vector2(32.0, 56.0)
const STANDING_HURTBOX_OFFSET := Vector2(0.0, -28.0)
const CROUCH_HURTBOX_SIZE := Vector2(32.0, 30.0)
const CROUCH_HURTBOX_OFFSET := Vector2(0.0, -15.0)
const ROLL_HURTBOX_SIZE := Vector2(34.0, 22.0)
const ROLL_HURTBOX_OFFSET := Vector2(0.0, -11.0)
const BODY_HEIGHT := 56.0
const KNOCKDOWN_LAND_BOUNCE_DURATION := 0.22 * CombatTiming.FIGHT_TIMING_SCALE
const KNOCKDOWN_LAND_BOUNCE_HEIGHT := 12.0

var _virtual_throw_direction: int = 0
var _grab_hold_timer: float = 0.0

var _virtual_left: bool = false
var _virtual_right: bool = false
var _virtual_jump_pulse: bool = false
var _virtual_jump_short: bool = true
var _virtual_attack_name: String = ""
var _virtual_guard: bool = false
var _virtual_down: bool = false
var _virtual_throw: bool = false
var _virtual_projectile_charge: float = -1.0
var _virtual_projectile_low: bool = false
var _projectile_charging: bool = false
var _projectile_auto_release: bool = false
var _was_on_floor_last_frame: bool = false
var _ledge_crouch_carry: bool = false
var _airborne_crouch_frames: int = 0
var _ledge_regrab_lockout: float = 0.0
var _w_getup_press_time: float = -1.0
var _external_displacement_frames: int = 0
var _hitstop_frames: int = 0
var _hit_flash_timer: float = 0.0
var _air_forward_combo_step: int = 0
var _jump_hold_frames: int = 0
var _gamepad_up_was_held: bool = false

const W_GETUP_HOLD_THRESHOLD := 0.1 * CombatTiming.FIGHT_TIMING_SCALE
const EXTERNAL_DISPLACEMENT_FRAMES := 12
const JUGGLE_ADVANCE_KNOCKBACK_RATIO := 1.0
const DEFAULT_JUGGLE_KNOCKBACK_SCALE := 0.35
const HIT_FLASH_DURATION := 0.1 * CombatTiming.FIGHT_TIMING_SCALE
const FULL_HOP_HOLD_FRAMES := 4

var state_machine: FighterStateMachine
var fight_manager: FightManager

@onready var body_rect: ColorRect = $FacingPivot/BodyRect
@onready var guard_indicator: ColorRect = $FacingPivot/GuardIndicator
@onready var iframe_overlay: ColorRect = $FacingPivot/IFrameOverlay
@onready var vframe_overlay: ColorRect = $FacingPivot/VFrameOverlay
@onready var facing_pivot: Node2D = $FacingPivot
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hurtbox: FightHurtbox = $FacingPivot/Hurtbox
@onready var hitbox: FightHitbox = $FacingPivot/Hitbox
@onready var grabbox: FightGrabbox = $FacingPivot/Grabbox
@onready var hurtbox_shape: CollisionShape2D = $FacingPivot/Hurtbox/CollisionShape2D
@onready var hitbox_shape: CollisionShape2D = $FacingPivot/Hitbox/CollisionShape2D
@onready var hurtbox_debug: ColorRect = $FacingPivot/Hurtbox/HurtboxDebug
@onready var hitbox_debug: ColorRect = $FacingPivot/Hitbox/HitboxDebug
@onready var grabbox_debug: ColorRect = $FacingPivot/Grabbox/GrabboxDebug
@onready var ai_controller: AiController = $AiController

var stagger_meter_label: Label

var _attacks: Dictionary = {}
var _dash_attack: AttackData
var _wakeup_attack: AttackData
var _grab: GrabData
var _debug_enabled: bool = false
var _input_buffer: FightInputBuffer


func _ready() -> void:
	if stats == null:
		stats = preload("res://scripts/resources/knight_fighter_stats.tres")
	lives = stats.max_lives

	state_machine = STATE_MACHINE_SCRIPT.new()
	state_machine.name = "StateMachine"
	add_child(state_machine)
	state_machine.setup(self)

	hurtbox.setup(self)
	hitbox.setup(self)
	hitbox.hit_landed.connect(_on_hit_landed)
	grabbox.setup(self)
	grabbox.grab_landed.connect(_on_grab_landed)

	_load_attacks()
	_instance_visual_rig()
	_input_buffer = FightInputBuffer.new()
	_split_shared_collision_shapes()
	_setup_stagger_meter_label()
	_update_hurtbox_profile()
	_update_visuals()
	facing_pivot.scale.x = float(facing)

	if not is_player_controlled:
		ai_controller.enabled = true
	else:
		ai_controller.enabled = false


func _setup_stagger_meter_label() -> void:
	stagger_meter_label = Label.new()
	stagger_meter_label.name = "StaggerMeterLabel"
	stagger_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stagger_meter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stagger_meter_label.position = Vector2(-24.0, -76.0)
	stagger_meter_label.size = Vector2(48.0, 18.0)
	stagger_meter_label.add_theme_font_size_override("font_size", 14)
	stagger_meter_label.add_theme_color_override("font_color", Color.WHITE)
	stagger_meter_label.add_theme_color_override("font_outline_color", Color.BLACK)
	stagger_meter_label.add_theme_constant_override("outline_size", 4)
	stagger_meter_label.visible = false
	facing_pivot.add_child(stagger_meter_label)


func _update_stagger_meter_display() -> void:
	if stagger_meter_label == null:
		return
	var should_show := state_machine.stagger_meter > 0 and (
		state_machine.current_state == FighterStateMachine.State.STAGGER
		or not is_on_floor()
	)
	stagger_meter_label.visible = should_show
	if should_show:
		stagger_meter_label.text = str(state_machine.stagger_meter)

# Shared fallbacks. A character's FighterStats can override any of these; when a
# stats field is left empty we drop back to these so existing characters keep
# working unchanged.
const DEFAULT_ATTACKS := {
	"neutral": preload("res://scripts/resources/attacks/jab.tres"),
	"forward": preload("res://scripts/resources/attacks/forward_strike.tres"),
	"down": preload("res://scripts/resources/attacks/down_strike.tres"),
	"anti_air": preload("res://scripts/resources/attacks/anti_air.tres"),
	"back_overhead": preload("res://scripts/resources/attacks/back_overhead.tres"),
	"back_retreat": preload("res://scripts/resources/attacks/back_retreat.tres"),
	"air_neutral": preload("res://scripts/resources/attacks/air_neutral.tres"),
	"air_forward": preload("res://scripts/resources/attacks/air_forward.tres"),
	"air_forward_2": preload("res://scripts/resources/attacks/air_forward_2.tres"),
	"air_forward_3": preload("res://scripts/resources/attacks/air_forward_3.tres"),
	"air_overhead": preload("res://scripts/resources/attacks/air_overhead.tres"),
	"air_up": preload("res://scripts/resources/attacks/air_up.tres"),
}
const DEFAULT_DASH_ATTACK := preload("res://scripts/resources/attacks/dash_attack.tres")
const DEFAULT_WAKEUP_ATTACK := preload("res://scripts/resources/attacks/wakeup_attack.tres")
const DEFAULT_GRAB := preload("res://scripts/resources/grabs/default_throw.tres")


# Builds this fighter's move set from its stats Resource, falling back to the
# shared defaults for any field the character data leaves unset.
func _load_attacks() -> void:
	if stats != null and not stats.attacks.is_empty():
		_attacks = stats.attacks.duplicate()
	else:
		_attacks = DEFAULT_ATTACKS.duplicate()
	_dash_attack = stats.dash_attack if stats != null and stats.dash_attack != null else DEFAULT_DASH_ATTACK
	_wakeup_attack = stats.wakeup_attack if stats != null and stats.wakeup_attack != null else DEFAULT_WAKEUP_ATTACK
	_grab = stats.grab_data if stats != null and stats.grab_data != null else DEFAULT_GRAB


# Instances the character's visual rig (stats.visual_scene) under FacingPivot so
# it flips with the fighter and is driven by its CharacterAnimator. Characters
# without a rig keep the placeholder BodyRect as a fallback.
func _instance_visual_rig() -> void:
	if stats == null or stats.visual_scene == null:
		body_rect.visible = true
		return
	facing_pivot.add_child(stats.visual_scene.instantiate())
	body_rect.visible = false


func get_dash_attack() -> AttackData:
	return _dash_attack


func _physics_process(delta: float) -> void:
	if fight_manager != null and fight_manager.match_finished:
		if state_machine.current_state != FighterStateMachine.State.DEAD:
			velocity = Vector2.ZERO
			move_and_slide()
		return

	if ai_controller.enabled:
		ai_controller.update_input(delta)

	if is_player_controlled:
		_input_buffer.age_buffers()
		_input_buffer.age_queue()
		_input_buffer.capture_player_input()
		if state_machine.can_buffer_inputs():
			_input_buffer.capture_action_intents(self)

	if opponent != null:
		_update_facing()

	if state_machine.current_state == FighterStateMachine.State.DEAD:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _hitstop_frames > 0:
		_hitstop_frames -= 1
		_update_visuals()
		return

	state_machine.tick(delta)
	if _ledge_regrab_lockout > 0.0:
		_ledge_regrab_lockout = maxf(0.0, _ledge_regrab_lockout - delta)
	_update_ledge_climb_animation()
	_apply_gravity(delta)
	_poll_double_tap_dash()
	_apply_movement(delta)
	_handle_projectile_input(delta)
	_poll_dash_attack_input()
	_update_jump_hold_tracking()
	_handle_actions()
	_sync_grabbed_position()
	move_and_slide()
	_clamp_ground_position_to_stage()
	if state_machine.is_on_ledge():
		snap_to_ledge(state_machine.ledge_side)
	if opponent != null and get_instance_id() < opponent.get_instance_id():
		_resolve_body_collision(opponent, delta)
	_update_wakeup_roll_animation()
	_check_wakeup_roll_ledge_contact()
	if state_machine.is_on_ledge():
		snap_to_ledge(state_machine.ledge_side)
	state_machine.update_knockdown_landing()
	state_machine.update_stun_landing()
	state_machine.update_attack_landing(_was_on_floor_last_frame, is_on_floor())
	_check_respawn_landing()
	_update_ledge_crouch_tracking()
	_check_ledge_grab_attempt()
	_check_stage_bounds()
	_update_ground_state()
	_update_visuals()
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
	if _external_displacement_frames > 0:
		_external_displacement_frames -= 1
	if is_on_floor():
		_clear_air_forward_combo()
	if is_player_controlled:
		_gamepad_up_was_held = GamepadInput.is_up_pressed()


func _clear_air_forward_combo() -> void:
	_air_forward_combo_step = 0


func _get_air_forward_chain_attack() -> String:
	match _air_forward_combo_step:
		1:
			return "air_forward_2"
		2:
			return "air_forward_3"
		_:
			return "air_forward"


func _register_air_forward_combo_hit(attack_data: AttackData, victim: Fighter) -> void:
	if not attack_data.id.begins_with("air_forward"):
		return
	if (
		victim == null
		or victim.is_on_floor()
		or victim.state_machine.is_knockdown_falling()
		or victim.state_machine.current_state == FighterStateMachine.State.KNOCKDOWN
	):
		_clear_air_forward_combo()
		return
	if victim.state_machine.current_state != FighterStateMachine.State.STAGGER:
		_clear_air_forward_combo()
		return
	match attack_data.id:
		"air_forward":
			_air_forward_combo_step = 1
		"air_forward_2":
			_air_forward_combo_step = 2
		"air_forward_3":
			_clear_air_forward_combo()


func _uses_juggle_gravity() -> bool:
	if is_on_floor() and velocity.y >= 0.0:
		return false
	if state_machine.current_state == FighterStateMachine.State.STAGGER:
		return true
	var attack := state_machine.current_attack as AttackData
	if state_machine.current_state == FighterStateMachine.State.ATTACK and attack != null:
		if attack.is_juggle_attack:
			return true
	return _is_juggle_pursuing()


func _is_juggle_pursuing() -> bool:
	if opponent == null or is_on_floor():
		return false
	if opponent.is_on_floor():
		return false
	return opponent.state_machine.current_state == FighterStateMachine.State.STAGGER


func _get_jump_velocity() -> float:
	if _wants_super_jump() and Input.is_action_pressed("jump"):
		return stats.super_jump_velocity
	if is_player_controlled:
		if Input.is_action_pressed("jump"):
			return stats.jump_velocity
		return stats.short_hop_velocity
	if _virtual_jump_short:
		return stats.short_hop_velocity
	return stats.jump_velocity


func _update_jump_hold_tracking() -> void:
	if not is_player_controlled or not is_on_floor():
		return
	if not _was_on_floor_last_frame:
		_jump_hold_frames = 0
	if Input.is_action_pressed("jump"):
		_jump_hold_frames += 1
	else:
		_jump_hold_frames = 0


func _can_takeoff_buffered_jump() -> bool:
	if not is_on_floor():
		return false
	if _wants_super_jump():
		return Input.is_action_pressed("jump")
	if not Input.is_action_pressed("jump"):
		return true
	return _jump_hold_frames >= FULL_HOP_HOLD_FRAMES


func _wants_super_jump() -> bool:
	if _is_crouch_intent_held():
		return true
	return _input_buffer.is_recent("move_down")


func mark_external_displacement(frames: int = EXTERNAL_DISPLACEMENT_FRAMES) -> void:
	_external_displacement_frames = maxi(_external_displacement_frames, frames)


func apply_hitstop(frames: int) -> void:
	if frames <= 0:
		return
	_hitstop_frames = maxi(_hitstop_frames, frames)


func is_in_hitstop() -> bool:
	return _hitstop_frames > 0


func pulse_hit_flash() -> void:
	_hit_flash_timer = HIT_FLASH_DURATION


func _uses_external_displacement() -> bool:
	return _external_displacement_frames > 0


func _is_grounded_for_stance() -> bool:
	return is_on_floor() or state_machine.is_crouching()


func should_preserve_crouch_air_state() -> bool:
	return _ledge_crouch_carry and (state_machine.is_crouching() or _is_crouch_intent_held())


func set_virtual_input(
	left: bool,
	right: bool,
	jump: bool,
	guard: bool = false,
	crouch: bool = false,
	attack_name: String = "",
	throw_attempt: bool = false,
	throw_direction: int = 0,
	projectile_charge: float = -1.0,
	projectile_low: bool = false,
	short_hop: bool = true
) -> void:
	_virtual_left = left
	_virtual_right = right
	if jump:
		_virtual_jump_pulse = true
		_virtual_jump_short = short_hop
	_virtual_guard = guard
	_virtual_down = crouch
	_virtual_throw = throw_attempt
	_virtual_throw_direction = throw_direction
	if attack_name != "":
		_virtual_attack_name = attack_name
	if projectile_charge >= 0.0:
		_virtual_projectile_charge = projectile_charge
	if projectile_low:
		_virtual_projectile_low = true


func clear_virtual_input() -> void:
	set_virtual_input(false, false, false, false, false, "", false, 0, -1.0, false)


func is_crouch_held() -> bool:
	if state_machine.is_knocked_down() or state_machine.is_on_ledge():
		return false
	if not _is_grounded_for_stance():
		return false
	if not state_machine.can_hold_guard() and not state_machine.is_crouching():
		return false
	return _is_crouch_intent_held()


func _is_crouch_intent_held() -> bool:
	if is_player_controlled:
		if Input.is_action_pressed("move_down") or _virtual_down:
			return true
		return GamepadInput.is_down_pressed()
	return _virtual_down


func is_guard_held() -> bool:
	if not _is_grounded_for_stance():
		return false
	if not state_machine.can_hold_guard() and not state_machine.is_blocking():
		return false
	if is_player_controlled:
		return Input.is_action_pressed("guard") or _virtual_guard
	return _virtual_guard


func resolve_standing_state() -> void:
	if state_machine.is_on_ledge():
		return
	if not is_on_floor():
		if should_preserve_crouch_air_state():
			state_machine.change_state(FighterStateMachine.State.CROUCH)
		else:
			state_machine.change_state(FighterStateMachine.State.IDLE)
		return
	if is_crouch_held():
		if is_guard_held():
			state_machine.change_state(FighterStateMachine.State.CROUCH_BLOCK)
		else:
			state_machine.change_state(FighterStateMachine.State.CROUCH)
	elif is_guard_held():
		state_machine.change_state(FighterStateMachine.State.BLOCK)
	elif _get_move_direction() != 0:
		state_machine.change_state(FighterStateMachine.State.MOVE)
	else:
		state_machine.change_state(FighterStateMachine.State.IDLE)
	_ensure_not_orphaned_action_state()


func _ensure_not_orphaned_action_state() -> void:
	if state_machine.current_attack != null:
		return
	match state_machine.current_state:
		FighterStateMachine.State.ATTACK, FighterStateMachine.State.GRAB:
			state_machine.change_state(FighterStateMachine.State.IDLE)


func _apply_gravity(delta: float) -> void:
	if state_machine.is_on_ledge():
		return
	if state_machine.is_knockdown_falling():
		var kd_gravity_scale := 1.0 if state_machine.knockdown_from_throw else stats.knockdown_gravity_scale
		velocity.y += stats.gravity * kd_gravity_scale * delta
		return
	var gravity_scale := 1.0
	if _uses_juggle_gravity():
		gravity_scale = stats.juggle_gravity_scale
	if is_on_floor():
		air_dash_used = false
		if velocity.y > 0.0:
			velocity.y = 0.0
		elif velocity.y < 0.0:
			velocity.y += stats.gravity * gravity_scale * delta
	else:
		velocity.y += stats.gravity * gravity_scale * delta
		_apply_fast_fall(delta, gravity_scale)


func _has_passed_jump_apex() -> bool:
	return not is_on_floor() and velocity.y >= 0.0


func _can_use_fast_fall() -> bool:
	if not state_machine.is_active_in_match() or is_on_floor():
		return false
	if not _has_passed_jump_apex():
		return false
	if _uses_juggle_gravity():
		return false
	if state_machine.is_knockdown_falling() or state_machine.is_in_hitstun():
		return false
	if state_machine.is_grabbed() or state_machine.is_on_ledge():
		return false
	return state_machine.current_state in [
		FighterStateMachine.State.IDLE,
		FighterStateMachine.State.MOVE,
		FighterStateMachine.State.ATTACK,
		FighterStateMachine.State.BLOCK,
		FighterStateMachine.State.DASH,
		FighterStateMachine.State.PROJECTILE_CHARGE,
	]


func _wants_fast_fall() -> bool:
	return _is_down_pressed()


func _apply_fast_fall(delta: float, gravity_scale: float) -> void:
	if not _can_use_fast_fall() or not _wants_fast_fall():
		return
	var fast_scale: float = stats.fast_fall_gravity_scale
	if fast_scale > 1.0:
		velocity.y += stats.gravity * gravity_scale * (fast_scale - 1.0) * delta
	if stats.fast_fall_max_velocity > 0.0:
		velocity.y = minf(velocity.y, stats.fast_fall_max_velocity)


func _apply_movement(delta: float) -> void:
	var sm := state_machine
	match sm.current_state:
		FighterStateMachine.State.MOVE:
			if is_on_floor():
				velocity.x = _get_move_direction() * stats.move_speed
			else:
				_apply_air_control(delta)
		FighterStateMachine.State.DASH:
			if not state_machine.dash_in_recovery:
				velocity.x = sm.dash_direction * stats.dash_speed
			elif is_on_floor():
				velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 4.0 * delta)
			if is_on_floor():
				velocity.y = 0.0
		FighterStateMachine.State.ATTACK, FighterStateMachine.State.BLOCK:
			var advance := _get_attack_advance()
			if advance != 0.0:
				velocity.x = facing * advance
			elif is_on_floor():
				var friction_scale := 3.0
				if _attack_has_lunge():
					friction_scale = 16.0
				elif absf(velocity.x) > 30.0:
					friction_scale = 1.5
				velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * friction_scale * delta)
		FighterStateMachine.State.CROUCH, FighterStateMachine.State.CROUCH_BLOCK:
			if is_on_floor():
				if velocity.y >= 0.0:
					velocity.y = 0.0
				if state_machine.current_attack != null:
					var crouch_advance := _get_attack_ground_advance()
					if crouch_advance > 0.0:
						velocity.x = facing * crouch_advance
					else:
						velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 3.0 * delta)
				elif sm.is_blocking():
					if absf(velocity.x) > 30.0:
						velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 1.5 * delta)
					else:
						velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 3.0 * delta)
				else:
					var move_dir := _get_move_direction()
					if move_dir != 0:
						velocity.x = move_dir * stats.move_speed * stats.crouch_move_scale
					else:
						velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 3.0 * delta)
		FighterStateMachine.State.LEDGE_RECOVERY:
			velocity = Vector2.ZERO
		FighterStateMachine.State.GRAB:
			if is_on_floor():
				velocity.y = 0.0
				if state_machine.grab_landed:
					velocity.x = 0.0
				elif not state_machine.grab_in_recovery:
					var grab_advance := _get_grab_advance_speed()
					if grab_advance > 0.0:
						velocity.x = facing * grab_advance
					else:
						velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 3.0 * delta)
				else:
					velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 4.0 * delta)
		FighterStateMachine.State.GRABBED:
			velocity = Vector2.ZERO
		FighterStateMachine.State.STAGGER:
			var stagger_t := state_machine.get_stagger_hitstun_progress()
			velocity.x = state_machine.hitstun_velocity_x * (1.0 - stagger_t)
			if is_on_floor() and velocity.y >= 0.0:
				velocity.y = 0.0
		FighterStateMachine.State.STUN:
			if is_on_floor():
				velocity.y = 0.0
				velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 2.5 * delta)
			else:
				velocity.x = state_machine.hitstun_velocity_x
		FighterStateMachine.State.KNOCKDOWN:
			if state_machine.is_knockdown_falling():
				velocity.x = state_machine.knockdown_velocity.x
			elif sm.knockdown_landed and is_on_floor():
				velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 2.5 * delta)
				velocity.y = 0.0
		FighterStateMachine.State.GETUP_INVINCIBLE:
			if state_machine.getup_from_ledge:
				velocity = Vector2.ZERO
			elif is_on_floor():
				velocity.y = 0.0
				velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 4.0 * delta)
		FighterStateMachine.State.SLOW_GETUP:
			if state_machine.getup_from_ledge:
				velocity = Vector2.ZERO
			elif is_on_floor():
				velocity.y = 0.0
				velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 2.5 * delta)
		FighterStateMachine.State.WAKEUP_ROLL:
			velocity = Vector2.ZERO
		FighterStateMachine.State.PROJECTILE_CHARGE:
			velocity.x = 0.0
			if is_on_floor() or state_machine.projectile_startup_remaining > 0.0:
				velocity.y = 0.0
		FighterStateMachine.State.RESPAWN:
			if state_machine.is_respawn_falling():
				velocity.x = 0.0
			elif is_on_floor():
				var move_dir := _get_move_direction()
				if move_dir != 0:
					velocity.x = move_dir * stats.move_speed
				else:
					velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 4.0 * delta)
				velocity.y = 0.0
		FighterStateMachine.State.IDLE:
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 2.0 * delta)
			else:
				_apply_air_control(delta)
		_:
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0.0, stats.move_speed * 2.0 * delta)
	_enforce_stage_walk_edges()


func _apply_air_control(delta: float) -> void:
	if not state_machine.is_active_in_match():
		return
	var move_dir := _get_move_direction()
	if move_dir != 0:
		velocity.x = move_dir * stats.air_move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, stats.air_move_speed * 3.0 * delta)


func _get_stage_walk_min_x() -> float:
	if fight_manager == null:
		return -1.0e6
	return fight_manager.platform_left + BODY_HALF_WIDTH


func _get_stage_walk_max_x() -> float:
	if fight_manager == null:
		return 1.0e6
	return fight_manager.platform_right - BODY_HALF_WIDTH


func _should_enforce_stage_walk_edges() -> bool:
	if fight_manager == null or not is_on_floor():
		return false
	if state_machine.is_on_ledge():
		return false
	if state_machine.is_in_hitstun():
		return false
	if state_machine.is_knocked_down():
		return false
	if state_machine.current_state == FighterStateMachine.State.WAKEUP_ROLL:
		return false
	if state_machine.is_blocking():
		return false
	if _uses_external_displacement():
		return false
	return _uses_protected_stage_movement()


func _uses_protected_stage_movement() -> bool:
	match state_machine.current_state:
		FighterStateMachine.State.DASH:
			return true
		FighterStateMachine.State.ATTACK:
			return _get_attack_advance() != 0.0
		FighterStateMachine.State.CROUCH:
			return (
				state_machine.current_attack != null
				and _get_attack_ground_advance() > 0.0
			)
		FighterStateMachine.State.GRAB:
			return (
				not state_machine.grab_landed
				and not state_machine.grab_in_recovery
				and _get_grab_advance_speed() > 0.0
			)
	return false


func _enforce_stage_walk_edges() -> void:
	if not _should_enforce_stage_walk_edges():
		return
	var min_x := _get_stage_walk_min_x()
	var max_x := _get_stage_walk_max_x()
	if global_position.x <= min_x and velocity.x < 0.0:
		velocity.x = 0.0
	if global_position.x >= max_x and velocity.x > 0.0:
		velocity.x = 0.0


func _clamp_ground_position_to_stage() -> void:
	if not _should_enforce_stage_walk_edges():
		return
	global_position.x = clampf(global_position.x, _get_stage_walk_min_x(), _get_stage_walk_max_x())


func _poll_dash_attack_input() -> void:
	if state_machine.current_state != FighterStateMachine.State.DASH:
		return
	if state_machine.dash_in_recovery:
		return
	if not is_player_controlled:
		if _virtual_attack_name != "":
			state_machine.buffer_dash_attack()
			_virtual_attack_name = ""
		return
	if Input.is_action_just_pressed("attack") or _input_buffer.is_recent("attack"):
		state_machine.buffer_dash_attack()
		_input_buffer.clear_action("attack")
		_input_buffer.remove_intent(FightInputBuffer.Intent.ATTACK)


func _handle_actions() -> void:
	if state_machine.is_holding_grab():
		_handle_grab_hold_input()
		return

	if state_machine.current_state == FighterStateMachine.State.KNOCKDOWN:
		if state_machine.knockdown_landed:
			_try_begin_prone_wakeup(false)
		return

	if state_machine.current_state in [
		FighterStateMachine.State.GETUP_INVINCIBLE,
		FighterStateMachine.State.SLOW_GETUP,
		FighterStateMachine.State.WAKEUP_ROLL,
	]:
		return

	if state_machine.is_on_ledge():
		_try_begin_prone_wakeup(true)
		return

	_try_buffer_combo_input()

	if not state_machine.can_accept_input():
		return

	if _try_execute_action_queue():
		return

	if _consume_virtual_projectile_fire():
		return


func build_input_snapshot() -> Dictionary:
	var move_dir := _get_move_direction()
	return {
		"facing": facing,
		"move_dir": move_dir,
		"up": _input_buffer.is_up_held(),
		"down": _is_crouch_intent_held(),
		"on_floor": is_on_floor(),
	}


func resolve_buffered_attack_name(snap: Dictionary) -> String:
	if not snap.get("on_floor", is_on_floor()):
		if snap.get("down", false):
			return "air_overhead"
		if snap.get("up", false):
			return "air_up"
		var air_move_dir := int(snap.get("move_dir", 0))
		var air_snap_facing := int(snap.get("facing", facing))
		if air_move_dir != 0 and air_move_dir == -air_snap_facing:
			return "back_retreat"
		if air_move_dir == air_snap_facing:
			return _get_air_forward_chain_attack()
		return "air_neutral"
	if not is_on_floor():
		return ""
	var attack_name := str(snap.get("attack_name", ""))
	if attack_name != "":
		return attack_name
	var move_dir := int(snap.get("move_dir", 0))
	var snap_facing := int(snap.get("facing", facing))
	if snap.get("down", false):
		return "down"
	if move_dir != 0 and move_dir == -snap_facing:
		return "back_overhead"
	if move_dir == snap_facing:
		return "forward"
	return "neutral"


func try_execute_action_queue() -> bool:
	return _try_execute_action_queue()


func get_input_queue_display_text() -> String:
	return _input_buffer.get_queue_display_text()


func _try_execute_action_queue() -> bool:
	if not is_player_controlled:
		return false
	var attempts := 0
	var max_attempts := _input_buffer.queue_length()
	while _input_buffer.has_queued_intents() and attempts < max_attempts:
		attempts += 1
		var intent := _input_buffer.peek_intent()
		if _execute_buffered_intent(intent):
			_input_buffer.pop_intent()
			return true
		if _should_retry_buffered_intent(intent):
			return false
		_input_buffer.pop_intent()
	return false


func _should_retry_buffered_intent(intent: FightInputBuffer.Intent) -> bool:
	match intent:
		FightInputBuffer.Intent.PROJECTILE:
			if stats.projectile_config == null:
				return false
			return (
				not state_machine.can_use_projectile()
				or _is_attack_intent_held()
				or state_machine.current_state == FighterStateMachine.State.PROJECTILE_CHARGE
			)
		FightInputBuffer.Intent.JUMP:
			return not is_on_floor() or not _can_takeoff_buffered_jump()
		FightInputBuffer.Intent.THROW, FightInputBuffer.Intent.GUARD, FightInputBuffer.Intent.CROUCH:
			return not is_on_floor()
		FightInputBuffer.Intent.ATTACK:
			if _input_buffer.is_guard_held() and _input_buffer.is_attack_held():
				return true
			return false
	return false


func _execute_buffered_intent(intent: FightInputBuffer.Intent) -> bool:
	var entry := _input_buffer.peek_entry()
	var data: Dictionary = entry.get("data", {})
	match intent:
		FightInputBuffer.Intent.ATTACK:
			if _input_buffer.is_guard_held() and _input_buffer.is_attack_held():
				return false
			var attack_name := str(data.get("attack_name", ""))
			if attack_name == "":
				attack_name = resolve_buffered_attack_name(data)
			if attack_name == "":
				return false
			if is_on_floor():
				velocity.y = minf(velocity.y, 0.0)
			_try_attack(attack_name)
			return true
		FightInputBuffer.Intent.THROW:
			if not is_on_floor():
				return false
			_try_throw()
			return true
		FightInputBuffer.Intent.JUMP:
			if not is_on_floor():
				return false
			if not _can_takeoff_buffered_jump():
				return false
			velocity.y = _get_jump_velocity()
			_jump_hold_frames = 0
			state_machine.change_state(FighterStateMachine.State.IDLE)
			return true
		FightInputBuffer.Intent.PROJECTILE:
			if stats.projectile_config == null:
				return false
			if not state_machine.can_use_projectile():
				return false
			if _is_attack_intent_held():
				return false
			var low_angle := bool(data.get("down", _is_down_pressed()))
			_projectile_auto_release = not Input.is_action_pressed("projectile")
			_clear_air_forward_combo()
			state_machine.begin_projectile_charge(low_angle)
			_projectile_charging = true
			return true
		FightInputBuffer.Intent.GUARD:
			if not is_on_floor() or not state_machine.can_hold_guard():
				return false
			state_machine.change_state(FighterStateMachine.State.BLOCK)
			return true
		FightInputBuffer.Intent.CROUCH:
			if not is_on_floor():
				return false
			state_machine.change_state(FighterStateMachine.State.CROUCH)
			return true
		FightInputBuffer.Intent.DASH:
			var dash_dir := int(data.get("dash_direction", 0))
			if dash_dir == 0:
				return false
			_try_dash(dash_dir)
			return true
	return false


func _handle_grab_hold_input() -> void:
	if not state_machine.is_holding_grab():
		_grab_hold_timer = 0.0
		return

	_grab_hold_timer += get_physics_process_delta_time()
	var throw_dir := _get_throw_direction_input()
	if throw_dir == 0 and not is_player_controlled and _grab_hold_timer >= CombatTiming.scale_time(0.12):
		throw_dir = _virtual_throw_direction
		if throw_dir == 0:
			throw_dir = 1 if randf() > 0.35 else -1
	if throw_dir != 0:
		state_machine.execute_throw_release(throw_dir)
		_grab_hold_timer = 0.0
		_virtual_throw_direction = 0


func _get_throw_direction_input() -> int:
	if _virtual_throw_direction != 0:
		return _virtual_throw_direction
	var move_dir := _get_move_direction()
	if move_dir == facing:
		return 1
	if move_dir == -facing:
		return -1
	return 0


func _sync_grabbed_position() -> void:
	if not state_machine.is_grabbed():
		return
	var thrower := state_machine.grabbed_by
	if thrower == null or not thrower.state_machine.is_holding_grab():
		state_machine.release_from_grab()
		return
	if thrower.state_machine.grab_victim != self:
		state_machine.release_from_grab()
		return
	var grab_data: GrabData = state_machine.current_grab
	var hold_offset := 24.0
	if grab_data != null:
		hold_offset = grab_data.grab_hold_offset
	global_position.x = thrower.global_position.x + thrower.facing * hold_offset
	global_position.y = thrower.global_position.y
	velocity = Vector2.ZERO
	facing = -thrower.facing
	facing_pivot.scale.x = float(facing)


func request_dash(direction: int) -> void:
	_try_dash(direction)


func _poll_double_tap_dash() -> void:
	if not is_player_controlled:
		return
	if not state_machine.can_accept_input():
		return
	if Input.is_action_just_pressed("move_left"):
		_register_move_tap(-1)
	elif Input.is_action_just_pressed("move_right"):
		_register_move_tap(1)


func _register_move_tap(direction: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _last_move_tap_direction == direction and (now - _last_move_tap_time) <= DOUBLE_TAP_WINDOW:
		if state_machine.can_accept_input():
			_try_dash(direction)
		elif state_machine.can_buffer_inputs():
			_input_buffer.enqueue_dash(direction)
		_last_move_tap_direction = 0
		_last_move_tap_time = -1.0
	else:
		_last_move_tap_direction = direction
		_last_move_tap_time = now


func _try_dash(direction: int) -> void:
	if state_machine.current_state == FighterStateMachine.State.DASH:
		return
	_clear_air_forward_combo()
	if not is_on_floor() and air_dash_used:
		return
	if not is_on_floor():
		air_dash_used = true
	state_machine.start_dash(direction)


func finish_dash() -> void:
	var dash_dir := state_machine.dash_direction
	if is_on_floor():
		velocity.x = 0.0
	else:
		velocity.x = dash_dir * stats.dash_speed * stats.dash_air_momentum_carry


func request_throw() -> void:
	_try_throw()


func _try_throw() -> void:
	if state_machine.current_state == FighterStateMachine.State.GRAB:
		return
	if not is_on_floor():
		return
	_clear_air_forward_combo()
	state_machine.start_grab(_grab)


func _try_buffer_combo_input() -> void:
	if not state_machine.can_buffer_combo():
		return
	if is_player_controlled:
		if not _input_buffer.attack_pressed_for_combo():
			return
		if not _is_neutral_attack_intent():
			return
	elif _virtual_attack_name != "" and _virtual_attack_name == "neutral":
		_virtual_attack_name = ""
	else:
		return
	state_machine.buffer_combo_follow_up()


func consume_combo_follow_up() -> AttackData:
	return state_machine.consume_combo_follow_up()


func _try_attack(attack_name: String) -> void:
	if not _attacks.has(attack_name):
		return
	var attack := _attacks[attack_name] as AttackData
	if attack != null and attack.is_retreat_jump:
		if is_on_floor():
			_begin_retreat_jump_attack(attack)
			return
		_clear_air_forward_combo()
		state_machine.start_attack(attack)
		return
	if attack_name.begins_with("air_"):
		if is_on_floor():
			return
		if attack_name == "air_forward":
			attack_name = _get_air_forward_chain_attack()
		elif _air_forward_combo_step > 0 and attack_name != _get_air_forward_chain_attack():
			_clear_air_forward_combo()
	elif not is_on_floor():
		return
	state_machine.start_attack(_attacks[attack_name])


func _begin_retreat_jump_attack(attack: AttackData) -> void:
	velocity.x = -facing * attack.retreat_hop_velocity.x
	velocity.y = attack.retreat_hop_velocity.y
	_clear_air_forward_combo()
	state_machine.start_attack(attack)


func _handle_projectile_input(delta: float) -> void:
	if state_machine.current_state == FighterStateMachine.State.PROJECTILE_CHARGE:
		state_machine.tick_projectile_charge(delta)
		if state_machine.projectile_startup_remaining > 0.0:
			return
		if _projectile_auto_release and not _is_projectile_pressed():
			_release_projectile_charge()
			return
		if _is_projectile_released() or state_machine.is_projectile_fully_charged():
			_release_projectile_charge()
		return

	if _projectile_charging:
		_projectile_charging = false

	if not state_machine.can_use_projectile():
		return

	if stats.projectile_config == null:
		return

	if _virtual_projectile_charge >= 0.0:
		return

	if _is_attack_intent_held():
		return

	if _is_projectile_pressed():
		_projectile_auto_release = Input.is_action_just_pressed("projectile")
		_clear_air_forward_combo()
		state_machine.begin_projectile_charge(_is_down_pressed())
		_projectile_charging = true


func _release_projectile_charge() -> void:
	var charge_ratio := state_machine.get_projectile_charge_ratio()
	state_machine.begin_projectile_release(charge_ratio)
	_projectile_charging = false
	_projectile_auto_release = false


func complete_projectile_startup() -> void:
	var low_angle := state_machine.is_projectile_low_angle()
	_fire_projectile(state_machine.projectile_pending_charge, low_angle)
	state_machine.finish_projectile_startup()


func _fire_projectile(charge_ratio: float, low_angle: bool = false) -> void:
	if stats.projectile_config == null:
		return
	var projectile := PROJECTILE_SCENE.instantiate() as FightProjectile
	get_parent().add_child(projectile)
	projectile.setup(self, charge_ratio, stats.projectile_config, low_angle)


func _consume_virtual_projectile_fire() -> bool:
	if _virtual_projectile_charge < 0.0:
		return false
	if not state_machine.can_use_projectile():
		_virtual_projectile_charge = -1.0
		return false
	var charge := clampf(_virtual_projectile_charge, 0.0, 1.0)
	_virtual_projectile_charge = -1.0
	state_machine.begin_projectile_charge(_virtual_projectile_low)
	state_machine.begin_projectile_release(charge)
	_virtual_projectile_low = false
	return true


func _is_projectile_pressed() -> bool:
	if not is_player_controlled:
		return false
	if Input.is_action_pressed("attack"):
		return false
	return Input.is_action_pressed("projectile")


func _is_projectile_released() -> bool:
	if not is_player_controlled:
		return false
	return Input.is_action_just_released("projectile")


func perform_fast_get_up() -> void:
	state_machine.begin_knockdown_wakeup(FighterStateMachine.WakeupOption.NEUTRAL)


func _snap_feet_to_ground(x: float = -1.0) -> void:
	if fight_manager == null:
		return
	if x < 0.0:
		x = global_position.x
	global_position.y = fight_manager.get_ground_y(x)


func debug_force_knockdown() -> void:
	if not is_player_controlled:
		return
	if not state_machine.is_active_in_match():
		return
	if state_machine.current_state in [
		FighterStateMachine.State.DEAD,
		FighterStateMachine.State.RESPAWN,
		FighterStateMachine.State.GRABBED,
	]:
		return

	set_hitbox_active(false)
	set_grabbox_active(false)
	state_machine.clear_oki_punish_window()
	state_machine.reset_stagger_meter()

	if fight_manager != null:
		_snap_feet_to_ground()

	_begin_knockdown_from_impulse(Vector2.ZERO)
	state_machine.knockdown_was_airborne = true
	state_machine.knockdown_landed = true
	state_machine.knockdown_landed_at = (
		state_machine.state_time
		- FighterStateMachine.KNOCKDOWN_GROUND_INVINCIBLE_DURATION
		- 0.05
	)
	velocity = Vector2.ZERO
	on_knockdown_landed()
	_update_visuals()


func perform_ledge_get_up() -> void:
	perform_ledge_wakeup(FighterStateMachine.WakeupOption.NEUTRAL)


func perform_ledge_wakeup(option: FighterStateMachine.WakeupOption) -> void:
	if not state_machine.begin_ledge_wakeup(option):
		return
	_reset_wakeup_w_press()
	var side := state_machine.ledge_side
	facing = -side if side != 0 else facing
	facing_pivot.scale.x = float(facing)
	_ledge_crouch_carry = false
	_airborne_crouch_frames = 0
	_virtual_jump_pulse = false
	_virtual_attack_name = ""
	_update_visuals()


func get_wakeup_attack() -> AttackData:
	return _wakeup_attack


func perform_wakeup_followup_attack() -> void:
	if fight_manager != null:
		_snap_feet_to_ground()
	velocity = Vector2.ZERO
	var attack_name := _resolve_attack_from_direction()
	if attack_name.begins_with("air_"):
		attack_name = "neutral"
	_try_attack(attack_name)


func perform_wakeup_followup_grab() -> void:
	if fight_manager != null:
		_snap_feet_to_ground()
	velocity = Vector2.ZERO
	state_machine.start_grab(_grab)


func _try_begin_prone_wakeup(from_ledge: bool) -> void:
	if from_ledge:
		if not state_machine.can_use_ledge_wakeup_options():
			return
	else:
		if not state_machine.can_use_knockdown_wakeup_options():
			return
		if state_machine.try_execute_buffered_prone_wakeup():
			_reset_wakeup_w_press()
			return
		if state_machine.has_buffered_prone_wakeup:
			return

	var buffering := not from_ledge and state_machine.is_knockdown_forced_ground()

	if _is_left_pressed() and not _is_right_pressed():
		_reset_wakeup_w_press()
		_queue_prone_wakeup(from_ledge, FighterStateMachine.WakeupOption.ROLL_LEFT, buffering)
		return
	if _is_right_pressed() and not _is_left_pressed():
		_reset_wakeup_w_press()
		_queue_prone_wakeup(from_ledge, FighterStateMachine.WakeupOption.ROLL_RIGHT, buffering)
		return
	if _should_begin_wakeup_grab():
		_virtual_attack_name = ""
		_reset_wakeup_w_press()
		_queue_prone_wakeup(from_ledge, FighterStateMachine.WakeupOption.GRAB, buffering)
		return
	if _just_pressed_attack_while_prone():
		_virtual_attack_name = ""
		_reset_wakeup_w_press()
		_queue_prone_wakeup(from_ledge, FighterStateMachine.WakeupOption.ATTACK, buffering)
		return
	if _just_pressed_slow_getup() and not _is_jump_getup_held():
		_reset_wakeup_w_press()
		_queue_prone_wakeup(from_ledge, FighterStateMachine.WakeupOption.SLOW, buffering)
		return
	if _just_pressed_guard_while_prone() and not _is_attack_intent_held():
		_reset_wakeup_w_press()
		_queue_prone_wakeup(from_ledge, FighterStateMachine.WakeupOption.BLOCK, buffering)
		return

	_poll_wakeup_w_getup(from_ledge, buffering)


func _queue_prone_wakeup(
	from_ledge: bool,
	option: FighterStateMachine.WakeupOption,
	buffering: bool
) -> void:
	if buffering:
		state_machine.buffer_prone_wakeup(option)
	else:
		_begin_prone_wakeup(from_ledge, option)


func _begin_prone_wakeup(from_ledge: bool, option: FighterStateMachine.WakeupOption) -> void:
	if from_ledge:
		perform_ledge_wakeup(option)
	else:
		state_machine.begin_knockdown_wakeup(option)


func _poll_wakeup_w_getup(from_ledge: bool, buffering: bool = false) -> void:
	if _just_pressed_get_up_neutral() or (_w_getup_press_time < 0.0 and _is_jump_getup_held()):
		_w_getup_press_time = Time.get_ticks_msec() / 1000.0

	if _w_getup_press_time < 0.0:
		return

	if _is_jump_getup_held():
		var jump_hold_time := Time.get_ticks_msec() / 1000.0 - _w_getup_press_time
		if jump_hold_time >= W_GETUP_HOLD_THRESHOLD:
			_queue_prone_wakeup(from_ledge, FighterStateMachine.WakeupOption.JUMP, buffering)
			_reset_wakeup_w_press()
		return

	var held := Time.get_ticks_msec() / 1000.0 - _w_getup_press_time
	if held < W_GETUP_HOLD_THRESHOLD:
		_queue_prone_wakeup(from_ledge, FighterStateMachine.WakeupOption.NEUTRAL, buffering)
	_reset_wakeup_w_press()


func _should_begin_wakeup_grab() -> bool:
	if not is_player_controlled:
		return _virtual_guard and _virtual_attack_name != ""
	if Input.is_action_just_pressed("attack") and Input.is_action_pressed("guard"):
		return true
	return Input.is_action_just_pressed("guard") and Input.is_action_pressed("attack")


func _is_wakeup_grab_intent() -> bool:
	return is_guard_held() and _is_attack_intent_held()


func _is_jump_getup_held() -> bool:
	if is_player_controlled:
		return Input.is_action_pressed("jump")
	return _virtual_jump_pulse


func _just_pressed_slow_getup() -> bool:
	if is_player_controlled:
		return Input.is_action_just_pressed("move_down")
	return _virtual_down


func _reset_wakeup_w_press() -> void:
	_w_getup_press_time = -1.0


func _is_attack_intent_held() -> bool:
	if _virtual_attack_name != "":
		return true
	if not is_player_controlled:
		return false
	return Input.is_action_pressed("attack")


func _just_pressed_attack_while_prone() -> bool:
	if _virtual_attack_name != "":
		return not is_guard_held()
	if not is_player_controlled:
		return false
	if not Input.is_action_just_pressed("attack"):
		return false
	return not Input.is_action_pressed("guard")


func _just_pressed_guard_while_prone() -> bool:
	if is_player_controlled:
		return Input.is_action_just_pressed("guard")
	return _virtual_guard


func set_grabbox_active(active: bool) -> void:
	if active and state_machine.current_grab != null:
		grabbox.activate(state_machine.current_grab)
		_update_grabbox_debug(state_machine.current_grab)
		grabbox_debug.visible = _debug_enabled
	else:
		grabbox.deactivate()
		grabbox_debug.visible = false


func set_hitbox_active(active: bool) -> void:
	if active and state_machine.current_attack != null:
		hitbox.activate(state_machine.current_attack)
		_update_hitbox_debug(state_machine.current_attack)
		hitbox_debug.visible = _debug_enabled
	else:
		hitbox.deactivate()
		hitbox_debug.visible = false


func _break_juggle_with(attacker: Fighter) -> void:
	if attacker != null:
		attacker.state_machine.clear_combo_buffer()


func receive_hit(attacker: Fighter, attack_data: AttackData) -> void:
	if not state_machine.is_active_in_match():
		return
	if state_machine.is_invincible():
		return
	if state_machine.is_knockdown_falling():
		return

	if state_machine.is_holding_grab():
		state_machine.release_held_grab()

	if state_machine.is_grabbing():
		set_grabbox_active(false)

	var direction: int = int(signf(global_position.x - attacker.global_position.x))
	if direction == 0:
		direction = attacker.facing

	if _try_resolve_guard_hit(attacker, attack_data, direction):
		return

	if state_machine.is_dash_vulnerable():
		state_machine.reset_stagger_meter()
		_begin_knockdown_from_impulse(
			_build_knockdown_impulse(direction, attack_data.knockback)
		)
		if not is_player_controlled and ai_controller.enabled:
			ai_controller.notify_took_damage()
		return

	if state_machine.is_vulnerable():
		_kill()
		return

	if not is_on_floor():
		_apply_airborne_hit(attacker, attack_data, direction)
		return

	if attack_data.launch_velocity < 0.0:
		_apply_launcher_hit(attacker, attack_data, direction)
		return

	var horizontal_kb := direction * attack_data.knockback * _get_knockback_taken_multiplier()
	match attack_data.hit_type:
		AttackData.HitType.KNOCKDOWN:
			var knockdown_stagger_kb := (
				direction
				* attack_data.knockback
				* _get_knockback_taken_multiplier()
				* stats.stagger_knockback_multiplier
			)
			var knockdown_stagger_hitstun := attack_data.hitstun_seconds
			if state_machine.apply_stagger_hit(
				attacker,
				attack_data.stagger_value,
				knockdown_stagger_kb,
				knockdown_stagger_hitstun
			):
				_begin_knockdown_from_impulse(
					_build_knockdown_impulse(direction, attack_data.knockback)
				)
		AttackData.HitType.STUN:
			state_machine.enter_stun(horizontal_kb, not is_on_floor())
		AttackData.HitType.STAGGER:
			var stagger_kb := (
				direction
				* attack_data.knockback
				* _get_knockback_taken_multiplier()
				* stats.stagger_knockback_multiplier
			)
			var stagger_hitstun := attack_data.hitstun_seconds
			if state_machine.apply_stagger_hit(
				attacker,
				attack_data.stagger_value,
				stagger_kb,
				stagger_hitstun
			):
				_begin_knockdown_from_impulse(
					_build_knockdown_impulse(direction, attack_data.knockback)
				)
		AttackData.HitType.KILL:
			_kill()

	if not is_player_controlled and ai_controller.enabled:
		ai_controller.notify_took_damage()


func _try_resolve_guard_hit(attacker: Fighter, attack_data: AttackData, direction: int) -> bool:
	if not state_machine.is_blocking() or not is_on_floor():
		return false

	match state_machine.current_state:
		FighterStateMachine.State.BLOCK:
			var block_mult := (
				stats.projectile_block_knockback_multiplier
				if attack_data.is_projectile
				else stats.block_knockback_multiplier
			)
			_apply_blocked_hit(attacker, attack_data, direction, block_mult)
			return true
		FighterStateMachine.State.CROUCH_BLOCK:
			if attack_data.is_overhead and not attack_data.is_projectile:
				attacker.state_machine.register_attack_hit()
				_begin_knockdown_from_impulse(
					_build_knockdown_impulse(direction, attack_data.knockback)
				)
				if not is_player_controlled and ai_controller.enabled:
					ai_controller.notify_took_damage()
				return true
			_apply_blocked_hit(
				attacker,
				attack_data,
				direction,
				stats.crouch_block_knockback_multiplier
			)
			return true
	return false


func _apply_blocked_hit(
	attacker: Fighter,
	attack_data: AttackData,
	direction: int,
	block_mult: float
) -> void:
	attacker.state_machine.register_attack_blocked()
	if not is_player_controlled and ai_controller.enabled:
		ai_controller.notify_blocked_hit()
	var block_knockback := attack_data.knockback * block_mult
	velocity.x = direction * block_knockback * _get_knockback_taken_multiplier()
	mark_external_displacement()


func _begin_knockdown_from_impulse(
	impulse: Vector2,
	from_throw: bool = false,
	juggle_attacker: Fighter = null
) -> void:
	var started_airborne := not is_on_floor()
	_break_juggle_with(juggle_attacker)
	state_machine.begin_knockdown_impulse(impulse, from_throw, started_airborne)
	if started_airborne:
		_input_buffer.reset()
		set_hitbox_active(false)
		set_grabbox_active(false)
		_clear_air_forward_combo()
	elif is_on_floor():
		global_position.y -= 8.0
		velocity = impulse


func try_receive_grab(thrower: Fighter, grab_data: GrabData) -> bool:
	if not state_machine.is_active_in_match():
		return false
	if not is_on_floor():
		return false
	if state_machine.is_invincible():
		return false
	if state_machine.is_grabbed():
		return false
	if state_machine.is_knocked_down():
		return false
	if state_machine.is_in_hitstun():
		return false
	if state_machine.is_attacking():
		return false
	if state_machine.is_grabbing():
		return false
	if state_machine.is_attack_active():
		return false
	if state_machine.is_crouching():
		return false

	state_machine.enter_grabbed(thrower, grab_data)
	return true


func apply_throw_from(thrower: Fighter, grab_data: GrabData, throw_vector: int) -> void:
	set_hitbox_active(false)
	set_grabbox_active(false)
	state_machine.grabbed_by = null
	state_machine.current_grab = null
	if throw_vector == 0:
		throw_vector = -thrower.facing
	var throw_impulse := _build_knockdown_impulse(
		throw_vector,
		grab_data.throw_knockback
	)
	_begin_knockdown_from_impulse(throw_impulse, true)


func release_from_grab() -> void:
	state_machine.release_from_grab()
	velocity = Vector2.ZERO


func _kill() -> void:
	if state_machine.is_holding_grab():
		state_machine.release_held_grab()
	if state_machine.is_grabbed():
		state_machine.release_from_grab()
	set_hitbox_active(false)
	set_grabbox_active(false)
	hitbox.deactivate()
	state_machine.clear_oki_punish_window()
	visible = false
	hurtbox.set_deferred("monitorable", false)
	state_machine.enter_dead()
	if fight_manager == null or not fight_manager.infinite_lives:
		lives -= 1
	died.emit(self)


func respawn_at(spawn_position: Vector2) -> void:
	var spawn_x := spawn_position.x
	var spawn_y := spawn_position.y
	if fight_manager != null:
		spawn_y = fight_manager.get_respawn_drop_y()
	global_position = Vector2(spawn_x, spawn_y)
	velocity = Vector2.ZERO
	_reset_facing_pivot_transform()
	visible = true
	hurtbox.monitorable = true
	state_machine.enter_respawn()
	_input_buffer.reset()
	_projectile_charging = false
	_projectile_auto_release = false
	move_and_slide()
	respawned.emit(self)
	_update_visuals()


func _check_respawn_landing() -> void:
	if not state_machine.is_respawn_falling():
		return
	if not is_on_floor():
		return
	if fight_manager != null:
		_snap_feet_to_ground()
	velocity = Vector2.ZERO
	state_machine.land_respawn()
	_update_visuals()


func on_knockdown_landed() -> void:
	if fight_manager != null:
		global_position.y = fight_manager.get_ground_y(global_position.x)
	velocity = Vector2.ZERO
	_reset_wakeup_w_press()
	_update_visuals()


func on_state_changed(next_state: FighterStateMachine.State) -> void:
	if next_state != FighterStateMachine.State.ATTACK:
		set_hitbox_active(false)
	if next_state != FighterStateMachine.State.GRAB:
		set_grabbox_active(false)
	_update_hurtbox_profile()
	_update_visuals()
	state_changed.emit(self, state_machine.get_state_name())


func _check_stage_bounds() -> void:
	if fight_manager == null:
		return
	if not state_machine.can_die_from_fall_off_stage():
		return
	if global_position.y >= fight_manager.death_y:
		_kill()
		return
	if not state_machine.is_on_ledge() and fight_manager.is_outside_horizontal_blast_zone(global_position.x):
		if not is_on_floor() or fight_manager.is_below_local_ground(global_position.x, global_position.y):
			_kill()


func _update_ground_state() -> void:
	if not state_machine.can_hold_guard() and not state_machine.is_crouching():
		return
	var moving := _get_move_direction() != 0
	state_machine.update_ground_state(
		moving,
		_is_grounded_for_stance(),
		is_guard_held(),
		is_crouch_held()
	)


func snap_to_ledge(side: int) -> void:
	if fight_manager == null:
		return
	global_position = fight_manager.get_ledge_hang_position(side, BODY_HALF_WIDTH, BODY_HEIGHT)
	velocity = Vector2.ZERO
	facing = -side if side != 0 else facing
	facing_pivot.scale.x = float(facing)


func _check_wakeup_roll_ledge_contact() -> void:
	if not state_machine.is_wakeup_rolling() or state_machine.wakeup_roll_from_ledge:
		return
	if fight_manager == null:
		return

	var roll_dir := state_machine.wakeup_roll_direction
	if roll_dir < 0:
		var hang_x := fight_manager.get_ledge_hang_x(-1, BODY_HALF_WIDTH)
		if global_position.x <= hang_x + 6.0:
			state_machine.snap_wakeup_roll_to_ledge(-1)
	elif roll_dir > 0:
		var hang_x := fight_manager.get_ledge_hang_x(1, BODY_HALF_WIDTH)
		if global_position.x >= hang_x - 6.0:
			state_machine.snap_wakeup_roll_to_ledge(1)


func start_ledge_regrab_lockout(duration: float = 1.5) -> void:
	_ledge_regrab_lockout = duration


func is_ledge_crouch_airborne() -> bool:
	return _ledge_crouch_carry and not is_on_floor()


func _update_ledge_climb_animation() -> void:
	if not state_machine.is_getting_up() or not state_machine.getup_from_ledge:
		return
	var progress := state_machine.get_getup_progress()
	global_position = _sample_ledge_mount_position(
		state_machine.ledge_climb_start,
		state_machine.ledge_climb_target,
		progress
	)
	velocity = Vector2.ZERO


func _sample_ledge_mount_position(start: Vector2, target: Vector2, progress: float) -> Vector2:
	var eased_x := 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 2.0)
	var x := lerpf(start.x, target.x, eased_x)
	const HORIZONTAL_PHASE := 0.62
	var y := start.y
	if progress >= HORIZONTAL_PHASE:
		var rise_t := (progress - HORIZONTAL_PHASE) / (1.0 - HORIZONTAL_PHASE)
		var eased_y := 1.0 - pow(1.0 - clampf(rise_t, 0.0, 1.0), 2.0)
		y = lerpf(start.y, target.y, eased_y)
		if fight_manager != null:
			y = lerpf(y, fight_manager.get_ground_y(x), eased_y)
	return Vector2(x, y)


func _update_wakeup_roll_animation() -> void:
	if not state_machine.is_wakeup_rolling():
		return
	var progress := state_machine.get_wakeup_roll_progress()
	if state_machine.wakeup_roll_from_ledge:
		global_position = _sample_ledge_mount_position(
			state_machine.ledge_climb_start,
			state_machine.ledge_climb_target,
			progress
		)
	else:
		var eased := 1.0 - pow(1.0 - progress, 2.0)
		global_position = state_machine.wakeup_roll_start_pos.lerp(
			state_machine.wakeup_roll_target_pos,
			eased
		)
		if fight_manager != null:
			_snap_feet_to_ground()
	velocity = Vector2.ZERO
	_reset_facing_pivot_transform()


func _update_ledge_crouch_tracking() -> void:
	if is_on_floor():
		_ledge_crouch_carry = state_machine.is_crouching() or _is_crouch_intent_held()
		_airborne_crouch_frames = 0
	elif _ledge_crouch_carry or (state_machine.is_crouching() and _was_on_floor_last_frame):
		if _was_on_floor_last_frame:
			_ledge_crouch_carry = true
			_airborne_crouch_frames = 1
		else:
			_airborne_crouch_frames += 1
	_was_on_floor_last_frame = is_on_floor()


func _check_ledge_grab_attempt() -> void:
	if fight_manager == null or state_machine.is_on_ledge():
		return
	if state_machine.is_knockdown_falling():
		return
	if _ledge_regrab_lockout > 0.0:
		return
	if not _ledge_crouch_carry or is_on_floor():
		return

	var airborne_frames := _airborne_crouch_frames
	if _was_on_floor_last_frame:
		airborne_frames = 1
	elif airborne_frames < 1:
		return

	if airborne_frames > 18:
		_ledge_crouch_carry = false
		return

	var grab_range := stats.ledge_grab_range
	var left_hang_x := fight_manager.get_ledge_hang_x(-1, BODY_HALF_WIDTH)
	var right_hang_x := fight_manager.get_ledge_hang_x(1, BODY_HALF_WIDTH)
	var x := global_position.x

	if x <= left_hang_x + grab_range:
		_ledge_crouch_carry = false
		_airborne_crouch_frames = 0
		state_machine.enter_ledge_recovery(-1)
		return
	if x >= right_hang_x - grab_range:
		_ledge_crouch_carry = false
		_airborne_crouch_frames = 0
		state_machine.enter_ledge_recovery(1)


func _split_shared_collision_shapes() -> void:
	if body_collision_shape.shape != null:
		body_collision_shape.shape = body_collision_shape.shape.duplicate()
	if hurtbox_shape.shape != null:
		hurtbox_shape.shape = hurtbox_shape.shape.duplicate()


func _uses_crouch_stance() -> bool:
	return state_machine.is_crouching()


func _uses_roll_stance() -> bool:
	return state_machine.is_wakeup_rolling()


func _update_hurtbox_profile() -> void:
	if _uses_roll_stance():
		_apply_stance_collision(body_collision_shape, ROLL_HURTBOX_SIZE, ROLL_HURTBOX_OFFSET)
		_apply_stance_collision(hurtbox_shape, ROLL_HURTBOX_SIZE, ROLL_HURTBOX_OFFSET)
		hurtbox_debug.position = ROLL_HURTBOX_OFFSET - ROLL_HURTBOX_SIZE * 0.5
		hurtbox_debug.size = ROLL_HURTBOX_SIZE
		return

	var crouching := _uses_crouch_stance()
	_apply_stance_collision(body_collision_shape, crouching)
	_apply_stance_collision(hurtbox_shape, crouching)
	if crouching:
		hurtbox_debug.position = CROUCH_HURTBOX_OFFSET - CROUCH_HURTBOX_SIZE * 0.5
		hurtbox_debug.size = CROUCH_HURTBOX_SIZE
	else:
		hurtbox_debug.position = STANDING_HURTBOX_OFFSET - STANDING_HURTBOX_SIZE * 0.5
		hurtbox_debug.size = STANDING_HURTBOX_SIZE


func _apply_stance_collision(
	shape_node: CollisionShape2D,
	crouching_or_size,
	offset: Vector2 = Vector2.ZERO
) -> void:
	var rect := shape_node.shape as RectangleShape2D
	if rect == null:
		return
	var size: Vector2
	var shape_offset: Vector2
	if crouching_or_size is bool:
		var crouching: bool = crouching_or_size
		if crouching:
			size = CROUCH_HURTBOX_SIZE
			shape_offset = CROUCH_HURTBOX_OFFSET
		else:
			size = STANDING_HURTBOX_SIZE
			shape_offset = STANDING_HURTBOX_OFFSET
	else:
		size = crouching_or_size as Vector2
		shape_offset = offset
	rect.size = size
	shape_node.position = shape_offset


func _update_facing() -> void:
	if opponent == null:
		return
	if state_machine.current_state in [
		FighterStateMachine.State.KNOCKDOWN,
		FighterStateMachine.State.STAGGER,
		FighterStateMachine.State.STUN,
		FighterStateMachine.State.GETUP_INVINCIBLE,
		FighterStateMachine.State.SLOW_GETUP,
		FighterStateMachine.State.WAKEUP_ROLL,
		FighterStateMachine.State.DEAD,
		FighterStateMachine.State.GRABBED,
		FighterStateMachine.State.LEDGE_RECOVERY,
	]:
		return
	if state_machine.is_holding_grab():
		return
	facing = 1 if opponent.global_position.x >= global_position.x else -1
	facing_pivot.scale.x = float(facing)


func _update_visuals() -> void:
	match state_machine.current_state:
		FighterStateMachine.State.BLOCK:
			body_rect.color = block_color
			guard_indicator.visible = true
			guard_indicator.color = guard_color
		FighterStateMachine.State.CROUCH:
			body_rect.color = body_color.darkened(0.12)
			guard_indicator.visible = false
			_apply_crouch_visual(true)
		FighterStateMachine.State.CROUCH_BLOCK:
			body_rect.color = block_color.darkened(0.08)
			guard_indicator.visible = true
			guard_indicator.color = guard_color
			_apply_crouch_visual(true)
		FighterStateMachine.State.LEDGE_RECOVERY:
			body_rect.color = body_color.darkened(0.18)
			guard_indicator.visible = false
			_apply_ledge_hang_visual()
		FighterStateMachine.State.GRAB:
			body_rect.color = grab_color
			guard_indicator.visible = false
		FighterStateMachine.State.GRABBED:
			body_rect.color = grab_color.darkened(0.2)
			guard_indicator.visible = false
		FighterStateMachine.State.DEAD:
			body_rect.color = Color(0.2, 0.2, 0.2, 0.3)
			guard_indicator.visible = false
		FighterStateMachine.State.KNOCKDOWN:
			body_rect.color = body_color.darkened(0.35)
			guard_indicator.visible = false
			_apply_crouch_visual(false)
		FighterStateMachine.State.STAGGER:
			body_rect.color = body_color.lightened(0.18)
			guard_indicator.visible = false
			rotation_degrees = 0.0
			_update_stagger_meter_display()
		FighterStateMachine.State.STUN:
			body_rect.color = body_color.darkened(0.5)
			guard_indicator.visible = false
			_apply_crouch_visual(false)
		FighterStateMachine.State.GETUP_INVINCIBLE:
			body_rect.color = body_color
			guard_indicator.visible = false
		FighterStateMachine.State.SLOW_GETUP:
			body_rect.color = body_color.darkened(0.08)
			guard_indicator.visible = false
		FighterStateMachine.State.WAKEUP_ROLL:
			body_rect.color = body_color.lightened(0.1)
			guard_indicator.visible = false
			_apply_roll_visual()
		_:
			body_rect.color = body_color
			guard_indicator.visible = false
			_apply_crouch_visual(false)
			if (
				state_machine.current_state != FighterStateMachine.State.KNOCKDOWN
				and not state_machine.is_getting_up()
			):
				rotation_degrees = 0.0

	if _hit_flash_timer > 0.0:
		var flash_strength := clampf(_hit_flash_timer / HIT_FLASH_DURATION, 0.0, 1.0)
		body_rect.color = body_rect.color.lerp(Color.WHITE, flash_strength * 0.82)

	_update_frame_overlays()


func _update_frame_overlays() -> void:
	if state_machine == null:
		return

	var show_iframes := state_machine.is_invincible()
	var show_vframes := state_machine.is_vulnerable()

	iframe_overlay.visible = show_iframes
	vframe_overlay.visible = show_vframes

	if show_iframes:
		var i_pulse := 0.9 + 0.1 * sin(state_machine.state_time * 18.0)
		iframe_overlay.color = Color(
			iframe_color.r, iframe_color.g, iframe_color.b, iframe_color.a * i_pulse
		)
	if show_vframes:
		var v_pulse := 0.88 + 0.12 * sin(state_machine.state_time * 22.0)
		vframe_overlay.color = Color(
			vframe_color.r, vframe_color.g, vframe_color.b, vframe_color.a * v_pulse
		)

	if state_machine.current_state == FighterStateMachine.State.KNOCKDOWN:
		_apply_knockdown_pose()
	elif state_machine.is_stunned() and is_on_floor():
		_reset_facing_pivot_transform()
		var stun_wobble := sin(state_machine.state_time * 28.0) * 8.0
		rotation_degrees = stun_wobble
	elif state_machine.is_getting_up():
		if state_machine.getup_from_ledge:
			_reset_facing_pivot_transform()
			var climb_t := state_machine.get_getup_progress()
			var hang_offset := (1.0 - climb_t) * BODY_HEIGHT
			body_rect.offset_top = -56.0 - hang_offset * 0.15
			body_rect.offset_bottom = 0.0
		else:
			_apply_getup_pose()
	elif state_machine.is_wakeup_rolling():
		_reset_facing_pivot_transform()
	else:
		_reset_facing_pivot_transform()


func _reset_facing_pivot_transform() -> void:
	rotation_degrees = 0.0
	facing_pivot.rotation_degrees = 0.0
	facing_pivot.position = Vector2.ZERO


func _apply_knockdown_pose() -> void:
	rotation_degrees = 0.0
	var lie_dir := state_machine.knockdown_lie_direction
	facing_pivot.rotation_degrees = -90.0 * lie_dir
	facing_pivot.position = Vector2.ZERO
	if state_machine.knockdown_landed:
		var ground_t := state_machine.get_knockdown_ground_time()
		if ground_t < KNOCKDOWN_LAND_BOUNCE_DURATION:
			var phase := ground_t / KNOCKDOWN_LAND_BOUNCE_DURATION
			facing_pivot.position.y = -sin(phase * PI) * KNOCKDOWN_LAND_BOUNCE_HEIGHT


func _apply_getup_pose() -> void:
	rotation_degrees = 0.0
	var getup_t := state_machine.get_getup_progress()
	var lie_dir := state_machine.knockdown_lie_direction
	facing_pivot.rotation_degrees = -90.0 * lie_dir * (1.0 - getup_t)
	facing_pivot.position = Vector2.ZERO


func _on_hit_landed(victim: Fighter, attack_data: AttackData) -> void:
	victim.receive_hit(self, attack_data)
	if state_machine.attack_contact == FighterStateMachine.ATTACK_CONTACT_BLOCK:
		_apply_hit_feedback(attack_data, victim, true)
		return
	state_machine.register_attack_hit(victim)
	_apply_hit_feedback(attack_data, victim, false)
	_apply_attacker_juggle_pop(attack_data)
	_register_air_forward_combo_hit(attack_data, victim)
	_refresh_juggle_mobility(victim)


func _apply_hit_feedback(
	attack_data: AttackData,
	victim: Fighter,
	was_blocked: bool
) -> void:
	if victim == null:
		return
	var frames := attack_data.hitstop_frames
	if was_blocked:
		frames = mini(frames, 2) if frames > 0 else 2
	elif frames <= 0:
		if attack_data.is_juggle_attack:
			frames = 6
		elif attack_data.launch_velocity < 0.0:
			frames = 8
		elif not victim.is_on_floor():
			frames = 5
		else:
			frames = 3
	apply_hitstop(frames)
	victim.apply_hitstop(frames)
	if not was_blocked:
		pulse_hit_flash()
		victim.pulse_hit_flash()


func _refresh_juggle_mobility(victim: Fighter) -> void:
	if victim == null or victim.is_on_floor():
		return
	if victim.state_machine.current_state != FighterStateMachine.State.STAGGER:
		return
	air_dash_used = false


func _on_grab_landed(victim: Fighter, grab_data: GrabData) -> void:
	if victim.try_receive_grab(self, grab_data):
		state_machine.begin_grab_hold(victim)
		velocity.x = 0.0


func set_debug_visible(enabled: bool) -> void:
	_debug_enabled = enabled
	hurtbox_debug.visible = enabled
	hitbox_debug.visible = enabled and hitbox.monitoring
	grabbox_debug.visible = enabled and grabbox.monitoring
	if enabled and state_machine != null and state_machine.current_attack != null:
		_update_hitbox_debug(state_machine.current_attack)
	if enabled and state_machine != null and state_machine.current_grab != null:
		_update_grabbox_debug(state_machine.current_grab)


func _update_grabbox_debug(grab_data: GrabData) -> void:
	var offset: Vector2 = grab_data.grab_offset
	grabbox_debug.position = offset - grab_data.grab_size * 0.5
	grabbox_debug.size = grab_data.grab_size


func _update_hitbox_debug(attack_data: AttackData) -> void:
	var offset: Vector2 = attack_data.hitbox_offset
	hitbox_debug.position = offset - attack_data.hitbox_size * 0.5
	hitbox_debug.size = attack_data.hitbox_size


func _get_knockback_taken_multiplier() -> float:
	return 1.0 / maxf(stats.weight, 0.25)


func _build_knockdown_impulse(direction: int, knockback: float) -> Vector2:
	return Vector2(
		direction * knockback * _get_knockback_taken_multiplier(),
		stats.knockdown_launch_velocity
	)


func _build_air_juggle_knockdown_impulse(direction: int, knockback: float) -> Vector2:
	return Vector2(
		direction
		* knockback
		* _get_knockback_taken_multiplier()
		* stats.air_knockdown_horizontal_scale,
		stats.air_knockdown_pop_velocity
	)


func _apply_juggle_hit(attacker: Fighter, attack_data: AttackData, direction: int) -> void:
	var kb_scale := attack_data.juggle_knockback_scale
	if kb_scale <= 0.0:
		kb_scale = DEFAULT_JUGGLE_KNOCKBACK_SCALE
	var stagger_kb := (
		direction
		* attack_data.knockback
		* _get_knockback_taken_multiplier()
		* stats.stagger_knockback_multiplier
		* kb_scale
	)
	var stagger_hitstun := attack_data.hitstun_seconds
	if state_machine.apply_stagger_hit(
		attacker,
		attack_data.stagger_value,
		stagger_kb,
		stagger_hitstun
	):
		_begin_knockdown_from_impulse(
			_build_air_juggle_knockdown_impulse(direction, attack_data.knockback),
			false,
			attacker
		)
	else:
		_apply_juggle_pop(attack_data)
		mark_external_displacement()
	if not is_player_controlled and ai_controller.enabled:
		ai_controller.notify_took_damage()


func _apply_attacker_juggle_pop(attack_data: AttackData) -> void:
	if is_on_floor():
		return
	var pop_y := attack_data.attacker_juggle_pop_velocity
	if pop_y != 0.0:
		if pop_y < 0.0:
			if velocity.y >= pop_y * 0.5:
				velocity.y = pop_y
			else:
				velocity.y = minf(velocity.y, pop_y)
		else:
			velocity.y = maxf(velocity.y, pop_y)
	var pop_forward := attack_data.attacker_juggle_pop_forward
	if pop_forward != 0.0:
		velocity.x = facing * pop_forward


func _apply_juggle_pop(attack_data: AttackData) -> void:
	if is_on_floor():
		return
	var pop := attack_data.juggle_pop_velocity
	if pop == 0.0:
		pop = -140.0
	if pop >= 0.0:
		return
	# Falling or barely rising — snap to full pop so the chain stays airborne.
	if velocity.y >= pop * 0.5:
		velocity.y = pop
	else:
		velocity.y = minf(velocity.y, pop)


func _apply_airborne_hit(attacker: Fighter, attack_data: AttackData, direction: int) -> void:
	if attack_data.hit_type == AttackData.HitType.KILL:
		_kill()
		if not is_player_controlled and ai_controller.enabled:
			ai_controller.notify_took_damage()
		return

	if attack_data.hit_type == AttackData.HitType.STUN:
		state_machine.reset_stagger_meter()
		state_machine.enter_stun(
			direction * attack_data.knockback * _get_knockback_taken_multiplier(),
			true
		)
		if not is_player_controlled and ai_controller.enabled:
			ai_controller.notify_took_damage()
		return

	if attack_data.is_anti_air or attack_data.hit_type == AttackData.HitType.KNOCKDOWN:
		state_machine.reset_stagger_meter()
		_begin_knockdown_from_impulse(
			_build_air_juggle_knockdown_impulse(direction, attack_data.knockback)
		)
		if not is_player_controlled and ai_controller.enabled:
			ai_controller.notify_took_damage()
		return

	if attack_data.is_juggle_attack:
		_apply_juggle_hit(attacker, attack_data, direction)
		return

	var stagger_kb := (
		direction
		* attack_data.knockback
		* _get_knockback_taken_multiplier()
		* stats.stagger_knockback_multiplier
	)
	var stagger_hitstun := attack_data.hitstun_seconds
	if state_machine.apply_stagger_hit(
		attacker,
		attack_data.stagger_value,
		stagger_kb,
		stagger_hitstun
	):
		_begin_knockdown_from_impulse(
			_build_air_juggle_knockdown_impulse(direction, attack_data.knockback)
		)
	else:
		mark_external_displacement()
	if not is_player_controlled and ai_controller.enabled:
		ai_controller.notify_took_damage()


func _apply_launcher_hit(attacker: Fighter, attack_data: AttackData, direction: int) -> void:
	var horizontal_kb := (
		direction
		* attack_data.knockback
		* _get_knockback_taken_multiplier()
		* stats.stagger_knockback_multiplier
	)
	var launch_y := attack_data.launch_velocity
	var stagger_hitstun := attack_data.hitstun_seconds
	if state_machine.apply_stagger_hit_with_launch(
		attacker,
		attack_data.stagger_value,
		horizontal_kb,
		stagger_hitstun,
		launch_y
	):
		_begin_knockdown_from_impulse(
			_build_knockdown_impulse(direction, attack_data.knockback)
		)
	else:
		mark_external_displacement()
	if not is_player_controlled and ai_controller.enabled:
		ai_controller.notify_took_damage()


func _can_body_push() -> bool:
	if opponent == null or not state_machine.is_active_in_match():
		return false
	if state_machine.is_wakeup_rolling():
		return false
	if not is_on_floor() or not opponent.is_on_floor():
		return false
	if state_machine.is_crouching():
		return false
	return state_machine.current_state in [
		FighterStateMachine.State.IDLE,
		FighterStateMachine.State.MOVE,
		FighterStateMachine.State.BLOCK,
		FighterStateMachine.State.ATTACK,
	]


func _get_grab_advance_speed() -> float:
	var grab: GrabData = state_machine.current_grab
	if grab == null or grab.grab_advance_speed <= 0.0:
		return 0.0
	if state_machine.current_state != FighterStateMachine.State.GRAB:
		return 0.0
	if state_machine.grab_landed:
		return 0.0
	var frame := CombatTiming.seconds_to_frame(state_machine.state_time)
	var end_frame: int = grab.startup_frames + grab.active_frames
	if frame >= end_frame:
		return 0.0
	return grab.grab_advance_speed


func _get_horizontal_overlap(other: Fighter) -> float:
	var gap := absf(global_position.x - other.global_position.x) - (BODY_HALF_WIDTH * 2.0)
	return maxf(-gap, 0.0)


func _wants_to_move_toward(other: Fighter) -> bool:
	var dir_to_other := signf(other.global_position.x - global_position.x)
	if dir_to_other == 0.0:
		return false
	var move_dir := _get_move_direction()
	if move_dir != 0:
		return float(move_dir) == dir_to_other
	return absf(velocity.x) > 20.0 and signf(velocity.x) == dir_to_other


func _resolve_body_collision(other: Fighter, delta: float) -> void:
	if opponent == null:
		return
	if not state_machine.is_active_in_match() or not other.state_machine.is_active_in_match():
		return
	if state_machine.is_wakeup_rolling() or other.state_machine.is_wakeup_rolling():
		return

	var overlap := _get_horizontal_overlap(other)
	if overlap > 0.0:
		var self_pushable := _can_body_push()
		var other_pushable := other._can_body_push()
		if self_pushable or other_pushable:
			var push_self_w := stats.weight
			var push_other_w := other.stats.weight
			var push_total_w := push_self_w + push_other_w
			var self_share := push_other_w / push_total_w if self_pushable else 0.0
			var other_share := push_self_w / push_total_w if other_pushable else 0.0
			if global_position.x < other.global_position.x:
				if self_pushable:
					global_position.x -= overlap * self_share
				if other_pushable:
					other.global_position.x += overlap * other_share
					if not other._wants_to_move_toward(self):
						other.mark_external_displacement()
			else:
				if self_pushable:
					global_position.x += overlap * self_share
				if other_pushable:
					other.global_position.x -= overlap * other_share
					if not other._wants_to_move_toward(self):
						other.mark_external_displacement()

	if not _can_body_push() or not other._can_body_push():
		return

	var self_weight := stats.weight
	var other_weight := other.stats.weight
	var total_weight := self_weight + other_weight
	var self_toward := _wants_to_move_toward(other)
	var other_toward := other._wants_to_move_toward(self)
	if not self_toward and not other_toward:
		return

	var weight_diff := absf(self_weight - other_weight)
	if weight_diff <= 0.001:
		if self_toward and other_toward:
			velocity.x *= 0.88
			other.velocity.x *= 0.88
		return

	var heavier := self if self_weight > other_weight else other
	var lighter := other if heavier == self else self
	var push_factor := heavier.stats.body_push_factor
	var push_away_dir := signf(lighter.global_position.x - heavier.global_position.x)
	if push_away_dir == 0.0:
		push_away_dir = 1.0

	var lighter_toward_heavier := lighter._wants_to_move_toward(heavier)
	var heavier_toward_lighter := heavier._wants_to_move_toward(lighter)

	if lighter_toward_heavier and heavier_toward_lighter:
		var push_amount := weight_diff * push_factor * delta
		lighter.global_position.x += push_away_dir * push_amount
		lighter.velocity.x = push_away_dir * maxf(absf(lighter.velocity.x), push_factor * weight_diff * 0.35)
		if not lighter._wants_to_move_toward(heavier):
			lighter.mark_external_displacement()
		heavier.velocity.x *= 1.0 - (weight_diff / total_weight) * 0.15
	elif lighter_toward_heavier:
		var resist := heavier.stats.weight / total_weight
		lighter.velocity.x *= 1.0 - resist * 0.7
		if overlap >= 0.0:
			lighter.global_position.x += push_away_dir * weight_diff * push_factor * delta * 0.45
			if not lighter._wants_to_move_toward(heavier):
				lighter.mark_external_displacement()


func _get_move_direction() -> int:
	var direction := 0
	if _is_left_pressed():
		direction -= 1
	if _is_right_pressed():
		direction += 1
	return direction


func _is_left_pressed() -> bool:
	if is_player_controlled:
		if Input.is_action_pressed("move_left") or _virtual_left:
			return true
		return GamepadInput.get_move_direction() < 0
	return _virtual_left


func _is_right_pressed() -> bool:
	if is_player_controlled:
		if Input.is_action_pressed("move_right") or _virtual_right:
			return true
		return GamepadInput.get_move_direction() > 0
	return _virtual_right


func _just_pressed_jump() -> bool:
	if _virtual_jump_pulse:
		_virtual_jump_pulse = false
		return true
	return false


func _consume_throw_input() -> bool:
	if _virtual_throw:
		_virtual_throw = false
		return true
	if not is_player_controlled:
		return false
	return false


func _is_up_intent_held() -> bool:
	if is_player_controlled:
		return _input_buffer.is_up_held()
	return false


func _is_up_intent_just_pressed() -> bool:
	if not is_player_controlled:
		return false
	return Input.is_action_just_pressed("move_up") or _gamepad_up_just_pressed()


func _just_pressed_throw() -> bool:
	return _consume_throw_input()


func _just_pressed_up() -> bool:
	if is_player_controlled and Input.is_action_just_pressed("move_up"):
		return true
	return is_player_controlled and _gamepad_up_just_pressed()


func _gamepad_up_just_pressed() -> bool:
	return GamepadInput.is_up_pressed() and not _gamepad_up_was_held


func _attack_has_lunge() -> bool:
	var attack := state_machine.current_attack as AttackData
	return attack != null and _get_attack_advance() != 0.0


func _get_attack_advance() -> float:
	var attack: AttackData = state_machine.current_attack
	if attack == null:
		return 0.0
	if state_machine.current_state not in [
		FighterStateMachine.State.ATTACK,
		FighterStateMachine.State.CROUCH,
		FighterStateMachine.State.CROUCH_BLOCK,
	]:
		return 0.0
	var frame := CombatTiming.seconds_to_frame(state_machine.state_time)
	var advance_end_frame := attack.startup_frames + attack.active_frames
	if frame >= advance_end_frame:
		return 0.0
	if is_on_floor():
		return attack.ground_advance_speed
	var advance := attack.air_advance_speed
	if attack.is_juggle_attack:
		var kb_scale := attack.juggle_knockback_scale
		if kb_scale <= 0.0:
			kb_scale = DEFAULT_JUGGLE_KNOCKBACK_SCALE
		var victim_kb := attack.knockback * kb_scale
		if opponent != null:
			victim_kb *= (
				opponent._get_knockback_taken_multiplier()
				* stats.stagger_knockback_multiplier
			)
		advance = minf(advance, absf(victim_kb) * JUGGLE_ADVANCE_KNOCKBACK_RATIO)
	return advance


func _get_attack_ground_advance() -> float:
	var attack: AttackData = state_machine.current_attack
	if attack == null or not is_on_floor():
		return 0.0
	if state_machine.current_state not in [
		FighterStateMachine.State.ATTACK,
		FighterStateMachine.State.CROUCH,
		FighterStateMachine.State.CROUCH_BLOCK,
	]:
		return 0.0
	var frame := CombatTiming.seconds_to_frame(state_machine.state_time)
	var advance_end_frame := attack.startup_frames + attack.active_frames
	if frame >= advance_end_frame:
		return 0.0
	return attack.ground_advance_speed


func _just_pressed_get_up_neutral() -> bool:
	if is_player_controlled:
		return Input.is_action_just_pressed("move_up")
	if _virtual_jump_pulse:
		_virtual_jump_pulse = false
		return true
	return false


func _apply_roll_visual() -> void:
	body_rect.offset_top = -ROLL_HURTBOX_SIZE.y
	body_rect.offset_bottom = 0.0
	guard_indicator.offset_top = -ROLL_HURTBOX_SIZE.y + 4.0
	guard_indicator.offset_bottom = -10.0
	iframe_overlay.offset_top = -ROLL_HURTBOX_SIZE.y
	iframe_overlay.offset_bottom = 0.0
	vframe_overlay.offset_top = -ROLL_HURTBOX_SIZE.y
	vframe_overlay.offset_bottom = 0.0


func _apply_crouch_visual(crouching: bool) -> void:
	if crouching:
		body_rect.offset_top = -CROUCH_HURTBOX_SIZE.y
		body_rect.offset_bottom = 0.0
		guard_indicator.offset_top = -CROUCH_HURTBOX_SIZE.y + 4.0
		guard_indicator.offset_bottom = -10.0
		iframe_overlay.offset_top = -CROUCH_HURTBOX_SIZE.y
		iframe_overlay.offset_bottom = 0.0
		vframe_overlay.offset_top = -CROUCH_HURTBOX_SIZE.y
		vframe_overlay.offset_bottom = 0.0
	else:
		body_rect.offset_top = -BODY_HEIGHT
		body_rect.offset_bottom = 0.0
		guard_indicator.offset_top = -52.0
		guard_indicator.offset_bottom = -10.0
		iframe_overlay.offset_top = -BODY_HEIGHT
		iframe_overlay.offset_bottom = 0.0
		vframe_overlay.offset_top = -BODY_HEIGHT
		vframe_overlay.offset_bottom = 0.0


func _apply_ledge_hang_visual() -> void:
	body_rect.offset_top = -56.0
	body_rect.offset_bottom = 0.0
	_reset_facing_pivot_transform()


func _is_down_pressed() -> bool:
	return _is_crouch_intent_held()


func _is_up_pressed() -> bool:
	return _input_buffer.is_up_held() if is_player_controlled else false


func _is_neutral_attack_intent() -> bool:
	if _is_up_pressed():
		return false
	if is_on_floor() and _is_down_pressed():
		return false
	if is_on_floor() and _get_move_direction() == facing:
		return false
	return true


func _is_back_pressed() -> bool:
	var move_dir := _get_move_direction()
	return move_dir != 0 and move_dir == -facing


func _resolve_attack_from_direction() -> String:
	if not is_on_floor():
		if _is_down_pressed():
			return "air_overhead"
		if _is_up_pressed():
			return "air_up"
		var air_move_dir := _get_move_direction()
		if air_move_dir != 0 and air_move_dir == -facing:
			return "back_retreat"
		if air_move_dir == facing:
			return _get_air_forward_chain_attack()
		return "air_neutral"
	if _is_down_pressed():
		return "down"
	if _is_back_pressed():
		return "back_overhead"
	var move_dir := _get_move_direction()
	if move_dir == facing:
		return "forward"
	return "neutral"


func _attack_button_just_pressed() -> bool:
	if is_player_controlled and Input.is_action_just_pressed("attack"):
		return true
	return _virtual_attack_name != ""


func _consume_attack_input() -> String:
	if _virtual_attack_name != "":
		var attack_name := _virtual_attack_name
		_virtual_attack_name = ""
		return attack_name
	return ""


func _clear_pending_attack_input() -> void:
	_virtual_attack_name = ""

# Dylan is a menace.
