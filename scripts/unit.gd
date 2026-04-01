class_name Unit
extends DrawHelpers
## Base class for all movable units (tanks, trucks).

signal died

var entity_id: int = 0
var label: String = ""
var faction: String = Game.PLAYER
var gx: float = 0.0
var gy: float = 0.0
var destination: Variant = null  # Vector2 or null
var path: Array[Vector2] = []
var path_goal: Variant = null  # Vector2 or null
var next_repath_at: float = 0.0
var blind_move: bool = false
var attack_target: Variant = null  # Unit or null
var attack_point: Variant = null  # Vector2 or null
var attack_point_tile: Vector2i = Vector2i(-1, -1)
var attack_point_hits_bridge: bool = false
var attack_point_blind: bool = false
var hp: float = 100.0
var max_hp: float = 100.0
var supplies: float = 100.0
var max_supplies: float = 100.0
var consumes_supplies: bool = true
var accepts_resupply: bool = true
var vision_radius: float = Game.VIS_UNIT
var speed: float = 0.9
var heading := Vector2(1.0, 0.0)
var movable: bool = true
var status_display_until: float = 0.0
var _last_visual_sig := ""

func _ready() -> void:
	add_to_group("units")
	if faction == Game.PLAYER:
		add_to_group("player_units")
	else:
		add_to_group("enemy_units")

func _process(_dt: float) -> void:
	position = Game.grid_to_world(gx, gy, Game.surface_lift_at(gx, gy))
	var visual_sig := "%0.3f|%0.3f|%0.3f|%0.3f|%s|%0.1f|%0.1f|%s" % [
		gx,
		gy,
		heading.x,
		heading.y,
		is_selected(),
		hp,
		supplies,
		status_display_until > Game.elapsed,
	]
	if visual_sig != _last_visual_sig:
		_last_visual_sig = visual_sig
		queue_redraw()

func get_collision_radius() -> float:
	return Game.TANK_COL_R

func get_lift() -> float:
	return Game.surface_lift_at(gx, gy) + 15.0

func is_selected() -> bool:
	return self in Game.selected_units

func screen_pos() -> Vector2:
	return Game.world_to_screen(Game.grid_to_world(gx, gy, get_lift()))

func _draw_transient_hp(sc: Vector2) -> void:
	var bw := 38.0; var bh := 6.0
	var x := sc.x - bw * 0.5; var y := sc.y - 36
	var fw := clampf(hp / max_hp, 0, 1) * (bw - 2)
	draw_rect(Rect2(x, y, bw, bh), Color(0.055, 0.067, 0.078, 0.9))
	draw_rect(Rect2(x + 1, y + 1, fw, bh - 2),
		Color(0.875, 0.420, 0.380) if faction == Game.ENEMY else Color(0.502, 0.827, 0.431))
	draw_rect(Rect2(x, y, bw, bh), Color(1, 0.941, 0.710, 0.6), false, 1)

func _draw_movable_bars(sc: Vector2) -> void:
	var bw := 42.0; var bh := 7.0
	var x := sc.x - bw * 0.5
	var hy := sc.y - 38; var sy := hy + 10
	var hf: float = (hp / max_hp) * (bw - 2) if max_hp > 0 else 0.0
	var sf: float = (supplies / max_supplies) * (bw - 2) if max_supplies > 0 else 0.0
	draw_rect(Rect2(x, hy, bw, bh), Color(0.055, 0.067, 0.078, 0.88))
	draw_rect(Rect2(x, sy, bw, bh), Color(0.055, 0.067, 0.078, 0.88))
	draw_rect(Rect2(x + 1, hy + 1, hf, bh - 2), Color(0.502, 0.827, 0.431))
	draw_rect(Rect2(x + 1, sy + 1, sf, bh - 2), Color(0.886, 0.769, 0.318))
	draw_rect(Rect2(x, hy, bw, bh), Color(1, 0.941, 0.710, 0.7), false, 1)
	draw_rect(Rect2(x, sy, bw, bh), Color(1, 0.941, 0.710, 0.7), false, 1)
