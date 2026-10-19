class_name Boot
extends Node
## The first scene: readies every sound and music file (Audio.preload_folder) behind a loading bar, then opens
## next_scene. On the web each music file is decoded into a sample, about a second each, which would otherwise
## freeze the menu or the game the first time it plays. Where nothing needs readying it moves straight on.

## Emitted once everything is readied, as next_scene opens.
signal finished

## Every sound and music file under this folder is loaded and readied here.
@export_dir var audio_folder: String = "res://audio"
## Opened once everything is readied. Empty stays here (for tests).
@export_file("*.tscn") var next_scene: String = "res://menu/main_menu.tscn"

## Streams waiting to be readied when the boot began.
var _total: int = 0
var _done: bool = false


func _ready() -> void:
	Audio.preload_folder(audio_folder)
	_total = Audio.to_ready()


func _process(_delta: float) -> void:
	if _done:
		return
	%Bar.value = progress()
	if Audio.to_ready() > 0:
		return
	_done = true
	finished.emit()
	if next_scene:
		get_tree().change_scene_to_file.call_deferred(next_scene)


## How far the readying has come, 0 to 1.
func progress() -> float:
	if _total == 0:
		return 1.0
	return 1.0 - float(Audio.to_ready()) / _total
