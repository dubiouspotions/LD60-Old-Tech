class_name WorldFixture
## Builds small test worlds from ASCII maps. Row 0 is the top. Outside the map is bedrock.

const LEGEND: Dictionary = {
	".": "", "#": "soil", "R": "rock", "B": "bedrock", "~": "water", "^": "spikes",
	"K": "brick", "C": "crystal", "T": "trunk", "L": "leaves", "F": "fill",
}


static func type(key: String) -> TerrainType:
	return load("res://data/terrain/%s.tres" % key)


static func terrain(test: GutTest, rows: Array) -> Terrain:
	var t: Terrain = load("res://world/terrain.tscn").instantiate()
	test.add_child_autofree(t)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key: String = LEGEND[row[x]]
			if key != "":
				t.set_type(Vector2i(x, y), type(key))
	t.settle()
	return t


static func bridge(test: GutTest, t: Terrain) -> Bridge:
	var b: Bridge = load("res://world/bridge.tscn").instantiate()
	b.terrain = t
	test.add_child_autofree(b)
	return b


static func army(test: GutTest, t: Terrain, b: Bridge) -> Army:
	var a: Army = load("res://game/army.tscn").instantiate()
	a.terrain = t
	a.bridge = b
	test.add_child_autofree(a)
	return a


## Paints a decoration (an old tile with no material, like battlements) at cell. Returns its atlas coords.
static func decorate(t: Terrain, cell: Vector2i) -> Vector2i:
	var src := t.tile_set.get_source(t.look.classic_source) as TileSetAtlasSource
	for i in src.get_tiles_count():
		var c := src.get_tile_id(i)
		if src.get_tile_data(c, 0).get_custom_data(Terrain.CUSTOM_DATA) == null:
			t.set_cell(cell, t.look.classic_source, c)
			return c
	return Vector2i(-1, -1)
