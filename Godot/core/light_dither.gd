@tool
class_name LightDither
extends Resource
## How the night lights fade out: in dither pixels instead of a smooth gradient. One of these
## (data/light_dither.tres) is shared by every DitheredLightTexture and the night grade, so the two match.

## BAYER_*: the ordered dither patterns (2x2, 4x4, 8x8 tiles), neat and regular. NOISE: scattered, grainy.
## BANDS: no dither, hard rings of the Steps levels.
enum Pattern { BAYER_2, BAYER_4, BAYER_8, NOISE, BANDS }

## Off: the lights fade smoothly.
@export var enabled: bool = true:
	set(v):
		enabled = v
		emit_changed()
## Screen pixels per dither pixel. 4 matches the tiles' and soldiers' pixels.
@export_range(1, 16, 1, "suffix:px") var pixel_size: int = 4:
	set(v):
		pixel_size = maxi(v, 1)
		emit_changed()
## Brightness levels between full and dark; the dither blends neighbouring levels. 1 is pure on/off.
@export_range(1, 16) var steps: int = 3:
	set(v):
		steps = maxi(v, 1)
		emit_changed()
@export var pattern: Pattern = Pattern.BAYER_4:
	set(v):
		pattern = v
		emit_changed()
## How far the dither reaches between two levels: 1 blends them over the whole way, 0 gives hard bands (as BANDS).
@export_range(0.0, 1.0, 0.01) var spread: float = 1.0:
	set(v):
		spread = v
		emit_changed()
## On: the pattern is fixed to the world (lined up with the tiles), and lights move over it. Off: each light carries
## its pattern along, laid out from its centre.
@export var world_space: bool = true:
	set(v):
		world_space = v
		emit_changed()
## Shift the pattern over time so the fade shimmers.
@export var animated: bool = false:
	set(v):
		animated = v
		emit_changed()
@export_range(0.5, 30.0, 0.5, "suffix:fps") var frames_per_second: float = 6.0:
	set(v):
		frames_per_second = v
		emit_changed()
## Frames before the shimmer repeats.
@export_range(2, 16) var frames: int = 4:
	set(v):
		frames = maxi(v, 2)
		emit_changed()


## The animation frame shown msec milliseconds in (always 0 when not animated).
func frame_at(msec: int) -> int:
	if not animated:
		return 0
	return int(msec / 1000.0 * frames_per_second) % frames


## How many frames a texture keeps (1 when not animated).
func frame_count() -> int:
	return frames if animated else 1


## The dither threshold (0..1) of the dither pixel at cell, in the given frame.
## Keep in step with threshold() in post/night_grade.gdshader.
func threshold(cell: Vector2i, frame: int) -> float:
	var t: float
	if pattern == Pattern.BANDS:
		return 0.5
	elif pattern == Pattern.NOISE:
		t = _hash(cell, frame)
	else:
		var n := pattern + 1
		var v := 0
		for i in n:
			var xb := (cell.x >> i) & 1
			var yb := (cell.y >> i) & 1
			v += ((xb ^ yb) * 2 + yb) << (2 * (n - 1 - i))
		t = fposmod((v + 0.5) / float(1 << (2 * n)) + float(frame) / frames, 1.0)
	return 0.5 + (t - 0.5) * spread


## threshold() of every dither pixel in a w x h block from origin, row by row, in one go (for drawing textures).
func thresholds(origin: Vector2i, w: int, h: int, frame: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	if pattern == Pattern.BANDS:
		out.fill(0.5)
		return out
	var i := 0
	if pattern == Pattern.NOISE:
		var lo := 0.5 - 0.5 * spread
		for y in range(origin.y, origin.y + h):
			for x in range(origin.x, origin.x + w):
				# _hash, inlined.
				var hv := (x * 374761393 + y * 668265263 + frame * 2246822519) & 0xffffffff
				hv = ((hv ^ (hv >> 13)) * 1274126177) & 0xffffffff
				hv ^= hv >> 16
				out[i] = lo + (hv & 0xffff) / 65536.0 * spread
				i += 1
		return out
	# Bayer: one tile, repeated.
	var p := 1 << (pattern + 1)
	var tile := PackedFloat32Array()
	for ty in p:
		for tx in p:
			tile.append(threshold(Vector2i(tx, ty), frame))
	for y in range(origin.y, origin.y + h):
		var row := (y & (p - 1)) * p
		for x in range(origin.x, origin.x + w):
			out[i] = tile[row + (x & (p - 1))]
			i += 1
	return out


## v (0..1) rounded to one of steps + 1 levels, up or down by the threshold of the dither pixel at cell.
func level(v: float, cell: Vector2i, frame: int) -> float:
	return clampf(floorf(v * steps + threshold(cell, frame)) / steps, 0.0, 1.0)


static func _hash(cell: Vector2i, seed: int) -> float:
	var h := (cell.x * 374761393 + cell.y * 668265263 + seed * 2246822519) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	h ^= h >> 16
	return (h & 0xffff) / 65536.0
