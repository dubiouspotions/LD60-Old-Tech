extends GutTest
## Player tools acting on a real level scene.

const MAP: Array = [
	"..............",
	"..............",
	"..............",
	"..............",
	"...T..........",
	"..LTL.........",
	"##############",
	"####RRR##C####",
	"BBBBBBBBBBBBBB",
]

var level: Level
var tools: ToolController


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	level.terrain.clear()
	level.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				level.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	tools = ToolController.new()
	tools.tools = GameState.campaign.tools
	tools.level = level
	tools.enabled = true
	add_child_autofree(tools)


func _select(kind: ToolDefinition.Kind, material_name: String = "") -> void:
	for i in tools.tools.size():
		var t := tools.tools[i]
		if t.kind == kind and (material_name == "" or t.bridge_material.display_name == material_name):
			tools.select(i)
			return
	fail_test("no such tool")


func _click(at: Vector2) -> void:
	tools._mouse_m = at
	tools._press()
	tools._release()


func test_dig_soil_adds_earth() -> void:
	_select(ToolDefinition.Kind.DIG)
	var earth := GameState.supplies.earth
	_click(Vector2(8.5, 6.5))
	assert_eq(GameState.supplies.earth, earth + 1)
	assert_null(level.terrain.type_at(Vector2i(8, 6)))


func test_dig_tree_adds_logs_and_rope() -> void:
	_select(ToolDefinition.Kind.DIG)
	var logs := GameState.supplies.logs
	_click(Vector2(3.5, 5.5))
	assert_eq(GameState.supplies.logs, logs + 4, "2 trunk + 2 bonus")
	assert_eq(GameState.supplies.rope, GameState.campaign.start_supplies.rope + 1, "2 leaves")


func test_fill_spends_earth_and_drops_block() -> void:
	_select(ToolDefinition.Kind.FILL)
	var earth := GameState.supplies.earth
	_click(Vector2(10.5, 1.5))
	assert_eq(GameState.supplies.earth, earth - 1)
	await wait_physics_frames(60)
	assert_eq(level.terrain.type_at(Vector2i(10, 5)), WorldFixture.type("fill"), "landed on the ground")


func test_fill_without_earth_does_nothing() -> void:
	_select(ToolDefinition.Kind.FILL)
	GameState.supplies.earth = 0
	_click(Vector2(10.5, 1.5))
	await wait_physics_frames(60)
	assert_null(level.terrain.type_at(Vector2i(10, 5)))


func test_log_build_spends_a_log() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	var logs := GameState.supplies.logs
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	assert_eq(level.bridge.members.size(), 1)
	assert_true(level.bridge.members[0].blueprint, "placed as a plan")
	assert_eq(GameState.supplies.logs, logs - 1)


func test_commit_builds_the_plan() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	assert_eq(tools.commit(), 1)
	assert_false(level.bridge.members[0].blueprint)


func test_support_tool_places_support() -> void:
	_select(ToolDefinition.Kind.BUILD, "Support")
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	assert_eq(level.bridge.members.size(), 1)
	assert_false(level.bridge.members[0].material.walkable)


func test_dig_member_refunds_it() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	var logs := GameState.supplies.logs
	_select(ToolDefinition.Kind.DIG)
	_click(Vector2(7.5, 6.05))
	assert_eq(level.bridge.members.size(), 0)
	assert_eq(GameState.supplies.logs, logs + 1)


func test_charge_blasts_rock_after_fuse() -> void:
	_select(ToolDefinition.Kind.CHARGE)
	var powder := GameState.supplies.powder
	_click(Vector2(5.5, 7.5))
	assert_eq(GameState.supplies.powder, powder - 1)
	assert_eq(level.terrain.type_at(Vector2i(5, 7)), WorldFixture.type("rock"), "fuse still burning")
	await wait_seconds(2.0)
	assert_null(level.terrain.type_at(Vector2i(5, 7)), "rock blasted")
	assert_eq(level.terrain.type_at(Vector2i(5, 8)), WorldFixture.type("bedrock"))
