class_name Soldier
extends Node2D
## One marching soldier. Army moves it; this node only shows it.
## The node origin is at the feet. Edit the look and the "walk"/"idle"/"sleep" animations in soldier.tscn.
## While sleeping, Body is hidden and the optional Asleep node (tent and "z") is shown instead.

@export var hurt_flash_color: Color = Color.WHITE
@export_range(0.0, 2.0, 0.05, "suffix:s") var hurt_flash_time: float = 0.3
## Seconds standing still before the idle animation starts, so brief stops do not restart the walk cycle.
@export_range(0.0, 2.0, 0.05, "suffix:s") var idle_delay: float = 0.25
## On each blow at work (an engineer digging or chopping, on the beat of the work sound), it jolts this many
## pixels towards the work...
@export_range(0.0, 8.0, 1.0, "suffix:px") var work_shake_px: float = 1.0
## ...for this long, then stands still until the next blow.
@export_range(0.01, 1.0, 0.01, "suffix:s") var work_shake_time: float = 0.08

## Simulation state, in metres. Owned by Army.
var pos: Vector2
var vy: float = 0.0
var airborne: bool = false
var fall_from: float = 0.0
var hp: int = 2
var max_hp: int = 2
var speed: float = 1.7
var moving: bool = false
var on_member: Bridge.Member
var on_t: float = 0.0
var dead: bool = false
## Camped for the night. Owned by Army.
var sleeping: bool = false
## Joined at the camp flag and walking back to its place at this x, at the end of the camp line; the column counts
## it there meanwhile. NAN once there. Owned by Army.
var joining_x: float = NAN
## Seconds stood still while the column makes camp. Owned by Army.
var still_time: float = 0.0
## 1 faces east (the march), -1 west.
var facing: int = 1

## Seconds since the soldier last moved.
var _stood: float = INF
## Seconds until the next strike while fighting.
var attack_cooldown: float = 0.0
## Seconds stood blocked by a wall. Owned by Army.
var blocked_time: float = 0.0
## Fraction of the mutiny countdown left while blocked (1 to 0), shown on MutinyClock; 0 when not blocked.
## Owned by Army.
var mutiny_left: float = 0.0
## Left the column. Owned by Army.
var deserting: bool = false
## Metres a deserter still walks before it vanishes. Owned by Army.
var desert_left: float = 0.0
## A deserter climbing a wall face (gravity is off meanwhile). Owned by Army.
var climbing: bool = false
## Tilt (radians, about its feet) towards its work, its front turned that way: a builder leaning towards where its
## piece grows. Owned by Crew.
var lean: float = 0.0
## The way to the work of the last blow, and the seconds its jolt still lasts.
var _blow_dir: Vector2 = Vector2.ZERO
var _blow_left: float = 0.0

@onready var _anim: AnimationPlayer = %AnimationPlayer
@onready var _body: CanvasItem = %Body
@onready var _asleep: CanvasItem = get_node_or_null(^"%Asleep")
@onready var _clock: MutinyClock = get_node_or_null(^"%MutinyClock")


func _ready() -> void:
	_anim.play(&"idle")
	_anim.seek(randf() * 0.5)


func set_leader(is_leader: bool) -> void:
	%Flag.visible = is_leader
	%Spear.visible = not is_leader


func stand_on(surface: Dictionary) -> void:
	on_member = surface.get("member")
	on_t = surface.get("t", 0.0)


## Copies sim state to the node. Called by Army after each step.
func sync() -> void:
	position = Grid.to_px(pos) + work_shake()
	scale.x = facing
	rotation = lean
	%Wounded.visible = hp < max_hp
	var lying := sleeping and _asleep != null
	if _asleep:
		_asleep.visible = lying
	_body.visible = not lying
	if _clock:
		_clock.visible = mutiny_left > 0.0 and not deserting
		_clock.left = mutiny_left
	var walking := moving or _stood < idle_delay
	var want := &"sleep" if lying else (&"walk" if walking else &"idle")
	if _anim.current_animation != want:
		_anim.play(want)
	_anim.speed_scale = speed / 1.7


## Bottom (world pixels, y) of what it sleeps in: the sprites under Asleep. Its feet if it has none.
func tent_bottom() -> float:
	var bottom := -INF
	if _asleep:
		for s: Sprite2D in _asleep.find_children("*", "Sprite2D"):
			bottom = maxf(bottom, (s.global_transform * Vector2(0, s.get_rect().end.y)).y)
	return bottom if is_finite(bottom) else global_position.y


func _process(delta: float) -> void:
	_stood = 0.0 if moving else _stood + delta
	_blow_left = maxf(_blow_left - delta, 0.0)


## A blow at the work that lies the way dir (from its chest): it jolts towards it for work_shake_time.
func work_blow(dir: Vector2) -> void:
	_blow_dir = dir
	_blow_left = work_shake_time
	sync()


## Where the jolt of the last blow puts it (pixels from its feet): work_shake_px towards the work, one of eight
## ways, while it lasts, else nothing.
func work_shake() -> Vector2:
	if _blow_left <= 0.0 or _blow_dir == Vector2.ZERO:
		return Vector2.ZERO
	var d := _blow_dir.normalized()
	# Within 22.5 degrees of an axis, straight along it; otherwise diagonal.
	var way := Vector2(signf(d.x) if absf(d.x) > 0.38 else 0.0, signf(d.y) if absf(d.y) > 0.38 else 0.0)
	return (way * work_shake_px).round()


func flash_hurt() -> void:
	_body.modulate = hurt_flash_color * 3.0
	create_tween().tween_property(_body, ^"modulate", Color.WHITE, hurt_flash_time)
