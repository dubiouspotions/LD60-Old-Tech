class_name Archer
extends Node2D
## An enemy archer on a tower. Shoots at the nearest soldier in range that it has a clear shot at (no ground or
## arrow-blocking bridge member on the arrow's arc), or at the nearest in range if it has a clear shot at none.
## Place it with its feet (node origin) on top of a solid tile. It dies when that tile is destroyed,
## or when soldiers reach it and cut it down. It rides its tower down when the tower falls (holding fire meanwhile),
## and dies if the tower breaks up.

@export_range(1.0, 40.0, 0.5, "suffix:m") var shoot_range: float = 13.0
@export var arrow_scene: PackedScene
@export_range(1.0, 60.0, 0.5, "suffix:m/s") var arrow_speed: float = 15.0
## Arcade arrow gravity; the archer leads its aim to match.
@export_range(0.0, 40.0, 0.5, "suffix:m/s²") var arrow_gravity: float = 12.0
## Random error of each shot, as a fraction of its speed.
@export_range(0.0, 0.5, 0.01) var aim_error: float = 0.04
@export_range(0.0, 10.0, 0.1, "suffix:s") var first_shot_delay: float = 1.5
@export_range(0.1, 10.0, 0.05, "suffix:s") var reload_time: float = 2.2
@export var shoot_sound: SoundEffect
@export var down_sound: SoundEffect
@export var down_text: String = "Tower down"
## Shared tuning, such as how many melee hits an archer takes before it falls.
@export var rules: ArcherRules
@export var slain_text: String = "Archer slain"
@export var hurt_flash_color: Color = Color.WHITE
## Height of the bow above the feet.
@export var bow_height: float = 0.6
## Holds fire while the column camps for the night.
@export var rests_at_night: bool = true

@export_group("Topple")
## When its tower is razed under it, the archer hangs in the air this long, then falls...
@export_range(0.0, 3.0, 0.05, "suffix:s") var topple_hang: float = 0.5
@export_range(1.0, 100.0, 1.0, "suffix:m/s²") var topple_gravity: float = 30.0
## ...lands lying flat and lies there this long, then blinks once and vanishes in a puff of smoke.
@export_range(0.0, 10.0, 0.1, "suffix:s") var lie_time: float = 2.0
@export var vanish_flash: Color = Color(3, 3, 3)
## How many times it blinks before it vanishes.
@export_range(1, 10) var vanish_blinks: int = 2
@export var smoke_color: Color = Color(0.78, 0.75, 0.7)
@export_range(0, 30) var smoke_puffs: int = 6

@export_group("Look")
@export var show_range: bool = true
@export var range_color: Color = Color(0.851, 0.314, 0.247, 0.28)

## True while a soldier is in range of this archer.
var engaging: bool = false
var hp: int = 3
var _cooldown: float = 0.0
var _down: bool = false
enum Topple { NONE, HANG, FALL, LIE, GONE }
## Seconds of each half of a vanishing blink (bright, then back).
const VANISH_BLINK: float = 0.1
var _topple: Topple = Topple.NONE
var _topple_time: float = 0.0
var _vy: float = 0.0


func _ready() -> void:
	_cooldown = first_shot_delay
	hp = rules.hit_points


func alive() -> bool:
	return not _down


## A soldier's melee strike.
func hit(damage: int) -> void:
	if _down:
		return
	hp -= damage
	modulate = hurt_flash_color * 3.0
	create_tween().tween_property(self, ^"modulate", Color.WHITE, 0.25)
	if hp <= 0:
		_go_down(slain_text)


func feet_m() -> Vector2:
	return Grid.to_m(position)


func _physics_process(dt: float) -> void:
	var world := World.of(self)
	if world and _topple != Topple.NONE:
		_topple_step(world, dt)
		return
	if world == null or _down:
		return
	if world.carries(self):
		engaging = false
		return
	if not world.terrain.is_solid(Grid.cell_of(feet_m() + Vector2(0, 0.5))):
		_go_down(down_text)
		return
	if rests_at_night and world.at_camp():
		engaging = false
		return
	_cooldown -= dt
	var origin := _bow()
	engaging = not _in_range(world).is_empty()
	if not engaging or _cooldown > 0.0:
		return
	var target := pick_target(world)
	_cooldown = reload_time
	var arrow: Arrow = arrow_scene.instantiate()
	arrow.velocity = _shot_velocity(_aim_point(target) - origin, randf_range(-aim_error, aim_error))
	arrow.gravity = arrow_gravity
	arrow.shooter_column = floori(feet_m().x)
	arrow.shooter_feet_y = feet_m().y
	arrow.position = Grid.to_px(origin)
	world.objects.add_child(arrow)
	Audio.play(shoot_sound, position)


## The soldier to shoot at: the nearest in range in sight, else the nearest in range, else null.
func pick_target(world: World) -> Soldier:
	var near := _in_range(world)
	for s in near:
		if sees(world, s):
			return s
	return near[0] if not near.is_empty() else null


## Soldiers within shoot_range of the bow, nearest first.
func _in_range(world: World) -> Array[Soldier]:
	var origin := _bow()
	var out: Array[Soldier] = []
	for s in world.army.soldiers:
		if _aim_point(s).distance_to(origin) < shoot_range:
			out.append(s)
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool:
		return _aim_point(a).distance_squared_to(origin) < _aim_point(b).distance_squared_to(origin))
	return out


## True if an arrow shot at the soldier (aimed true) would reach it: its arc meets no ground and no bridge member
## that stops arrows on the way (the same rules as the arrow, see Arrow.obstacle).
func sees(world: World, s: Soldier) -> bool:
	var a := _bow()
	var b := _aim_point(s)
	var vel := _shot_velocity(b - a, 0.0)
	var p := a
	var age := 0.0
	var dt := 1.0 / 60.0
	var column := floori(feet_m().x)
	while (b.x - p.x) * signf(vel.x) > 0.0 and age < 4.0:
		var from := p
		age += dt
		p += vel * dt
		vel.y += arrow_gravity * dt
		if not Arrow.obstacle(world, from, p, age, column, feet_m().y).is_empty():
			return false
	return true


## Inside the archer's own crenellations: its column or a neighbour, above its feet. Its arrows pass through them
## right after the shot.
static func own_tower(p: Vector2, column: int, feet_y: float) -> bool:
	return absi(Grid.cell_of(p).x - column) <= 1 and p.y < feet_y


## Launch velocity to land an arrow at offset to, its sideways speed off by error (a fraction).
func _shot_velocity(to: Vector2, error: float) -> Vector2:
	var flight := maxf(0.25, to.length() / arrow_speed)
	return Vector2(to.x / flight * (1.0 + error), to.y / flight - 0.5 * arrow_gravity * flight)


func _bow() -> Vector2:
	return feet_m() - Vector2(0, bow_height)


func _aim_point(s: Soldier) -> Vector2:
	return s.pos - Vector2(0, 0.5)


## Its tower broke up under it.
## Its tower was razed under it: it hangs a moment, falls, lies flat, then vanishes (see Topple).
func topple() -> void:
	if _topple != Topple.NONE:
		return
	if not _down:
		Effects.say(position - Vector2(0, Grid.PX), down_text, Color("e9a93b"))
		Audio.play(down_sound, position)
	_down = true
	engaging = false
	queue_redraw()
	_topple = Topple.HANG
	_topple_time = 0.0
	_vy = 0.0


## Coming down off a razed tower, from the hang until it has vanished.
func toppling() -> bool:
	return _topple != Topple.NONE and not is_queued_for_deletion()


## Lying on the ground after toppling.
func lying() -> bool:
	return _topple == Topple.LIE


func _topple_step(world: World, dt: float) -> void:
	_topple_time += dt
	match _topple:
		Topple.HANG:
			if _topple_time >= topple_hang:
				_topple = Topple.FALL
		Topple.FALL:
			_vy += topple_gravity * dt
			var feet := feet_m()
			var next := feet.y + _vy * dt
			if _on_falling_piece(world, Vector2(feet.x, next)):
				# Rides the rubble of its tower until that breaks too.
				_vy = 0.0
				return
			if world.terrain.is_solid(Grid.cell_of(Vector2(feet.x, next))):
				_lie_down(floorf(next))
				return
			position.y = next * Grid.PX
		Topple.LIE:
			if _topple_time >= lie_time:
				_topple = Topple.GONE
				_topple_time = 0.0
		Topple.GONE:
			# Full-body blinks, then a puff of smoke.
			modulate = vanish_flash if fmod(_topple_time, VANISH_BLINK * 2.0) < VANISH_BLINK else Color.WHITE
			if _topple_time >= VANISH_BLINK * 2.0 * vanish_blinks:
				Effects.dust(position - Vector2(0, 0.25 * Grid.PX), smoke_color, smoke_puffs)
				queue_free()


func _on_falling_piece(world: World, p: Vector2) -> bool:
	return world.objects.get_children().any(func(o: Node) -> bool:
		return o is FallingPiece and not o.is_queued_for_deletion() and (o as FallingPiece).covers(p))


## Lands lying flat on its side on the ground at y (metres), and lies perfectly still: its animations stop.
func _lie_down(y: float) -> void:
	for s in find_children("*", "AnimatedSprite2D", true, false):
		(s as AnimatedSprite2D).pause()
	_topple = Topple.LIE
	_topple_time = 0.0
	rotation = -PI / 2
	position.y = (y - 0.25) * Grid.PX
	Audio.play(down_sound, position)


func lose_ground() -> void:
	if not _down:
		_go_down(down_text)


func _go_down(text: String) -> void:
	_down = true
	engaging = false
	Effects.say(position - Vector2(0, Grid.PX), text, Color("e9a93b"))
	Audio.play(down_sound, position)
	var tw := create_tween()
	tw.tween_property(self, ^"modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


func _draw() -> void:
	if show_range and not _down:
		var c := Vector2(0, -bow_height * Grid.PX)
		var r := shoot_range * Grid.PX
		var n := 72
		for i in range(0, n, 2):
			draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 4, range_color, 1.5)
