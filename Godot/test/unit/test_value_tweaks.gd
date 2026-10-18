extends GutTest
## The ValueTweaks node in the main scene: one Inspector panel that reads and writes the balance values where they
## live (campaign, rules, tools, terrain types). Values changed here are restored after each test.

var tweaks: ValueTweaks
var _main: Node
var _changed := {}


func before_each() -> void:
	_main = load("res://game/main.tscn").instantiate()
	tweaks = _main.get_node("ValueTweaks")


func after_each() -> void:
	for n: String in _changed:
		tweaks.set(n, _changed[n])
	_changed.clear()
	_main.free()


func _tweak(n: String, value: Variant) -> void:
	if not _changed.has(n):
		_changed[n] = tweaks.get(n)
	tweaks.set(n, value)


func _names() -> Array:
	return tweaks.get_property_list().map(func(p: Dictionary) -> String: return p.name)


func test_main_scene_has_the_tweaks() -> void:
	assert_not_null(tweaks)
	assert_eq(tweaks.campaign, GameState.campaign)


func test_lists_the_initial_tweakables() -> void:
	var names := _names()
	for n in ["army/start_soldiers", "army/soldier_hit_points", "army/mutiny_time", "army/recruit_cost/gold",
			"crew/engineers", "enemies/archer_hit_points",
			"supplies/start/logs", "supplies/checkpoint/logs",
			"prices/bridge/logs", "prices/fill/earth",
			"yields/soil/dig/earth", "yields/tree_trunk/fell/logs"]:
		assert_has(names, n)


func test_values_read_and_write_through_to_the_data() -> void:
	var campaign := GameState.campaign
	var rules := campaign.army_rules
	assert_eq(tweaks.get("army/soldier_hit_points"), rules.hit_points)
	_tweak("army/soldier_hit_points", 7)
	assert_eq(rules.hit_points, 7)
	_tweak("crew/engineers", 5)
	assert_eq(tweaks.crew_rules.crew_size, 5)
	_tweak("enemies/archer_hit_points", 9)
	assert_eq(tweaks.archer_rules.hit_points, 9)
	_tweak("supplies/checkpoint/logs", 11)
	assert_eq(campaign.checkpoint_supplies.logs, 11)
	var bridge: ToolDefinition = campaign.tools.filter(func(t: ToolDefinition) -> bool: return t.display_name == "Bridge")[0]
	_tweak("prices/bridge/logs", 3)
	assert_eq(bridge.price().logs, 3)


func test_new_campaign_starts_with_the_tweaked_values() -> void:
	_tweak("army/start_soldiers", 4)
	_tweak("supplies/start/rope", 13)
	GameState.new_campaign()
	assert_eq(GameState.soldiers, 4)
	assert_eq(GameState.supplies.rope, 13)
