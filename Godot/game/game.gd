class_name Game
extends Node
## Runs the campaign on one stitched World: camps and nights, pause/speed, and the HUD cards.
## Levels, tools and starting supplies come from data/campaign.tres.

@export var fast_speed: float = 2.0
@export var lost_title: String = "The army has fallen"
@export var lost_text: String = "Lost on level %d. Retrying restores the army and supplies you had at the checkpoint."
## Status bar text once the level is lost, by the army or by the engineers, and once the campaign is won.
@export var lost_status: String = "Column lost"
@export var crew_lost_status: String = "Engineers lost"
@export var victory_status: String = "Campaign won"
## When the last engineer dies instead.
@export var crew_lost_title: String = "The engineers are gone"
@export var crew_lost_text: String = "Lost on level %d: no engineers are left to build. Retrying restores the army, the engineers and the supplies you had at the checkpoint."
## Seconds the world goes on after the level is lost, so the player sees how, before the lost card covers it.
@export_range(0.0, 10.0, 0.1, "suffix:s") var lost_delay: float = 1.5
@export var victory_text: String = "All %d levels crossed with %d soldiers standing."
## Banner title when the level has no display name.
@export var arrival_title: String = "Level %d"
@export var arrival_text: String = "Camp for the night · +%d soldiers · supplies"
## Shown when a tester toggles the cheats (F2); %s = on / off.
@export var cheats_text: String = "Cheats %s"
## Turning the cheats on tops every supply up to at least this.
@export var cheat_supplies: int = 99
@export_group("March")
## Status while the column camps (%d = seconds until the king orders the march).
@export var patience_text: String = "Night camp · %d s"
## Status while the column gets up and breaks camp.
@export var morning_text: String = "Morning · breaking camp"
## Status while the column marches toward a deep drop or hazard (%s = what).
@export var danger_text: String = "Marching · %s"
@export var march_title: String = "Forward, march!"
@export var march_player_text: String = "The column breaks camp on your order"
@export var march_king_text: String = "The king has lost his patience"
@export var march_sound: SoundEffect
## How far above a plan its Build button floats.
@export var plan_button_rise: float = 0.4

@onready var _world: World = %World
@onready var _tools: ToolController = %ToolController
@onready var _camera: CameraRig = %Camera
@onready var _hud: Hud = %HUD
@onready var _day_night: DayNight = %DayNight

var _over: bool = false
## Status bar text once the game is over (lost or won).
var _over_status: String = ""
## Counts losses, so a lost card still waiting is dropped when the level is retried meanwhile.
var _losses: int = 0
## Plans shown with Build buttons this frame (see _show_plans).
var _plans: Array[Array] = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    %LevelHolder.process_mode = Node.PROCESS_MODE_PAUSABLE
    var campaign := GameState.campaign
    _tools.tools = campaign.tools
    _tools.world = _world
    _camera.world = _world
    _hud.build_tools(campaign.tools)
    _tools.tool_changed.connect(_on_tool_changed)
    _hud.tool_pressed.connect(_tools.select)
    _hud.material_picked.connect(_tools.pick_material)
    _hud.pause_pressed.connect(_toggle_pause)
    _hud.speed_pressed.connect(_toggle_speed)
    _hud.follow_toggled.connect(func(on: bool) -> void:
        if on:
            _camera.snap_to_lead()
        else:
            _camera.follow = false)
    _hud.build_pressed.connect(_on_build_pressed)
    _hud.cancel_pressed.connect(_on_cancel_pressed)
    _hud.march_pressed.connect(_march)
    _hud.recruit_pressed.connect(_recruit)
    _hud.hire_pressed.connect(_hire)
    _hud.begin_pressed.connect(_begin)
    _hud.retry_pressed.connect(_retry)
    _hud.restart_level_pressed.connect(_retry)
    _hud.restart_pressed.connect(_restart)
    _camera.follow_changed.connect(_hud.set_follow)
    _hud.set_volumes(Audio.volume(_hud.music_bus), Audio.volume(_hud.sound_bus))
    _hud.volume_changed.connect(Audio.set_volume)
    _world.camp_made.connect(_on_camp_made)
    _world.march_ordered.connect(_on_march_ordered)
    _world.night_changed.connect(_on_night_changed)
    _world.victory.connect(_on_victory, CONNECT_DEFERRED)
    _world.army_lost.connect(_lose.bind(lost_title, lost_text, lost_status), CONNECT_DEFERRED)
    _world.crew_lost.connect(_lose.bind(crew_lost_title, crew_lost_text, crew_lost_status), CONNECT_DEFERRED)
    _tools.select(0)
    var index := _take_start_level()
    GameState.new_campaign()
    _start_at_level(maxi(index, 0))
    if index >= 0:
        _begin()
    else:
        _set_paused(true)
        _hud.show_intro(true)


## The campaign index of the level the game was asked to start at (a level run on its own), or -1. A level not in
## the campaign becomes a campaign of its own.
func _take_start_level() -> int:
    var path := GameState.start_level
    GameState.start_level = ""
    if path.is_empty():
        return -1
    var index := GameState.campaign.levels.find(path)
    if index < 0:
        var only: Campaign = GameState.campaign.duplicate()
        only.levels = [path] as Array[String]
        GameState.campaign = only
        index = 0
    return index


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"pause"):
        _toggle_pause()
    elif event.is_action_pressed(&"speed"):
        _toggle_speed()
    elif event.is_action_pressed(&"march"):
        _march()
    elif event.is_action_pressed(&"recruit"):
        _recruit()
    elif event.is_action_pressed(&"restart_level"):
        _retry()
    elif event.is_action_pressed(&"cheat_instant_work"):
        _toggle_cheats()


## For testers: instant work (building and digging), and (turning on) plenty of every supply.
func _toggle_cheats() -> void:
    var rules := _world.crew.rules
    rules.instant_work = not rules.instant_work
    if rules.instant_work:
        var top_up := Supplies.new()
        for k in Supplies.KEYS:
            top_up.set(k, maxi(0, cheat_supplies - GameState.supplies.get(k)))
        var lead := _world.army.lead()
        _world.gain(top_up, lead.pos - Vector2(0, 2.6) if lead else Vector2.ZERO)
    var lead := _world.army.lead()
    if lead:
        Effects.say(Grid.to_px(lead.pos - Vector2(0, 2.0)), cheats_text % ("on" if rules.instant_work else "off"), Color("e9a93b"))


func _process(_delta: float) -> void:
    var lead := _world.army.lead()
    _hud.set_level(GameState.level_number(), floori(lead.pos.x) if lead else 0)
    _show_plans()
    _hud.set_march(_world.camping() and not _over)
    var rules := _world.army.rules
    var crew := _world.crew.rules
    var camp: Camp = _world.camp()
    var can_recruit := _world.army.soldiers.size() < rules.max_soldiers and GameState.supplies.can_afford(rules.recruit_cost)
    var can_hire := _world.crew.engineers.size() < crew.max_crew and GameState.supplies.can_afford(crew.hire_cost)
    _hud.set_shop(_world.shop_open() and not _over, rules.recruit_cost.gold, can_recruit,
            crew.hire_cost.gold, can_hire, _world.shop_spot() if camp else Vector2.ZERO, Grid.to_px(_camera.reach_m()))
    _update_status()
    _update_lead_marker(lead)
    _update_crew_marker()


func _begin() -> void:
    _hud.hide_cards()
    _tools.enabled = true
    _set_paused(false)


func _march() -> void:
    if not _over and not _hud.any_card_open():
        _world.march()


## Where a plan's buttons float (pixels): a little over its highest point, centred.
func _plan_spot(plan: Array) -> Vector2:
    var lo := INF
    var hi := -INF
    var top := INF
    for m: Bridge.Member in plan:
        for j: Bridge.Joint in [m.a, m.b]:
            lo = minf(lo, j.pos.x)
            hi = maxf(hi, j.pos.x)
            top = minf(top, j.pos.y)
    return Grid.to_px(Vector2((lo + hi) / 2, top - plan_button_rise))


## A Build button above each plan, a little over its highest point.
func _show_plans() -> void:
    _plans.clear()
    if not _over:
        _plans = _world.bridge.plans()
    var spots: Array = []
    var counts: Array = []
    for plan in _plans:
        spots.append(_plan_spot(plan))
        counts.append(plan.size())
    _hud.set_build_spots(spots, counts)


func _on_build_pressed(index: int) -> void:
    if index < _plans.size():
        _world.bridge.order_plan(_plans[index])


func _on_cancel_pressed(index: int) -> void:
    if index < _plans.size():
        var at := Grid.to_m(_plan_spot(_plans[index]))
        _world.gain(_world.bridge.cancel_plan(_plans[index]), at)


func _recruit() -> void:
    if not _over and not _hud.any_card_open():
        _world.recruit()


func _hire() -> void:
    if not _over and not _hud.any_card_open():
        _world.hire_engineer()


func _on_march_ordered(by_player: bool) -> void:
    _hud.banner(march_title, march_player_text if by_player else march_king_text)
    Audio.play(march_sound)
    Audio.play(GameState.campaign.dawn_sound)
    var c := _world.current_chunk()
    if c:
        Audio.play_music(c.level.music)


func _on_night_changed(night: bool, seconds: float) -> void:
    _day_night.set_night(night, false, seconds)
    if night and GameState.campaign.camp_music:
        Audio.play_music(GameState.campaign.camp_music)


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


func _on_tool_changed(index: int, material: BridgeMaterial) -> void:
    _hud.set_tool(index, material)


## Puts the column at the start of level index with the soldiers and supplies GameState holds.
func _start_at_level(index: int) -> void:
    _tools.cancel()
    _world.begin(index, GameState.soldiers, GameState.engineers)
    # The view starts on the column; following is the player's choice (Follow / C).
    _camera.follow = false
    _camera.center_on_lead()
    _over = false
    var c := _world.current_chunk()
    if not _world.at_camp():
        Audio.play_music(c.level.music)


func _on_camp_made(index: int, joined: int) -> void:
    var c := _world.chunk(index)
    var title := c.level.display_name if not c.level.display_name.is_empty() else arrival_title % (index + 1)
    _hud.banner(title, arrival_text % joined)
    Audio.play(GameState.campaign.level_up_sound)


func _on_victory() -> void:
    _over = true
    _over_status = victory_status
    _tools.enabled = false
    _set_paused(true)
    _hud.show_victory(victory_text % [GameState.campaign.levels.size(), GameState.soldiers])
    _hud.set_paused(true, false)
    Audio.play(GameState.campaign.victory_sound)


## The level is lost: title and text (with %d for the level) say why on the card, which comes after lost_delay;
## status says so in the status bar meanwhile.
func _lose(title: String, text: String, status: String) -> void:
    _over = true
    _over_status = status
    _tools.enabled = false
    _losses += 1
    var loss := _losses
    if lost_delay > 0.0:
        await get_tree().create_timer(lost_delay, true, false, true).timeout
    if not _over or loss != _losses:
        return
    _hud.show_lost(title, text % GameState.level_number())
    _set_paused(true)
    Audio.play(GameState.campaign.lost_sound)


## Restarts the current level from its checkpoint: column, supplies and the level as they were.
func _retry() -> void:
    _hud.hide_cards()
    GameState.retry()
    _start_at_level(GameState.level_index)
    _tools.enabled = true
    _set_paused(false)


func _restart() -> void:
    _hud.hide_cards()
    GameState.new_campaign()
    _start_at_level(0)
    _tools.enabled = true
    _set_paused(false)


func _update_status() -> void:
    var reason := _world.army.halt_reason
    var under_fire := false
    for o in _world.objects.get_children():
        if o is Archer and o.engaging:
            under_fire = true
            break
    if _over:
        _hud.set_status(_over_status, Hud.Mood.FIRE)
    elif get_tree().paused and _hud.any_card_open():
        # Paused for a card (the intro). A plain pause shows the PAUSED tag, and the status carries on as below.
        _hud.set_status("Awaiting orders", Hud.Mood.HALT)
    elif _world.camping():
        _hud.set_status(patience_text % ceili(_world.march_left()), Hud.Mood.HALT)
    elif _world.at_camp():
        _hud.set_status(morning_text, Hud.Mood.HALT)
    elif under_fire:
        _hud.set_status("Under fire · %s" % reason if reason else "Under fire", Hud.Mood.FIRE)
    elif reason:
        _hud.set_status("Halted · %s" % reason, Hud.Mood.HALT)
    elif not _world.army.danger.is_empty():
        _hud.set_status(danger_text % _world.army.danger, Hud.Mood.FIRE)
    else:
        _hud.set_status("Marching", Hud.Mood.NORMAL)


func _update_lead_marker(lead: Soldier) -> void:
    if lead == null:
        _hud.set_lead_marker(0, 0)
        return
    var screen := _world.get_viewport().get_canvas_transform() * lead.position
    _hud.set_lead_marker(_off_screen_side(screen), screen.y - Grid.PX)


## Points the red arrow at the nearest engineer off screen, if any is.
func _update_crew_marker() -> void:
    var w := _world.get_viewport().get_visible_rect().size.x
    var best := Vector2.INF
    var best_off := INF
    for e in _world.crew.engineers:
        var screen := _world.get_viewport().get_canvas_transform() * Grid.to_px(e.pos)
        var off := maxf(-screen.x, screen.x - w)
        if off > 0.0 and off < best_off:
            best_off = off
            best = screen
    if best_off == INF:
        _hud.set_crew_marker(0, 0)
        return
    _hud.set_crew_marker(_off_screen_side(best), best.y - Grid.PX)


## Which side of the screen a screen position is off: -1 left, 1 right, 0 on screen.
func _off_screen_side(screen: Vector2) -> int:
    var w := _world.get_viewport().get_visible_rect().size.x
    return 1 if screen.x > w else (-1 if screen.x < 0 else 0)
