class_name ToolButton
extends Button
## One button in the tool rack, filled from a ToolDefinition.


func setup(def: ToolDefinition) -> void:
	%Key.text = def.key_label
	%Name.text = def.display_name
	%Hint.text = def.hint
	%Hint.visible = not def.hint.is_empty()
	tooltip_text = "%s (%s)" % [def.display_name, def.key_label]
	custom_minimum_size.x = $Row.get_combined_minimum_size().x + 20
