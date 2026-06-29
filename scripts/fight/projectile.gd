extends Area2D
class_name FightProjectile

## Base straight-line projectile: travels horizontally at a fixed speed, hits the
## first enemy fighter it overlaps, and clashes with other projectiles by size.
## Despawns on hit, on timeout, or when it leaves the arena bounds.


#region Constants

const HURTBOX_LAYER := 4
const PROJECTILE_LAYER := 16

#endregion


#region Onready

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var body_rect: ColorRect = $BodyRect

#endregion


#region Public state

var owner_fighter: Fighter
var direction: int = 1
var speed: float = 420.0
var stagger_damage: int = 4
var health: int = 4
var knockback: float = 175.0
var charge_ratio: float = 0.0
var size_value: float = 14.0
var is_low_angle: bool = false
var hit_effect_scene: PackedScene

#endregion


#region Private state

var _hit_fighters: Dictionary = {}
var _destroyed: bool = false
var _lifetime: float = 0.0
var _max_lifetime: float = 2.5
var _size_similarity_ratio: float = 0.72

#endregion


#region Lifecycle

func _ready() -> void:
	collision_layer = PROJECTILE_LAYER
	collision_mask = HURTBOX_LAYER | PROJECTILE_LAYER
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _destroyed:
		return
	_apply_motion(delta)
	_lifetime += delta
	if _lifetime >= _max_lifetime:
		destroy()
		return
	_check_bounds()

#endregion


#region Public API

## Configures the projectile from the firing fighter and config, scaling stagger,
## health, and size by charge, then positions it at the resolved spawn offset.
func setup(from_fighter: Fighter, charge: float, config: ProjectileConfig, low_angle: bool = false) -> void:
	owner_fighter = from_fighter
	direction = from_fighter.facing
	charge_ratio = clampf(charge, 0.0, 1.0)
	is_low_angle = low_angle

	stagger_damage = int(
		lerpf(float(config.min_stagger), float(config.max_stagger), charge_ratio)
	)
	health = int(lerpf(float(config.min_health), float(config.max_health), charge_ratio))
	knockback = config.knockback
	speed = config.speed
	hit_effect_scene = config.hit_effect_scene
	_max_lifetime = CombatTiming.scale_time(config.max_lifetime)
	_size_similarity_ratio = config.size_similarity_ratio

	var size := config.min_size.lerp(config.max_size, charge_ratio)
	size_value = maxf(size.x, size.y)
	_apply_size(size)

	var spawn_offset := _resolve_spawn_offset(config, from_fighter.is_on_floor())
	global_position = from_fighter.global_position + Vector2(spawn_offset.x * direction, spawn_offset.y)

	body_rect.color = from_fighter.body_color.lightened(0.35)

	for area in get_overlapping_areas():
		_on_area_entered(area)


## Subtracts health and destroys the projectile once it drops to zero.
func take_hit(damage: int) -> void:
	if _destroyed:
		return
	health -= damage
	if health <= 0:
		destroy()


## Disables collision and frees the projectile; safe to call more than once.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()


## Builds the AttackData for an impact, resolving kill vs. stagger from the
## current stagger damage and the owner's auto-kill threshold.
func get_attack_data() -> AttackData:
	var data := AttackData.new()
	data.id = "projectile"
	data.is_projectile = true
	data.source_x = global_position.x
	data.knockback = knockback
	data.stagger_value = stagger_damage
	if stagger_damage >= 100:
		data.hit_type = AttackData.HitType.KILL
	elif owner_fighter != null and owner_fighter.stats.projectile_config != null:
		if stagger_damage >= owner_fighter.stats.projectile_config.auto_kill_stagger:
			data.hit_type = AttackData.HitType.KILL
		else:
			data.hit_type = AttackData.HitType.STAGGER
	else:
		data.hit_type = AttackData.HitType.STAGGER
	data.hitstun_seconds = -1.0
	return data

#endregion


#region Private helpers

func _resolve_spawn_offset(config: ProjectileConfig, on_floor: bool) -> Vector2:
	if is_low_angle:
		return config.low_spawn_offset if on_floor else config.air_low_spawn_offset
	return config.spawn_offset if on_floor else config.air_spawn_offset


func _check_bounds() -> void:
	var fm := owner_fighter.fight_manager if owner_fighter != null else null
	if fm == null:
		return
	if global_position.x < fm.get_left_edge_x() - 80.0 or global_position.x > fm.get_right_edge_x() + 80.0:
		destroy()


func _apply_size(size: Vector2) -> void:
	if collision_shape.shape is RectangleShape2D:
		(collision_shape.shape as RectangleShape2D).size = size
	collision_shape.position = Vector2.ZERO
	body_rect.size = size
	body_rect.position = -size * 0.5


func _apply_motion(delta: float) -> void:
	global_position.x += direction * speed * delta


func _on_area_entered(area: Area2D) -> void:
	if _destroyed:
		return
	if area is FightHurtbox:
		_try_hit_fighter(area as FightHurtbox)
	elif area is FightProjectile and area != self:
		_try_clash_with(area as FightProjectile)


func _try_hit_fighter(hurtbox: FightHurtbox) -> void:
	if owner_fighter == null:
		return
	var victim := hurtbox.owner_fighter as Fighter
	if victim == null or victim == owner_fighter:
		return
	if victim.state_machine.is_knockdown_falling():
		return
	var victim_id := victim.get_instance_id()
	if _hit_fighters.has(victim_id):
		return
	_hit_fighters[victim_id] = true
	victim.receive_hit(owner_fighter, get_attack_data())
	# plays the projectile_hit_effect animation.
	_on_hit_fighter(victim)
	destroy()


# Spawns the config's hit effect at the impact point, parented to the arena (a sibling)
# since the projectile frees itself on this same hit. Override for custom behavior.
func _on_hit_fighter(victim: Fighter) -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate() as Node2D
	get_parent().add_child(fx)
	# On the fighter (its x) at the height the projectile struck (the projectile's y).
	fx.global_position = Vector2(victim.global_position.x, global_position.y)


func _try_clash_with(other: FightProjectile) -> void:
	if other._destroyed or _destroyed:
		return
	if get_instance_id() > other.get_instance_id():
		return
	_resolve_projectile_clash(other)


func _resolve_projectile_clash(other: FightProjectile) -> void:
	var self_size := size_value
	var other_size := other.size_value
	var larger := maxf(self_size, other_size)
	var smaller := minf(self_size, other_size)
	if larger <= 0.0:
		destroy()
		other.destroy()
		return
	if smaller / larger >= _size_similarity_ratio:
		destroy()
		other.destroy()
		return
	if self_size >= other_size:
		other.destroy()
		take_hit(other.stagger_damage)
	else:
		destroy()
		other.take_hit(stagger_damage)

#endregion
