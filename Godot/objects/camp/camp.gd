class_name Camp
extends Node2D
## The column's night camp: tents, a fire with its light and crackle. The node origin is the camp flag's foot;
## the column sleeps behind it. The World pitches it at nightfall and calls strike() at dawn.

@export_range(0.1, 10.0, 0.1, "suffix:s") var fade_time: float = 1.5
## Tiles between the bottom of the lowest tent and the Camp Shoppe button.
@export_range(0.0, 5.0, 0.25, "suffix:tiles") var tiles_below_tents: float = 1.0

@onready var _crackle: AudioStreamPlayer2D = %Crackle
@onready var _light: PointLight2D = %FireLight


func _ready() -> void:
	_crackle.finished.connect(_crackle.play)


## Where the Camp Shoppe button hangs from, in world pixels: across from the ButtonSpot marker, tiles_below_tents
## under lowest_tent (the bottom of the lowest tent, world pixels y), or at the marker without tents.
func button_spot(lowest_tent: float = -INF) -> Vector2:
	var spot: Vector2 = %ButtonSpot.global_position
	if is_finite(lowest_tent):
		spot.y = lowest_tent + tiles_below_tents * Grid.PX
	return spot


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
