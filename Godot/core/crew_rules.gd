@tool
class_name CrewRules
extends Resource
## How the engineer crew builds ordered blueprints. Units: metres and seconds.

@export_range(1, 12) var crew_size: int = 3
## Walking speed on the ground. Engineers carry no armour, so they should outpace the column (ArmyRules march speed).
@export_range(0.1, 10.0, 0.05, "suffix:m/s") var walk_speed: float = 6.8
## Speed climbing along scaffolding and finished members, and up or down terrain.
@export_range(0.1, 10.0, 0.05, "suffix:m/s") var climb_speed: float = 4.8
## Ledges up to this high are stepped onto. Higher ones are climbed only when the way at the
## engineer's own level is blocked, so tunnels are walked through rather than climbed over.
@export_range(0.0, 5.0, 0.05, "suffix:m") var step_up: float = 1.05
## Highest climb and deepest drop an engineer takes on the ground. Anything more, or a hazard,
## has to be crossed over the structure.
@export_range(0.0, 20.0, 0.5, "suffix:m") var max_climb: float = 3.0
@export_range(0.0, 20.0, 0.5, "suffix:m") var max_drop: float = 3.0
## An engineer left with nothing to stand on (its structure collapsed) falls with this gravity, up to max_fall_speed.
@export_range(1.0, 100.0, 1.0, "suffix:m/s²") var fall_gravity: float = 30.0
@export_range(1.0, 50.0, 1.0, "suffix:m/s") var max_fall_speed: float = 20.0
## An idle engineer that makes no way back to the column this long (stranded on a ledge or in a pit) climbs
## up or down any height of ground to get there (Max Climb and Max Drop no longer hold it). 0: never.
@export_range(0.0, 30.0, 0.5, "suffix:s") var stranded_time: float = 3.0
## Engineers dig a marked cell whose centre is within this distance of their chest.
## How long the digging takes is set per terrain type (Dig Time).
@export_range(0.5, 5.0, 0.1, "suffix:m") var dig_reach: float = 1.6
## An ordered plan that is not connected to ground or finished work is built from the ground by an engineer
## standing where one of its ends is within this distance of their chest.
@export_range(0.5, 5.0, 0.1, "suffix:m") var build_reach: float = 1.6
## Digging pace: multiplies each terrain type's Dig Time (2 = twice as fast). Building pace is per material
## (Build Speed on data/bridge/*.tres).
@export_range(0.05, 10.0, 0.05) var dig_speed: float = 1.0
## Idle engineers trail this far behind the last soldier (at camp: this far in front of the first)...
@export_range(0.0, 10.0, 0.1, "suffix:m") var follow_gap: float = 1.2
## ...and this far apart.
@export_range(0.1, 3.0, 0.05, "suffix:m") var spacing: float = 0.6
## Pause after the last engineer is back on the ground before the scaffolding comes down.
@export_range(0.0, 5.0, 0.1, "suffix:s") var strike_delay: float = 0.6

@export_group("Sound")
## Played while an engineer works, every work_sound_interval.
@export var work_sound: SoundEffect
@export_range(0.05, 3.0, 0.05, "suffix:s") var work_sound_interval: float = 0.45
@export var strike_sound: SoundEffect

@export_group("Cheats")
## For testing: ordered plans are finished the moment they are ordered. F2 toggles it (with a supply top-up) while playing.
@export var instant_build: bool = false
