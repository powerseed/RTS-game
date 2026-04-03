class_name Structure
extends DrawHelpers
## Base class for all structures (buildings).

signal destroyed

var entity_id: int = 0
var label: String = ""
var faction: String = Game.PLAYER
var grid_col: int = 0
var grid_row: int = 0
var grid_w: int = 2
var grid_h: int = 2
var hp: float = 1000.0
var max_hp: float = 1000.0
var _pulse: float = 0.0
var _last_visual_sig := ""

func _ready() -> void:
	add_to_group("structures")
	if faction == Game.PLAYER:
		add_to_group("player_structures")
	var tw := create_tween().set_loops()
	tw.tween_property(self, "_pulse", 1.0, 0.7).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "_pulse", 0.0, 0.7).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _process(_dt: float) -> void:
	var ground_lift := Game.surface_lift_at(grid_col + 0.5, grid_row + 0.5)
	position = Game.grid_to_world(grid_col + grid_w, grid_row + grid_h, ground_lift)
	var sel := is_selected()
	var visual_sig := "%0.3f|%0.3f|%s|%0.3f" % [
		position.x,
		position.y,
		sel,
		_pulse if sel else 0.0
	]
	visual_sig += "|%0.1f|%0.1f" % [hp, max_hp]
	if visual_sig != _last_visual_sig:
		_last_visual_sig = visual_sig
		queue_redraw()

func is_selected() -> bool:
	return Game.selected_structure == self

func hp_ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0

func _draw_structure_hp_bar(anchor: Vector2, width: float = 84.0) -> void:
	draw_rect(Rect2(anchor.x - width * 0.5, anchor.y, width, 8.0), Color(0.059, 0.071, 0.090, 0.85))
	draw_rect(
		Rect2(anchor.x - width * 0.5 + 1.0, anchor.y + 1.0, (width - 2.0) * clampf(hp_ratio(), 0.0, 1.0), 6.0),
		Color(0.475, 0.804, 0.443, 0.92))
	draw_rect(Rect2(anchor.x - width * 0.5, anchor.y, width, 8.0), Color(1.0, 0.914, 0.682, 0.46), false, 1.0)
