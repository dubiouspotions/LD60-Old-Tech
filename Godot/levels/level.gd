@tool
class_name Level
extends Node2D
## Root of every level scene. Make a new level with Scene > New Inherited Scene > levels/level_base.tscn,
## paint the Terrain, move StartFlag and ExitFlag, and drop objects (archers, ...) under Objects. The tall Grass
## grows by itself in the editor (see regrow_grass); with no Scatter on the Grass node it is painted by hand.
## A level is a template: the World stitches it on so its StartFlag meets the previous level's ExitFlag,
## copying the ground from the StartFlag column on and moving its objects along.

@export var display_name: String = ""
@export var music: AudioStream
## Soldiers that join when the column arrives here (not on the first level). -1 uses the campaign's
## Checkpoint Reinforcements, so set it only for a level that should be different.
@export_range(-1, 50) var reinforcements: int = -1
## Supplies dropped when the column arrives here (not on the first level). Empty uses the campaign's
## Checkpoint Supplies, so set it only for a level that should drop something different.
@export var supply_drop: Supplies
## Seconds the column camps at the start before the king orders the march. 0 marches at once.
## The army sleeps through the night while the engineers keep working. The player can order the march earlier.
@export_range(0.0, 300.0, 1.0, "suffix:s") var march_delay: float = 30.0
## The Camp Shoppe (soldiers and engineers for gold) opens at this level's camp.
@export var camp_shoppe: bool = true
## Regrows the tall grass now, for example after moving a flag or an object.
@export_tool_button("Regrow Grass", "Reload") var regrow: Callable = regrow_grass

var _regrow_queued: bool = false


func _ready() -> void:
    if Engine.is_editor_hint():
        var g := grass() as TallGrass
        terrain().cell_changed.connect(_regrow_later.unbind(1))
        if g and g.scatter:
            g.scatter.changed.connect(_regrow_later)
        regrow_grass()
        return
    # Run on its own (Run Current Scene in the editor): play the game from this level.
    if get_tree().current_scene == self:
        GameState.start_level = scene_file_path
        get_tree().change_scene_to_file.call_deferred(ProjectSettings.get_setting("application/run/main_scene"))


## Supplies dropped when the column arrives here: Supply Drop, or the campaign's Checkpoint Supplies.
func drop() -> Supplies:
    var d: Supplies = supply_drop if supply_drop else GameState.campaign.checkpoint_supplies
    return d if d else Supplies.new()


## Soldiers that join when the column arrives here: Reinforcements, or the campaign's Checkpoint Reinforcements.
func joining() -> int:
    return reinforcements if reinforcements >= 0 else GameState.campaign.checkpoint_reinforcements


func terrain() -> Terrain:
    return get_node(^"Terrain")


## Tall grass for this level (see TallGrass).
func grass() -> TileMapLayer:
    return get_node(^"Grass")


## Grows the tall grass by the Grass node's Scatter, clear of the flags and objects. Does nothing without one.
func regrow_grass() -> void:
    var g := grass() as TallGrass
    if g == null or g.scatter == null:
        return
    var keep_clear: Array[int] = [floori(start_flag().metres().x), floori(exit_flag().metres().x)]
    for o in objects().get_children():
        if o is Node2D:
            keep_clear.append(floori((o as Node2D).position.x / Grid.PX))
    g.regrow(keep_clear, hash(scene_file_path.get_file()))


func _regrow_later() -> void:
    if not _regrow_queued:
        _regrow_queued = true
        (func() -> void:
            _regrow_queued = false
            regrow_grass()).call_deferred()


func objects() -> Node2D:
    return get_node(^"Objects")


func start_flag() -> CheckpointFlag:
    return get_node(^"StartFlag")


func exit_flag() -> CheckpointFlag:
    return get_node(^"ExitFlag")
