class_name Terrain
extends DrawHelpers
## Renders the isometric terrain (ground tiles, edge faces, backdrop, decorations).
## Tile colors are baked into a single texture at startup for performance.
## Cliff edges and decorations (trees, rocks) are drawn per-tile only for visible tiles.

var _terrain_tex: ImageTexture
var _map_pts: PackedVector2Array
var _map_uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
var _map_white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _last_ct := Transform2D()
var _edge_poly := PackedVector2Array([Vector2(), Vector2(), Vector2(), Vector2()])
var _edge_line := PackedVector2Array([Vector2(), Vector2(), Vector2(), Vector2(), Vector2()])

# Pre-computed decoration list: [col, row, type, size_seed]
var _decorations: Array[Vector4i] = []
const DECO_TREE := 0
const DECO_ROCK := 1
const DECO_BUSH := 2

const CLIFF_H := 14.0  # pixel height of cliff face

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bake_terrain()
	_bake_decorations()
	_map_pts = PackedVector2Array([
		Game.grid_to_world(0, 0),
		Game.grid_to_world(Game.MAP_COLS, 0),
		Game.grid_to_world(Game.MAP_COLS, Game.MAP_ROWS),
		Game.grid_to_world(0, Game.MAP_ROWS),
	])

func _bake_terrain() -> void:
	var img := Image.create(Game.MAP_COLS, Game.MAP_ROWS, false, Image.FORMAT_RGB8)
	for r in range(Game.MAP_ROWS):
		for c in range(Game.MAP_COLS):
			var tt: int = Game.get_tile(c, r)
			var elev: int = Game.get_elev(c, r)
			var elev_t: float = clampf(float(elev) / float(Game.MAX_HILL_ELEV), 0.0, 1.0)
			var tc: Color
			match tt:
				Game.Tile.WATER:
					var nD := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
					if nD > 0.6:
						tc = Color(0.220, 0.380, 0.500)
					elif nD < 0.4:
						tc = Color(0.180, 0.330, 0.460)
					else:
						tc = Color(0.200, 0.355, 0.480)
				Game.Tile.SWAMP:
					var nD := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
					if nD > 0.62:
						tc = Color(0.305, 0.366, 0.222)
					elif nD < 0.38:
						tc = Color(0.242, 0.297, 0.173)
					else:
						tc = Color(0.274, 0.332, 0.198)
				Game.Tile.FOREST:
					var nD := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
					if elev == 1:
						if nD > 0.52:
							tc = Color(0.255, 0.470, 0.237)
						else:
							tc = Color(0.225, 0.430, 0.208)
					else:
						if nD > 0.52:
							tc = Color(0.223, 0.412, 0.196)
						else:
							tc = Color(0.198, 0.370, 0.175)
				Game.Tile.HILL:
					var nD := (Game.noise_d.get_noise_2d(c, r) + 1.0) * 0.5
					if nD > 0.55:
						tc = Color(0.512, 0.542, 0.297).lerp(Color(0.680, 0.710, 0.398), elev_t)
					else:
						tc = Color(0.470, 0.500, 0.274).lerp(Color(0.620, 0.652, 0.364), elev_t)
				_:  # GRASS
					if elev == 1:
						tc = Color(0.490, 0.640, 0.400)
					else:
						tc = Color(0.471, 0.616, 0.373)
			img.set_pixel(c, r, tc)
	_terrain_tex = ImageTexture.create_from_image(img)

func _bake_decorations() -> void:
	# Scatter trees, rocks, bushes on suitable tiles using deterministic hash
	for r in range(Game.MAP_ROWS):
		for c in range(Game.MAP_COLS):
			var tt: int = Game.get_tile(c, r)
			if tt == Game.Tile.WATER: continue
			# Deterministic pseudo-random from coordinates
			var h := (c * 73856093) ^ (r * 19349663)
			var chance := (h % 1000) / 1000.0
			var size_seed: int = (h >> 10) % 100
			if tt == Game.Tile.FOREST:
				if chance < 0.235:
					_decorations.append(Vector4i(c, r, DECO_TREE, size_seed))
				elif chance < 0.268:
					_decorations.append(Vector4i(c, r, DECO_BUSH, size_seed))
				elif chance < 0.280:
					_decorations.append(Vector4i(c, r, DECO_ROCK, size_seed))
			elif tt == Game.Tile.SWAMP:
				if chance < 0.086:
					_decorations.append(Vector4i(c, r, DECO_BUSH, size_seed))
				elif chance < 0.111:
					_decorations.append(Vector4i(c, r, DECO_ROCK, size_seed))
			elif tt == Game.Tile.HILL:
				if chance < 0.062:
					_decorations.append(Vector4i(c, r, DECO_ROCK, size_seed))
				elif chance < 0.095:
					_decorations.append(Vector4i(c, r, DECO_BUSH, size_seed))
			else:
				if chance < 0.017:
					_decorations.append(Vector4i(c, r, DECO_BUSH, size_seed))
				elif chance < 0.024:
					_decorations.append(Vector4i(c, r, DECO_ROCK, size_seed))

func _process(_dt: float) -> void:
	var ct := get_canvas_transform()
	if ct != _last_ct:
		_last_ct = ct
		queue_redraw()

func _visible_grid_rect() -> Array:
	var inv := get_canvas_transform().affine_inverse()
	var vp := get_viewport_rect().size
	var corners := [
		Game.world_to_grid((inv * Vector2.ZERO).x, (inv * Vector2.ZERO).y),
		Game.world_to_grid((inv * Vector2(vp.x, 0)).x, (inv * Vector2(vp.x, 0)).y),
		Game.world_to_grid((inv * Vector2(vp.x, vp.y)).x, (inv * Vector2(vp.x, vp.y)).y),
		Game.world_to_grid((inv * Vector2(0, vp.y)).x, (inv * Vector2(0, vp.y)).y),
	]
	var mnx := minf(minf(corners[0].x, corners[1].x), minf(corners[2].x, corners[3].x))
	var mxx := maxf(maxf(corners[0].x, corners[1].x), maxf(corners[2].x, corners[3].x))
	var mny := minf(minf(corners[0].y, corners[1].y), minf(corners[2].y, corners[3].y))
	var mxy := maxf(maxf(corners[0].y, corners[1].y), maxf(corners[2].y, corners[3].y))
	return [mnx, mxx, mny, mxy]

func _draw() -> void:
	var whole := [_map_pts[0], _map_pts[1], _map_pts[2], _map_pts[3]]
	# shadow
	_poly_fill(_off_pts(whole, 0, Game.BASE_SLAB + 36), Color(0.067, 0.102, 0.063, 0.26))
	# terrain — single textured polygon
	draw_polygon(_map_pts, _map_white, _map_uvs, _terrain_tex)

	var vgr := _visible_grid_rect()
	var sc := clampi(int(vgr[0]) - 3, 0, Game.MAP_COLS - 1)
	var ec := clampi(ceili(vgr[1]) + 3, 0, Game.MAP_COLS - 1)
	var sr := clampi(int(vgr[2]) - 3, 0, Game.MAP_ROWS - 1)
	var er := clampi(ceili(vgr[3]) + 3, 0, Game.MAP_ROWS - 1)

	# cliff edges — draw south and east faces where elevation drops
	_draw_cliffs(sc, ec, sr, er)
	# decorations — only visible tiles
	_draw_decorations(sc, ec, sr, er)

	# map south & east edges
	if er >= Game.MAP_ROWS - 1:
		var col_s := Color(0.341, 0.380, 0.259, 0.72)
		var col_se := Color(0.133, 0.165, 0.102, 0.35)
		for c in range(sc, ec + 1):
			_edge_poly[0] = Game.grid_to_world(c, Game.MAP_ROWS)
			_edge_poly[1] = Game.grid_to_world(c + 1, Game.MAP_ROWS)
			_edge_poly[2] = Vector2(_edge_poly[1].x, _edge_poly[1].y + Game.BASE_SLAB)
			_edge_poly[3] = Vector2(_edge_poly[0].x, _edge_poly[0].y + Game.BASE_SLAB)
			draw_colored_polygon(_edge_poly, col_s)
			_edge_line[0] = _edge_poly[0]; _edge_line[1] = _edge_poly[1]
			_edge_line[2] = _edge_poly[2]; _edge_line[3] = _edge_poly[3]
			_edge_line[4] = _edge_poly[0]
			draw_polyline(_edge_line, col_se, 1)
	if ec >= Game.MAP_COLS - 1:
		var col_e := Color(0.278, 0.318, 0.212, 0.8)
		var col_ee := Color(0.110, 0.133, 0.086, 0.35)
		for r in range(sr, er + 1):
			_edge_poly[0] = Game.grid_to_world(Game.MAP_COLS, r)
			_edge_poly[1] = Game.grid_to_world(Game.MAP_COLS, r + 1)
			_edge_poly[2] = Vector2(_edge_poly[1].x, _edge_poly[1].y + Game.BASE_SLAB)
			_edge_poly[3] = Vector2(_edge_poly[0].x, _edge_poly[0].y + Game.BASE_SLAB)
			draw_colored_polygon(_edge_poly, col_e)
			_edge_line[0] = _edge_poly[0]; _edge_line[1] = _edge_poly[1]
			_edge_line[2] = _edge_poly[2]; _edge_line[3] = _edge_poly[3]
			_edge_line[4] = _edge_poly[0]
			draw_polyline(_edge_line, col_ee, 1)
	# border
	_poly_stroke(whole, Color(1, 0.973, 0.863, 0.08), 2)

# ── cliff edges ───────────────────────────────────────────────────────────────
func _draw_cliffs(sc: int, ec: int, sr: int, er: int) -> void:
	var cliff_south := Color(0.380, 0.340, 0.260)
	var cliff_east := Color(0.320, 0.290, 0.220)
	var cliff_line := Color(0.200, 0.180, 0.140, 0.5)
	for r in range(sr, er + 1):
		for c in range(sc, ec + 1):
			var e := Game.get_elev(c, r)
			if e == 0: continue
			# South face: if tile below is lower
			if r + 1 < Game.MAP_ROWS:
				var south_diff := e - Game.get_elev(c, r + 1)
				if south_diff > 0:
					var bl := Game.grid_to_world(c, r + 1)
					var br := Game.grid_to_world(c + 1, r + 1)
					var south_h := CLIFF_H * float(south_diff)
					var tl := Vector2(bl.x, bl.y - south_h)
					var tr := Vector2(br.x, br.y - south_h)
					_poly_fill([tl, tr, br, bl], cliff_south)
					draw_line(tl, tr, cliff_line, 1.0)
			# East face: if tile to the right is lower
			if c + 1 < Game.MAP_COLS:
				var east_diff := e - Game.get_elev(c + 1, r)
				if east_diff > 0:
					var tl := Game.grid_to_world(c + 1, r)
					var bl := Game.grid_to_world(c + 1, r + 1)
					var east_h := CLIFF_H * float(east_diff)
					var tr := Vector2(tl.x, tl.y - east_h)
					var br := Vector2(bl.x, bl.y - east_h)
					_poly_fill([tr, br, bl, tl], cliff_east)
					draw_line(tr, br, cliff_line, 1.0)

# ── decorations ───────────────────────────────────────────────────────────────
func _draw_decorations(sc: int, ec: int, sr: int, er: int) -> void:
	for d in _decorations:
		var c: int = d.x
		var r: int = d.y
		if c < sc or c > ec or r < sr or r > er: continue
		var sz: float = 0.7 + (d.w % 50) / 100.0  # 0.7 - 1.2 scale factor
		var cx: float = c + 0.5
		var cy: float = r + 0.5
		var elev: int = Game.get_elev(c, r)
		var lift: float = CLIFF_H * float(elev)
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
	# shadow
	_ellipse_fill(Vector2(base.x + 4, base.y + 4), crown_rx * 0.8, crown_ry * 0.6, Color(0.06, 0.08, 0.04, 0.2))
	# trunk
	var trunk_top := Vector2(base.x, base.y - trunk_h)
	draw_line(base, trunk_top, Color(0.350, 0.260, 0.160), 2.5 * sz)
	# crown layers (overlapping ellipses for volume)
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
	# shadow
	_ellipse_fill(Vector2(base.x + 3, base.y + 3), rx * 0.8, ry * 0.6, Color(0.06, 0.08, 0.04, 0.18))
	# rock body (stacked ellipses for 3D look)
	var top := Vector2(base.x, base.y - 5 * sz)
	_ellipse_fill(base, rx, ry, Color(0.420, 0.400, 0.370))
	_ellipse_fill(Vector2(base.x, base.y - 2.5 * sz), rx * 0.9, ry * 0.85, Color(0.480, 0.460, 0.420))
	_ellipse_fill(top, rx * 0.7, ry * 0.6, Color(0.540, 0.520, 0.480))

func _draw_bush(cx: float, cy: float, sz: float, lift: float) -> void:
	var base := Game.grid_to_world(cx, cy, lift)
	var rx := 6.5 * sz
	var ry := 4.0 * sz
	# shadow
	_ellipse_fill(Vector2(base.x + 2, base.y + 3), rx * 0.7, ry * 0.5, Color(0.06, 0.08, 0.04, 0.15))
	# bush (two overlapping green ellipses)
	_ellipse_fill(Vector2(base.x, base.y - 2 * sz), rx, ry, Color(0.300, 0.480, 0.260))
	_ellipse_fill(Vector2(base.x + 1.5 * sz, base.y - 3.5 * sz), rx * 0.7, ry * 0.65, Color(0.350, 0.520, 0.300))
