class_name Grid
## World units. The simulation works in metres (1 tile = 1 m); nodes are placed in pixels.

const PX: float = 32.0


static func to_px(m: Vector2) -> Vector2:
	return m * PX


static func to_m(px: Vector2) -> Vector2:
	return px / PX


static func cell_of(m: Vector2) -> Vector2i:
	return Vector2i(floori(m.x), floori(m.y))
