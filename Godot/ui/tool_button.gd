class_name ToolButton
extends Button
## One button in the tool rack, filled from a ToolDefinition.


func setup(def: ToolDefinition) -> void:
	%Key.text = def.key_label
	%Name.text = def.display_name
	%Hint.text = def.hint
	tooltip_text = "%s (%s)" % [def.display_name, def.key_label]
	if not def.hint.is_empty():
		tooltip_text += "
" + def.hint
	set_compact(false)


## Compact buttons hide the hint line to save width.
func set_compact(compact: bool) -> void:
	%Hint.visible = not compact and not %Hint.text.is_empty()
	custom_minimum_size.x = $Row.get_combined_minimum_size().x + 20
