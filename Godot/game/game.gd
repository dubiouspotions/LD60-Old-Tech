class_name Game
extends Node
## Runs the campaign: loads levels in order, moves the column between them, pause/speed, and the HUD cards.
## Levels, tools and starting supplies come from data/campaign.tres.

@export var fast_speed: float = 2.0
@export var lost_text: String = "Lost on level %d. Retrying restores the army and supplies you had at the checkpoint."
@export var victory_text: String = "All %d levels crossed with %d soldiers standing."
## Banner title when the level has no display name.
@export var arrival_title: String = "Level %d"
@export var arrival_text: String = "Checkpoint · +%d soldiers · supplies"
@export_group("March")
## Status while the column waits (%d = seconds left).
@export var patience_text: String = "The king waits · %d s"
## Status while the column marches toward a deep drop or hazard (%s = what).
@export var danger_text: String = "Marching · %s"
@export var march_title: String = "Forward, march!"
@export var march_player_text: String = "The column advances on your order"
@export var march_king_text: String = "The king has lost his patience"
@export var march_sound: SoundEffect

@onready var _holder: Node2D = %LevelHolder
@onready var _tools: ToolController = %ToolController
@onready var _camera: CameraRig = %Camera
@onready var _hud: Hud = %HUD

var level: Level
var _over: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	var campaign := GameState.campaign
	_tools.tools = campaign.tools
	_hud.build_tools(campaign.tools)
	_tools.tool_changed.connect(_on_tool_changed)
	_hud.tool_pressed.connect(_tools.select)
	_hud.pause_pressed.connect(_toggle_pause)
	_hud.speed_pressed.connect(_toggle_speed)
	_hud.follow_pressed.connect(_camera.snap_to_lead)
	_hud.commit_pressed.connect(_tools.commit)
	_hud.march_pressed.connect(_march)
	_hud.begin_pressed.connect(_begin)
	_hud.retry_pressed.connect(_retry)
	_hud.restart_pressed.connect(_restart)
	_camera.follow_changed.connect(_hud.set_follow)
	_tools.select(0)
	GameState.new_campaign()
	_load_level(0, false)
	_set_paused(true)
	_hud.show_intro(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_toggle_pause()
	elif event.is_action_pressed(&"speed"):
		_toggle_speed()
	elif event.is_action_pressed(&"march"):
		_march()


func _process(_delta: float) -> void:
	if level == null:
		return
	var lead := level.army.lead()
	_hud.set_level(GameState.level_number(), floori(lead.pos.x) if lead else 0)
	_hud.set_plan(level.bridge.blueprint_count())
	_hud.set_march(level.army.hold and not _over)
	_update_status()
	_update_lead_marker(lead)


func _begin() -> void:
	_hud.hide_cards()
	_tools.enabled = true
	_set_paused(false)


func _march() -> void:
	if level and not _over and not _hud.any_card_open():
		level.march()


func _on_march_ordered(by_player: bool) -> void:
	_hud.banner(march_title, march_player_text if by_player else march_king_text)
	Audio.play(march_sound)


func _toggle_pause() -> void:
	if _hud.any_card_open():
		return
	_set_paused(not get_tree().paused)


func _toggle_speed() -> void:
	Engine.time_scale = fast_speed if is_equal_approx(Engine.time_scale, 1.0) else 1.0
	_hud.set_speed(Engine.time_scale)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_hud.set_paused(paused, not _hud.any_card_open())


func _on_tool_changed(index: int) -> void:
	_hud.set_tool(index)
	_camera.pan_tool = _tools.tool().kind == ToolDefinition.Kind.PAN


func _load_level(index: int, arriving: bool) -> void:
	if level:
		_holder.remove_child(level)
		level.queue_free()
	Effects.clear()
	_tools.cancel()
	level = GameState.campaign.levels[index].instantiate()
	_holder.add_child(level)
	if arriving:
		var joined := GameState.arrive(index, level.reinforcements, level.supply_drop)
		var title := level.display_name if not level.display_name.is_empty() else arrival_title % GameState.level_number()
		_hud.banner(title, arrival_text % joined)
		Audio.play(GameState.campaign.level_up_sound)
	else:
		GameState.level_index = index
	level.start(GameState.soldiers, GameState.level_number())
	level.exit_reached.connect(_on_exit_reached, CONNECT_DEFERRED)
	level.army_lost.connect(_on_army_lost, CONNECT_DEFERRED)
	level.march_ordered.connect(_on_march_ordered)
	_tools.level = level
	_camera.level = level
	_camera.snap_to_lead()
	_over = false
	Audio.play_music(level.music)


func _on_exit_reached() -> void:
	if GameState.has_next_level():
		_load_level(GameState.level_index + 1, true)
		return
	_over = true
	_tools.enabled = false
	_set_paused(true)
	_hud.show_victory(victory_text % [GameState.campaign.levels.size(), GameState.soldiers])
	_hud.set_paused(true, false)
	Audio.play(GameState.campaign.victory_sound)


func _on_army_lost() -> void:
	_over = true
	_tools.enabled = false
	_hud.show_lost(lost_text % GameState.level_number())
	_set_paused(true)
	Audio.play(GameState.campaign.lost_sound)


func _retry() -> void:
	_hud.hide_cards()
	GameState.retry()
	_load_level(GameState.level_index, false)
	_tools.enabled = true
	_set_paused(false)


func _restart() -> void:
	_hud.hide_cards()
	GameState.new_campaign()
	_load_level(0, false)
	_tools.enabled = true
	_set_paused(false)


func _update_status() -> void:
	var reason := level.army.halt_reason
	var under_fire := false
	for o in level.objects.get_children():
		if o is Archer and o.engaging:
			under_fire = true
			break
	if _over:
		_hud.set_status("Column lost", Hud.Mood.FIRE)
	elif get_tree().paused:
		_hud.set_status("Paused" if not _hud.any_card_open() else "Awaiting orders", Hud.Mood.HALT)
	elif level.army.hold:
		_hud.set_status(patience_text % ceili(level.march_left()), Hud.Mood.HALT)
	elif under_fire:
		_hud.set_status("Under fire · %s" % reason if reason else "Under fire", Hud.Mood.FIRE)
	elif reason:
		_hud.set_status("Halted · %s" % reason, Hud.Mood.HALT)
	elif not level.army.danger.is_empty():
		_hud.set_status(danger_text % level.army.danger, Hud.Mood.FIRE)
	else:
		_hud.set_status("Marching", Hud.Mood.NORMAL)


func _update_lead_marker(lead: Soldier) -> void:
	if lead == null:
		_hud.set_lead_marker(0, 0)
		return
	var screen := level.get_viewport().get_canvas_transform() * lead.position
	var w := level.get_viewport().get_visible_rect().size.x
	var side := 1 if screen.x > w else (-1 if screen.x < 0 else 0)
	_hud.set_lead_marker(side, screen.y - Grid.PX)
