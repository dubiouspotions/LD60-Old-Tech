extends Node
## Campaign progress that outlives a level: supplies, column size, current level, checkpoint, best level.
## Autoload "GameState".

signal supplies_changed
signal soldiers_changed(count: int)
signal best_changed(level_number: int)

const CAMPAIGN_PATH: String = "res://data/campaign.tres"
## Where the best level is stored. Tests point this elsewhere.
var save_path: String = "user://sappers.cfg"

var campaign: Campaign
var supplies: Supplies = Supplies.new()
var soldiers: int = 0
## 0-based index into campaign.levels.
var level_index: int = 0
## 1-based, as shown to the player.
var best_level: int = 1
## A level scene to start the game at, set by a level run on its own (Run Current Scene). The Game takes it once.
var start_level: String = ""

var _checkpoint_supplies: Supplies = Supplies.new()
var _checkpoint_soldiers: int = 0


func _ready() -> void:
	if ResourceLoader.exists(CAMPAIGN_PATH):
		campaign = load(CAMPAIGN_PATH)
	_load_best()


func new_campaign() -> void:
	level_index = 0
	soldiers = campaign.start_soldiers
	supplies = campaign.start_supplies.copy() if campaign.start_supplies else Supplies.new()
	_checkpoint()


## Called when the column reaches the next level. Adds reinforcements (capped) and the level's supply drop.
## Returns how many soldiers actually joined.
func arrive(index: int, reinforcements: int, supply_drop: Supplies) -> int:
	level_index = index
	var cap := campaign.army_rules.max_soldiers if campaign.army_rules else 999
	var joined := clampi(cap - soldiers, 0, reinforcements)
	soldiers += joined
	supplies.add(supply_drop)
	if level_number() > best_level:
		best_level = level_number()
		_save_best()
		best_changed.emit(best_level)
	_checkpoint()
	return joined


## Restores the column and supplies held when the current level began.
func retry() -> void:
	supplies = _checkpoint_supplies.copy()
	soldiers = _checkpoint_soldiers
	supplies_changed.emit()
	soldiers_changed.emit(soldiers)


func level_number() -> int:
	return level_index + 1


func has_next_level() -> bool:
	return level_index + 1 < campaign.levels.size()


func spend(cost: Supplies) -> bool:
	if not supplies.spend(cost):
		return false
	supplies_changed.emit()
	return true


func gain(found: Supplies) -> void:
	if found == null or found.is_empty():
		return
	supplies.add(found)
	supplies_changed.emit()


func set_soldiers(count: int) -> void:
	if count == soldiers:
		return
	soldiers = count
	soldiers_changed.emit(count)


func _checkpoint() -> void:
	_checkpoint_supplies = supplies.copy()
	_checkpoint_soldiers = soldiers
	supplies_changed.emit()
	soldiers_changed.emit(soldiers)


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		best_level = int(cfg.get_value("progress", "best_level", 1))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value("progress", "best_level", best_level)
	cfg.save(save_path)
