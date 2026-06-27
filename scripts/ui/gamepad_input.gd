extends RefCounted
class_name GamepadInput

const STICK_DEADZONE := 0.42
const N64_STICK_DEADZONE := 0.48

# Retro-Bit Tribute64 D-Input default indices (USB / Mac HID).
const N64_BTN_A := 1
const N64_BTN_B := 2
const N64_BTN_Z := 7
const N64_BTN_C_UP := 12
const N64_BTN_C_RIGHT := 11
const N64_BTN_C_DOWN := 4
const N64_BTN_C_LEFT := 14
const N64_BTN_START := 10

const PROBE_MAX_BUTTONS := 24
const HYPERKIN_VENDOR_ID := "2e24"
const HYPERKIN_N64_ADAPTER_PRODUCT_ID := "0bff"
const N64_DPAD_FALLBACK := {
	"left": [JOY_BUTTON_DPAD_LEFT],
	"right": [JOY_BUTTON_DPAD_RIGHT],
	"up": [JOY_BUTTON_DPAD_UP],
	"down": [JOY_BUTTON_DPAD_DOWN],
}


static func get_primary_device() -> int:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return -1
	return int(pads[0])


static func get_device_label(device: int = -1) -> String:
	if device < 0:
		device = get_primary_device()
	if device < 0:
		return "No gamepad detected"
	return "%s (#%d)" % [get_device_friendly_name(device), device]


static func get_device_friendly_name(device: int = -1) -> String:
	if device < 0:
		device = get_primary_device()
	if device < 0:
		return "No gamepad detected"
	var raw_name := Input.get_joy_name(device)
	if is_n64_adapter_device(device):
		return "Hyperkin N64 Adapter (%s)" % raw_name
	return raw_name


static func is_n64_adapter_device(device: int = -1) -> bool:
	if device < 0:
		device = get_primary_device()
	if device < 0:
		return false
	if _joy_guid_matches_hyperkin_n64(device):
		return true
	var name := Input.get_joy_name(device).to_lower()
	return (
		"retro" in name
		or "hyperkin" in name
		or "n64" in name
		or "tribute 64" in name
		or "tribute64" in name
	)


static func is_retrobit_n64_device(device: int = -1) -> bool:
	return is_n64_adapter_device(device)


static func _joy_guid_matches_hyperkin_n64(device: int) -> bool:
	var guid := Input.get_joy_guid(device).to_lower()
	if guid.is_empty():
		return false
	# SDL-style GUIDs embed USB vendor/product as little-endian 16-bit values.
	var has_vendor := HYPERKIN_VENDOR_ID in guid or "240e" in guid
	var has_product := HYPERKIN_N64_ADAPTER_PRODUCT_ID in guid or "ff0b" in guid
	return has_vendor and has_product


static func get_move_direction() -> int:
	var device := get_primary_device()
	if device < 0:
		return 0
	var deadzone := N64_STICK_DEADZONE if is_n64_adapter_device(device) else STICK_DEADZONE
	var stick_x := _read_stick_x(device)
	if absf(stick_x) >= deadzone:
		return int(signf(stick_x)) if stick_x != 0.0 else 0
	if _is_any_pressed(device, N64_DPAD_FALLBACK["left"]):
		return -1
	if _is_any_pressed(device, N64_DPAD_FALLBACK["right"]):
		return 1
	return 0


static func is_up_pressed() -> bool:
	var device := get_primary_device()
	if device < 0:
		return false
	if _is_any_pressed(device, N64_DPAD_FALLBACK["up"]):
		return true
	var stick_y := _read_stick_y(device)
	var deadzone := N64_STICK_DEADZONE if is_n64_adapter_device(device) else STICK_DEADZONE
	return stick_y <= -deadzone


static func is_down_pressed() -> bool:
	var device := get_primary_device()
	if device < 0:
		return false
	if _is_any_pressed(device, N64_DPAD_FALLBACK["down"]):
		return true
	var stick_y := _read_stick_y(device)
	var deadzone := N64_STICK_DEADZONE if is_n64_adapter_device(device) else STICK_DEADZONE
	return stick_y >= deadzone


static func is_button_pressed(button_index: int) -> bool:
	var device := get_primary_device()
	if device < 0:
		return false
	return Input.is_joy_button_pressed(device, button_index)


static func poll_debug_lines(device: int = -1) -> PackedStringArray:
	if device < 0:
		device = get_primary_device()
	if device < 0:
		return PackedStringArray(["Plug in a gamepad, then press buttons."])
	var lines: PackedStringArray = []
	lines.append(get_device_label(device))
	var guid := Input.get_joy_guid(device)
	if not guid.is_empty():
		lines.append("GUID %s" % guid)
	lines.append(
		"Stick %.2f, %.2f" % [_read_stick_x(device), _read_stick_y(device)]
	)
	var pressed: PackedStringArray = []
	for button_index in range(PROBE_MAX_BUTTONS):
		if Input.is_joy_button_pressed(device, button_index):
			pressed.append("Btn %d" % button_index)
	if pressed.is_empty():
		lines.append("Buttons: (none)")
	else:
		lines.append("Buttons: " + ", ".join(pressed))
	return lines


static func _read_stick_x(device: int) -> float:
	var value := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	if absf(value) < 0.001:
		value = Input.get_joy_axis(device, 0 as JoyAxis)
	return value


static func _read_stick_y(device: int) -> float:
	var value := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	if absf(value) < 0.001:
		value = Input.get_joy_axis(device, 1 as JoyAxis)
	return value


static func _is_any_pressed(device: int, button_indices: Array) -> bool:
	for button_index in button_indices:
		if Input.is_joy_button_pressed(device, int(button_index)):
			return true
	return false
