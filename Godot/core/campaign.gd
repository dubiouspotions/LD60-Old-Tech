@tool
class_name Campaign
extends Resource
## The ordered list of levels and what the column starts with.

## Level scenes in march order. Loaded one by one as the column nears them.
@export_file("*.tscn") var levels: Array[String] = []
@export_range(1, 200) var start_soldiers: int = 10
@export var start_supplies: Supplies
## Supplies dropped at each checkpoint (level start, from the second level on). A level's own Supply Drop wins.
@export var checkpoint_supplies: Supplies
## Soldiers who join at each checkpoint (from the second level on). A level's own Reinforcements wins.
@export_range(0, 50) var checkpoint_reinforcements: int = 0
@export var army_rules: ArmyRules
## Tools in rack order.
@export var tools: Array[ToolDefinition] = []
@export var level_up_sound: SoundEffect
@export var lost_sound: SoundEffect
@export var victory_sound: SoundEffect
@export_group("Camp")
## Plays while the column camps for the night. Each level's own music returns at dawn.
@export var camp_music: AudioStream
## Plays when the column breaks camp.
@export var dawn_sound: SoundEffect

var _placed_by: Dictionary = {} # TerrainType -> the Fill tool that drops it


## What digging up a tile of type gives back when a tool places that type (the Box tool's boxes): the tool's cost
## less one of each supply (Supplies.reclaimed), like any built thing taken back. null for other types.
func reclaim_for(type: TerrainType) -> Supplies:
	if _placed_by.is_empty():
		for t in tools:
			if t.kind == ToolDefinition.Kind.FILL and t.spawn_scene:
				var block := t.spawn_scene.instantiate()
				_placed_by[block.get(&"type")] = t
				block.free()
	var placer: ToolDefinition = _placed_by.get(type)
	return placer.price().reclaimed() if placer else null
