class_name Camp
extends Node2D
## The column's night camp: tents, a fire with its light and crackle. The node origin is the camp flag's foot;
## the column sleeps behind it. The World pitches it at nightfall and calls strike() at dawn.

@export_range(0.1, 10.0, 0.1, "suffix:s") var fade_time: float = 1.5

@onready var _crackle: AudioStreamPlayer2D = %Crackle
@onready var _light: PointLight2D = %FireLight


func _ready() -> void:
	_crackle.finished.connect(_crackle.play)


## Where camp buttons (Recruit) float: the ButtonSpot marker, above the tents. World pixels.
func button_spot() -> Vector2:
	return %ButtonSpot.global_position


## Fades the camp out and removes it.
func strike() -> void:
	for p in find_children("*", "CPUParticles2D"):
		(p as CPUParticles2D).emitting = false
	%Flicker.stop()
	var tw := create_tween().set_parallel()
	tw.tween_property(self, ^"modulate:a", 0.0, fade_time)
	# Back to daylight, not to dark: the fire is a Mix light (see NightLight).
	tw.tween_property(_light, ^"energy", NightLight.DAY_ENERGY, fade_time)
	tw.tween_property(_light, ^"color", NightLight.DAY_COLOR, fade_time)
	tw.tween_property(_crackle, ^"volume_db", -40.0, fade_time)
	tw.chain().tween_callback(queue_free)
