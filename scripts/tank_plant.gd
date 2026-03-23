class_name TankPlant
extends Structure
## Tank production facility. Produces tanks automatically via a Timer node.

signal tank_produced(plant: TankPlant)

@onready var production_timer: Timer = $ProductionTimer
var produced: int = 0

func _ready() -> void:
	super._ready()
	label = "Tank Plant"
	grid_w = 2
	grid_h = 2
	production_timer.timeout.connect(_on_production_timeout)
	production_timer.start(0.8)

func _on_production_timeout() -> void:
	produced += 1
	tank_produced.emit(self)

func get_production_progress() -> float:
	if production_timer and not production_timer.is_stopped():
		return 1.0 - clampf(production_timer.time_left / production_timer.wait_time, 0, 1)
	return 0.0

func _draw() -> void:
	draw_set_transform(-position, 0)  # draw in absolute world coordinates
	var c := grid_col
	var r := grid_row
	var pad := _fp(c - 0.08, r - 0.08, 2.16, 2.16, 0)
	var base := _fp(c + 0.14, r + 0.16, 1.72, 1.62, 0)
	var shell := _fp(c + 0.2, r + 0.18, 1.58, 1.5, 0)
	var sel := is_selected()
	var pulse := _pulse
	# shadow
	_poly_fill(_off_pts([pad.nw, pad.ne, pad.se, pad.sw], 28, 18), Color(0.078, 0.098, 0.102, 0.22))
	# pad
	_poly_fill([pad.nw, pad.ne, pad.se, pad.sw], Color(0.451, 0.451, 0.424))
	_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw],
		Color(1, 0.906, 0.588, 0.9) if sel else Color(0.118, 0.133, 0.141, 0.45),
		3.0 if sel else 2.0)
	# base + shell prisms
	_prism(base, 10, Color(0.525, 0.522, 0.482), Color(0.412, 0.412, 0.376), Color(0.349, 0.345, 0.310))
	var hp := Game.BLDG.tank_plant.height_px
	_prism(shell, hp, Color(0.486, 0.553, 0.596), Color(0.380, 0.447, 0.490), Color(0.310, 0.361, 0.392))
	# roof inset
	var ri := _fp(c + 0.46, r + 0.44, 0.88, 0.7, hp + 1)
	_poly_fill([ri.nw, ri.ne, ri.se, ri.sw], Color(0.843, 0.725, 0.416))
	# smokestack
	_prism(_fp(c + 0.42, r + 0.44, 0.28, 0.28, hp),
		34, Color(0.604, 0.647, 0.678), Color(0.463, 0.502, 0.541), Color(0.400, 0.439, 0.471))
	# vent
	_prism(_fp(c + 1.08, r + 0.42, 0.26, 0.36, hp),
		22, Color(0.698, 0.722, 0.741), Color(0.545, 0.576, 0.596), Color(0.471, 0.502, 0.522))
	# door
	var dlb := Game.grid_to_world(c + 0.78, r + grid_h, 0)
	var drb := Game.grid_to_world(c + 1.34, r + grid_h, 0)
	var dlt := Game.grid_to_world(c + 0.78, r + grid_h, 26)
	var drt := Game.grid_to_world(c + 1.34, r + grid_h, 26)
	_poly_fill([dlt, drt, drb, dlb], Color(0.157, 0.188, 0.212))
	# yellow strip
	var sl := Game.grid_to_world(c + 0.72, r + grid_h, 34)
	var sr_ := Game.grid_to_world(c + 1.4, r + grid_h, 34)
	var slr := Game.grid_to_world(c + 1.4, r + grid_h, 26)
	var sll := Game.grid_to_world(c + 0.72, r + grid_h, 26)
	_poly_fill([sl, sr_, slr, sll], Color(1, 0.863, 0.467, 0.74))
	# factory bay
	var fb := _fp(c + 0.95, r + 0.98, 0.72, 0.48, 40)
	_poly_fill([fb.nw, fb.ne, fb.se, fb.sw], Color(0.082, 0.102, 0.118, 0.25))
	# progress bar
	var prog := get_production_progress()
	var ba := Game.grid_to_world(c + grid_w * 0.5, r + grid_h * 0.5, hp + 32)
	_progress_bar(ba.x - 42, ba.y, 84, prog)
	# selection glow
	if sel:
		_poly_stroke([pad.nw, pad.ne, pad.se, pad.sw],
			Color(1, 0.902, 0.549, 0.6 + pulse * 0.25), 3)
