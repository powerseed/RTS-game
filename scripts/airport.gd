class_name Airport
extends Structure
## Airport structure with staged construction driven by delivered supply.

signal construction_completed(site)

var build_supply_required: float = Game.AIRPORT_BUILD_COST
var build_supplied_total: float = 0.0
var build_supply_buffer: float = 0.0
var build_supply_consumed: float = 0.0
var build_supply_rate: float = Game.AIRPORT_BUILD_RATE
var completed: bool = true
var _last_build_sig := ""

func _ready() -> void:
	super._ready()
	label = "Airport"
	grid_w = 6
	grid_h = 4
	max_hp = Game.AIRPORT_BUILD_HP
	build_supply_required = Game.AIRPORT_BUILD_COST
	build_supply_rate = Game.AIRPORT_BUILD_RATE
	_begin_construction()

func _process(dt: float) -> void:
	super._process(dt)
	if is_under_construction():
		_update_construction(dt)
	var build_sig := "%s|%0.1f|%0.1f|%0.1f|%0.1f" % [
		completed,
		hp,
		build_supplied_total,
		build_supply_buffer,
		build_supply_consumed,
	]
	if build_sig != _last_build_sig:
		_last_build_sig = build_sig
		queue_redraw()

func _begin_construction() -> void:
	completed = false
	hp = 0.0
	build_supplied_total = 0.0
	build_supply_buffer = 0.0
	build_supply_consumed = 0.0

func _update_construction(dt: float) -> void:
	if build_supply_buffer <= 0.001 or build_supply_consumed >= build_supply_required - 0.001:
		return
	var consume: float = minf(build_supply_buffer, minf(build_supply_rate * dt, build_supply_required - build_supply_consumed))
	if consume <= 0.0:
		return
	build_supply_buffer = maxf(0.0, build_supply_buffer - consume)
	build_supply_consumed = minf(build_supply_required, build_supply_consumed + consume)
	hp = minf(max_hp, hp + consume)
	if build_supply_consumed >= build_supply_required - 0.001:
		build_supply_consumed = build_supply_required
		build_supply_buffer = 0.0
		completed = true
		construction_completed.emit(self)

func complete_instantly() -> void:
	if completed:
		return
	build_supplied_total = build_supply_required
	build_supply_buffer = 0.0
	build_supply_consumed = build_supply_required
	hp = max_hp
	completed = true
	queue_redraw()
	construction_completed.emit(self)

func is_under_construction() -> bool:
	return not completed

func build_progress_ratio() -> float:
	return build_supply_consumed / build_supply_required if build_supply_required > 0.0 else 1.0

func supply_total_ratio() -> float:
	return build_supplied_total / build_supply_required if build_supply_required > 0.0 else 0.0

func supply_buffer_ratio() -> float:
	return build_supply_buffer / build_supply_required if build_supply_required > 0.0 else 0.0

func build_supply_room() -> float:
	return maxf(0.0, build_supply_required - build_supplied_total)

func can_receive_build_supply() -> bool:
	return is_under_construction() and build_supply_room() > 0.001

func receive_build_supply(amount: float) -> float:
	if amount <= 0.0 or not can_receive_build_supply():
		return 0.0
	var accepted: float = minf(amount, build_supply_room())
	build_supplied_total += accepted
	build_supply_buffer += accepted
	return accepted

func _draw() -> void:
	draw_set_transform(-position, 0)
	if is_under_construction() and hp <= 0.001:
		_draw_blueprint()
	elif is_under_construction():
		_draw_finished_airport()
		_draw_construction_bars()
	else:
		_draw_finished_airport()
		var anchor := Game.grid_to_world(
			float(grid_col) + float(grid_w) * 0.5,
			float(grid_row) + float(grid_h) * 0.5,
			Game.BLDG.airport.height_px + 22.0)
		_draw_structure_hp_bar(anchor, 148.0)

func _draw_blueprint() -> void:
	var c: float = float(grid_col)
	var r: float = float(grid_row)
	var sel := is_selected()
	var pulse: float = _pulse
	var pad := _fp(c - 0.08, r - 0.08, 6.16, 4.16, 0)
	var apron := _fp(c + 0.34, r + 0.56, 5.12, 1.72, 0)
	var runway := _fp(c + 0.38, r + 2.30, 5.12, 1.10, 0)
	var slot_a := _fp(c + 0.92, r + 1.24, 1.48, 0.84, 0)
	var slot_b := _fp(c + 3.08, r + 1.24, 1.48, 0.84, 0)
	var shadow_pts := _off_pts([pad.nw, pad.ne, pad.se, pad.sw], 32, 22)
	_poly_fill(shadow_pts, Color(0.051, 0.067, 0.078, 0.18))
	_poly_fill([pad.nw, pad.ne, pad.se, pad.sw], Color(0.353, 0.467, 0.518, 0.14))
	_dashed_poly([pad.nw, pad.ne, pad.se, pad.sw], Color(0.631, 0.839, 0.949, 0.90), 9.0, 6.0, 2.0)
	_poly_fill([apron.nw, apron.ne, apron.se, apron.sw], Color(0.373, 0.427, 0.459, 0.20))
	_poly_stroke([apron.nw, apron.ne, apron.se, apron.sw], Color(0.859, 0.906, 0.937, 0.24), 1.0)
	_poly_fill([runway.nw, runway.ne, runway.se, runway.sw], Color(0.357, 0.420, 0.455, 0.24))
	_poly_stroke([runway.nw, runway.ne, runway.se, runway.sw], Color(0.875, 0.914, 0.945, 0.38), 1.2)
	var center_a := _mix(runway.nw, runway.sw, 0.5)
	var center_b := _mix(runway.ne, runway.se, 0.5)
	draw_line(center_a, center_b, Color(0.965, 0.949, 0.851, 0.42), 1.8)
	_dashed_poly([slot_a.nw, slot_a.ne, slot_a.se, slot_a.sw], Color(0.973, 0.922, 0.722, 0.84), 6.0, 4.0, 1.6)
	_dashed_poly([slot_b.nw, slot_b.ne, slot_b.se, slot_b.sw], Color(0.973, 0.922, 0.722, 0.84), 6.0, 4.0, 1.6)
	if sel:
		_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw], Color(1.0, 0.925, 0.631, 0.62 + pulse * 0.24), 3.0)
	_draw_construction_bars()

func _draw_construction_bars() -> void:
	var anchor := Game.grid_to_world(
		float(grid_col) + float(grid_w) * 0.5,
		float(grid_row) + float(grid_h) * 0.5,
		40.0)
	var bar_w := 148.0
	var bar_h := 8.0
	var hp_y := anchor.y - 36.0
	var sup_y := hp_y + 18.0
	_draw_bar_with_text(
		anchor.x - bar_w * 0.5,
		hp_y,
		bar_w,
		bar_h,
		hp_ratio(),
		0.0,
		Color(0.475, 0.804, 0.443, 0.92),
		Color(0.475, 0.804, 0.443, 0.92),
		"HP %d / %d" % [roundi(hp), roundi(max_hp)])
	_draw_bar_with_text(
		anchor.x - bar_w * 0.5,
		sup_y,
		bar_w,
		bar_h,
		supply_total_ratio(),
		supply_buffer_ratio(),
		Color(0.678, 0.525, 0.247, 0.86),
		Color(0.973, 0.773, 0.302, 0.95),
		"%d / %d" % [roundi(build_supply_buffer), roundi(build_supply_required)])

func _draw_bar_with_text(x: float, y: float, w: float, h: float, total_ratio: float, active_ratio: float, total_color: Color, active_color: Color, txt: String) -> void:
	draw_rect(Rect2(x, y, w, h), Color(0.055, 0.071, 0.086, 0.84))
	if total_ratio > 0.0:
		draw_rect(Rect2(x + 1.0, y + 1.0, (w - 2.0) * clampf(total_ratio, 0.0, 1.0), h - 2.0), total_color)
	if active_ratio > 0.0:
		draw_rect(Rect2(x + 1.0, y + 1.0, (w - 2.0) * clampf(active_ratio, 0.0, 1.0), h - 2.0), active_color)
	draw_rect(Rect2(x, y, w, h), Color(1.0, 0.914, 0.682, 0.46), false, 1.0)
	var font := ThemeDB.fallback_font
	var font_size := 12
	var size := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		Vector2(x + w * 0.5 - size.x * 0.5, y - 3.0),
		txt,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.973, 0.945, 0.871))

func _draw_finished_airport() -> void:
	var c := grid_col
	var r := grid_row
	var pad := _fp(c - 0.08, r - 0.08, 6.16, 4.16, 0)
	var apron := _fp(c + 0.34, r + 0.56, 5.12, 1.72, 0)
	var runway := _fp(c + 0.38, r + 2.30, 5.12, 1.10, 0)
	var slot_a := _fp(c + 0.92, r + 1.24, 1.48, 0.84, 0)
	var slot_b := _fp(c + 3.08, r + 1.24, 1.48, 0.84, 0)
	var sel := is_selected()
	var pulse := _pulse
	_poly_fill(_off_pts([pad.nw, pad.ne, pad.se, pad.sw], 34, 24), Color(0.059, 0.071, 0.082, 0.22))
	_poly_fill([pad.nw, pad.ne, pad.se, pad.sw], Color(0.424, 0.455, 0.439))
	_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw],
		Color(1, 0.906, 0.588, 0.9) if sel else Color(0.102, 0.122, 0.137, 0.46),
		3.0 if sel else 2.0)
	_poly_fill([apron.nw, apron.ne, apron.se, apron.sw], Color(0.396, 0.435, 0.459))
	_poly_stroke([apron.nw, apron.ne, apron.se, apron.sw], Color(0.910, 0.922, 0.933, 0.12), 1.0)
	_poly_fill([slot_a.nw, slot_a.ne, slot_a.se, slot_a.sw], Color(0.522, 0.565, 0.588))
	_poly_fill([slot_b.nw, slot_b.ne, slot_b.se, slot_b.sw], Color(0.522, 0.565, 0.588))
	_poly_stroke([slot_a.nw, slot_a.ne, slot_a.se, slot_a.sw], Color(0.973, 0.941, 0.812, 0.90), 1.8)
	_poly_stroke([slot_b.nw, slot_b.ne, slot_b.se, slot_b.sw], Color(0.973, 0.941, 0.812, 0.90), 1.8)
	draw_line(_mix(slot_a.nw, slot_a.sw, 0.5), _mix(slot_a.ne, slot_a.se, 0.5), Color(0.973, 0.949, 0.859, 0.88), 1.8)
	draw_line(_mix(slot_b.nw, slot_b.sw, 0.5), _mix(slot_b.ne, slot_b.se, 0.5), Color(0.973, 0.949, 0.859, 0.88), 1.8)
	_poly_fill([runway.nw, runway.ne, runway.se, runway.sw], Color(0.251, 0.282, 0.314))
	_poly_stroke([runway.nw, runway.ne, runway.se, runway.sw], Color(0.910, 0.922, 0.933, 0.18), 1.0)
	var center_a := _mix(runway.nw, runway.sw, 0.5)
	var center_b := _mix(runway.ne, runway.se, 0.5)
	draw_line(center_a, center_b, Color(0.973, 0.949, 0.859), 2.0)
	var dash_offsets := [0.12, 0.24, 0.36, 0.48, 0.60, 0.72, 0.84]
	for t in dash_offsets:
		var dash_start := _mix(center_a, center_b, t - 0.03)
		var dash_end := _mix(center_a, center_b, t + 0.03)
		draw_line(dash_start, dash_end, Color(0.145, 0.161, 0.173), 2.0)
	if sel:
		_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw], Color(1, 0.902, 0.549, 0.6 + pulse * 0.25), 3.0)
