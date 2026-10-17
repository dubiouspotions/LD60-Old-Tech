@tool
class_name TerrainType
extends Resource
## What one kind of tile does. Assign it to tiles in the TileSet through the "terrain" custom data layer.
## Empty cells are air.

enum Hazard { NONE, WATER, SPIKES }
enum DigAction { NONE, REMOVE, FELL }

@export var display_name: String = ""

@export_group("Physical")
## Blocks soldiers, supports fill, and stops logs passing through.
@export var solid: bool = true
## Natural ground: holds structures up and bolts bridge joints that touch it.
@export var anchor: bool = true
## Collapses when no chain of structure tiles connects it to anchor ground (bricks, towers).
@export var structure: bool = false
## Falls when the tile below is not solid (dumped fill).
@export var falls: bool = false
## Fill can be dropped into this tile, replacing it.
@export var fill_replaces: bool = false
## Wood floats in it.
@export var buoyant: bool = false
## Charges can not be placed on it and blasts leave it alone.
@export var blast_proof: bool = false

@export_group("Hazard")
@export var hazard: Hazard = Hazard.NONE
## Shown when a soldier dies inside this tile.
@export var death_text: String = ""
## Shown in the status bar when the column halts in front of it.
@export var ahead_text: String = ""

@export_group("Dig")
@export var dig_action: DigAction = DigAction.NONE
## Seconds one engineer works to dig this tile (or fell the whole tree).
@export_range(0.1, 30.0, 0.1, "suffix:s") var dig_time: float = 1.0
## Given for each tile removed with the Dig tool.
@export var dig_yield: Supplies
## Floating text after digging one tile. Empty shows nothing.
@export var dig_text: String = ""
## Shown when Dig is used on a tile that can not be dug.
@export var too_hard_text: String = ""
@export var dig_sound: SoundEffect

@export_group("Bulk yield")
## Given by blasts, collapses and felled trees: bulk_yield for every bulk_tiles_per_yield tiles.
@export var bulk_yield: Supplies
@export_range(1, 20) var bulk_tiles_per_yield: int = 1
## Given once per blast/fell when at least one tile of this type was taken.
@export var bulk_bonus: Supplies

@export_group("Look")
@export var debris_color: Color = Color("7b5131")


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
