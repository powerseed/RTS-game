class_name TerrainBand
extends DrawHelpers
## Draws a contiguous band of isometric terrain sums so Godot can cull strips cheaply.

const DECO_TREE := 0
const DECO_ROCK := 1
const DECO_BUSH := 2

var sum_start: int = 0
var sum_end: int = 0
var decorations: Array = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func _draw() -> void:
	for sum in range(sum_start, sum_end + 1):
		for r in range(Game.MAP_ROWS):
			var c := sum - r
			if c < 0 or c >= Game.MAP_COLS:
				continue
			_draw_tile(c, r)
		_draw_decorations_for_sum(sum)

func _draw_tile(c: int, r: int) -> void:
	var tt: int = Game.get_tile(c, r)
	var top := Game.tile_top_poly(c, r)
	var tc := _tile_color(c, r, tt)
	_draw_south_face(c, r, top, tt)
	_draw_east_face(c, r, top, tt)
	draw_colored_polygon(top, tc)
	_poly_stroke(top, Color(0.035, 0.043, 0.031, 0.18), 1.0)
	_draw_ramp_mark(c, r, top)

func _draw_south_face(c: int, r: int, top: PackedVector2Array, tt: int) -> void:
	var cur_sw_h := Game.corner_elev_units(c, r, Game.Corner.SW)
	var cur_se_h := Game.corner_elev_units(c, r, Game.Corner.SE)
	var next_nw_h := 0.0
	var next_ne_h := 0.0
	var bl: Vector2
	var br: Vector2
	if r + 1 < Game.MAP_ROWS:
		next_nw_h = Game.corner_elev_units(c, r + 1, Game.Corner.NW)
		next_ne_h = Game.corner_elev_units(c, r + 1, Game.Corner.NE)
		bl = Game.grid_to_world(c, r + 1, Game.elev_units_to_lift(next_nw_h))
		br = Game.grid_to_world(c + 1, r + 1, Game.elev_units_to_lift(next_ne_h))
	else:
		bl = Game.grid_to_world(c, r + 1, 0.0)
		br = Game.grid_to_world(c + 1, r + 1, 0.0)
	if (cur_sw_h + cur_se_h) * 0.5 <= (next_nw_h + next_ne_h) * 0.5 + 0.01:
		return
	var fc := _south_face_color(tt)
	draw_colored_polygon(PackedVector2Array([top[3], top[2], br, bl]), fc)
	draw_line(top[3], top[2], Color(0.157, 0.141, 0.114, 0.45), 1.0)

func _draw_east_face(c: int, r: int, top: PackedVector2Array, tt: int) -> void:
	var cur_ne_h := Game.corner_elev_units(c, r, Game.Corner.NE)
	var cur_se_h := Game.corner_elev_units(c, r, Game.Corner.SE)
	var next_nw_h := 0.0
	var next_sw_h := 0.0
	var tl: Vector2
	var bl: Vector2
	if c + 1 < Game.MAP_COLS:
		next_nw_h = Game.corner_elev_units(c + 1, r, Game.Corner.NW)
		next_sw_h = Game.corner_elev_units(c + 1, r, Game.Corner.SW)
		tl = Game.grid_to_world(c + 1, r, Game.elev_units_to_lift(next_nw_h))
		bl = Game.grid_to_world(c + 1, r + 1, Game.elev_units_to_lift(next_sw_h))
	else:
		tl = Game.grid_to_world(c + 1, r, 0.0)
		bl = Game.grid_to_world(c + 1, r + 1, 0.0)
	if (cur_ne_h + cur_se_h) * 0.5 <= (next_nw_h + next_sw_h) * 0.5 + 0.01:
		return
	var fc := _east_face_color(tt)
	draw_colored_polygon(PackedVector2Array([top[1], top[2], bl, tl]), fc)
	draw_line(top[1], top[2], Color(0.129, 0.118, 0.094, 0.45), 1.0)

func _draw_ramp_mark(c: int, r: int, top: PackedVector2Array) -> void:
	var ramp := Game.get_ramp(c, r)
	if ramp == Game.Ramp.NONE:
		return
	var low_center := Vector2.ZERO
	var high_center := Vector2.ZERO
	match ramp:
		Game.Ramp.NORTH:
			low_center = (top[0] + top[1]) * 0.5
			high_center = (top[3] + top[2]) * 0.5
		Game.Ramp.EAST:
			low_center = (top[1] + top[2]) * 0.5
			high_center = (top[0] + top[3]) * 0.5
		Game.Ramp.SOUTH:
			low_center = (top[3] + top[2]) * 0.5
			high_center = (top[0] + top[1]) * 0.5
		Game.Ramp.WEST:
			low_center = (top[0] + top[3]) * 0.5
			high_center = (top[1] + top[2]) * 0.5
	draw_line(low_center, high_center, Color(1.0, 0.925, 0.702, 0.55), 2.0)

func _tile_color(c: int, r: int, tt: int) -> Color:
	var elev_t: float = clampf(float(Game.get_elev(c, r)) / float(Game.MAX_HILL_ELEV), 0.0, 1.0)
	match tt:
		Game.Tile.WATER:
			var nD := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
			if nD > 0.6:
				return Color(0.220, 0.380, 0.500)
			elif nD < 0.4:
				return Color(0.180, 0.330, 0.460)
			return Color(0.200, 0.355, 0.480)
		Game.Tile.BRIDGE:
			var nD_bridge := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
			if nD_bridge > 0.55:
				return Color(0.600, 0.455, 0.240)
			elif nD_bridge < 0.35:
				return Color(0.520, 0.382, 0.192)
			return Color(0.560, 0.418, 0.215)
		Game.Tile.SWAMP:
			var nD2 := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
			if nD2 > 0.62:
				return Color(0.305, 0.366, 0.222)
			elif nD2 < 0.38:
				return Color(0.242, 0.297, 0.173)
			return Color(0.274, 0.332, 0.198)
		Game.Tile.FOREST:
			var nD3 := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
			if nD3 > 0.52:
				return Color(0.223, 0.412, 0.196)
			return Color(0.198, 0.370, 0.175)
		Game.Tile.HILL:
			var nD4 := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
			if nD4 > 0.55:
				return Color(0.512, 0.542, 0.297).lerp(Color(0.756, 0.784, 0.455), elev_t)
			return Color(0.470, 0.500, 0.274).lerp(Color(0.698, 0.725, 0.412), elev_t)
		_:
			return Color(0.471, 0.616, 0.373)

func _south_face_color(tt: int) -> Color:
	match tt:
		Game.Tile.BRIDGE:
			return Color(0.420, 0.295, 0.155)
		Game.Tile.HILL:
			return Color(0.443, 0.396, 0.286)
		Game.Tile.SWAMP:
			return Color(0.239, 0.271, 0.173)
		Game.Tile.FOREST:
			return Color(0.204, 0.282, 0.165)
		_:
			return Color(0.341, 0.380, 0.259)

func _east_face_color(tt: int) -> Color:
	match tt:
		Game.Tile.BRIDGE:
			return Color(0.360, 0.252, 0.130)
		Game.Tile.HILL:
			return Color(0.365, 0.329, 0.235)
		Game.Tile.SWAMP:
			return Color(0.204, 0.231, 0.145)
		Game.Tile.FOREST:
			return Color(0.176, 0.243, 0.141)
		_:
			return Color(0.278, 0.318, 0.212)

func _draw_decorations_for_sum(sum: int) -> void:
	for item in decorations:
		var d: Vector4i = item
		if d.x + d.y != sum:
			continue
		var c: int = d.x
		var r: int = d.y
		var sz: float = 0.7 + (d.w % 50) / 100.0
		var cx: float = c + 0.5
		var cy: float = r + 0.5
		var lift: float = Game.surface_lift_at(cx, cy)
		match d.z:
			DECO_TREE:
				_draw_tree(cx, cy, sz, lift)
			DECO_ROCK:
				_draw_rock(cx, cy, sz, lift)
			DECO_BUSH:
				_draw_bush(cx, cy, sz, lift)

func _draw_tree(cx: float, cy: float, sz: float, lift: float) -> void:
	var base := Game.grid_to_world(cx, cy, lift)
	var trunk_h := 18.0 * sz
	var crown_rx := 9.0 * sz
	var crown_ry := 6.5 * sz
	_ellipse_fill(Vector2(base.x + 4, base.y + 4), crown_rx * 0.8, crown_ry * 0.6, Color(0.06, 0.08, 0.04, 0.2))
	var trunk_top := Vector2(base.x, base.y - trunk_h)
	draw_line(base, trunk_top, Color(0.350, 0.260, 0.160), 2.5 * sz)
	var c1 := Vector2(base.x, base.y - trunk_h - crown_ry * 0.3)
	var c2 := Vector2(base.x - 2 * sz, base.y - trunk_h - crown_ry * 0.8)
	var c3 := Vector2(base.x + 1.5 * sz, base.y - trunk_h - crown_ry * 1.2)
	_ellipse_fill(c1, crown_rx, crown_ry, Color(0.280, 0.460, 0.240))
	_ellipse_fill(c2, crown_rx * 0.8, crown_ry * 0.75, Color(0.310, 0.500, 0.270))
	_ellipse_fill(c3, crown_rx * 0.7, crown_ry * 0.65, Color(0.340, 0.530, 0.290))

func _draw_rock(cx: float, cy: float, sz: float, lift: float) -> void:
	var base := Game.grid_to_world(cx, cy, lift)
	var rx := 7.0 * sz
	var ry := 4.5 * sz
	_ellipse_fill(Vector2(base.x + 3, base.y + 3), rx * 0.8, ry * 0.6, Color(0.06, 0.08, 0.04, 0.18))
	var top := Vector2(base.x, base.y - 5 * sz)
	_ellipse_fill(base, rx, ry, Color(0.420, 0.400, 0.370))
	_ellipse_fill(Vector2(base.x, base.y - 2.5 * sz), rx * 0.9, ry * 0.85, Color(0.480, 0.460, 0.420))
	_ellipse_fill(top, rx * 0.7, ry * 0.6, Color(0.540, 0.520, 0.480))

func _draw_bush(cx: float, cy: float, sz: float, lift: float) -> void:
	var base := Game.grid_to_world(cx, cy, lift)
	var rx := 6.5 * sz
	var ry := 4.0 * sz
	_ellipse_fill(Vector2(base.x + 2, base.y + 3), rx * 0.7, ry * 0.5, Color(0.06, 0.08, 0.04, 0.15))
	_ellipse_fill(Vector2(base.x, base.y - 2 * sz), rx, ry, Color(0.300, 0.480, 0.260))
	_ellipse_fill(Vector2(base.x + 1.5 * sz, base.y - 3.5 * sz), rx * 0.7, ry * 0.65, Color(0.350, 0.520, 0.300))
