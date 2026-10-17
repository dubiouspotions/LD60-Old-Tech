extends Node2D
## Text that drifts up and fades. Edit the Label child for font and outline.

@export_range(0.1, 5.0, 0.1, "suffix:s") var lifetime: float = 1.6
@export var rise_px: float = 40.0

@onready var _label: Label = $Label


func show_text(text: String, color: Color) -> void:
	_label.text = text
	_label.modulate = color
	var tw := create_tween().set_parallel()
	tw.tween_property(self, ^"position:y", position.y - rise_px, lifetime)
	tw.tween_property(self, ^"modulate:a", 0.0, lifetime).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(queue_free)
