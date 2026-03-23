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
var _pulse: float = 0.0

func _ready() -> void:
	add_to_group("structures")
	if faction == Game.PLAYER:
		add_to_group("player_structures")
	var tw := create_tween().set_loops()
	tw.tween_property(self, "_pulse", 1.0, 0.7).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "_pulse", 0.0, 0.7).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _process(_dt: float) -> void:
	position = Game.grid_to_world(grid_col + grid_w, grid_row + grid_h, 0)
	queue_redraw()

func is_selected() -> bool:
	return Game.selected_structure == self
