class_name MenuShow
extends Node2D
## The main menu's backdrop, played on a real World: engineers walk in with the column and build a bridge over a
## ravine while the column waits at its edge; it marches onto it, the bridge gives way and the soldiers fall into the depths. Once the last has
## fallen or crossed, what is left of the bridge drops after them, and after a rest the next act (MenuAct) begins.
## The acts loop.
## The view is the Camera node; move it in the scene to frame the ravine.

enum Stage { BUILD, CROSS, GIVE_WAY, FALL, LINGER, REST }

## The level the show is played on.
@export_file("*.tscn") var level: String = "res://menu/menu_level.tscn"
@export var acts: Array[MenuAct] = []
## While the bridge is going up, the column waits this far short of its near end.
@export_range(0.0, 10.0, 0.1, "suffix:m") var wait_short: float = 0.3
## Seconds between the last soldier falling or crossing and the rest of the bridge falling.
@export_range(0.0, 20.0, 0.1, "suffix:s") var linger: float = 1.5
## Seconds the ravine lies empty before the next crew comes.
@export_range(0.0, 30.0, 0.1, "suffix:s") var rest: float = 3.0
## An act that has not ended after this long (the crew got stuck, say) is cut short.
@export_range(10.0, 600.0, 1.0, "suffix:s") var act_timeout: float = 120.0
## Where the sun stands (see Sun.progress).
@export_range(-0.2, 1.2, 0.01) var sun: float = 0.3

@onready var world: World = %World
@onready var camera: Camera2D = %Camera

## Index into acts of the act being played, -1 before the first.
var act_index: int = -1
var stage: Stage = Stage.REST
## The current act's bridge members, in the order of its Pieces.
var members: Array[Bridge.Member] = []
var _act: MenuAct
var _campaign: Campaign
var _act_time: float = 0.0
var _stage_time: float = 0.0
## How many of the act's Breaks have been broken.
var _broke: int = 0
## The bridge's near and far end (x, metres).
var _span: Vector2


func _exit_tree() -> void:
	GameState.campaign = _campaign


func _ready() -> void:
	# The World plays GameState's campaign, so the show swaps in one of its own level, and gives it back on leaving.
	# Not before now: as the game's first scene the show enters the tree before GameState has loaded the campaign.
	_campaign = GameState.campaign
	var show: Campaign = _campaign.duplicate()
	show.levels = [level] as Array[String]
	GameState.campaign = show
	($Background/SunPixel2 as Sun).progress = sun
	if not acts.is_empty():
		next_act()


## Starts the next act (after the last, the first again).
func next_act() -> void:
	act_index = (act_index + 1) % acts.size()
	play(acts[act_index])


## Starts act from the top: the crew and the column walk in, and the column waits at the ravine's edge while the
## crew builds.
func play(act: MenuAct) -> void:
	_act = act
	_act_time = 0.0
	_broke = 0
	world.begin(0, act.soldiers, act.engineers)
	var bridge := world.bridge
	members.clear()
	_span = Vector2(INF, -INF)
	for p in act.pieces:
		var m := bridge.build(bridge.snap_point(p.from), bridge.snap_point(p.to), p.material, true)
		members.append(m)
		_span = Vector2(minf(_span.x, minf(m.a.pos.x, m.b.pos.x)), maxf(_span.y, maxf(m.a.pos.x, m.b.pos.x)))
	bridge.order_blueprints()
	world.army.stop_x = _span.x - wait_short
	_enter(Stage.BUILD)


func _physics_process(dt: float) -> void:
	if _act == null:
		return
	_act_time += dt
	_stage_time += dt
	if _act_time > act_timeout:
		next_act()
		return
	match stage:
		Stage.BUILD:
			if _standing():
				world.army.stop_x = world.current_chunk().exit_flag.metres().x
				_enter(Stage.CROSS)
		Stage.CROSS:
			if _giving_way() or army_gone() or members.any(func(m: Bridge.Member) -> bool: return m.dead):
				_enter(Stage.GIVE_WAY)
		Stage.GIVE_WAY:
			if _broke >= _act.breaks.size():
				_enter(Stage.FALL)
			elif _broke == 0 or _stage_time >= _act.break_stagger:
				var i := _act.breaks[_broke]
				_broke += 1
				_stage_time = 0.0
				if i >= 0 and i < members.size() and not members[i].dead:
					_snap(members[i])
		Stage.FALL:
			if army_gone():
				_enter(Stage.LINGER)
		Stage.LINGER:
			if _stage_time >= linger:
				# Unbolted, what is left of the bridge drops into the ravine after the column.
				for j in world.bridge.nodes:
					j.pinned = false
				_enter(Stage.REST)
		Stage.REST:
			if _stage_time >= rest:
				next_act()


## Soldiers standing on the bridge.
func on_bridge() -> int:
	return world.army.soldiers.reduce(func(n: int, s: Soldier) -> int: return n + int(s.on_member != null and not s.dead), 0)


## Every soldier has fallen or marched out of view on the far side.
func army_gone() -> bool:
	var right := Grid.to_m(camera.get_screen_center_position() + get_viewport_rect().size / camera.zoom / 2.0).x
	return world.army.soldiers.all(func(s: Soldier) -> bool: return s.dead or s.pos.x > right + 1.0)


## The act's load is on the bridge: enough soldiers on it, the front one far enough across.
func _giving_way() -> bool:
	var lead := world.army.lead()
	return lead != null and on_bridge() >= _act.give_way_at and lead.pos.x >= lerpf(_span.x, _span.y, _act.give_way_past)


func _enter(s: Stage) -> void:
	stage = s
	_stage_time = 0.0


## Every piece is built and off its scaffolding (or broken already).
func _standing() -> bool:
	return members.all(func(m: Bridge.Member) -> bool: return m.dead or not (m.blueprint or m.scaffolded))


## Breaks a piece with its sound and debris, but without the floating message the game shows.
func _snap(m: Bridge.Member) -> void:
	Audio.play(m.material.break_sound, Grid.to_px((m.a.pos + m.b.pos) / 2))
	world.bridge.break_member(m, true)
