@tool
class_name Campaign
extends Resource
## The ordered list of levels and what the column starts with.

@export var levels: Array[PackedScene] = []
@export_range(1, 200) var start_soldiers: int = 10
@export var start_supplies: Supplies
@export var army_rules: ArmyRules
## Tools in rack order.
@export var tools: Array[ToolDefinition] = []
@export var level_up_sound: SoundEffect
@export var lost_sound: SoundEffect
@export var victory_sound: SoundEffect
