extends GutTest
## Checks every campaign level is playable as built: catches flags in the air, archers on nothing, bad seams.


func _levels() -> Array:
	var out := []
	for path: String in GameState.campaign.levels:
		var level: Level = load(path).instantiate()
		add_child_autofree(level)
		out.append(level)
	return out


func test_campaign_has_levels_and_tools() -> void:
	assert_gt(GameState.campaign.levels.size(), 0)
	assert_eq(GameState.campaign.tools.size(), 5)


func test_flags_stand_on_ground() -> void:
	for level: Level in _levels():
		for flag: CheckpointFlag in [level.start_flag(), level.exit_flag()]:
			var foot := flag.metres()
			assert_true(level.terrain().is_solid(Grid.cell_of(foot + Vector2(0, 0.5))), "%s %s on ground" % [level.name, flag.name])
			assert_false(level.terrain().is_solid(Grid.cell_of(foot - Vector2(0, 0.5))), "%s %s not buried" % [level.name, flag.name])


func test_exit_is_right_of_start() -> void:
	for level: Level in _levels():
		assert_gt(level.exit_flag().position.x, level.start_flag().position.x, level.name)
		assert_lt(level.exit_flag().metres().x, level.terrain().size.x, "%s exit inside the level" % level.name)


func test_archers_stand_on_solid_ground() -> void:
	for level: Level in _levels():
		for o in level.objects().get_children():
			if o is Archer:
				assert_true(level.terrain().is_solid(Grid.cell_of(o.feet_m() + Vector2(0, 0.5))), "%s %s" % [level.name, o.name])


func test_signs_stand_clear_of_the_ground() -> void:
	for level: Level in _levels():
		for o in level.objects().get_children():
			if o is Sign:
				var board := Grid.to_m((o as Sign).position)
				assert_false(level.terrain().is_solid(Grid.cell_of(board - Vector2(0, 0.25))), "%s %s not buried" % [level.name, o.name])


func test_levels_stitch_into_one_walkable_world() -> void:
	GameState.new_campaign()
	var world: World = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.begin(0, 10)
	for s in world.army.soldiers:
		assert_true(world.terrain.is_solid(Grid.cell_of(s.pos + Vector2(0, 0.5))), "spawned on ground")
	for i in range(1, GameState.campaign.levels.size()):
		var c := world.place_now(i)
		var t := world.terrain
		assert_lte(absi(t.surface_row(c.seam) - t.surface_row(c.seam - 1)), 1, "seam into level %d is walkable" % (i + 1))
		assert_false(t.is_solid(Grid.cell_of(c.start_flag.metres() - Vector2(0, 0.5))), "camp %d not buried" % (i + 1))


## Tall grass stands in the air on top of the ground.
func test_tall_grass_stands_on_ground() -> void:
	for level: Level in _levels():
		for cell in level.grass().get_used_cells():
			assert_false(level.terrain().is_solid(cell), "%s grass at %s not buried" % [level.name, cell])
			assert_true(level.terrain().is_solid(cell + Vector2i.DOWN), "%s grass at %s on ground" % [level.name, cell])


## The game finds archers (to fight, and for the "under fire" status) only under Objects.
func test_archers_are_under_objects() -> void:
	for level: Level in _levels():
		for o in level.find_children("*", "Node2D", true, false):
			if o is Archer:
				assert_eq(o.get_parent(), level.objects(), "%s %s belongs under Objects" % [level.name, o.name])


## The campaign ground (dirt and rock) is painted with the v2 tiles. Water and spikes may use either art.
func test_levels_use_the_v2_tiles() -> void:
	var look: TerrainLook = load("res://data/terrain_look.tres")
	var drawn := look.dirt_types + look.rock_types
	for path: String in GameState.campaign.levels:
		var lv: Level = load(path).instantiate()
		var t: Terrain = lv.get_node("Terrain")
		var old := 0
		for cell in t.get_used_cells():
			if t.painted_type(cell) in drawn and t.get_cell_source_id(cell) != look.source_id:
				old += 1
		assert_eq(old, 0, "%s cells still painted with old tiles" % path)
		lv.free()

