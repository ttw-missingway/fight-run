extends FightProjectile
class_name MimicProjectile

## Mimic's arcing coin: lobs under gravity, then on contact with the stage floor
## spins in place as a grounded hitbox for the linger duration. Over the final
## stretch it flashes a despawn warning, then topples over (no longer a hitbox)
## and fades out.


#region Constants

const WORLD_LAYER: int = 1

#endregion


#region Private state

var _velocity: Vector2 = Vector2.ZERO
var _gravity: float = 0.0
var _landed: bool = false
var _linger_seconds: float = 8.0
var _spin_degrees: float = 90.0
var _sprite_scale: float = 2.0
var _flash_seconds: float = 3.0
var _flash_interval: float = 0.15
var _fade_out_seconds: float = 0.25
var _rest_nudge: float = 0.0
var _flash_tween: Tween

#endregion


#region Lifecycle

func _ready() -> void:
	super()
	# Also watch the stage floor; the floor is a body, so it arrives via body_entered.
	collision_mask |= WORLD_LAYER
	body_entered.connect(_on_body_entered)

#endregion


#region Public API

## Extends the base spawn: seeds the arc velocity, sizes the coin, and starts the spin.
func setup(from_fighter: Fighter, charge: float, config: ProjectileConfig, low_angle: bool = false) -> void:
	super(from_fighter, charge, config, low_angle)
	var mc := config as MimicProjectileConfig
	_gravity = mc.gravity
	# Coin charge affects only linger duration and arc size; damage/hitbox are fixed.
	var tier := _charge_tier(charge_ratio, mc)
	_linger_seconds = _linger_for_tier(tier, mc)
	# Each charge stage above base scales the target height and distance; gravity then
	# sets how snappy the resulting lob is.
	var stage_factor := 1.0 + float(tier) * (mc.charge_stage_multiplier - 1.0)
	_velocity = _arc_launch_velocity(mc.arc_base_height * stage_factor, mc.arc_base_distance * stage_factor)
	_spin_degrees = mc.landing_spin_degrees
	_sprite_scale = mc.sprite_scale
	_flash_seconds = mc.flash_seconds
	_flash_interval = mc.flash_interval
	_fade_out_seconds = mc.fade_out_seconds
	_rest_nudge = mc.ground_rest_nudge
	var spr := $AnimatedSprite2D as AnimatedSprite2D
	spr.scale = Vector2(_sprite_scale * direction, _sprite_scale)
	spr.play("fly")

#endregion


#region Private helpers

func _apply_motion(delta: float) -> void:
	if _landed:
		# Frozen in place while the coin spins as a grounded hitbox.
		return
	# Gravity bends the arc down.
	_velocity.y += _gravity * delta
	global_position += _velocity * delta


func _on_body_entered(_body: Node) -> void:
	# Only the stage floor is in our mask, so any body contact means we landed.
	_on_land()


func _on_land() -> void:
	if _landed:
		return
	_landed = true
	# body_entered fires after the shape has already dipped into the floor, so snap
	# the coin flush to the real ground surface rather than freezing where it overshot.
	_snap_to_ground()
	# Cancel the base flight timeout; the linger phase governs lifetime from here.
	_max_lifetime = INF
	# Keep spinning as a live hitbox: flash a warning over the tail, then topple.
	var flash_delay := maxf(_linger_seconds - _flash_seconds, 0.0)
	get_tree().create_timer(flash_delay).timeout.connect(_start_flashing)
	get_tree().create_timer(_linger_seconds).timeout.connect(_topple)


## Coin charge tier by how long the shot was actually held: 0 = below half, 1 = half,
## 2 = full. The charge curve is logarithmic, so the damage ratio is converted back to
## a linear time fraction first — matching the player's "half charge" feel and flash.
func _charge_tier(ratio: float, mc: MimicProjectileConfig) -> int:
	var held := _charge_time_fraction(ratio, mc)
	if held >= mc.full_charge_threshold:
		return 2
	if held >= mc.half_charge_threshold:
		return 1
	return 0


func _linger_for_tier(tier: int, mc: MimicProjectileConfig) -> float:
	match tier:
		2:
			return mc.ground_linger_seconds
		1:
			return mc.linger_half_seconds
		_:
			return mc.linger_min_seconds


## Converts a target peak height + horizontal distance into a launch velocity for the
## configured gravity. Negative vy lobs upward; x carries the throw direction.
func _arc_launch_velocity(height: float, distance: float) -> Vector2:
	if height <= 0.0 or _gravity <= 0.0:
		return Vector2(direction * distance, 0.0)
	var vy := -sqrt(2.0 * _gravity * height)
	var flight := 2.0 * absf(vy) / _gravity
	return Vector2(direction * distance / flight, vy)


## Inverts the logarithmic charge curve to recover the fraction of max hold time.
func _charge_time_fraction(ratio: float, mc: MimicProjectileConfig) -> float:
	var scaled_max := CombatTiming.scale_time(mc.max_charge_time)
	var a := scaled_max * mc.charge_log_speed
	if a <= 0.0:
		return ratio
	return clampf((pow(1.0 + a, ratio) - 1.0) / a, 0.0, 1.0)


func _snap_to_ground() -> void:
	var fm := owner_fighter.fight_manager if owner_fighter != null else null
	if fm == null:
		return
	# Rest the coin's visible (opaque) bottom flush on the surface, plus any nudge.
	global_position.y = fm.get_ground_y(global_position.x) - _sprite_bottom_offset() - _rest_nudge


## Distance in px from the coin's origin down to the lowest opaque pixel of the
## current sprite frame, accounting for its scale and rotation, so the visible coin
## rests flush whether upright or toppled. Falls back to the full frame if the image
## can't be read.
func _sprite_bottom_offset() -> float:
	var spr := $AnimatedSprite2D as AnimatedSprite2D
	var frames := spr.sprite_frames
	if frames == null:
		return 0.0
	var tex := frames.get_frame_texture(spr.animation, spr.frame)
	if tex == null:
		return 0.0
	var frame_size := Vector2(tex.get_width(), tex.get_height())
	var img := tex.get_image()
	var rect := Rect2(Vector2.ZERO, frame_size)
	if img != null:
		rect = Rect2(img.get_used_rect())
	# Project the opaque rect's corners through the sprite's scale + rotation and
	# take the lowest (largest screen-Y), relative to the centered origin.
	var center := frame_size * 0.5
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y),
		rect.end,
	]
	var lowest := -INF
	for corner in corners:
		var local: Vector2 = (corner - center) * spr.scale
		lowest = maxf(lowest, local.rotated(spr.rotation).y)
	return lowest


func _start_flashing() -> void:
	if _destroyed:
		return
	var spr := $AnimatedSprite2D as AnimatedSprite2D
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_callback(spr.hide)
	_flash_tween.tween_interval(_flash_interval)
	_flash_tween.tween_callback(spr.show)
	_flash_tween.tween_interval(_flash_interval)


func _topple() -> void:
	if _destroyed:
		return
	# Stop the warning flash and restore visibility for the topple.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var spr := $AnimatedSprite2D as AnimatedSprite2D
	spr.show()
	# No longer a hitbox once it tips onto its side.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	# Tip onto its side, then re-snap so the rotated sprite rests flush (its upright
	# snap leaves it hovering), and fade out quickly before despawning.
	spr.stop()
	spr.frame = 3
	spr.rotation = deg_to_rad(_spin_degrees)
	_snap_to_ground()
	var tween := create_tween()
	tween.tween_property(spr, "modulate:a", 0.0, _fade_out_seconds)
	tween.tween_callback(destroy)

#endregion
