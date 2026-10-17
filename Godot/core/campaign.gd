@tool
class_name Campaign
extends Resource
## The ordered list of levels and what the column starts with.

## Level scenes in march order. Loaded one by one as the column nears them.
@export_file("*.tscn") var levels: Array[String] = []
@export_range(1, 200) var start_soldiers: int = 10
@export var start_supplies: Supplies
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
