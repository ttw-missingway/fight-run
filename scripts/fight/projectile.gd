extends Area2D
class_name FightProjectile

const HURTBOX_LAYER := 4
const PROJECTILE_LAYER := 16

var owner_fighter: Fighter
var direction: int = 1
var speed: float = 420.0
var stagger_damage: int = 4
var health: int = 4
var knockback: float = 175.0
var charge_ratio: float = 0.0
var size_value: float = 14.0
var is_low_angle: bool = false

var _hit_fighters: Dictionary = {}
var _destroyed: bool = false
var _lifetime: float = 0.0
var _max_lifetime: float = 2.5
var _size_similarity_ratio: float = 0.72

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var body_rect: ColorRect = $BodyRect


func _ready() -> void:
	collision_layer = PROJECTILE_LAYER
	collision_mask = HURTBOX_LAYER | PROJECTILE_LAYER
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)


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


func _resolve_spawn_offset(config: ProjectileConfig, on_floor: bool) -> Vector2:
	if is_low_angle:
		return config.low_spawn_offset if on_floor else config.air_low_spawn_offset
	return config.spawn_offset if on_floor else config.air_spawn_offset


func _physics_process(delta: float) -> void:
	if _destroyed:
		return
	global_position.x += direction * speed * delta
	_lifetime += delta
	if _lifetime >= _max_lifetime:
		destroy()
		return
	_check_bounds()


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


func take_hit(damage: int) -> void:
	if _destroyed:
		return
	health -= damage
	if health <= 0:
		destroy()


func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()


func get_attack_data() -> AttackData:
	var data := AttackData.new()
	data.id = "projectile"
	data.is_projectile = true
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
	destroy()


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
