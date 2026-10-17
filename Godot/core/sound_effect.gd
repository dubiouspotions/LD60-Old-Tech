@tool
class_name SoundEffect
extends Resource
## A sound a designer can assign anywhere. One of the streams is picked at random each time it plays.

@export var streams: Array[AudioStream] = []
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db: float = 0.0
## Random pitch spread, 0.1 = ±10 %.
@export_range(0.0, 0.5, 0.01) var pitch_variation: float = 0.08
@export var bus: StringName = &"SFX"


func pick() -> AudioStream:
	if streams.is_empty():
		return null
	return streams[randi() % streams.size()]
