@tool
class_name TallGrass
extends TileMapLayer
## Tall grass in the world, drawn in front of the soldiers and objects. Levels paint it on their Grass layer, in the
## air on top of the ground; the World stitches it on with the level's terrain. A patch goes when the ground under
## it is dug away or its own cell is filled, also while painting a level in the editor. A level's grass with a
## scatter is grown by it instead of painted (see Level.regrow_grass).

## The ground the grass stands on.
@export var terrain: Terrain:
	set(v):
		if terrain:
			terrain.cell_changed.disconnect(_on_cell_changed)
		terrain = v
		if terrain:
			terrain.cell_changed.connect(_on_cell_changed)
## Spreads this grass over the terrain in the editor. Empty: the grass is painted by hand.
@export var scatter: GrassScatter


## Replaces the grass with scatter's patches, clear of the keep_clear columns (see GrassScatter.cells).
func regrow(keep_clear: Array, vary: int) -> void:
	clear()
	for c in scatter.cells(terrain, keep_clear, vary):
		set_cell(c, 0, Vector2i.ZERO)


## Copies src's grass whose column, moved by offset, is seam or later, replacing everything from seam on.
func stamp(src: TileMapLayer, offset: Vector2i, seam: int) -> void:
	clear_from(seam)
	for cell in src.get_used_cells():
		var to := cell + offset
		if to.x >= seam:
			set_cell(to, src.get_cell_source_id(cell), src.get_cell_atlas_coords(cell), src.get_cell_alternative_tile(cell))


## Removes the grass from column x on.
func clear_from(x: int) -> void:
	for cell in get_used_cells():
		if cell.x >= x:
			erase_cell(cell)


## Removes the grass left of column x.
func unload_before(x: int) -> void:
	for cell in get_used_cells():
		if cell.x < x:
			erase_cell(cell)


func _on_cell_changed(cell: Vector2i) -> void:
	for c: Vector2i in [cell, cell + Vector2i.UP]:
		if get_cell_source_id(c) != -1 and (terrain.is_solid(c) or not terrain.is_solid(c + Vector2i.DOWN)):
			erase_cell(c)
