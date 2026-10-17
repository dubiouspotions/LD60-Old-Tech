class_name FallingBlock
extends Node2D
## A tile falling straight down until it lands, then it becomes that tile again.
## The node origin is the top-left of the cell.

@export var type: TerrainType
@export var gravity: float = 30.0
@export var max_speed: float = 22.0
@export var land_sound: SoundEffect

var _vy: float = 0.0


func _physics_process(dt: float) -> void:
	var level := Level.of(self)
	if level == null:
		return
	var t := level.terrain
	var x := floori(position.x / Grid.PX)
	_vy = minf(_vy + gravity * dt, max_speed)
	position.y += _vy * dt * Grid.PX
	var r := floori(position.y / Grid.PX)
	if r + 1 >= t.size.y or t.is_solid(Vector2i(x, r + 1)):
		while r > 0 and t.is_solid(Vector2i(x, r)):
			r -= 1
		t.set_type(Vector2i(x, r), type)
		var at := Grid.to_px(Vector2(x + 0.5, r + 1))
		Effects.debris(at, type.debris_color if type else Color.WHITE, 3, 70.0)
		Audio.play(land_sound, at)
		queue_free()


func cell_x() -> int:
	return floori(position.x / Grid.PX)
