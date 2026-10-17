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


func test_build_buttons_float_above_plans() -> void:
	watch_signals(hud)
	hud.set_build_spots([Vector2(100, 200), Vector2(300, 220)], [2, 1])
	var buttons := hud.get_node("%WorldButtons").get_children().filter(func(b: Node) -> bool: return b is WorldButton and b.visible and b != hud.get_node("%RecruitButton"))
	assert_eq(buttons.size(), 2)
	var second: WorldButton = buttons[1]
	assert_almost_eq(second.position.x + second.size.x / 2, 300.0, 1.0, "centred on its plan")
	assert_almost_eq(second.position.y + second.size.y, 220.0, 1.0, "sits above it")
	second.pressed.emit()
	assert_signal_emitted_with_parameters(hud, "build_pressed", [1])
	hud.set_build_spots([], [])
	assert_false(hud.get_node("%WorldButtons").get_children().any(func(b: Node) -> bool: return b.visible))


func test_recruit_button_floats_above_the_camp() -> void:
	hud.set_recruit(true, 5, true, Vector2(400, 300))
	var b: WorldButton = hud.get_node("%RecruitButton")
	assert_eq(b.get_parent(), hud.get_node("%WorldButtons"))
	assert_almost_eq(b.position.x + b.size.x / 2, 400.0, 1.0)
	assert_almost_eq(b.position.y + b.size.y, 300.0, 1.0)
