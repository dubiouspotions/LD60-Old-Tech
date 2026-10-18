class_name ToolController
extends Node2D
## Turns mouse and tool keys into Dig / Fill / Build actions on the world, and draws the cursor.
## Dig marks cells for the engineers (and takes back bridge members at once). Build tools place blueprints; commit
## hands them to the engineers. Works while the game is paused so the player can plan before resuming.

signal tool_changed(index: int)

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
var world: World
## Off while an overlay (intro, lost) is up.
var enabled: bool = false

var _mouse_m: Vector2
var _hover: bool = false
var _holding: bool = false
var _hold_left: float = 0.0
var _build_from: Bridge.Snap
## While Dig is held: true marks cells, false clears marks (decided by the first cell clicked).
var _dig_marking: bool = true


func tool() -> ToolDefinition:
    return tools[current] if current < tools.size() else null


func select(index: int) -> void:
    if index < 0 or index >= tools.size():
        return
    current = index
    _build_from = null
    _holding = false
    tool_changed.emit(index)


func cancel() -> void:
    _build_from = null
    _holding = false


## Hands every blueprint in the world to the crew. Returns how many.
func commit() -> int:
    if not enabled or world == null:
        return 0
    return world.bridge.order_blueprints()


func _unhandled_input(event: InputEvent) -> void:
    for i in tools.size():
        if tools[i].action != &"" and event.is_action_pressed(tools[i].action):
            select(i)
            get_viewport().set_input_as_handled()
            return
    if event.is_action_pressed(&"cancel"):
        cancel()
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


func _process(delta: float) -> void:
    _update_mouse()
    if lantern:
        lantern.global_position = get_global_mouse_position()
    if _holding and enabled and world:
        _hold_left -= delta
        if _hold_left <= 0.0:
            _use(Grid.cell_of(_mouse_m), false)
            _hold_left = tool().repeat_interval
    queue_redraw()


func _update_mouse() -> void:
    _mouse_m = Grid.to_m(get_global_mouse_position())


func _press() -> void:
    var t := tool()
    if t.kind == ToolDefinition.Kind.BUILD:
        _build_from = world.bridge.snap_point(_mouse_m)
        return
    _holding = t.repeat_interval > 0.0
    _hold_left = t.repeat_interval
    _use(Grid.cell_of(_mouse_m), true)


func _release() -> void:
    _holding = false
    if _build_from == null:
        return
    var from := _build_from
    _build_from = null
    var mat := tool().bridge_material
    var ends := _plan_ends(from, world.bridge.snap_point(_mouse_m, from.node))
    from = ends[0]
    var to: Bridge.Snap = ends[1]
    var check := world.bridge.check_build(from, to, mat, GameState.supplies)
    if check.ok and GameState.spend(mat.cost):
        world.bridge.build(from, to, mat, true)
        Audio.play(tool().use_sound, Grid.to_px((from.pos + to.pos) / 2))
    elif not check.msg.is_empty():
        _say(to.pos - Vector2(0, 0.6), check.msg, ok_color)


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
                GameState.gain(m.material.cost)
                if m.blueprint:
                    world.bridge.remove_member(m)
                else:
                    world.bridge.break_member(m, true)
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
                    _say(center - Vector2(0, 0.5), t.no_supply_text, ok_color)
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
    _draw_marks()
    if not enabled or not _hover or tool() == null:
        return
    var t := tool()
    var px := Grid.PX
    if t.kind == ToolDefinition.Kind.BUILD:
        _draw_build(t.bridge_material)
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
    for cell in world.terrain.besieged_cells():
        var done := world.terrain.siege_progress(cell)
        if done > 0.0:
            var r := Rect2(Vector2(cell) * px, Vector2.ONE * px).grow(-3)
            draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), r.size * Vector2(1, 0) + Vector2(0, 4)), Color(siege_color, 0.3))
            draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x * done, 4)), siege_color)


func _draw_build(mat: BridgeMaterial) -> void:
    var px := Grid.PX
    var bridge := world.bridge
    if _build_from == null:
        var p := bridge.snap_point(_mouse_m)
        _marker(p)
        return
    var mouse := bridge.snap_point(_mouse_m, _build_from.node)
    var ends := _plan_ends(_build_from, mouse)
    var from: Bridge.Snap = ends[0]
    var to: Bridge.Snap = ends[1]
    var check := bridge.check_build(from, to, mat, GameState.supplies)
    var color: Color = mat.color if check.ok else bad_color
    color.a = 0.75
    # The line follows the drag; the markers show where the ends land (out of the ground).
    var a := _build_from.pos * px
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

