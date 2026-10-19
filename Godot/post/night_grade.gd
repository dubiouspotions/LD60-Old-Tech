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
## How the fade around lights is dithered (data/light_dither.tres, shared with the lights' textures). Empty or off:
## smooth. Each frame it also picks the animation frame of every DitheredLightTexture.
@export var dither: LightDither

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
	var on := dither != null and dither.enabled
	var frame := dither.frame_at(Time.get_ticks_msec()) if on else 0
	_place_lights(frame)
	var spots := light_spots()
	var m := material as ShaderMaterial
	var packed: Array[Vector4] = spots.duplicate()
	packed.resize(MAX_SPOTS)
	m.set_shader_parameter(&"spots", packed)
	m.set_shader_parameter(&"spot_count", spots.size())
	m.set_shader_parameter(&"view_size", get_viewport_rect().size)
	m.set_shader_parameter(&"falloff", falloff)
	m.set_shader_parameter(&"dither_steps", float(dither.steps) if on else 0.0)
	if on:
		m.set_shader_parameter(&"pixel_size", float(dither.pixel_size))
		m.set_shader_parameter(&"pattern", dither.pattern)
		m.set_shader_parameter(&"spread", dither.spread)
		m.set_shader_parameter(&"frame", frame)
		m.set_shader_parameter(&"frames", dither.frames)
		m.set_shader_parameter(&"world_space", dither.world_space)
		# Where the world's origin lands on screen, rounded like the tiles under a camera between pixels.
		m.set_shader_parameter(&"world_origin", get_viewport().get_canvas_transform().origin.round())


## The lit spots on screen: (x, y, radius) in viewport pixels (at the light's offset) and a strength 0..1, at most
## MAX_SPOTS.
func light_spots() -> Array[Vector4]:
	_lights.assign(_lights.filter(func(l: Variant) -> bool: return is_instance_valid(l) and (l as Node).is_inside_tree()))
	var out: Array[Vector4] = []
	for l in _lights:
		if not l.is_visible_in_tree() or not l.enabled or l.energy <= 0.0 or l.texture == null:
			continue
		var xf := l.get_global_transform_with_canvas()
		var r := l.texture.get_width() * l.texture_scale * 0.5 * xf.get_scale().x * reach
		var at := xf * l.offset
		out.append(Vector4(at.x, at.y, r, clampf(l.energy / full_light_energy, 0.0, 1.0)))
		if out.size() == MAX_SPOTS:
			break
	return out


## Draws every light with a DitheredLightTexture centred on a whole art pixel of the world and a whole screen pixel
## (by its offset), so its dither pixels, and the grade's around it, line up with the tiles' pixels, and shows the
## pattern as it falls there in this animation frame. In world space that depends on where the light is, so lights
## must not share a texture (make it Local To Scene).
func _place_lights(frame: int) -> void:
	for v: Variant in _lights:
		if not is_instance_valid(v):
			continue
		var l := v as PointLight2D
		var tex := l.texture as DitheredLightTexture
		if tex == null or not l.is_inside_tree():
			continue
		var d := tex.dither
		if d == null or not d.enabled:
			l.offset = Vector2.ZERO
			tex.show(Vector2i.ZERO, 0)
			continue
		# On the world's pixel grid, then onto a whole screen pixel (where the tiles land under a camera between
		# pixels), so the texture is not filtered across two rows.
		var cell := Vector2i((l.global_position / d.pixel_size).round())
		var at := Vector2(cell * d.pixel_size)
		var canvas := l.get_canvas_transform()
		var on_screen := canvas * at
		l.offset = l.to_local(at + canvas.affine_inverse().basis_xform(on_screen.round() - on_screen))
		tex.show(cell if d.world_space else Vector2i.ZERO, frame)
