class_name FallingPiece
extends Node2D
## A tower or tree that lost the ground under it, falling straight down as one piece with what stands on it (riders:
## archers, flags, torches and any other object on top of it or inside it). It stops on the first cell of ground in
## its way and becomes ground again there, each tile as it was. If it fell further than its tiles' Survives Fall, or
## onto something that Breaks Falling (spikes), it breaks up instead: a tower collapses, a tree is felled, and its
## riders go with it. Landing whole after more than crush_free_fall, it breaks a layer of the ground under it for
## every metre more and sinks into the hole, again and again, until a short drop leaves it standing. It crushes
## soldiers, engineers, archers and boxes it falls onto. Stepped by the World. The node origin is the top-left of
## its top-left cell.

@export var gravity: float = 30.0
@export var max_speed: float = 22.0
## Played when it lands in one piece.
@export var land_sound: SoundEffect
@export_range(0.0, 2.0, 0.05) var land_shake: float = 0.2
## Metres it can drop and land whole without breaking the ground under it. Each metre more breaks one layer (ground
## that can not be dug, such as bedrock, holds).
@export_range(0, 10) var crush_free_fall: int = 1

## The lifted tiles (Terrain.lift), by the cell each came from.
var tiles: Dictionary = {}
## Nodes carried down with it.
var riders: Array[Node2D] = []
## A razed tower coming down: each time it hits the ground its bottom row breaks, and the rest falls on, until none
## is left (instead of landing in one piece).
var crumble: bool = false
## Seconds before it starts to fall (the columns of a razed tower go one after another).
var delay: float = 0.0
## Metres fallen so far.
var fallen: float = 0.0
var _vy: float = 0.0
var _origin: Vector2i


## Takes the tiles and draws them with the terrain's TileSet.
func setup(lifted: Dictionary, terrain: Terrain) -> void:
	tiles = lifted
	_origin = Vector2i(1 << 30, 1 << 30)
	for c: Vector2i in tiles:
		_origin = Vector2i(mini(_origin.x, c.x), mini(_origin.y, c.y))
	position = Grid.to_px(Vector2(_origin))
	var layer: TileMapLayer = $Tiles
	layer.tile_set = terrain.tile_set
	for c: Vector2i in tiles:
		var tile: Dictionary = tiles[c]
		if tile.source != -1:
			layer.set_cell(c - _origin, tile.source, tile.coords, tile.alt)


## Does the piece cover the point p (metres) where it is now.
func covers(p: Vector2) -> bool:
	return tiles.has(Vector2i(floori(p.x), floori(p.y - fallen)))


func step(dt: float, world: World) -> void:
	if delay > 0.0:
		delay -= dt
		return
	var t := world.terrain
	_vy = minf(_vy + gravity * dt, max_speed)
	var next := fallen + _vy * dt
	var landed := false
	for k in range(floori(fallen) + 1, ceili(next) + 1):
		if _blocked(t, k):
			next = k - 1
			landed = true
			break
	for r in riders:
		if is_instance_valid(r):
			r.position.y += (next - fallen) * Grid.PX
	fallen = next
	position.y = (_origin.y + fallen) * Grid.PX
	world.crush_under(self)
	if landed:
		_land(world)


## Would the piece at k rows down overlap anything (ground, a hazard, the bottom of the world).
func _blocked(t: Terrain, k: int) -> bool:
	for c: Vector2i in tiles:
		var at := c + Vector2i(0, k)
		if at.y >= t.size.y or t.type_at(at) != null:
			return true
	return false


func _land(world: World) -> void:
	var t := world.terrain
	var rows := roundi(fallen)
	if crumble:
		_break_bottom_row(t, rows)
		if not tiles.is_empty():
			_vy = 0.0
			return
	var survives := INF
	var smashed := false
	var ground := {}
	for c: Vector2i in tiles:
		var type: TerrainType = tiles[c].type
		if type == null:
			continue
		ground[c] = tiles[c]
		survives = minf(survives, type.survives_fall)
		var under := t.type_at(c + Vector2i(0, rows + 1))
		smashed = smashed or (under != null and under.breaks_falling and not c + Vector2i.DOWN in tiles)
	if fallen > survives or smashed:
		# Decorations go with the rubble.
		t.break_up(t.put(ground, rows))
		for r in riders:
			if is_instance_valid(r):
				if r.has_method(&"lose_ground"):
					r.lose_ground()
				else:
					r.queue_free()
	else:
		var cells := t.put(tiles, rows)
		_crush_under(t, cells, rows - crush_free_fall)
		Audio.play(land_sound, position)
		Effects.shake(land_shake)
	riders.clear()
	queue_free()


## Breaks the bottom row of the piece, rows below where it started, where it hit the ground.
func _break_bottom_row(t: Terrain, rows: int) -> void:
	var bottom := -(1 << 30)
	for c: Vector2i in tiles:
		bottom = maxi(bottom, c.y)
	var row := {}
	var color := Color.GRAY
	for c: Vector2i in tiles.keys():
		if c.y != bottom:
			continue
		row[c] = tiles[c]
		tiles.erase(c)
		($Tiles as TileMapLayer).erase_cell(c - _origin)
		if row[c].type != null:
			color = (row[c].type as TerrainType).debris_color
	if row.values().any(func(tile: Dictionary) -> bool: return tile.type != null):
		# Set down where it hit, then broken; break_up takes the decorations beside it too.
		t.break_up(t.put(row, rows))
		return
	for c: Vector2i in row:
		var at := t.cell_center_px(c + Vector2i(0, rows))
		Effects.rubble(at, color, t.collapse_rubble, t.collapse_rubble_speed)
		Effects.dust(at, color, t.collapse_dust)


## Breaks layers of the ground under the landed cells (each column's lowest), stopping at ground that can not be
## dug. With nothing under it the piece comes loose and falls on into the hole.
func _crush_under(t: Terrain, cells: Array[Vector2i], layers: int) -> void:
	for c in cells:
		if c + Vector2i.DOWN in cells:
			continue
		for k in range(1, layers + 1):
			var n := c + Vector2i(0, k)
			var nt := t.type_at(n)
			if nt != null and nt.dig_action == TerrainType.DigAction.NONE:
				break
			if nt != null:
				t.set_type(n, null)
				Effects.debris(t.cell_center_px(n), nt.debris_color, 3, 90.0)
