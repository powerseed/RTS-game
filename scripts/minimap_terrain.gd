extends Control
## Static terrain layer for the isometric minimap.

const C_BG := Color(0.047, 0.055, 0.063, 0.92)
const C_BORDER := Color(1.0, 0.906, 0.659, 0.26)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var mm: MiniMap = get_parent() as MiniMap
	if mm == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	for sum in range(Game.MAP_COLS + Game.MAP_ROWS - 1):
		for r in range(Game.MAP_ROWS):
			var c := sum - r
			if c < 0 or c >= Game.MAP_COLS:
				continue
			draw_colored_polygon(mm.tile_poly(c, r), mm.terrain_color(c, r))
	var outline: PackedVector2Array = mm.outline_poly()
	for i in range(outline.size()):
		draw_line(outline[i], outline[(i + 1) % outline.size()], C_BORDER, 1.0)
