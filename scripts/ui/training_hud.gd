extends CanvasLayer


#region Signals

# Emitted when the player picks an AI behavior mode in the menu.
signal ai_mode_selected(mode: int)

# Emitted when the Infinite Lives toggle changes.
signal infinite_mode_toggled(enabled: bool)

# Emitted when the debug "Knock Down" button is pressed.
signal debug_knockdown_requested

# Emitted when the "Show Input Buffer" toggle changes.
signal input_buffer_toggled(enabled: bool)

# Emitted when a character is chosen in the Player / AI dropdowns.
signal player_character_selected(stats: FighterStats)
signal ai_character_selected(stats: FighterStats)

#endregion


#region Onready

@onready var _panel: PanelContainer = $AiSelectorPanel
@onready var _infinite_toggle: CheckButton = $AiSelectorPanel/VBox/InfiniteToggle
@onready var _inner: VBoxContainer = $AiSelectorPanel/VBox/Scroll/Inner

#endregion


#region Privatestate

var _infinite_lives: bool = false
var _ai_buttons: Dictionary = {}
var _mode_button_group := ButtonGroup.new()
var _characters: Array = []
var _player_char_option: OptionButton
var _ai_char_option: OptionButton

#endregion


#region Lifecycle

func _ready() -> void:
	_panel.visible = false
	# PauseMenu owns pause + Esc; we only show/hide our panel in response.
	PauseMenu.opened.connect(_on_pause_opened)
	PauseMenu.closed.connect(_on_pause_closed)
	_infinite_toggle.toggled.connect(func(enabled: bool) -> void:
		_infinite_lives = enabled
		infinite_mode_toggled.emit(enabled)
	)
	_build_character_section()
	_add_mode_selection(_inner, "Simple AI", AiController.SIMPLE_MODES)
	_add_mode_selection(_inner, "Complex AI", AiController.COMPLEX_MODES)
	_build_debug_section()

#endregion


#region PublicAPI

func set_active_ai_mode(mode: int) -> void:
	for mode_key in _ai_buttons:
		_ai_buttons[mode_key].button_pressed = mode_key == mode


# Preselects the dropdowns to the characters currently in the match. Uses
# OptionButton.select(), which does NOT emit item_selected, so this won't
# trigger a reload.
func set_active_characters(player_stats: FighterStats, ai_stats: FighterStats) -> void:
	_select_character(_player_char_option, player_stats)
	_select_character(_ai_char_option, ai_stats)

#endregion


#region Privatehelpers

func _on_pause_opened() -> void:
	_panel.visible = true

func _on_pause_closed() -> void:
	_panel.visible = false

func _add_mode_selection(parent: VBoxContainer, title: String, modes: Array) -> void:
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

func _build_debug_section() -> void:
	var header := Label.new()
	header.text = "Debug"
	header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_inner.add_child(header)

	var knockdown_button := Button.new()
	knockdown_button.text = "Knock Down (K)"
	knockdown_button.pressed.connect(func() -> void: debug_knockdown_requested.emit())
	_inner.add_child(knockdown_button)

	var buffer_toggle := CheckButton.new()
	buffer_toggle.text = "Show Input Buffer"
	buffer_toggle.toggled.connect(func(enabled: bool) -> void: input_buffer_toggled.emit(enabled))
	_inner.add_child(buffer_toggle)

func _build_character_section() -> void:
	var header := Label.new()
	header.text = "Characters"
	header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_inner.add_child(header)

	_characters = _discover_characters()
	_player_char_option = _add_character_row("Player", player_character_selected)
	_ai_char_option = _add_character_row("AI", ai_character_selected)

func _add_character_row(label_text: String, on_selected: Signal) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(60.0, 0.0)
	row.add_child(label)

	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(150.0, 0.0)
	for i in _characters.size():
		option.add_item(_characters[i].name, i)
	option.item_selected.connect(func(index: int) -> void:
		on_selected.emit(_characters[index].stats)
	)
	row.add_child(option)
	_inner.add_child(row)
	return option

func _select_character(option: OptionButton, stats: FighterStats) -> void:
	if option == null or stats == null:
		return
	for i in _characters.size():
		var candidate: FighterStats = _characters[i].stats
		if candidate == stats or candidate.resource_path == stats.resource_path:
			option.select(i)
			return

# Auto-discovers playable characters by scanning for FighterStats resources, so
# dropping in a new *_fighter_stats.tres makes it selectable with no code change.
func _discover_characters() -> Array:
	var found: Array = []
	var dir := DirAccess.open("res://scripts/resources/")
	if dir == null:
		return found
	for file in dir.get_files():
		if not file.ends_with("fighter_stats.tres"):
			continue
		var res := load("res://scripts/resources/" + file)
		if res is FighterStats:
			found.append({"name": _character_display_name(res, file), "stats": res})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return found

# A character's display name is its visual rig's root node name (e.g. "Knight"),
# falling back to a prettified file name if it has no visual scene.
func _character_display_name(stats: FighterStats, file: String) -> String:
	if stats.visual_scene != null:
		var state := stats.visual_scene.get_state()
		if state != null and state.get_node_count() > 0:
			return String(state.get_node_name(0))
	return file.get_basename().capitalize()

#endregion
