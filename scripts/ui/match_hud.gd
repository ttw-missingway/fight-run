extends CanvasLayer

## Overlay for a match: shows each fighter's lives and state, an optional input
## buffer readout, and the end-of-match result panel with its restart button.


#region Signals

## Emitted when the player activates the result panel's restart button.
signal restart_requested

#endregion


#region Onready

@onready var player_lives_label: Label = $Control/PlayerLivesLabel
@onready var opponent_lives_label: Label = $Control/OpponentLivesLabel
@onready var state_label: Label = $Control/StateLabel
@onready var result_panel: PanelContainer = $Control/ResultPanel
@onready var result_label: Label = $Control/ResultPanel/ResultVBox/ResultLabel
@onready var restart_button: Button = $Control/ResultPanel/ResultVBox/RestartButton
@onready var hud_control: Control = $Control

#endregion


#region Private state

var _player: Fighter
var _opponent: Fighter
var _infinite_lives: bool = false
var _show_input_buffer: bool = false
var _input_buffer_panel: PanelContainer
var _input_buffer_label: Label

#endregion


#region Lifecycle

func _process(_delta: float) -> void:
	if _show_input_buffer:
		_refresh_input_buffer_display()

#endregion


#region Public API

## Binds the HUD to both fighters, wiring state/restart signals and building the
## input buffer readout. Call once before the match starts.
func setup(player: Fighter, opponent: Fighter) -> void:
	_player = player
	_opponent = opponent
	result_panel.visible = false
	player.state_changed.connect(_on_state_changed)
	opponent.state_changed.connect(_on_state_changed)
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_build_input_buffer_readout()


## Toggles the infinite-lives display, redrawing the life labels accordingly.
func set_infinite_lives(enabled: bool) -> void:
	_infinite_lives = enabled
	_refresh_life_labels()


## Shows or hides the live input buffer readout panel.
func set_input_buffer_visible(enabled: bool) -> void:
	_show_input_buffer = enabled
	if _input_buffer_panel != null:
		_input_buffer_panel.visible = enabled
	_refresh_input_buffer_display()


## Updates the life count shown for whichever fighter is given.
func update_lives(fighter: Fighter, lives: int) -> void:
	if fighter == _player:
		player_lives_label.text = _life_text("Player Lives", lives)
	elif fighter == _opponent:
		opponent_lives_label.text = _life_text("AI Lives", lives)


## Reveals the result panel with the given outcome text.
func show_result(text: String) -> void:
	result_label.text = text
	result_panel.visible = true

#endregion


#region Private helpers

func _build_input_buffer_readout() -> void:
	# Live readout only; the toggle that drives it lives in TrainingHUD's Debug
	# section. Starts hidden and is shown via set_input_buffer_visible().
	_input_buffer_panel = PanelContainer.new()
	_input_buffer_panel.name = "InputBufferPanel"
	_input_buffer_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_input_buffer_panel.offset_left = 8.0
	_input_buffer_panel.offset_top = 88.0
	_input_buffer_panel.offset_right = 220.0
	_input_buffer_panel.offset_bottom = 132.0
	_input_buffer_panel.visible = false
	_input_buffer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_control.add_child(_input_buffer_panel)

	_input_buffer_label = Label.new()
	_input_buffer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_input_buffer_label.text = "Buffer: (empty)"
	_input_buffer_panel.add_child(_input_buffer_label)


func _refresh_input_buffer_display() -> void:
	if _input_buffer_label == null or _player == null:
		return
	_input_buffer_label.text = "Buffer: %s" % _player.get_input_queue_display_text()


func _life_text(prefix: String, lives: int) -> String:
	if _infinite_lives:
		return "%s: ∞" % prefix
	return "%s: %d" % [prefix, lives]


func _refresh_life_labels() -> void:
	if _player != null:
		update_lives(_player, _player.lives)
	if _opponent != null:
		update_lives(_opponent, _opponent.lives)


func _on_state_changed(fighter: Fighter, state_name: String) -> void:
	if fighter == _player:
		if fighter.state_machine.is_in_punish_window():
			state_label.text = "State: %s (v-frames)" % state_name
		else:
			state_label.text = "State: %s" % state_name

#endregion
