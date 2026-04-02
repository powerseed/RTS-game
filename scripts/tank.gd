class_name Tank
extends Unit
## Armored tank unit with auto-fire combat.

var can_attack: bool = true
var attack_range: float = Game.ATK_RANGE
var attack_damage: float = Game.ATK_DMG
@onready var attack_timer: Timer = $AttackTimer

func _ready() -> void:
	super._ready()
	speed *= 2.0
	if label.is_empty():
		label = "Enemy Tank" if faction == Game.ENEMY else "Tank"

func get_collision_radius() -> float:
	return Game.TANK_COL_R

func get_lift() -> float:
	return Game.surface_lift_at(gx, gy) + 15.0

func _draw() -> void:
	draw_set_transform(-position, 0)  # draw in absolute world coordinates
	var lift := get_lift()
	var fwd_lift := Game.surface_lift_at(gx + heading.x * 0.24, gy + heading.y * 0.24) + 15.0
	var sc := Game.grid_to_world(gx, gy, lift)
	var fwd := Game.grid_to_world(gx + heading.x * 0.24, gy + heading.y * 0.24, fwd_lift)
	var ang := atan2(fwd.y - sc.y, fwd.x - sc.x)
	var sel := is_selected()
	var enemy := faction == Game.ENEMY
	var track_c := Color(0.184, 0.114, 0.114) if enemy else Color(0.110, 0.149, 0.114)
	var hull_c := Color(0.545, 0.278, 0.263) if enemy else Color(0.306, 0.439, 0.318)
	var turret_c := Color(0.435, 0.196, 0.176) if enemy else Color(0.216, 0.325, 0.231)
	var dome_c := Color(0.733, 0.353, 0.314) if enemy else Color(0.373, 0.529, 0.392)
	var barrel_c := Color(0.259, 0.114, 0.114) if enemy else Color(0.133, 0.200, 0.145)
	var edge_c := Color(0.110, 0.039, 0.039, 0.5) if enemy else Color(0.027, 0.043, 0.031, 0.45)
	# shadow
	_ellipse_fill(Vector2(sc.x, sc.y + 17), 21, 9, Color(0.075, 0.094, 0.071, 0.32))
	# selection ring
	if sel:
		_ellipse_stroke(Vector2(sc.x, sc.y + 17), 24, 11, Color(1, 0.898, 0.561, 0.95), 2)
	# rotated body
	draw_set_transform(sc - position, ang)
	# tracks
	draw_rect(Rect2(-15, -12, 30, 8), track_c)
	draw_rect(Rect2(-15, 4, 30, 8), track_c)
	# hull
	_poly_fill([Vector2(-13, 0), Vector2(-5, -12), Vector2(14, -9),
				Vector2(16, 0), Vector2(8, 11), Vector2(-10, 8)], hull_c)
	# turret
	_poly_fill([Vector2(-10, 0), Vector2(-2, -8), Vector2(10, -6),
				Vector2(12, 0), Vector2(6, 7), Vector2(-8, 5)], turret_c)
	# dome
	_ellipse_fill(Vector2(1, -1), 7.5, 5.8, dome_c)
	# barrel
	draw_rect(Rect2(3, -3, 20, 4), barrel_c)
	# track edges
	draw_rect(Rect2(-15, -12, 30, 8), edge_c, false, 1)
	draw_rect(Rect2(-15, 4, 30, 8), edge_c, false, 1)
	draw_set_transform(-position, 0)  # back to world coordinates
	# status bars
	if sel:
		_draw_movable_bars(sc)
	elif _should_draw_status_overlay():
		_draw_transient_hp(sc)
