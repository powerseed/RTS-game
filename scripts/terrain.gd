class_name Terrain
extends DrawHelpers
## Renders the isometric terrain (ground tiles, edge faces, backdrop).
## Tile colors are baked into a single texture at startup for performance.

var _terrain_tex: ImageTexture
var _map_pts: PackedVector2Array
var _map_uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
var _map_white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _last_ct := Transform2D()
var _edge_poly := PackedVector2Array([Vector2(), Vector2(), Vector2(), Vector2()])
var _edge_line := PackedVector2Array([Vector2(), Vector2(), Vector2(), Vector2(), Vector2()])

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bake_terrain()
	_map_pts = PackedVector2Array([
		Game.grid_to_world(0, 0),
		Game.grid_to_world(Game.MAP_COLS, 0),
		Game.grid_to_world(Game.MAP_COLS, Game.MAP_ROWS),
		Game.grid_to_world(0, Game.MAP_ROWS),
	])

func _bake_terrain() -> void:
	var img := Image.create(Game.MAP_COLS, Game.MAP_ROWS, false, Image.FORMAT_RGB8)
	var na := Game.noise_a
	for r in range(Game.MAP_ROWS):
		for c in range(Game.MAP_COLS):
			var nA := (na.get_noise_2d(c, r) + 1.0) * 0.5
			var tc: Color
			if nA > 0.7: tc = Color(0.498, 0.659, 0.404)
			elif nA < 0.32: tc = Color(0.435, 0.580, 0.341)
			else: tc = Color(0.471, 0.616, 0.373)
			img.set_pixel(c, r, tc)
	_terrain_tex = ImageTexture.create_from_image(img)

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
	# terrain — single textured polygon replaces thousands of per-tile draws
	draw_polygon(_map_pts, _map_white, _map_uvs, _terrain_tex)
	# south & east edges (only drawn when visible, ~50+40 polygons max)
	var vgr := _visible_grid_rect()
	var sc := clampi(int(vgr[0]) - 3, 0, Game.MAP_COLS - 1)
	var ec := clampi(ceili(vgr[1]) + 3, 0, Game.MAP_COLS - 1)
	var sr := clampi(int(vgr[2]) - 3, 0, Game.MAP_ROWS - 1)
	var er := clampi(ceili(vgr[3]) + 3, 0, Game.MAP_ROWS - 1)
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
