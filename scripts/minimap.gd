class_name MiniMap
extends Control
## Container for an isometric minimap that matches the main battlefield orientation.

const TerrainLayerScript := preload("res://scripts/minimap_terrain.gd")
const OverlayLayerScript := preload("res://scripts/minimap_overlay.gd")

const PAD := 6.0

var terrain_layer: Control
var overlay_layer: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	terrain_layer = TerrainLayerScript.new()
	terrain_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	terrain_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(terrain_layer)
	overlay_layer = OverlayLayerScript.new()
	overlay_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_layer)
	terrain_layer.queue_redraw()
	overlay_layer.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if terrain_layer != null:
			terrain_layer.queue_redraw()
		if overlay_layer != null:
			overlay_layer.queue_redraw()

func map_bounds_world() -> Rect2:
	var corners := [
		Game.grid_to_world(0.0, 0.0),
		Game.grid_to_world(float(Game.MAP_COLS), 0.0),
		Game.grid_to_world(float(Game.MAP_COLS), float(Game.MAP_ROWS)),
		Game.grid_to_world(0.0, float(Game.MAP_ROWS)),
	]
	var min_x := minf(minf(corners[0].x, corners[1].x), minf(corners[2].x, corners[3].x))
	var max_x := maxf(maxf(corners[0].x, corners[1].x), maxf(corners[2].x, corners[3].x))
	var min_y := minf(minf(corners[0].y, corners[1].y), minf(corners[2].y, corners[3].y))
	var max_y := maxf(maxf(corners[0].y, corners[1].y), maxf(corners[2].y, corners[3].y))
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func map_rect() -> Rect2:
	var bounds: Rect2 = map_bounds_world()
	var avail := size - Vector2(PAD * 2.0, PAD * 2.0)
	var scale_x: float = avail.x / bounds.size.x
	var scale_y: float = avail.y / bounds.size.y
	var scale: float = minf(scale_x, scale_y)
	var draw_size := bounds.size * scale
	var pos := (size - draw_size) * 0.5
	return Rect2(pos, draw_size)

func world_to_panel(world_pos: Vector2) -> Vector2:
	var bounds: Rect2 = map_bounds_world()
	var rect: Rect2 = map_rect()
	var nx: float = 0.0 if bounds.size.x <= 0.0 else (world_pos.x - bounds.position.x) / bounds.size.x
	var ny: float = 0.0 if bounds.size.y <= 0.0 else (world_pos.y - bounds.position.y) / bounds.size.y
	return Vector2(
		rect.position.x + nx * rect.size.x,
		rect.position.y + ny * rect.size.y
	)

func grid_to_panel(gx: float, gy: float) -> Vector2:
	return world_to_panel(Game.grid_to_world(gx, gy))

func tile_poly(c: int, r: int) -> PackedVector2Array:
	return PackedVector2Array([
		grid_to_panel(float(c), float(r)),
		grid_to_panel(float(c + 1), float(r)),
		grid_to_panel(float(c + 1), float(r + 1)),
		grid_to_panel(float(c), float(r + 1)),
	])

func terrain_color(c: int, r: int) -> Color:
	var tt: int = Game.get_tile(c, r)
	match tt:
		Game.Tile.WATER:
			return Color(0.200, 0.355, 0.480)
		Game.Tile.BRIDGE:
			return Color(0.560, 0.418, 0.215)
		Game.Tile.SWAMP:
			return Color(0.274, 0.332, 0.198)
		Game.Tile.FOREST:
			return Color(0.198, 0.370, 0.175)
		Game.Tile.HILL:
			var elev_t: float = clampf(float(Game.get_elev(c, r)) / float(Game.MAX_HILL_ELEV), 0.0, 1.0)
			return Color(0.470, 0.500, 0.274).lerp(Color(0.698, 0.725, 0.412), elev_t)
		_:
			return Color(0.471, 0.616, 0.373)

func outline_poly() -> PackedVector2Array:
	return PackedVector2Array([
		grid_to_panel(0.0, 0.0),
		grid_to_panel(float(Game.MAP_COLS), 0.0),
		grid_to_panel(float(Game.MAP_COLS), float(Game.MAP_ROWS)),
		grid_to_panel(0.0, float(Game.MAP_ROWS)),
	])
