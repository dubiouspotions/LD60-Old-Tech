class_name Bird
extends Node2D
## A bird: flushed from the tall grass or a falling tree it bursts up and away (launch), or it crosses the sky in
## level flight (cruise). Gone after its life. The sheet faces right and is mirrored when flying left. Birds (the
## World's flock keeper) sends it off.

## Flying speed, metres per second.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var speed: float = 4.5
## Upward speed on take-off, metres per second.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var climb: float = 3.0
## How much faster it climbs each second.
@export_range(0.0, 20.0, 0.1, "suffix:m/s²") var lift: float = 1.5
## Flap animation speed, frames per second.
@export_range(1.0, 60.0, 0.5) var fps: float = 14.0
@export_range(0.5, 30.0, 0.1, "suffix:s") var life: float = 5.0

var velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _dir: float = 1.0
## Frame its flapping starts from, so a flock does not flap in step.
var _first_frame: int = 0

@onready var _sprite: Sprite2D = $Sprite


## Sets it off flying up and away in direction dir (1 right, -1 left) in color, with a little random variety.
func launch(dir: float, color: Color, rng: RandomNumberGenerator) -> void:
	_start(dir, color, rng)
	velocity = Vector2(_dir * speed * rng.randf_range(0.6, 1.0), -climb * rng.randf_range(0.7, 1.2))


## Sets it off in level flight in direction dir, for long enough to cover distance metres.
func cruise(dir: float, color: Color, rng: RandomNumberGenerator, distance: float) -> void:
	_start(dir, color, rng)
	velocity = Vector2(_dir * speed, 0.0)
	lift = 0.0
	life = distance / speed + 1.0


func _start(dir: float, color: Color, rng: RandomNumberGenerator) -> void:
	_dir = signf(dir) if dir != 0.0 else 1.0
	$Sprite.flip_h = _dir < 0.0
	$Sprite.self_modulate = color
	_first_frame = rng.randi() % $Sprite.hframes
	$Sprite.frame = _first_frame


func _physics_process(dt: float) -> void:
	_age += dt
	velocity.x = move_toward(velocity.x, _dir * speed, speed * dt)
	velocity.y -= lift * dt
	position += velocity * dt * Grid.PX
	_sprite.frame = (_first_frame + int(_age * fps)) % _sprite.hframes
	if _age >= life:
		queue_free()
