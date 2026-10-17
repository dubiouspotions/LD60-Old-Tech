extends Node
## Generates starter levels with the original game's segment generator and saves them as editable scenes
## (levels/level_NN.tscn, inherited from level_base.tscn). After that, designers edit them by hand.
## Refuses to overwrite a level that already exists unless "force" is passed.
## Runs as a scene so the autoloads exist:
##   godot --headless res://dev/generate_levels.tscn -- [count=6] [seed=60] [force]

const SEG: int = 120 # level length up to the exit flag area, tiles
const TAIL: int = 14 # flat run after it, where the exit flag stands
const FLAG_OFF: int = 6
const ROWS: int = 48
const BASE: String = "res://levels/level_base.tscn"
const ARCHER: String = "res://objects/archer/archer.tscn"

enum K { GROUND, CHASM, PIT, MESA }
enum Tile { AIR, DIRT, GRASS, ROCK, BEDROCK, WATER, BRICK, CRYSTAL, TRUNK, LEAVES, SPIKES }

var seed_value: int = 60
var rng := RandomNumberGenerator.new()

# per level
var surf: PackedInt32Array
var kind: PackedInt32Array
var base: PackedInt32Array
var no_tree: PackedByteArray
var extras: Array = []
var h: int
var i: int
var level_n: int
var grid: Array = [] # columns of Tile


func _ready() -> void:
	var count := 6
	var force := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("count="):
			count = int(a.get_slice("=", 1))
		elif a.begins_with("seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a == "force":
			force = true
	h = 27
	for s in count:
		var path := "res://levels/level_%02d.tscn" % (s + 1)
		_generate(s)
		if FileAccess.file_exists(path) and not force:
			print("skip existing ", path)
			continue
		_save(s, path)
	get_tree().quit()


func _hash2(x: int, y: int) -> float:
	var v := (x * 374761393 + y * 668265263 + seed_value * 2246822519) & 0xFFFFFFFF
	v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(v ^ (v >> 16)) / 4294967296.0


func _put(row: int, k: int = K.GROUND) -> void:
	if i < SEG:
		surf[i] = row
		kind[i] = k
		base[i] = h
		i += 1


func _flat(n: int) -> void:
	for k in n:
		_put(h)


func _gentle(n: int) -> void:
	for k in n:
		if k > 0 and k < n - 1 and rng.randf() < 0.2:
			var nh := h + (-1 if rng.randf() < 0.5 else 1)
			if nh >= 20 and nh <= 33:
				h = nh
		_put(h)


func _obstacle(type: String) -> void:
	var L := level_n
	match type:
		"chasm":
			var w := mini(3 + int(rng.randf() * (L + 2)), 11)
			for k in w:
				_put(h, K.CHASM)
		"mesa":
			var r := 2 + int(rng.randf() * mini(L + 1, 4))
			var w := 4 + int(rng.randf() * 5)
			var rocky := L >= 3 and rng.randf() < 0.45
			for k in w:
				_put(h - r, K.MESA if rocky else K.GROUND)
		"step":
			if h >= 28:
				h -= 2 + int(rng.randf() * mini(L + 1, 4))
			else:
				h = mini(h + 4 + int(rng.randf() * mini(L + 1, 4)), 34)
			_flat(3)
		"pit":
			var w := 3 + int(rng.randf() * 3)
			for k in w:
				_put(h + 3, K.PIT)
		"pillar":
			var ph := 3 + int(rng.randf() * mini(L + 2, 5))
			_flat(1)
			extras.append({t = "pillar", i = i, top = h - ph, g = h})
			_flat(3)
		"tower":
			_flat(2)
			extras.append({t = "tower", i = i, g = h, th = 6 + int(rng.randf() * 4)})
			_flat(5)


func _generate(s: int) -> void:
	level_n = s + 1
	rng.seed = hash([seed_value, s])
	surf = PackedInt32Array()
	surf.resize(SEG)
	kind = PackedInt32Array()
	kind.resize(SEG)
	base = PackedInt32Array()
	base.resize(SEG)
	no_tree = PackedByteArray()
	no_tree.resize(SEG + TAIL)
	extras = []
	i = 0
	var pool := ["chasm", "mesa", "pit"]
	if level_n >= 2:
		pool.append_array(["step", "pillar", "chasm"])
	if level_n >= 3:
		pool.append_array(["tower", "mesa"])
	if level_n >= 5:
		pool.append_array(["tower", "chasm", "pillar"])
	_flat(12)
	var max_obs := mini(2 + level_n / 2, 5)
	var n := 0
	var last := ""
	while i < SEG - 26 and n < max_obs:
		_gentle(maxi(4, 9 - level_n / 2) + int(rng.randf() * 5))
		var type: String = pool[int(rng.randf() * pool.size())]
		while type == last:
			type = pool[int(rng.randf() * pool.size())]
		last = type
		var st := i
		_obstacle(type)
		for k in range(maxi(0, st - 1), mini(SEG - 1, i) + 1):
			no_tree[k] = 1
		n += 1
	if i < SEG:
		_gentle(SEG - i)
	# flat tail where the exit flag stands; the next level starts at this height
	surf.resize(SEG + TAIL)
	kind.resize(SEG + TAIL)
	base.resize(SEG + TAIL)
	for k in range(SEG, SEG + TAIL):
		surf[k] = h
		kind[k] = K.GROUND
		base[k] = h
	_fill_grid()


func _fill_grid() -> void:
	var width := SEG + TAIL
	grid = []
	for k in width:
		var col := PackedInt32Array()
		col.resize(ROWS)
		var g := surf[k]
		var soil := g + 4 + int(_hash2(k, 7) * 3)
		for y in ROWS:
			var t := Tile.AIR
			if y >= ROWS - 2:
				t = Tile.BEDROCK
			elif kind[k] == K.CHASM:
				t = Tile.AIR if y < ROWS - 7 else (Tile.WATER if y < ROWS - 4 else Tile.ROCK)
			elif y < g:
				t = Tile.AIR
			elif kind[k] == K.MESA and y < base[k]:
				t = Tile.ROCK
			elif y == g:
				t = Tile.GRASS
			elif y < soil:
				t = Tile.CRYSTAL if (y <= g + 3 and _hash2(k, y) < 0.028) else Tile.DIRT
			else:
				t = Tile.ROCK
			col[y] = t
		if kind[k] == K.PIT:
			col[g - 1] = Tile.SPIKES
		grid.append(col)
	for e: Dictionary in extras:
		var x: int = e.i
		if e.t == "pillar":
			for dx in 2:
				for y in range(e.top, e.g):
					grid[x + dx][y] = Tile.ROCK
		elif e.t == "tower":
			var top: int = e.g - e.th
			for dx in 3:
				for y in range(top - 1, e.g):
					grid[x + dx][y] = Tile.BRICK
			e.archer = Vector2(x + 1.5, top - 1)
	_tree(2)
	_tree(10)
	var k := 14
	while k < SEG - 2:
		if not no_tree[k] and not no_tree[k - 1] and not no_tree[k + 1] and kind[k] == K.GROUND \
				and surf[k - 1] == surf[k] and surf[k + 1] == surf[k] and rng.randf() < 0.08:
			_tree(k)
			k += 3
		k += 1


func _tree(k: int) -> void:
	var g := surf[k]
	var th := 3 + int(rng.randf() * 2)
	for y in range(g - th, g):
		grid[k][y] = Tile.TRUNK
	for dx in range(-1, 2):
		for dy in range(-2, 2):
			if absi(dx) + absf(dy + 0.5) > 2:
				continue
			var yy := g - th + dy
			if k + dx >= 0 and k + dx < grid.size() and yy >= 0 and grid[k + dx][yy] == Tile.AIR:
				grid[k + dx][yy] = Tile.LEAVES


func _atlas(t: int, x: int, y: int) -> Vector2i:
	var v := int(_hash2(x, y) * 3)
	match t:
		Tile.DIRT: return Vector2i(v, 0)
		Tile.GRASS: return Vector2i(3 + v, 0)
		Tile.ROCK: return Vector2i(6 + v, 0)
		Tile.BEDROCK: return Vector2i(9, 0)
		Tile.BRICK: return Vector2i(1 + v, 1) if y % 2 == 0 else Vector2i(v, 3)
		Tile.TRUNK: return Vector2i(4, 1)
		Tile.LEAVES: return Vector2i(5 + v, 1)
		Tile.SPIKES: return Vector2i(8, 1)
		Tile.WATER: return Vector2i(0, 2) if grid[x][y - 1] != Tile.WATER else Vector2i(9, 1)
		Tile.CRYSTAL: return Vector2i(4, 2)
	return Vector2i(-1, -1)


## Writes an inherited scene (instance of level_base.tscn) so later changes to the base reach every level.
## Godot has no script API to save inherited scenes, so the .tscn text is written directly.
func _save(_s: int, path: String) -> void:
	var terrain: TileMapLayer = (load("res://world/terrain.tscn") as PackedScene).instantiate()
	for x in grid.size():
		for y in ROWS:
			var t: int = grid[x][y]
			if t != Tile.AIR:
				terrain.set_cell(Vector2i(x, y), 0, _atlas(t, x, y))
	var lines: PackedStringArray = [
		'[gd_scene format=3]',
		'',
		'[ext_resource type="PackedScene" path="%s" id="1_base"]' % BASE,
		'[ext_resource type="PackedScene" path="%s" id="2_archer"]' % ARCHER,
		'',
		'[node name="Level%02d" instance=ExtResource("1_base")]' % level_n,
		'display_name = "Level %d"' % level_n,
		'',
		'[node name="Terrain" parent="."]',
		'tile_map_data = %s' % var_to_str(terrain.tile_map_data),
		'',
		'[node name="StartFlag" parent="."]',
		'position = %s' % var_to_str(Grid.to_px(Vector2(FLAG_OFF + 0.5, surf[FLAG_OFF]))),
		'',
		'[node name="ExitFlag" parent="."]',
		'position = %s' % var_to_str(Grid.to_px(Vector2(SEG + FLAG_OFF + 0.5, surf[SEG + FLAG_OFF]))),
	]
	terrain.free()
	var n := 0
	for e: Dictionary in extras:
		if e.t != "tower":
			continue
		n += 1
		lines.append_array([
			'',
			'[node name="Archer%d" parent="Objects" instance=ExtResource("2_archer")]' % n,
			'position = %s' % var_to_str(Grid.to_px(e.archer)),
			'reload_time = %s' % var_to_str(maxf(0.9, 2.2 - 0.12 * (level_n - 3))),
		])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("
".join(lines) + "
")
	f.close()
	print("wrote ", path, " (", n, " towers)")
