extends Node
class_name FightManager


#region Signals

signal match_over(winner: Fighter, loser: Fighter)
signal lives_changed(fighter: Fighter, lives: int)

#endregion


#region Constants

const RESPAWN_BEAM_SCENE := preload("res://scenes/fight/respawn_beam.tscn")
const RESPAWN_WINDOW := 5.0 * CombatTiming.FIGHT_TIMING_SCALE
const AI_RESPAWN_DELAY := 2.0 * CombatTiming.FIGHT_TIMING_SCALE

#endregion


#region Exports

@export var stage_profile: StageProfile = preload("res://scripts/resources/default_stage_profile.tres")
@export var arena_bounds: Rect2 = Rect2(-760.0, -240.0, 1520.0, 480.0)
@export var platform_y: float = 130.0
@export var platform_left: float = -696.0
@export var platform_right: float = 696.0
@export var platform_surface_half_width: float = 720.0
@export var death_y: float = 270.0
@export var horizontal_blast_margin: float = 112.0
@export var spawn_height: float = 80.0
@export var fall_death_margin: float = 6.0

#endregion


#region Public state

var player: Fighter
var opponent: Fighter
var match_finished: bool = false
var infinite_lives: bool = false

#endregion


#region Private state

var _arena: Node
var _active_beam: RespawnBeam
var _pending_ai_respawn: bool = false
var _ai_respawn_timer: float = 0.0

#endregion


#region Lifecycle

func _process(delta: float) -> void:
	if _pending_ai_respawn:
		_ai_respawn_timer -= delta
		if _ai_respawn_timer <= 0.0:
			_pending_ai_respawn = false
			_auto_respawn_ai()

#endregion


#region Public API

func setup(arena: Node, player_fighter: Fighter, opponent_fighter: Fighter) -> void:
	_arena = arena
	player = player_fighter
	opponent = opponent_fighter
	player.opponent = opponent
	opponent.opponent = player
	player.fight_manager = self
	opponent.fight_manager = self
	player.died.connect(_on_fighter_died)
	opponent.died.connect(_on_fighter_died)
	_emit_lives(player)
	_emit_lives(opponent)


func configure_stage(profile: StageProfile) -> void:
	stage_profile = profile
	if profile == null:
		return
	platform_surface_half_width = profile.half_width
	platform_left = profile.get_walkable_left()
	platform_right = profile.get_walkable_right()
	platform_y = profile.center_ground_y
	arena_bounds = Rect2(
		profile.get_left_edge_x() - 40.0,
		-240.0,
		profile.half_width * 2.0 + 80.0,
		480.0
	)
	death_y = profile.center_ground_y + 140.0


func get_ground_y(x: float) -> float:
	if stage_profile != null:
		return stage_profile.get_ground_y(x)
	return platform_y


func get_left_edge_x() -> float:
	if stage_profile != null:
		return stage_profile.get_left_edge_x()
	return -platform_surface_half_width


func get_right_edge_x() -> float:
	if stage_profile != null:
		return stage_profile.get_right_edge_x()
	return platform_surface_half_width


func get_respawn_position(spawn_x: float) -> Vector2:
	return Vector2(spawn_x, get_ground_y(spawn_x))


func get_respawn_drop_y() -> float:
	return arena_bounds.position.y + 24.0


func get_ledge_hang_x(side: int, body_half_width: float = 16.0) -> float:
	if stage_profile != null:
		return stage_profile.get_ledge_hang_x(side, body_half_width)
	if side < 0:
		return -platform_surface_half_width + body_half_width * 0.5
	return platform_surface_half_width - body_half_width * 0.5


func get_ledge_hang_position(side: int, body_half_width: float, body_height: float) -> Vector2:
	var hang_x := get_ledge_hang_x(side, body_half_width)
	var hang_y := get_ground_y(hang_x) + body_height
	if stage_profile != null:
		hang_y = stage_profile.get_ledge_hang_y(hang_x, body_height)
	return Vector2(hang_x, hang_y)


func is_outside_horizontal_blast_zone(x: float) -> bool:
	return x < platform_left - horizontal_blast_margin or x > platform_right + horizontal_blast_margin


func is_below_local_ground(x: float, y: float) -> bool:
	return y > get_ground_y(x) + fall_death_margin

#endregion


#region Private helpers

func _on_fighter_died(fighter: Fighter) -> void:
	_emit_lives(fighter)
	if not infinite_lives and fighter.lives <= 0:
		_finish_match(fighter)
		return

	if fighter.is_player_controlled:
		_spawn_player_beam(fighter)
	else:
		_pending_ai_respawn = true
		_ai_respawn_timer = AI_RESPAWN_DELAY


func _spawn_player_beam(fighter: Fighter) -> void:
	if _active_beam != null:
		_active_beam.queue_free()
	_active_beam = RESPAWN_BEAM_SCENE.instantiate()
	_arena.add_child(_active_beam)
	_active_beam.respawn_confirmed.connect(_on_player_respawn_confirmed)
	_active_beam.expired.connect(_on_beam_expired)
	_active_beam.setup(fighter, self, spawn_height, RESPAWN_WINDOW)


func _on_player_respawn_confirmed(fighter: Fighter, spawn_x: float) -> void:
	_active_beam = null
	fighter.respawn_at(get_respawn_position(spawn_x))


func _on_beam_expired(fighter: Fighter) -> void:
	_active_beam = null
	fighter.respawn_at(get_respawn_position(0.0))


func _auto_respawn_ai() -> void:
	var min_x := platform_left + 60.0
	var max_x := platform_right - 60.0
	var spawn_x := randf_range(min_x, max_x)
	opponent.respawn_at(get_respawn_position(spawn_x))


func _finish_match(loser: Fighter) -> void:
	if match_finished:
		return
	match_finished = true
	var winner: Fighter = opponent if loser == player else player
	match_over.emit(winner, loser)


func _emit_lives(fighter: Fighter) -> void:
	lives_changed.emit(fighter, fighter.lives)

#endregion
