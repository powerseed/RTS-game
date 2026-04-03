class_name SupplyDepot
extends Structure
## Stores supplies and dispatches supply trucks.

var stored: float = 2000.0
var max_stored: float = 2000.0
var _last_storage_sig := ""

func _ready() -> void:
	super._ready()
	label = "Supply Depot"
	grid_w = 2
	grid_h = 2

func _process(dt: float) -> void:
	super._process(dt)
	var storage_sig := "%0.1f|%0.1f" % [stored, max_stored]
	if storage_sig != _last_storage_sig:
		_last_storage_sig = storage_sig
		queue_redraw()

func _draw() -> void:
	draw_set_transform(-position, 0)  # draw in absolute world coordinates
	var c := grid_col
	var r := grid_row
	var pad := _fp(c - 0.05, r - 0.05, 2.1, 2.1, 0)
	var base := _fp(c + 0.14, r + 0.14, 1.72, 1.72, 0)
	var tb := _fp(c + 0.36, r + 0.34, 1.28, 1.2, 0)
	var hp := Game.BLDG.supply_depot.height_px
	var hatch := _fp(c + 0.82, r + 0.8, 0.34, 0.3, hp + 2)
	var sel := is_selected()
	var pulse := _pulse
	var sr_: float = max_stored if max_stored > 0 else 1
	var ratio: float = stored / sr_
	# shadow
	_poly_fill(_off_pts([pad.nw, pad.ne, pad.se, pad.sw], 24, 16), Color(0.071, 0.094, 0.110, 0.24))
	# pad
	_poly_fill([pad.nw, pad.ne, pad.se, pad.sw], Color(0.420, 0.459, 0.427))
	_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw],
		Color(1, 0.906, 0.588, 0.9) if sel else Color(0.106, 0.129, 0.137, 0.5),
		3.0 if sel else 2.0)
	# base
	_prism(base, 10, Color(0.443, 0.518, 0.490), Color(0.365, 0.427, 0.404), Color(0.294, 0.345, 0.325))
	# tank body
	_prism(tb, hp, Color(0.659, 0.718, 0.753), Color(0.498, 0.553, 0.592), Color(0.404, 0.459, 0.494))
	# hatch
	_poly_fill([hatch.nw, hatch.ne, hatch.se, hatch.sw], Color(0.831, 0.761, 0.510))
	_poly_stroke([hatch.nw, hatch.ne, hatch.se, hatch.sw], Color(0.188, 0.220, 0.227, 0.55), 2)
	# pipe
	_prism(_fp(c + 1.46, r + 0.36, 0.2, 0.24, 8),
		38, Color(0.784, 0.663, 0.420), Color(0.616, 0.518, 0.322), Color(0.510, 0.427, 0.275))
	# supplies bar
	var ba := Game.grid_to_world(c + grid_w * 0.5, r + grid_h * 0.5, hp + 24)
	_draw_structure_hp_bar(Vector2(ba.x, ba.y - 18.0), 84.0)
	_progress_bar(ba.x - 42, ba.y, 84, ratio)
	var font := ThemeDB.fallback_font
	var supply_text := "%d / %d" % [roundi(stored), roundi(max_stored)]
	var font_size := 12
	var text_size := font.get_string_size(supply_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		Vector2(ba.x - text_size.x * 0.5, ba.y - 6.0),
		supply_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.973, 0.945, 0.871)
	)
	if sel:
		_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw],
			Color(1, 0.902, 0.549, 0.6 + pulse * 0.25), 3)
