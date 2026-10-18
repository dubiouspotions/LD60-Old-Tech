class_name FallingBlock
extends Node2D
## A tile falling straight down until it lands on the ground, where it becomes that tile again (it breaks on spikes
## and other tiles with Breaks Falling). It comes to rest
## on bridge pieces (loading them) and on soldiers and archers, unless it reaches them at the bridge's Harm Speed:
## then it crushes them and falls on. Stepped by the World. The node origin is the top-left of the cell. It shows
## the TileSet's picture of its terrain type.

@export var type: TerrainType
@export var gravity: float = 30.0
@export var max_speed: float = 22.0
## Weight it puts on a bridge piece it rests on.
@export var mass: float = 600.0
@export var land_sound: SoundEffect
## Breaks on any soldier or archer it falls on, hurting nobody (a sandbag), instead of resting on them or crushing
## them at Harm Speed.
@export var harmless: bool = false
## Puffs of dust when it breaks, and its sound then (the landing sound if none).
@export_range(0, 20) var smash_dust: int = 0
@export var smash_sound: SoundEffect

## The bridge piece it rests on (and where along it), else null.
var on_member: Bridge.Member
## The soldier, archer or block it rests on, else null.
var resting_on: Node2D
var on_t: float = 0.0
var _vy: float = 0.0


func _ready() -> void:
	var world := World.of(self)
	if world and type:
		$Sprite.texture = world.terrain.tile_texture(type)


## Falls for dt. bodies: [[soldier, archer or block, Bridge.Body], ...] it can land on; soldiers and archers it
## reaches at Harm Speed are crushed instead.
func step(dt: float, world: World, bodies: Array) -> void:
	var t := world.terrain
	var x := cell_x()
	var bottom := position.y / Grid.PX + 1.0
	_vy = minf(_vy + gravity * dt, max_speed)
	var next := bottom + _vy * dt
	var rest := INF
	on_member = null
	resting_on = null
	for k: float in [0.15, 0.5, 0.85]:
		var deck := world.bridge.walk_surface(x + k, bottom - 0.05, false)
		if not deck.is_empty() and deck.y <= next and deck.y < rest:
			rest = deck.y
			on_member = deck.member
			on_t = deck.t
			resting_on = null
	for pair: Array in bodies:
		var b: Bridge.Body = pair[1]
		var head := b.top()
		if pair[0] == self or absf(b.center.x - (x + 0.5)) >= 0.5 + b.half_width() or head < bottom - 0.05 or head > next:
			continue
		if harmless and not b.is_box():
			smash()
			return
		if _vy >= world.bridge.harm_speed and not b.is_box():
			world.crush(pair[0])
		elif head < rest:
			rest = head
			on_member = null
			resting_on = pair[0]
	if rest < INF:
		next = rest
		_vy = 0.0
	position.y = (next - 1.0) * Grid.PX
	if rest < INF:
		return
	var r := floori(position.y / Grid.PX)
	var inside := t.type_at(Vector2i(x, floori(next - 0.5)))
	if inside and inside.breaks_falling:
		smash()
		return
	if r + 1 >= t.size.y or t.is_solid(Vector2i(x, r + 1)):
		while r > 0 and t.is_solid(Vector2i(x, r)):
			r -= 1
		t.set_type(Vector2i(x, r), type)
		var at := Grid.to_px(Vector2(x + 0.5, r + 1))
		Effects.debris(at, type.debris_color if type else Color.WHITE, 3, 70.0)
		Audio.play(land_sound, at)
		queue_free()


## Smashed (on spikes, on someone when harmless, or under a falling tower or tree): debris, dust, gone.
func smash() -> void:
	var at := position + Vector2(0.5, 1.0) * Grid.PX
	var color := type.debris_color if type else Color.WHITE
	Effects.debris(at, color, 6, 120.0)
	Effects.dust(position + Vector2(0.5, 0.5) * Grid.PX, color, smash_dust)
	Audio.play(smash_sound if smash_sound else land_sound, at)
	queue_free()


func cell_x() -> int:
	return floori(position.x / Grid.PX)
