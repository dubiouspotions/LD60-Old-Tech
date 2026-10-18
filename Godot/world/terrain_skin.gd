@tool
class_name TerrainSkin
extends Node2D
## Draws the rock in the dirt over the parent Terrain when its look is on (see TerrainLook): a layer half a cell
## off, each tile covering the corner where four cells meet and picked by which of them are rock. The Terrain draws
## its own cells; this is only the rock overlay. In the editor it follows the painted tiles as you paint.

var _terrain: Terrain
var _body: TileMapLayer
var _on: bool = false
var _editor_dirty: bool = true


func _ready() -> void:
	_terrain = get_parent() as Terrain
	_body = TileMapLayer.new()
	_body.name = "Body"
	_body.position = Vector2.ONE * Grid.PX / 2.0
	add_child(_body, false, Node.INTERNAL_MODE_FRONT)
	if Engine.is_editor_hint() and _terrain:
		_terrain.changed.connect(func() -> void: _editor_dirty = true)
	refresh()


func _process(_delta: float) -> void:
	refresh()


func body_layer() -> TileMapLayer:
	return _body


## Applies the look's switch and redraws the overlay around whatever changed in the terrain.
func refresh() -> void:
	if _terrain == null:
		return
	var look := _terrain.look
	var on := look != null and look.enabled and look.texture != null
	if Engine.is_editor_hint():
		if on and (_editor_dirty or not _on):
			_editor_dirty = false
			_on = true
			_use_texture(look)
			_redraw(_terrain.rules(true), _terrain.get_used_rect())
		elif not on and _on:
			_on = false
			_body.clear()
		return
	var changes := _terrain.take_changes()
	if on != _on:
		_on = on
		_body.clear()
		if on:
			_use_texture(look)
			changes.all = true
	if not _on:
		return
	var rules := _terrain.rules()
	if changes.all:
		_redraw(rules, Rect2i(_terrain.min_x - 1, -1, _terrain.size.x - _terrain.min_x + 2, _terrain.size.y + 2))
		return
	var corners := {}
	for c: Vector2i in changes.cells:
		for dy in range(-1, 1):
			for dx in range(-1, 1):
				corners[c + Vector2i(dx, dy)] = true
	for c: Vector2i in corners:
		_draw_corner(rules, c)


func _use_texture(look: TerrainLook) -> void:
	if _body.tile_set and (_body.tile_set.get_source(0) as TileSetAtlasSource).texture == look.texture:
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i.ONE * look.tile_size
	var src := TileSetAtlasSource.new()
	src.texture = look.texture
	src.texture_region_size = Vector2i.ONE * look.tile_size
	ts.add_source(src, 0)
	for c: Vector2i in look.body:
		if c.x >= 0 and not src.has_tile(c):
			src.create_tile(c)
	_body.tile_set = ts


func _redraw(rules: TileRules, area: Rect2i) -> void:
	_body.clear()
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			_draw_corner(rules, Vector2i(x, y))


func _draw_corner(rules: TileRules, corner: Vector2i) -> void:
	var tile := rules.body(corner)
	if tile.x < 0:
		_body.erase_cell(corner)
	else:
		_body.set_cell(corner, 0, tile)
