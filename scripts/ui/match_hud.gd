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
var _controls_panel: PanelContainer
var _controls_toggle: Button
var _controls_rows: VBoxContainer
var _rebind_action: String = ""
var _rebind_button: Button
var _rebind_buttons: Dictionary = {}
var _controls_panel_expanded: bool = false
var _gamepad_status_label: Label


func setup(player: Fighter, opponent: Fighter) -> void:
	_player = player
	_opponent = opponent
	result_panel.visible = false
	player.state_changed.connect(_on_state_changed)
	opponent.state_changed.connect(_on_state_changed)
	debug_knockdown_button.pressed.connect(func() -> void: debug_knockdown_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	ControlSettings.load_bindings()
	ControlSettings.migrate_retrobit_if_needed()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_build_controls_panel()
	_refresh_controls_summary()
	_build_ai_selector()
	_build_input_buffer_display()
	set_active_ai_mode(opponent.ai_controller.behavior_mode)


func _build_controls_panel() -> void:
	var sidebar := HBoxContainer.new()
	sidebar.name = "ControlsSidebar"
	sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sidebar.anchor_top = 0.12
	sidebar.anchor_bottom = 0.88
	sidebar.offset_left = 0.0
	sidebar.offset_top = 0.0
	sidebar.offset_right = 44.0
	sidebar.offset_bottom = 0.0
	sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_control.add_child(sidebar)

	_controls_toggle = Button.new()
	_controls_toggle.name = "ControlsToggle"
	_controls_toggle.text = "Controls ›"
	_controls_toggle.custom_minimum_size = Vector2(40.0, 0.0)
	_controls_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_controls_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_controls_toggle.pressed.connect(_toggle_controls_panel)
	sidebar.add_child(_controls_toggle)

	_controls_panel = PanelContainer.new()
	_controls_panel.name = "ControlsPanel"
	_controls_panel.visible = false
	_controls_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls_panel.custom_minimum_size = Vector2(248.0, 0.0)
	_controls_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	sidebar.add_child(_controls_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_controls_panel.add_child(outer)

	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	outer.add_child(title)

	var hint := Label.new()
	hint.text = "Click a binding, then press a key or gamepad button. Esc cancels."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	outer.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_controls_rows = VBoxContainer.new()
	_controls_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_controls_rows)

	for entry in ControlSettings.REMAPPABLE_ACTIONS:
		_add_rebind_row(str(entry["label"]), str(entry["action"]))

	var reset_button := Button.new()
	reset_button.text = "Reset to Defaults"
	reset_button.pressed.connect(_reset_control_bindings)
	outer.add_child(reset_button)

	var n64_button := Button.new()
	n64_button.text = "Apply N64 / Retro-Bit Layout"
	n64_button.pressed.connect(_apply_n64_bindings)
	outer.add_child(n64_button)

	_gamepad_status_label = Label.new()
	_gamepad_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gamepad_status_label.add_theme_font_size_override("font_size", 11)
	_gamepad_status_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
	outer.add_child(_gamepad_status_label)
	_refresh_gamepad_status()


func _add_rebind_row(label_text: String, action: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	row.add_child(name_label)

	var key_button := Button.new()
	key_button.text = ControlSettings.get_action_display_name(action)
	key_button.custom_minimum_size = Vector2(72.0, 0.0)
	key_button.pressed.connect(func() -> void: _begin_rebind(action, key_button))
	row.add_child(key_button)

	_controls_rows.add_child(row)
	_rebind_buttons[action] = key_button


func _toggle_controls_panel() -> void:
	_controls_panel_expanded = not _controls_panel_expanded
	_controls_panel.visible = _controls_panel_expanded
	_controls_toggle.text = "‹" if _controls_panel_expanded else "Controls ›"
	var sidebar := _controls_panel.get_parent() as Control
	if sidebar != null:
		sidebar.offset_right = 292.0 if _controls_panel_expanded else 44.0
	var buffer_panel := hud_control.get_node_or_null("InputBufferPanel") as Control
	if buffer_panel != null:
		buffer_panel.offset_left = 300.0 if _controls_panel_expanded else 8.0


func _begin_rebind(action: String, button: Button) -> void:
	if _rebind_button != null:
		_rebind_button.text = ControlSettings.get_action_display_name(_rebind_action)
	_rebind_action = action
	_rebind_button = button
	button.text = "…"


func _cancel_rebind() -> void:
	if _rebind_button != null:
		_rebind_button.text = ControlSettings.get_action_display_name(_rebind_action)
	_rebind_action = ""
	_rebind_button = null


func _finish_rebind() -> void:
	if _rebind_button != null:
		_rebind_button.text = ControlSettings.get_action_display_name(_rebind_action)
	_rebind_action = ""
	_rebind_button = null
	_refresh_controls_summary()
	_refresh_rebind_button_labels()


func _refresh_rebind_button_labels() -> void:
	for action in _rebind_buttons.keys():
		var button: Button = _rebind_buttons[action]
		if button == _rebind_button:
			continue
		button.text = ControlSettings.get_action_display_name(action)


func _reset_control_bindings() -> void:
	_cancel_rebind()
	ControlSettings.reset_to_defaults()
	_refresh_rebind_button_labels()
	_refresh_controls_summary()
	_refresh_gamepad_status()


func _apply_n64_bindings() -> void:
	_cancel_rebind()
	ControlSettings.apply_n64_dinput_bindings()
	ControlSettings.save_bindings()
	_refresh_rebind_button_labels()
	_refresh_controls_summary()
	_refresh_gamepad_status()


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected:
		ControlSettings.migrate_retrobit_if_needed()
		_refresh_rebind_button_labels()
		_refresh_controls_summary()
	_refresh_gamepad_status()


func _refresh_gamepad_status() -> void:
	if _gamepad_status_label == null:
		return
	var lines := GamepadInput.poll_debug_lines()
	lines.insert(
		0,
		"Retro-Bit D-Input: A jump, B attack, Z guard, C← grab, C↑ projectile, stick move."
	)
	lines.insert(
		1,
		"Xbox mode: hold Start+B for 5s, then Reset to Defaults."
	)
	_gamepad_status_label.text = "\n".join(lines)


func _refresh_controls_summary() -> void:
	var pad_hint := "N64: stick move, A jump, B attack, Z guard, C← grab, C↑ shot"
	if GamepadInput.get_primary_device() >= 0 and not GamepadInput.is_retrobit_n64_device():
		pad_hint = "Gamepad: stick/D-pad move, A jump, X attack, B guard, Y grab, RB projectile"
	controls_label.text = (
		"%s  ·  %s  ·  F1 hitboxes  ·  K test KD"
		% [ControlSettings.get_controls_summary(), pad_hint]
	)


func _unhandled_input(event: InputEvent) -> void:
	if _rebind_action.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_cancel_rebind()
			get_viewport().set_input_as_handled()
			return
		ControlSettings.remap_action(_rebind_action, key_event)
		_finish_rebind()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		ControlSettings.remap_action(_rebind_action, event)
		_finish_rebind()
		get_viewport().set_input_as_handled()


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
	if _controls_panel_expanded and _gamepad_status_label != null:
		_refresh_gamepad_status()


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
