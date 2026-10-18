extends GutTest
## The HUD rows fit the window: tool hints fold away first, then the title.

var hud: Hud


func before_each() -> void:
	hud = load("res://ui/hud.tscn").instantiate()
	add_child_autofree(hud)
	hud.build_tools(GameState.campaign.tools)
	hud.set_march(true)


func _hints_shown() -> bool:
	return hud.get_node("%Tools").get_children().all(func(b: Node) -> bool: return b.get_node("%Hint").visible)


func test_wide_window_shows_everything() -> void:
	hud.fit_to(4000.0)
	assert_true(_hints_shown())
	assert_true(hud.get_node("%Title").visible)


func test_narrow_window_folds_hints_to_fit_the_rack() -> void:
	hud.fit_to(4000.0)
	var width: float = hud.get_node("%Rack").get_combined_minimum_size().x - 1.0
	hud.fit_to(width)
	assert_false(_hints_shown(), "hints folded")
	assert_lte(hud.get_node("%Rack").get_combined_minimum_size().x, width, "rack fits")


func test_narrower_window_hides_the_title_to_fit_the_top_bar() -> void:
	hud.fit_to(4000.0)
	var width: float = hud.get_node("%TopBar").get_combined_minimum_size().x - 1.0
	hud.fit_to(width)
	assert_false(hud.get_node("%Title").visible, "title hidden")
	assert_lte(hud.get_node("%TopBar").get_combined_minimum_size().x, width, "top bar fits")


func test_widening_again_unfolds() -> void:
	hud.fit_to(1000.0)
	hud.fit_to(4000.0)
	assert_true(_hints_shown())
	assert_true(hud.get_node("%Title").visible)


func test_recruit_button_shows_at_camp_and_reports_clicks() -> void:
	watch_signals(hud)
	hud.set_recruit(true, 5, true, Vector2.ZERO)
	var b: Button = hud.get_node("%RecruitButton")
	assert_true(b.visible)
	assert_string_contains(b.text, "5")
	b.pressed.emit()
	assert_signal_emitted(hud, "recruit_pressed")
	hud.set_recruit(true, 5, false, Vector2.ZERO)
	assert_true(b.disabled, "greyed out when gold is short")
	hud.set_recruit(false, 5, true, Vector2.ZERO)
	assert_false(b.visible)


func test_build_and_cancel_buttons_float_above_plans() -> void:
	watch_signals(hud)
	hud.set_build_spots([Vector2(100, 200), Vector2(300, 220)], [2, 1])
	var pairs := hud.get_node("%WorldButtons").get_children().filter(func(n: Node) -> bool: return n is PlanButtons and n.visible)
	assert_eq(pairs.size(), 2)
	var second: PlanButtons = pairs[1]
	assert_almost_eq(second.position.x + second.size.x / 2, 300.0, 1.0, "centred on its plan")
	assert_almost_eq(second.position.y + second.size.y, 220.0, 1.0, "sits above it")
	second.get_node("%Build").pressed.emit()
	assert_signal_emitted_with_parameters(hud, "build_pressed", [1])
	second.get_node("%Cancel").pressed.emit()
	assert_signal_emitted_with_parameters(hud, "cancel_pressed", [1])
	hud.set_build_spots([], [])
	assert_false(hud.get_node("%WorldButtons").get_children().any(func(n: Node) -> bool: return n.visible))


func test_recruit_button_floats_above_the_camp() -> void:
	hud.set_recruit(true, 5, true, Vector2(400, 300))
	var b: WorldButton = hud.get_node("%RecruitButton")
	assert_eq(b.get_parent(), hud.get_node("%WorldButtons"))
	assert_almost_eq(b.position.x + b.size.x / 2, 400.0, 1.0)
	assert_almost_eq(b.position.y + b.size.y, 300.0, 1.0)


func test_supplies_sit_just_above_the_build_buttons() -> void:
	var supplies: Control = hud.get_node("%Supplies")
	var rack: Control = hud.get_node("%Rack")
	var column := rack.get_parent()
	assert_eq(supplies.get_parent().get_parent(), column, "in the bottom area, not the top bar")
	assert_eq(supplies.get_parent().get_index() + 1, rack.get_index(), "right above the rack")


func test_tool_buttons_show_cost_and_grey_out_when_unaffordable() -> void:
	GameState.new_campaign()
	var tools := GameState.campaign.tools
	var log_index := -1
	for i in tools.size():
		if tools[i].kind == ToolDefinition.Kind.BUILD and tools[i].bridge_material.resource_path.ends_with("log.tres"):
			log_index = i
	var b: ToolButton = hud.get_node("%Tools").get_child(log_index)
	assert_true(b.get_node("%Cost").visible, "cost shown")
	assert_string_contains(b.tooltip_text, "1 log")
	GameState.supplies.logs = 0
	GameState.supplies_changed.emit()
	assert_false(b.affordable, "greyed out with no logs")
	GameState.supplies.logs = 5
	GameState.supplies_changed.emit()
	assert_true(b.affordable)
	var dig: ToolButton = hud.get_node("%Tools").get_child(0)
	assert_false(dig.get_node("%Cost").visible, "free tools show no cost")
	assert_true(dig.affordable)


func test_supply_bar_shows_stone() -> void:
	GameState.supplies.stone = 3
	hud._refresh_supplies()
	assert_eq((hud.get_node("%Stone").get_node("%Value") as Label).text, "3")


func test_bridge_shows_a_material_picker() -> void:
	GameState.new_campaign()
	var tools := GameState.campaign.tools
	var i := tools.map(func(t: ToolDefinition) -> String: return t.display_name).find("Bridge")
	var b: ToolButton = hud.get_node("%Tools").get_child(i)
	var stone: BridgeMaterial = tools[i].materials()[1]
	var picker: Control = hud.get_node("%MaterialPicker")
	hud.set_tool(i, tools[i].materials()[0])
	assert_true(picker.visible, "shown for Bridge")
	var names := picker.get_node("%Materials").get_children().map(func(c: Button) -> String: return c.text.get_slice(" ", 0))
	assert_eq(names, ["Log", "Stone"])
	watch_signals(hud)
	(picker.get_node("%Materials").get_child(1) as Button).pressed.emit()
	assert_signal_emitted_with_parameters(hud, "material_picked", [stone])
	hud.set_tool(i, stone)
	assert_string_contains(b.tooltip_text, "1 stone", "the button shows what the pick costs")
	hud.set_tool(0)
	assert_false(picker.visible, "hidden for tools with one material")
