extends Node
## One-time bootstrap of the designer data under res://data. Values match the original web game.
## Runs as a scene so the autoloads exist (refuses to overwrite existing files):
##   godot --headless res://dev/bootstrap_data.tscn


func _ready() -> void:
	_sounds()
	_terrain()
	_bridge()
	_army()
	_crew()
	_tools()
	_campaign()
	get_tree().quit()


func _save(res: Resource, path: String) -> void:
	if FileAccess.file_exists(path):
		print("skip existing ", path)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(res, path)
	print("wrote ", path, " ", error_string(err))


func _sfx(name: String, volume: float = 0.0, pitch: float = 0.08, bus: StringName = &"SFX") -> void:
	var s := SoundEffect.new()
	s.streams = [load("res://audio/sfx/%s.wav" % name)]
	s.volume_db = volume
	s.pitch_variation = pitch
	s.bus = bus
	_save(s, "res://data/sounds/%s.tres" % name)


func _sounds() -> void:
	for n in ["dig", "fill_land", "log_place", "rope_place", "member_snap", "charge_place", "arrow_shot", "arrow_hit",
			"soldier_hurt", "soldier_death", "tree_fell", "crystal", "collapse", "tower_down", "ui_click"]:
		_sfx(n, -4.0)
	_sfx("explosion", 0.0, 0.12)
	for n in ["checkpoint", "lost", "victory"]:
		_sfx(n, -2.0, 0.0)


func _snd(name: String) -> SoundEffect:
	return load("res://data/sounds/%s.tres" % name)


func _t(file: String, name: String, props: Dictionary) -> void:
	var t := TerrainType.new()
	t.display_name = name
	for k: String in props:
		t.set(k, props[k])
	_save(t, "res://data/terrain/%s.tres" % file)


func _terrain() -> void:
	var too_hard := "Too hard. Use a charge"
	_t("soil", "Soil", {dig_action = TerrainType.DigAction.REMOVE, dig_time = 0.8, dig_yield = Supplies.make(1),
		bulk_yield = Supplies.make(1), bulk_tiles_per_yield = 2, dig_sound = _snd("dig"), debris_color = Color("7b5131")})
	_t("fill", "Fill", {falls = true, dig_action = TerrainType.DigAction.REMOVE, dig_time = 0.6, dig_yield = Supplies.make(1),
		bulk_yield = Supplies.make(1), bulk_tiles_per_yield = 2, dig_sound = _snd("dig"), debris_color = Color("a0703f")})
	_t("rock", "Rock", {too_hard_text = too_hard, debris_color = Color("5b6472")})
	_t("bedrock", "Bedrock", {blast_proof = true, debris_color = Color("262a33")})
	_t("crystal", "Powder crystal", {dig_action = TerrainType.DigAction.REMOVE, dig_time = 1.6, dig_yield = Supplies.make(0, 0, 0, 1),
		dig_text = "+1 powder", bulk_yield = Supplies.make(0, 0, 0, 1), dig_sound = _snd("crystal"), debris_color = Color("8ff0e0")})
	_t("brick", "Brick", {anchor = false, structure = true, too_hard_text = too_hard,
		bulk_yield = Supplies.make(1), bulk_tiles_per_yield = 3, debris_color = Color("94463a")})
	_t("water", "Water", {solid = false, anchor = false, fill_replaces = true, buoyant = true, blast_proof = true,
		hazard = TerrainType.Hazard.WATER, death_text = "Drowned", ahead_text = "Water ahead", debris_color = Color("3480b6")})
	_t("spikes", "Spikes", {solid = false, anchor = false, hazard = TerrainType.Hazard.SPIKES,
		death_text = "Spiked", ahead_text = "Spikes ahead", debris_color = Color("cfd4da")})
	_t("trunk", "Tree trunk", {solid = false, anchor = false, dig_action = TerrainType.DigAction.FELL, dig_time = 2.5,
		bulk_yield = Supplies.make(0, 1), bulk_bonus = Supplies.make(0, 2), dig_sound = _snd("tree_fell"), debris_color = Color("5b3a22")})
	_t("leaves", "Leaves", {solid = false, anchor = false, fill_replaces = true, dig_action = TerrainType.DigAction.FELL, dig_time = 0.8,
		bulk_yield = Supplies.make(0, 0, 1), bulk_tiles_per_yield = 2, dig_sound = _snd("tree_fell"), debris_color = Color("3f6e34")})


func _bridge() -> void:
	var log_m := BridgeMaterial.new()
	log_m.display_name = "Log"
	log_m.cost = Supplies.make(0, 1)
	log_m.place_sound = _snd("log_place")
	log_m.break_sound = _snd("member_snap")
	_save(log_m, "res://data/bridge/log.tres")
	var rope := BridgeMaterial.new()
	rope.display_name = "Rope"
	rope.cost = Supplies.make(0, 0, 1)
	rope.no_supply_text = "No rope. Cut leaves"
	rope.max_length = 12.0
	rope.kg_per_m = 0.5
	rope.compliance = 2e-6
	rope.break_force = 11000.0
	rope.tension_only = true
	rope.walkable = false
	rope.snapped_text = "Rope snapped"
	rope.buckled_text = ""
	rope.color = Color("d9c38f")
	rope.edge_color = Color("d9c38f")
	rope.thickness = 0.07
	rope.draw_as_rope = true
	rope.place_sound = _snd("rope_place")
	rope.break_sound = _snd("member_snap")
	_save(rope, "res://data/bridge/rope.tres")
	var support := BridgeMaterial.new()
	support.display_name = "Support"
	support.cost = Supplies.make(0, 1)
	support.kg_per_m = 14.0
	support.break_force = 13000.0
	support.walkable = false
	support.snapped_text = "Support pulled apart"
	support.buckled_text = "Support buckled"
	support.color = Color(0.54, 0.38, 0.22)
	support.edge_color = Color(0.3, 0.2, 0.11)
	support.thickness = 0.13
	support.draw_layer = -1
	support.place_sound = _snd("log_place")
	support.break_sound = _snd("member_snap")
	_save(support, "res://data/bridge/support.tres")


func _army() -> void:
	var r := ArmyRules.new()
	r.death_sound = _snd("soldier_death")
	r.hurt_sound = _snd("soldier_hurt")
	_save(r, "res://data/army_rules.tres")


func _crew() -> void:
	var r := CrewRules.new()
	r.work_sound = _snd("dig")
	r.strike_sound = _snd("rope_place")
	_save(r, "res://data/crew_rules.tres")


func _tool(file: String, props: Dictionary) -> void:
	var t := ToolDefinition.new()
	for k: String in props:
		t.set(k, props[k])
	_save(t, "res://data/tools/%s.tres" % file)


func _tools() -> void:
	_tool("1_dig", {kind = ToolDefinition.Kind.DIG, display_name = "Dig", hint = "earth · trees · undo",
		action = &"tool_dig", key_label = "1", repeat_interval = 0.06})
	_tool("2_fill", {kind = ToolDefinition.Kind.FILL, display_name = "Fill", hint = "1 earth · falls",
		action = &"tool_fill", key_label = "2", repeat_interval = 0.11, cost = Supplies.make(1),
		no_supply_text = "No earth. Dig some", spawn_scene = load("res://objects/falling_block/falling_block.tscn")})
	_tool("3_log", {kind = ToolDefinition.Kind.BUILD, display_name = "Log", hint = "1 log · ≤ 5 m · push + pull",
		action = &"tool_log", key_label = "3", bridge_material = load("res://data/bridge/log.tres")})
	_tool("4_support", {kind = ToolDefinition.Kind.BUILD, display_name = "Support", hint = "1 log · ≤ 5 m · not walked on",
		action = &"tool_support", key_label = "4", bridge_material = load("res://data/bridge/support.tres")})
	_tool("5_rope", {kind = ToolDefinition.Kind.BUILD, display_name = "Rope", hint = "1 rope · ≤ 12 m · pull only",
		action = &"tool_rope", key_label = "5", bridge_material = load("res://data/bridge/rope.tres")})
	_tool("6_charge", {kind = ToolDefinition.Kind.CHARGE, display_name = "Charge", hint = "1 powder · r 2.6",
		action = &"tool_charge", key_label = "6", cost = Supplies.make(0, 0, 0, 1),
		no_supply_text = "No powder. Mine crystals", spawn_scene = load("res://objects/charge/charge.tscn")})
	_tool("7_pan", {kind = ToolDefinition.Kind.PAN, display_name = "Pan", hint = "drag the view",
		action = &"tool_pan", key_label = "7"})


func _campaign() -> void:
	var c := Campaign.new()
	var levels: Array[String] = []
	for f in DirAccess.get_files_at("res://levels"):
		if f.begins_with("level_") and f.ends_with(".tscn") and f != "level_base.tscn":
			levels.append("res://levels/" + f)
	c.levels = levels
	c.start_soldiers = 10
	c.start_supplies = Supplies.make(8, 12, 6, 2)
	c.army_rules = load("res://data/army_rules.tres")
	var tools: Array[ToolDefinition] = []
	for f in ["1_dig", "2_fill", "3_log", "4_support", "5_rope", "6_charge", "7_pan"]:
		tools.append(load("res://data/tools/%s.tres" % f))
	c.tools = tools
	c.level_up_sound = _snd("checkpoint")
	c.lost_sound = _snd("lost")
	c.victory_sound = _snd("victory")
	_save(c, "res://data/campaign.tres")
