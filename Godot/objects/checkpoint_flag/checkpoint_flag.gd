@tool
class_name CheckpointFlag
extends Node2D
## Start or exit flag of a level. Place the node origin on the ground at the pole's foot.
## The column starts at the start flag and leaves the level when its front passes the exit flag.

@export var open_color: Color = Color("e9a93b")
@export var reached_color: Color = Color("4d8bf0")

@export var label: String = "L1":
	set(v):
		label = v
		if is_node_ready():
			%Label.text = v

@export var reached: bool = false:
	set(v):
		reached = v
		if is_node_ready():
			%Cloth.color = reached_color if v else open_color


func _ready() -> void:
	label = label
	reached = reached


func metres() -> Vector2:
	return Grid.to_m(position)
