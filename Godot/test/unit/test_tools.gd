extends GutTest
## Player tools acting on a real world.

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

var world: World
var tools: ToolController


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	# Enough to build with, whatever the campaign starts with.
	GameState.supplies = Supplies.new()
	GameState.supplies.earth = 8
	GameState.supplies.logs = 12
	GameState.supplies.rope = 6
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.terrain.clear()
	world.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	tools = ToolController.new()
	tools.tools = GameState.campaign.tools
	tools.world = world
	tools.enabled = true
	add_child_autofree(tools)


## Selects the tool of kind (and, for a build tool, switches it to the material of that name).
func _select(kind: ToolDefinition.Kind, material_name: String = "") -> void:
	for i in tools.tools.size():
		var t := tools.tools[i]
		if t.kind != kind:
			continue
		if material_name == "":
			tools.select(i)
			return
		for m in t.materials():
			if m.display_name == material_name:
				tools.select(i)
				tools.pick_material(m)
				return
	fail_test("no such tool")


func _click(at: Vector2) -> void:
	tools._mouse_m = at
	tools._press()
	tools._release()


func test_dig_marks_soil_for_the_engineers() -> void:
	_select(ToolDefinition.Kind.DIG)
	var earth := GameState.supplies.earth
	_click(Vector2(8.5, 6.5))
	assert_true(world.terrain.is_marked(Vector2i(8, 6)))
	assert_eq(world.terrain.type_at(Vector2i(8, 6)), WorldFixture.type("soil"), "not dug yet")
	assert_eq(GameState.supplies.earth, earth, "nothing gained yet")


func test_dig_marked_cell_again_unmarks() -> void:
	_select(ToolDefinition.Kind.DIG)
	_click(Vector2(8.5, 6.5))
	_click(Vector2(8.5, 6.5))
	assert_false(world.terrain.is_marked(Vector2i(8, 6)))


func test_dig_marks_rock() -> void:
	_select(ToolDefinition.Kind.DIG)
	_click(Vector2(5.5, 7.5))
	assert_true(world.terrain.is_marked(Vector2i(5, 7)))


func test_dig_does_not_mark_bedrock() -> void:
	_select(ToolDefinition.Kind.DIG)
	_click(Vector2(5.5, 8.5))
	assert_false(world.terrain.is_marked(Vector2i(5, 8)))


func test_dig_marks_tree() -> void:
	_select(ToolDefinition.Kind.DIG)
	_click(Vector2(3.5, 5.5))
	assert_true(world.terrain.is_marked(Vector2i(3, 5)))
	assert_eq(world.terrain.type_at(Vector2i(3, 5)), WorldFixture.type("trunk"))


func test_box_spends_five_logs_and_drops_a_box() -> void:
	_select(ToolDefinition.Kind.FILL)
	assert_eq(tools.tool().display_name, "Box")
	GameState.supplies.logs = 7
	var earth := GameState.supplies.earth
	_click(Vector2(10.5, 1.5))
	assert_eq(GameState.supplies.logs, 2, "five logs")
	assert_eq(GameState.supplies.earth, earth, "no earth")
	await wait_physics_frames(60)
	assert_eq(world.terrain.type_at(Vector2i(10, 5)), WorldFixture.type("fill"), "landed on the ground")
	assert_eq(world.terrain.type_at(Vector2i(10, 5)).display_name, "Box")


func test_box_without_five_logs_does_nothing() -> void:
	_select(ToolDefinition.Kind.FILL)
	GameState.supplies.logs = 4
	_click(Vector2(10.5, 1.5))
	await wait_physics_frames(60)
	assert_null(world.terrain.type_at(Vector2i(10, 5)))


func test_two_clicks_place_one_plank_and_stop() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_click(Vector2(6, 6))
	assert_eq(world.bridge.members.size(), 0, "a click only starts the plank")
	_click(Vector2(9, 6))
	assert_eq(world.bridge.members.size(), 1, "the second click places the end")
	assert_eq(world.bridge.members[0].b.pos, Vector2(9, 6))
	assert_null(tools.preview_from(), "and that is it")
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 1, "the next click starts a new plank")


func test_shift_on_a_click_carries_on_from_its_end() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_click(Vector2(6, 6))
	tools.chain = true
	_click(Vector2(9, 6))
	assert_eq(world.bridge.members.size(), 1)
	assert_eq(tools.preview_from().pos, Vector2(9, 6), "the next plank starts at the end")
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 2, "each Shift-click adds the next plank")
	assert_eq(world.bridge.members[1].a, world.bridge.members[0].b, "joined at the last point")
	tools.chain = false
	assert_null(tools.preview_from(), "letting go of Shift ends the chain: nothing follows the mouse")
	_click(Vector2(13, 5))
	assert_eq(world.bridge.members.size(), 2, "the next click starts a new plank")


func test_clicking_the_last_point_again_ends_a_chain() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	tools.chain = true
	_click(Vector2(6, 6))
	_click(Vector2(9, 6))
	_click(Vector2(9, 6))
	tools.chain = false
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 1, "the click after it starts a new plank")


func test_holding_shift_picks_up_where_you_left_off() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_click(Vector2(6, 6))
	_click(Vector2(9, 6))
	assert_null(tools.preview_from())
	tools.chain = true
	assert_eq(tools.preview_from().pos, Vector2(9, 6), "a new plank from the last end follows the mouse")
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 2)
	assert_eq(world.bridge.members[1].a, world.bridge.members[0].b, "carried on from it")


func test_letting_go_of_shift_drops_the_picked_up_plank() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_click(Vector2(6, 6))
	_click(Vector2(9, 6))
	tools.chain = true
	tools.chain = false
	assert_null(tools.preview_from(), "nothing follows the mouse")
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 1, "the click starts a new plank instead")


func test_no_picking_up_from_a_plan_already_ordered() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_click(Vector2(6, 6))
	_click(Vector2(9, 6))
	tools.commit()
	tools.chain = true
	assert_null(tools.preview_from(), "the crew has it now")


func test_right_click_cancels_even_with_shift_held() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	tools.chain = true
	_click(Vector2(6, 6))
	_click(Vector2(9, 6))
	tools.cancel()
	assert_null(tools.preview_from(), "no plank, and none picked up again while Shift stays down")
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 1, "the click starts a new one")


func test_shift_is_the_chain_key() -> void:
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	assert_true(InputMap.action_has_event(&"chain_build", shift))


func test_right_click_or_cancel_finishes_a_chain() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_click(Vector2(6, 6))
	_click(Vector2(9, 6))
	tools.cancel()
	_click(Vector2(11, 6))
	assert_eq(world.bridge.members.size(), 1, "the next click starts a new chain")
	assert_true(InputMap.action_has_event(&"cancel", _right_click()), "right-click cancels")


## Through real input: the camera, which pans on a right-drag, must not swallow the right-click first.
func test_a_real_right_click_finishes_a_chain_even_with_the_camera() -> void:
	var cam := CameraRig.new()
	cam.world = world
	add_child_autofree(cam)
	_select(ToolDefinition.Kind.BUILD, "Log")
	_click(Vector2(6, 6))
	_click(Vector2(9, 6))
	get_viewport().push_input(_right_click())
	var up := _right_click()
	up.pressed = false
	get_viewport().push_input(up)
	_click(Vector2(11, 6))
	assert_eq(world.bridge.members.size(), 1, "the chain ended: the next click starts a new one")


func test_a_click_that_can_not_build_keeps_the_chain() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_click(Vector2(6, 6))
	_click(Vector2(13, 6))
	assert_eq(world.bridge.members.size(), 0, "too long")
	_click(Vector2(9, 6))
	assert_eq(world.bridge.members.size(), 1, "still building from the first point")
	assert_eq(world.bridge.members[0].a.pos, Vector2(6, 6))


func _right_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	return e


func test_log_build_spends_a_log_per_metre() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	var logs := GameState.supplies.logs
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	assert_eq(world.bridge.members.size(), 1)
	assert_true(world.bridge.members[0].blueprint, "placed as a plan")
	assert_eq(GameState.supplies.logs, logs - 3, "3 m: 3 logs")


func test_commit_orders_the_plan() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	assert_eq(tools.commit(), 1)
	assert_true(world.bridge.members[0].ordered, "handed to the crew")


func test_support_tool_places_support() -> void:
	_select(ToolDefinition.Kind.BUILD, "Support")
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	assert_eq(world.bridge.members.size(), 1)
	assert_false(world.bridge.members[0].material.walkable)


func test_dig_member_refunds_it() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	var logs := GameState.supplies.logs
	_select(ToolDefinition.Kind.DIG)
	_click(Vector2(7.5, 6.05))
	assert_eq(world.bridge.members.size(), 0)
	assert_eq(GameState.supplies.logs, logs + 3, "all 3 back")

func test_bridge_tool_is_called_bridge() -> void:
	var names := tools.tools.map(func(t: ToolDefinition) -> String: return t.display_name)
	assert_true("Bridge" in names)
	assert_false("Log" in names)


func test_stone_build_spends_stone_and_builds_a_heavy_member() -> void:
	_select(ToolDefinition.Kind.BUILD, "Stone")
	GameState.supplies.stone = 3
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(8, 6)
	tools._release()
	assert_eq(world.bridge.members.size(), 1)
	assert_eq(GameState.supplies.stone, 1, "2 m: 2 stone")
	var stone := world.bridge.members[0].material
	assert_gt(stone.kg_per_m, preload("res://data/bridge/log.tres").kg_per_m, "heavier than a log")
	assert_gt(stone.break_force, preload("res://data/bridge/log.tres").break_force, "stronger than a log")


func test_tools_in_order_on_keys_one_to_five() -> void:
	var names := tools.tools.map(func(t: ToolDefinition) -> String: return t.display_name)
	assert_eq(names, ["Dig/Chop", "Bridge", "Support", "Rope", "Box"])
	for i in tools.tools.size():
		var t: ToolDefinition = tools.tools[i]
		assert_eq(t.key_label, str(i + 1))
		var key := InputEventKey.new()
		key.physical_keycode = KEY_1 + i
		assert_true(InputMap.action_has_event(t.action, key), "%s on key %d" % [t.display_name, i + 1])


func test_bridge_builds_the_material_picked() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	var bridge := tools.current
	assert_eq(tools.tool().display_name, "Bridge")
	tools.select(bridge)
	assert_eq(tools.build_material().display_name, "Log", "pressing Bridge again changes nothing")
	tools.pick_material(tools.tool().materials()[1])
	assert_eq(tools.build_material().display_name, "Stone", "picked")
	_select(ToolDefinition.Kind.BUILD, "Rope")
	tools.select(bridge)
	assert_eq(tools.build_material().display_name, "Stone", "coming back from another tool keeps the pick")


func test_a_plan_from_inside_the_ground_is_measured_from_where_it_leaves_it() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	# From deep in the ground (x 2, row 8) up out of it: 6.4 m in all, 3.8 m of it above the ground.
	tools._mouse_m = Vector2(2, 8)
	tools._press()
	tools._mouse_m = Vector2(6, 3)
	tools._release()
	assert_eq(world.bridge.members.size(), 1, "built: the part above the ground is short enough")
	var m: Bridge.Member = world.bridge.members[0]
	assert_lt(m.length, 5.0, "measured from the face of the ground")


## Starts a chain at from and places one plank to to with Shift held; the chain then waits at to.
func _chain(from: Vector2, to: Vector2) -> void:
	tools.chain = true
	_click(from)
	_click(to)


func test_ordering_a_plan_ends_the_chain_building_onto_it() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_chain(Vector2(6, 6), Vector2(9, 6))
	world.bridge.order_plan(world.bridge.plans()[0])
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 1, "the click starts a new chain instead of adding to the ordered plan")


func test_ordering_every_plan_ends_the_chain() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_chain(Vector2(6, 6), Vector2(9, 6))
	tools.commit()
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 1)


func test_ordering_another_plan_keeps_the_chain() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_chain(Vector2(1, 6), Vector2(3, 6))
	tools.cancel()
	_chain(Vector2(8, 6), Vector2(10, 6))
	var first: Array = world.bridge.plans().filter(func(p: Array) -> bool: return (p[0] as Bridge.Member).a.pos.x < 5.0)[0]
	world.bridge.order_plan(first)
	_click(Vector2(12, 5))
	assert_eq(world.bridge.members.size(), 3, "the other chain carried on")


func test_cancelling_the_plan_ends_the_chain_building_onto_it() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	_chain(Vector2(6, 6), Vector2(9, 6))
	GameState.gain(world.bridge.cancel_plan(world.bridge.plans()[0]))
	_click(Vector2(11, 5))
	assert_eq(world.bridge.members.size(), 0, "the click starts a new chain, not a plank from a joint that is gone")


func test_digging_away_a_plan_says_what_came_back() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	tools._mouse_m = Vector2(6, 6)
	tools._press()
	tools._mouse_m = Vector2(9, 6)
	tools._release()
	watch_signals(Effects)
	_select(ToolDefinition.Kind.DIG)
	_click(Vector2(7.5, 6.05))
	assert_signal_emitted_with_parameters(Effects, "said", ["+3 logs", Grid.to_px(Vector2(7.5, 6) - Vector2(0, 0.6))])


## Plans a log from from to to (a drag) and returns how many logs it took.
func _logs_for(from: Vector2, to: Vector2) -> int:
	_select(ToolDefinition.Kind.BUILD, "Log")
	GameState.supplies.logs = 20
	tools._mouse_m = from
	tools._press()
	tools._mouse_m = to
	tools._release()
	return 20 - GameState.supplies.logs


func test_a_plan_costs_one_per_started_metre() -> void:
	assert_eq(_logs_for(Vector2(6, 6), Vector2(7, 6)), 1, "1 m: 1 log")
	assert_eq(_logs_for(Vector2(6, 5), Vector2(9.5, 5)), 4, "3.5 m: 4 logs")
	assert_eq(_logs_for(Vector2(2, 4), Vector2(5, 0)), 5, "5 m: 5 logs")


func test_a_plan_needs_its_full_price() -> void:
	_select(ToolDefinition.Kind.BUILD, "Log")
	GameState.supplies.logs = 2
	tools._mouse_m = Vector2(6, 5)
	tools._press()
	tools._mouse_m = Vector2(9.5, 5)
	tools._release()
	assert_eq(world.bridge.members.size(), 0, "4 logs needed, 2 held")
	assert_eq(GameState.supplies.logs, 2)


func test_taking_a_plan_back_returns_what_it_cost() -> void:
	_logs_for(Vector2(6, 5), Vector2(9.5, 5))
	_select(ToolDefinition.Kind.DIG)
	_click(Vector2(7.5, 5.05))
	assert_eq(GameState.supplies.logs, 20, "all 4 back")


func test_splitting_a_plan_does_not_make_logs() -> void:
	_logs_for(Vector2(5, 5), Vector2(7.5, 5))
	var paid := 20 - GameState.supplies.logs
	var m: Bridge.Member = world.bridge.members[0]
	world.bridge.split(m, Vector2(6.2, 5))
	var back := Supplies.new()
	for p: Bridge.Member in world.bridge.members:
		back.add(p.paid)
	assert_eq(back.logs, paid, "the two halves are worth what was paid")
