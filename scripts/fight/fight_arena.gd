extends Node2D

const FIGHTER_SCENE := preload("res://scenes/fight/fighter.tscn")

@export var stage_profile: StageProfile = preload("res://scripts/resources/default_stage_profile.tres")
@export var player_stats: FighterStats = preload("res://scripts/resources/default_fighter_stats.tres")
@export var opponent_stats: FighterStats = preload("res://scripts/resources/heavy_fighter_stats.tres")
@export var debug_hitboxes: bool = false

@onready var fight_manager: FightManager = $FightManager
@onready var match_hud: CanvasLayer = $MatchHUD
@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var opponent_spawn: Marker2D = $OpponentSpawn
@onready var stage_geometry: StageGeometry = $Platform

var _player: Fighter
var _opponent: Fighter


func _ready() -> void:
	if stage_geometry != null:
		stage_geometry.apply_profile(stage_profile)
	fight_manager.configure_stage(stage_profile)

	var player_pos := _spawn_position_from_marker(player_spawn)
	var opponent_pos := _spawn_position_from_marker(opponent_spawn)
	_player = _spawn_fighter(player_pos, Color(0.2, 0.45, 0.95), true)
	_opponent = _spawn_fighter(opponent_pos, Color(0.9, 0.25, 0.2), false)
	var player := _player
	var opponent := _opponent

	fight_manager.setup(self, player, opponent)
	fight_manager.match_over.connect(_on_match_over)
	fight_manager.lives_changed.connect(_on_lives_changed)
	fight_manager.mana_changed.connect(_on_mana_changed)
	match_hud.restart_requested.connect(_restart_match)

	match_hud.setup(player, opponent)
	match_hud.ai_mode_selected.connect(_on_ai_mode_selected)
	match_hud.infinite_mode_toggled.connect(_on_infinite_mode_toggled)
	match_hud.infinite_mana_toggled.connect(_on_infinite_mana_toggled)
	match_hud.debug_knockdown_requested.connect(_debug_knockdown_player)
	_on_lives_changed(player, player.lives)
	_on_lives_changed(opponent, opponent.lives)
	_on_mana_changed(player, player.mana)
	_on_mana_changed(opponent, opponent.mana)
	_set_debug_visibility(debug_hitboxes)


func _spawn_position_from_marker(marker: Marker2D) -> Vector2:
	var x := marker.global_position.x
	return Vector2(x, stage_profile.get_ground_y(x))


func _spawn_fighter(spawn_position: Vector2, color: Color, is_player: bool) -> Fighter:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	fighter.global_position = spawn_position
	fighter.body_color = color
	fighter.block_color = color.lightened(0.2)
	fighter.is_player_controlled = is_player
	fighter.stats = player_stats if is_player else opponent_stats
	add_child(fighter)
	return fighter


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_hitboxes = not debug_hitboxes
		_set_debug_visibility(debug_hitboxes)
	if event.is_action_pressed("debug_knockdown"):
		_debug_knockdown_player()


func _debug_knockdown_player() -> void:
	if _player != null:
		_player.debug_force_knockdown()


func _on_ai_mode_selected(mode: int) -> void:
	if _opponent == null:
		return
	_opponent.ai_controller.set_behavior_mode(mode as AiController.BehaviorMode)
	match_hud.set_active_ai_mode(mode)


func _on_infinite_mode_toggled(enabled: bool) -> void:
	fight_manager.infinite_lives = enabled


func _on_infinite_mana_toggled(enabled: bool) -> void:
	fight_manager.infinite_mana = enabled


func _on_mana_changed(fighter: Fighter, mana: int) -> void:
	match_hud.update_mana(fighter, mana)


func _set_debug_visibility(enabled: bool) -> void:
	for child in get_children():
		if child is Fighter:
			child.set_debug_visible(enabled)


func _on_lives_changed(fighter: Fighter, lives: int) -> void:
	match_hud.update_lives(fighter, lives)


func _on_match_over(winner: Fighter, _loser: Fighter) -> void:
	var label := "You Win!" if winner.is_player_controlled else "You Lose!"
	match_hud.show_result(label)


func _restart_match() -> void:
	get_tree().reload_current_scene()
