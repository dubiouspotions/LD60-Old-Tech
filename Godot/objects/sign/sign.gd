@tool
class_name Sign
extends Node2D
## A signpost with a tutorial text, placed under a level's Objects with its origin on the ground. The board is as
## big as its text plus the padding, wraps past max_width, and sits centred on the post. A lamp lights it at night,
## so it can be read in camp.

## What the board says.
@export_multiline var text: String = "":
	set(v):
		text = v
		_relayout()
@export var font: Font:
	set(v):
		font = v
		_relayout()
@export_range(6, 96) var font_size: int = 16:
	set(v):
		font_size = v
		_relayout()
@export var font_color: Color = Color(0.96, 0.9, 0.75):
	set(v):
		font_color = v
		_relayout()
## The text wraps onto more lines past this width, in pixels.
@export_range(32, 960, 8, "suffix:px") var max_width: float = 200.0:
	set(v):
		max_width = v
		_relayout()
## Space between the text and the board's edge, in pixels: left and right, top and bottom.
@export var padding: Vector2i = Vector2i(10, 6):
	set(v):
		padding = v
		_relayout()
## Height of the post: from the ground to the bottom of the board.
@export_range(0, 256, 4, "suffix:px") var post_height: float = 40.0:
	set(v):
		post_height = v
		_relayout()

@onready var _board: PanelContainer = %Board
@onready var _padding: MarginContainer = %Padding
@onready var _text: Label = %Text
@onready var _post: Control = %Post
@onready var _lamp: Node2D = %Lamp


func _ready() -> void:
	# A container grows with its contents but never shrinks back, so the board is fitted again whenever they change.
	_board.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	_layout()


func _relayout() -> void:
	if is_node_ready():
		_layout()


func _layout() -> void:
	_text.text = text
	if font:
		_text.add_theme_font_override(&"font", font)
	else:
		_text.remove_theme_font_override(&"font")
	_text.add_theme_font_size_override(&"font_size", font_size)
	_text.add_theme_color_override(&"font_color", font_color)
	for side in [&"margin_left", &"margin_right"]:
		_padding.add_theme_constant_override(side, padding.x)
	for side in [&"margin_top", &"margin_bottom"]:
		_padding.add_theme_constant_override(side, padding.y)
	var one_line := _text.get_theme_font(&"font").get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1,
			font_size).x
	var wraps := one_line > max_width
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wraps else TextServer.AUTOWRAP_OFF
	# A wrapping label needs a set width, or it measures one character per line.
	_text.custom_minimum_size.x = max_width if wraps else 0.0
	_fit()


func _fit() -> void:
	_board.reset_size()
	_post.position = Vector2(-_post.size.x / 2.0, -post_height)
	_post.size.y = post_height
	_board.position = Vector2(-_board.size.x / 2.0, -post_height - _board.size.y)
	_lamp.position = Vector2(0, _board.position.y + _board.size.y / 2.0)
