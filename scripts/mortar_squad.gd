class_name MortarSquad
extends Tank
## Light infantry-style indirect-fire squad built from the unit factory.

func _ready() -> void:
	super._ready()
	label = "Mortar Squad"
	speed = 0.68
	vision_radius = Game.VIS_UNIT * 0.92
	attack_range = Game.ATK_RANGE * Game.MORTAR_RANGE_MUL
	attack_damage = Game.ATK_DMG * 0.80
	max_climb_up_steps = 1
	uphill_speed_mul = 0.2
	if attack_timer != null:
		attack_timer.wait_time = 1.45

func get_collision_radius() -> float:
	return Game.TRUCK_COL_R

func get_lift() -> float:
	return Game.surface_lift_at(gx, gy) + 10.0

func _draw() -> void:
	draw_set_transform(-position, 0)
	var lift: float = get_lift()
	var fwd_lift: float = Game.surface_lift_at(gx + heading.x * 0.18, gy + heading.y * 0.18) + 10.0
	var sc: Vector2 = Game.grid_to_world(gx, gy, lift)
	var fwd: Vector2 = Game.grid_to_world(gx + heading.x * 0.18, gy + heading.y * 0.18, fwd_lift)
	var ang: float = atan2(fwd.y - sc.y, fwd.x - sc.x)
	var sel: bool = is_selected()
	var enemy: bool = faction == Game.ENEMY
	var body_c: Color = Color(0.596, 0.314, 0.278) if enemy else Color(0.420, 0.498, 0.318)
	var mortar_c: Color = Color(0.863, 0.812, 0.655) if enemy else Color(0.831, 0.886, 0.720)
	var base_c: Color = Color(0.255, 0.184, 0.141) if enemy else Color(0.227, 0.278, 0.196)
	var edge_c: Color = Color(0.125, 0.055, 0.043, 0.48) if enemy else Color(0.043, 0.055, 0.039, 0.44)
	_ellipse_fill(Vector2(sc.x, sc.y + 12.0), 17.0, 7.0, Color(0.055, 0.071, 0.071, 0.28))
	if sel:
		_ellipse_stroke(Vector2(sc.x, sc.y + 12.0), 20.0, 9.0, Color(1.0, 0.898, 0.561, 0.95), 2.0)
	draw_set_transform(sc - position, ang)
	draw_circle(Vector2(-9.0, -2.0), 3.2, body_c)
	draw_circle(Vector2(-3.5, 3.0), 3.2, body_c)
	draw_circle(Vector2(3.0, -4.0), 3.2, body_c)
	draw_circle(Vector2(8.5, 1.0), 3.2, body_c)
	_poly_fill([
		Vector2(-4.0, 6.0),
		Vector2(7.0, 2.0),
		Vector2(12.0, 8.0),
		Vector2(0.0, 12.0),
	], base_c)
	draw_line(Vector2(0.0, 5.0), Vector2(12.0, -12.0), mortar_c, 3.0)
	draw_line(Vector2(1.0, 5.0), Vector2(8.0, 13.0), mortar_c, 2.0)
	draw_line(Vector2(1.0, 5.0), Vector2(-6.0, 10.0), mortar_c, 2.0)
	draw_circle(Vector2(12.0, -12.0), 2.2, mortar_c)
	draw_set_transform(-position, 0)
	if sel:
		_draw_movable_bars(sc)
	elif status_display_until > Game.elapsed:
		_draw_transient_hp(sc)
