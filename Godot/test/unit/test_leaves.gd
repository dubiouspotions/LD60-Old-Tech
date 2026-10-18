extends GutTest
## Felling a tree: its leaves burst outward in a poof, flutter down and are gone when they touch the ground.

const MAP: Array = [
	"..............................",
	"..............................",
	"..............................",
	"..............................",
	"..............................",
	"..............................",
	"##############################",
	"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
]

var world: World
var leaves: LeafPoof


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.terrain.clear()
	world.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	leaves = world.leaves
	leaves.set_physics_process(false)


## Trunk at column 12 (rows 3..5), a 3x2 crown of leaves (rows 1..2).
func _tree(with_leaves: bool = true) -> void:
	for y in range(3, 6):
		world.terrain.set_type(Vector2i(12, y), WorldFixture.type("trunk"))
	if with_leaves:
		for x in range(11, 14):
			for y in range(1, 3):
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type("leaves"))


func _centre() -> Vector2:
	return Vector2(12.5, 2.0)


func _spread() -> float:
	var total := 0.0
	var ps := leaves.positions()
	for p in ps:
		total += p.distance_to(_centre())
	return total / maxf(1.0, ps.size())


func test_felling_a_tree_poofs_its_leaves() -> void:
	_tree()
	world.terrain.fell(Vector2i(12, 5))
	assert_eq(leaves.count(), mini(6 * leaves.per_cell, leaves.max_leaves), "a few for each leaf cell")
	for p in leaves.positions():
		assert_between(p.x, 10.5, 14.5, "in the crown")
		assert_between(p.y, 0.5, 3.5)


func test_no_leaves_no_poof() -> void:
	_tree(false)
	world.terrain.fell(Vector2i(12, 5))
	assert_eq(leaves.count(), 0)


func test_they_burst_outward() -> void:
	_tree()
	world.terrain.fell(Vector2i(12, 5))
	var before := _spread()
	for i in 12:
		leaves.advance(1.0 / 60.0)
	assert_gt(_spread(), before + 0.2, "a poof, away from the middle of the crown")


func test_they_flutter_down_and_go_when_they_touch_the_ground() -> void:
	_tree()
	world.terrain.fell(Vector2i(12, 5))
	var lowest := 0.0
	for i in int(leaves.max_life * 60) + 2:
		leaves.advance(1.0 / 60.0)
		for p in leaves.positions():
			assert_false(world.terrain.is_solid(Grid.cell_of(p)), "never inside the ground")
			lowest = maxf(lowest, p.y)
		if leaves.count() == 0:
			break
	assert_eq(leaves.count(), 0, "all gone")
	assert_gt(lowest, 5.0, "they got down near the ground first")
