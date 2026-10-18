extends Node
## Regrows the tall grass of every campaign level by its Grass node's Scatter and saves it, as the editor does when
## a level is edited (see Level.regrow_grass). Levels without a Scatter keep their hand-painted grass.
## Runs as a scene (the levels need the autoloads):
##   godot --headless res://dev/scatter_grass.tscn
## Levels are inherited scenes, so only the Grass node's tile_map_data is written.


func _ready() -> void:
	for path: String in GameState.campaign.levels:
		_regrow(path)
	get_tree().quit()


func _regrow(path: String) -> void:
	var lv: Level = (load(path) as PackedScene).instantiate()
	add_child(lv)
	var grass := lv.grass() as TallGrass
	if grass == null or grass.scatter == null:
		print("scatter_grass: %s has no Scatter, kept" % path)
		lv.free()
		return
	lv.regrow_grass()
	var data := Marshalls.raw_to_base64(grass.tile_map_data)
	var patches := grass.get_used_cells().size()
	lv.free()
	_write(path, data)
	print("scatter_grass: %s gets %d grass cells" % [path, patches])


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
