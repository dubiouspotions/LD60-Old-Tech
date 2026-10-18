class_name Archer
extends Node2D
## An enemy archer on a tower. Shoots at the nearest soldier in range.
## Place it with its feet (node origin) on top of a solid tile. It dies when that tile is destroyed,
## or when soldiers reach it and cut it down.

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

@export_group("Look")
@export var show_range: bool = true
@export var range_color: Color = Color(0.851, 0.314, 0.247, 0.28)

## True while a soldier is in range of this archer.
var engaging: bool = false
var hp: int = 3
var _cooldown: float = 0.0
var _down: bool = false


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
	if world == null or _down:
		return
	if not world.terrain.is_solid(Grid.cell_of(feet_m() + Vector2(0, 0.5))):
		_go_down(down_text)
		return
	if rests_at_night and world.at_camp():
		engaging = false
		return
	_cooldown -= dt
	var origin := feet_m() - Vector2(0, bow_height)
	var target: Soldier = null
	var best := shoot_range
	for s in world.army.soldiers:
		var d := (s.pos - Vector2(0, 0.5)).distance_to(origin)
		if d < best:
			best = d
			target = s
	engaging = target != null
	if target == null or _cooldown > 0.0:
		return
	_cooldown = reload_time
	var to := target.pos - Vector2(0, 0.5) - origin
	var flight := maxf(0.25, to.length() / arrow_speed)
	var vel := Vector2(to.x / flight * (1.0 + randf_range(-aim_error, aim_error)), to.y / flight - 0.5 * arrow_gravity * flight)
	var arrow: Arrow = arrow_scene.instantiate()
	arrow.velocity = vel
	arrow.gravity = arrow_gravity
	arrow.shooter_column = floori(feet_m().x)
	arrow.shooter_feet_y = feet_m().y
	arrow.position = Grid.to_px(origin)
	world.objects.add_child(arrow)
	Audio.play(shoot_sound, position)


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
