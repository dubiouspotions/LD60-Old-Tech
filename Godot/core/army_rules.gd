@tool
class_name ArmyRules
extends Resource
## How the marching column moves. Units: metres (1 tile = 1 m) and seconds.

@export_range(0.1, 10.0, 0.05, "suffix:m/s") var march_speed: float = 1.7
## Each soldier gets a random speed within ± this fraction.
@export_range(0.0, 0.5, 0.01) var speed_spread: float = 0.06
@export_range(0.05, 0.5, 0.01, "suffix:m") var foot_half_width: float = 0.25
## Highest ledge a soldier steps onto.
@export_range(0.0, 3.0, 0.05, "suffix:m") var step_up: float = 1.05
## Free height a soldier needs to pass; lower gaps halt the column.
@export_range(1.0, 5.0, 1.0, "suffix:m") var headroom: float = 2.0
## Minimum gap between soldiers.
@export_range(0.1, 3.0, 0.05, "suffix:m") var spacing: float = 0.55
## Deeper step-downs are warned about (the column still walks off them).
@export_range(0.0, 20.0, 0.5, "suffix:m") var max_drop: float = 3.0
@export_range(1.0, 30.0, 0.5, "suffix:m") var fatal_fall: float = 5.5
## Arcade gravity for soldiers and falling fill.
@export_range(1.0, 100.0, 1.0, "suffix:m/s²") var gravity: float = 30.0
@export_range(1.0, 50.0, 1.0, "suffix:m/s") var max_fall_speed: float = 20.0
@export_range(1, 10) var hit_points: int = 2
## Each soldier presses on bridges with this mass.
@export_range(1.0, 300.0, 1.0, "suffix:kg") var soldier_mass: float = 80.0
## Distance between soldiers when they spawn.
@export_range(0.2, 3.0, 0.01, "suffix:m") var spawn_spacing: float = 0.62
@export_range(1, 200) var max_soldiers: int = 24
## Soldiers higher than this apart do not queue behind each other.
@export_range(0.1, 5.0, 0.1, "suffix:m") var queue_height: float = 1.5

@export_group("Camp")
## Gap between soldiers as they gather at camp, so the sleepers do not pile up.
@export_range(0.1, 5.0, 0.05, "suffix:m") var camp_spacing: float = 1.3
## Seconds a soldier stands at camp before lying down.
@export_range(0.0, 10.0, 0.1, "suffix:s") var settle_time: float = 0.6
@export var camp_text: String = "Making camp"

@export_group("Recruits")
## Price of one soldier bought at camp.
@export var recruit_cost: Supplies
@export var recruit_text: String = "+1 soldier"
@export var recruit_sound: SoundEffect

@export_group("Melee")
## A soldier fights an enemy (archer) whose feet are at most this far ahead and about level with its own.
@export_range(0.1, 3.0, 0.05, "suffix:m") var melee_reach: float = 0.9
@export_range(0.1, 5.0, 0.05, "suffix:s") var attack_interval: float = 0.6
@export_range(1, 10) var melee_damage: int = 1
@export var attack_sound: SoundEffect
## Each blow on a tower throws this many chips of its stone (its Debris Colour) and sparks off the blade.
@export_range(0, 30) var hit_chips: int = 3
@export_range(0, 30) var hit_sparks: int = 6

@export_group("Mutiny")
## Seconds a soldier stands blocked (by a wall or a low ceiling) before it deserts. Besieging a tower or
## fighting an enemy does not count. 0 turns mutiny off.
@export_range(0.0, 60.0, 0.5, "suffix:s") var mutiny_time: float = 8.0
## Deserters walk back the way they came, climbing any cliff, and vanish after this far.
@export_range(1.0, 100.0, 1.0, "suffix:m") var desert_distance: float = 20.0
@export_range(0.5, 20.0, 0.5, "suffix:m/s") var desert_climb_speed: float = 4.0
@export var desert_sound: SoundEffect

@export_group("Messages")
## Status while the front soldier is blocked (%s = why, %d = seconds before it deserts).
@export var mutiny_text: String = "%s · deserting in %d s"
@export var desert_text: String = "Deserted!"
## Status while the front soldier fights an enemy.
@export var fight_text: String = "Fighting an archer"
## Status while the front soldier attacks a tower in its way (see each terrain type's Raze Time).
@export var siege_text: String = "Besieging the tower"
## Shown while the column waits for the king's order to march.
@export var hold_text: String = "Awaiting the king's order"
## Status while the front waits at the level's exit for the rest of the column.
@export var gather_text: String = "Waiting for the column"
## How far ahead the front soldier spots deep drops and hazards. Only a warning in the status bar.
@export_range(0.5, 20.0, 0.5, "suffix:m") var warn_distance: float = 3.0
@export var wall_text: String = "%d m wall ahead"
@export var low_text: String = "Too low to pass"
@export var drop_text: String = "%d m drop ahead"
@export var chasm_text: String = "Chasm ahead"
## Drops deeper than this are reported as a chasm.
@export var chasm_depth: float = 8.0
@export var fell_text: String = "Fell"
@export var crushed_text: String = "Crushed"

@export_group("Sound")
@export var death_sound: SoundEffect
@export var hurt_sound: SoundEffect
