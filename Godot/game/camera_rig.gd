class_name CameraRig
extends Camera2D
## Starts each level on the front of the column without following it; the Follow action (button or C) follows it.
## Pans with keys, right/middle drag or the wheel. Panning by hand turns follow off.

signal follow_changed(on: bool)

## Where the front soldier sits on screen while following (fraction of the view).
@export var follow_anchor: Vector2 = Vector2(0.35, 0.58)
@export_range(0.1, 20.0, 0.1) var follow_rate: float = 3.0
@export var key_pan_speed: Vector2 = Vector2(28, 20)
## Metres per wheel notch.
@export var wheel_step: float = 1.5
## How far ahead of the column the view may wander, metres.
@export var max_lead_ahead: float = 80.0
## Fraction of the view the rear soldier must stay inside.
@export_range(0.1, 1.0) var keep_rear_in_view: float = 0.8
## Pixels of shake per unit of shake amount.
@export var shake_px: float = 16.0

var world: World
var follow: bool = false:
	set(v):
		if v != follow:
			follow = v
			follow_changed.emit(v)

var _drag_from: Vector2
var _drag_cam: Vector2
var _dragging: bool = false
var _shake: float = 0.0


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	Effects.shake_requested.connect(func(a: float) -> void: _shake = maxf(_shake, a))


## Top-left of the view in metres.
func view_m() -> Vector2:
	return Grid.to_m(position)


func view_size_m() -> Vector2:
	return Grid.to_m(get_viewport_rect().size / zoom)


## Follows the column, starting with the view on it.
func snap_to_lead() -> void:
	follow = true
	center_on_lead()


## Puts the view on the column (where following would hold it) without following it.
func center_on_lead() -> void:
	var lead := world.army.lead() if world else null
	if lead:
		position = Grid.to_px(lead.pos - view_size_m() * follow_anchor)
	_clamp()


## While a drag pans the view, its motion and release are taken here, before the HUD sees them, and kept from it:
## no button hovers or swallows the drag until the pan button is let go.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event.is_action_released(&"drag_view") or event.is_action_released(&"use_tool"):
		_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		position = _drag_cam - (event.position - _drag_from) / zoom
		# Kept within its limit at once, so what is pinned to the world does not jump about until the next frame.
		_clamp()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"follow"):
		follow = true
	var drag_start := event.is_action_pressed(&"drag_view")
	if drag_start and event is InputEventMouseButton:
		_dragging = true
		_drag_from = event.position
		_drag_cam = position
		follow = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		var dir := -1.0 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
		position.x += dir * wheel_step * Grid.PX
		_clamp()
		follow = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false


func _process(delta: float) -> void:
	# real time, so panning feels the same at 2x speed
	var dt := delta / maxf(Engine.time_scale, 0.001)
	var pan := Input.get_vector(&"pan_left", &"pan_right", &"pan_up", &"pan_down")
	if pan != Vector2.ZERO:
		position += pan * key_pan_speed * Grid.PX * dt
		follow = false
	var lead := world.army.lead() if world else null
	if follow and lead:
		var target := Grid.to_px(lead.pos - view_size_m() * follow_anchor)
		position += (target - position) * minf(1.0, dt * follow_rate)
	_clamp()
	_shake = maxf(0.0, _shake - dt)
	offset = Vector2(randf() - 0.5, randf() - 0.5) * _shake * shake_px if _shake > 0.0 else Vector2.ZERO


func _clamp() -> void:
	if world == null:
		return
	var view := view_size_m()
	var m := view_m()
	var lim := _left_edge_limits(view)
	m.x = clampf(m.x, lim.x, lim.y)
	m.y = clampf(m.y, 0.0, maxf(0.0, world.terrain.size.y - view.y))
	position = Grid.to_px(m)


## Leftmost and rightmost x, in metres, the view can be panned to show.
func reach_m() -> Vector2:
	var view := view_size_m()
	var lim := _left_edge_limits(view)
	return Vector2(lim.x, lim.y + view.x)


## Lowest and highest x the view's left edge may take: near the column and inside the terrain.
func _left_edge_limits(view: Vector2) -> Vector2:
	var lo := -INF
	var hi := INF
	var lead := world.army.lead()
	if lead:
		lo = world.army.rear().pos.x - view.x * keep_rear_in_view
		hi = lead.pos.x + max_lead_ahead
	var left := float(world.terrain.min_x)
	var right := maxf(left, world.terrain.size.x - view.x)
	return Vector2(clampf(lo, left, right), clampf(hi, left, right))
