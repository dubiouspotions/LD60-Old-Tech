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
