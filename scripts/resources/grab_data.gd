extends Resource
class_name GrabData


#region Exports

@export var id: String = "throw"
@export var startup_frames: int = 12
@export var active_frames: int = 4
@export var recovery_frames: int = 16
@export var whiff_recovery_frames: int = 44
@export var grab_offset: Vector2 = Vector2(30, -28)
@export var grab_size: Vector2 = Vector2(36, 40)
@export var throw_knockback: float = 450.0
@export var grab_advance_speed: float = 0.0
@export var grab_hold_offset: float = 24.0

#endregion
