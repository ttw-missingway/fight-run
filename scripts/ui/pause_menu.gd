extends CanvasLayer

## Global pause menu (autoloaded, so it exists in every scene).
##
## This is the single owner of the pause state and the Esc toggle — no other
## system should call get_tree().paused directly. Mode-specific overlays such as
## TrainingHUD react to the opened/closed signals instead.


#region Signals

signal opened
signal closed

#endregion


#region Enums

enum Screen { MAIN, CONTROLS }

#endregion


#region Private state

var _root: Control
var _main_screen: Control
var _controls_screen: Control
var _current_screen: Screen = Screen.MAIN
var _main_focus: Control
var _controls_focus: Control

# Controls / rebinding state (moved here from MatchHUD).
var _controls_rows: VBoxContainer
var _rebind_action: String = ""
var _rebind_button: Button
var _rebind_buttons: Dictionary = {}
var _gamepad_status_label: Label

#endregion


#region Lifecycle

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	_build_ui()
	_root.visible = false
	ControlSettings.load_bindings()
	ControlSettings.migrate_retrobit_if_needed()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_sync_ui_navigation()


func _unhandled_input(event: InputEvent) -> void:
	# A pending rebind captures the next key/button and swallows Esc to cancel.
	if not _rebind_action.is_empty():
		_handle_rebind_input(event)
		return
	if not _root.visible:
		# Only the pause button (Esc / Start) opens the menu during play.
		if event.is_action_pressed("pause"):
			open()
			get_viewport().set_input_as_handled()
		return
	# Menu open: pause (Esc/Start) or cancel (Esc/B) backs out one level.
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _current_screen == Screen.CONTROLS:
			_show_screen(Screen.MAIN)
		else:
			close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _root.visible and _current_screen == Screen.CONTROLS and _gamepad_status_label != null:
		_refresh_gamepad_status()

#endregion


#region Public API

func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	_show_screen(Screen.MAIN)
	get_tree().paused = true
	opened.emit()


func close() -> void:
	_cancel_rebind()
	_root.visible = false
	get_tree().paused = false
	closed.emit()

#endregion


#region Private helpers

func _sync_ui_navigation() -> void:
	# Let the controller's primary face button confirm menu items on any pad by
	# copying the gamepad bindings used for "jump" onto ui_accept. (Directional
	# focus + a standard A button already work via Godot's built-in ui_* events;
	# this covers pads like the N64 adapter whose "A" is a different button index.)
	_mirror_gamepad_events("jump", "ui_accept")


func _mirror_gamepad_events(from_action: String, to_action: String) -> void:
	if not InputMap.has_action(from_action) or not InputMap.has_action(to_action):
		return
	for event in InputMap.action_get_events(from_action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			if not InputMap.action_has_event(to_action, event):
				InputMap.action_add_event(to_action, event)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_main_screen = _build_main_screen()
	center.add_child(_main_screen)

	_controls_screen = _build_controls_screen()
	center.add_child(_controls_screen)


func _show_screen(screen: Screen) -> void:
	_current_screen = screen
	_main_screen.visible = screen == Screen.MAIN
	_controls_screen.visible = screen == Screen.CONTROLS
	var focus_target: Control = _main_focus if screen == Screen.MAIN else _controls_focus
	if focus_target != null:
		focus_target.call_deferred("grab_focus")


func _build_main_screen() -> Control:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(220.0, 0.0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.pressed.connect(close)
	vbox.add_child(resume_button)
	_main_focus = resume_button

	var controls_button := Button.new()
	controls_button.text = "Controls"
	controls_button.pressed.connect(func() -> void: _show_screen(Screen.CONTROLS))
	vbox.add_child(controls_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit_button)

	return panel


func _build_controls_screen() -> Control:
	var panel := PanelContainer.new()

	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(360.0, 0.0)
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	outer.add_child(title)

	var hint := Label.new()
	hint.text = "Click a binding, then press a key or gamepad button. Esc cancels."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	outer.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 280.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
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

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(func() -> void: _show_screen(Screen.MAIN))
	outer.add_child(back_button)

	return panel


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
	if _controls_focus == null:
		_controls_focus = key_button


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
	_refresh_gamepad_status()


func _apply_n64_bindings() -> void:
	_cancel_rebind()
	ControlSettings.apply_n64_dinput_bindings()
	ControlSettings.save_bindings()
	_refresh_rebind_button_labels()
	_refresh_gamepad_status()


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected:
		ControlSettings.migrate_retrobit_if_needed()
		_refresh_rebind_button_labels()
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


func _handle_rebind_input(event: InputEvent) -> void:
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

#endregion
