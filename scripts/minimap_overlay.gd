extends Control
## Dynamic unit, structure, and camera overlay for the isometric minimap.

const C_PLAYER_UNIT := Color(1.0, 0.890, 0.541)
const C_ENEMY_UNIT := Color(0.929, 0.408, 0.349)
const C_PLAYER_STRUCT := Color(1.0, 0.824, 0.396)
const C_ENEMY_STRUCT := Color(0.847, 0.345, 0.318)
const C_CAMERA := Color(1.0, 0.973, 0.816, 0.92)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var mm: MiniMap = get_parent() as MiniMap
	if mm == null:
		return
	_draw_structures(mm)
	_draw_units(mm)
	_draw_camera_frame(mm)

func _draw_structures(mm: MiniMap) -> void:
	for s_node in Game.get_structures():
		var s: Structure = s_node as Structure
		if s == null:
			continue
		var pos := mm.grid_to_panel(s.grid_col + s.grid_w * 0.5, s.grid_row + s.grid_h * 0.5)
		var dims := Vector2(
			maxf(4.0, mm.map_rect().size.x * float(s.grid_w) / float(Game.MAP_COLS)),
			maxf(4.0, mm.map_rect().size.y * float(s.grid_h) / float(Game.MAP_ROWS))
		)
		var col := C_PLAYER_STRUCT if s.faction == Game.PLAYER else C_ENEMY_STRUCT
		draw_rect(Rect2(pos - dims * 0.5, dims), col)

func _draw_units(mm: MiniMap) -> void:
	for u_node in Game.get_units():
		var u: Unit = u_node as Unit
		if u == null or not u.visible:
			continue
		var pos := mm.grid_to_panel(u.gx, u.gy)
		var col := C_PLAYER_UNIT if u.faction == Game.PLAYER else C_ENEMY_UNIT
		draw_circle(pos, 2.2, col)

func _draw_camera_frame(mm: MiniMap) -> void:
	if Game.camera == null:
		return
	var cam: Camera2D = Game.camera
	var center: Vector2 = cam.get_screen_center_position()
	var half: Vector2 = get_viewport_rect().size / (2.0 * cam.zoom)
	var world_pts := [
		center + Vector2(-half.x, -half.y),
		center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y),
		center + Vector2(-half.x, half.y),
	]
	var mini_pts := PackedVector2Array()
	for wp in world_pts:
		mini_pts.append(mm.world_to_panel(wp))
	for i in range(mini_pts.size()):
		draw_line(mini_pts[i], mini_pts[(i + 1) % mini_pts.size()], C_CAMERA, 1.0)
