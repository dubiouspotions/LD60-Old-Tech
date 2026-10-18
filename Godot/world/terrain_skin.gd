class_name TerrainSkin
extends Node2D
## Draws the parent Terrain with the v2 look when look.enabled (see TerrainLook), and hides the Terrain's own tiles.
## Every tile is a rule on the cell's neighbours, so tiles never meet an edge they were not drawn for:
## - the cell layer picks the grass surface, walls, inner corners, fillets in air cells, water and spikes;
## - the body layer sits half a cell off and draws rock pockets in the dirt: each of its tiles covers the corner
##   where four cells meet and is picked by which of them are rock.
## Materials without v2 art keep their old tile. Only cells around a change are redrawn.

## Atlas source id of the v2 sheet in the terrain's TileSet.
const V2_SOURCE: int = 100

@export var look: TerrainLook

var _terrain: Terrain
var _cells: TileMapLayer
var _body: TileMapLayer
var _on: bool = false


func _ready() -> void:
	_terrain = get_parent() as Terrain
	_cells = TileMapLayer.new()
	_cells.name = "Cells"
	add_child(_cells)
	_body = TileMapLayer.new()
	_body.name = "Body"
	_body.position = Vector2.ONE * Grid.PX / 2.0
	add_child(_body)
	refresh()


func _process(_delta: float) -> void:
	refresh()


func cells_layer() -> TileMapLayer:
	return _cells


func body_layer() -> TileMapLayer:
	return _body


## Applies the look's switch and redraws whatever changed in the terrain since the last call.
func refresh() -> void:
	if _terrain == null:
		return
	var on := look != null and look.enabled and look.texture != null
	var changes := _terrain.take_changes()
	if on != _on:
		_on = on
		_terrain.enabled = not on
		_cells.clear()
		_body.clear()
		if on:
			_add_source()
			changes.all = true
	if not _on:
		return
	if changes.all:
		_redraw_all()
	else:
		_redraw_around(changes.cells)


func _add_source() -> void:
	var ts := _terrain.tile_set
	_cells.tile_set = ts
	_body.tile_set = ts
	if ts.has_source(V2_SOURCE):
		return
	var img := look.texture.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(look.sky_key):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i.ONE * look.tile_size
	for y in img.get_height() / look.tile_size:
		for x in img.get_width() / look.tile_size:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, V2_SOURCE)


func _redraw_all() -> void:
	_cells.clear()
	_body.clear()
	for y in range(-1, _terrain.size.y + 1):
		for x in range(_terrain.min_x - 1, _terrain.size.x + 1):
			_draw_cell(Vector2i(x, y))
			_draw_body(Vector2i(x, y))


func _redraw_around(changed: Array) -> void:
	var cells := {}
	var corners := {}
	for c: Vector2i in changed:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				cells[c + Vector2i(dx, dy)] = true
		for dy in range(-1, 1):
			for dx in range(-1, 1):
				corners[c + Vector2i(dx, dy)] = true
	for c: Vector2i in cells:
		_draw_cell(c)
	for c: Vector2i in corners:
		_draw_body(c)


func _draw_cell(cell: Vector2i) -> void:
	var t := _terrain.type_at(cell)
	var tile := Vector2i(-1, -1)
	if t == null:
		tile = _fillet(cell)
	elif t in look.water_types:
		tile = TerrainLook.pick(look.water if _terrain.type_at(cell + Vector2i.UP) in look.water_types else look.water_top, cell)
	elif t in look.spike_types:
		tile = TerrainLook.pick(look.spikes, cell)
	elif _ground(cell):
		tile = _ground_tile(cell)
	else:
		var old := _terrain.atlas_tile(t)
		if old.is_empty():
			_cells.erase_cell(cell)
		else:
			_cells.set_cell(cell, old[0], old[1])
		return
	if tile.x < 0:
		_cells.erase_cell(cell)
	else:
		_cells.set_cell(cell, V2_SOURCE, tile)


## Grass edge, wall, inner corner or plain dirt for a dirt or rock cell.
func _ground_tile(cell: Vector2i) -> Vector2i:
	var up := _solid(cell + Vector2i.UP)
	var left := _solid(cell + Vector2i.LEFT)
	var right := _solid(cell + Vector2i.RIGHT)
	if not up:
		if not left and right:
			return TerrainLook.pick(look.corner_tl, cell)
		if left and not right:
			return TerrainLook.pick(look.corner_tr, cell)
		return TerrainLook.pick(look.flat_tops, cell)
	if not left:
		return TerrainLook.pick(look.wall_l, cell)
	if not right:
		return TerrainLook.pick(look.wall_r, cell)
	if not _solid(cell + Vector2i(-1, -1)):
		return TerrainLook.pick(look.inner_tl, cell)
	if not _solid(cell + Vector2i(1, -1)):
		return TerrainLook.pick(look.inner_tr, cell)
	return TerrainLook.pick(look.dirt, cell)


## Grass filling the air cell at the foot of a step, or (-1, -1).
func _fillet(cell: Vector2i) -> Vector2i:
	if not _ground(cell + Vector2i.DOWN):
		return Vector2i(-1, -1)
	var left := _ground(cell + Vector2i.LEFT)
	var right := _ground(cell + Vector2i.RIGHT)
	if right and not left:
		# The low fillet meets the rounded top-left corner of the ground below.
		var low := not _solid(cell + Vector2i(-1, 1))
		return TerrainLook.pick(look.fillet_r_low if low else look.fillet_r, cell)
	if left and not right:
		var low := not _solid(cell + Vector2i(1, 1))
		return TerrainLook.pick(look.fillet_l_low if low else look.fillet_l, cell)
	return Vector2i(-1, -1)


## Rock in the dirt: the tile on the corner where cells (x, y) to (x + 1, y + 1) meet. Only drawn where all four
## are dirt or rock and at least one is rock; elsewhere the cell layer shows through.
func _draw_body(corner: Vector2i) -> void:
	var quad: Array[Vector2i] = [corner, corner + Vector2i.RIGHT, corner + Vector2i.DOWN, corner + Vector2i.ONE]
	var mask := 0
	for i in 4:
		if not _ground(quad[i]):
			_body.erase_cell(corner)
			return
		if _terrain.type_at(quad[i]) in look.rock_types:
			mask |= 1 << i
	if mask == 0:
		_body.erase_cell(corner)
	else:
		_body.set_cell(corner, V2_SOURCE, look.body_tile(mask, corner))


## Dirt or rock: drawn from the v2 sheet.
func _ground(cell: Vector2i) -> bool:
	var t := _terrain.type_at(cell)
	return t != null and (t in look.dirt_types or t in look.rock_types)


func _solid(cell: Vector2i) -> bool:
	return _terrain.is_solid(cell)
