extends Node
class_name FighterStateMachine

## Per-fighter combat state machine: tracks the active state (attacks, grabs, dashes,
## hitstun, knockdown, wakeup, projectiles, respawn) and drives its timed transitions.


#region Enums

enum State {
	IDLE,
	MOVE,
	BLOCK,
	CROUCH,
	CROUCH_BLOCK,
	ATTACK,
	GRAB,
	GRABBED,
	DASH,
	STAGGER,
	STUN,
	KNOCKDOWN,
	GETUP_INVINCIBLE,
	SLOW_GETUP,
	WAKEUP_ROLL,
	PUNISH_WINDOW,
	LEDGE_RECOVERY,
	PROJECTILE_CHARGE,
	DEAD,
	RESPAWN,
}


enum WakeupOption {
	NEUTRAL,
	BLOCK,
	ATTACK,
	JUMP,
	CROUCH,
	GRAB,
	ROLL_LEFT,
	ROLL_RIGHT,
	SLOW,
}

#endregion


#region Constants

const KNOCKDOWN_FALL_DURATION := 0.38 * CombatTiming.FIGHT_TIMING_SCALE
const KNOCKDOWN_FORCED_GROUND_DURATION := 1.0 * CombatTiming.FIGHT_TIMING_SCALE
const KNOCKDOWN_GROUND_INVINCIBLE_DURATION := 1.25 * CombatTiming.FIGHT_TIMING_SCALE
const KNOCKDOWN_GROUND_AUTO_GETUP_DELAY := 2.75 * CombatTiming.FIGHT_TIMING_SCALE
const GETUP_INVINCIBLE_DURATION := 0.35 * CombatTiming.FIGHT_TIMING_SCALE
const WAKEUP_ROLL_DURATION := 0.28 * CombatTiming.FIGHT_TIMING_SCALE
const PUNISH_WINDOW_DURATION := 0.45 * CombatTiming.FIGHT_TIMING_SCALE
const DASH_IFRAME_START := 0.28
const DASH_IFRAME_END := 0.72
const RESPAWN_INVINCIBLE_DURATION := 1.0 * CombatTiming.FIGHT_TIMING_SCALE


const ATTACK_CONTACT_NONE := 0
const ATTACK_CONTACT_HIT := 1
const ATTACK_CONTACT_BLOCK := 2

#endregion


#region Public state

var current_state: State = State.IDLE
var state_time: float = 0.0
var attack_frame: int = 0
var current_attack: Resource
var current_grab: Resource
var grab_landed: bool = false
var grab_in_recovery: bool = false
var grab_whiffed: bool = false
var grab_victim: Fighter
var grabbed_by: Fighter
var dash_direction: int = 1
var dash_in_recovery: bool = false
var dash_attack_buffered: bool = false
var knockdown_landed: bool = false
var knockdown_from_throw: bool = false
var knockdown_was_airborne: bool = false
var knockdown_started_in_air: bool = false
var knockdown_left_ground: bool = false
var knockdown_lie_direction: int = 1
var knockdown_velocity: Vector2 = Vector2.ZERO
var knockdown_landed_at: float = 0.0
var has_buffered_prone_wakeup: bool = false
var buffered_prone_wakeup: WakeupOption = WakeupOption.NEUTRAL
var hitstun_velocity_x: float = 0.0
var stagger_hitstun_duration: float = 0.30
var stun_started_airborne: bool = false
var respawn_falling: bool = false
var respawn_iframes_remaining: float = 0.0
var oki_punish_time_left: float = 0.0
var attack_contact: int = 0  # 0=none, 1=hit, 2=block
var attack_recovery_frames: int = 0
var attack_landing_lag_time: float = 0.0
var attack_landing_lag_applied: bool = false
var ledge_side: int = 0
var getup_from_ledge: bool = false
var getup_invincible_duration: float = GETUP_INVINCIBLE_DURATION
var pending_wakeup_followup: WakeupOption = WakeupOption.NEUTRAL
var wakeup_roll_direction: int = 1
var wakeup_roll_from_ledge: bool = false
var wakeup_roll_start_pos: Vector2 = Vector2.ZERO
var wakeup_roll_target_pos: Vector2 = Vector2.ZERO
var lethal_punish_throw: bool = false
var stagger_meter: int = 0


var combo_follow_up_buffered: AttackData
var attack_hit_serial: int = 0
var ledge_climb_start: Vector2 = Vector2.ZERO
var ledge_climb_target: Vector2 = Vector2.ZERO
var projectile_charge_time: float = 0.0
var projectile_recovery_remaining: float = 0.0
var projectile_startup_remaining: float = 0.0
var projectile_pending_charge: float = 0.0
var projectile_pending_low: bool = false

#endregion


#region Private state

var _stagger_hit_serial_by_attacker: Dictionary = {}


var _fighter: CharacterBody2D

#endregion


#region Public API

## Binds the owning fighter; call once before any other use.
func setup(fighter: CharacterBody2D) -> void:
	_fighter = fighter


## Returns the current State's enum key as a string, for debug and animation lookup.
func get_state_name() -> String:
	return State.keys()[current_state]


## True when in a neutral state that can start a brand-new action this frame.
func can_accept_input() -> bool:
	if projectile_recovery_remaining > 0.0:
		return false
	if current_attack != null:
		return false
	if current_state == State.PROJECTILE_CHARGE:
		return false
	if current_state == State.RESPAWN and not respawn_falling:
		return true
	return current_state in [
		State.IDLE,
		State.MOVE,
		State.BLOCK,
		State.CROUCH,
		State.CROUCH_BLOCK,
		State.LEDGE_RECOVERY,
	]


## True when an input can be queued now to fire as soon as the current action ends.
func can_buffer_inputs() -> bool:
	if not is_active_in_match():
		return false
	if can_accept_input():
		return true
	if current_state == State.ATTACK:
		return true
	if current_state in [State.CROUCH, State.CROUCH_BLOCK] and current_attack != null:
		return true
	if current_state == State.DASH:
		return true
	if projectile_recovery_remaining > 0.0:
		return true
	if current_state == State.PROJECTILE_CHARGE:
		return true
	if current_state in [State.BLOCK, State.CROUCH_BLOCK, State.STAGGER, State.STUN]:
		return true
	return false


## True while crouching or crouch-blocking.
func is_crouching() -> bool:
	return current_state in [State.CROUCH, State.CROUCH_BLOCK]


## True only while plain crouching (not crouch-block), where the low profile applies.
func is_crouch_low_profiling() -> bool:
	return current_state == State.CROUCH


## True while hanging in ledge recovery.
func is_on_ledge() -> bool:
	return current_state == State.LEDGE_RECOVERY


## True while in the knockdown state, whether falling or grounded.
func is_knocked_down() -> bool:
	return current_state == State.KNOCKDOWN


## True while in stagger or stun hitstun.
func is_in_hitstun() -> bool:
	return current_state in [State.STAGGER, State.STUN]


## True while in the heavier stun state.
func is_stunned() -> bool:
	return current_state == State.STUN


## True when the current attack has a combo follow-up that can be buffered.
func can_buffer_combo() -> bool:
	if current_attack == null:
		return false
	var attack := current_attack as AttackData
	return attack.combo_follow_up != null


## Buffers the current attack's combo follow-up, if it has one.
func buffer_combo_follow_up() -> void:
	if not can_buffer_combo():
		return
	combo_follow_up_buffered = (current_attack as AttackData).combo_follow_up


## Returns and clears the buffered combo follow-up (null if none).
func consume_combo_follow_up() -> AttackData:
	var next := combo_follow_up_buffered
	combo_follow_up_buffered = null
	return next


## Drops any buffered combo follow-up.
func clear_combo_buffer() -> void:
	combo_follow_up_buffered = null


## Zeroes the stagger meter, clears per-attacker hit tracking, and refreshes its display.
func reset_stagger_meter() -> void:
	stagger_meter = 0
	_stagger_hit_serial_by_attacker.clear()
	(_fighter as Fighter)._update_stagger_meter_display()


## Adds a stagger hit (ignoring a duplicate from the same attack); returns true if it
## crossed the knockdown threshold, otherwise enters stagger and returns false.
func apply_stagger_hit(
	attacker: Fighter,
	stagger_value: int,
	horizontal_kb: float,
	hitstun_seconds: float,
	can_knock_down: bool = true
) -> bool:
	var serial := attacker.state_machine.attack_hit_serial
	var attacker_id := attacker.get_instance_id()
	if _stagger_hit_serial_by_attacker.get(attacker_id, -1) == serial:
		return false
	_stagger_hit_serial_by_attacker[attacker_id] = serial

	stagger_meter += stagger_value
	(_fighter as Fighter)._update_stagger_meter_display()

	var knockdown_threshold := (_fighter as Fighter).stats.stagger_meter_knockdown
	if stagger_meter >= knockdown_threshold:
		if can_knock_down:
			reset_stagger_meter()
			return true
		# This hit can't fell them (e.g. a not-fully-charged coin): cap the meter just below
		# the threshold so it still staggers but never triggers a knockdown.
		stagger_meter = knockdown_threshold - 1
		(_fighter as Fighter)._update_stagger_meter_display()

	enter_stagger(horizontal_kb, hitstun_seconds)
	return false


## Like apply_stagger_hit but staggers with an added vertical launch on the non-knockdown path.
func apply_stagger_hit_with_launch(
	attacker: Fighter,
	stagger_value: int,
	horizontal_kb: float,
	hitstun_seconds: float,
	launch_velocity: float
) -> bool:
	var serial := attacker.state_machine.attack_hit_serial
	var attacker_id := attacker.get_instance_id()
	if _stagger_hit_serial_by_attacker.get(attacker_id, -1) == serial:
		return false
	_stagger_hit_serial_by_attacker[attacker_id] = serial

	stagger_meter += stagger_value
	(_fighter as Fighter)._update_stagger_meter_display()

	var knockdown_threshold := (_fighter as Fighter).stats.stagger_meter_knockdown
	if stagger_meter >= knockdown_threshold:
		reset_stagger_meter()
		return true

	enter_stagger(horizontal_kb, hitstun_seconds, launch_velocity)
	return false


## True when the fighter is in a state that can keep holding guard.
func can_hold_guard() -> bool:
	if current_state == State.RESPAWN and not respawn_falling:
		return true
	return current_state in [State.IDLE, State.MOVE, State.BLOCK, State.CROUCH, State.CROUCH_BLOCK]


## True while blocking, standing or crouching.
func is_blocking() -> bool:
	return current_state in [State.BLOCK, State.CROUCH_BLOCK]


## True while in the grab state.
func is_grabbing() -> bool:
	return current_state == State.GRAB


## True while actively holding a grabbed victim.
func is_holding_grab() -> bool:
	return current_state == State.GRAB and grab_landed and grab_victim != null


## True while being held in an opponent's grab.
func is_grabbed() -> bool:
	return current_state == State.GRABBED


## True while the current attack is in its active (hitting) frames.
func is_attack_active() -> bool:
	if current_attack == null:
		return false
	if attack_landing_lag_time > 0.0:
		return false
	var frame := CombatTiming.seconds_to_frame(state_time)
	return (
		frame >= current_attack.startup_frames
		and frame < current_attack.startup_frames + current_attack.active_frames
	)


## True while attacking and not yet in landing lag.
func is_attacking() -> bool:
	return current_state == State.ATTACK and current_attack != null and attack_landing_lag_time <= 0.0


## True while serving an attack's landing lag.
func is_attack_in_landing_lag() -> bool:
	return attack_landing_lag_time > 0.0


## True while knocked down but not yet landed.
func is_knockdown_falling() -> bool:
	return current_state == State.KNOCKDOWN and not knockdown_landed


## True while still falling from a knockdown that began airborne.
func is_air_knockdown_falling() -> bool:
	return is_knockdown_falling() and knockdown_started_in_air


## 0..1 progress through the knockdown fall (1 once landed).
func get_knockdown_fall_progress() -> float:
	if knockdown_landed:
		return 1.0
	return clampf(state_time / KNOCKDOWN_FALL_DURATION, 0.0, 1.0)


## 0..1 progress through the current get-up (1 if not getting up).
func get_getup_progress() -> float:
	if current_state == State.GETUP_INVINCIBLE:
		if getup_invincible_duration <= 0.0:
			return 1.0
		return clampf(state_time / getup_invincible_duration, 0.0, 1.0)
	if current_state == State.SLOW_GETUP:
		var duration := CombatTiming.scale_time((_fighter as Fighter).stats.slow_getup_duration)
		if duration <= 0.0:
			return 1.0
		return clampf(state_time / duration, 0.0, 1.0)
	return 1.0


## Wakeup-roll duration from stats, or the default constant when unset.
func get_wakeup_roll_duration() -> float:
	var duration := CombatTiming.scale_time((_fighter as Fighter).stats.wakeup_roll_duration)
	if duration > 0.0:
		return duration
	return WAKEUP_ROLL_DURATION


## 0..1 progress through the wakeup roll (1 if not rolling).
func get_wakeup_roll_progress() -> float:
	if current_state != State.WAKEUP_ROLL:
		return 1.0
	var duration := get_wakeup_roll_duration()
	if duration <= 0.0:
		return 1.0
	return clampf(state_time / duration, 0.0, 1.0)


## True during either get-up state.
func is_getting_up() -> bool:
	return current_state in [State.GETUP_INVINCIBLE, State.SLOW_GETUP]


## True during a wakeup roll.
func is_wakeup_rolling() -> bool:
	return current_state == State.WAKEUP_ROLL


## True while the active frames of a wakeup-reversal attack grant invincibility.
func is_wakeup_attack_invincible() -> bool:
	if current_attack == null:
		return false
	var attack := current_attack as AttackData
	if attack == null or not attack.is_wakeup_attack:
		return false
	return is_attack_active()


## Opens the okizeme punish window after a wakeup.
func begin_oki_punish_window() -> void:
	oki_punish_time_left = PUNISH_WINDOW_DURATION


## Closes the okizeme punish window.
func clear_oki_punish_window() -> void:
	oki_punish_time_left = 0.0


## True while knockdown invincibility applies (still falling, or within the grounded grace).
func is_knockdown_invincible() -> bool:
	if current_state != State.KNOCKDOWN:
		return false
	if is_knockdown_falling():
		return true
	return (state_time - knockdown_landed_at) < KNOCKDOWN_GROUND_INVINCIBLE_DURATION


## Seconds spent grounded in knockdown (0 until landed).
func get_knockdown_ground_time() -> float:
	if not knockdown_landed:
		return 0.0
	return state_time - knockdown_landed_at


## True while pinned to the ground early in knockdown, before wakeup is allowed.
func is_knockdown_forced_ground() -> bool:
	return (
		current_state == State.KNOCKDOWN
		and knockdown_landed
		and get_knockdown_ground_time() < KNOCKDOWN_FORCED_GROUND_DURATION
	)


## True when a wakeup can be performed from the grounded knockdown right now.
func can_execute_prone_wakeup() -> bool:
	return can_use_knockdown_wakeup_options() and not is_knockdown_forced_ground()


## Buffers a wakeup option to fire when allowed; returns false if one is already buffered.
func buffer_prone_wakeup(option: WakeupOption) -> bool:
	if has_buffered_prone_wakeup:
		return false
	buffered_prone_wakeup = option
	has_buffered_prone_wakeup = true
	return true


## Fires a buffered prone wakeup if one is queued and now allowed; returns whether it started.
func try_execute_buffered_prone_wakeup() -> bool:
	if not can_execute_prone_wakeup():
		return false
	if not has_buffered_prone_wakeup:
		return false
	var option := buffered_prone_wakeup
	has_buffered_prone_wakeup = false
	return _begin_wakeup(option, false)


## True during the dash's mid-window invincibility frames.
func is_dash_invincible() -> bool:
	if current_state != State.DASH or dash_in_recovery:
		return false
	var duration := get_dash_active_duration()
	if duration <= 0.0:
		return false
	var progress := state_time / duration
	return progress >= DASH_IFRAME_START and progress <= DASH_IFRAME_END


## True during dash recovery, when the dash can be punished.
func is_dash_vulnerable() -> bool:
	return current_state == State.DASH and dash_in_recovery


## Active dash duration from stats, shorter on the ground than airborne.
func get_dash_active_duration() -> float:
	var fighter := _fighter as Fighter
	if fighter.is_on_floor():
		return CombatTiming.scale_time(fighter.stats.dash_ground_duration)
	return CombatTiming.scale_time(fighter.stats.dash_duration)


## True while respawn invincibility (falling or post-land iframes) applies.
func is_respawn_invincible() -> bool:
	if current_state == State.RESPAWN:
		return respawn_falling or respawn_iframes_remaining > 0.0
	return respawn_iframes_remaining > 0.0


## True when any source of invincibility is currently active.
func is_invincible() -> bool:
	return current_state in [
		State.GETUP_INVINCIBLE,
		State.GRABBED,
		State.WAKEUP_ROLL,
	] or is_knockdown_invincible() or is_dash_invincible() or is_respawn_invincible() or is_slow_getup_invincible() or is_wakeup_attack_invincible()


## True during the invincible early window of a slow get-up.
func is_slow_getup_invincible() -> bool:
	if current_state != State.SLOW_GETUP:
		return false
	return state_time < CombatTiming.scale_time((_fighter as Fighter).stats.slow_getup_invincible_duration)


## True when the fighter can be punished (punish window, dash recovery, or exposed grounded knockdown).
func is_vulnerable() -> bool:
	if is_in_punish_window():
		return true
	if is_dash_vulnerable():
		return true
	return is_knocked_down() and knockdown_landed and not is_knockdown_invincible()


## True while the okizeme punish window is open.
func is_in_punish_window() -> bool:
	return oki_punish_time_left > 0.0


## True unless dead.
func is_active_in_match() -> bool:
	return current_state != State.DEAD


## True when falling off the stage should be lethal (not while dead, respawning, or on a ledge).
func can_die_from_fall_off_stage() -> bool:
	return current_state not in [State.DEAD, State.RESPAWN, State.LEDGE_RECOVERY]


## Transitions to next_state, tearing down attack/grab/dash/charge bookkeeping for the
## state being left and notifying the fighter.
func change_state(next_state: State) -> void:
	if current_state == next_state:
		return
	if current_attack != null and next_state != State.ATTACK:
		current_attack = null
		attack_contact = ATTACK_CONTACT_NONE
		attack_recovery_frames = 0
		attack_landing_lag_time = 0.0
		attack_landing_lag_applied = false
		(_fighter as Fighter).set_hitbox_active(false)
	if current_state == State.GRAB and next_state != State.GRAB:
		_release_grab_victim()
		current_grab = null
		grab_landed = false
		grab_in_recovery = false
		grab_whiffed = false
		clear_oki_punish_window()
		(_fighter as Fighter).set_grabbox_active(false)
	if current_state == State.GRABBED and next_state != State.GRABBED:
		grabbed_by = null
	if current_state == State.DASH:
		dash_in_recovery = false
		if next_state != State.ATTACK:
			dash_attack_buffered = false
	if current_state == State.PROJECTILE_CHARGE and next_state != State.PROJECTILE_CHARGE:
		projectile_charge_time = 0.0
		projectile_startup_remaining = 0.0
		projectile_pending_low = false
		var fighter := _fighter as Fighter
		if fighter != null:
			fighter._projectile_launcher.reset()
	current_state = next_state
	state_time = 0.0
	attack_frame = 0
	_fighter.on_state_changed(next_state)


## Starts an attack, resetting attack bookkeeping; keeps the crouch state for crouch-preserving attacks.
func start_attack(attack_data: Resource) -> void:
	attack_hit_serial += 1
	current_attack = attack_data
	attack_contact = ATTACK_CONTACT_NONE
	attack_recovery_frames = 0
	attack_landing_lag_time = 0.0
	attack_landing_lag_applied = false
	attack_frame = 0
	state_time = 0.0
	combo_follow_up_buffered = null
	var attack := attack_data as AttackData
	var fighter := _fighter as Fighter
	if attack != null and attack.keeps_crouch and (is_crouching() or fighter.is_crouch_held()):
		if not is_crouching():
			change_state(State.CROUCH)
		# change_state(CROUCH) clears current_attack; restore it for _tick_attack.
		current_attack = attack_data
		attack_contact = ATTACK_CONTACT_NONE
		attack_recovery_frames = 0
		attack_landing_lag_time = 0.0
		attack_landing_lag_applied = false
		attack_frame = 0
		state_time = 0.0
		fighter._update_hurtbox_profile()
		fighter.on_attack_started()
		return
	change_state(State.ATTACK)
	fighter.on_attack_started()


## True when a projectile can be started now (alive, off-ledge, has a config, and accepting input).
func can_use_projectile() -> bool:
	if not is_active_in_match():
		return false
	if is_on_ledge():
		return false
	var fighter := _fighter as Fighter
	if fighter.stats.projectile_config == null:
		return false
	return can_accept_input()


## Enters the projectile charge state, optionally aiming low.
func begin_projectile_charge(low_angle: bool = false) -> void:
	projectile_charge_time = 0.0
	projectile_startup_remaining = 0.0
	projectile_pending_low = low_angle
	change_state(State.PROJECTILE_CHARGE)


## Advances projectile startup then charge time while charging; call each frame.
func tick_projectile_charge(delta: float) -> void:
	if current_state != State.PROJECTILE_CHARGE:
		return
	if projectile_startup_remaining > 0.0:
		projectile_startup_remaining = maxf(0.0, projectile_startup_remaining - delta)
		if projectile_startup_remaining <= 0.0:
			(_fighter as Fighter).complete_projectile_startup()
		return
	projectile_charge_time += delta


## Logarithmic damage charge ratio for the time held (0 if no config).
func get_projectile_charge_ratio() -> float:
	var config := (_fighter as Fighter).stats.projectile_config
	if config == null:
		return 0.0
	return config.get_charge_ratio(projectile_charge_time)


## Fraction of max charge TIME held (linear), unlike the logarithmic damage ratio.
func get_projectile_charge_time_fraction() -> float:
	var config := (_fighter as Fighter).stats.projectile_config
	if config == null:
		return 0.0
	var scaled_max := CombatTiming.scale_time(config.max_charge_time)
	if scaled_max <= 0.0:
		return 0.0
	return clampf(projectile_charge_time / scaled_max, 0.0, 1.0)


## True once charge time has reached the configured maximum.
func is_projectile_fully_charged() -> bool:
	var config := (_fighter as Fighter).stats.projectile_config
	if config == null:
		return false
	return projectile_charge_time >= CombatTiming.scale_time(config.max_charge_time)


## True once charging has begun accumulating, so the charge can no longer be cancelled freely.
func is_projectile_committed() -> bool:
	return (
		current_state == State.PROJECTILE_CHARGE
		and (
			projectile_charge_time > 0.0
			or projectile_startup_remaining > 0.0
		)
	)


## Locks in the charge ratio and begins startup before the shot fires.
func begin_projectile_release(charge_ratio: float) -> void:
	projectile_pending_charge = clampf(charge_ratio, 0.0, 1.0)
	projectile_charge_time = 0.0
	var config := (_fighter as Fighter).stats.projectile_config
	if config != null:
		projectile_startup_remaining = CombatTiming.frames_to_seconds(config.startup_frames)
	else:
		projectile_startup_remaining = 0.0
		(_fighter as Fighter).complete_projectile_startup()


## True if the pending shot is aimed low.
func is_projectile_low_angle() -> bool:
	return projectile_pending_low


## Completes startup: clears the pending charge, applies recovery, and returns to standing.
func finish_projectile_startup() -> void:
	projectile_pending_charge = 0.0
	projectile_pending_low = false
	var config := (_fighter as Fighter).stats.projectile_config
	if config != null:
		projectile_recovery_remaining = CombatTiming.frames_to_seconds(config.recovery_frames)
	(_fighter as Fighter).resolve_standing_state()


## Marks the current attack as having hit; buffers its auto-combo follow-up on an airborne juggle.
func register_attack_hit(victim: Fighter = null) -> void:
	if current_attack == null:
		return
	attack_contact = ATTACK_CONTACT_HIT
	var attack := current_attack as AttackData
	if attack == null:
		return
	var can_continue_juggle := (
		victim != null
		and not victim.is_on_floor()
		and victim.state_machine.current_state == State.STAGGER
	)
	if attack.auto_combo_on_hit and attack.combo_follow_up != null and can_continue_juggle:
		combo_follow_up_buffered = attack.combo_follow_up


## Marks the current attack as blocked, unless it has already registered a hit.
func register_attack_blocked() -> void:
	if current_attack == null:
		return
	if attack_contact != ATTACK_CONTACT_HIT:
		attack_contact = ATTACK_CONTACT_BLOCK


## Starts a grab attempt with the given grab data.
func start_grab(grab_data: Resource) -> void:
	current_grab = grab_data
	grab_landed = false
	grab_in_recovery = false
	grab_whiffed = false
	grab_victim = null
	change_state(State.GRAB)


## Latches onto a grabbed victim and restarts the state timer for the hold.
func begin_grab_hold(victim: Fighter) -> void:
	if current_grab == null:
		return
	grab_landed = true
	grab_in_recovery = false
	grab_victim = victim
	(_fighter as Fighter).set_grabbox_active(false)
	state_time = 0.0


## Throws the held victim in the given direction and enters grab recovery.
func execute_throw_release(throw_direction: int) -> void:
	if current_grab == null or grab_victim == null:
		return
	var victim := grab_victim
	var grab_data := current_grab
	var throw_vector := throw_direction * (_fighter as Fighter).facing
	grab_victim = null
	grab_landed = false
	grab_in_recovery = true
	grab_whiffed = false
	victim.apply_throw_from(_fighter as Fighter, grab_data, throw_vector)
	state_time = CombatTiming.frames_to_seconds(grab_data.startup_frames + grab_data.active_frames)


## Releases the currently held victim.
func release_held_grab() -> void:
	_release_grab_victim()


## Enters the grabbed state under thrower; records whether the throw lands as a lethal punish.
func enter_grabbed(thrower: Fighter, grab_data: Resource) -> void:
	grabbed_by = thrower
	current_grab = grab_data
	lethal_punish_throw = is_in_punish_window()
	change_state(State.GRABBED)


## Leaves the grabbed state and returns to standing.
func release_from_grab() -> void:
	if current_state != State.GRABBED:
		return
	grabbed_by = null
	current_grab = null
	lethal_punish_throw = false
	(_fighter as Fighter).resolve_standing_state()


## Starts a dash in the given direction.
func start_dash(direction: int) -> void:
	dash_direction = direction
	dash_in_recovery = false
	dash_attack_buffered = false
	change_state(State.DASH)


## Buffers a dash-attack during the dash's active window.
func buffer_dash_attack() -> void:
	if current_state != State.DASH or dash_in_recovery:
		return
	dash_attack_buffered = true


## Starts a buffered dash-attack if grounded, facing the dash direction; returns whether it fired.
func try_start_buffered_dash_attack() -> bool:
	if not dash_attack_buffered:
		return false
	dash_attack_buffered = false
	dash_in_recovery = false
	var fighter := _fighter as Fighter
	if not fighter.is_on_floor():
		return false
	fighter.facing = dash_direction
	fighter.facing_pivot.scale.x = float(dash_direction)
	start_attack(fighter.get_dash_attack())
	return true


## Launches into knockdown with the given impulse, resetting knockdown bookkeeping and lie direction.
func begin_knockdown_impulse(
	impulse: Vector2,
	from_throw: bool = false,
	started_airborne: bool = false
) -> void:
	reset_stagger_meter()
	knockdown_velocity = impulse
	knockdown_landed = false
	knockdown_from_throw = from_throw
	knockdown_was_airborne = false
	knockdown_started_in_air = started_airborne
	knockdown_left_ground = false
	knockdown_landed_at = 0.0
	has_buffered_prone_wakeup = false
	clear_oki_punish_window()
	knockdown_lie_direction = int(signf(impulse.x))
	if knockdown_lie_direction == 0:
		knockdown_lie_direction = signi((_fighter as Fighter).facing)
		if knockdown_lie_direction == 0:
			knockdown_lie_direction = 1
	change_state(State.KNOCKDOWN)
	_fighter.velocity = impulse


## Enters (or refreshes) stagger hitstun with the given knockback and optional duration and vertical launch.
func enter_stagger(
	horizontal_kb: float,
	hitstun_seconds: float = -1.0,
	vertical_kb: float = 0.0
) -> void:
	hitstun_velocity_x = horizontal_kb
	stun_started_airborne = false
	clear_oki_punish_window()
	var fighter := _fighter as Fighter
	if hitstun_seconds < 0.0:
		stagger_hitstun_duration = CombatTiming.scale_time(fighter.stats.stagger_hitstun_duration)
	else:
		stagger_hitstun_duration = CombatTiming.scaled_hitstun(hitstun_seconds)
	if current_state == State.STAGGER:
		state_time = 0.0
	else:
		change_state(State.STAGGER)
	if fighter.is_on_floor():
		fighter.velocity = Vector2(horizontal_kb, vertical_kb)
	else:
		fighter.velocity.x = horizontal_kb
		if vertical_kb != 0.0:
			fighter.velocity.y = vertical_kb


## 0..1 progress through stagger hitstun (1 if not staggering).
func get_stagger_hitstun_progress() -> float:
	if current_state != State.STAGGER or stagger_hitstun_duration <= 0.0:
		return 1.0
	return clampf(state_time / stagger_hitstun_duration, 0.0, 1.0)


## Enters the heavier stun state with knockback, optionally spiking an airborne victim downward.
func enter_stun(horizontal_kb: float, spike_in_air: bool) -> void:
	reset_stagger_meter()
	hitstun_velocity_x = horizontal_kb
	stun_started_airborne = not _fighter.is_on_floor()
	clear_oki_punish_window()
	change_state(State.STUN)
	var fighter := _fighter as Fighter
	if fighter.is_on_floor():
		fighter.velocity = Vector2(horizontal_kb, 0.0)
	else:
		fighter.velocity.x = horizontal_kb
		if spike_in_air:
			fighter.velocity.y = maxf(fighter.velocity.y, fighter.stats.stun_air_spike_velocity)


## On landing during an attack's active frames, applies that attack's landing lag. Call on floor-state changes.
func update_attack_landing(was_on_floor: bool, is_on_floor: bool) -> void:
	if current_attack == null or attack_landing_lag_applied:
		return
	if was_on_floor or not is_on_floor:
		return

	var attack := current_attack as AttackData
	var frame := CombatTiming.seconds_to_frame(state_time)
	var active_start := attack.startup_frames
	var active_end := attack.startup_frames + attack.active_frames
	if frame < active_start or frame >= active_end:
		return

	_apply_attack_landing_lag(attack)


## Tracks airborne stun and zeroes downward velocity on landing; call each frame while stunned.
func update_stun_landing() -> void:
	if current_state != State.STUN:
		return
	if not _fighter.is_on_floor():
		stun_started_airborne = true
	elif stun_started_airborne:
		_fighter.velocity.y = 0.0


## Detects the knockdown landing, marking it landed and triggering death or the landing callback.
func update_knockdown_landing() -> void:
	if current_state != State.KNOCKDOWN or knockdown_landed:
		return
	if not _fighter.is_on_floor():
		knockdown_was_airborne = true
		knockdown_left_ground = true
	elif knockdown_started_in_air or knockdown_left_ground:
		var lethal := knockdown_from_throw and lethal_punish_throw
		knockdown_landed = true
		knockdown_landed_at = state_time
		knockdown_from_throw = false
		lethal_punish_throw = false
		if lethal:
			(_fighter as Fighter)._kill()
		else:
			(_fighter as Fighter).on_knockdown_landed()


## True while still falling during respawn.
func is_respawn_falling() -> bool:
	return current_state == State.RESPAWN and respawn_falling


## Enters the respawn fall.
func enter_respawn() -> void:
	respawn_falling = true
	respawn_iframes_remaining = 0.0
	change_state(State.RESPAWN)


## Ends the respawn fall and starts post-respawn invincibility.
func land_respawn() -> void:
	if current_state != State.RESPAWN or not respawn_falling:
		return
	respawn_falling = false
	respawn_iframes_remaining = RESPAWN_INVINCIBLE_DURATION
	state_time = 0.0


## Enters the dead state.
func enter_dead() -> void:
	respawn_falling = false
	respawn_iframes_remaining = 0.0
	change_state(State.DEAD)


## True during get-up when a wakeup follow-up can be buffered.
func can_buffer_wakeup_followup() -> bool:
	return current_state in [State.GETUP_INVINCIBLE, State.SLOW_GETUP]


## Queues the wakeup follow-up action, ignoring roll and slow options.
func set_wakeup_followup(option: WakeupOption) -> void:
	if option in [WakeupOption.ROLL_LEFT, WakeupOption.ROLL_RIGHT, WakeupOption.SLOW]:
		return
	pending_wakeup_followup = option


## True when grounded in knockdown, so knockdown wakeup options are available.
func can_use_knockdown_wakeup_options() -> bool:
	return current_state == State.KNOCKDOWN and knockdown_landed


## True while on a ledge, so ledge get-up options are available.
func can_use_ledge_wakeup_options() -> bool:
	return current_state == State.LEDGE_RECOVERY


## Ends grounded knockdown invincibility early by backdating the landing time.
func forfeit_knockdown_invincibility() -> void:
	if current_state != State.KNOCKDOWN or not knockdown_landed:
		return
	knockdown_landed_at = state_time - KNOCKDOWN_GROUND_INVINCIBLE_DURATION


## Cuts a get-up short, completing the wakeup transition immediately.
func complete_wakeup_early() -> void:
	if current_state in [State.GETUP_INVINCIBLE, State.SLOW_GETUP]:
		_complete_wakeup_transition()


## Begins a wakeup from knockdown, buffering it if still in the forced-ground window; returns whether it started.
func begin_knockdown_wakeup(option: WakeupOption) -> bool:
	if not can_use_knockdown_wakeup_options():
		return false
	if is_knockdown_forced_ground():
		return buffer_prone_wakeup(option)
	return _begin_wakeup(option, false)


## Begins a get-up from the ledge; returns whether it started.
func begin_ledge_wakeup(option: WakeupOption) -> bool:
	if not can_use_ledge_wakeup_options():
		return false
	return _begin_wakeup(option, true)


## Attempts a neutral fast get-up from knockdown.
func try_fast_get_up() -> bool:
	return begin_knockdown_wakeup(WakeupOption.NEUTRAL)


## Enters ledge recovery on the given side, snapping the fighter to the ledge.
func enter_ledge_recovery(side: int) -> void:
	ledge_side = side
	pending_wakeup_followup = WakeupOption.NEUTRAL
	wakeup_roll_from_ledge = false
	change_state(State.LEDGE_RECOVERY)
	var fighter := _fighter as Fighter
	fighter.snap_to_ledge(side)
	fighter.velocity = Vector2.ZERO


## Converts an in-progress wakeup roll into ledge recovery on the given side.
func snap_wakeup_roll_to_ledge(side: int) -> void:
	if current_state != State.WAKEUP_ROLL:
		return
	pending_wakeup_followup = WakeupOption.NEUTRAL
	wakeup_roll_from_ledge = false
	_fighter.velocity = Vector2.ZERO
	enter_ledge_recovery(side)


## True if a ledge get-up is currently available.
func try_ledge_get_up() -> bool:
	return can_use_ledge_wakeup_options()


## Begins a neutral get-up from the ledge.
func begin_ledge_get_up() -> bool:
	return begin_ledge_wakeup(WakeupOption.NEUTRAL)


## Advances the state machine each frame: decays timers and runs per-state timeouts and transitions.
func tick(delta: float) -> void:
	if projectile_recovery_remaining > 0.0:
		projectile_recovery_remaining = maxf(0.0, projectile_recovery_remaining - delta)

	if oki_punish_time_left > 0.0:
		oki_punish_time_left = maxf(0.0, oki_punish_time_left - delta)

	if respawn_iframes_remaining > 0.0:
		respawn_iframes_remaining = maxf(0.0, respawn_iframes_remaining - delta)

	if current_state != State.PROJECTILE_CHARGE and projectile_startup_remaining > 0.0:
		projectile_startup_remaining = 0.0

	if attack_landing_lag_time > 0.0:
		attack_landing_lag_time = maxf(0.0, attack_landing_lag_time - delta)
	else:
		state_time += delta
	match current_state:
		State.ATTACK, State.CROUCH, State.CROUCH_BLOCK:
			if current_attack != null:
				_tick_attack()
		State.GRAB:
			_tick_grab()
		State.GRABBED:
			pass
		State.DASH:
			if dash_in_recovery:
				if state_time >= CombatTiming.scale_time((_fighter as Fighter).stats.dash_recovery_duration):
					if (_fighter as Fighter).try_execute_action_queue():
						return
					(_fighter as Fighter).resolve_standing_state()
			elif state_time >= get_dash_active_duration():
				(_fighter as Fighter).finish_dash()
				if try_start_buffered_dash_attack():
					return
				var recovery: float = CombatTiming.scale_time(
					(_fighter as Fighter).stats.dash_recovery_duration
				)
				if recovery > 0.0:
					dash_in_recovery = true
					state_time = 0.0
				else:
					(_fighter as Fighter).resolve_standing_state()
		State.KNOCKDOWN:
			if knockdown_landed and get_knockdown_ground_time() >= KNOCKDOWN_GROUND_AUTO_GETUP_DELAY:
				if has_buffered_prone_wakeup:
					try_execute_buffered_prone_wakeup()
				else:
					_fighter.perform_fast_get_up()
		State.STAGGER:
			if state_time >= stagger_hitstun_duration:
				reset_stagger_meter()
				if (_fighter as Fighter).try_execute_action_queue():
					return
				(_fighter as Fighter).resolve_standing_state()
		State.STUN:
			if state_time >= CombatTiming.scale_time((_fighter as Fighter).stats.stun_hitstun_duration):
				if (_fighter as Fighter).try_execute_action_queue():
					return
				(_fighter as Fighter).resolve_standing_state()
		State.GETUP_INVINCIBLE:
			if state_time >= getup_invincible_duration:
				_complete_wakeup_transition()
		State.SLOW_GETUP:
			if state_time >= CombatTiming.scale_time((_fighter as Fighter).stats.slow_getup_duration):
				_complete_wakeup_transition()
		State.WAKEUP_ROLL:
			if state_time >= get_wakeup_roll_duration():
				_complete_wakeup_transition()
		State.RESPAWN:
			if not respawn_falling and respawn_iframes_remaining <= 0.0:
				(_fighter as Fighter).resolve_standing_state()


## Resolves the neutral ground state (idle/move/block/crouch) from movement and input, when no action is in progress.
func update_ground_state(
	is_moving: bool,
	is_on_floor: bool,
	is_guarding: bool,
	is_crouching_input: bool
) -> void:
	if current_state == State.PROJECTILE_CHARGE:
		return
	if projectile_startup_remaining > 0.0:
		return
	if projectile_recovery_remaining > 0.0:
		return
	if current_attack != null:
		return
	if current_state == State.RESPAWN:
		if respawn_falling:
			return
	elif current_state == State.LEDGE_RECOVERY:
		return
	elif current_state not in [State.IDLE, State.MOVE, State.BLOCK, State.CROUCH, State.CROUCH_BLOCK]:
		return
	if not is_on_floor:
		if current_state in [State.IDLE, State.MOVE, State.BLOCK, State.CROUCH, State.CROUCH_BLOCK]:
			var fighter := _fighter as Fighter
			if not fighter.is_ledge_crouch_airborne() and not fighter.should_preserve_crouch_air_state():
				change_state(State.IDLE)
		return
	if is_crouching_input:
		if is_guarding:
			change_state(State.CROUCH_BLOCK)
		else:
			change_state(State.CROUCH)
	elif is_guarding:
		change_state(State.BLOCK)
	elif is_moving:
		change_state(State.MOVE)
	else:
		change_state(State.IDLE)

#endregion


#region Private helpers

func _release_grab_victim() -> void:
	if grab_victim != null:
		grab_victim.release_from_grab()
		grab_victim = null


func _apply_attack_landing_lag(attack: AttackData) -> void:
	var fighter := _fighter as Fighter
	var lag_frames := attack.landing_lag_frames
	if lag_frames < 0:
		if not attack.id.begins_with("air_"):
			return
		lag_frames = fighter.stats.air_attack_landing_lag_frames
	if lag_frames <= 0:
		return

	attack_landing_lag_applied = true
	attack_landing_lag_time = CombatTiming.frames_to_seconds(lag_frames)
	state_time = CombatTiming.frames_to_seconds(attack.startup_frames + attack.active_frames)
	attack_recovery_frames = 0
	fighter.set_hitbox_active(false)
	if fighter.is_on_floor():
		fighter.velocity.y = 0.0


func _begin_wakeup(option: WakeupOption, from_ledge: bool) -> bool:
	var fighter := _fighter as Fighter
	getup_from_ledge = from_ledge
	wakeup_roll_from_ledge = false
	fighter.rotation_degrees = 0.0
	fighter._reset_facing_pivot_transform()
	fighter.velocity = Vector2.ZERO
	fighter.start_ledge_regrab_lockout()
	clear_oki_punish_window()
	if not from_ledge and is_knockdown_invincible():
		forfeit_knockdown_invincibility()

	match option:
		WakeupOption.ROLL_LEFT:
			pending_wakeup_followup = WakeupOption.NEUTRAL
			wakeup_roll_direction = -1
			_setup_wakeup_roll(fighter, from_ledge)
			change_state(State.WAKEUP_ROLL)
		WakeupOption.ROLL_RIGHT:
			pending_wakeup_followup = WakeupOption.NEUTRAL
			wakeup_roll_direction = 1
			_setup_wakeup_roll(fighter, from_ledge)
			change_state(State.WAKEUP_ROLL)
		WakeupOption.SLOW:
			pending_wakeup_followup = WakeupOption.NEUTRAL
			getup_invincible_duration = fighter.stats.slow_getup_duration
			if from_ledge:
				_setup_ledge_climb_target()
			change_state(State.SLOW_GETUP)
		WakeupOption.ATTACK:
			pending_wakeup_followup = WakeupOption.ATTACK
			getup_invincible_duration = GETUP_INVINCIBLE_DURATION
			if from_ledge:
				_setup_ledge_climb_target()
			change_state(State.GETUP_INVINCIBLE)
		WakeupOption.BLOCK:
			pending_wakeup_followup = WakeupOption.BLOCK
			getup_invincible_duration = GETUP_INVINCIBLE_DURATION
			if from_ledge:
				_setup_ledge_climb_target()
			change_state(State.GETUP_INVINCIBLE)
		WakeupOption.GRAB:
			pending_wakeup_followup = WakeupOption.GRAB
			getup_invincible_duration = GETUP_INVINCIBLE_DURATION
			if from_ledge:
				_setup_ledge_climb_target()
			change_state(State.GETUP_INVINCIBLE)
		WakeupOption.CROUCH:
			pending_wakeup_followup = WakeupOption.CROUCH
			getup_invincible_duration = GETUP_INVINCIBLE_DURATION
			if from_ledge:
				_setup_ledge_climb_target()
			change_state(State.GETUP_INVINCIBLE)
		WakeupOption.JUMP:
			pending_wakeup_followup = WakeupOption.JUMP
			getup_invincible_duration = GETUP_INVINCIBLE_DURATION
			if from_ledge:
				_setup_ledge_climb_target()
			change_state(State.GETUP_INVINCIBLE)
		_:
			pending_wakeup_followup = WakeupOption.NEUTRAL
			getup_invincible_duration = GETUP_INVINCIBLE_DURATION
			if from_ledge:
				_setup_ledge_climb_target()
			change_state(State.GETUP_INVINCIBLE)
	return true


func _setup_wakeup_roll(fighter: Fighter, from_ledge: bool) -> void:
	var roll_inward := from_ledge and wakeup_roll_direction == -ledge_side
	if roll_inward:
		wakeup_roll_from_ledge = true
		ledge_climb_start = fighter.global_position
		var fm := fighter.fight_manager
		var target_x := (
			ledge_climb_start.x + float(wakeup_roll_direction) * fighter.stats.wakeup_roll_distance
		)
		var target_y := fm.get_ground_y(target_x) if fm != null else ledge_climb_start.y
		ledge_climb_target = Vector2(target_x, target_y)
	else:
		_setup_ground_wakeup_roll(fighter)


func _setup_ledge_climb_target() -> void:
	var fighter := _fighter as Fighter
	var fm := fighter.fight_manager
	ledge_climb_start = fighter.global_position
	var target_x := ledge_climb_start.x - float(ledge_side) * 18.0
	var target_y := fm.get_ground_y(target_x) if fm != null else ledge_climb_start.y
	ledge_climb_target = Vector2(target_x, target_y)


func _setup_ground_wakeup_roll(fighter: Fighter) -> void:
	wakeup_roll_from_ledge = false
	wakeup_roll_start_pos = fighter.global_position
	var target_x := (
		wakeup_roll_start_pos.x + float(wakeup_roll_direction) * fighter.stats.wakeup_roll_distance
	)
	var target_y := wakeup_roll_start_pos.y
	if fighter.fight_manager != null:
		target_y = fighter.fight_manager.get_ground_y(target_x)
	wakeup_roll_target_pos = Vector2(target_x, target_y)


func _complete_wakeup_transition() -> void:
	var fighter := _fighter as Fighter
	var followup := pending_wakeup_followup
	pending_wakeup_followup = WakeupOption.NEUTRAL
	var was_ledge := getup_from_ledge
	getup_from_ledge = false
	wakeup_roll_from_ledge = false
	fighter.rotation_degrees = 0.0

	if was_ledge and fighter.fight_manager != null:
		fighter.global_position.y = fighter.fight_manager.get_ground_y(fighter.global_position.x)

	begin_oki_punish_window()

	match followup:
		WakeupOption.BLOCK:
			if fighter.is_guard_held():
				change_state(State.BLOCK)
			else:
				fighter.resolve_standing_state()
		WakeupOption.ATTACK:
			fighter.resolve_standing_state()
			fighter.perform_wakeup_followup_attack()
		WakeupOption.JUMP:
			fighter.resolve_standing_state()
			fighter.velocity.y = fighter.stats.jump_velocity
			change_state(State.IDLE)
		WakeupOption.CROUCH:
			change_state(State.CROUCH)
		WakeupOption.GRAB:
			fighter.resolve_standing_state()
			fighter.perform_wakeup_followup_grab()
		_:
			fighter.resolve_standing_state()


func _get_attack_max_frames(attack: AttackData) -> int:
	return (
		attack.startup_frames
		+ attack.active_frames
		+ maxi(
			attack.recovery_frames_whiff,
			maxi(attack.recovery_frames_hit, attack.recovery_frames_block)
		)
		+ 12
	)


func _finish_attack() -> void:
	current_attack = null
	attack_contact = ATTACK_CONTACT_NONE
	attack_recovery_frames = 0
	attack_landing_lag_time = 0.0
	attack_landing_lag_applied = false
	(_fighter as Fighter).set_hitbox_active(false)
	if (_fighter as Fighter).try_execute_action_queue():
		return
	(_fighter as Fighter).resolve_standing_state()
	(_fighter as Fighter)._ensure_not_orphaned_action_state()


func _tick_attack() -> void:
	if current_attack == null:
		_finish_attack()
		return

	if attack_landing_lag_time > 0.0:
		(_fighter as Fighter).set_hitbox_active(false)
		return

	var attack: AttackData = current_attack
	var startup_frames: int = attack.startup_frames
	var active_frames: int = attack.active_frames
	var frame := CombatTiming.seconds_to_frame(state_time)
	var active_end_frame: int = startup_frames + active_frames

	if frame > _get_attack_max_frames(attack):
		_finish_attack()
		return

	if frame < startup_frames:
		_fighter.set_hitbox_active(false)
	elif frame < active_end_frame:
		if attack_frame != frame:
			attack_frame = frame
			if frame == startup_frames:
				_fighter.set_hitbox_active(true)
	else:
		_fighter.set_hitbox_active(false)
		if attack_recovery_frames == 0:
			var outcome := AttackData.RecoveryOutcome.WHIFF
			match attack_contact:
				ATTACK_CONTACT_HIT:
					outcome = AttackData.RecoveryOutcome.HIT
				ATTACK_CONTACT_BLOCK:
					outcome = AttackData.RecoveryOutcome.BLOCK
			attack_recovery_frames = attack.get_recovery_frames(outcome)

	var link_frame := attack.get_combo_link_frame()
	var recovery_end_frame := active_end_frame + attack_recovery_frames
	if frame >= link_frame and frame < recovery_end_frame:
		var next_attack := (_fighter as Fighter).consume_combo_follow_up()
		if next_attack != null:
			start_attack(next_attack)
			return

	if frame >= recovery_end_frame:
		_finish_attack()


func _tick_grab() -> void:
	if current_grab == null:
		(_fighter as Fighter).resolve_standing_state()
		return

	var grab := current_grab as GrabData
	var recovery_start_frames: int = grab.startup_frames + grab.active_frames
	var recovery_frames := (
		grab.whiff_recovery_frames if grab_whiffed else grab.recovery_frames
	)
	var total_frames: int = recovery_start_frames + recovery_frames
	var frame := CombatTiming.seconds_to_frame(state_time)

	if grab_in_recovery:
		(_fighter as Fighter).set_grabbox_active(false)
		if frame >= total_frames:
			current_grab = null
			grab_in_recovery = false
			grab_whiffed = false
			clear_oki_punish_window()
			(_fighter as Fighter).set_grabbox_active(false)
			(_fighter as Fighter).resolve_standing_state()
		return

	if grab_landed and grab_victim != null:
		(_fighter as Fighter).set_grabbox_active(false)
		return

	if frame < grab.startup_frames:
		(_fighter as Fighter).set_grabbox_active(false)
	elif frame < recovery_start_frames:
		(_fighter as Fighter).set_grabbox_active(true)
	elif not grab_landed and not grab_in_recovery:
		grab_in_recovery = true
		grab_whiffed = true
		state_time = CombatTiming.frames_to_seconds(recovery_start_frames)
		(_fighter as Fighter).set_grabbox_active(false)
		return
	else:
		(_fighter as Fighter).set_grabbox_active(false)

#endregion
