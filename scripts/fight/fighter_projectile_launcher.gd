extends Node
class_name FighterProjectileLauncher

## Handles projectile charging, release, and firing for a Fighter.
## Inert when the owning fighter's stats carry no projectile_config.
##
## _fighter is typed CharacterBody2D (not Fighter) to break the circular class_name
## dependency: Fighter references FighterProjectileLauncher, so the reverse reference
## must use the built-in base type. Cast to Fighter locally inside each method.


#region Constants

# Charge time fraction at which the half-charge flash fires.
const CHARGE_FLASH_TIME_FRACTION := 0.5

#endregion


#region Private state

var _fighter: CharacterBody2D
var _projectile_charging: bool = false
var _projectile_auto_release: bool = false
var _await_projectile_release: bool = false
var _charge_half_flashed: bool = false
var _virtual_charge: float = -1.0
var _virtual_low: bool = false

#endregion


#region Public API

## Binds the owning fighter. Call once from Fighter._ready() before the first tick.
func setup(fighter: CharacterBody2D) -> void:
	_fighter = fighter


## Processes one physics frame of projectile input and charge state.
func tick(delta: float) -> void:
	var f := _fighter as Fighter
	if f.state_machine.current_state == FighterStateMachine.State.PROJECTILE_CHARGE:
		f.state_machine.tick_projectile_charge(delta)
		if f.state_machine.projectile_startup_remaining > 0.0:
			return
		if not _charge_half_flashed and f.state_machine.get_projectile_charge_time_fraction() >= CHARGE_FLASH_TIME_FRACTION:
			_charge_half_flashed = true
			f.pulse_charge_flash()
		if _projectile_auto_release and not _is_pressed(f):
			_release_charge(f)
			return
		var fully_charged := f.state_machine.is_projectile_fully_charged()
		if _is_released(f) or fully_charged:
			# A full-charge shot auto-fires; require a button release before the next
			# charge so a continued hold can't immediately spawn a second projectile.
			if fully_charged:
				_await_projectile_release = true
			_release_charge(f)
		return

	if _projectile_charging:
		_projectile_charging = false

	if not f.state_machine.can_use_projectile():
		return
	if f.stats.projectile_config == null:
		return
	if _virtual_charge >= 0.0:
		return
	if f.is_attack_intent_held():
		return
	if _await_projectile_release:
		if not _is_pressed(f):
			_await_projectile_release = false
		return
	if _is_pressed(f):
		_projectile_auto_release = Input.is_action_just_pressed("projectile")
		f.clear_air_forward_combo()
		f.state_machine.begin_projectile_charge(f.is_down_pressed())
		_projectile_charging = true
		_charge_half_flashed = false


## Resets all charging state; call when the fighter respawns.
func reset() -> void:
	_projectile_charging = false
	_projectile_auto_release = false


## Queues a virtual projectile fire for AI or replay. Charge < 0 leaves it unchanged.
func set_virtual_fire(charge: float, low: bool) -> void:
	if charge >= 0.0:
		_virtual_charge = charge
	if low:
		_virtual_low = true


## Clears virtual projectile input back to neutral.
func clear_virtual_fire() -> void:
	_virtual_charge = -1.0
	_virtual_low = false


## Consumes a pending virtual fire command. Returns true if one was consumed.
func consume_virtual_fire() -> bool:
	var f := _fighter as Fighter
	if _virtual_charge < 0.0:
		return false
	if not f.state_machine.can_use_projectile():
		_virtual_charge = -1.0
		return false
	var charge := clampf(_virtual_charge, 0.0, 1.0)
	_virtual_charge = -1.0
	f.state_machine.begin_projectile_charge(_virtual_low)
	f.state_machine.begin_projectile_release(charge)
	_virtual_low = false
	return true


## Fires the currently charged projectile. Called by Fighter.complete_projectile_startup().
func fire_charged() -> void:
	var f := _fighter as Fighter
	var low_angle := f.state_machine.is_projectile_low_angle()
	_fire(f, f.state_machine.projectile_pending_charge, low_angle)
	f.state_machine.finish_projectile_startup()


## Begins a projectile charge from the input buffer. Called by Fighter._execute_buffered_intent().
func begin_buffered_charge(low_angle: bool) -> void:
	var f := _fighter as Fighter
	_projectile_auto_release = not Input.is_action_pressed("projectile")
	f.clear_air_forward_combo()
	f.state_machine.begin_projectile_charge(low_angle)
	_projectile_charging = true

#endregion


#region Private helpers

func _release_charge(f: Fighter) -> void:
	var charge_ratio := f.state_machine.get_projectile_charge_ratio()
	f.state_machine.begin_projectile_release(charge_ratio)
	_projectile_charging = false
	_projectile_auto_release = false


func _fire(f: Fighter, charge_ratio: float, low_angle: bool = false) -> void:
	if f.stats.projectile_config == null:
		return
	var projectile := f.stats.projectile_config.projectile_scene.instantiate() as FightProjectile
	f.get_parent().add_child(projectile)
	var spawn := _resolve_spawn(f, low_angle)
	projectile.setup(f, charge_ratio, f.stats.projectile_config, low_angle, spawn)
	if f.is_debug_enabled():
		projectile.set_debug_visible(true)


# Returns the world-space spawn position. Reads ProjectileOrigin from the visual rig when
# present; falls back to the config offset so rigs without the marker are unaffected.
func _resolve_spawn(f: Fighter, low_angle: bool) -> Vector2:
	var rig := f.get_rig()
	if rig != null:
		var marker := rig.get_node_or_null(^"ProjectileOrigin") as Marker2D
		if marker != null:
			return marker.global_position
	var config := f.stats.projectile_config
	var on_floor := f.is_on_floor()
	var offset: Vector2
	if low_angle:
		offset = config.low_spawn_offset if on_floor else config.air_low_spawn_offset
	else:
		offset = config.spawn_offset if on_floor else config.air_spawn_offset
	return f.global_position + Vector2(offset.x * f.facing, offset.y)


func _is_pressed(f: Fighter) -> bool:
	if not f.is_player_controlled:
		return false
	if Input.is_action_pressed("attack"):
		return false
	return Input.is_action_pressed("projectile")


func _is_released(f: Fighter) -> bool:
	if not f.is_player_controlled:
		return false
	return Input.is_action_just_released("projectile")

#endregion
