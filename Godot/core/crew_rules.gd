@tool
class_name CrewRules
extends Resource
## How the engineer crew builds ordered blueprints. Units: metres and seconds.

@export_range(1, 12) var crew_size: int = 3
## Walking speed on the ground. Engineers carry no armour, so they should outpace the column (ArmyRules march speed).
@export_range(0.1, 10.0, 0.05, "suffix:m/s") var walk_speed: float = 3.4
## Speed climbing along scaffolding and finished members, and up or down terrain.
@export_range(0.1, 10.0, 0.05, "suffix:m/s") var climb_speed: float = 2.4
## Ledges up to this high are stepped onto. Higher ones are climbed only when the way at the
## engineer's own level is blocked, so tunnels are walked through rather than climbed over.
@export_range(0.0, 5.0, 0.05, "suffix:m") var step_up: float = 1.05
## Highest climb and deepest drop an engineer takes on the ground. Anything more, or a hazard,
## has to be crossed over the structure.
@export_range(0.0, 20.0, 0.5, "suffix:m") var max_climb: float = 3.0
@export_range(0.0, 20.0, 0.5, "suffix:m") var max_drop: float = 3.0
## Metres of member one engineer builds per second.
@export_range(0.05, 10.0, 0.05, "suffix:m/s") var build_speed: float = 0.8
## Idle engineers trail this far behind the front soldier...
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
