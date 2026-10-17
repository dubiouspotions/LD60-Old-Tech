extends SceneTree
## Draws the placeholder tile atlas (world/tiles.png) and builds world/tileset.tres from it.
## The art reproduces the original canvas drawing. Replace tiles.png with real art at any time;
## keep the atlas layout, or re-assign tiles in the TileSet editor.
##
## Two passes, because the PNG must be imported before the TileSet can reference it:
##   godot --headless -s res://dev/build_tileset.gd -- art
##   godot --headless --import
##   godot --headless -s res://dev/build_tileset.gd -- tileset

const T: int = 32
const COLS: int = 10
const ROWS: int = 4
const PNG_PATH: String = "res://world/tiles.png"
const TILESET_PATH: String = "res://world/tileset.tres"
const FRAMES: int = 4

## atlas coords -> [terrain file, animation frames]
const LAYOUT: Dictionary = {
	Vector2i(0, 0): ["soil", 1], Vector2i(1, 0): ["soil", 1], Vector2i(2, 0): ["soil", 1],
	Vector2i(3, 0): ["soil", 1], Vector2i(4, 0): ["soil", 1], Vector2i(5, 0): ["soil", 1],
	Vector2i(6, 0): ["rock", 1], Vector2i(7, 0): ["rock", 1], Vector2i(8, 0): ["rock", 1],
	Vector2i(9, 0): ["bedrock", 1],
	Vector2i(0, 1): ["fill", 1],
	Vector2i(1, 1): ["brick", 1], Vector2i(2, 1): ["brick", 1], Vector2i(3, 1): ["brick", 1],
	Vector2i(4, 1): ["trunk", 1],
	Vector2i(5, 1): ["leaves", 1], Vector2i(6, 1): ["leaves", 1], Vector2i(7, 1): ["leaves", 1],
	Vector2i(8, 1): ["spikes", 1], Vector2i(9, 1): ["water", 1],
	Vector2i(0, 2): ["water", FRAMES], Vector2i(4, 2): ["crystal", FRAMES],
	Vector2i(0, 3): ["brick", 1], Vector2i(1, 3): ["brick", 1], Vector2i(2, 3): ["brick", 1],
}

const DIRT: Array[Color] = [Color("7b5131"), Color("80553a"), Color("74492b")]
const GRASS: Array[Color] = [Color("6f9a3c"), Color("79a443"), Color("668f36")]
const ROCK: Array[Color] = [Color("5b6472"), Color("626b7a"), Color("545c69")]
const BRICK: Array[Color] = [Color("94463a"), Color("8a3f33"), Color("9c4d3f")]
const LEAVES: Array[Color] = [Color("3f6e34"), Color("4a7a3a"), Color("365f2d")]

var img: Image


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "art" in args:
		_art()
	if "tileset" in args:
		_tileset()
	quit()


func _rect(cell: Vector2i, x: float, y: float, w: float, h: float, c: Color) -> void:
	var ox := cell.x * T
	var oy := cell.y * T
	for py in range(int(round(y * T)), int(round((y + h) * T))):
		for px in range(int(round(x * T)), int(round((x + w) * T))):
			if px >= 0 and px < T and py >= 0 and py < T:
				var dst := img.get_pixel(ox + px, oy + py)
				img.set_pixel(ox + px, oy + py, dst.blend(c))


func _shape(cell: Vector2i, c: Color, inside: Callable) -> void:
	for py in T:
		for px in T:
			if inside.call((px + 0.5) / T, (py + 0.5) / T):
				var dst := img.get_pixel(cell.x * T + px, cell.y * T + py)
				img.set_pixel(cell.x * T + px, cell.y * T + py, dst.blend(c))


func _dirt(cell: Vector2i, v: int) -> void:
	_rect(cell, 0, 0, 1, 1, DIRT[v])
	if v == 1:
		_rect(cell, 0.3, 0.5, 0.18, 0.14, Color("5e3b22"))


func _brick(cell: Vector2i, v: int, odd: bool) -> void:
	_rect(cell, 0, 0, 1, 1, BRICK[v])
	var mortar := Color("5a2a22")
	_rect(cell, 0, 0.47, 1, 0.06, mortar)
	_rect(cell, 0, 0, 1, 0.04, mortar)
	var o := 0.25 if odd else 0.75
	_rect(cell, o, 0, 0.06, 0.47, mortar)
	_rect(cell, 1 - o, 0.5, 0.06, 0.5, mortar)


func _art() -> void:
	img = Image.create_empty(COLS * T, ROWS * T, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for v in 3:
		_dirt(Vector2i(v, 0), v)
		var g := Vector2i(3 + v, 0)
		_dirt(g, v)
		_rect(g, 0, 0, 1, 0.32, GRASS[v])
		_rect(g, 0.2, 0, 0.08, 0.4, GRASS[v])
		var r := Vector2i(6 + v, 0)
		_rect(r, 0, 0, 1, 1, ROCK[v])
		_rect(r, 0, 0.85, 1, 0.15, Color(0, 0, 0, 0.18))
		if v == 1:
			_rect(r, 0.55, 0.15, 0.1, 0.5, Color(0, 0, 0, 0.18))
		_brick(Vector2i(1 + v, 1), v, false)
		_brick(Vector2i(v, 3), v, true)
		var l := Vector2i(5 + v, 1)
		_shape(l, LEAVES[v], func(x: float, y: float) -> bool: return Vector2(x - 0.5, y - 0.5).length() < 0.68)
	_rect(Vector2i(9, 0), 0, 0, 1, 1, Color("262a33"))
	# fill
	var f := Vector2i(0, 1)
	_rect(f, 0, 0, 1, 1, Color("a0703f"))
	var fl := Color("7d5430")
	_shape(f, fl, func(x: float, y: float) -> bool:
		return x < 1.0 / T or y < 1.0 / T or x > 1 - 1.0 / T or y > 1 - 1.0 / T or (absf(x + y - 1.0) < 0.04 and x > 0.2 and x < 0.8))
	_rect(Vector2i(4, 1), 0.34, 0, 0.32, 1, Color("5b3a22"))
	_shape(Vector2i(8, 1), Color("cfd4da"), func(x: float, y: float) -> bool:
		var k := fmod(x * 3.0, 1.0)
		return y > 0.25 and y >= 1.0 - (1.0 - absf(k - 0.5) * 2.0) * 0.75)
	var water := Color(52 / 255.0, 128 / 255.0, 182 / 255.0, 0.82)
	_rect(Vector2i(9, 1), 0, 0, 1, 1, water)
	for fr in FRAMES:
		var phase := TAU * fr / FRAMES
		var w := Vector2i(fr, 2)
		_rect(w, 0, 0, 1, 1, water)
		_rect(w, 0, 0.08 + sin(phase) * 0.06, 1, 0.08, Color("8cc6e8"))
		var c := Vector2i(4 + fr, 2)
		_dirt(c, 0)
		_rect(c, 0.1, 0.1, 0.8, 0.8, Color(143 / 255.0, 240 / 255.0, 224 / 255.0, 0.25 + 0.15 * sin(phase)))
		_shape(c, Color("8ff0e0"), func(x: float, y: float) -> bool: return absf(x - 0.5) / 0.28 + absf(y - 0.5) / 0.35 <= 1.0)
	img.save_png(ProjectSettings.globalize_path(PNG_PATH))
	print("wrote ", PNG_PATH)


func _tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "terrain")
	ts.set_custom_data_layer_type(0, TYPE_OBJECT)
	var src := TileSetAtlasSource.new()
	src.texture = load(PNG_PATH)
	src.texture_region_size = Vector2i(T, T)
	ts.add_source(src, 0)
	for coords: Vector2i in LAYOUT:
		var entry: Array = LAYOUT[coords]
		src.create_tile(coords)
		var frames: int = entry[1]
		if frames > 1:
			src.set_tile_animation_frames_count(coords, frames)
			for i in frames:
				src.set_tile_animation_frame_duration(coords, i, 0.22)
		var data := src.get_tile_data(coords, 0)
		data.set_custom_data("terrain", load("res://data/terrain/%s.tres" % entry[0]))
	print("wrote ", TILESET_PATH, " ", error_string(ResourceSaver.save(ts, TILESET_PATH)))
