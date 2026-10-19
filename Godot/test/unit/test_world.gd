extends GutTest
## The stitched world: levels stream in ahead, unload behind, and the column camps at every level start.

var world: World


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.set_process(false)


func _run(seconds: float) -> void:
	for i in int(seconds * 60):
		world._physics_process(1.0 / 60.0)


func test_begin_places_first_level_and_camps() -> void:
	world.begin(0, 5)
	var c0 := world.chunk(0)
	assert_not_null(c0)
	assert_eq(world.current, 0)
	assert_eq(world.army.soldiers.size(), 5)
	assert_almost_eq(world.army.lead().pos.x, c0.start_flag.metres().x, 0.01)
	assert_eq(world.crew.engineers.size(), world.crew.rules.crew_size)
	assert_true(world.camping(), "camped until the march is ordered")
	assert_not_null(world.camp(), "camp pitched")
	_run(world.dusk_time)
	assert_true(world.army.lead().sleeping, "asleep by nightfall")


func test_next_level_stitches_onto_the_exit_flag() -> void:
	world.begin(0, 3)
	var c0 := world.chunk(0)
	var c1 := world.place_now(1)
	assert_eq(c1.seam, floori(c0.exit_flag.metres().x))
	assert_eq(c1.start_flag, c0.exit_flag, "one flag marks both")
	var t := world.terrain
	assert_lte(absi(t.surface_row(c1.seam) - t.surface_row(c1.seam - 1)), 1, "walkable seam")
	assert_gt(t.size.x, c1.seam + 100)
	assert_eq(c1.exit_flag.label, "L3")


func test_archers_move_with_their_level() -> void:
	world.begin(0, 3)
	for i in range(1, 5):
		world.place_now(i)
	var archers := world.objects.get_children().filter(func(o: Node) -> bool: return o is Archer)
	assert_gt(archers.size(), 0, "level 5 has a tower")
	for a: Archer in archers:
		assert_true(world.terrain.is_solid(Grid.cell_of(a.feet_m() + Vector2(0, 0.5))), "%s on its tower" % a.name)


func test_streams_next_level_in_the_background() -> void:
	world.begin(0, 3)
	world.request(1)
	world.set_process(true)
	await wait_until(func() -> bool: return world.chunk(1) != null, 5.0)
	assert_not_null(world.chunk(1))


func test_unload_drops_the_level_behind() -> void:
	world.begin(0, 3)
	var c1 := world.place_now(1)
	world.unload(0)
	assert_null(world.chunk(0))
	assert_eq(world.terrain.min_x, c1.seam)
	assert_eq(world.terrain.type_at(Vector2i(c1.seam - 3, 30)), world.terrain.out_of_bounds)
	assert_true(is_instance_valid(c1.start_flag), "camp flag of the next level kept")


## Restarting from a checkpoint whose level behind was already unloaded puts that level back, as on arrival: the
## column camps on the ground behind its flag and the view can pan back over it.
func test_restarting_at_a_checkpoint_puts_the_level_behind_back() -> void:
	world.begin(0, 3)
	var c1 := world.place_now(1)
	world.unload(0)
	world.begin(1, 8)
	assert_not_null(world.chunk(0), "the level behind is back")
	c1 = world.chunk(1)
	var flag := c1.start_flag.metres().x
	assert_lt(world.terrain.min_x, floori(flag) - 10, "ground behind the camp flag")
	for s in world.army.soldiers:
		assert_lt(s.pos.x, flag + 0.01, "behind the flag")
		assert_false(world.terrain.type_at(Grid.cell_of(s.pos + Vector2(0, 0.5))) == world.terrain.out_of_bounds,
				"%s stands on the level's ground, not the edge of the world" % s.pos)
		assert_almost_eq(s.pos.y, float(world.terrain.surface_row(floori(s.pos.x))), 0.01, "on its surface")
		assert_gt(s.pos.y, 1.0, "not up in the sky")


func test_column_arrives_and_camps_at_the_next_level() -> void:
	world.begin(0, 3)
	world.march()
	var c1 := world.place_now(1)
	c1.level.reinforcements = 2
	var x := c1.start_flag.metres().x
	world.army.spawn(3, x + 0.05)
	watch_signals(world)
	_run(0.1)
	assert_signal_emitted(world, "camp_made")
	var joined: int = get_signal_parameters(world, "camp_made")[1]
	assert_eq(joined, 2, "the level's own reinforcements")
	assert_eq(world.current, 1)
	assert_eq(GameState.level_index, 1)
	assert_eq(world.army.soldiers.size(), 3 + joined, "reinforcements join the camp")
	assert_true(world.camping())
	_run(world.dusk_time + 2.0)
	assert_true(world.army.soldiers.all(func(s: Soldier) -> bool: return s.sleeping), "everyone joined the camp")


func test_camp_sleeps_while_engineers_work() -> void:
	world.begin(0, 3)
	var lead := world.army.lead()
	var x := lead.pos.x
	var cell := Vector2i(floori(x) + 3, world.terrain.surface_row(floori(x) + 3))
	world.terrain.mark(cell)
	_run(15.0)
	assert_eq(lead.pos.x, x, "the column sleeps")
	assert_null(world.terrain.type_at(cell), "the engineers dug through the night")


func test_march_breaks_camp() -> void:
	world.begin(0, 3)
	watch_signals(world)
	world.march()
	assert_false(world.camping())
	assert_false(world.army.lead().sleeping, "up at first light")
	assert_signal_emitted_with_parameters(world, "night_changed", [false, world.morning_time])
	assert_signal_emitted_with_parameters(world, "march_ordered", [true])
	var x := world.army.lead().pos.x
	_run(world.morning_time * 0.5)
	assert_eq(world.army.lead().pos.x, x, "the morning is for breaking camp")
	_run(world.morning_time * 0.5 + 1.0)
	assert_gt(world.army.lead().pos.x, x, "then the march")


func test_king_ends_the_night() -> void:
	world.begin(0, 3)
	world.start_at(world.chunk(0).start_flag.metres().x, 3, 1.0)
	watch_signals(world)
	_run(1.5)
	assert_false(world.camping())
	assert_signal_emitted_with_parameters(world, "march_ordered", [false])


func test_rewind_restores_the_level_and_clears_work_beyond() -> void:
	world.begin(0, 3)
	var c1 := world.place_now(1)
	var x := c1.seam + 20
	var cell := Vector2i(x, world.terrain.surface_row(x))
	world.terrain.set_type(cell, null)
	var b := world.bridge
	b.build(b.snap_point(Vector2(x, cell.y)), b.snap_point(Vector2(x + 3, cell.y)), preload("res://data/bridge/log.tres"))
	world.rewind(1)
	assert_not_null(world.terrain.type_at(cell), "ground restored")
	assert_eq(b.members.size(), 0, "bridges past the checkpoint removed")
	assert_eq(world.chunk(1).seam, c1.seam, "same place as before")


func test_last_exit_wins() -> void:
	var last := GameState.campaign.levels.size() - 1
	world.begin(last, 3)
	world.march()
	world.army.spawn(1, world.chunk(last).exit_flag.metres().x + 0.05)
	watch_signals(world)
	_run(0.1)
	assert_signal_emitted(world, "victory")


func test_archers_hold_fire_while_the_column_sleeps() -> void:
	world.begin(0, 3)
	var x := world.army.lead().pos.x
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(x + 4, world.terrain.surface_row(floori(x) + 4)))
	archer.first_shot_delay = 0.0
	world.objects.add_child(archer)
	var shots := [0]
	world.objects.child_entered_tree.connect(func(n: Node) -> void: shots[0] += int(n is Arrow))
	await wait_physics_frames(90)
	assert_eq(shots[0], 0, "no arrows at night")
	world.march()
	_run(world.morning_time + 0.1)
	await wait_physics_frames(30)
	assert_gt(shots[0], 0, "shoots by day")


func test_falling_block_looks_like_its_tile() -> void:
	world.begin(0, 3)
	var box := load("res://data/terrain/box.tres") as TerrainType
	var block: FallingBlock = world.falling_block_scene.instantiate()
	block.type = box
	world.objects.add_child(block)
	var sprite: Sprite2D = block.get_node("Sprite")
	assert_eq((sprite.texture as AtlasTexture).region, (world.terrain.tile_texture(box) as AtlasTexture).region)
	assert_eq((sprite.texture as AtlasTexture).atlas, (world.terrain.tile_texture(box) as AtlasTexture).atlas)


func test_soldiers_cost_two_gold_and_engineers_five() -> void:
	assert_eq(world.army.rules.recruit_cost.gold, 2)
	assert_eq(world.crew.rules.hire_cost.gold, 5)


func test_the_shoppe_hangs_under_the_camp() -> void:
	world.begin(0, 3)
	var camp: Camp = world.camp()
	assert_gt(camp.button_spot().y, camp.global_position.y, "below the camp's ground, not above the tents")


## The Camp Shoppe button hangs one tile (Tiles Below Tents) below the bottom of the lowest tent.
func test_the_shoppe_hangs_a_tile_below_the_lowest_tent() -> void:
	world.begin(0, 3)
	_run(world.dusk_time)
	var camp: Camp = world.camp()
	var asleep := world.army.soldiers.filter(func(s: Soldier) -> bool: return s.sleeping)
	assert_gt(asleep.size(), 0, "the column sleeps in its tents")
	var lowest := -INF
	for s: Soldier in asleep:
		var tent: Sprite2D = s.get_node("Asleep/Tent")
		lowest = maxf(lowest, (tent.global_transform * Vector2(0, tent.get_rect().end.y)).y)
	assert_eq(camp.tiles_below_tents, 1.0)
	assert_almost_eq(world.shop_spot().y, lowest + Grid.PX, 0.5)
	assert_almost_eq(world.shop_spot().x, camp.button_spot().x, 0.5, "across, where the camp says")


## The Camp Shoppe opens only once a tent is up, and only on levels that have it.
func test_the_shoppe_opens_once_a_tent_is_up() -> void:
	world.begin(1, 3)
	assert_true(world.chunk(1).level.camp_shoppe, "levels have it by default")
	assert_true(world.camping())
	assert_false(world.army.soldiers.any(func(s: Soldier) -> bool: return s.sleeping))
	assert_false(world.shop_open(), "no tent yet")
	_run(world.dusk_time)
	assert_true(world.shop_open(), "open once the tents are up")
	world.chunk(1).level.camp_shoppe = false
	assert_false(world.shop_open(), "a level can keep it closed")


func test_hire_an_engineer_at_camp() -> void:
	world.begin(0, 3)
	var crew := world.crew.engineers.size()
	var cost: Supplies = world.crew.rules.hire_cost
	GameState.supplies.gold = cost.gold * 2
	assert_true(world.hire_engineer())
	assert_eq(world.crew.engineers.size(), crew + 1)
	assert_eq(GameState.supplies.gold, cost.gold)
	var e: Crew.Engineer = world.crew.engineers[-1]
	assert_true(world.terrain.is_solid(Grid.cell_of(e.pos + Vector2(0, 0.5))), "on the ground")
	assert_almost_eq(e.pos.x, world.camp().position.x / Grid.PX, 4.0, "at the camp")


## Engineers hired are kept like soldiers: a restart from the checkpoint brings back the crew it had on arrival.
func test_a_restart_brings_back_the_crew_it_had_at_the_checkpoint() -> void:
	world.begin(0, 3)
	var start := world.crew.engineers.size()
	assert_eq(GameState.engineers, start, "the crew's size is kept")
	GameState.supplies.gold = world.crew.rules.hire_cost.gold * 3
	world.hire_engineer()
	world.hire_engineer()
	assert_eq(GameState.engineers, start + 2)
	GameState.arrive(1, 0, Supplies.new())
	world.hire_engineer()
	assert_eq(GameState.engineers, start + 3)
	GameState.retry()
	assert_eq(GameState.engineers, start + 2, "as it was on arrival")
	world.begin(1, GameState.soldiers, GameState.engineers)
	assert_eq(world.crew.engineers.size(), start + 2, "the restart brings them back")
	GameState.new_campaign()
	world.begin(0, 3, GameState.engineers)
	assert_eq(world.crew.engineers.size(), start, "a new campaign starts with the crew's own size")


## A restart puts everything back as it was when the checkpoint was first reached: whatever was dug, marked,
## built, bought, spent, gained or lost during the night and the day after is undone.
func test_a_restart_undoes_the_whole_night_and_day() -> void:
	world.begin(0, 3)
	world.place_now(1)
	GameState.supplies = Supplies.make(10, 10, 10, 20, 10)
	GameState.arrive(1, 0, Supplies.new())
	world.begin(1, GameState.soldiers, GameState.engineers)
	var had := GameState.supplies.copy()
	var soldiers := world.army.soldiers.size()
	var crew := world.crew.engineers.size()
	var flag := world.chunk(1).start_flag.metres()
	var x := floori(flag.x) + 4
	var top := Vector2i(x, world.terrain.surface_row(x))
	var ground: TerrainType = world.terrain.type_at(top)
	var below := top + Vector2i.DOWN
	# The night's work.
	world.recruit()
	world.hire_engineer()
	GameState.spend(Supplies.make(3, 3))
	world.terrain.set_type(top, null)
	world.terrain.mark(below)
	var bridge := world.bridge
	bridge.build(bridge.snap_point(flag + Vector2(1, -1)), bridge.snap_point(flag + Vector2(3, -1)), load("res://data/bridge/log.tres"))
	world.crew.order_throw(top + Vector2i(2, -1), GameState.campaign.tools[0])
	assert_eq(world.army.soldiers.size(), soldiers + 1, "a soldier bought")
	assert_eq(world.crew.engineers.size(), crew + 1, "an engineer bought")
	assert_true(world.terrain.is_marked(below), "a cell marked")
	assert_ne(GameState.supplies.describe_cost(), had.describe_cost(), "supplies spent")
	# The day's work, after the march: a soldier lost, supplies found, more dug and built, the next level in.
	world.march()
	assert_false(world.camping(), "on the march")
	world.army.kill(world.army.soldiers[0], "")
	world.army.step(1.0 / 60.0)
	assert_eq(world.army.soldiers.size(), soldiers, "the one bought, then one lost")
	GameState.gain(Supplies.make(0, 0, 0, 5))
	var day_cell := top + Vector2i(6, 0)
	var day_ground: TerrainType = world.terrain.type_at(day_cell)
	world.terrain.set_type(day_cell, null)
	bridge.build(bridge.snap_point(flag + Vector2(6, -1)), bridge.snap_point(flag + Vector2(8, -1)), load("res://data/bridge/log.tres"))
	world.place_now(2)
	# Restart from the checkpoint.
	GameState.retry()
	world.begin(1, GameState.soldiers, GameState.engineers)
	assert_eq(GameState.supplies.describe_cost(), had.describe_cost(), "supplies as on arrival")
	assert_eq(world.army.soldiers.size(), soldiers, "soldiers as on arrival")
	assert_eq(world.crew.engineers.size(), crew, "engineers as on arrival")
	assert_eq(world.terrain.type_at(top), ground, "dug ground back")
	assert_eq(world.terrain.type_at(day_cell), day_ground, "and what was dug by day")
	assert_true(world.camping(), "camped at the checkpoint again")
	assert_false(world.terrain.is_marked(below), "marks gone")
	assert_eq(bridge.members.filter(func(m: Bridge.Member) -> bool: return maxf(m.a.pos.x, m.b.pos.x) > flag.x).size(), 0, "nothing built past the flag")
	assert_eq(world.crew.throws.size(), 0, "no throws waiting")


## Soldiers joining at a checkpoint: the campaign's Checkpoint Reinforcements (none), unless the level sets its own.
func test_reinforcements_at_a_checkpoint_come_from_the_campaign_unless_the_level_says() -> void:
	assert_eq(GameState.campaign.checkpoint_reinforcements, 0, "none by default")
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	assert_eq(level.reinforcements, -1, "levels use the campaign's")
	assert_eq(level.joining(), 0)
	level.reinforcements = 4
	assert_eq(level.joining(), 4, "a level's own wins")
	level.free()
	world.begin(0, 3)
	world.skip_level()
	assert_eq(world.army.soldiers.size(), 3 + world.chunk(1).level.joining(), "arrived with them")


## A soldier recruited at camp turns up at the camp flag and walks back to the end of the camp line to sleep, without
## taking the leader's place on the way.
func test_a_recruit_turns_up_at_the_camp_flag_and_walks_to_the_end_of_the_line() -> void:
	world.begin(0, 3)
	_run(world.dusk_time + 2.0)
	var flag := world.army.camp_x
	var lead := world.army.lead()
	var rear_x := world.army.rear().pos.x
	GameState.supplies.gold = world.army.rules.recruit_cost.gold
	assert_true(world.recruit())
	var recruit: Soldier = world.army.soldiers.filter(func(s: Soldier) -> bool: return not s.sleeping)[0]
	assert_almost_eq(recruit.pos.x, flag, 0.5, "turns up at the flag")
	_run(0.1)
	assert_eq(world.army.lead(), lead, "the leader stays the leader")
	assert_eq(world.army.rear(), recruit, "counted at the end of the line")
	_run(8.0)
	assert_lt(recruit.pos.x, rear_x, "walked back past the old end of the line")
	assert_true(recruit.sleeping, "and lay down there")


func test_no_hiring_by_day_without_gold_or_past_the_crew_limit() -> void:
	world.begin(0, 3)
	var crew := world.crew.engineers.size()
	GameState.supplies.gold = world.crew.rules.hire_cost.gold - 1
	assert_false(world.hire_engineer(), "short of gold")
	GameState.supplies.gold = 100
	for i in world.crew.rules.max_crew:
		world.hire_engineer()
	assert_eq(world.crew.engineers.size(), world.crew.rules.max_crew, "up to the limit")
	assert_false(world.hire_engineer(), "past the limit")
	world.march()
	_run(world.morning_time + 0.1)
	world.crew.engineers.resize(crew)
	assert_false(world.hire_engineer(), "not by day")


func test_recruit_at_camp_spends_gold_and_joins_the_camp() -> void:
	world.begin(0, 3)
	var cost: Supplies = world.army.rules.recruit_cost
	GameState.supplies.gold = cost.gold * 2
	assert_true(world.recruit())
	assert_eq(world.army.soldiers.size(), 4)
	assert_eq(GameState.supplies.gold, cost.gold)
	assert_eq(GameState.soldiers, 4)
	_run(world.dusk_time + 3.0)
	assert_true(world.army.soldiers.all(func(s: Soldier) -> bool: return s.sleeping), "the recruit sleeps in camp")


func test_no_recruiting_by_day() -> void:
	world.begin(0, 3)
	GameState.supplies.gold = 100
	world.march()
	_run(world.morning_time + 0.1)
	assert_false(world.recruit())
	assert_eq(world.army.soldiers.size(), 3)
	assert_eq(GameState.supplies.gold, 100)


func test_no_recruiting_without_gold() -> void:
	world.begin(0, 3)
	GameState.supplies.gold = world.army.rules.recruit_cost.gold - 1
	assert_false(world.recruit())
	assert_eq(world.army.soldiers.size(), 3)


func test_no_recruiting_past_the_army_limit() -> void:
	world.begin(0, world.army.rules.max_soldiers)
	GameState.supplies.gold = 100
	assert_false(world.recruit())
	assert_eq(GameState.supplies.gold, 100)


func test_camp_marks_where_its_buttons_go() -> void:
	world.begin(0, 3)
	var camp: Camp = world.camp()
	var spot: Marker2D = camp.get_node("%ButtonSpot")
	assert_eq(camp.button_spot(), camp.global_position + spot.position)
	assert_gt(spot.position.y, 0.0, "under the camp, where the Camp Shoppe hangs")


func test_level_ends_only_when_every_soldier_has_arrived() -> void:
	world.begin(0, 3)
	world.march()
	_run(world.morning_time + 0.1)
	world.place_now(1)
	var exit_x := world.chunk(0).exit_flag.metres().x
	world.army.spawn(3, exit_x - 2.0)
	var straggler: Soldier = world.army.rear()
	straggler.pos.x = exit_x - 12.0
	straggler.pos.y = world.terrain.surface_row(floori(straggler.pos.x))
	_run(4.0)
	assert_eq(world.current, 0, "still waiting for the straggler")
	assert_lt(world.army.lead().pos.x, exit_x + 0.1, "the front waits at the flag")
	assert_eq(world.army.halt_reason, world.army.rules.gather_text)
	_run(12.0)
	assert_eq(world.current, 1, "level ends once everyone is in")


func test_archers_ignore_engineers() -> void:
	world.begin(0, 3)
	world.march()
	_run(world.morning_time + 0.1)
	var x := world.army.lead().pos.x
	for s in world.army.soldiers:
		s.pos.x = x - 40.0
	for e in world.crew.engineers:
		e.pos = Vector2(x, world.terrain.surface_row(floori(x)))
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(x + 4, world.terrain.surface_row(floori(x) + 4)))
	archer.first_shot_delay = 0.0
	world.objects.add_child(archer)
	var shots := [0]  # an array, so the lambda can write to it
	world.objects.child_entered_tree.connect(func(n: Node) -> void: shots[0] += int(n is Arrow))
	await wait_physics_frames(60)
	assert_eq(shots[0], 0, "engineers in range draw no fire")
	assert_false(archer.engaging)
	world.army.lead().pos.x = x
	await wait_physics_frames(30)
	assert_gt(shots[0], 0, "a soldier in range does")

