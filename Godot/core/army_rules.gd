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
## Minimum gap between soldiers.
@export_range(0.1, 3.0, 0.05, "suffix:m") var spacing: float = 0.55
## Deepest step-down the column accepts.
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

@export_group("Messages")
@export var wall_text: String = "%d m wall ahead"
@export var drop_text: String = "%d m drop ahead"
@export var chasm_text: String = "Chasm ahead"
## Drops deeper than this are reported as a chasm.
@export var chasm_depth: float = 8.0
@export var fell_text: String = "Fell"
@export var crushed_text: String = "Crushed"

@export_group("Sound")
@export var death_sound: SoundEffect
@export var hurt_sound: SoundEffect
