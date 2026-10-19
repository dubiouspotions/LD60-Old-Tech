@tool
class_name DitheredLightTexture
extends ImageTexture
## A round light texture for PointLight2D that fades out in dither pixels instead of a smooth gradient, as its
## LightDither says (shared with the night grade). Use it at texture_scale 1, so every dither pixel lands on whole
## screen pixels. The pattern is laid out from the centre, the same way the night grade lays out its own dither around
## each light, so the two line up. Rebuilt from its settings when loaded; the picture itself is not saved.

## Smooth (dither off) textures are drawn at this many pixels per step and scaled up smoothly.
const SMOOTH_PX: int = 4
## Pictures kept for reuse (one per spot of the pattern and animation frame a light has been shown at).
const CACHE_SIZE: int = 16

## How the fade is dithered (data/light_dither.tres). Empty or off: a smooth fade.
@export var dither: LightDither:
	set(v):
		if dither and dither.changed.is_connected(_queue_rebuild):
			dither.changed.disconnect(_queue_rebuild)
		dither = v
		if dither:
			dither.changed.connect(_queue_rebuild)
		_queue_rebuild()
## Colour and opacity from the centre (left) to the edge (right). Empty: white fading to clear.
@export var gradient: Gradient:
	set(v):
		if gradient and gradient.changed.is_connected(_queue_rebuild):
			gradient.changed.disconnect(_queue_rebuild)
		gradient = v
		if gradient:
			gradient.changed.connect(_queue_rebuild)
		_queue_rebuild()
## Width and height in pixels (the light's reach is half of it). Rounded up to whole dither pixels.
@export_range(16, 2048, 1, "suffix:px") var size: int = 256:
	set(v):
		size = v
		_queue_rebuild()

var _queued := false
## Pictures already drawn, by Vector3i(phase x, phase y, frame), the most recently shown last.
var _cache: Dictionary[Vector3i, Image] = {}
var _shown := Vector3i.ZERO
var _has_image := false
## 1 - distance from the centre of every dither pixel, measured once per size (see _measure).
var _field := PackedFloat32Array()
var _field_half := -1


func _init() -> void:
	_queue_rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name == "image":
		property.usage = PROPERTY_USAGE_NONE


## Redraws the picture from the settings now (it also happens by itself, a frame after a change).
func rebuild() -> void:
	_queued = false
	_cache.clear()
	var key := _shown
	_shown = Vector3i(-1, -1, -1)
	show(Vector2i(key.x, key.y), key.z)


## Shows the pattern as it falls at phase (the dither pixel under the centre, counted in the pattern; the world cell
## in world space) in animation frame (wrapping around). Pictures are drawn the first time and the last few kept.
func show(phase: Vector2i, frame: int) -> void:
	var key := Vector3i(phase.x, phase.y, posmod(frame, dither.frame_count()) if _dithered() else 0)
	if not _dithered():
		key = Vector3i.ZERO
	if key == _shown and _has_image:
		return
	_shown = key
	var img: Image = _cache.get(key)
	if img:
		_cache.erase(key)
	else:
		img = _paint(Vector2i(key.x, key.y), key.z)
		if _cache.size() >= CACHE_SIZE:
			_cache.erase(_cache.keys()[0])
	_cache[key] = img
	# Not update(): lights draw from a copy in the renderer's light atlas, which only set_image() refreshes.
	set_image(img)
	_has_image = true


## The picture shown now.
func shown_image() -> Image:
	return _cache.get(_shown)


func _dithered() -> bool:
	return dither != null and dither.enabled


func _paint(phase: Vector2i, frame: int) -> Image:
	var on := _dithered()
	var px := dither.pixel_size if on else SMOOTH_PX
	var half := ceili(size / 2.0 / px)
	var cells := half * 2
	if _field_half != half:
		_measure(half)
	# The colour of each level (clear first, the centre last) as one RGBA8 int.
	var levels := dither.steps if on else 255
	var lut := PackedInt32Array()
	for k in levels + 1:
		var c := gradient.sample(1.0 - float(k) / levels) if gradient else Color(1, 1, 1, float(k) / levels)
		lut.append(c.r8 | c.g8 << 8 | c.b8 << 16 | c.a8 << 24)
	var th := dither.thresholds(phase - Vector2i(half, half), cells, cells, frame) if on else PackedFloat32Array()
	var pixels := PackedInt32Array()
	pixels.resize(cells * cells)
	for i in cells * cells:
		var v := _field[i]
		if v <= 0.0:
			pixels[i] = lut[0]
		elif on:
			pixels[i] = lut[clampi(floori(v * levels + th[i]), 0, levels)]
		else:
			pixels[i] = lut[roundi(v * levels)]
	var img := Image.create_from_data(cells, cells, false, Image.FORMAT_RGBA8, pixels.to_byte_array())
	img.resize(cells * px, cells * px, Image.INTERPOLATE_NEAREST if on else Image.INTERPOLATE_BILINEAR)
	return img


## Fills _field with 1 - the distance of each dither pixel's centre from the middle (1 at the centre, 0 at the
## edge and beyond), for half dither pixels each side.
func _measure(half: int) -> void:
	_field_half = half
	_field.resize(half * half * 4)
	var i := 0
	for cy in half * 2:
		for cx in half * 2:
			_field[i] = maxf(1.0 - Vector2(cx - half + 0.5, cy - half + 0.5).length() / half, 0.0)
			i += 1


func _queue_rebuild() -> void:
	if not _queued:
		_queued = true
		(func() -> void:
			if _queued:
				rebuild()).call_deferred()
