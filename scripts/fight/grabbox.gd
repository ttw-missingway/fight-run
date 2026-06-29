extends Area2D
class_name FightGrabbox

## An owner fighter's grab volume: detects an opponent's hurtbox during an active
## grab window and announces the catch once per victim.


#region Signals

## Emitted when an opposing fighter is grabbed. payload: caught fighter, active grab data.
signal grab_landed(victim: CharacterBody2D, grab_data: Resource)

#endregion


#region Public state

var owner_fighter: CharacterBody2D
var grab_data: Resource

#endregion


#region Private state

var _grabbed_victims: Dictionary = {}

#endregion


#region Public API

## Binds the owning fighter, sets collision layers, and wires overlap detection.
func setup(owner_body: CharacterBody2D) -> void:
	owner_fighter = owner_body
	collision_layer = 8
	collision_mask = 4
	monitoring = false
	area_entered.connect(_on_area_entered)


## Opens the grab window: sizes/positions the shape from the data and starts monitoring.
func activate(data: Resource) -> void:
	grab_data = data
	_grabbed_victims.clear()
	monitoring = true
	var shape_node := $CollisionShape2D as CollisionShape2D
	if shape_node.shape is RectangleShape2D:
		var rect := shape_node.shape as RectangleShape2D
		rect.size = data.grab_size
	shape_node.position = data.grab_offset
	for area in get_overlapping_areas():
		_on_area_entered(area)


## Closes the grab window and clears the active grab data.
func deactivate() -> void:
	set_deferred("monitoring", false)
	grab_data = null

#endregion


#region Private helpers

func _on_area_entered(area: Area2D) -> void:
	if grab_data == null or owner_fighter == null:
		return
	if not area is FightHurtbox:
		return
	var victim: CharacterBody2D = (area as FightHurtbox).owner_fighter
	if victim == null or victim == owner_fighter:
		return
	if _grabbed_victims.has(victim.get_instance_id()):
		return
	_grabbed_victims[victim.get_instance_id()] = true
	grab_landed.emit(victim, grab_data)

#endregion
