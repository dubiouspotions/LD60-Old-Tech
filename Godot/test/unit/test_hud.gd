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


func test_the_night_timer_sits_at_the_top_centre_with_march_now_beneath() -> void:
	await wait_frames(2)
	var width := hud.get_viewport().get_visible_rect().size.x
	var status := (hud.get_node("%StatusPanel") as Control).get_global_rect()
	assert_almost_eq(status.get_center().x, width / 2.0, 1.0, "centred")
	assert_lt(status.position.y, 40.0, "at the top")
	var panel: PanelContainer = hud.get_node("%MarchPanel")
	var march: Button = hud.get_node("%MarchButton")
	var rect := panel.get_global_rect()
	assert_almost_eq(rect.get_center().x, width / 2.0, 1.0, "centred too")
	assert_between(rect.position.y, status.end.y + 12.0, status.end.y + 32.0, "beneath the timer, with a little room")
	assert_true(panel.is_ancestor_of(march))
	assert_eq(panel.theme_type_variation, &"NinePatchPanel", "the Camp Shoppe's look")
	assert_eq(march.theme_type_variation, &"PanelButton")
	assert_eq(march.get_theme_font(&"font").resource_path, "res://ui/fonts/alagard.ttf")
	hud.set_march(false)
	assert_false(panel.visible, "gone once the column marches")
	hud.set_march(true)
	assert_true(panel.visible)


func _shop(soldier_ok: bool = true, engineer_ok: bool = true, at: Vector2 = Vector2(400, 300)) -> void:
	hud.set_shop(true, 2, soldier_ok, 5, engineer_ok, at)


func test_camp_shoppe_panel_shows_under_the_camp() -> void:
	_shop()
	var panel: PanelContainer = hud.get_node("%ShopPanel")
	var b: Button = hud.get_node("%ShopButton")
	assert_true(b.is_visible_in_tree(), "on screen, not hidden by a parent")
	assert_eq(b.text, "Camp Shoppe")
	assert_true(panel.is_ancestor_of(b), "the button is in the panel")
	assert_eq(panel.get_parent(), hud.get_node("%WorldButtons"))
	assert_almost_eq(panel.position.x + panel.size.x / 2, 400.0, 1.0, "centred under the camp")
	assert_almost_eq(panel.position.y, 300.0, 1.0, "hanging below the spot, not above it")
	b.pressed.emit()
	hud.set_shop(false, 2, true, 5, true, Vector2.ZERO)
	assert_false(panel.visible, "gone when the camp is struck")
	assert_false(hud.get_node("%ShopMenu").visible, "and its list folded up")


## A red arrow at the screen edge points at the nearest engineer off screen, like the blue one at the leader.
func test_crew_marker_points_at_an_engineer_off_screen() -> void:
	var m: Label = hud.get_node("%CrewMarker")
	var lead: Label = hud.get_node("%LeadMarker")
	hud.set_crew_marker(0, 0.0)
	assert_false(m.visible, "nobody off screen")
	hud.set_crew_marker(-1, 300.0)
	assert_true(m.visible)
	assert_eq(m.text, "◀")
	assert_lt(m.position.x, 50.0, "on the left edge")
	hud.set_crew_marker(1, 300.0)
	assert_eq(m.text, "▶")
	assert_gt(m.get_theme_color(&"font_color").r, 0.8, "red")
	assert_lt(m.get_theme_color(&"font_color").b, 0.5)
	assert_eq(m.get_theme_font_size(&"font_size"), lead.get_theme_font_size(&"font_size"), "the same arrow as the leader's")


## It fades in when it opens, and is gone at once when it closes.
func test_camp_shoppe_fades_in() -> void:
	var panel: PanelContainer = hud.get_node("%ShopPanel")
	assert_gt(hud.shop_fade_time, 0.0)
	_shop()
	assert_true(panel.visible)
	assert_lt(panel.modulate.a, 0.1, "starts see-through")
	_shop()
	await wait_seconds(hud.shop_fade_time + 0.1)
	_shop()
	assert_almost_eq(panel.modulate.a, 1.0, 0.01, "faded in")
	hud.set_shop(false, 2, true, 5, true, Vector2.ZERO)
	assert_false(panel.visible)


## The panel never hangs past where the view can be scrolled (reach, world pixels): it keeps shop_edge_margin from
## that edge instead. (Without a camera, world and screen pixels are the same here.)
func test_the_panel_keeps_a_margin_from_where_scrolling_stops() -> void:
	var panel: PanelContainer = hud.get_node("%ShopPanel")
	var reach := Vector2(100, 900)
	hud.set_shop(true, 2, true, 5, true, Vector2(110, 300), reach)
	assert_almost_eq(panel.position.x, reach.x + hud.shop_edge_margin, 1.0, "pushed in from the left cut-off")
	hud.set_shop(true, 2, true, 5, true, Vector2(895, 300), reach)
	assert_almost_eq(panel.position.x + panel.size.x, reach.y - hud.shop_edge_margin, 1.0, "and from the right one")
	hud.set_shop(true, 2, true, 5, true, Vector2(500, 300), reach)
	assert_almost_eq(panel.position.x + panel.size.x / 2, 500.0, 1.0, "centred under the camp when there is room")
	assert_gt(hud.shop_edge_margin, 0.0)


## The Camp Shoppe belongs to the camp: it stays under it whatever the HUD is doing, and the HUD's own controls
## (drawn in front of it) cover it where they meet.
func test_the_hud_is_in_front_of_the_camp_shoppe() -> void:
	var panel: PanelContainer = hud.get_node("%ShopPanel")
	var march: Control = hud.get_node("%MarchButton")
	var spot := march.get_global_rect().get_center() + Vector2(0, -20)
	hud.set_shop(true, 2, true, 5, true, spot)
	assert_almost_eq(panel.position.y, spot.y, 1.0, "stays under the camp, not pushed aside")
	var world_buttons: Control = hud.get_node("%WorldButtons")
	assert_eq(world_buttons.get_parent(), hud, "a layer of its own...")
	assert_eq(world_buttons.get_index(), 0, "...drawn first, so the rest of the HUD is in front and gets clicks first")


func test_pressing_it_drops_down_two_purchases() -> void:
	_shop()
	var panel: PanelContainer = hud.get_node("%ShopPanel")
	var b: Button = hud.get_node("%ShopButton")
	var menu: Control = hud.get_node("%ShopMenu")
	assert_false(menu.visible, "closed at first")
	await wait_frames(2)
	var closed := panel.size.y
	b.pressed.emit()
	_shop()
	assert_true(menu.is_visible_in_tree(), "dropped down")
	assert_true(panel.is_ancestor_of(menu), "inside the same panel")
	await wait_frames(2)
	assert_gt(panel.size.y, closed + 20.0, "the panel grows to hold them")
	assert_almost_eq(panel.position.y, 300.0, 1.0, "downward, from the same spot")
	for pair in [["%ShopSoldier", "Soldier", "2"], ["%ShopEngineer", "Engineer", "5"]]:
		var o: Button = hud.get_node(pair[0])
		var name_label: Label = o.get_node("Row/Name")
		var price: Label = o.get_node("Row/Price")
		var icon: TextureRect = o.get_node("Row/Icon")
		assert_eq(name_label.text, pair[1])
		assert_eq(price.text, pair[2])
		assert_eq(icon.texture.resource_path, "res://world/goldbar.png", "the price in gold, with the gold icon")
		assert_lt(name_label.position.x, o.size.x / 4.0, "%s on the left" % pair[1])
		assert_gt(price.position.x, o.size.x / 2.0, "its price on the right")
		assert_gt(icon.position.x, price.position.x, "then the gold icon")
	var soldier: Button = hud.get_node("%ShopSoldier")
	var engineer: Button = hud.get_node("%ShopEngineer")
	assert_eq(soldier.size.x, engineer.size.x, "the same width, so the prices line up")
	assert_almost_eq(b.size.x, soldier.size.x, 0.5, "and as wide as the Camp Shoppe button")
	assert_almost_eq(menu.position.x + menu.size.x / 2, b.position.x + b.size.x / 2, 1.0, "lined up under it")
	assert_gte(menu.position.y, b.position.y + b.size.y - 1.0, "below the button")
	b.pressed.emit()
	assert_false(menu.visible, "a second press folds it up")
	_shop()
	await wait_frames(2)
	assert_almost_eq(panel.size.y, closed, 0.5, "and the panel shrinks back")


func test_the_shoppe_sits_on_the_nine_patch_panel() -> void:
	var panel: PanelContainer = hud.get_node("%ShopPanel")
	var style := panel.get_theme_stylebox(&"panel") as StyleBoxTexture
	assert_not_null(style, "a nine-patch panel")
	assert_eq(style.texture.resource_path, "res://ui/elements/panel_ninepatch.png")


## The look is the theme's, to reuse anywhere: a NinePatchPanel with PanelButtons on it, which show only their
## words, in Alagard.
func test_the_shoppe_wears_the_reusable_panel_look() -> void:
	assert_eq((hud.get_node("%ShopPanel") as Control).theme_type_variation, &"NinePatchPanel")
	var b: Button = hud.get_node("%ShopButton")
	for o: Button in [b, hud.get_node("%ShopSoldier"), hud.get_node("%ShopEngineer")]:
		assert_eq(o.theme_type_variation, &"PanelButton", o.name)
		assert_true(o.get_theme_stylebox(&"normal") is StyleBoxEmpty, "%s draws no button of its own" % o.name)
		assert_eq(o.get_theme_stylebox(&"hover").resource_path, "res://ui/styles/ninepatch_highlight.tres",
				"%s glows when the mouse is over it" % o.name)
		assert_eq(o.get_theme_font(&"font").resource_path, "res://ui/fonts/alagard.ttf")
	for l: Label in [hud.get_node("%ShopSoldier/Row/Name"), hud.get_node("%ShopEngineer/Row/Price")]:
		assert_eq(l.get_theme_font(&"font").resource_path, "res://ui/fonts/alagard.ttf")


func test_the_shoppe_text_lights_up_under_the_mouse() -> void:
	_shop()
	var b: Button = hud.get_node("%ShopButton")
	var soldier: Button = hud.get_node("%ShopSoldier")
	var lit := soldier.get_theme_color(&"font_hover_color")
	assert_eq(b.get_theme_color(&"font_hover_color"), lit, "Camp Shoppe")
	var name_label: Label = soldier.get_node("Row/Name")
	var price: Label = soldier.get_node("Row/Price")
	var normal := name_label.get_theme_color(&"font_color")
	assert_ne(normal, lit)
	soldier.mouse_entered.emit()
	assert_eq(name_label.get_theme_color(&"font_color"), lit, "the purchase under the mouse")
	assert_eq(price.get_theme_color(&"font_color"), lit, "price and all")
	soldier.mouse_exited.emit()
	assert_eq(name_label.get_theme_color(&"font_color"), normal, "and back when it leaves")
	soldier.mouse_entered.emit()
	_shop(false, true)
	assert_eq(name_label.get_theme_color(&"font_color"), normal, "not left lit once it can no longer be bought")


func test_purchases_report_clicks() -> void:
	watch_signals(hud)
	_shop()
	hud.get_node("%ShopButton").pressed.emit()
	hud.get_node("%ShopSoldier").pressed.emit()
	assert_signal_emitted(hud, "recruit_pressed")
	hud.get_node("%ShopEngineer").pressed.emit()
	assert_signal_emitted(hud, "hire_pressed")


## A purchase that can not be made is greyed out and lets clicks through to the world behind it.
func test_unaffordable_purchases_grey_out_and_let_clicks_through() -> void:
	_shop(false, true)
	var soldier: Button = hud.get_node("%ShopSoldier")
	var engineer: Button = hud.get_node("%ShopEngineer")
	assert_true(soldier.disabled)
	assert_eq(soldier.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks pass through")
	assert_false(engineer.disabled)
	assert_eq(engineer.mouse_filter, Control.MOUSE_FILTER_STOP)


func test_build_and_cancel_buttons_float_above_plans() -> void:
	watch_signals(hud)
	hud.set_build_spots([Vector2(100, 200), Vector2(300, 220)], [2, 1])
	var pairs := hud.get_node("%WorldButtons").get_children().filter(func(n: Node) -> bool: return n is PlanButtons and n.visible)
	assert_eq(pairs.size(), 2)
	assert_true((pairs[0] as Control).is_visible_in_tree(), "on screen, not hidden by a parent")
	var second: PlanButtons = pairs[1]
	assert_almost_eq(second.position.x + second.size.x / 2, 300.0, 1.0, "centred on its plan")
	assert_almost_eq(second.position.y + second.size.y, 220.0, 1.0, "sits above it")
	second.get_node("%Build").pressed.emit()
	assert_signal_emitted_with_parameters(hud, "build_pressed", [1])
	second.get_node("%Cancel").pressed.emit()
	assert_signal_emitted_with_parameters(hud, "cancel_pressed", [1])
	hud.set_build_spots([], [])
	assert_false(hud.get_node("%WorldButtons").get_children().any(func(n: Node) -> bool: return n.visible))


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
	for c in b.get_node("%Cost").get_children():
		var shown: Color = (c as CanvasItem).modulate * (b.get_node("%Cost") as CanvasItem).modulate
		if c is ColorRect:
			assert_eq(shown, Color.WHITE, "the supply's swatch keeps its colour")
		else:
			assert_eq(shown, b.short_cost_color, "the count turns red")
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


func test_the_bridge_button_shows_its_materials_as_icons_on_itself() -> void:
	GameState.new_campaign()
	var tools := GameState.campaign.tools
	var i := tools.map(func(t: ToolDefinition) -> String: return t.display_name).find("Bridge")
	var b: ToolButton = hud.get_node("%Tools").get_child(i)
	var mats := tools[i].materials()
	var icons: Array = b.get_node("%Materials").get_children()
	assert_eq(icons.size(), 2, "one per material")
	assert_eq(icons.map(func(c: Button) -> Texture2D: return c.icon), mats.map(func(m: BridgeMaterial) -> Texture2D: return m.icon))
	assert_true(icons.all(func(c: Button) -> bool: return c.icon != null), "each material has an icon")
	assert_true((icons[0] as Button).button_pressed, "the first is the pick at first")
	watch_signals(hud)
	(icons[1] as Button).pressed.emit()
	assert_signal_emitted_with_parameters(hud, "tool_pressed", [i])
	assert_signal_emitted_with_parameters(hud, "material_picked", [mats[1]])
	hud.set_tool(i, mats[1])
	assert_true((icons[1] as Button).button_pressed, "the pick shows")
	assert_true(is_instance_valid(icons[1]), "the icons stay (one may be emitting this very pick)")
	assert_string_contains(b.tooltip_text, "1 stone", "the button shows what the pick costs")
	assert_false(hud.has_node("%MaterialPicker"), "no picker floating above the rack any more")
	var dig: ToolButton = hud.get_node("%Tools").get_child(0)
	assert_false(dig.get_node("%Materials").visible, "no icons on a tool with one material")


## Picking a material keeps a folded rack folded: no hint line pops back onto the button.
func test_picking_a_material_keeps_the_rack_folded() -> void:
	GameState.new_campaign()
	var tools := GameState.campaign.tools
	var i := tools.map(func(t: ToolDefinition) -> String: return t.display_name).find("Bridge")
	var b: ToolButton = hud.get_node("%Tools").get_child(i)
	hud.fit_to(10.0)
	assert_false(b.get_node("%Hint").visible, "folded: no hint")
	hud.set_tool(i, tools[i].materials()[1])
	assert_false(b.get_node("%Hint").visible, "still folded after the pick")
	assert_eq(b.get_node("%Hint").text, tools[i].materials()[1].hint, "the hint follows the pick for when it unfolds")


func test_the_lost_card_fades_the_screen_then_slides_in_from_below() -> void:
	var lost: ColorRect = hud.get_node("%Lost")
	var center: Control = lost.get_node("Center")
	var dim := lost.color.a
	hud.show_lost("Lost", "text")
	assert_true(lost.visible)
	assert_almost_eq(lost.color.a, 0.0, 0.01, "starts clear")
	assert_gt(center.position.y, 0.0, "the card starts below")
	await get_tree().create_timer(hud.card_fade_time + hud.card_slide_time + 0.2, true, false, true).timeout
	assert_almost_eq(lost.color.a, dim, 0.01, "faded to the overlay")
	assert_almost_eq(center.position.y, 0.0, 0.5, "slid into place")


## The Build/Cancel and Recruit buttons live under WorldButtons. Hiding it in the editor (it happened more than once)
## must not take them off the screen.
func test_world_buttons_show_even_if_hidden_in_the_scene() -> void:
	var other: Hud = load("res://ui/hud.tscn").instantiate()
	other.get_node("%WorldButtons").visible = false
	add_child_autofree(other)
	assert_true(other.get_node("%WorldButtons").visible)


func test_the_panel_look_is_in_the_theme_for_any_panel_to_use() -> void:
	var theme: Theme = load("res://ui/theme.tres")
	assert_eq(theme.get_type_variation_base(&"NinePatchPanel"), &"PanelContainer")
	assert_eq(theme.get_type_variation_base(&"PanelButton"), &"Button")
	var style := theme.get_stylebox(&"panel", &"NinePatchPanel") as StyleBoxTexture
	assert_eq(style.resource_path, "res://ui/styles/ninepatch_panel.tres", "its own file, to use directly too")
	assert_eq(style.texture.resource_path, "res://ui/elements/panel_ninepatch.png")


## The highlight frame is laid on top of a PanelButton when it is hovered or toggled on, with the same nine-patch
## settings as the panel under it.
func test_panel_buttons_glow_when_hovered_or_toggled() -> void:
	var theme: Theme = load("res://ui/theme.tres")
	var glow := theme.get_stylebox(&"hover", &"PanelButton") as StyleBoxTexture
	assert_not_null(glow)
	assert_eq(glow.resource_path, "res://ui/styles/ninepatch_highlight.tres")
	assert_eq(glow.texture.resource_path, "res://ui/elements/panel_highlight_ninepatch.png")
	for state: StringName in [&"pressed", &"hover_pressed"]:
		assert_eq(theme.get_stylebox(state, &"PanelButton"), glow, "%s too: a toggled tool glows" % state)
	assert_true(theme.get_stylebox(&"normal", &"PanelButton") is StyleBoxEmpty, "not when idle")
	var panel := theme.get_stylebox(&"panel", &"NinePatchPanel") as StyleBoxTexture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(glow.get_texture_margin(side), panel.get_texture_margin(side), "same nine-patch margins")


func test_the_tool_buttons_wear_the_panel_look() -> void:
	var tools: Control = hud.get_node("%Tools")
	var panel := tools.get_parent() as PanelContainer
	assert_not_null(panel, "the tools sit on a panel")
	assert_eq(panel.theme_type_variation, &"NinePatchPanel")
	assert_gt(tools.get_child_count(), 0)
	for b: Button in tools.get_children():
		assert_eq(b.theme_type_variation, &"PanelButton", b.name)
		assert_eq((b.get_node("%Name") as Label).get_theme_font(&"font").resource_path, "res://ui/fonts/alagard.ttf",
				"its name in Alagard")


## Glowing must not move or resize a PanelButton: every state has the same padding (content margins).
func test_a_panel_button_keeps_its_size_when_it_glows() -> void:
	var theme: Theme = load("res://ui/theme.tres")
	var normal := theme.get_stylebox(&"normal", &"PanelButton")
	for state: StringName in [&"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style := theme.get_stylebox(state, &"PanelButton")
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_eq(style.get_content_margin(side), normal.get_content_margin(side),
					"%s padding on side %d matches the idle look" % [state, side])
	_shop()
	await wait_frames(2)
	var b: Button = hud.get_node("%ShopButton")
	var idle := b.get_combined_minimum_size()
	b.add_theme_stylebox_override(&"normal", b.get_theme_stylebox(&"hover"))
	assert_eq(b.get_combined_minimum_size(), idle, "the Camp Shoppe button stays the same size under the mouse")
	b.remove_theme_stylebox_override(&"normal")


func test_the_top_of_the_screen_is_laid_out_without_overlaps() -> void:
	hud.set_paused(true, true)
	await wait_frames(2)
	var status: Label = hud.get_node("%Status")
	var timer := (hud.get_node("%StatusPanel") as Control).get_global_rect()
	var march := (hud.get_node("%MarchPanel") as Control).get_global_rect()
	var tag := (hud.get_node("%PausedTag") as Control).get_global_rect()
	assert_eq(status.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "the timer's text centred")
	assert_eq(status.position.x + status.size.x / 2.0, status.get_parent_control().size.x / 2.0, "and not nudged aside")
	assert_gte(march.position.y, timer.end.y + 12.0, "March Now a little below the timer")
	assert_gte(tag.position.y, march.end.y, "PAUSED below March Now")
