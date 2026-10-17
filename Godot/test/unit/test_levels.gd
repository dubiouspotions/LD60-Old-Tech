extends GutTest
## Checks every campaign level is playable as built: catches flags in the air, archers on nothing, etc.


func _levels() -> Array:
	var out := []
	for scene: PackedScene in GameState.campaign.levels:
		var level: Level = scene.instantiate()
		add_child_autofree(level)
		out.append(level)
	return out


func test_campaign_has_levels_and_tools() -> void:
	assert_gt(GameState.campaign.levels.size(), 0)
	assert_eq(GameState.campaign.tools.size(), 6)


func test_flags_stand_on_ground() -> void:
	for level: Level in _levels():
		for flag: CheckpointFlag in [level.start_flag, level.exit_flag]:
			var foot := flag.metres()
			assert_true(level.terrain.is_solid(Grid.cell_of(foot + Vector2(0, 0.5))), "%s %s on ground" % [level.name, flag.name])
			assert_false(level.terrain.is_solid(Grid.cell_of(foot - Vector2(0, 0.5))), "%s %s not buried" % [level.name, flag.name])


func test_exit_is_right_of_start() -> void:
	for level: Level in _levels():
		assert_gt(level.exit_flag.position.x, level.start_flag.position.x, level.name)
		assert_lt(level.exit_flag.metres().x, level.terrain.size.x, "%s exit inside the level" % level.name)


func test_archers_stand_on_solid_ground() -> void:
	for level: Level in _levels():
		for o in level.objects.get_children():
			if o is Archer:
				assert_true(level.terrain.is_solid(Grid.cell_of(o.feet_m() + Vector2(0, 0.5))), "%s %s" % [level.name, o.name])


func test_army_spawns_on_ground() -> void:
	for level: Level in _levels():
		level.start(10, 1)
		assert_eq(level.army.soldiers.size(), 10, level.name)
		for s in level.army.soldiers:
			assert_true(level.terrain.is_solid(Grid.cell_of(s.pos + Vector2(0, 0.5))), level.name)
