@tool
class_name TerrainType
extends Resource
## What one kind of tile does. Assign it to tiles in the TileSet through the "terrain" custom data layer.
## Empty cells are air.

enum Hazard { NONE, WATER, SPIKES }
enum DigAction { NONE, REMOVE, FELL }

@export var display_name: String = ""

@export_group("Physical")
## Blocks soldiers, holds up boxes, and stops logs passing through.
@export var solid: bool = true
## Natural ground: holds up structures (bricks, towers) standing on it. Bridge joints bolt to any solid tile, this or not.
@export var anchor: bool = true
## Falls when no chain of structure tiles connects it to anchor ground under one of them (bricks, towers): ground
## only beside it does not hold it.
@export var structure: bool = false
## A tower or tree whose ground is taken away falls as one piece, carrying what stands on it, and stands where it
## lands. Falling further than this breaks it up (a tower collapses, a tree is felled). The lowest in a piece counts.
@export_range(0.0, 50.0, 0.5, "suffix:m") var survives_fall: float = 3.0
## A falling piece with a tile of this kills the soldiers, engineers and archers it comes down on (a tower). Off, it
## leaves them alive (a tree).
@export var crushes: bool = true
## Falls when the tile below is not solid (a dropped box).
@export var falls: bool = false
## A tile dropped by a Fill tool (a box) can land in this tile, replacing it.
@export var fill_replaces: bool = false
## Comes back when what took its place is gone (water: a sandbag dug out of it, or falling out of it).
@export var refills: bool = false
## Wood floats in it.
@export var buoyant: bool = false

@export_group("Hazard")
@export var hazard: Hazard = Hazard.NONE
## Breaks what falls onto it (spikes): boxes, and bridge pieces whose loose part reaches it. Pieces bolted down
## there on purpose stay.
@export var breaks_falling: bool = false
## Shown when a soldier dies inside this tile.
@export var death_text: String = ""
## Shown in the status bar when the column halts in front of it.
@export var ahead_text: String = ""

@export_group("Dig")
@export var dig_action: DigAction = DigAction.NONE
## Seconds one engineer works to dig this tile (or fell the whole tree). Engineers digging together add up.
@export_range(0.1, 30.0, 0.1, "suffix:s") var dig_time: float = 1.0
## Given for each tile removed with the Dig tool.
@export var dig_yield: Supplies
## Shown when Dig is used on a tile that can not be dug.
@export var too_hard_text: String = ""
@export var dig_sound: SoundEffect

@export_group("Siege")
## Seconds one soldier must attack this tile to raze the structure it belongs to (a tower). 0: can not be attacked.
@export_range(0.0, 300.0, 0.5, "suffix:s") var raze_time: float = 0.0

@export_group("Impact")
## Energy (J, after the piece's Ram) one fast bridge piece hitting this tile needs to break it. 0: hits never
## break it (towers take siege from hits instead). A tile that holds may break the piece instead.
@export_range(0.0, 100000.0, 10.0, "suffix:J") var impact_strength: float = 0.0

@export_group("Bulk yield")
## Given by collapses and felled trees: bulk_yield for every bulk_tiles_per_yield tiles.
@export var bulk_yield: Supplies
@export_range(1, 20) var bulk_tiles_per_yield: int = 1
## Given once per collapse/fell when at least one tile of this type was taken.
@export var bulk_bonus: Supplies

@export_group("Look")
@export var debris_color: Color = Color("7b5131")
## A liquid (water): drops of debris_color thrown up where something falls into it at Splash Speed or faster
## (0: no splash), with splash_sound.
@export_range(0, 40) var splash_amount: int = 0
@export_range(0.0, 20.0, 0.5, "suffix:m/s") var splash_speed: float = 2.0
@export var splash_sound: SoundEffect


## Short label, shown on the tiles in the TileSet editor's paint view.
func _to_string() -> String:
	return display_name if not display_name.is_empty() else resource_path.get_file().get_basename()


## Is a tile of this type broken by one hit doing damage (J, after Ram)?
func breaks_under(damage: float) -> bool:
	return raze_time <= 0.0 and impact_strength > 0.0 and damage >= impact_strength


func is_hazard() -> bool:
	return hazard != Hazard.NONE


## Sum of bulk yields for a tally {TerrainType: count}.
static func bulk_total(counts: Dictionary) -> Supplies:
	var total := Supplies.new()
	for t: TerrainType in counts:
		var n: int = counts[t]
		if n <= 0:
			continue
		total.add(t.bulk_yield, n / t.bulk_tiles_per_yield)
		total.add(t.bulk_bonus)
	return total
