class_name ToolButton
extends Button
## One button in the tool rack, filled from a ToolDefinition. Shows what one use costs, and dims when the
## player can not afford it. A tool that builds several materials shows an icon per material to pick it.

## One of the material icons was clicked.
signal material_pressed(material: BridgeMaterial)

## Look of a button the player can not afford, and of its cost.
@export var unaffordable_modulate: Color = Color(1, 1, 1, 0.45)
@export var short_cost_color: Color = Color("ff6a55")
@export_range(4, 24) var swatch_size: int = 10
## Size of the material icons on a button whose tool builds several materials.
@export_range(12, 64) var material_icon_size: int = 36

## False while the player can not afford one use.
var affordable: bool = true
## The material a build button builds now (null: its first).
var build_material: BridgeMaterial
## The tool the material icons were made for.
var _icons_for: ToolDefinition
## Folded by set_compact: the hint line is hidden.
var _compact: bool = false


## colors: supply key (&"earth", &"logs", ...) -> swatch colour, the same as the supply readouts. mat: the
## material a build tool builds now (null: its first).
func setup(def: ToolDefinition, colors: Dictionary = {}, mat: BridgeMaterial = null) -> void:
    build_material = mat
    var hint := def.hint_for(mat)
    %Key.text = def.key_label
    %Name.text = def.display_name
    %Hint.text = hint
    tooltip_text = "%s (%s)" % [def.display_name, def.key_label]
    var price := def.price(mat)
    # Build tools pay per started metre (or metres_per_cost) of what is planned.
    var built: BridgeMaterial = (mat if mat else def.bridge_material) if def.kind == ToolDefinition.Kind.BUILD else null
    var per := "/" + built.cost_unit() if built else ""
    if not price.is_empty() and built:
        tooltip_text += "\nCosts " + price.describe_cost() + " per started " + built.cost_stretch()
    elif not price.is_empty():
        tooltip_text += "\nCosts " + price.describe_cost()
    if not hint.is_empty():
        tooltip_text += "\n" + hint
    _fill_cost(price, colors, per)
    _fill_materials(def, mat)
    set_compact(_compact)


func set_affordable(ok: bool) -> void:
    affordable = ok
    modulate = Color.WHITE if ok else unaffordable_modulate
    # Only the counts turn red: the swatches keep their colour, which says which supply it is.
    for c in %Cost.get_children():
        if c is Label:
            (c as Label).modulate = Color.WHITE if ok else short_cost_color


## One swatch and count per supply the price asks for.
func _fill_cost(price: Supplies, colors: Dictionary, per: String = "") -> void:
    var row: HBoxContainer = %Cost
    for c in row.get_children():
        c.free()
    for k in Supplies.KEYS:
        var v: int = price.get(k)
        if v <= 0:
            continue
        var swatch := ColorRect.new()
        swatch.color = colors.get(k, Color.WHITE)
        swatch.custom_minimum_size = Vector2.ONE * swatch_size
        swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(swatch)
        var count := Label.new()
        count.text = str(v) + per
        count.theme_type_variation = &"Caption"
        count.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(count)
    row.visible = row.get_child_count() > 0
    set_affordable(affordable)


## An icon per material when the tool builds several, the one it builds now (mat, or the first) pressed. The icons
## are made once per tool and only re-pressed after, as one of them may be emitting the very pick that got here.
func _fill_materials(def: ToolDefinition, mat: BridgeMaterial) -> void:
    var row: HBoxContainer = %Materials
    var all := def.materials()
    row.visible = all.size() > 1
    if _icons_for != def:
        _icons_for = def
        for c in row.get_children():
            c.queue_free()
            row.remove_child(c)
        if row.visible:
            var group := ButtonGroup.new()
            for m in all:
                var b := Button.new()
                b.toggle_mode = true
                b.button_group = group
                b.focus_mode = Control.FOCUS_NONE
                b.icon = m.icon
                b.expand_icon = true
                b.custom_minimum_size = Vector2.ONE * material_icon_size
                b.tooltip_text = "%s · %s/%s" % [m.display_name, m.cost.describe_cost() if m.cost else "", m.cost_unit()]
                b.pressed.connect(func() -> void: material_pressed.emit(m))
                row.add_child(b)
    var chosen := mat if mat else (all[0] if not all.is_empty() else null)
    for i in row.get_child_count():
        (row.get_child(i) as Button).set_pressed_no_signal(all[i] == chosen)


## Compact buttons hide the hint line to save width.
func set_compact(compact: bool) -> void:
    _compact = compact
    %Hint.visible = not compact and not %Hint.text.is_empty()
    custom_minimum_size.x = $Row.get_combined_minimum_size().x + 20
