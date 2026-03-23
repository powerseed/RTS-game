class_name Overlay
extends DrawHelpers
## Draws fog of war, weapon bursts, placement ghost, and truck radius.
## Rendered on top of all entities via z_index. Camera2D-aware world-space drawing.
## Fog is rendered as a single textured polygon updated each frame.

var bursts: Array[Dictionary] = []

# ── fog texture state ────────────────────────────────────────────────────────
var _fog_data: PackedByteArray
var _fog_tex: ImageTexture
var _fog_pts: PackedVector2Array
var _fog_uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
var _fog_white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])

func _ready() -> void:
	z_index = 3000
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Pre-allocate fog pixel data (RGBA8: 4 bytes per pixel, RGB always 0)
	var sz := Game.MAP_COLS * Game.MAP_ROWS * 4
	_fog_data = PackedByteArray()
	_fog_data.resize(sz)
	_fog_data.fill(0)
	var img := Image.create_from_data(Game.MAP_COLS, Game.MAP_ROWS, false, Image.FORMAT_RGBA8, _fog_data)
	_fog_tex = ImageTexture.create_from_image(img)
	_fog_pts = PackedVector2Array([
		Game.grid_to_world(0, 0),
		Game.grid_to_world(Game.MAP_COLS, 0),
		Game.grid_to_world(Game.MAP_COLS, Game.MAP_ROWS),
		Game.grid_to_world(0, Game.MAP_ROWS),
	])

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	_draw_bursts()
	_draw_fog()
	_draw_truck_radius()
	_draw_ghost()

# ── public API ───────────────────────────────────────────────────────────────
func add_burst(b: Dictionary) -> void:
	b.start_time = Game.elapsed
	bursts.append(b)
	get_tree().create_timer(b.max_ttl).timeout.connect(func(): bursts.erase(b))

# ── bursts ───────────────────────────────────────────────────────────────────
func _draw_bursts() -> void:
	for b in bursts:
		var s := Game.grid_to_world(b.sx, b.sy, 21)
		var e := Game.grid_to_world(b.ex, b.ey, 17)
		var a := clampf(1.0 - (Game.elapsed - b.start_time) / b.max_ttl, 0, 1)
		var lc: Color
		var fc: Color
		if b.faction == Game.ENEMY:
			lc = Color(1, 0.471, 0.471, 0.25 + a * 0.75)
			fc = Color(1, 0.541, 0.541, 0.18 + a * 0.5)
		else:
			lc = Color(1, 0.839, 0.471, 0.25 + a * 0.75)
			fc = Color(1, 0.910, 0.698, 0.18 + a * 0.5)
		draw_line(s, e, lc, 2.3)
		_ellipse_fill(e, 3 + a * 2.5, 3 + a * 2.5, fc)

# ── fog of war ───────────────────────────────────────────────────────────────
func _draw_fog() -> void:
	# Write fog alpha into the pixel data — only the alpha byte changes (R,G,B stay 0)
	var vis := Game.fog_vis
	var exp_ := Game.fog_exp
	var total := Game.MAP_COLS * Game.MAP_ROWS
	var idx := 3  # first pixel's alpha byte in RGBA8
	for i in range(total):
		_fog_data[idx] = 0 if vis[i] else (148 if exp_[i] else 240)
		idx += 4
	# Upload to GPU as a single texture, draw as one polygon
	var img := Image.create_from_data(Game.MAP_COLS, Game.MAP_ROWS, false, Image.FORMAT_RGBA8, _fog_data)
	_fog_tex.update(img)
	draw_polygon(_fog_pts, _fog_white, _fog_uvs, _fog_tex)

# ── truck resupply radius ────────────────────────────────────────────────────
func _draw_truck_radius() -> void:
	for u in Game.selected_units:
		if not is_instance_valid(u) or not (u is Truck): continue
		var c := Game.grid_to_world(u.gx, u.gy, 0)
		var rx := Game.TRUCK_RESUPPLY_R * Game.BASE_TILE_W * 0.70710678
		var ry := Game.TRUCK_RESUPPLY_R * Game.BASE_TILE_H * 0.70710678
		_ellipse_fill(c, rx, ry, Color(0.902, 0.776, 0.310, 0.09))
		_ellipse_stroke(c, rx, ry, Color(0.957, 0.847, 0.443, 0.75), 1.5)

# ── placement ghost ──────────────────────────────────────────────────────────
func _draw_ghost() -> void:
	var ht := Game.hover_tile
	if Game.build_mode == "" or ht == Vector2i(-1, -1): return
	var d := Game.bldg_def(Game.build_mode)
	if d.is_empty(): return
	var valid := Game.fp_valid(ht.x, ht.y, d.w, d.h)
	var gh := clampf(d.height_px * 0.78, 46, 68)
	var pad := _fp(ht.x, ht.y, d.w, d.h, 0)
	var top := _fp(ht.x, ht.y, d.w, d.h, gh if valid else gh * 0.78)
	var glow := Color(1, 0.878, 0.478, 0.22) if valid else Color(1, 0.455, 0.376, 0.24)
	var line := Color(1, 0.929, 0.643, 0.94) if valid else Color(1, 0.647, 0.588, 0.94)
	_poly_fill([pad.nw, pad.ne, pad.se, pad.sw], glow)
	var side_c := Color(1, 0.878, 0.478, 0.18) if valid else Color(1, 0.455, 0.376, 0.18)
	_poly_fill([top.sw, top.se, pad.se, pad.sw], side_c)
	_poly_fill([top.ne, top.se, pad.se, pad.ne], side_c)
	var top_c := Color(1, 0.945, 0.769, 0.2) if valid else Color(1, 0.710, 0.643, 0.16)
	_poly_fill([top.nw, top.ne, top.se, top.sw], top_c)
	_dashed_poly([top.nw, top.ne, top.se, top.sw], line, 10, 6, 2)
