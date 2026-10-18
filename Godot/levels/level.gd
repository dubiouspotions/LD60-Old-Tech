class_name Level
extends Node2D
## Root of every level scene. Make a new level with Scene > New Inherited Scene > levels/level_base.tscn,
## paint the Terrain and the tall Grass, move StartFlag and ExitFlag, and drop objects (archers, ...) under Objects.
## A level is a template: the World stitches it on so its StartFlag meets the previous level's ExitFlag,
## copying the ground from the StartFlag column on and moving its objects along.

@export var display_name: String = ""
@export var music: AudioStream
## Soldiers that join when the column arrives here (not on the first level).
@export_range(0, 50) var reinforcements: int = 3
## Supplies dropped when the column arrives here (not on the first level). Empty uses the campaign's
## Checkpoint Supplies, so set it only for a level that should drop something different.
@export var supply_drop: Supplies
## Seconds the column camps at the start before the king orders the march. 0 marches at once.
## The army sleeps through the night while the engineers keep working. The player can order the march earlier.
@export_range(0.0, 300.0, 1.0, "suffix:s") var march_delay: float = 30.0


func _ready() -> void:
	# Run on its own (Run Current Scene in the editor): play the game from this level.
	if get_tree().current_scene == self:
		GameState.start_level = scene_file_path
		get_tree().change_scene_to_file.call_deferred(ProjectSettings.get_setting("application/run/main_scene"))


func terrain() -> Terrain:
	return get_node(^"Terrain")


## Tall grass painted for this level (see TallGrass).
func grass() -> TileMapLayer:
	return get_node(^"Grass")


func objects() -> Node2D:
	return get_node(^"Objects")


func start_flag() -> CheckpointFlag:
	return get_node(^"StartFlag")


func exit_flag() -> CheckpointFlag:
	return get_node(^"ExitFlag")
