extends GutTest
## Felling a tree drops its logs as pieces of wood. The engineer who felled it picks them all up before it takes any
## other work; idle engineers nearby help. The logs count as supplies once picked up.

const MAP: Array = [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"######....####",
	"######....####",
	"######^^^^####",
	"BBBBBBBBBBBBBB",
]

var world: World


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.terrain.clear()
	world.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(4, 5.5)
	world.crew.spawn(5.5)


## Steps the crew and the wood until done() or seconds pass.
func _run(seconds: float, done: Callable = func() -> bool: return false) -> void:
	for i in int(seconds * 60):
		world.bridge.step(1.0 / 60.0)
		world.crew.step(1.0 / 60.0)
		world.wood.advance(1.0 / 60.0)
		if done.call():
			return


## A two-cell tree at column 2 on the ground (row 6), with a leaf each side.
func _tree() -> void:
	world.terrain.set_type(Vector2i(2, 5), WorldFixture.type("trunk"))
	world.terrain.set_type(Vector2i(2, 4), WorldFixture.type("trunk"))
	world.terrain.set_type(Vector2i(1, 4), WorldFixture.type("leaves"))
	world.terrain.set_type(Vector2i(3, 4), WorldFixture.type("leaves"))


func _yield_logs() -> int:
	var cells := world.terrain.tree_cells(Vector2i(2, 5))
	var counts := {}
	for c in cells:
		var t := world.terrain.type_at(c)
		counts[t] = counts.get(t, 0) + 1
	return TerrainType.bulk_total(counts).logs


func _felled() -> bool:
	return world.terrain.type_at(Vector2i(2, 5)) == null


func test_pieces_are_drawn_with_the_wood_sprite() -> void:
	assert_eq(world.wood.texture.resource_path, "res://world/wood_sprite.png")


func test_felling_drops_one_piece_per_log_and_no_logs_yet() -> void:
	_tree()
	var logs := _yield_logs()
	assert_gt(logs, 0)
	var had := GameState.supplies.logs
	world.terrain.mark(Vector2i(2, 5))
	_run(15.0, _felled)
	assert_true(_felled())
	assert_eq(world.wood.count(), logs, "one piece of wood per log")
	assert_eq(GameState.supplies.logs, had, "not in the stores until picked up")


func test_pieces_fall_and_rest_on_the_ground() -> void:
	_tree()
	world.terrain.mark(Vector2i(2, 5))
	_run(15.0, _felled)
	world.crew.set_physics_process(false)
	for i in 120:
		world.wood.advance(1.0 / 60.0)
	for p in world.wood.pieces:
		assert_true(p.resting, "landed")
		assert_true(world.terrain.is_solid(Grid.cell_of(p.pos + Vector2(0, 0.1))), "on the ground")
		assert_false(world.terrain.is_solid(Grid.cell_of(p.pos - Vector2(0, 0.1))), "not inside it")


func test_the_feller_gathers_every_piece_and_the_logs_then_count() -> void:
	_tree()
	var logs := _yield_logs()
	var had := GameState.supplies.logs
	world.terrain.mark(Vector2i(2, 5))
	_run(15.0, _felled)
	_run(20.0, func() -> bool: return world.wood.count() == 0)
	assert_eq(world.wood.count(), 0, "all picked up")
	assert_eq(GameState.supplies.logs, had + logs)


func test_the_feller_takes_no_other_work_until_its_wood_is_in() -> void:
	_tree()
	world.terrain.mark(Vector2i(2, 5))
	_run(15.0, _felled)
	var feller: Crew.Engineer = null
	for e in world.crew.engineers:
		if not e.gather.is_empty():
			feller = e
	assert_not_null(feller, "the one that felled it owns the wood")
	world.terrain.mark(Vector2i(12, 6))
	while world.wood.count() > 0 and not feller.gather.is_empty():
		assert_false(feller.digging, "not off digging elsewhere")
		assert_null(feller.job, "nor building")
		_run(1.0 / 60.0)
	assert_eq(world.wood.count(), 0)


func test_idle_engineers_nearby_help() -> void:
	# Helpers to have, whatever the campaign's crew size.
	world.crew.rules = world.crew.rules.duplicate()
	world.crew.rules.crew_size = 3
	world.crew.spawn(5.5)
	_tree()
	world.terrain.mark(Vector2i(2, 5))
	_run(15.0, _felled)
	var pickers := {}
	world.crew.picked_up.connect(func(_piece: Wood.Piece, e: Crew.Engineer) -> void: pickers[e] = true)
	_run(20.0, func() -> bool: return world.wood.count() == 0)
	assert_gt(pickers.size(), 1, "more than the feller")


func test_a_piece_out_of_reach_does_not_hold_the_feller_forever() -> void:
	_tree()
	world.terrain.mark(Vector2i(2, 5))
	_run(15.0, _felled)
	# Drop one piece into the spike pit, where no engineer may walk.
	var p: Wood.Piece = world.wood.pieces[0]
	p.pos = Vector2(7.5, 8.0)
	p.resting = true
	_run(world.crew.rules.gather_give_up + 20.0, func() -> bool: return world.wood.count() == 0)
	assert_eq(world.wood.count(), 0, "fetched in the end")


func test_the_instant_work_cheat_skips_the_gathering() -> void:
	_tree()
	var logs := _yield_logs()
	var had := GameState.supplies.logs
	world.terrain.mark(Vector2i(2, 5))
	world.crew.rules.instant_work = true
	_run(1.0 / 60.0)
	world.crew.rules.instant_work = false
	assert_eq(world.wood.count(), 0)
	assert_eq(GameState.supplies.logs, had + logs)
