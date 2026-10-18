class_name ToolController
extends Node2D
## Turns mouse and tool keys into Dig / Fill / Build actions on the world, and draws the cursor.
## Dig marks cells for the engineers (and takes back bridge members at once). Build tools place blueprints; commit
## hands them to the engineers. Works while the game is paused so the player can plan before resuming.

## The tool or its material (for a build tool with several) changed.
signal tool_changed(index: int, material: BridgeMaterial)

@export var member_pick_radius: float = 0.3
@export var ok_color: Color = Color("e9a93b")
@export var bad_color: Color = Color("ff6a55")
@export var anchor_color: Color = Color("8fd18a")
@export var joint_color: Color = Color("ece4d2")
@export var loose_color: Color = Color(0.925, 0.894, 0.824, 0.45)
@export var text_shadow: Color = Color("17202b")
## Outline and progress bar of cells marked for digging.
@export var mark_color: Color = Color("e9a93b")
## Progress bar on a tower block the column is attacking.
@export var siege_color: Color = Color("ff6a55")
@export var preview_font_size: int = 16
## Light that follows the cursor so the engineers' work can be seen at night (optional).
@export var lantern: Node2D

var tools: Array[ToolDefinition] = []
var current: int = 0
var world: World:
	set(v):
		world = v
		if world and not world.bridge.ordered.is_connected(_on_ordered):
			world.bridge.ordered.connect(_on_ordered)
## Off while an overlay (intro, lost) is up.
var enabled: bool = false

var _mouse_m: Vector2
var _hover: bool = false
var _holding: bool = false
var _hold_left: float = 0.0
## Where the cursor was (metres) when a held Dig last marked cells.
var _held_at: Vector2
var _build_from: Bridge.Snap
## Building with clicks (not a drag): the first click starts a plank, the second places its end. While chain is
## held, the next plank follows the mouse from the end just placed (see chain); letting go of it ends the chain.
## Clicking the last point again, right-click or Esc finishes.
var _build_waiting: bool = false
## Chain key (Shift, the "chain_build" action) held. Held with nothing being drawn, a new plank from the end of
## the last one placed follows the mouse, if that plan has not been ordered yet: a click places it.
var chain: bool = false
## Where the last plank placed ended (picked up again with chain), or NAN.
var _last_end: Vector2 = Vector2(NAN, NAN)
## While Dig is held: true marks cells, false clears marks (decided by the first cell clicked).
var _dig_marking: bool = true
var _material: Dictionary = {} # tool index -> index into its materials()


func tool() -> ToolDefinition:
	return tools[current] if current < tools.size() else null


## The material the current build tool builds, or null.
func build_material() -> BridgeMaterial:
	var t := tool()
	if t == null or t.kind != ToolDefinition.Kind.BUILD:
		return null
	var all := t.materials()
	return all[_material.get(current, 0) % all.size()] if not all.is_empty() else null


func select(index: int) -> void:
	if index < 0 or index >= tools.size():
		return
	current = index
	_build_from = null
	_build_waiting = false
	_holding = false
	tool_changed.emit(index, build_material())


## Makes the current build tool build mat (one of its materials, picked in the HUD's material picker).
func pick_material(mat: BridgeMaterial) -> void:
	var t := tool()
	var i := t.materials().find(mat) if t else -1
	if i < 0:
		return
	_material[current] = i
	_build_from = null
	_build_waiting = false
	tool_changed.emit(current, mat)


func cancel() -> void:
	_build_from = null
	_build_waiting = false
	_holding = false
	_last_end = Vector2(NAN, NAN)


## Where the plank following the mouse starts: the one being drawn, or (chain held) the end of the last one placed.
## null when there is none.
func preview_from() -> Bridge.Snap:
	if _build_from:
		return _build_from
	return _resume_point() if chain else null


## The end of the last plank placed as a point to build on, while its plan is still a plan nobody has ordered.
func _resume_point() -> Bridge.Snap:
	if world == null or is_nan(_last_end.x):
		return null
	var p := world.bridge.snap_point(_last_end)
	if p.node == null:
		return null
	for m in world.bridge.members:
		if (m.a == p.node or m.b == p.node) and (not m.blueprint or m.ordered):
			return null
	return p


## Hands every blueprint in the world to the crew. Returns how many.
func commit() -> int:
	if not enabled or world == null:
		return 0
	return world.bridge.order_blueprints()


## Cancel (Esc or right-click) is seen here, before the camera takes the right button for panning. It is not
## consumed, so a right-drag still pans.
## A chain whose joint is gone (its plan cancelled or dug away) ends.
func _drop_lost_chain() -> void:
	if _build_from and _build_from.node and not world.bridge.nodes.has(_build_from.node):
		cancel()


## A chain building onto plans just handed to the crew ends there.
func _on_ordered(planned: Array[Bridge.Member]) -> void:
	var at := _build_from.node if _build_from else null
	if at and planned.any(func(m: Bridge.Member) -> bool: return m.a == at or m.b == at):
		cancel()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cancel"):
		cancel()
	elif event.is_action(&"chain_build"):
		chain = event.is_pressed()


func _unhandled_input(event: InputEvent) -> void:
	for i in tools.size():
		if tools[i].action != &"" and event.is_action_pressed(tools[i].action):
			select(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"commit_build"):
		commit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_hover = true
	if not enabled or world == null or tool() == null:
		return
	if event.is_action_pressed(&"use_tool"):
		_update_mouse()
		_press()
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"use_tool"):
		_update_mouse()
		_release()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_hover = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel()
		chain = false


func _process(delta: float) -> void:
	_update_mouse()
	if lantern:
		lantern.global_position = get_global_mouse_position()
	if _holding and enabled and world:
		_hold(delta)
	queue_redraw()


## While the button is held: Dig marks every cell the cursor passed since the last frame, however fast it moves;
## other tools repeat at their repeat_interval where the cursor is.
func _hold(delta: float) -> void:
	if tool().kind == ToolDefinition.Kind.DIG:
		var from := _held_at
		var steps := ceili(from.distance_to(_mouse_m) / 0.25)
		var last := Grid.cell_of(from)
		for i in range(1, steps + 1):
			var cell := Grid.cell_of(from.lerp(_mouse_m, float(i) / steps))
			if cell != last:
				_use(cell, false)
				last = cell
		_held_at = _mouse_m
		return
	_hold_left -= delta
	if _hold_left <= 0.0:
		_use(Grid.cell_of(_mouse_m), false)
		_hold_left = tool().repeat_interval


func _update_mouse() -> void:
	_mouse_m = Grid.to_m(get_global_mouse_position())


## Build tools take a drag (press at the start, release at the end) or clicks (see _build_waiting and chain).
func _press() -> void:
	var t := tool()
	_drop_lost_chain()
	if t.kind == ToolDefinition.Kind.BUILD:
		if _build_from == null and chain:
			_build_from = _resume_point()
			_build_waiting = _build_from != null
		if _build_from and _build_waiting:
			var to := world.bridge.snap_point(_mouse_m, _build_from.node)
			if to.pos == _build_from.pos:
				cancel()
			elif _place_build():
				# Done. With chain held, the next plank follows from its end (preview_from) until Shift is let go.
				_build_from = null
				_build_waiting = false
			return
		_build_from = world.bridge.snap_point(_mouse_m)
		return
	_holding = t.repeat_interval > 0.0
	_hold_left = t.repeat_interval
	_held_at = _mouse_m
	_use(Grid.cell_of(_mouse_m), true)


func _release() -> void:
	_holding = false
	if _build_from == null or _build_waiting:
		return
	if world.bridge.snap_point(_mouse_m, _build_from.node).pos == _build_from.pos:
		# A click rather than a drag: wait for a second click to place the end.
		_build_waiting = true
		return
	_place_build()


## Places a plank from _build_from to the mouse, if it can be built and afforded. Returns whether it was placed.
## A drag ends here; a chain of clicks keeps _build_from (the caller moves it on).
func _place_build() -> bool:
	var from := _build_from
	if not _build_waiting:
		_build_from = null
	var mat := build_material()
	var ends := _plan_ends(from, world.bridge.snap_point(_mouse_m, from.node))
	from = ends[0]
	var to: Bridge.Snap = ends[1]
	var check := world.bridge.check_build(from, to, mat, GameState.supplies)
	if check.ok and GameState.spend(check.cost):
		_last_end = world.bridge.build(from, to, mat, true).b.pos
		Audio.play(tool().use_sound, Grid.to_px((from.pos + to.pos) / 2))
		return true
	if not check.msg.is_empty():
		_say(to.pos - Vector2(0, 0.6), check.msg, ok_color)
	return false


## Applies the current tool to one cell. first is true on the click, false on held repeats.
func _use(cell: Vector2i, first: bool) -> void:
	var t := tool()
	var terrain := world.terrain
	var here := terrain.type_at(cell)
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	match t.kind:
		ToolDefinition.Kind.DIG:
			var m := world.bridge.member_at(_mouse_m, member_pick_radius)
			if m:
				var mid := (m.a.pos + m.b.pos) / 2.0
				if m.blueprint:
					# A plan was never built: all of it back.
					world.gain(m.paid, mid - Vector2(0, 0.6))
					world.bridge.remove_member(m)
				elif m.material.dismantle_instantly:
					world.gain(world.bridge.take_apart(m), mid - Vector2(0, 0.6))
				elif first:
					m.dismantle = not m.dismantle
					Audio.play(t.use_sound, Grid.to_px(mid))
				return
			if first:
				_dig_marking = not terrain.is_marked(cell)
			if not _dig_marking:
				terrain.unmark(cell)
			elif not terrain.is_marked(cell):
				if terrain.mark(cell):
					Audio.play(t.use_sound, Grid.to_px(center))
				elif first and here:
					_say(center - Vector2(0, 0.5), here.too_hard_text, ok_color)
		ToolDefinition.Kind.FILL:
			if (here and not here.fill_replaces) or _falling_at(cell):
				return
			if not GameState.spend(t.cost):
				if first:
					_say(center - Vector2(0, 0.5), GameState.supplies.missing_text(t.cost, t.no_supply_text), ok_color)
				return
			if here:
				terrain.set_type(cell, null)
			var block: FallingBlock = t.spawn_scene.instantiate()
			block.position = Grid.to_px(Vector2(cell))
			world.objects.add_child(block)
			Audio.play(t.use_sound, block.position)


func _falling_at(cell: Vector2i) -> bool:
	for o in world.objects.get_children():
		if o is FallingBlock and o.cell_x() == cell.x and absf(o.position.y / Grid.PX - cell.y) < 1.0:
			return true
	return false


func _say(at_m: Vector2, text: String, color: Color) -> void:
	Effects.say(Grid.to_px(at_m), text, color)


func _draw() -> void:
	if world == null:
		return
	_drop_lost_chain()
	_draw_marks()
	if not enabled or not _hover or tool() == null:
		return
	var t := tool()
	var px := Grid.PX
	if t.kind == ToolDefinition.Kind.BUILD:
		_draw_build(build_material())
		return
	var cell := Grid.cell_of(_mouse_m)
	var r := Rect2(Vector2(cell) * px, Vector2.ONE * px)
	var here := world.terrain.type_at(cell)
	var ok := true
	if t.kind == ToolDefinition.Kind.DIG:
		var m := world.bridge.member_at(_mouse_m, member_pick_radius)
		if m:
			draw_line(m.a.pos * px, m.b.pos * px, Color(ok_color, 0.5), 0.36 * px)
			return
		ok = here != null and here.dig_action != TerrainType.DigAction.NONE
	elif t.kind == ToolDefinition.Kind.FILL:
		ok = (here == null or here.fill_replaces) and GameState.supplies.can_afford(t.cost)
		if ok:
			draw_rect(r, Color(0.627, 0.439, 0.247, 0.5))
	draw_rect(r.grow(-1), ok_color if ok else bad_color, false, 2.0)


func _draw_marks() -> void:
	var px := Grid.PX
	for cell in world.terrain.marked_cells():
		var r := Rect2(Vector2(cell) * px, Vector2.ONE * px).grow(-3)
		draw_rect(r, mark_color, false, 2.0)
		draw_line(r.position, r.end, Color(mark_color, 0.5), 1.5)
		var done := world.terrain.dig_progress(cell)
		if done > 0.0:
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x * done, 4)), mark_color)
	for m in world.bridge.members:
		if m.dismantle and not m.blueprint:
			draw_line(m.a.pos * px, m.b.pos * px, Color(mark_color, 0.35), 0.36 * px)
			draw_line(m.a.pos * px, m.a.pos.lerp(m.b.pos, 1.0 - m.progress) * px, mark_color, 3.0)
	for cell in world.terrain.besieged_cells():
		var done := world.terrain.siege_progress(cell)
		if done > 0.0:
			var r := Rect2(Vector2(cell) * px, Vector2.ONE * px).grow(-3)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), r.size * Vector2(1, 0) + Vector2(0, 4)), Color(siege_color, 0.3))
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x * done, 4)), siege_color)


func _draw_build(mat: BridgeMaterial) -> void:
	var px := Grid.PX
	var bridge := world.bridge
	var start := preview_from()
	if start == null:
		var p := bridge.snap_point(_mouse_m)
		_marker(p)
		return
	var mouse := bridge.snap_point(_mouse_m, start.node)
	var ends := _plan_ends(start, mouse)
	var from: Bridge.Snap = ends[0]
	var to: Bridge.Snap = ends[1]
	var check := bridge.check_build(from, to, mat, GameState.supplies)
	var color: Color = mat.color if check.ok else bad_color
	color.a = 0.75
	# The line follows the drag; the markers show where the ends land (out of the ground).
	var a := start.pos * px
	var b := mouse.pos * px
	if mat.draw_as_rope:
		draw_dashed_line(a, b, color, maxf(2.0, mat.thickness * px), 6.0)
	else:
		draw_line(a, b, color, mat.thickness * 1.1 * px)
	_marker(from)
	_marker(to)
	if not check.msg.is_empty():
		var font := ThemeDB.fallback_font
		var at := b - Vector2(0, 0.45 * px)
		var w := font.get_string_size(check.msg, HORIZONTAL_ALIGNMENT_LEFT, -1, preview_font_size).x
		draw_string(font, at - Vector2(w / 2 - 1, -1), check.msg, HORIZONTAL_ALIGNMENT_LEFT, -1, preview_font_size, text_shadow)
		draw_string(font, at - Vector2(w / 2, 0), check.msg, HORIZONTAL_ALIGNMENT_LEFT, -1, preview_font_size, joint_color if check.ok else bad_color)


## Both ends of the plan dragged from from to to, each moved out of the ground if buried in it.
func _plan_ends(from: Bridge.Snap, to: Bridge.Snap) -> Array[Bridge.Snap]:
	var bridge := world.bridge
	var a := bridge.fit_to_ground(from, to)
	return [a, bridge.fit_to_ground(to, a)]


func _marker(p: Bridge.Snap) -> void:
	var color := joint_color if p.node or p.on_member else (anchor_color if p.anchor else loose_color)
	draw_arc(p.pos * Grid.PX, 0.22 * Grid.PX, 0, TAU, 20, color, 2.0)
