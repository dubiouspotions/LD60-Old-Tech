extends Node
## Re-tiles every campaign level with the v2 rules (see TerrainLook) and writes the new tiles into the level
## scenes. Tiles that already fit are kept, so hand-painted variants survive a re-run. Materials without v2 art
## keep their old tiles. Runs as a scene (Terrain needs the autoloads):
##   godot --headless res://dev/convert_levels_v2.tscn
## Levels are inherited scenes, which Godot can not save from a script, so only the Terrain's tile_map_data line
## in each .tscn is replaced.


func _ready() -> void:
	for path: String in GameState.campaign.levels:
		_convert(path)
	get_tree().quit()


func _convert(path: String) -> void:
	var lv: Level = (load(path) as PackedScene).instantiate()
	var terrain: Terrain = lv.get_node("Terrain")
	terrain.rebuild()
	var before := terrain.tile_map_data
	terrain.retile_all()
	var data := terrain.tile_map_data
	lv.free()
	if data == before:
		print("convert_levels_v2: %s already up to date" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var in_terrain := false
	var done := false
	for i in lines.size():
		if lines[i].begins_with("[node "):
			in_terrain = lines[i].begins_with('[node name="Terrain"')
		elif in_terrain and lines[i].begins_with("tile_map_data = "):
			var encoded := 'PackedByteArray("%s")' % Marshalls.raw_to_base64(data) if text.begins_with("[gd_scene format=4") \
					else var_to_str(data)
			lines[i] = "tile_map_data = " + encoded
			done = true
	if not done:
		push_error("convert_levels_v2: no Terrain tile_map_data in %s" % path)
		return
	FileAccess.open(path, FileAccess.WRITE).store_string("\n".join(lines))
	print("convert_levels_v2: re-tiled %s" % path)
