class_name ToolController
extends Node2D
## Turns mouse and tool keys into Dig / Fill / Build / Charge actions on the current level, and draws the cursor.
## Build tools place blueprints; commit builds them. Works while the game is paused so the player can plan before resuming.

signal tool_changed(index: int)

@export var member_pick_radius: float = 0.3
@export var ok_color: Color = Color("e9a93b")
@export var bad_color: Color = Color("ff6a55")
@export var anchor_color: Color = Color("8fd18a")
@export var joint_color: Color = Color("ece4d2")
@export var loose_color: Color = Color(0.925, 0.894, 0.824, 0.45)
@export var text_shadow: Color = Color("17202b")
@export var preview_font_size: int = 16

var tools: Array[ToolDefinition] = []
var current: int = 0
var level: Level
## Off while an overlay (intro, lost) is up.
var enabled: bool = false

var _mouse_m: Vector2
var _hover: bool = false
var _holding: bool = false
var _hold_left: float = 0.0
var _build_from: Bridge.Snap
var _radius_cache: Dictionary = {}


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


## Hands every blueprint on the level to the crew. Returns how many.
func commit() -> int:
    if not enabled or level == null:
        return 0
    return level.bridge.order_blueprints()


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
    if not enabled or level == null or tool() == null or tool().kind == ToolDefinition.Kind.PAN:
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
    if _holding and enabled and level:
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
        _build_from = level.bridge.snap_point(_mouse_m)
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
    var to := level.bridge.snap_point(_mouse_m, from.node)
    var check := level.bridge.check_build(from, to, mat, GameState.supplies)
    if check.ok and GameState.spend(mat.cost):
        level.bridge.build(from, to, mat, true)
        Audio.play(tool().use_sound, Grid.to_px((from.pos + to.pos) / 2))
    elif not check.msg.is_empty():
        _say(to.pos - Vector2(0, 0.6), check.msg, ok_color)


## Applies the current tool to one cell. first is true on the click, false on held repeats.
func _use(cell: Vector2i, first: bool) -> void:
    var t := tool()
    var terrain := level.terrain
    var here := terrain.type_at(cell)
    var center := Vector2(cell) + Vector2(0.5, 0.5)
    match t.kind:
        ToolDefinition.Kind.DIG:
            var m := level.bridge.member_at(_mouse_m, member_pick_radius)
            if m:
                GameState.gain(m.material.cost)
                if m.blueprint:
                    level.bridge.remove_member(m)
                else:
                    level.bridge.break_member(m, true)
                return
            var got := terrain.dig(cell)
            if got == null:
                if first and here:
                    _say(center - Vector2(0, 0.5), here.too_hard_text, ok_color)
                return
            GameState.gain(got)
            if here.dig_action == TerrainType.DigAction.FELL:
                _say(center - Vector2(0, 0.5), got.describe(), joint_color)
            else:
                _say(center - Vector2(0, 0.5), here.dig_text, here.debris_color)
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
            level.objects.add_child(block)
            Audio.play(t.use_sound, block.position)
        ToolDefinition.Kind.CHARGE:
            if (here and here.blast_proof) or _charge_at(cell):
                return
            if not GameState.spend(t.cost):
                _say(center - Vector2(0, 0.5), t.no_supply_text, ok_color)
                return
            var charge: Charge = t.spawn_scene.instantiate()
            charge.position = Grid.to_px(Vector2(cell))
            level.objects.add_child(charge)


func _falling_at(cell: Vector2i) -> bool:
    for o in level.objects.get_children():
        if o is FallingBlock and o.cell_x() == cell.x and absf(o.position.y / Grid.PX - cell.y) < 1.0:
            return true
    return false


func _charge_at(cell: Vector2i) -> bool:
    for o in level.objects.get_children():
        if o is Charge and o.cell() == cell:
            return true
    return false


func _say(at_m: Vector2, text: String, color: Color) -> void:
    Effects.say(Grid.to_px(at_m), text, color)


func _draw() -> void:
    if not enabled or not _hover or level == null or tool() == null:
        return
    var t := tool()
    var px := Grid.PX
    match t.kind:
        ToolDefinition.Kind.PAN:
            return
        ToolDefinition.Kind.BUILD:
            _draw_build(t.bridge_material)
            return
    var cell := Grid.cell_of(_mouse_m)
    var r := Rect2(Vector2(cell) * px, Vector2.ONE * px)
    var here := level.terrain.type_at(cell)
    var ok := true
    if t.kind == ToolDefinition.Kind.DIG:
        var m := level.bridge.member_at(_mouse_m, member_pick_radius)
        if m:
            draw_line(m.a.pos * px, m.b.pos * px, Color(ok_color, 0.5), 0.36 * px)
            return
        ok = here != null and here.dig_action != TerrainType.DigAction.NONE
    elif t.kind == ToolDefinition.Kind.FILL:
        ok = (here == null or here.fill_replaces) and GameState.supplies.can_afford(t.cost)
        if ok:
            draw_rect(r, Color(0.627, 0.439, 0.247, 0.5))
    elif t.kind == ToolDefinition.Kind.CHARGE:
        ok = (here == null or not here.blast_proof) and GameState.supplies.can_afford(t.cost)
        var radius := _blast_radius(t.spawn_scene)
        var n := 64
        for i in range(0, n, 2):
            draw_arc(r.get_center(), radius * px, TAU * i / n, TAU * (i + 1) / n, 3, Color(ok_color if ok else bad_color, 0.7), 1.5)
    draw_rect(r.grow(-1), ok_color if ok else bad_color, false, 2.0)


func _draw_build(mat: BridgeMaterial) -> void:
    var px := Grid.PX
    var bridge := level.bridge
    if _build_from == null:
        var p := bridge.snap_point(_mouse_m)
        _marker(p)
        return
    var to := bridge.snap_point(_mouse_m, _build_from.node)
    var check := bridge.check_build(_build_from, to, mat, GameState.supplies)
    var color: Color = mat.color if check.ok else bad_color
    color.a = 0.75
    var a := _build_from.pos * px
    var b := to.pos * px
    if mat.draw_as_rope:
        draw_dashed_line(a, b, color, maxf(2.0, mat.thickness * px), 6.0)
    else:
        draw_line(a, b, color, mat.thickness * 1.1 * px)
    _marker(_build_from)
    _marker(to)
    if not check.msg.is_empty():
        var font := ThemeDB.fallback_font
        var at := b - Vector2(0, 0.45 * px)
        var w := font.get_string_size(check.msg, HORIZONTAL_ALIGNMENT_LEFT, -1, preview_font_size).x
        draw_string(font, at - Vector2(w / 2 - 1, -1), check.msg, HORIZONTAL_ALIGNMENT_LEFT, -1, preview_font_size, text_shadow)
        draw_string(font, at - Vector2(w / 2, 0), check.msg, HORIZONTAL_ALIGNMENT_LEFT, -1, preview_font_size, joint_color if check.ok else bad_color)


func _marker(p: Bridge.Snap) -> void:
    var color := joint_color if p.node else (anchor_color if p.anchor else loose_color)
    draw_arc(p.pos * Grid.PX, 0.22 * Grid.PX, 0, TAU, 20, color, 2.0)


## Blast radius of a charge scene, read once from an instance so the preview matches the scene.
func _blast_radius(scene: PackedScene) -> float:
    if not _radius_cache.has(scene):
        var probe: Node = scene.instantiate()
        _radius_cache[scene] = probe.get(&"blast_radius") if &"blast_radius" in probe else 0.0
        probe.free()
    return _radius_cache[scene]
