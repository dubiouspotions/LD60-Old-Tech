class_name Soldier
extends Node2D
## One marching soldier. Army moves it; this node only shows it.
## The node origin is at the feet. Edit the look and the "walk"/"idle"/"sleep" animations in soldier.tscn.
## While sleeping, Body is hidden and the optional Asleep node (lying pose) is shown instead.

@export var hurt_flash_color: Color = Color.WHITE
@export_range(0.0, 2.0, 0.05, "suffix:s") var hurt_flash_time: float = 0.3

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
## Seconds until the next strike while fighting.
var attack_cooldown: float = 0.0

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
	%Wounded.visible = hp < max_hp
	var lying := sleeping and _asleep != null
	if _asleep:
		_asleep.visible = lying
	_body.visible = not lying
	var want := &"sleep" if lying else (&"walk" if moving else &"idle")
	if _anim.current_animation != want:
		_anim.play(want)
	_anim.speed_scale = speed / 1.7


func flash_hurt() -> void:
	_body.modulate = hurt_flash_color * 3.0
	create_tween().tween_property(_body, ^"modulate", Color.WHITE, hurt_flash_time)
