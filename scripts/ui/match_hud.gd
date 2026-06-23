extends CanvasLayer

signal ai_mode_selected(mode: int)
signal infinite_mode_toggled(enabled: bool)
signal restart_requested
signal debug_knockdown_requested

@onready var player_lives_label: Label = $Control/PlayerLivesLabel
@onready var opponent_lives_label: Label = $Control/OpponentLivesLabel
@onready var state_label: Label = $Control/StateLabel
@onready var ai_mode_button: Button = $Control/AiModeButton
@onready var debug_knockdown_button: Button = $Control/DebugKnockdownButton
@onready var result_panel: PanelContainer = $Control/ResultPanel
@onready var result_label: Label = $Control/ResultPanel/ResultVBox/ResultLabel
@onready var restart_button: Button = $Control/ResultPanel/ResultVBox/RestartButton
@onready var controls_label: Label = $Control/ControlsLabel
@onready var hud_control: Control = $Control

var _player: Fighter
var _opponent: Fighter
var _infinite_lives: bool = false
var _show_input_buffer: bool = false
var _ai_buttons: Dictionary = {}
var _mode_button_group := ButtonGroup.new()
var _input_buffer_toggle: CheckButton
var _input_buffer_label: Label


func setup(player: Fighter, opponent: Fighter) -> void:
	_player = player
	_opponent = opponent
	result_panel.visible = false
	player.state_changed.connect(_on_state_changed)
	opponent.state_changed.connect(_on_state_changed)
	debug_knockdown_button.pressed.connect(func() -> void: debug_knockdown_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	controls_label.text = (
		"Move ←/→/↑/↓  Jump S (tap=short hop, hold=full hop, ↓+S=super jump)  ↓ in air (past peak)=fast fall  "
		+ "Attack X  Guard A  Grab D or X+A  Projectile Z (↓+Z low)  "
		+ "Crouch ↓  Anti-air ↑+X  Dash ←←/→→ then X=dash attack  "
		+ "Oki: ←/→=roll  tap ↑=get up  hold S=jump  ↓=slow  X=attack  A=shield  X+A=grab  "
		+ "Respawn: ←/→ position, X confirm  Test KD: K  F1 debug hitboxes"
	)
	_build_ai_selector()
	_build_input_buffer_display()
	set_active_ai_mode(opponent.ai_controller.behavior_mode)


func _build_input_buffer_display() -> void:
	var panel := PanelContainer.new()
	panel.name = "InputBufferPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 8.0
	panel.offset_top = 88.0
	panel.offset_right = 220.0
	panel.offset_bottom = 148.0
	hud_control.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_input_buffer_toggle = CheckButton.new()
	_input_buffer_toggle.text = "Show Input Buffer"
	_input_buffer_toggle.toggled.connect(func(enabled: bool) -> void:
		_show_input_buffer = enabled
		_input_buffer_label.visible = enabled
		_refresh_input_buffer_display()
	)
	vbox.add_child(_input_buffer_toggle)

	_input_buffer_label = Label.new()
	_input_buffer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_input_buffer_label.visible = false
	_input_buffer_label.text = "Buffer: (empty)"
	vbox.add_child(_input_buffer_label)


func _process(_delta: float) -> void:
	if _show_input_buffer:
		_refresh_input_buffer_display()


func _refresh_input_buffer_display() -> void:
	if _input_buffer_label == null or _player == null:
		return
	_input_buffer_label.text = "Buffer: %s" % _player.get_input_queue_display_text()


func _build_ai_selector() -> void:
	ai_mode_button.visible = false

	var panel := PanelContainer.new()
	panel.name = "AiSelectorPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -184.0
	panel.offset_top = 88.0
	panel.offset_right = -8.0
	panel.offset_bottom = 468.0
	hud_control.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)

	var infinite_toggle := CheckButton.new()
	infinite_toggle.text = "Infinite Lives"
	infinite_toggle.toggled.connect(func(enabled: bool) -> void:
		_infinite_lives = enabled
		infinite_mode_toggled.emit(enabled)
		_refresh_life_labels()
	)
	outer.add_child(infinite_toggle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 4)
	scroll.add_child(inner)

	_add_mode_section(inner, "Simple AI", AiController.SIMPLE_MODES)
	_add_mode_section(inner, "Complex AI", AiController.COMPLEX_MODES)


func _add_mode_section(parent: VBoxContainer, title: String, modes: Array) -> void:
	var header := Label.new()
	header.text = title
	header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	parent.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)

	for mode in modes:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _mode_button_group
		button.text = AiController.MODE_LABELS.get(mode, "?")
		button.custom_minimum_size = Vector2(82.0, 0.0)
		button.pressed.connect(func() -> void: ai_mode_selected.emit(mode))
		grid.add_child(button)
		_ai_buttons[mode] = button


func set_active_ai_mode(mode: int) -> void:
	for mode_key in _ai_buttons:
		_ai_buttons[mode_key].button_pressed = mode_key == mode


func update_ai_mode(_mode_label: String) -> void:
	pass


func update_lives(fighter: Fighter, lives: int) -> void:
	if fighter == _player:
		player_lives_label.text = _life_text("Player Lives", lives)
	elif fighter == _opponent:
		opponent_lives_label.text = _life_text("AI Lives", lives)


func _life_text(prefix: String, lives: int) -> String:
	if _infinite_lives:
		return "%s: ∞" % prefix
	return "%s: %d" % [prefix, lives]


func _refresh_life_labels() -> void:
	if _player != null:
		update_lives(_player, _player.lives)
	if _opponent != null:
		update_lives(_opponent, _opponent.lives)


func show_result(text: String) -> void:
	result_label.text = text
	result_panel.visible = true


func _on_state_changed(fighter: Fighter, state_name: String) -> void:
	if fighter == _player:
		if fighter.state_machine.is_in_punish_window():
			state_label.text = "State: %s (v-frames)" % state_name
		else:
			state_label.text = "State: %s" % state_name
