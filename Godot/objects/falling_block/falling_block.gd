class_name FallingBlock
extends Node2D
## A tile falling straight down until it lands on the ground, where it becomes that tile again. It comes to rest
## on bridge pieces (loading them) and on soldiers and archers, unless it reaches them at the bridge's Harm Speed:
## then it crushes them and falls on. Stepped by the World. The node origin is the top-left of the cell. It shows
## the TileSet's picture of its terrain type.

@export var type: TerrainType
@export var gravity: float = 30.0
@export var max_speed: float = 22.0
## Weight it puts on a bridge piece it rests on.
@export var mass: float = 600.0
@export var land_sound: SoundEffect

## The bridge piece it rests on (and where along it), else null.
var on_member: Bridge.Member
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
	for k: float in [0.15, 0.5, 0.85]:
		var deck := world.bridge.walk_surface(x + k, bottom - 0.05, false)
		if not deck.is_empty() and deck.y <= next and deck.y < rest:
			rest = deck.y
			on_member = deck.member
			on_t = deck.t
	for pair: Array in bodies:
		var b: Bridge.Body = pair[1]
		var head := b.top()
		if pair[0] == self or absf(b.center.x - (x + 0.5)) >= 0.5 + b.half_width() or head < bottom - 0.05 or head > next:
			continue
		if _vy >= world.bridge.harm_speed and not b.is_box():
			world.crush(pair[0])
		elif head < rest:
			rest = head
			on_member = null
	if rest < INF:
		next = rest
		_vy = 0.0
	position.y = (next - 1.0) * Grid.PX
	if rest < INF:
		return
	var r := floori(position.y / Grid.PX)
	if r + 1 >= t.size.y or t.is_solid(Vector2i(x, r + 1)):
		while r > 0 and t.is_solid(Vector2i(x, r)):
			r -= 1
		t.set_type(Vector2i(x, r), type)
		var at := Grid.to_px(Vector2(x + 0.5, r + 1))
		Effects.debris(at, type.debris_color if type else Color.WHITE, 3, 70.0)
		Audio.play(land_sound, at)
		queue_free()


func cell_x() -> int:
	return floori(position.x / Grid.PX)
