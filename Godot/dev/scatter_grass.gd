extends Node
## Scatters patches of tall grass over every campaign level that has none yet, as a starting point to paint over.
## Runs as a scene (the levels need the autoloads):
##   godot --headless res://dev/scatter_grass.tscn -- [force] [gap=6,14] [width=2,4] [seed=1]
## force re-scatters levels that already have grass. A patch is a run of grass cells on flat soil (the cell under
## each is soil, the cell itself air), kept clear of the flags, the level's objects and the ground left of the
## StartFlag (dropped when levels are stitched). Levels are inherited scenes, so only the Grass node's
## tile_map_data is written.

const FLAG_CLEAR: int = 3


func _ready() -> void:
	var force := false
	var gap := Vector2i(6, 14)
	var width := Vector2i(2, 4)
	var seed_base := 1
	for a in OS.get_cmdline_user_args():
		if a == "force":
			force = true
		elif a.begins_with("gap="):
			gap = Vector2i(int(a.get_slice("=", 1).get_slice(",", 0)), int(a.get_slice("=", 1).get_slice(",", 1)))
		elif a.begins_with("width="):
			width = Vector2i(int(a.get_slice("=", 1).get_slice(",", 0)), int(a.get_slice("=", 1).get_slice(",", 1)))
		elif a.begins_with("seed="):
			seed_base = int(a.get_slice("=", 1))
	var levels: Array = GameState.campaign.levels
	for i in levels.size():
		_scatter(levels[i], force, gap, width, seed_base * 7919 + i)
	get_tree().quit()


func _scatter(path: String, force: bool, gap: Vector2i, width: Vector2i, rng_seed: int) -> void:
	var lv: Level = (load(path) as PackedScene).instantiate()
	add_child(lv)
	var grass := lv.grass()
	if not grass.get_used_cells().is_empty() and not force:
		print("scatter_grass: %s already has grass" % path)
		lv.free()
		return
	grass.clear()
	var t := lv.terrain()
	var soil: TerrainType = load("res://data/terrain/soil.tres")
	var start := floori(lv.start_flag().metres().x)
	var keep_clear := [start, floori(lv.exit_flag().metres().x)]
	for o in lv.objects().get_children():
		if o is Node2D:
			keep_clear.append(floori((o as Node2D).position.x / Grid.PX))
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var x := start + FLAG_CLEAR + rng.randi_range(0, gap.x)
	var patches := 0
	while x < t.size.x - FLAG_CLEAR:
		var w := rng.randi_range(width.x, width.y)
		if _fits(t, soil, x, w, keep_clear):
			var y := t.surface_row(x) - 1
			for i in w:
				grass.set_cell(Vector2i(x + i, y), 0, Vector2i.ZERO)
			patches += 1
			x += w + rng.randi_range(gap.x, gap.y)
		else:
			x += 1
	var data := Marshalls.raw_to_base64(grass.tile_map_data)
	lv.free()
	_write(path, data)
	print("scatter_grass: %s gets %d patches" % [path, patches])


## A run of w cells from column x on flat soil, open to the sky above the grass, away from flags and objects.
func _fits(t: Terrain, soil: TerrainType, x: int, w: int, keep_clear: Array) -> bool:
	var row := t.surface_row(x)
	for i in w:
		var cx := x + i
		for k: int in keep_clear:
			if absi(cx - k) < FLAG_CLEAR:
				return false
		if t.surface_row(cx) != row or t.type_at(Vector2i(cx, row)) != soil:
			return false
		if t.type_at(Vector2i(cx, row - 1)) != null or t.type_at(Vector2i(cx, row - 2)) != null:
			return false
	return true


func _write(path: String, data: String) -> void:
	var lines := FileAccess.get_file_as_string(path).rstrip("\n").split("\n")
	var out: PackedStringArray = []
	var skip := false
	for line in lines:
		if line.begins_with("[node "):
			skip = line.begins_with('[node name="Grass"')
		if not skip:
			out.append(line)
	while not out.is_empty() and out[out.size() - 1].strip_edges().is_empty():
		out.remove_at(out.size() - 1)
	out.append("")
	out.append('[node name="Grass" parent="." index="4" unique_id=1873402215]')
	out.append('tile_map_data = PackedByteArray("%s")' % data)
	FileAccess.open(path, FileAccess.WRITE).store_string("\n".join(out) + "\n")
