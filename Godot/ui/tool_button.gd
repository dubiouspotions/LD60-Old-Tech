class_name ToolButton
extends Button
## One button in the tool rack, filled from a ToolDefinition. Shows what one use costs, and dims when the
## player can not afford it.

## Look of a button the player can not afford, and of its cost.
@export var unaffordable_modulate: Color = Color(1, 1, 1, 0.45)
@export var short_cost_color: Color = Color("ff6a55")
@export_range(4, 24) var swatch_size: int = 10

## False while the player can not afford one use.
var affordable: bool = true
## The material a build button builds now (null: its first).
var build_material: BridgeMaterial


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
	# Build tools pay per started metre of what is planned.
	var per := "/m" if def.kind == ToolDefinition.Kind.BUILD else ""
	if not price.is_empty():
		tooltip_text += "\nCosts " + price.describe_cost() + (" per started metre" if per else "")
	if not hint.is_empty():
		tooltip_text += "\n" + hint
	_fill_cost(price, colors, per)
	set_compact(false)


func set_affordable(ok: bool) -> void:
	affordable = ok
	modulate = Color.WHITE if ok else unaffordable_modulate
	%Cost.modulate = Color.WHITE if ok else short_cost_color


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


## Compact buttons hide the hint line to save width.
func set_compact(compact: bool) -> void:
	%Hint.visible = not compact and not %Hint.text.is_empty()
	custom_minimum_size.x = $Row.get_combined_minimum_size().x + 20
