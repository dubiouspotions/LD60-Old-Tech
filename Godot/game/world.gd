class_name World
extends Node2D
## One continuous world built from the campaign's level scenes. Each level is stitched on so its StartFlag meets
## the previous level's ExitFlag. The next level streams in on a background thread as the view nears the end of
## the ground; levels far behind the column and the view are unloaded.
## At every level start the column camps. Dusk: the column closes up to the camp and lies down as night falls.
## Night: it sleeps while the engineers keep working, until the player orders the march or the king loses
## patience (the level's march_delay, counted from arrival). Morning: day breaks and the column gets up and
## breaks camp, then marches.

signal army_lost
## The column starts marching: ordered by the player, or by the king when his patience runs out.
signal march_ordered(by_player: bool)
## The column reached level index and made camp. joined soldiers arrived with the supplies.
signal camp_made(index: int, joined: int)
## Night falls over seconds at dusk, and day breaks over seconds in the morning.
signal night_changed(night: bool, seconds: float)
## The front soldier passed the last level's exit.
signal victory
signal level_streamed(index: int)

enum Phase { DAY, DUSK, NIGHT, MORNING }


## One stitched level.
class Chunk:
	var index: int
	## The level scene's root, kept for its settings (music, march delay, ...). Not in the tree.
	var level: Level
	## Cells added to the level scene's coordinates.
	var offset: Vector2i
	## First world column this level owns.
	var seam: int
	var start_flag: CheckpointFlag
	var exit_flag: CheckpointFlag
	## Objects that came with the level (archers, ...).
	var owned: Array[Node] = []

	## First world column of the next level.
	func end() -> int:
		return floori(exit_flag.metres().x)


@export var falling_block_scene: PackedScene
## Pitched at the camp flag while the column sleeps. Needs a strike() method that removes it.
@export var camp_scene: PackedScene
## Load the next level when the view's right edge comes this close to the end of the ground.
@export_range(5.0, 500.0, 1.0, "suffix:m") var stream_ahead: float = 60.0
## Unload a level once its end is this far behind both the rear soldier and the view's left edge.
@export_range(5.0, 500.0, 1.0, "suffix:m") var unload_behind: float = 40.0
## Seconds from arriving at camp to full night: the column closes up and lies down meanwhile.
@export_range(0.0, 30.0, 0.5, "suffix:s") var dusk_time: float = 4.0
## Seconds from the march order to the march: day breaks, the column gets up and breaks camp.
@export_range(0.0, 30.0, 0.5, "suffix:s") var morning_time: float = 2.5

@onready var terrain: Terrain = %Terrain
@onready var bridge: Bridge = %Bridge
@onready var army: Army = %Army
@onready var crew: Crew = %Crew
## Falling blocks, charges, arrows and the levels' objects.
@onready var objects: Node2D = %Objects
@onready var flags: Node2D = %Flags

## Campaign index of the level the column is in, -1 before begin().
var current: int = -1

var _chunks: Dictionary = {} # index -> Chunk
## index -> [offset, seam], so a rewound level lands where it was.
var _placements: Dictionary = {}
var _loading: int = -1
var phase: Phase = Phase.DAY
var _march_left: float = 0.0
var _phase_left: float = 0.0
var _done: bool = false
var _camp: Node2D


static func of(node: Node) -> World:
	while node and not node is World:
		node = node.get_parent()
	return node as World


func _ready() -> void:
	bridge.terrain = terrain
	army.terrain = terrain
	army.bridge = bridge
	crew.terrain = terrain
	crew.bridge = bridge
	crew.army = army
	terrain.tile_detached.connect(_on_tile_detached)
	terrain.collapsed.connect(func(found: Supplies, _cells: Array[Vector2i]) -> void: GameState.gain(found))
	bridge.member_broken.connect(_on_member_broken)
	crew.dig_finished.connect(_on_dig_finished)
	army.count_changed.connect(_on_army_count)


func chunk(index: int) -> Chunk:
	return _chunks.get(index)


func current_chunk() -> Chunk:
	return chunk(current)


## The camp while the column sleeps, else null.
func camp() -> Node2D:
	return _camp if is_instance_valid(_camp) else null


## Starts (or restarts) the column at level index with soldiers: everything from that level on is put back
## as designed, and the column camps at its start flag.
func begin(index: int, soldiers: int) -> void:
	_done = false
	if index == 0 or not _placements.has(index):
		_wipe()
	rewind(index)
	current = index
	GameState.level_index = index
	var c := chunk(index)
	c.start_flag.reached = true
	start_at(c.start_flag.metres().x, soldiers, c.level.march_delay)


## Puts the column and the crew at x and camps for march_delay seconds (0 marches at once).
func start_at(x: float, soldiers: int, march_delay: float) -> void:
	army.spawn(soldiers, x)
	crew.spawn(x)
	_make_camp(x, march_delay)


## Removes level index and everything after it, then places index again as designed.
func rewind(index: int) -> void:
	var seam: int = _placements[index][1] if _placements.has(index) else terrain.min_x
	var later: Array = _chunks.keys().filter(func(i: int) -> bool: return i >= index)
	later.sort()
	later.reverse()
	for i: int in later:
		_drop(i, i > index)
	terrain.clear_from(seam)
	bridge.remove_outside(-INF, seam)
	_free_objects(func(x: float) -> bool: return x >= seam)
	_strike_camp()
	place_now(index)


## Loads and stitches level index now, on this thread.
func place_now(index: int) -> Chunk:
	if chunk(index):
		return chunk(index)
	return _place(index, load(GameState.campaign.levels[index]))


## Starts loading level index on a background thread. It is stitched on when ready.
func request(index: int) -> void:
	if _loading >= 0 or chunk(index) or index >= GameState.campaign.levels.size():
		return
	ResourceLoader.load_threaded_request(GameState.campaign.levels[index], "PackedScene")
	_loading = index


## Removes level index from the world. Only for the oldest level, behind the column.
func unload(index: int) -> void:
	var c := chunk(index)
	if c == null:
		return
	var edge := c.end()
	terrain.unload_before(edge)
	bridge.remove_outside(edge, INF)
	_free_objects(func(x: float) -> bool: return x < edge)
	_drop(index, true)


## Buys one soldier with gold while the column camps; it joins the camp. Returns false when not camping,
## short of gold, or at the army limit.
func recruit() -> bool:
	var rules := army.rules
	if not camping() or army.soldiers.size() >= rules.max_soldiers or not GameState.spend(rules.recruit_cost):
		return false
	army.reinforce(1)
	var at := army.rear().pos
	Audio.play(rules.recruit_sound, Grid.to_px(at))
	Effects.say(Grid.to_px(at - Vector2(0, 1.4)), rules.recruit_text, Color("ece4d2"))
	return true


## Orders the column to march now, before the king does.
func march() -> void:
	_order_march(true)


## Seconds until the king orders the march, or 0 when not camping.
func march_left() -> float:
	return maxf(_march_left, 0.0) if camping() else 0.0


## At camp before the march order (dusk or night).
func camping() -> bool:
	return phase == Phase.DUSK or phase == Phase.NIGHT


## At camp, from dusk until the column marches off in the morning.
func at_camp() -> bool:
	return phase != Phase.DAY


func _physics_process(dt: float) -> void:
	if _done:
		return
	_advance_phase(dt)
	bridge.step(dt, army.bridge_loads())
	army.foes = objects.get_children().filter(func(o: Node) -> bool: return o is Archer and o.alive())
	army.step(dt)
	crew.step(dt)
	_check_exit()


func _process(_delta: float) -> void:
	if current < 0:
		return
	_poll_loading()
	_stream()


func _check_exit() -> void:
	var lead := army.lead()
	var c := current_chunk()
	if lead == null or c == null or _done or lead.pos.x < c.exit_flag.metres().x:
		return
	var next := current + 1
	if next >= GameState.campaign.levels.size():
		_done = true
		c.exit_flag.reached = true
		victory.emit()
		return
	if chunk(next) == null:
		request(next)
		return
	_arrive(next)


func _arrive(index: int) -> void:
	var c := chunk(index)
	current = index
	c.start_flag.reached = true
	var joined := GameState.arrive(index, c.level.reinforcements, c.level.supply_drop)
	army.reinforce(joined)
	_make_camp(c.start_flag.metres().x, c.level.march_delay)
	camp_made.emit(index, joined)


## Pitches camp at x for delay seconds (0 marches on without camping).
func _make_camp(x: float, delay: float) -> void:
	_strike_camp()
	_march_left = delay
	if delay <= 0.0:
		_set_day()
		night_changed.emit(false, 0.0)
		return
	phase = Phase.DUSK
	_phase_left = dusk_time
	army.hold = false
	army.camp_x = x
	army.resting = true
	if camp_scene:
		_camp = camp_scene.instantiate()
		_camp.position = Grid.to_px(Vector2(x, terrain.surface_row(floori(x))))
		objects.add_child(_camp)
	night_changed.emit(true, dusk_time)


func _advance_phase(dt: float) -> void:
	if phase == Phase.DAY:
		return
	_phase_left -= dt
	if camping():
		_march_left -= dt
		if phase == Phase.DUSK and _phase_left <= 0.0:
			phase = Phase.NIGHT
		if _march_left <= 0.0:
			_order_march(false)
	elif phase == Phase.MORNING and _phase_left <= 0.0:
		_set_day()


## Morning: everyone gets up while day breaks; the march starts when the morning is over.
func _order_march(by_player: bool) -> void:
	if not camping():
		return
	phase = Phase.MORNING
	_phase_left = morning_time
	army.resting = false
	army.hold = true
	_strike_camp()
	night_changed.emit(false, morning_time)
	march_ordered.emit(by_player)
	if morning_time <= 0.0:
		_set_day()


func _set_day() -> void:
	phase = Phase.DAY
	army.hold = false
	army.resting = false
	army.camp_x = NAN


func _strike_camp() -> void:
	if camp():
		_camp.call(&"strike")
	_camp = null


## Requests the next level when the view nears the end, unloads levels far behind.
func _stream() -> void:
	var view := _view_m()
	var last := current
	while chunk(last + 1):
		last += 1
	if chunk(last) and view.end.x >= terrain.size.x - stream_ahead:
		request(last + 1)
	var rear := army.rear()
	var behind := minf(view.position.x, rear.pos.x if rear else view.position.x) - unload_behind
	for i: int in _chunks.keys():
		if i < current and chunk(i).end() < behind and not _chunks.has(i - 1):
			unload(i)


func _poll_loading() -> void:
	if _loading < 0:
		return
	var path: String = GameState.campaign.levels[_loading]
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var index := _loading
	_loading = -1
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("World: could not load %s" % path)
		return
	var scene: PackedScene = ResourceLoader.load_threaded_get(path)
	if chunk(index) == null and (chunk(index - 1) or _placements.has(index)):
		_place(index, scene)


## Stitches a level scene onto the world.
func _place(index: int, scene: PackedScene) -> Chunk:
	var lv: Level = scene.instantiate()
	var c := Chunk.new()
	c.index = index
	c.level = lv
	var start := lv.start_flag()
	var prev := chunk(index - 1)
	if _placements.has(index):
		c.offset = _placements[index][0]
		c.seam = _placements[index][1]
	elif prev:
		c.seam = prev.end()
		var meet := Grid.cell_of(prev.exit_flag.metres())
		c.offset = Vector2i(c.seam - floori(start.metres().x), meet.y - roundi(start.metres().y))
	else:
		c.offset = Vector2i(terrain.min_x, 0)
		c.seam = terrain.min_x
	_placements[index] = [c.offset, c.seam]
	terrain.stamp(lv.terrain(), c.offset, c.seam)
	var shift := Grid.to_px(Vector2(c.offset))
	if prev:
		c.start_flag = prev.exit_flag
		start.free()
	else:
		c.start_flag = _adopt(start, shift)
	c.exit_flag = _adopt(lv.exit_flag(), shift)
	c.start_flag.label = "L%d" % (index + 1)
	c.exit_flag.label = "L%d" % (index + 2)
	for o in lv.objects().get_children():
		if o is Node2D and floori((o.position.x + shift.x) / Grid.PX) >= c.seam:
			c.owned.append(_adopt(o, shift, objects))
		else:
			o.free()
	_chunks[index] = c
	level_streamed.emit(index)
	return c


## Moves a node out of a level scene into the world, shifted by shift pixels.
func _adopt(n: Node2D, shift: Vector2, into: Node = null) -> Node2D:
	n.get_parent().remove_child(n)
	n.owner = null
	n.position += shift
	(into if into else flags).add_child(n)
	return n


## Forgets a level and frees what came with it. A flag shared with a neighbouring level stays.
## forget_place false keeps where it was stitched on, so placing it again puts it back there.
func _drop(index: int, forget_place: bool) -> void:
	var c := chunk(index)
	for o in c.owned:
		if is_instance_valid(o):
			o.queue_free()
	var prev := chunk(index - 1)
	var next := chunk(index + 1)
	if not (prev and c.start_flag == prev.exit_flag):
		c.start_flag.queue_free()
	if not (next and c.exit_flag == next.start_flag):
		c.exit_flag.queue_free()
	c.level.free()
	_chunks.erase(index)
	if forget_place:
		_placements.erase(index)


func _wipe() -> void:
	for i: int in _chunks.keys():
		_drop(i, true)
	_placements.clear()
	_loading = -1
	terrain.clear()
	terrain.rebuild()
	bridge.clear()
	_free_objects(func(_x: float) -> bool: return true)
	for f in flags.get_children():
		f.queue_free()
	_strike_camp()
	Effects.clear()


func _free_objects(hit: Callable) -> void:
	for o in objects.get_children():
		if o is Node2D and hit.call(o.position.x / Grid.PX):
			o.queue_free()


## The camera's view in metres, or the column's span when there is no camera.
func _view_m() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam:
		var size := get_viewport_rect().size / cam.zoom
		return Rect2(Grid.to_m(cam.get_screen_center_position() - size / 2), Grid.to_m(size))
	var lead := army.lead()
	var rear := army.rear()
	return Rect2(rear.pos.x if rear else 0.0, 0, (lead.pos.x - rear.pos.x) if lead else 0.0, 0)


func _on_army_count(count: int) -> void:
	GameState.set_soldiers(count)
	if count == 0 and not _done:
		_done = true
		army_lost.emit()


func _on_tile_detached(cell: Vector2i, type: TerrainType) -> void:
	if falling_block_scene == null:
		return
	var block: FallingBlock = falling_block_scene.instantiate()
	block.type = type
	block.position = Grid.to_px(Vector2(cell))
	objects.add_child(block)


## An engineer finished digging a marked cell: take the tile and its supplies.
func _on_dig_finished(cell: Vector2i) -> void:
	var here := terrain.type_at(cell)
	var got := terrain.dig(cell)
	if got == null:
		return
	GameState.gain(got)
	var at := Grid.to_px(Vector2(cell) + Vector2(0.5, 0))
	if here.dig_action == TerrainType.DigAction.FELL:
		Effects.say(at, got.describe(), Color("ece4d2"))
	else:
		Effects.say(at, here.dig_text, here.debris_color)


func _on_member_broken(member: Bridge.Member, text: String) -> void:
	Effects.say(Grid.to_px((member.a.pos + member.b.pos) / 2 - Vector2(0, 0.6)), text, Color("ff6a55"))
