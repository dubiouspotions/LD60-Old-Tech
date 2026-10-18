class_name NightGrade
extends ColorRect
## The night colour grade, on a CanvasLayer above the world and below the HUD. At night (amount, faded by DayNight)
## the picture blends into lut, except around every visible PointLight2D in the game (the camp fire, the
## engineers' lamps, the cursor lantern, any light added later), which keeps its day colours.

const MAX_SPOTS: int = 32

## 0 by day, 1 at full night. DayNight sets this.
@export_range(0.0, 1.0, 0.01) var amount: float = 0.0:
	set(v):
		amount = v
		visible = amount > 0.0
		(material as ShaderMaterial).set_shader_parameter(&"amount", amount)
## The night LUT (a 3D texture, imported from a strip of slices).
@export var lut: Texture3D:
	set(v):
		lut = v
		(material as ShaderMaterial).set_shader_parameter(&"lut", lut)
## A light at this energy or more keeps the day colours fully at its centre; dimmer ones partly.
@export_range(0.05, 4.0, 0.05) var full_light_energy: float = 0.6
## How much of a light's reach keeps the day colours (1 = the whole texture radius).
@export_range(0.1, 2.0, 0.05) var reach: float = 0.8
## 1 fades linearly towards the edge; higher keeps the day colours closer around the light.
@export_range(0.25, 4.0, 0.05) var falloff: float = 1.0

var _lights: Array[PointLight2D] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for n in get_tree().root.find_children("*", "PointLight2D", true, false):
		_lights.append(n)
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is PointLight2D:
			_lights.append(n))
	amount = amount
	lut = lut


func _process(_delta: float) -> void:
	if amount <= 0.0:
		return
	var spots := light_spots()
	var m := material as ShaderMaterial
	var packed: Array[Vector4] = spots.duplicate()
	packed.resize(MAX_SPOTS)
	m.set_shader_parameter(&"spots", packed)
	m.set_shader_parameter(&"spot_count", spots.size())
	m.set_shader_parameter(&"view_size", get_viewport_rect().size)
	m.set_shader_parameter(&"falloff", falloff)


## The lit spots on screen: (x, y, radius) in viewport pixels and a strength 0..1, at most MAX_SPOTS.
func light_spots() -> Array[Vector4]:
	_lights.assign(_lights.filter(func(l: Variant) -> bool: return is_instance_valid(l) and (l as Node).is_inside_tree()))
	var out: Array[Vector4] = []
	for l in _lights:
		if not l.is_visible_in_tree() or not l.enabled or l.energy <= 0.0 or l.texture == null:
			continue
		var xf := l.get_global_transform_with_canvas()
		var r := l.texture.get_width() * l.texture_scale * 0.5 * xf.get_scale().x * reach
		out.append(Vector4(xf.origin.x, xf.origin.y, r, clampf(l.energy / full_light_energy, 0.0, 1.0)))
		if out.size() == MAX_SPOTS:
			break
	return out
