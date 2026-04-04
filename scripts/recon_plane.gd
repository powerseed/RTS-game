class_name ReconPlane
extends Unit
## Reconnaissance plane that can taxi-free fly between map points.

var home_airport_id: int = 0
var home_slot: Variant = null  # Vector2 or null
var low_fuel_returning: bool = false
var crash_on_return_arrival: bool = false
var return_target: Variant = null  # Vector2 or null
var _parked: bool = true
var flight_elev_steps: float = 7.0

func _ready() -> void:
	super._ready()
	label = "Reconnaissance Plane"
	z_index = 40
	hp = 50.0
	max_hp = 50.0
	movable = false
	speed = 3.0
	vision_radius = Game.VIS_UNIT * 2.0
	consumes_supplies = true
	accepts_resupply = true
	move_supply_per_unit = Game.SUP_PER_UNIT * 2.0
	attack_supply_per_shot = 0.0
	idle_supply_rate = 0.0
	supplies = 300.0
	max_supplies = 300.0
	visibility_signature = 1.0
	destination = null
	blind_move = false
	attack_target = null
	attack_structure_target = null
	attack_point = null
	_parked = is_parked()

func _process(dt: float) -> void:
	var parked_now: bool = is_parked()
	if parked_now != _parked:
		_parked = parked_now
		_last_visual_sig = ""
	super._process(dt)

func _airport_slot_positions(airport: Airport) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	slots.append(Vector2(airport.grid_col + 1.66, airport.grid_row + 1.66))
	slots.append(Vector2(airport.grid_col + 3.82, airport.grid_row + 1.66))
	return slots

func is_parked() -> bool:
	if destination != null:
		return false
	var plane_pos := Vector2(gx, gy)
	for s_node in Game.get_structures():
		var airport: Airport = s_node as Airport
		if airport == null or airport.faction != faction or airport.is_under_construction():
			continue
		for slot in _airport_slot_positions(airport):
			if plane_pos.distance_to(slot) < 0.46:
				return true
	return false

func get_collision_radius() -> float:
	return 0.0

func get_lift() -> float:
	return Game.surface_lift_at(gx, gy) if _parked else Game.elev_units_to_lift(flight_elev_steps)

func get_eye_lift() -> float:
	return Game.surface_lift_at(gx, gy) if _parked else Game.elev_units_to_lift(flight_elev_steps)

func affected_by_ground_concealment() -> bool:
	return false

func _draw() -> void:
	draw_set_transform(-position, 0)
	var sc := Game.grid_to_world(gx, gy, get_lift())
	var ground_sc := Game.grid_to_world(gx, gy, Game.surface_lift_at(gx, gy) + 2.0)
	var enemy: bool = faction == Game.ENEMY
	var wing_c: Color = Color(0.647, 0.690, 0.741) if enemy else Color(0.620, 0.725, 0.780)
	var body_c: Color = Color(0.878, 0.831, 0.788) if enemy else Color(0.859, 0.894, 0.925)
	var glass_c: Color = Color(0.376, 0.235, 0.216) if enemy else Color(0.255, 0.420, 0.490)
	_ellipse_fill(Vector2(ground_sc.x, ground_sc.y + 9.0), 24.0, 8.0, Color(0.043, 0.055, 0.071, 0.28))
	draw_set_transform(sc - position, -0.22)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-20.0, 5.0),
		Vector2(-5.0, -3.0),
		Vector2(18.0, -3.0),
		Vector2(26.0, 0.0),
		Vector2(18.0, 5.0),
		Vector2(-4.0, 9.0),
	]), body_c)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4.0, -1.0),
		Vector2(10.0, -15.0),
		Vector2(20.0, -1.0),
		Vector2(11.0, 0.0),
		Vector2(7.0, -4.0),
		Vector2(3.0, 0.0),
	]), wing_c)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-18.0, 5.0),
		Vector2(-24.0, -5.0),
		Vector2(-12.0, 3.0),
	]), wing_c)
	draw_colored_polygon(PackedVector2Array([
		Vector2(4.0, 0.0),
		Vector2(11.0, -1.0),
		Vector2(10.0, 4.0),
		Vector2(3.0, 4.0),
	]), glass_c)
	draw_line(Vector2(-3.0, 2.0), Vector2(22.0, 2.0), Color(0.173, 0.212, 0.231, 0.64), 1.8)
	draw_set_transform(-position, 0)
	if is_selected():
		_draw_movable_bars(sc)
	elif _should_draw_status_overlay():
		_draw_transient_hp(sc)
