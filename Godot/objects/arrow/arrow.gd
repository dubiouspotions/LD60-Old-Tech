class_name Arrow
extends Node2D
## A flying arrow. Sticks in ground and in arrow-blocking bridge members (logs), wounds the first soldier
## it passes through.

@export var kill_text: String = "Shot"
@export var hit_sound: SoundEffect
@export_range(0.1, 10.0, 0.1, "suffix:s") var stuck_time: float = 1.2
@export_range(0.5, 20.0, 0.5, "suffix:s") var max_flight: float = 4.0
## Half width of a soldier for hit tests.
@export var soldier_half_width: float = 0.32

## Metres per second; set by the archer.
var velocity: Vector2
var gravity: float = 12.0
## The archer's own tower column is ignored right after the shot.
var shooter_column: int = -999

var _age: float = 0.0
var _stuck: float = -1.0


func _ready() -> void:
	rotation = velocity.angle()


func _physics_process(dt: float) -> void:
	if _stuck >= 0.0:
		_stuck -= dt
		if _stuck < 0.0:
			queue_free()
		return
	var world := World.of(self)
	if world == null:
		return
	_age += dt
	var from := Grid.to_m(position)
	position += velocity * dt * Grid.PX
	velocity.y += gravity * dt
	rotation = velocity.angle()
	var p := Grid.to_m(position)
	var block: Variant = world.bridge.arrow_block(from, p)
	if block != null:
		position = Grid.to_px(block)
		Audio.play(hit_sound, position)
		_stuck = stuck_time
		return
	var cell := Grid.cell_of(p)
	var own_tower := _age < 0.12 and absi(cell.x - shooter_column) <= 1
	if not own_tower and world.terrain.is_solid(cell):
		_stuck = stuck_time
		return
	if _age > max_flight:
		queue_free()
		return
	for s in world.army.soldiers:
		if absf(s.pos.x - p.x) < soldier_half_width and p.y > s.pos.y - 1.0 and p.y < s.pos.y:
			Audio.play(hit_sound, position)
			world.army.hit(s, kill_text)
			queue_free()
			return
