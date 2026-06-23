extends RefCounted
class_name FightInputBuffer

enum Intent {
	NONE = -1,
	JUMP,
	ATTACK,
	THROW,
	PROJECTILE,
	GUARD,
	CROUCH,
	DASH,
}

const BUFFER_FRAMES := 5
const MAX_QUEUE_SIZE := 6
const ACTION_QUEUE_FRAMES := 15

const TRACKED_ACTIONS := [
	"attack",
	"jump",
	"move_up",
	"guard",
	"grab",
	"projectile",
	"move_down",
	"move_left",
	"move_right",
]

const INTENT_LABELS := {
	Intent.JUMP: "Jump",
	Intent.ATTACK: "Attack",
	Intent.THROW: "Throw",
	Intent.PROJECTILE: "Projectile",
	Intent.GUARD: "Guard",
	Intent.CROUCH: "Crouch",
	Intent.DASH: "Dash",
}

var _ages: Dictionary = {}
var _queue: Array[Dictionary] = []


func reset() -> void:
	_ages.clear()
	_queue.clear()


func age_buffers() -> void:
	var expired: Array[String] = []
	for action in _ages.keys():
		_ages[action] += 1
		if _ages[action] > BUFFER_FRAMES:
			expired.append(action)
	for action in expired:
		_ages.erase(action)


func age_queue() -> void:
	var expired_indices: Array[int] = []
	for i in _queue.size():
		_queue[i]["age"] += 1
		if _queue[i]["age"] > ACTION_QUEUE_FRAMES:
			expired_indices.append(i)
	for i in range(expired_indices.size() - 1, -1, -1):
		_queue.remove_at(expired_indices[i])


func capture_player_input() -> void:
	for action in TRACKED_ACTIONS:
		if Input.is_action_just_pressed(action):
			_mark_pressed(action)


func capture_action_intents(fighter: Fighter) -> void:
	var throw_fresh := (
		Input.is_action_just_pressed("attack")
		or Input.is_action_just_pressed("guard")
		or Input.is_action_just_pressed("grab")
		or is_recent("attack")
		or is_recent("guard")
		or is_recent("grab")
	)
	if throw_fresh and is_attack_held() and is_guard_held():
		_enqueue(Intent.THROW)
		clear_action("attack")
		clear_action("guard")
		clear_action("grab")
		return

	if Input.is_action_just_pressed("grab"):
		_enqueue(Intent.THROW)
		clear_action("grab")
		return

	if Input.is_action_just_pressed("attack"):
		var snap := fighter.build_input_snapshot()
		if fighter.is_on_floor() and (snap.get("up", false) or is_recent("move_up")):
			snap["attack_name"] = "anti_air"
		else:
			snap["attack_name"] = fighter.resolve_buffered_attack_name(snap)
		_enqueue(Intent.ATTACK, snap)
		clear_action("attack")
		return

	if Input.is_action_just_pressed("projectile"):
		var snap := fighter.build_input_snapshot()
		_enqueue(Intent.PROJECTILE, snap)
		clear_action("projectile")
		return

	if Input.is_action_just_pressed("guard"):
		_enqueue(Intent.GUARD)
		clear_action("guard")
		return

	if Input.is_action_just_pressed("move_down") and fighter.is_on_floor():
		_enqueue(Intent.CROUCH)
		clear_action("move_down")
		return

	if Input.is_action_just_pressed("jump") and not is_attack_held():
		_enqueue(Intent.JUMP)
		clear_action("jump")


func enqueue_dash(direction: int) -> void:
	if direction == 0:
		return
	_enqueue(Intent.DASH, {"dash_direction": direction})


func _enqueue(intent: Intent, data: Dictionary = {}) -> void:
	for entry in _queue:
		if entry["intent"] == intent:
			entry["age"] = 0
			entry["data"] = data.duplicate()
			return
	_queue.append({"intent": intent, "age": 0, "data": data.duplicate()})
	while _queue.size() > MAX_QUEUE_SIZE:
		_queue.pop_front()


func peek_entry() -> Dictionary:
	if _queue.is_empty():
		return {}
	return _queue[0]


func peek_intent() -> Intent:
	var entry := peek_entry()
	if entry.is_empty():
		return Intent.NONE
	return entry["intent"] as Intent


func pop_intent() -> Intent:
	if _queue.is_empty():
		return Intent.NONE
	var intent: Intent = _queue[0]["intent"]
	_queue.pop_front()
	return intent


func has_queued_intents() -> bool:
	return not _queue.is_empty()


func queue_length() -> int:
	return _queue.size()


func get_queue_display_text() -> String:
	if _queue.is_empty():
		return "(empty)"
	var parts: PackedStringArray = []
	for entry in _queue:
		var intent: Intent = entry["intent"]
		if not INTENT_LABELS.has(intent):
			continue
		var label: String = INTENT_LABELS[intent]
		var data: Dictionary = entry.get("data", {})
		if intent == Intent.ATTACK and data.has("attack_name"):
			label = "%s (%s)" % [label, str(data["attack_name"])]
		elif intent == Intent.DASH and data.has("dash_direction"):
			var dir := int(data["dash_direction"])
			label = "%s (%s)" % [label, "←" if dir < 0 else "→"]
		var remaining: int = ACTION_QUEUE_FRAMES - int(entry["age"])
		parts.append("%s %df" % [label, maxi(remaining, 0)])
	return " → ".join(parts)


func _mark_pressed(action: String) -> void:
	_ages[action] = 0


func is_recent(action: String, max_age: int = -1) -> bool:
	if max_age < 0:
		max_age = BUFFER_FRAMES
	return _ages.get(action, 999) <= max_age


func clear_action(action: String) -> void:
	_ages.erase(action)


func is_up_held() -> bool:
	return Input.is_action_pressed("move_up")


func is_attack_held() -> bool:
	return Input.is_action_pressed("attack")


func is_guard_held() -> bool:
	return Input.is_action_pressed("guard")


func remove_intent(intent: Intent) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i]["intent"] == intent:
			_queue.remove_at(i)


func attack_pressed_for_combo() -> bool:
	return Input.is_action_just_pressed("attack") or is_recent("attack")
