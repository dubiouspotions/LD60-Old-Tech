extends GutTest


func before_all() -> void:
	GameState.save_path = "user://test_sappers.cfg"


func test_new_campaign_uses_campaign_start() -> void:
	GameState.new_campaign()
	assert_eq(GameState.soldiers, GameState.campaign.start_soldiers)
	assert_eq(GameState.supplies.logs, GameState.campaign.start_supplies.logs)
	assert_eq(GameState.level_index, 0)


func test_arrive_adds_capped_reinforcements_and_supplies() -> void:
	GameState.new_campaign()
	var cap: int = GameState.campaign.army_rules.max_soldiers
	GameState.set_soldiers(cap - 1)
	var logs_before := GameState.supplies.logs
	var joined := GameState.arrive(1, 3, Supplies.make(0, 8))
	assert_eq(joined, 1)
	assert_eq(GameState.soldiers, cap)
	assert_eq(GameState.supplies.logs, logs_before + 8)


func test_retry_restores_checkpoint() -> void:
	GameState.new_campaign()
	GameState.arrive(1, 3, Supplies.new())
	var soldiers := GameState.soldiers
	var earth := GameState.supplies.earth
	GameState.spend(Supplies.make(1))
	GameState.set_soldiers(2)
	GameState.retry()
	assert_eq(GameState.soldiers, soldiers)
	assert_eq(GameState.supplies.earth, earth)
