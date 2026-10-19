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
## The last engineer died: the level is lost.
signal crew_lost
## The column starts marching: ordered by the player, or by the king when his patience runs out.
signal march_ordered(by_player: bool)
## The column reached level index and made camp. joined soldiers arrived with the supplies.
signal camp_made(index: int, joined: int)
## Night falls over seconds at dusk, and day breaks over seconds in the morning.
signal night_changed(night: bool, seconds: float)
## The front soldier passed the last level's exit.
signal victory
signal level_streamed(index: int)

## A body (soldier or archer) for bridge hits: a circle this high above the feet with this radius, metres.
const BODY_MID: float = 0.9
const BODY_RADIUS: float = 0.6
## Colour of the "+N ..." text when supplies are gained.
const GAIN_COLOR: Color = Color("ece4d2")

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
## Flies what an engineer throws (a sandbag) to its cell.
@export var thrown_scene: PackedScene
## Drops a tower or tree whose ground was taken away.
@export var falling_piece_scene: PackedScene
## A razed tower comes down a column at a time, left to right, each this many seconds after the one before.
@export_range(0.0, 1.0, 0.01, "suffix:s") var collapse_stagger: float = 0.06
## Pitched at the camp flag while the column sleeps. Needs a strike() method that removes it.
@export var camp_scene: PackedScene
## While camping, load one more level when the view's right edge comes this close to the end of the ground.
@export_range(5.0, 500.0, 1.0, "suffix:m") var stream_ahead: float = 60.0
## Unload a level once its end is this far behind both the rear soldier and the view's left edge.
@export_range(5.0, 500.0, 1.0, "suffix:m") var unload_behind: float = 40.0
## Seconds from arriving at camp to full night: the column closes up and lies down meanwhile.
@export_range(0.0, 30.0, 0.5, "suffix:s") var dusk_time: float = 4.0
## Seconds from the march order to the march: day breaks, the column gets up and breaks camp.
@export_range(0.0, 30.0, 0.5, "suffix:s") var morning_time: float = 2.5
## How far the sun is below the horizon at night, in shares of its day (see sun_progress).
@export_range(0.0, 0.5, 0.01) var sun_below: float = 0.2

@onready var terrain: Terrain = %Terrain
@onready var bridge: Bridge = %Bridge
@onready var army: Army = %Army
@onready var crew: Crew = %Crew
## Falling blocks, arrows, the camp and the levels' objects.
@onready var objects: Node2D = %Objects
@onready var flags: Node2D = %Flags
@onready var grass: TallGrass = %Grass
## Holds the levels' fireflies swarms, above the night grade (DayNight fades them in).
@onready var fireflies: FireflyLayer = %Fireflies
## Pollen drifting on the wind by day (DayNight fades it out at night).
@onready var pollen: Pollen = %Pollen
## Birds hiding in the tall grass.
@onready var birds: Birds = %Birds
## Leaves bursting from felled trees.
@onready var leaves: LeafPoof = %Leaves
## Pieces of wood from felled trees, waiting to be picked up by the crew.
@onready var wood: Wood = %Wood

## Campaign index of the level the column is in, -1 before begin().
var current: int = -1

var _chunks: Dictionary = {} # index -> Chunk
## index -> [offset, seam], so a rewound level lands where it was.
var _placements: Dictionary = {}
var _loading: int = -1
## A level asked for while another was loading: requested once that one is in, or -1.
var _queued: int = -1
var phase: Phase = Phase.DAY
var _march_left: float = 0.0
var _phase_left: float = 0.0
var _done: bool = false
var _camp: Node2D
## The pieces of wood the last tree to come down dropped.
var _dropped: Array[Wood.Piece] = []


static func of(node: Node) -> World:
	while node and not node is World:
		node = node.get_parent()
	return node as World


func _ready() -> void:
	bridge.terrain = terrain
	grass.terrain = terrain
	army.terrain = terrain
	army.bridge = bridge
	crew.terrain = terrain
	crew.bridge = bridge
	crew.army = army
	crew.wood = wood
	crew.picked_up.connect(_on_picked_up)
	army.struck.connect(_on_struck)
	terrain.tile_detached.connect(_on_tile_detached)
	crew.chopped.connect(func(cell: Vector2i) -> void:
		leaves.shake(cell)
		birds.chop(cell))
	terrain.drops_loose = falling_piece_scene != null
	terrain.came_loose.connect(func(tiles: Dictionary) -> void: _drop_piece(tiles, false))
	terrain.razed.connect(_on_razed)
	terrain.felled.connect(_on_felled)
	terrain.collapsed.connect(func(found: Supplies, cells: Array[Vector2i]) -> void: gain(found, _top_of(cells)))
	bridge.member_broken.connect(_on_member_broken)
	bridge.struck.connect(_on_bridge_struck)
	crew.dig_finished.connect(_on_dig_finished)
	crew.threw.connect(_on_threw)
	crew.dismantled.connect(func(m: Bridge.Member) -> void: gain(bridge.take_apart(m), (m.a.pos + m.b.pos) / 2.0 - Vector2(0, 0.6)))
	army.count_changed.connect(_on_army_count)
	crew.count_changed.connect(_on_crew_count)


func chunk(index: int) -> Chunk:
	return _chunks.get(index)


## How far through its day the sun is (Sun.progress): 0 at dawn, 1 at sunset, going by the leader's way from the
## level's start flag to its exit flag. It rises from sun_below under the horizon while the column breaks camp,
## sinks back there at dusk, and stays down all night.
func sun_progress() -> float:
	match phase:
		Phase.NIGHT:
			return 1.0 + sun_below
		Phase.DUSK:
			return 1.0 + sun_below * (1.0 - _phase_left / dusk_time if dusk_time > 0.0 else 1.0)
		Phase.MORNING:
			return -sun_below * (_phase_left / morning_time if morning_time > 0.0 else 0.0)
	var c := current_chunk()
	var lead := army.lead()
	if c == null or lead == null:
		return 0.5
	var start := c.start_flag.metres().x
	return clampf((lead.pos.x - start) / maxf(c.exit_flag.metres().x - start, 0.01), 0.0, 1.0)


## The level that owns world column x (the last one whose seam is at or left of it), or null.
func chunk_at(x: float) -> Chunk:
	var best: Chunk = null
	for c: Chunk in _chunks.values():
		if c.seam <= x and (best == null or c.seam > best.seam):
			best = c
	return best


func current_chunk() -> Chunk:
	return chunk(current)


## The camp while the column sleeps, else null.
func camp() -> Node2D:
	return _camp if is_instance_valid(_camp) else null


## The Camp Shoppe is open: camped at a level that has one (Level.camp_shoppe), once a tent is up.
func shop_open() -> bool:
	var c := chunk(current)
	return camping() and camp() != null and c != null and c.level.camp_shoppe 			and army.soldiers.any(func(s: Soldier) -> bool: return s.sleeping)


## Where the Camp Shoppe button hangs (world pixels): under the camp, below the lowest tent of the sleeping column.
func shop_spot() -> Vector2:
	var lowest := -INF
	for s: Soldier in army.soldiers:
		if s.sleeping:
			lowest = maxf(lowest, s.tent_bottom())
	return (camp() as Camp).button_spot(lowest)


## Starts (or restarts) the column at level index with soldiers: everything from that level on is put back
## as designed, and the column camps at its start flag. If the level behind was unloaded, it is put back too (as
## designed), so the camp has ground behind it and the view can pan back over it, as on arrival.
func begin(index: int, soldiers: int, engineers: int = 0) -> void:
	_done = false
	if index == 0 or not _placements.has(index):
		_wipe()
	elif chunk(index - 1) == null and _placements.has(index - 1):
		var keep := {index - 1: _placements[index - 1], index: _placements[index]}
		_wipe()
		_placements = keep
		terrain.unload_before(keep[index - 1][1])
		place_now(index - 1)
	rewind(index)
	current = index
	GameState.level_index = index
	var c := chunk(index)
	c.start_flag.reached = true
	start_at(c.start_flag.metres().x, soldiers, c.level.march_delay, engineers)
	army.stop_x = c.exit_flag.metres().x
	request(index + 1)


## Puts the column and the crew (engineers; 0: the crew's own starting size) at x and camps for march_delay
## seconds (0 marches at once).
func start_at(x: float, soldiers: int, march_delay: float, engineers: int = 0) -> void:
	army.spawn(soldiers, x)
	crew.spawn(x, engineers)
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
	grass.clear_from(seam)
	wood.clear_from(seam)
	birds.forget_from(seam)
	bridge.remove_outside(-INF, seam)
	_free_objects(func(x: float) -> bool: return x >= seam)
	_strike_camp()
	place_now(index)


## Loads and stitches level index now, on this thread.
func place_now(index: int) -> Chunk:
	if chunk(index):
		return chunk(index)
	return _place(index, load(GameState.campaign.levels[index]))


## Starts loading level index on a background thread (on the main thread where there are no threads, as on the
## web). It is stitched on when ready. Asked for at every checkpoint (see begin and _arrive), so the hitch of
## loading and stitching falls at the camp rather than in the middle of the march.
func request(index: int) -> void:
	if index == _loading or chunk(index) or index >= GameState.campaign.levels.size():
		return
	if _loading >= 0:
		_queued = index
		return
	ResourceLoader.load_threaded_request(GameState.campaign.levels[index], "PackedScene")
	_loading = index


## Level index is loading in the background, or waiting to load once the one loading is in.
func requested(index: int) -> bool:
	return index >= 0 and (index == _loading or index == _queued)


## Removes level index from the world. Only for the oldest level, behind the column.
func unload(index: int) -> void:
	var c := chunk(index)
	if c == null:
		return
	var edge := c.end()
	terrain.unload_before(edge)
	grass.unload_before(edge)
	wood.clear_before(edge)
	birds.forget_before(edge)
	bridge.remove_outside(edge, INF)
	_free_objects(func(x: float) -> bool: return x < edge)
	# Where it was placed is kept: a restart at the next level puts it back there.
	_drop(index, false)


## Buys one soldier with gold while the column camps; it joins the camp. Returns false when not camping,
## short of gold, or at the army limit.
func recruit() -> bool:
	var rules := army.rules
	if not camping() or army.soldiers.size() >= rules.max_soldiers or not GameState.spend(rules.recruit_cost):
		return false
	army.reinforce(1, army.camp_x)
	var at := army.rear().pos
	Audio.play(rules.recruit_sound, Grid.to_px(at))
	Effects.say(Grid.to_px(at - Vector2(0, 1.4)), rules.recruit_text, Color("ece4d2"))
	return true


## Hires one engineer with gold while the column camps; it joins the crew at the camp. Returns false when not
## camping, short of gold, or at the crew limit.
func hire_engineer() -> bool:
	var rules := crew.rules
	if not camping() or crew.engineers.size() >= rules.max_crew or not GameState.spend(rules.hire_cost):
		return false
	var at := Grid.to_m(_camp.position) if _camp else army.rear().pos
	crew.hire(at.x)
	Audio.play(rules.hire_sound, Grid.to_px(at))
	Effects.say(Grid.to_px(at - Vector2(0, 1.4)), rules.hire_text, Color("ece4d2"))
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
	_advance_phase(dt)
	army.foes = objects.get_children().filter(func(o: Node) -> bool: return o is Archer and o.alive())
	# A block that landed or broke is freed only at the end of the frame; it must not fall on meanwhile.
	var blocks := objects.get_children().filter(func(o: Node) -> bool: return o is FallingBlock and not o.is_queued_for_deletion())
	var bodies := _bodies(blocks)
	_step_bridge(dt, bodies, blocks)
	# What is thrown, and harmless blocks (sandbags), break on engineers too.
	var with_crew := bodies + _crew_bodies()
	for b: FallingBlock in blocks:
		b.step(dt, self, with_crew if b.harmless else bodies)
	for o: Node in objects.get_children():
		if o is ThrownBag and not o.is_queued_for_deletion():
			(o as ThrownBag).step(dt, self, with_crew)
	_crush_under_weight(bodies, blocks)
	for p: FallingPiece in objects.get_children().filter(func(o: Node) -> bool: return o is FallingPiece and not o.is_queued_for_deletion()):
		p.step(dt, self)
	var down := collapsing()
	army.wait_reason = army.rules.collapse_text if down else ""
	crew.wait = down
	army.step(dt)
	crew.step(dt)
	_check_exit()


func _process(_delta: float) -> void:
	if current < 0:
		return
	_poll_loading()
	_stream()


## The level ends when every living soldier has gathered at its exit flag, not just the front one.
func _check_exit() -> void:
	var c := current_chunk()
	if c == null or _done or not army.gathered():
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


## Testing cheat: ends the level as if every soldier had gathered at its exit flag. The column and the crew are
## put at the next level's camp and arrive there (reinforcements, supply drop, checkpoint); on the last level the
## campaign is won.
func skip_level() -> void:
	if _done or current < 0:
		return
	var next := current + 1
	if next >= GameState.campaign.levels.size():
		_done = true
		current_chunk().exit_flag.reached = true
		victory.emit()
		return
	var x := place_now(next).start_flag.metres().x
	army.spawn(army.soldiers.size(), x)
	crew.spawn(x, crew.engineers.size())
	_arrive(next)


func _arrive(index: int) -> void:
	var c := chunk(index)
	current = index
	c.start_flag.reached = true
	var drop := c.level.drop()
	var joined := GameState.arrive(index, c.level.joining(), drop)
	_show_gain(drop, c.start_flag.metres() - Vector2(0, 2.0))
	army.reinforce(joined)
	army.stop_x = c.exit_flag.metres().x
	_make_camp(c.start_flag.metres().x, c.level.march_delay)
	camp_made.emit(index, joined)
	request(index + 1)


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


## Requests the next level when the view nears the end while the column camps (by day that waits for the next
## camp, or for the column needing it at the exit flag), and unloads levels far behind.
func _stream() -> void:
	var view := _view_m()
	var last := current
	while chunk(last + 1):
		last += 1
	if at_camp() and chunk(last) and view.end.x >= terrain.size.x - stream_ahead:
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
	var queued := _queued
	_queued = -1
	if queued >= 0:
		request(queued)


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
	grass.stamp(lv.grass(), c.offset, c.seam)
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
			c.owned.append(_adopt(o, shift, fireflies if o is Fireflies else objects))
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
	grass.clear()
	wood.clear_all()
	birds.clear()
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


## The level is lost when the last engineer dies, as when the last soldier does.
func _on_crew_count(count: int) -> void:
	GameState.engineers = count
	if count == 0 and not _done:
		_done = true
		crew_lost.emit()


func _on_tile_detached(cell: Vector2i, type: TerrainType) -> void:
	if falling_block_scene == null:
		return
	var block: FallingBlock = falling_block_scene.instantiate()
	block.type = type
	block.position = Grid.to_px(Vector2(cell))
	objects.add_child(block)


## A razed tower's tiles above the row struck come down a column at a time, left to right (collapse_stagger).
func _on_razed(tiles: Dictionary) -> void:
	var columns := {}
	for c: Vector2i in tiles:
		if not columns.has(c.x):
			columns[c.x] = {}
		columns[c.x][c] = tiles[c]
	var xs := columns.keys()
	xs.sort()
	for i in xs.size():
		_drop_piece(columns[xs[i]], true, i * collapse_stagger)


## Drops lifted tiles (a tower or tree that lost its ground, or a razed tower's column: crumble) as a FallingPiece,
## after delay seconds, with what stands on or in it riding down. The archers of a razed tower are not carried:
## they topple off it.
func _drop_piece(tiles: Dictionary, crumble: bool, delay: float = 0.0) -> void:
	var piece: FallingPiece = falling_piece_scene.instantiate()
	piece.setup(tiles, terrain)
	piece.crumble = crumble
	piece.delay = delay
	for o: Node in objects.get_children() + flags.get_children():
		if o is Node2D and not (o is FallingBlock or o is FallingPiece or o is Arrow or carries(o)):
			var feet := Grid.to_m(o.position)
			if tiles.has(Grid.cell_of(feet)) or tiles.has(Grid.cell_of(feet + Vector2(0, 0.5))):
				if crumble and o is Archer:
					(o as Archer).topple()
				else:
					piece.riders.append(o)
	objects.add_child(piece)


## A razed tower is still coming down, or one of its archers is: the column and the crew stand back.
func collapsing() -> bool:
	return objects.get_children().any(func(o: Node) -> bool:
		return (o is FallingPiece and o.crumble and not o.is_queued_for_deletion()) or (o is Archer and o.toppling()))


## Is node riding down on a falling tower or tree.
func carries(node: Node) -> bool:
	return objects.get_children().any(func(o: Node) -> bool: return o is FallingPiece and node in o.riders)


## Smashes every box the falling piece now covers and, if it crushes, kills every soldier, engineer and archer it
## covers, except what it carries.
func crush_under(piece: FallingPiece) -> void:
	var kills := piece.crushes()
	if kills:
		for s: Soldier in army.soldiers + army.deserters:
			if not s.dead and piece.covers(s.pos - Vector2(0, 0.3)):
				army.crush(s)
		for e: Crew.Engineer in crew.engineers.duplicate():
			if piece.covers(e.pos - Vector2(0, 0.3)):
				crew.crush(e)
	for o: Node in objects.get_children():
		if kills and o is Archer and o.alive() and not o in piece.riders and piece.covers(o.feet_m() - Vector2(0, 0.3)):
			crush(o)
		elif o is FallingBlock and not o.is_queued_for_deletion() and piece.covers(Grid.to_m(o.position) + Vector2(0.5, 0.5)):
			o.smash()


## Adds found to the supplies and shows "+N ..." at at (metres). Every gain of supplies goes through here (or, for
## the camp's supply drop, which GameState adds itself, through _show_gain), so none goes unseen.
func gain(found: Supplies, at: Vector2, color: Color = GAIN_COLOR) -> void:
	if found == null or found.is_empty():
		return
	GameState.gain(found)
	_show_gain(found, at, color)


func _show_gain(found: Supplies, at: Vector2, color: Color = GAIN_COLOR) -> void:
	if found and not found.is_empty():
		Effects.say(Grid.to_px(at), found.describe(), color)


## Top centre of a group of cells, metres.
static func _top_of(cells: Array[Vector2i]) -> Vector2:
	var lo := INF
	var hi := -INF
	var top := INF
	for c in cells:
		lo = minf(lo, c.x)
		hi = maxf(hi, c.x + 1)
		top = minf(top, c.y)
	return Vector2((lo + hi) / 2.0, top)


## An engineer threw an ordered throw: it flies from its hands to its cell and falls on from there.
func _on_threw(order: Crew.Throw, from: Vector2) -> void:
	var block: FallingBlock = order.tool.spawn_scene.instantiate()
	var bag: ThrownBag = thrown_scene.instantiate()
	bag.block = block
	objects.add_child(bag)
	bag.throw(from, order.cell, crew.rules, terrain.tile_texture(block.type))
	Audio.play(order.tool.use_sound, Grid.to_px(from))


## A tree is coming down, chopped or not: leaves and birds fly, and its logs drop as pieces of wood for the crew
## to pick up (they count once picked up).
func _on_felled(cells: Array[Vector2i], found: Supplies) -> void:
	leaves.burst(cells)
	birds.from_tree(cells)
	_dropped = wood.drop(cells, found.logs) if found.logs > 0 else ([] as Array[Wood.Piece])
	found.logs = 0


## An engineer finished digging a marked cell: take the tile and its supplies. The engineer that felled a tree
## picks up its wood.
func _on_dig_finished(cell: Vector2i) -> void:
	var here := terrain.type_at(cell)
	var feller := crew.finisher_of(cell)
	_dropped = []
	var got := terrain.dig(cell)
	if got == null:
		return
	var back := GameState.campaign.reclaim_for(here)
	if back:
		got = back
	if feller:
		crew.gather(feller, _dropped)
	gain(got, Vector2(cell) + Vector2(0.5, 0), GAIN_COLOR if here.dig_action == TerrainType.DigAction.FELL else here.debris_color)


## A soldier's blow on a tower: the tile shakes and blinks, chips of its stone fly and the blade throws sparks, at
## the face toward the soldier, at chest height.
func _on_struck(cell: Vector2i, by: Soldier) -> void:
	var t := terrain.type_at(cell)
	if t == null:
		return
	terrain.hit(cell)
	var side := -1.0 if by.pos.x < cell.x + 0.5 else 1.0
	var at := Vector2(cell.x + (0.0 if side < 0.0 else 1.0), clampf(by.pos.y - 0.6, cell.y + 0.1, cell.y + 0.9))
	Effects.debris(Grid.to_px(at), t.debris_color, army.rules.hit_chips, 110.0)
	Effects.sparks(Grid.to_px(at), army.rules.hit_sparks, Vector2(side, -0.6).normalized())


## A piece of wood picked up: its log goes into the supplies.
func _on_picked_up(piece: Wood.Piece, _by: Crew.Engineer) -> void:
	wood.remove(piece)
	var log := Supplies.new()
	log.logs = 1
	gain(log, piece.pos - Vector2(0, 0.5))


## Every living soldier and archer, and every falling block, as a body bridge pieces and falling blocks collide
## with: [[who, Bridge.Body], ...].
func _bodies(blocks: Array) -> Array:
	var out := []
	for s: Soldier in army.soldiers + army.deserters:
		if not s.dead:
			out.append([s, Bridge.Body.new(s.pos - Vector2(0, BODY_MID), BODY_RADIUS, Vector2(0, s.vy) if s.airborne else Vector2.ZERO, s.on_member)])
	for a: Archer in army.foes:
		out.append([a, Bridge.Body.new(a.feet_m() - Vector2(0, BODY_MID), BODY_RADIUS)])
	for b: FallingBlock in blocks:
		out.append([b, Bridge.Body.box(Grid.to_m(b.position) + Vector2(0.5, 0.5), Vector2(0.5, 0.5), b.on_member)])
	return out


## Every engineer as a body, as _bodies has the soldiers (only thrown and harmless things hit them).
func _crew_bodies() -> Array:
	return crew.engineers.map(func(e: Crew.Engineer) -> Array: return [e, Bridge.Body.new(e.pos - Vector2(0, BODY_MID), BODY_RADIUS)])


## Steps the bridge under the column and the blocks resting on it, colliding with bodies; crushes those it hits
## too fast.
func _step_bridge(dt: float, bodies: Array, blocks: Array) -> void:
	var loads := army.bridge_loads()
	for b: FallingBlock in blocks:
		if b.on_member and not b.on_member.dead:
			loads.append([b.on_member, b.on_t, b.mass])
	var just: Array[Bridge.Body] = []
	for pair: Array in bodies:
		just.append(pair[1])
	bridge.step(dt, loads, just)
	for pair: Array in bodies:
		if (pair[1] as Bridge.Body).crushed:
			crush(pair[0])


## Crushes every soldier and archer carrying more than the bridge's Crush Weight: bridge pieces lying on them
## (with what those carry) and falling blocks resting on them, through any stack of blocks.
func _crush_under_weight(bodies: Array, blocks: Array) -> void:
	var weight := {}
	for pair: Array in bodies:
		weight[pair[0]] = (pair[1] as Bridge.Body).load
	for b: FallingBlock in blocks:
		var under: Node2D = b.resting_on
		for depth in blocks.size():
			if not (under is FallingBlock):
				break
			under = (under as FallingBlock).resting_on
		if under and weight.has(under):
			weight[under] += b.mass
	for who: Node2D in weight:
		if weight[who] > bridge.crush_weight:
			crush(who)


## Kills a soldier or archer crushed by something heavy.
func crush(who: Node2D) -> void:
	if who is Soldier and not who.dead:
		army.crush(who)
	elif who is Archer and who.alive():
		who.hit(who.hp)


## Bridge pieces hit the ground fast: a tower cell is battered by the damage, other ground breaks if the damage
## reaches its Impact Strength (nothing gained).
func _on_bridge_struck(cell: Vector2i, damage: float) -> void:
	var t := terrain.type_at(cell)
	if t == null:
		return
	if t.raze_time > 0.0:
		terrain.hit(cell)
		terrain.besiege(cell, bridge.siege_per_kj * damage / 1000.0)
	elif t.breaks_under(damage):
		terrain.dig(cell)


func _on_member_broken(member: Bridge.Member, text: String) -> void:
	Effects.say(Grid.to_px((member.a.pos + member.b.pos) / 2 - Vector2(0, 0.6)), text, Color("ff6a55"))
