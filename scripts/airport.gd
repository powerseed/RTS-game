class_name Airport
extends Structure
## Airfield structure placeholder for future aerial production.

func _ready() -> void:
	super._ready()
	label = "Airport"
	grid_w = 4
	grid_h = 3

func _draw() -> void:
	draw_set_transform(-position, 0)
	var c := grid_col
	var r := grid_row
	var pad := _fp(c - 0.08, r - 0.08, 4.16, 3.16, 0)
	var runway := _fp(c + 0.24, r + 0.34, 3.20, 1.08, 0)
	var taxi := _fp(c + 2.46, r + 1.24, 0.86, 1.06, 0)
	var hangar := _fp(c + 0.56, r + 1.52, 1.28, 0.92, 0)
	var tower := _fp(c + 2.86, r + 1.72, 0.36, 0.36, 0)
	var sel := is_selected()
	var pulse := _pulse
	var hp := Game.BLDG.airport.height_px
	_poly_fill(_off_pts([pad.nw, pad.ne, pad.se, pad.sw], 28, 18), Color(0.059, 0.071, 0.082, 0.22))
	_poly_fill([pad.nw, pad.ne, pad.se, pad.sw], Color(0.424, 0.455, 0.439))
	_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw],
		Color(1, 0.906, 0.588, 0.9) if sel else Color(0.102, 0.122, 0.137, 0.46),
		3.0 if sel else 2.0)
	_poly_fill([runway.nw, runway.ne, runway.se, runway.sw], Color(0.251, 0.282, 0.314))
	_poly_stroke([runway.nw, runway.ne, runway.se, runway.sw], Color(0.910, 0.922, 0.933, 0.18), 1.0)
	var center_a := _mix(runway.nw, runway.sw, 0.5)
	var center_b := _mix(runway.ne, runway.se, 0.5)
	draw_line(center_a, center_b, Color(0.973, 0.949, 0.859), 2.0)
	var dash_offsets := [0.18, 0.34, 0.50, 0.66, 0.82]
	for t in dash_offsets:
		var dash_start := _mix(center_a, center_b, t - 0.04)
		var dash_end := _mix(center_a, center_b, t + 0.04)
		draw_line(dash_start, dash_end, Color(0.145, 0.161, 0.173), 2.0)
	_poly_fill([taxi.nw, taxi.ne, taxi.se, taxi.sw], Color(0.471, 0.522, 0.380))
	_prism(hangar, hp, Color(0.694, 0.729, 0.761), Color(0.541, 0.576, 0.612), Color(0.451, 0.482, 0.514))
	var hangar_door_lb := Game.grid_to_world(c + 0.92, r + 2.44, 0)
	var hangar_door_rb := Game.grid_to_world(c + 1.48, r + 2.44, 0)
	var hangar_door_lt := Game.grid_to_world(c + 0.92, r + 2.44, 26)
	var hangar_door_rt := Game.grid_to_world(c + 1.48, r + 2.44, 26)
	_poly_fill([hangar_door_lt, hangar_door_rt, hangar_door_rb, hangar_door_lb], Color(0.176, 0.200, 0.224))
	_prism(tower, hp + 14, Color(0.780, 0.808, 0.827), Color(0.627, 0.659, 0.682), Color(0.537, 0.565, 0.592))
	_poly_fill([
		Game.grid_to_world(c + 2.76, r + 1.62, hp + 18),
		Game.grid_to_world(c + 3.26, r + 1.62, hp + 18),
		Game.grid_to_world(c + 3.26, r + 2.10, hp + 18),
		Game.grid_to_world(c + 2.76, r + 2.10, hp + 18),
	], Color(0.941, 0.800, 0.447))
	if sel:
		_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw], Color(1, 0.902, 0.549, 0.6 + pulse * 0.25), 3.0)
