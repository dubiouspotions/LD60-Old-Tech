@tool
class_name Terrain
extends TileMapLayer
## The level ground. Paint it with the TileSet; every tile's behaviour comes from the TerrainType
## in its "terrain" custom data. Cells are metres: cell (x, y) covers x..x+1, y..y+1. Empty cells are air.
## Outside the painted area: above is air, left/right/below is out_of_bounds (bedrock).

## A fill-type tile fell loose; the level spawns a falling block for it.
signal tile_detached(cell: Vector2i, type: TerrainType)
## Structures with no ground under them fell apart.
signal collapsed(found: Supplies, cells: Array[Vector2i])

const CUSTOM_DATA: String = "terrain"

@export var out_of_bounds: TerrainType
@export var collapse_sound: SoundEffect
## How far around a change structures are re-checked for support.
@export_range(4, 100) var structure_search: int = 30

## Painted width and height in cells (from the origin).
var size: Vector2i = Vector2i.ZERO

var _types: Dictionary = {} # Vector2i -> TerrainType
var _tile_for: Dictionary = {} # TerrainType -> [source_id, atlas_coords]
var _dirty_cols: Dictionary = {} # int -> true


func _ready() -> void:
	rebuild()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		settle()


## Re-reads every painted cell. Call after painting from code.
func rebuild() -> void:
	_types.clear()
	_tile_for.clear()
	size = Vector2i.ZERO
	_index_tileset()
	for cell in get_used_cells():
		var t := _read_cell(cell)
		if t:
			_types[cell] = t
	_update_size()


func type_at(cell: Vector2i) -> TerrainType:
	if cell.y < 0:
		return null
	if cell.x < 0 or cell.x >= size.x or cell.y >= size.y:
		return out_of_bounds
	return _types.get(cell)


func is_solid(cell: Vector2i) -> bool:
	var t := type_at(cell)
	return t != null and t.solid


func is_anchor(cell: Vector2i) -> bool:
	var t := type_at(cell)
	return t != null and t.anchor


## Top-most solid row in column x.
func surface_row(x: int) -> int:
	for y in size.y:
		if is_solid(Vector2i(x, y)):
			return y
	return size.y


## Changes one cell. null makes it air. Marks the area for settle().
func set_type(cell: Vector2i, type: TerrainType) -> void:
	if type == null:
		_types.erase(cell)
		erase_cell(cell)
	else:
		if _tile_for.is_empty():
			_index_tileset()
		_types[cell] = type
		var tile: Array = _tile_for.get(type, [])
		if tile.is_empty():
			push_error("Terrain: no tile in the TileSet uses %s" % type.resource_path)
		else:
			set_cell(cell, tile[0], tile[1])
	if cell.x >= size.x or cell.y >= size.y:
		_update_size()
	_dirty_cols[cell.x] = true


## Digs one cell with the Dig tool. Returns what was gained, or null if the tile can not be dug.
func dig(cell: Vector2i) -> Supplies:
	var t := type_at(cell)
	if t == null or t.dig_action == TerrainType.DigAction.NONE or not _inside(cell):
		return null
	Audio.play(t.dig_sound, cell_center_px(cell))
	if t.dig_action == TerrainType.DigAction.FELL:
		return fell(cell)
	set_type(cell, null)
	Effects.debris(cell_center_px(cell), t.debris_color, 3, 90.0)
	var got := t.dig_yield.copy() if t.dig_yield else Supplies.new()
	return got


## Removes every connected tile that fells with this one (a whole tree). Returns the bulk yield.
func fell(cell: Vector2i) -> Supplies:
	var counts := {}
	var stack: Array[Vector2i] = [cell]
	var seen := {}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if seen.has(c):
			continue
		seen[c] = true
		var t := type_at(c)
		if t == null or t.dig_action != TerrainType.DigAction.FELL:
			continue
		counts[t] = counts.get(t, 0) + 1
		set_type(c, null)
		Effects.debris(cell_center_px(c), t.debris_color, 1, 70.0)
		stack.append_array([c + Vector2i.RIGHT, c + Vector2i.LEFT, c + Vector2i.DOWN, c + Vector2i.UP])
	return TerrainType.bulk_total(counts)


## Clears every cell whose centre lies within radius (metres) of center. Trees caught are felled whole.
func blast(center: Vector2, radius: float) -> Supplies:
	var counts := {}
	var felled := Supplies.new()
	var r := ceili(radius)
	var c0 := Vector2i(floori(center.x), floori(center.y))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var cell := c0 + Vector2i(dx, dy)
			if (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(center) > radius:
				continue
			var t := type_at(cell)
			if t == null or t.blast_proof or not _inside(cell):
				continue
			if t.dig_action == TerrainType.DigAction.FELL:
				felled.add(fell(cell))
				continue
			counts[t] = counts.get(t, 0) + 1
			set_type(cell, null)
			Effects.debris(cell_center_px(cell), t.debris_color, 2, 160.0)
	var got := TerrainType.bulk_total(counts)
	got.add(felled)
	return got


## Detaches unsupported falling tiles and collapses unsupported structures near recent changes.
func settle() -> void:
	if _dirty_cols.is_empty():
		return
	var xs: Array = _dirty_cols.keys()
	xs.sort()
	_dirty_cols.clear()
	_detach_loose(xs)
	# group nearby columns so one flood fill covers each cluster
	var a: int = xs[0]
	var b: int = xs[0]
	for i in range(1, xs.size() + 1):
		if i < xs.size() and xs[i] - b <= 20:
			b = xs[i]
			continue
		_collapse_unsupported(a - structure_search, b + structure_search, a - structure_search / 2, b + structure_search / 2)
		if i < xs.size():
			a = xs[i]
			b = xs[i]


func cell_center_px(cell: Vector2i) -> Vector2:
	return Grid.to_px(Vector2(cell) + Vector2(0.5, 0.5))


func _detach_loose(xs: Array) -> void:
	var seen := {}
	for x: int in xs:
		for xx in range(x - 1, x + 2):
			if seen.has(xx):
				continue
			seen[xx] = true
			for y in range(size.y - 2, -1, -1):
				var cell := Vector2i(xx, y)
				var t := type_at(cell)
				if t and t.falls and not is_solid(cell + Vector2i.DOWN) and _inside(cell):
					_types.erase(cell)
					erase_cell(cell)
					tile_detached.emit(cell, t)


func _collapse_unsupported(xa: int, xb: int, ca: int, cb: int) -> void:
	var supported := {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in _types:
		if cell.x < xa or cell.x > xb or not _types[cell].structure:
			continue
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
			if is_anchor(cell + d):
				supported[cell] = true
				queue.append(cell)
				break
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = cell + d
			if n.x < xa or n.x > xb or supported.has(n):
				continue
			var t: TerrainType = _types.get(n)
			if t and t.structure:
				supported[n] = true
				queue.append(n)
	var counts := {}
	var fallen: Array[Vector2i] = []
	for cell: Vector2i in _types.keys():
		var t: TerrainType = _types[cell]
		if cell.x < ca or cell.x > cb or not t.structure or supported.has(cell):
			continue
		counts[t] = counts.get(t, 0) + 1
		fallen.append(cell)
		_types.erase(cell)
		erase_cell(cell)
		Effects.debris(cell_center_px(cell), t.debris_color, 3, 110.0)
	if fallen.is_empty():
		return
	Audio.play(collapse_sound, cell_center_px(fallen[0]))
	Effects.shake(0.25)
	collapsed.emit(TerrainType.bulk_total(counts), fallen)


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _update_size() -> void:
	# Only grows: digging the last tile of a column must not move the level edge.
	var r := get_used_rect()
	size = Vector2i(maxi(size.x, r.end.x), maxi(size.y, r.end.y))


func _read_cell(cell: Vector2i) -> TerrainType:
	var data := get_cell_tile_data(cell)
	if data == null:
		return null
	return data.get_custom_data(CUSTOM_DATA) as TerrainType


func _index_tileset() -> void:
	if tile_set == null:
		return
	for i in tile_set.get_source_count():
		var sid := tile_set.get_source_id(i)
		var src := tile_set.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coords := src.get_tile_id(t)
			var type := src.get_tile_data(coords, 0).get_custom_data(CUSTOM_DATA) as TerrainType
			if type and not _tile_for.has(type):
				_tile_for[type] = [sid, coords]
