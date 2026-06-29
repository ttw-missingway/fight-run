extends RefCounted
class_name ControlSettings


#region Constants

const SAVE_PATH := "user://input_bindings.json"

const REMAPPABLE_ACTIONS: Array[Dictionary] = [
	{"action": "move_left", "label": "Move Left"},
	{"action": "move_right", "label": "Move Right"},
	{"action": "move_up", "label": "Move Up"},
	{"action": "move_down", "label": "Move Down"},
	{"action": "jump", "label": "Jump"},
	{"action": "attack", "label": "Attack"},
	{"action": "guard", "label": "Guard"},
	{"action": "grab", "label": "Grab"},
	{"action": "projectile", "label": "Projectile"},
]

const DEFAULT_PHYSICAL_KEYS := {
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"jump": KEY_S,
	"attack": KEY_X,
	"guard": KEY_A,
	"grab": KEY_D,
	"projectile": KEY_Z,
}

const DEFAULT_GAMEPAD_BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP],
	"move_down": [JOY_BUTTON_DPAD_DOWN],
	"jump": [JOY_BUTTON_A],
	"attack": [JOY_BUTTON_X],
	"guard": [JOY_BUTTON_B],
	"grab": [JOY_BUTTON_Y],
	"projectile": [JOY_BUTTON_RIGHT_SHOULDER],
}

const DEFAULT_GAMEPAD_MOTIONS := {
	"move_left": [{"axis": JOY_AXIS_LEFT_X, "axis_value": -1.0}],
	"move_right": [{"axis": JOY_AXIS_LEFT_X, "axis_value": 1.0}],
	"move_up": [{"axis": JOY_AXIS_LEFT_Y, "axis_value": -1.0}],
	"move_down": [{"axis": JOY_AXIS_LEFT_Y, "axis_value": 1.0}],
}

# Retro-Bit Tribute64 USB D-Input (default mode). Hold Start+B for 5s to switch modes.
const DEFAULT_N64_DINPUT_BUTTONS := {
	"jump": [1],
	"attack": [2],
	"guard": [7],
	"grab": [14],
	"projectile": [12],
}

const N64_GAMEPAD_DEADZONE := 0.48
const XBOX_GAMEPAD_DEADZONE := 0.35

const MIRROR_ACTIONS := {
	"attack": ["respawn_confirm"],
}

const JOY_BUTTON_LABELS := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_DPAD_UP: "D-Pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}

const N64_BUTTON_LABELS := {
	1: "N64 A",
	2: "N64 B",
	7: "N64 Z",
	12: "N64 C↑",
	11: "N64 C→",
	4: "N64 C↓",
	14: "N64 C←",
	10: "N64 Start",
}

#endregion


#region Public API

static func load_bindings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		apply_default_bindings()
		maybe_apply_retrobit_preset()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		apply_default_bindings()
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		apply_default_bindings()
		return
	if _is_legacy_save(parsed):
		apply_default_bindings()
		for action in parsed.keys():
			var keycode := int(parsed[action])
			if keycode > 0:
				_replace_action_events_of_type(str(action), "key", [_make_key_event(keycode)])
		save_bindings()
		return
	_deserialize_save(parsed)
	migrate_retrobit_if_needed()


static func save_bindings() -> void:
	var data: Dictionary = {}
	for entry in REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		var serialized: Array = []
		for ev in InputMap.action_get_events(action):
			var blob := _serialize_event(ev)
			if not blob.is_empty():
				serialized.append(blob)
		data[action] = serialized
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()


static func apply_default_bindings() -> void:
	_apply_gamepad_preset(DEFAULT_GAMEPAD_BUTTONS, DEFAULT_GAMEPAD_MOTIONS, XBOX_GAMEPAD_DEADZONE)


static func apply_n64_dinput_bindings() -> void:
	_apply_gamepad_preset(DEFAULT_N64_DINPUT_BUTTONS, {}, N64_GAMEPAD_DEADZONE)


static func maybe_apply_retrobit_preset() -> void:
	migrate_retrobit_if_needed()


static func migrate_retrobit_if_needed() -> void:
	if not GamepadInput.is_retrobit_n64_device():
		return
	if not _jump_bound_to_xbox_a():
		return
	apply_n64_dinput_bindings()
	save_bindings()


static func reset_to_defaults() -> void:
	if GamepadInput.is_retrobit_n64_device():
		apply_n64_dinput_bindings()
	else:
		apply_default_bindings()
	save_bindings()


static func remap_action(action: String, event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var physical := key_event.physical_keycode
		if physical == 0:
			physical = key_event.keycode
		if physical == 0:
			return
		_replace_action_events_of_type(action, "key", [_make_key_event(physical)])
	elif event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		_replace_action_events_of_type(
			action,
			"joy_button",
			[_make_joy_button_event(button_event.button_index)]
		)
	else:
		return
	if MIRROR_ACTIONS.has(action):
		for mirrored in MIRROR_ACTIONS[action]:
			_copy_action_binding_type(action, str(mirrored), _event_type_name(event))
	save_bindings()


static func get_action_display_name(action: String) -> String:
	var parts: PackedStringArray = []
	for ev in InputMap.action_get_events(action):
		var label := _format_event(ev)
		if label != "" and label not in parts:
			parts.append(label)
	if parts.is_empty():
		return "—"
	return " / ".join(parts)


static func get_controls_summary() -> String:
	var parts: PackedStringArray = []
	for entry in REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		parts.append("%s %s" % [entry["label"], get_action_display_name(action)])
	return "  ·  ".join(parts)

#endregion


#region Private helpers

static func _jump_bound_to_xbox_a() -> bool:
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_A:
			return true
	return false


static func _apply_gamepad_preset(
	button_map: Dictionary,
	motion_map: Dictionary,
	deadzone: float
) -> void:
	for entry in REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		if DEFAULT_PHYSICAL_KEYS.has(action):
			InputMap.action_add_event(action, _make_key_event(int(DEFAULT_PHYSICAL_KEYS[action])))
		if button_map.has(action):
			for button_index in button_map[action]:
				InputMap.action_add_event(action, _make_joy_button_event(int(button_index)))
		if motion_map.has(action):
			for motion in motion_map[action]:
				InputMap.action_add_event(
					action,
					_make_joy_motion_event(int(motion["axis"]), float(motion["axis_value"]))
				)
		InputMap.action_set_deadzone(action, deadzone)
	_apply_mirror_actions("attack")


static func _deserialize_save(data: Dictionary) -> void:
	apply_default_bindings()
	for action in data.keys():
		if not InputMap.has_action(action):
			continue
		var entries: Array = data[action]
		if typeof(entries) != TYPE_ARRAY:
			continue
		var events: Array[InputEvent] = []
		for blob in entries:
			if typeof(blob) != TYPE_DICTIONARY:
				continue
			var ev := _deserialize_event(blob)
			if ev != null:
				events.append(ev)
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for ev in events:
			InputMap.action_add_event(action, ev)
	_apply_mirror_actions("attack")


static func _replace_action_events_of_type(
	action: String,
	type_name: String,
	replacement: Array[InputEvent]
) -> void:
	if not InputMap.has_action(action):
		return
	var preserved: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if _event_type_name(ev) != type_name:
			preserved.append(ev)
	InputMap.action_erase_events(action)
	for ev in preserved:
		InputMap.action_add_event(action, ev)
	for ev in replacement:
		InputMap.action_add_event(action, ev)


static func _copy_action_binding_type(from_action: String, to_action: String, type_name: String) -> void:
	if not InputMap.has_action(to_action):
		return
	var replacement: Array[InputEvent] = []
	for ev in InputMap.action_get_events(from_action):
		if _event_type_name(ev) == type_name:
			replacement.append(ev.duplicate())
	_replace_action_events_of_type(to_action, type_name, replacement)


static func _apply_mirror_actions(source_action: String) -> void:
	if not MIRROR_ACTIONS.has(source_action):
		return
	for mirrored in MIRROR_ACTIONS[source_action]:
		for type_name in ["key", "joy_button"]:
			_copy_action_binding_type(source_action, str(mirrored), type_name)


static func _is_legacy_save(data: Dictionary) -> bool:
	for action in data.keys():
		if typeof(data[action]) == TYPE_FLOAT or typeof(data[action]) == TYPE_INT:
			return true
	return false


static func _serialize_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return {
			"type": "key",
			"physical_keycode": key_event.physical_keycode,
		}
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		return {
			"type": "joy_button",
			"button_index": button_event.button_index,
			"device": button_event.device,
		}
	if event is InputEventJoypadMotion:
		var motion_event := event as InputEventJoypadMotion
		return {
			"type": "joy_motion",
			"axis": motion_event.axis,
			"axis_value": motion_event.axis_value,
			"device": motion_event.device,
		}
	return {}


static func _deserialize_event(data: Dictionary) -> InputEvent:
	match str(data.get("type", "")):
		"key":
			return _make_key_event(int(data.get("physical_keycode", 0)))
		"joy_button":
			var ev := _make_joy_button_event(int(data.get("button_index", 0)))
			ev.device = int(data.get("device", -1))
			return ev
		"joy_motion":
			var motion := _make_joy_motion_event(
				int(data.get("axis", 0)),
				float(data.get("axis_value", 0.0))
			)
			motion.device = int(data.get("device", -1))
			return motion
	return null


static func _make_key_event(physical_keycode: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode as Key
	return ev


static func _make_joy_button_event(button_index: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button_index as JoyButton
	ev.device = -1
	return ev


static func _make_joy_motion_event(axis: int, axis_value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis as JoyAxis
	ev.axis_value = axis_value
	ev.device = -1
	return ev


static func _event_type_name(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key"
	if event is InputEventJoypadButton:
		return "joy_button"
	if event is InputEventJoypadMotion:
		return "joy_motion"
	return ""


static func _format_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return _format_key_event(event as InputEventKey)
	if event is InputEventJoypadButton:
		return _format_joy_button_event(event as InputEventJoypadButton)
	if event is InputEventJoypadMotion:
		return _format_joy_motion_event(event as InputEventJoypadMotion)
	return ""


static func _format_key_event(event: InputEventKey) -> String:
	var physical := event.physical_keycode
	if physical != 0:
		var keycode := DisplayServer.keyboard_get_keycode_from_physical(physical)
		if keycode != 0:
			return OS.get_keycode_string(keycode)
	return OS.get_keycode_string(event.keycode)


static func _format_joy_button_event(event: InputEventJoypadButton) -> String:
	if _bindings_use_n64_layout() and N64_BUTTON_LABELS.has(event.button_index):
		return N64_BUTTON_LABELS[event.button_index]
	if JOY_BUTTON_LABELS.has(event.button_index):
		return JOY_BUTTON_LABELS[event.button_index]
	return "Btn %d" % event.button_index


static func _bindings_use_n64_layout() -> bool:
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventJoypadButton and ev.button_index == 1:
			return true
	return false


static func _format_joy_motion_event(event: InputEventJoypadMotion) -> String:
	if event.axis == JOY_AXIS_LEFT_X:
		return "L Stick ←" if event.axis_value < 0.0 else "L Stick →"
	if event.axis == JOY_AXIS_LEFT_Y:
		return "L Stick ↑" if event.axis_value < 0.0 else "L Stick ↓"
	return "Axis %d" % event.axis

#endregion
