extends Area2D
class_name FightHitbox

## An owner fighter's attack volume: detects opposing hurtboxes and projectiles
## during an active attack window, dealing damage to projectiles and announcing
## clean hits once per victim.


#region Signals

## Emitted when an opposing fighter is struck. payload: hit fighter, active attack data.
signal hit_landed(victim: CharacterBody2D, attack_data: Resource)

#endregion


#region Constants

const PROJECTILE_LAYER := 16

#endregion


#region Public state

var owner_fighter: CharacterBody2D
var attack_data: Resource

#endregion


#region Private state

var _hit_victims: Dictionary = {}

#endregion


#region Public API

## Binds the owning fighter, sets collision layers, and wires overlap detection.
func setup(owner_body: CharacterBody2D) -> void:
	owner_fighter = owner_body
	collision_layer = 8
	collision_mask = 4 | PROJECTILE_LAYER
	monitoring = false
	area_entered.connect(_on_area_entered)


## Opens the attack window: sizes/positions the shape from the data and starts
## monitoring, preserving already-hit victims when the same attack stays active.
func activate(data: Resource) -> void:
	var same_attack_window := monitoring and attack_data == data
	attack_data = data
	var shape_node := $CollisionShape2D as CollisionShape2D
	if shape_node.shape is RectangleShape2D:
		var rect := shape_node.shape as RectangleShape2D
		rect.size = data.hitbox_size
	shape_node.position = data.hitbox_offset
	if same_attack_window:
		return
	_hit_victims.clear()
	monitoring = true
	for area in get_overlapping_areas():
		_on_area_entered(area)


## Closes the attack window and clears the active attack data and hit record.
func deactivate() -> void:
	set_deferred("monitoring", false)
	attack_data = null
	_hit_victims.clear()

#endregion


#region Private helpers

func _on_area_entered(area: Area2D) -> void:
	if attack_data == null or owner_fighter == null:
		return
	if area is FightProjectile:
		var projectile := area as FightProjectile
		if projectile.owner_fighter == owner_fighter:
			return
		var data := attack_data as AttackData
		var damage: int = data.stagger_value
		if data.hit_type == AttackData.HitType.KILL:
			damage = 100
		projectile.take_hit(damage)
		return
	if not area is FightHurtbox:
		return
	var victim: CharacterBody2D = (area as FightHurtbox).owner_fighter
	if victim == null or victim == owner_fighter:
		return
	if _hit_victims.has(victim.get_instance_id()):
		return
	var victim_fighter := victim as Fighter
	if victim_fighter != null and attack_data.is_anti_air and victim_fighter.is_on_floor():
		return
	if victim_fighter != null and victim_fighter.state_machine.is_knockdown_falling():
		return
	if victim_fighter != null and victim_fighter.state_machine.is_invincible():
		return
	_hit_victims[victim.get_instance_id()] = true
	hit_landed.emit(victim, attack_data)

#endregion
