class_name Soldier
extends Node2D
## One marching soldier. Army moves it; this node only shows it.
## The node origin is at the feet. Edit the look and the "walk"/"idle"/"sleep" animations in soldier.tscn.
## While sleeping, Body is hidden and the optional Asleep node (tent and "z") is shown instead.

@export var hurt_flash_color: Color = Color.WHITE
@export_range(0.0, 2.0, 0.05, "suffix:s") var hurt_flash_time: float = 0.3
## Seconds standing still before the idle animation starts, so brief stops do not restart the walk cycle.
@export_range(0.0, 2.0, 0.05, "suffix:s") var idle_delay: float = 0.25

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
## Left the column. Owned by Army.
var deserting: bool = false
## Metres a deserter still walks before it vanishes. Owned by Army.
var desert_left: float = 0.0
## A deserter climbing a wall face (gravity is off meanwhile). Owned by Army.
var climbing: bool = false

@onready var _anim: AnimationPlayer = %AnimationPlayer
@onready var _body: CanvasItem = %Body
@onready var _asleep: CanvasItem = get_node_or_null(^"%Asleep")


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
	position = Grid.to_px(pos)
	scale.x = facing
	%Wounded.visible = hp < max_hp
	var lying := sleeping and _asleep != null
	if _asleep:
		_asleep.visible = lying
	_body.visible = not lying
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


func flash_hurt() -> void:
	_body.modulate = hurt_flash_color * 3.0
	create_tween().tween_property(_body, ^"modulate", Color.WHITE, hurt_flash_time)
