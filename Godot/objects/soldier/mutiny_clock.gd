@tool
class_name MutinyClock
extends Node2D
## Pie clock over a soldier blocked by a wall: the slice runs down clockwise, like a kitchen timer, until the
## soldier deserts (ArmyRules.mutiny_time). Soldier sets `left` and hides the clock when nothing counts down.
## Drawn as square pixels on the soldier sprite's own pixel grid, so it matches the pixel art.

## World pixels per art pixel. The soldier sprite's art pixels are 4 texels at its AnimatedSprite2D scale.
@export var pixel_size: Vector2 = Vector2(1.44, 1.625):
	set(v):
		pixel_size = v
		queue_redraw()
## Width of the clock in art pixels, outline included. Odd sizes have a centre pixel.
@export_range(5, 31, 1) var diameter: int = 9:
	set(v):
		diameter = v
		queue_redraw()
## Ticks per full round: the slice jumps a tick at a time instead of sweeping. 0 sweeps pixel by pixel.
@export_range(0, 60, 1) var ticks: int = 12:
	set(v):
		ticks = v
		queue_redraw()
@export var fill_color: Color = Color("e9a93b"):
	set(v):
		fill_color = v
		queue_redraw()
@export var empty_color: Color = Color("3b4a46"):
	set(v):
		empty_color = v
		queue_redraw()
@export var outline_color: Color = Color("102a2e"):
	set(v):
		outline_color = v
		queue_redraw()
## Below this fraction of the time left the fill blinks between Warn Color and Warn Blink Color.
@export_range(0.0, 1.0, 0.05) var warn_left: float = 0.35
@export var warn_color: Color = Color("ff6a55")
@export var warn_blink_color: Color = Color("ffd9a0")
## Blinks per second while warning.
@export_range(0.5, 20.0, 0.5, "suffix:/s") var blink_rate: float = 3.0
## Fraction of the countdown left: 1 just blocked, 0 deserting. Set here to preview it in the editor.
@export_range(0.0, 1.0, 0.01) var left: float = 0.65:
	set(v):
		left = v
		queue_redraw()

var _time: float = 0.0
var _blink: bool = false


func _process(delta: float) -> void:
	_time += delta
	var blink := left < warn_left and fmod(_time * blink_rate, 1.0) < 0.5
	if blink != _blink:
		_blink = blink
		queue_redraw()
	# Undo the soldier's mirroring (scale.x = facing) so the clock always runs clockwise.
	var parent := get_parent() as Node2D
	scale.x = -1.0 if parent and parent.scale.x < 0.0 else 1.0


func _draw() -> void:
	var shown := left if ticks == 0 else ceilf(left * ticks) / ticks
	var fill := fill_color
	if left < warn_left:
		fill = warn_blink_color if _blink else warn_color
	var mid := (diameter - 1) / 2.0
	for y in diameter:
		for x in diameter:
			var c := Vector2(x - mid, y - mid)
			if not _inside(c):
				continue
			var color := empty_color
			if not (_inside(c + Vector2.LEFT) and _inside(c + Vector2.RIGHT) and _inside(c + Vector2.UP)
					and _inside(c + Vector2.DOWN)):
				color = outline_color
			elif shown > 0.0 and (c == Vector2.ZERO or _turn(c) >= 1.0 - shown):
				color = fill
			draw_rect(Rect2((c - Vector2(0.5, 0.5)) * pixel_size, pixel_size), color)


## Whether the art pixel at offset c from the centre is on the round face.
func _inside(c: Vector2) -> bool:
	return c.length() <= diameter / 2.0 - 0.3


## How far round from 12 o'clock, clockwise, the art pixel at offset c sits: 0 to 1.
func _turn(c: Vector2) -> float:
	return fposmod(atan2(c.x, -c.y), TAU) / TAU
