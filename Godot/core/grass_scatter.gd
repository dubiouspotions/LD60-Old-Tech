@tool
class_name GrassScatter
extends Resource
## How a level's tall grass is spread over its ground. In the editor the Level regrows its grass by these settings
## whenever the ground is painted or a setting changes (see Level.regrow_grass). A patch is a run of cells in the
## air on top of open ground that grass grows on. Where patches go is set by the seed alone, so painting one spot
## never moves the grass elsewhere: the ground only decides which cells of each patch grow.

## Ground the grass grows on.
@export var grows_on: Array[TerrainType] = []:
	set(v):
		grows_on = v
		emit_changed()
## Metres between patches, least and most.
@export var gap: Vector2i = Vector2i(6, 14):
	set(v):
		gap = v
		emit_changed()
## Cells in a patch, least and most.
@export var width: Vector2i = Vector2i(2, 4):
	set(v):
		width = v
		emit_changed()
## Metres kept clear of the flags, the level's objects and the level's ends.
@export_range(0, 20) var clearance: int = 3:
	set(v):
		clearance = v
		emit_changed()
## Another number gives other places for the patches.
@export var pattern_seed: int = 1:
	set(v):
		pattern_seed = v
		emit_changed()


## The grass cells on terrain, clear of the keep_clear columns. vary gives each level its own pattern.
func cells(terrain: Terrain, keep_clear: Array, vary: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([pattern_seed, vary])
	var left := terrain.min_x + clearance
	var right := terrain.size.x - clearance
	var x := terrain.min_x + rng.randi_range(0, maxi(gap.y, 0))
	while x < right:
		var w := rng.randi_range(width.x, width.y)
		for cx in range(maxi(x, left), mini(x + w, right)):
			var row := terrain.surface_row(cx)
			if row >= 2 and _clear(cx, keep_clear) and terrain.type_at(Vector2i(cx, row)) in grows_on \
					and terrain.type_at(Vector2i(cx, row - 1)) == null and terrain.type_at(Vector2i(cx, row - 2)) == null:
				out.append(Vector2i(cx, row - 1))
		x += maxi(w, 1) + rng.randi_range(gap.x, gap.y)
	return out


func _clear(x: int, keep_clear: Array) -> bool:
	for k: int in keep_clear:
		if absi(x - k) < clearance:
			return false
	return true
