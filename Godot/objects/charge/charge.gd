class_name Charge
extends Node2D
## A powder charge. Blasts rock, brick, earth, trees, bridges and soldiers within blast_radius when the fuse ends.
## The node origin is the top-left of its cell.

@export_range(0.1, 10.0, 0.1, "suffix:s") var fuse: float = 1.6
@export_range(0.5, 10.0, 0.1, "suffix:m") var blast_radius: float = 2.6
## Soldiers this much beyond the radius are still caught.
@export var soldier_margin: float = 0.4
## Other charges inside the blast go off after at most this long.
@export var chain_fuse: float = 0.12
@export var kill_text: String = "Caught in blast"
@export var explosion_sound: SoundEffect
@export var place_sound: SoundEffect
## One-shot effect scene spawned at the centre (flash, smoke).
@export var flash_scene: PackedScene
@export var shake: float = 0.45

@export_group("Look")
@export var ring_color: Color = Color(1, 0.416, 0.333, 0.6)
@export var fuse_color: Color = Color("e9a93b")
@export var spark_color: Color = Color("fff2c0")

var time_left: float = 0.0


func _ready() -> void:
	time_left = fuse
	Audio.play(place_sound, center_px())


func cell() -> Vector2i:
	return Grid.cell_of(Grid.to_m(position))


func center_px() -> Vector2:
	return position + Vector2.ONE * Grid.PX / 2


func _physics_process(dt: float) -> void:
	time_left -= dt
	queue_redraw()
	if time_left <= 0.0:
		explode()


func explode() -> void:
	var world := World.of(self)
	if world == null or is_queued_for_deletion():
		return
	var center := Grid.to_m(center_px())
	queue_free()
	GameState.gain(world.terrain.blast(center, blast_radius))
	world.bridge.blast(center, blast_radius)
	world.army.blast(center, blast_radius + soldier_margin, kill_text)
	for other in get_parent().get_children():
		if other is Charge and other != self and Grid.to_m(other.center_px()).distance_to(center) <= blast_radius + 0.5:
			other.time_left = minf(other.time_left, chain_fuse)
	Audio.play(explosion_sound, center_px())
	Effects.spawn(flash_scene, center_px())
	Effects.shake(shake)


func _draw() -> void:
	var c := Vector2.ONE * Grid.PX / 2
	var px := Grid.PX
	_dashed_circle(c, blast_radius * px, ring_color)
	draw_rect(Rect2(c - Vector2.ONE * 0.3 * px, Vector2.ONE * 0.6 * px), Color("2a2420"))
	draw_rect(Rect2(c + Vector2(-0.3, -0.05) * px, Vector2(0.6, 0.1) * px), fuse_color)
	draw_arc(c, 0.45 * px, -PI / 2, -PI / 2 + TAU * clampf(time_left / fuse, 0, 1), 24, fuse_color, 2.0)
	if fmod(time_left * 5.0, 1.0) > 0.5:
		draw_rect(Rect2(c + Vector2(-2, -0.45 * px), Vector2(4, 4)), spark_color)


func _dashed_circle(c: Vector2, r: float, color: Color) -> void:
	var n := maxi(16, int(r / 4))
	for i in range(0, n, 2):
		draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 3, color, 1.5)
