@tool
class_name Readout
extends HBoxContainer
## A small caption + value pair for the top bar ("ARMY 10"). An optional colour swatch shows a supply.

@export var caption: String = "Caption":
	set(v):
		caption = v
		if is_node_ready():
			%Caption.text = v.to_upper()
## Transparent hides the swatch.
@export var swatch: Color = Color(0, 0, 0, 0):
	set(v):
		swatch = v
		if is_node_ready():
			%Swatch.color = v
			%Swatch.visible = v.a > 0.0
@export var bump_color: Color = Color("e9a93b")

var _last: String = ""


func _ready() -> void:
	caption = caption
	swatch = swatch


## Sets the value. A raised number flashes briefly.
func set_value(text: String, flash_if_up: bool = false) -> void:
	var value: Label = %Value
	if flash_if_up and _last.is_valid_int() and text.is_valid_int() and int(text) > int(_last):
		value.modulate = bump_color
		create_tween().tween_property(value, ^"modulate", Color.WHITE, 0.5)
	_last = text
	value.text = text
