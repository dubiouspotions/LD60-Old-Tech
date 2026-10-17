@tool
class_name Ridge
extends Node2D
## A distant mountain ridge drawn across the screen. Put it on a background CanvasLayer.
## It scrolls with the camera at `parallax` of the camera speed.

@export var color: Color = Color("6b6f8a"):
	set(v):
		color = v
		queue_redraw()
## 0 = fixed to the screen, 1 = moves with the world.
@export_range(0.0, 1.0, 0.01) var parallax: float = 0.12
## Baseline height as a fraction of the screen height.
@export_range(0.0, 1.0, 0.01) var base: float = 0.72:
	set(v):
		base = v
		queue_redraw()
## Peak height as a fraction of the screen height.
@export_range(0.0, 1.0, 0.01) var amplitude: float = 0.22:
	set(v):
		amplitude = v
		queue_redraw()
## Peaks per metre of camera travel.
@export_range(0.001, 1.0, 0.001) var frequency: float = 0.05:
	set(v):
		frequency = v
		queue_redraw()
@export var seed_salt: int = 101:
	set(v):
		seed_salt = v
		queue_redraw()

var _cam_m: Vector2


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d() if not Engine.is_editor_hint() else null
	var m := Grid.to_m(cam.get_screen_center_position() - get_viewport_rect().size / 2) if cam else Vector2.ZERO
	if m != _cam_m:
		_cam_m = m
		queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	var yoff := -_cam_m.y * Grid.PX * parallax * 0.4
	var pts := PackedVector2Array([Vector2(0, size.y)])
	var x := 0.0
	while x <= size.x + 8:
		var wx := (x / Grid.PX + _cam_m.x * parallax) * frequency
		var h := _noise(wx, seed_salt) * 0.7 + _noise(wx * 2.7, seed_salt + 1) * 0.3
		pts.append(Vector2(x, size.y * base + yoff - h * size.y * amplitude))
		x += 8
	pts.append(Vector2(size.x + 8, size.y))
	draw_colored_polygon(pts, color)


static func _hash(x: int, salt: int) -> float:
	var h := (x * 374761393 + salt * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(h ^ (h >> 16)) / 4294967296.0


static func _noise(t: float, salt: int) -> float:
	var i := floori(t)
	var f := t - i
	var s := f * f * (3 - 2 * f)
	return lerpf(_hash(i, salt), _hash(i + 1, salt), s)
