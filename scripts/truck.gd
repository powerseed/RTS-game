class_name Truck
extends Unit
## Supply truck that transports and distributes supplies to nearby units.

var follow_target: Node2D = null  # unit to follow and resupply
var construction_target: Structure = null
var aura_query_accum_s: float = 0.0
var next_aura_query_at: float = 0.0
var last_aura_query_pos: Vector2 = Vector2(-99999.0, -99999.0)

func _ready() -> void:
	super._ready()
	label = "Supply Truck"
	consumes_supplies = false
	move_supply_per_unit = 0.0
	attack_supply_per_shot = 0.0
	idle_supply_rate = 0.0
	vision_radius = Game.VIS_TRUCK

func get_collision_radius() -> float:
	return Game.TRUCK_COL_R

func get_lift() -> float:
	return Game.surface_lift_at(gx, gy) + 12.0

func _draw() -> void:
	draw_set_transform(-position, 0)  # draw in absolute world coordinates
	var lift := get_lift()
	var fwd_lift := Game.surface_lift_at(gx + heading.x * 0.22, gy + heading.y * 0.22) + 12.0
	var sc := Game.grid_to_world(gx, gy, lift)
	var fwd := Game.grid_to_world(gx + heading.x * 0.22, gy + heading.y * 0.22, fwd_lift)
	var ang := atan2(fwd.y - sc.y, fwd.x - sc.x)
	var sel := is_selected()
	var cr: float = supplies / max_supplies if max_supplies > 0 else 0.0
	# shadow
	_ellipse_fill(Vector2(sc.x, sc.y + 14), 17, 7, Color(0.055, 0.071, 0.071, 0.28))
	if sel:
		_ellipse_stroke(Vector2(sc.x, sc.y + 14), 20, 9, Color(1, 0.898, 0.561, 0.95), 2)
	draw_set_transform(sc - position, ang)
	# wheels
	draw_rect(Rect2(-13, -10, 10, 20), Color(0.235, 0.247, 0.259))
	draw_rect(Rect2(2, -10, 10, 20), Color(0.235, 0.247, 0.259))
	# body
	_poly_fill([Vector2(-12, -6), Vector2(-2, -11), Vector2(10, -8),
				Vector2(12, 6), Vector2(2, 10), Vector2(-10, 7)], Color(0.553, 0.588, 0.475))
	# cab
	_poly_fill([Vector2(-12, -6), Vector2(-2, -11), Vector2(1, -1), Vector2(-8, 3)],
			   Color(0.384, 0.439, 0.357))
	# cargo
	var cc := Color(0.824, 0.698, 0.373) if cr > 0 else Color(0.341, 0.369, 0.384)
	draw_rect(Rect2(-1, -5, 8, 8), cc)
	draw_rect(Rect2(-1, -5, 8, 8), Color(0.067, 0.082, 0.090, 0.55), false, 1)
	draw_set_transform(-position, 0)  # back to world coordinates
	if sel:
		_draw_movable_bars(sc)
