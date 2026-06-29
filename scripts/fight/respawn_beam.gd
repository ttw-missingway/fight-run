extends Node2D
class_name RespawnBeam

## Post-death respawn marker: lets a player slide a beam along the platform and
## confirm a spawn point, or expires on its own once the timer runs out.


#region Signals

## Emitted when the player confirms a spawn location. payload: respawning fighter, chosen x.
signal respawn_confirmed(fighter: Fighter, spawn_x: float)
## Emitted when the respawn timer elapses without a confirmation. payload: respawning fighter.
signal expired(fighter: Fighter)

#endregion


#region Onready

@onready var beam_rect: ColorRect = $BeamRect
@onready var timer_label: Label = $TimerLabel

#endregion


#region Private state

var _fighter: Fighter
var _fight_manager: FightManager
var _bounds: Rect2
var _spawn_height: float
var _time_left: float
var _beam_x: float = 0.0

#endregion


#region Lifecycle

func _process(delta: float) -> void:
	_time_left -= delta
	timer_label.text = "Respawn: %.1fs — Move A/D, press H" % maxf(_time_left, 0.0)

	if _fighter.is_player_controlled:
		if Input.is_action_pressed("move_left"):
			_beam_x -= 260.0 * delta
		if Input.is_action_pressed("move_right"):
			_beam_x += 260.0 * delta
		_beam_x = clampf(
			_beam_x,
			_fight_manager.platform_left + 40.0,
			_fight_manager.platform_right - 40.0
		)

		if Input.is_action_just_pressed("respawn_confirm"):
			respawn_confirmed.emit(_fighter, _beam_x)
			queue_free()
			return

	_update_visuals()

	if _time_left <= 0.0:
		expired.emit(_fighter)
		queue_free()

#endregion


#region Public API

## Initializes the beam for a fighter: caches the manager and bounds, seeds the
## beam at the fighter's position, and starts the countdown.
func setup(
	fighter: Fighter,
	fight_manager: FightManager,
	spawn_height: float,
	duration: float
) -> void:
	_fighter = fighter
	_fight_manager = fight_manager
	_bounds = fight_manager.arena_bounds
	_spawn_height = spawn_height
	_time_left = duration
	_beam_x = clampf(
		fighter.global_position.x,
		fight_manager.platform_left + 40.0,
		fight_manager.platform_right - 40.0
	)
	_update_visuals()

#endregion


#region Private helpers

func _update_visuals() -> void:
	if beam_rect == null or _fight_manager == null:
		return
	var ground_y := _fight_manager.get_ground_y(_beam_x)
	beam_rect.position = Vector2(_beam_x - 8.0, _bounds.position.y + 20.0)
	beam_rect.size = Vector2(16.0, ground_y + _spawn_height - _bounds.position.y - 20.0)

#endregion
