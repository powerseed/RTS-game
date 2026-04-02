class_name Overlay
extends DrawHelpers
## Draws fog of war, tank shells, impact explosions, placement ghost, and truck radius.
## Rendered on top of all entities via z_index. Camera2D-aware world-space drawing.
## Fog is rendered as a single textured polygon updated each frame.

signal shell_hit(shell: Dictionary)

var shells: Array[Dictionary] = []
var explosions: Array[Dictionary] = []

# Fog texture state
var _fog_data: PackedByteArray
var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_pts: PackedVector2Array
var _fog_uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
var _fog_white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _seen_fog_revision: int = -1
var _last_overlay_sig := ""
var _mouse_warning_text: String = ""
var _mouse_warning_world := Vector2.ZERO
var _mouse_warning_until: float = 0.0

func _ready() -> void:
	z_index = 3000
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Pre-allocate fog pixel data (RGBA8: 4 bytes per pixel, RGB always 0)
	var sz := Game.MAP_COLS * Game.MAP_ROWS * 4
	_fog_data = PackedByteArray()
	_fog_data.resize(sz)
	_fog_data.fill(0)
	_fog_img = Image.create_from_data(Game.MAP_COLS, Game.MAP_ROWS, false, Image.FORMAT_RGBA8, _fog_data)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_fog_pts = PackedVector2Array([
		Game.grid_to_world(0, 0),
		Game.grid_to_world(Game.MAP_COLS, 0),
		Game.grid_to_world(Game.MAP_COLS, Game.MAP_ROWS),
		Game.grid_to_world(0, Game.MAP_ROWS),
	])

func _process(dt: float) -> void:
	_update_shells(dt)
	_update_explosions()
	var overlay_sig := _overlay_signature()
	var needs_anim_redraw := not shells.is_empty() or not explosions.is_empty()
	if needs_anim_redraw or overlay_sig != _last_overlay_sig or Game.fog_revision != _seen_fog_revision:
		_last_overlay_sig = overlay_sig
		queue_redraw()

func _draw() -> void:
	_draw_shells()
	_draw_explosions()
	_draw_fog()
	_draw_depot_radius()
	_draw_truck_radius()
	_draw_ghost()
	_draw_mouse_warning()

# Public API
func fire_shell(shell: Dictionary) -> void:
	shell["cx"] = float(shell.get("sx", 0.0))
	shell["cy"] = float(shell.get("sy", 0.0))
	shells.append(shell)

func show_mouse_warning(msg: String, screen_pos: Vector2, duration: float = 0.95) -> void:
	_mouse_warning_text = msg
	_mouse_warning_world = Game.screen_to_world(screen_pos + Vector2(18.0, -14.0))
	_mouse_warning_until = Game.elapsed + maxf(duration, 0.1)
	queue_redraw()

# Shells / explosions
func _update_shells(dt: float) -> void:
	var i := shells.size() - 1
	while i >= 0:
		var shell: Dictionary = shells[i]
		var target: Variant = shell.get("target", null)
		var target_unit: Unit = target as Unit
		if target_unit != null and is_instance_valid(target_unit) and target_unit.hp > 0:
			shell["tx"] = target_unit.gx
			shell["ty"] = target_unit.gy
			shell["tz_lift"] = target_unit.get_lift()
		var shell_pos := Vector2(float(shell.get("cx", 0.0)), float(shell.get("cy", 0.0)))
		var target_pos := Vector2(float(shell.get("tx", 0.0)), float(shell.get("ty", 0.0)))
		var delta := target_pos - shell_pos
		var dist := delta.length()
		var shell_speed: float = float(shell.get("speed", Game.SHELL_SPEED))
		var step := shell_speed * dt
		if dist <= Game.SHELL_HIT_R or step >= dist:
			_add_explosion(String(shell.get("faction", Game.PLAYER)), target_pos.x, target_pos.y)
			emit_signal("shell_hit", shell)
			shells.remove_at(i)
			i -= 1
			continue
		var dir := delta / dist
		shell["cx"] = shell_pos.x + dir.x * step
		shell["cy"] = shell_pos.y + dir.y * step
		shells[i] = shell
		i -= 1

func _update_explosions() -> void:
	var i := explosions.size() - 1
	while i >= 0:
		var explosion: Dictionary = explosions[i]
		if Game.elapsed - float(explosion.get("start_time", 0.0)) >= Game.EXPLOSION_TTL:
			explosions.remove_at(i)
		i -= 1

func _add_explosion(faction: String, gx: float, gy: float) -> void:
	explosions.append({
		"faction": faction,
		"gx": gx,
		"gy": gy,
		"start_time": Game.elapsed,
	})

func _draw_shells() -> void:
	for shell: Dictionary in shells:
		var origin := Vector2(float(shell.get("sx", 0.0)), float(shell.get("sy", 0.0)))
		var shell_pos := Vector2(float(shell.get("cx", 0.0)), float(shell.get("cy", 0.0)))
		var target_pos := Vector2(float(shell.get("tx", 0.0)), float(shell.get("ty", 0.0)))
		var total_len := maxf(origin.distance_to(target_pos), 0.001)
		var travel_t := clampf(origin.distance_to(shell_pos) / total_len, 0.0, 1.0)
		var start_lift: float = float(shell.get("sz_lift", Game.surface_lift_at(origin.x, origin.y) + 19.0))
		var end_lift: float = float(shell.get("tz_lift", Game.surface_lift_at(target_pos.x, target_pos.y) + 4.0))
		var ground_lift: float = Game.surface_lift_at(shell_pos.x, shell_pos.y)
		var arc_base: float = float(shell.get("arc_base", Game.SHELL_ARC_BASE))
		var arc_per_unit: float = float(shell.get("arc_per_unit", Game.SHELL_ARC_PER_UNIT))
		var arc_min: float = float(shell.get("arc_min", 12.0))
		var arc_max: float = float(shell.get("arc_max", 38.0))
		var arc_peak: float = clampf(
			arc_base +
			total_len * arc_per_unit +
			maxf(0.0, start_lift - end_lift) * Game.SHELL_ARC_ELEV_BIAS,
			arc_min,
			arc_max
		)
		var arc_t: float = 4.0 * travel_t * (1.0 - travel_t)
		var shell_lift: float = lerpf(start_lift, end_lift, travel_t) + arc_peak * arc_t
		var sc := Game.grid_to_world(shell_pos.x, shell_pos.y, shell_lift)
		var shadow := Game.grid_to_world(shell_pos.x, shell_pos.y, ground_lift + 2.0)
		var shell_fill := Color(0.149, 0.137, 0.122)
		var faction := String(shell.get("faction", Game.PLAYER))
		var shell_hi := Color(0.859, 0.741, 0.545, 0.8) if faction == Game.PLAYER else Color(0.878, 0.553, 0.475, 0.8)
		_ellipse_fill(shadow, 4.2, 2.2, Color(0.035, 0.031, 0.027, 0.28))
		_ellipse_fill(sc, 4.0, 3.0, shell_fill)
		_ellipse_fill(Vector2(sc.x - 1.0, sc.y - 1.2), 1.4, 1.0, shell_hi)

func _draw_explosions() -> void:
	for e: Dictionary in explosions:
		var start_time := float(e.get("start_time", 0.0))
		var t := clampf((Game.elapsed - start_time) / Game.EXPLOSION_TTL, 0.0, 1.0)
		var c := Game.grid_to_world(float(e.get("gx", 0.0)), float(e.get("gy", 0.0)), 17.0)
		var flash := 18.0 * (1.0 - t * 0.45)
		var ring := 10.0 + t * 18.0
		var smoke := 8.0 + t * 14.0
		var fire_core := Color(1.0, 0.847, 0.467, 0.42 * (1.0 - t))
		var fire_outer := Color(1.0, 0.525, 0.216, 0.56 * (1.0 - t))
		var smoke_col := Color(0.149, 0.133, 0.118, 0.34 * (1.0 - t * 0.7))
		_ellipse_fill(c, flash, flash * 0.62, fire_outer)
		_ellipse_fill(c, flash * 0.58, flash * 0.36, fire_core)
		_ellipse_stroke(c, ring, ring * 0.58, Color(1.0, 0.776, 0.459, 0.85 * (1.0 - t)), 2.0)
		_ellipse_fill(Vector2(c.x, c.y - 2.0), smoke, smoke * 0.5, smoke_col)

func _draw_mouse_warning() -> void:
	if _mouse_warning_text == "" or Game.elapsed >= _mouse_warning_until:
		return
	var font := ThemeDB.fallback_font
	var font_size := 18
	var text_size := font.get_string_size(_mouse_warning_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(12.0, 8.0)
	var box_pos := _mouse_warning_world + Vector2(-6.0, -text_size.y - 10.0)
	var box_size := Vector2(text_size.x + pad.x * 2.0, text_size.y + pad.y * 2.0)
	draw_rect(Rect2(box_pos, box_size), Color(0.125, 0.043, 0.043, 0.88))
	draw_rect(Rect2(box_pos, box_size), Color(0.976, 0.659, 0.576, 0.92), false, 1.5)
	draw_string(
		font,
		box_pos + Vector2(pad.x, pad.y + text_size.y * 0.8),
		_mouse_warning_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(1.0, 0.910, 0.890)
	)

# Fog of war
func _draw_fog() -> void:
	if Game.fog_revision != _seen_fog_revision:
		var vis := Game.fog_vis
		var exp_ := Game.fog_exp
		var total := Game.MAP_COLS * Game.MAP_ROWS
		var idx := 3
		for i in range(total):
			_fog_data[idx] = 0 if vis[i] else (148 if exp_[i] else 240)
			idx += 4
		_fog_img.set_data(Game.MAP_COLS, Game.MAP_ROWS, false, Image.FORMAT_RGBA8, _fog_data)
		_fog_tex.update(_fog_img)
		_seen_fog_revision = Game.fog_revision
	draw_polygon(_fog_pts, _fog_white, _fog_uvs, _fog_tex)

func _overlay_signature() -> String:
	var parts: Array[String] = [
		"sh:" + str(shells.size()),
		"ex:" + str(explosions.size()),
		"bm:" + Game.build_mode,
	]
	if Game.build_mode != "":
		parts.append("ht:" + str(Game.hover_tile.x) + "," + str(Game.hover_tile.y))
	if _mouse_warning_text != "" and Game.elapsed < _mouse_warning_until:
		parts.append("mw:%s:%d:%d" % [_mouse_warning_text, roundi(_mouse_warning_world.x), roundi(_mouse_warning_world.y)])
	var ss = Game.selected_structure
	if ss != null and is_instance_valid(ss) and ss is SupplyDepot:
		parts.append("sd:" + str(ss.get_instance_id()))
	else:
		parts.append("sd:0")
	for u in Game.selected_units:
		if is_instance_valid(u) and u is Truck:
			parts.append("tr:%d:%0.2f:%0.2f" % [u.get_instance_id(), u.gx, u.gy])
	return "|".join(parts)

# Supply depot aura
func _draw_depot_radius() -> void:
	var ss = Game.selected_structure
	if ss == null or not is_instance_valid(ss) or not (ss is SupplyDepot):
		return
	if ss.faction != Game.PLAYER:
		return
	var cx: float = ss.grid_col + ss.grid_w * 0.5
	var cy: float = ss.grid_row + ss.grid_h * 0.5
	var c := Game.grid_to_world(cx, cy, Game.surface_lift_at(cx, cy))
	var rx := Game.DEPOT_SUPPLY_R * Game.BASE_TILE_W * 0.70710678
	var ry := Game.DEPOT_SUPPLY_R * Game.BASE_TILE_H * 0.70710678
	_ellipse_fill(c, rx, ry, Color(0.310, 0.776, 0.902, 0.07))
	_ellipse_stroke(c, rx, ry, Color(0.443, 0.847, 0.957, 0.6), 1.5)

# Truck resupply radius
func _draw_truck_radius() -> void:
	for u in Game.selected_units:
		if not is_instance_valid(u) or not (u is Truck):
			continue
		var c := Game.grid_to_world(u.gx, u.gy, Game.surface_lift_at(u.gx, u.gy))
		var rx := Game.TRUCK_RESUPPLY_R * Game.BASE_TILE_W * 0.70710678
		var ry := Game.TRUCK_RESUPPLY_R * Game.BASE_TILE_H * 0.70710678
		_ellipse_fill(c, rx, ry, Color(0.902, 0.776, 0.310, 0.09))
		_ellipse_stroke(c, rx, ry, Color(0.957, 0.847, 0.443, 0.75), 1.5)

# Placement ghost
func _draw_ghost() -> void:
	var ht := Game.hover_tile
	if Game.build_mode == "" or ht == Vector2i(-1, -1):
		return
	var d := Game.bldg_def(Game.build_mode)
	if d.is_empty():
		return
	var valid := Game.fp_valid(ht.x, ht.y, d.w, d.h)
	var gh := clampf(d.height_px * 0.78, 46, 68)
	var base_lift := Game.elev_units_to_lift(Game.get_elev(ht.x, ht.y))
	var pad := _fp(ht.x, ht.y, d.w, d.h, base_lift)
	var top := _fp(ht.x, ht.y, d.w, d.h, base_lift + (gh if valid else gh * 0.78))
	var glow := Color(1, 0.878, 0.478, 0.22) if valid else Color(1, 0.455, 0.376, 0.24)
	var line := Color(1, 0.929, 0.643, 0.94) if valid else Color(1, 0.647, 0.588, 0.94)
	_poly_fill([pad.nw, pad.ne, pad.se, pad.sw], glow)
	var side_c := Color(1, 0.878, 0.478, 0.18) if valid else Color(1, 0.455, 0.376, 0.18)
	_poly_fill([top.sw, top.se, pad.se, pad.sw], side_c)
	_poly_fill([top.ne, top.se, pad.se, pad.ne], side_c)
	var top_c := Color(1, 0.945, 0.769, 0.2) if valid else Color(1, 0.710, 0.643, 0.16)
	_poly_fill([top.nw, top.ne, top.se, top.sw], top_c)
	_dashed_poly([top.nw, top.ne, top.se, top.sw], line, 10, 6, 2)
