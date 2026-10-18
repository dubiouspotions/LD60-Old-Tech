extends Node
## Builds the v2 terrain tiles from the artist's sheet. Runs as a scene, so files are saved with their UIDs the way
## the editor writes them. Two passes, because the keyed PNG must be imported before the TileSet can use it:
##   godot --headless res://dev/build_tiles_v2.tscn -- art       (sheet -> world/tiles_v2_keyed.png, sky transparent)
##   godot --headless --import
##   godot --headless res://dev/build_tiles_v2.tscn -- tileset   (adds/replaces the v2 source in world/tileset.tres)
## The tileset pass creates one tile per coordinate listed in data/terrain_look.tres and tags it with its material:
## grass/dirt tiles get one alternative per dirt or rock material, so painting one sets that material.
## Re-run both passes after changing the sheet or the roles.

const LOOK_PATH: String = "res://data/terrain_look.tres"
const SOURCE_PNG: String = "res://world/tiles_v2.png"
const KEYED_PNG: String = "res://world/tiles_v2_keyed.png"
const TILESET_PATH: String = "res://world/tileset.tres"
## The TileSet custom data layer that holds each tile's TerrainType (see Terrain).
const CUSTOM_DATA: String = "terrain"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "art" in args:
		_art()
	elif "tileset" in args:
		_tileset()
	else:
		push_error("build_tiles_v2: pass 'art' or 'tileset'")
	get_tree().quit()


func _art() -> void:
	var sky := Color("64988e")
	var look := ResourceLoader.load(LOOK_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainLook
	if look:
		sky = look.sky_key
	var img := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_PNG))
	img.convert(Image.FORMAT_RGBA8)
	var keyed := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(sky):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				keyed += 1
	img.save_png(ProjectSettings.globalize_path(KEYED_PNG))
	print("build_tiles_v2: wrote %s (%d sky pixels made transparent)" % [KEYED_PNG, keyed])


func _tileset() -> void:
	var look: TerrainLook = load(LOOK_PATH)
	var ts: TileSet = load(TILESET_PATH)
	if ts.has_source(look.source_id):
		ts.remove_source(look.source_id)
	var src := TileSetAtlasSource.new()
	src.texture = look.texture
	src.texture_region_size = Vector2i.ONE * look.tile_size
	ts.add_source(src, look.source_id)
	var tiles := 0
	for role in TerrainLook.CELL_ROLES:
		for coords: Vector2i in look.get(role):
			if src.has_tile(coords):
				push_error("build_tiles_v2: %s is listed in more than one role" % coords)
				continue
			src.create_tile(coords)
			tiles += 1
			var mats := look.materials(role)
			for i in mats.size():
				var alt := 0 if i == 0 else src.create_alternative_tile(coords)
				if mats[i] != null:
					src.get_tile_data(coords, alt).set_custom_data(CUSTOM_DATA, mats[i])
	var own_uid := _uid_in_header(TILESET_PATH)
	var err := ResourceSaver.save(ts, TILESET_PATH)
	_restore_uids(TILESET_PATH, own_uid)
	print("build_tiles_v2: %d tiles in source %d of %s (%s)" % [tiles, look.source_id, TILESET_PATH, error_string(err)])


## Saving outside the editor drops UIDs. Puts back the file's own UID and the UID on every ext_resource, as the
## editor writes them, so the file does not churn when someone opens and saves it in the editor.
func _restore_uids(path: String, own_uid: String) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var line := lines[i]
		if i == 0 and not own_uid.is_empty() and not line.contains("uid="):
			lines[i] = line.trim_suffix("]") + ' uid="%s"]' % own_uid
		elif line.begins_with("[ext_resource") and not line.contains("uid="):
			var ref := line.get_slice('path="', 1).get_slice('"', 0)
			var uid := _uid_of(ref)
			if not uid.is_empty():
				lines[i] = line.replace(' path="', ' uid="%s" path="' % uid)
	FileAccess.open(path, FileAccess.WRITE).store_string("\n".join(lines))


## The UID of a resource file: from its .import file for imported assets, else from its header.
func _uid_of(path: String) -> String:
	if FileAccess.file_exists(path + ".import"):
		for line in FileAccess.get_file_as_string(path + ".import").split("\n"):
			if line.begins_with("uid="):
				return line.get_slice('"', 1)
		return ""
	return _uid_in_header(path)


func _uid_in_header(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var head := FileAccess.get_file_as_string(path).get_slice("\n", 0)
	return head.get_slice('uid="', 1).get_slice('"', 0) if head.contains('uid="') else ""

