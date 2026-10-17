class_name Army
extends Node2D
## The marching column. Once ordered to march it never stops by choice: soldiers walk off drops, into hazards and
## onto unfinished bridges. Only a wall they can not climb halts them. The front soldier warns of danger ahead.
## Front soldier carries the flag. Tuning lives in the ArmyRules resource.

signal soldier_died(pos: Vector2, text: String)
signal count_changed(count: int)

@export var rules: ArmyRules
@export var soldier_scene: PackedScene
@export var body_colors: Array[Color] = [Color("4d8bf0"), Color("ece4d2")]

var terrain: Terrain
var bridge: Bridge
## Front first.
var soldiers: Array[Soldier] = []
## Why the front soldier is not moving, or "" while it marches.
var halt_reason: String = ""
## Danger the front soldier is marching toward (a deep drop, a hazard), or "". A warning only.
var danger: String = ""
## Enemies soldiers fight when they reach them (archers). Set by the level each tick.
## Each needs feet_m(), alive() and hit(damage).
var foes: Array = []
## Waiting for the order to march. Soldiers still fall, but do not walk.
var hold: bool = false


func lead() -> Soldier:
	return soldiers[0] if not soldiers.is_empty() else null


func rear() -> Soldier:
	return soldiers[-1] if not soldiers.is_empty() else null


## Places count soldiers on the ground, the first at x and the rest behind it.
func spawn(count: int, x: float) -> void:
	for s in soldiers:
		s.queue_free()
	soldiers.clear()
	for i in count:
		_add(maxf(0.5, x - i * rules.spawn_spacing))
	_update_leader()
	count_changed.emit(soldiers.size())


## Load each soldier puts on the bridge: [[member, t, kg], ...].
func bridge_loads() -> Array:
	var out := []
	for s in soldiers:
		if s.on_member and not s.on_member.dead:
			out.append([s.on_member, s.on_t, rules.soldier_mass])
	return out


func step(dt: float) -> void:
	soldiers.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.pos.x > b.pos.x)
	halt_reason = ""
	danger = ""
	for i in soldiers.size():
		var s := soldiers[i]
		if s.dead:
			continue
		s.moving = false
		if not _settle_vertical(s, dt):
			continue
		if s.airborne:
			continue
		if hold:
			if i == 0:
				halt_reason = rules.hold_text
			continue
		var foe: Node2D = _foe_in_reach(s)
		if foe:
			_fight(s, foe, dt)
			if i == 0:
				halt_reason = rules.fight_text
			continue
		var ahead: Soldier = soldiers[i - 1] if i > 0 else null
		if ahead and not ahead.dead and ahead.pos.x - s.pos.x < rules.spacing and absf(ahead.pos.y - s.pos.y) < rules.queue_height:
			continue
		var dx := s.speed * dt
		if i == 0:
			danger = _danger_ahead(s)
		var block := _blocked_ahead(s, dx)
		if not block.is_empty():
			if i == 0:
				halt_reason = block
			continue
		s.pos.x += dx
		s.moving = true
		var sup := _support(s, s.pos.y - rules.step_up)
		if sup.hazard == null and sup.y <= s.pos.y + 0.2:
			s.pos.y = sup.y
			s.stand_on(sup)
	_remove_dead()
	for s in soldiers:
		s.sync()


## Damages one soldier. Returns true if it died.
func hit(s: Soldier, kill_text: String) -> bool:
	if s.dead:
		return false
	s.hp -= 1
	s.flash_hurt()
	Audio.play(rules.hurt_sound, Grid.to_px(s.pos))
	if s.hp <= 0:
		kill(s, kill_text)
		_remove_dead()
		return true
	return false


## Kills every soldier within radius (metres) of center.
func blast(center: Vector2, radius: float, text: String) -> void:
	for s in soldiers:
		if (s.pos - Vector2(0, 0.5)).distance_to(center) < radius:
			kill(s, text)
	_remove_dead()


func kill(s: Soldier, text: String) -> void:
	if s.dead:
		return
	s.dead = true
	s.on_member = null
	var at := Grid.to_px(s.pos - Vector2(0, 0.5))
	for c in body_colors:
		Effects.debris(at, c, 4, 190.0)
	Effects.say(Grid.to_px(s.pos - Vector2(0, 1.4)), text, Color("ff6a55"))
	Audio.play(rules.death_sound, at)
	soldier_died.emit(s.pos, text)


## Gravity, landing, falling off and hazards. Returns false if the soldier died.
func _settle_vertical(s: Soldier, dt: float) -> bool:
	var pushes := 0
	while not s.airborne and terrain.is_solid(Grid.cell_of(s.pos - Vector2(0, 0.5))) and pushes < 3:
		s.pos.y = floorf(s.pos.y - 0.5)
		pushes += 1
	if pushes >= 3:
		kill(s, rules.crushed_text)
		return false
	if s.airborne:
		s.vy = minf(s.vy + rules.gravity * dt, rules.max_fall_speed)
		var ny := s.pos.y + s.vy * dt
		var sup := _support(s, s.pos.y)
		if sup.hazard == null and sup.y <= ny:
			s.pos.y = sup.y
			s.airborne = false
			s.stand_on(sup)
			if s.pos.y - s.fall_from > rules.fatal_fall:
				kill(s, rules.fell_text)
				return false
		else:
			s.pos.y = ny
	else:
		var sup := _support(s, s.pos.y - rules.step_up)
		if sup.hazard != null or sup.y > s.pos.y + 0.2:
			s.airborne = true
			s.vy = 0.0
			s.fall_from = s.pos.y
			s.on_member = null
		else:
			s.pos.y = sup.y
			s.stand_on(sup)
	if s.pos.y >= terrain.size.y - 1:
		kill(s, "")
		return false
	var body := terrain.type_at(Grid.cell_of(s.pos - Vector2(0, 0.5)))
	if body and body.is_hazard():
		kill(s, body.death_text)
		return false
	return true


## A living foe just ahead of the soldier and about level with it, or null.
func _foe_in_reach(s: Soldier) -> Node2D:
	for f: Node2D in foes:
		if not is_instance_valid(f) or not f.alive():
			continue
		var d: Vector2 = f.feet_m() - s.pos
		if d.x > -rules.foot_half_width and d.x < rules.melee_reach and absf(d.y) < rules.step_up:
			return f
	return null


func _fight(s: Soldier, foe: Node2D, dt: float) -> void:
	s.attack_cooldown -= dt
	if s.attack_cooldown > 0.0:
		return
	s.attack_cooldown = rules.attack_interval
	Audio.play(rules.attack_sound, Grid.to_px(s.pos))
	foe.hit(rules.melee_damage)


## Wall text if the soldier can not take the next dx step, else "". Drops and hazards never block.
func _blocked_ahead(s: Soldier, dx: float) -> String:
	var xp := s.pos.x + rules.foot_half_width + dx
	var sup := surface_at(xp, s.pos.y - rules.step_up)
	var col := floori(xp)
	var head_blocked: bool = terrain.is_solid(Vector2i(floori(s.pos.x), floori(s.pos.y - 1.5))) and sup.y < s.pos.y - 0.5
	if terrain.is_solid(Vector2i(col, floori(sup.y - 0.5))) or head_blocked:
		var h := 0
		var r := roundi(s.pos.y)
		while h < 14 and terrain.is_solid(Vector2i(col, r - 1 - h)):
			h += 1
		return rules.wall_text % maxi(h, 2)
	return ""


## Warning text for the first deep drop or hazard within warn_distance ahead of the soldier, else "".
func _danger_ahead(s: Soldier) -> String:
	var x := s.pos.x + rules.foot_half_width
	var end := x + rules.warn_distance
	while x < end:
		x += 0.25
		var sup := surface_at(x, s.pos.y - rules.step_up)
		if terrain.is_solid(Vector2i(floori(x), floori(sup.y - 0.5))):
			return ""
		var drop: float = sup.y - s.pos.y
		if sup.hazard != null:
			return rules.chasm_text if drop > rules.max_drop else (sup.hazard as TerrainType).ahead_text
		if drop > rules.max_drop:
			return rules.chasm_text if drop > rules.chasm_depth else rules.drop_text % roundi(drop)
	return ""


## Highest surface at x at or below y_from: tile tops, hazards and bridge decks.
## {y, hazard: TerrainType or null, member, t}
func surface_at(x: float, y_from: float) -> Dictionary:
	var col := floori(x)
	var best := {y = float(terrain.size.y), hazard = null, member = null, t = 0.0}
	for r in range(maxi(0, ceili(y_from - 1e-6)), terrain.size.y):
		var t := terrain.type_at(Vector2i(col, r))
		if t == null:
			continue
		if t.solid:
			best.y = float(r)
			break
		if t.is_hazard():
			best.y = float(r)
			best.hazard = t
			break
	if bridge:
		var deck := bridge.walk_surface(x, y_from)
		if not deck.is_empty() and deck.y < best.y:
			best = {y = deck.y, hazard = null, member = deck.member, t = deck.t}
	return best


## Surface under both feet. A foot over a hazard is ignored if the other is on safe ground.
func _support(s: Soldier, y_from: float) -> Dictionary:
	var a := surface_at(s.pos.x - rules.foot_half_width, y_from)
	var b := surface_at(s.pos.x + rules.foot_half_width, y_from)
	if (a.hazard == null) != (b.hazard == null):
		return b if a.hazard != null else a
	return a if a.y <= b.y else b


func _add(x: float) -> Soldier:
	var s: Soldier = soldier_scene.instantiate()
	s.pos = Vector2(x, terrain.surface_row(floori(x)))
	s.max_hp = rules.hit_points
	s.hp = rules.hit_points
	s.speed = rules.march_speed * (1.0 + randf_range(-rules.speed_spread, rules.speed_spread))
	add_child(s)
	soldiers.append(s)
	s.sync()
	return s


func _remove_dead() -> void:
	var before := soldiers.size()
	for s in soldiers:
		if s.dead:
			s.queue_free()
	soldiers = soldiers.filter(func(s: Soldier) -> bool: return not s.dead)
	if soldiers.size() != before:
		_update_leader()
		count_changed.emit(soldiers.size())


func _update_leader() -> void:
	for i in soldiers.size():
		soldiers[i].set_leader(i == 0)
