class_name UnitIcon
extends Control
## Simple vector icon for unit rows in the production panel.

var unit_type: String = Game.T_TANK

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(44, 44)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.071, 0.086, 0.098, 0.88))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.906, 0.659, 0.20), false, 1.0)
	match unit_type:
		Game.T_AIRPORT:
			_draw_airport_icon()
		Game.T_MORTAR:
			_draw_mortar_icon()
		Game.T_TANK:
			_draw_tank_icon()
		_:
			_draw_placeholder_icon()

func _draw_airport_icon() -> void:
	var runway := Rect2(size.x * 0.20, size.y * 0.14, size.x * 0.60, size.y * 0.72)
	draw_rect(runway, Color(0.365, 0.404, 0.427))
	draw_rect(runway, Color(0.820, 0.843, 0.871, 0.20), false, 1.0)
	draw_line(Vector2(size.x * 0.50, size.y * 0.18), Vector2(size.x * 0.50, size.y * 0.80), Color(0.937, 0.925, 0.839), 2.0)
	draw_line(Vector2(size.x * 0.50, size.y * 0.26), Vector2(size.x * 0.50, size.y * 0.34), Color(0.204, 0.224, 0.235), 2.0)
	draw_line(Vector2(size.x * 0.50, size.y * 0.46), Vector2(size.x * 0.50, size.y * 0.54), Color(0.204, 0.224, 0.235), 2.0)
	draw_line(Vector2(size.x * 0.50, size.y * 0.66), Vector2(size.x * 0.50, size.y * 0.74), Color(0.204, 0.224, 0.235), 2.0)
	var tower := Rect2(size.x * 0.66, size.y * 0.22, size.x * 0.12, size.y * 0.30)
	var cab := Rect2(size.x * 0.62, size.y * 0.16, size.x * 0.20, size.y * 0.10)
	draw_rect(tower, Color(0.663, 0.694, 0.722))
	draw_rect(cab, Color(0.918, 0.780, 0.443))
	draw_rect(Rect2(size.x * 0.22, size.y * 0.58, size.x * 0.16, size.y * 0.12), Color(0.541, 0.596, 0.631))

func _draw_tank_icon() -> void:
	var hull := Rect2(size.x * 0.18, size.y * 0.54, size.x * 0.64, size.y * 0.16)
	var turret := Rect2(size.x * 0.34, size.y * 0.34, size.x * 0.28, size.y * 0.16)
	var barrel_a := Vector2(size.x * 0.62, size.y * 0.42)
	var barrel_b := Vector2(size.x * 0.82, size.y * 0.32)
	draw_rect(hull, Color(0.620, 0.674, 0.420))
	draw_rect(turret, Color(0.769, 0.792, 0.541))
	draw_line(barrel_a, barrel_b, Color(0.902, 0.918, 0.690), 3.0)
	draw_circle(Vector2(size.x * 0.32, size.y * 0.76), 4.0, Color(0.271, 0.302, 0.216))
	draw_circle(Vector2(size.x * 0.50, size.y * 0.76), 4.0, Color(0.271, 0.302, 0.216))
	draw_circle(Vector2(size.x * 0.68, size.y * 0.76), 4.0, Color(0.271, 0.302, 0.216))

func _draw_mortar_icon() -> void:
	var base := Rect2(size.x * 0.28, size.y * 0.60, size.x * 0.34, size.y * 0.10)
	var plate := PackedVector2Array([
		Vector2(size.x * 0.22, size.y * 0.78),
		Vector2(size.x * 0.48, size.y * 0.64),
		Vector2(size.x * 0.74, size.y * 0.78),
		Vector2(size.x * 0.48, size.y * 0.88),
	])
	var tube_a := Vector2(size.x * 0.46, size.y * 0.58)
	var tube_b := Vector2(size.x * 0.68, size.y * 0.24)
	draw_colored_polygon(plate, Color(0.286, 0.337, 0.235))
	draw_rect(base, Color(0.514, 0.569, 0.404))
	draw_line(tube_a, tube_b, Color(0.867, 0.910, 0.733), 4.0)
	draw_circle(Vector2(size.x * 0.26, size.y * 0.42), 3.0, Color(0.918, 0.867, 0.671))
	draw_circle(Vector2(size.x * 0.37, size.y * 0.36), 3.0, Color(0.918, 0.867, 0.671))
	draw_circle(Vector2(size.x * 0.58, size.y * 0.80), 3.0, Color(0.918, 0.867, 0.671))

func _draw_placeholder_icon() -> void:
	draw_line(Vector2(size.x * 0.24, size.y * 0.24), Vector2(size.x * 0.76, size.y * 0.76), Color(0.820, 0.698, 0.431), 3.0)
	draw_line(Vector2(size.x * 0.76, size.y * 0.24), Vector2(size.x * 0.24, size.y * 0.76), Color(0.820, 0.698, 0.431), 3.0)
