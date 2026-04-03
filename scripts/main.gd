extends Node2D
## Main scene – input handling, camera, game loop.
## Uses Godot input actions, signals, groups, and node-based entities.

const TankScene := preload("res://scenes/tank.tscn")
const MortarSquadScene := preload("res://scenes/mortar_squad.tscn")
const TruckScene := preload("res://scenes/truck.tscn")
const SupplyDepotScene := preload("res://scenes/supply_depot.tscn")
const AirportScene := preload("res://scenes/airport.tscn")
const PATH_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const PATH_GOAL_EPS := 0.45
const PATH_REPATH_S := 0.3
const VISION_RAY_COUNT := 12
const VISION_RAY_STEP := 0.5
const VISION_BLOCK_EPS_M := 0.35
const TANK_BUILD_COST := 500.0
const TANK_BUILD_TIME := 60.0
const MORTAR_BUILD_COST := 200.0
const MORTAR_BUILD_TIME := 10.0

@onready var cam2d: Camera2D = $Camera2D
@onready var entities: Node2D = $Entities
@onready var overlay: Overlay = $Overlay
@onready var hud = $UILayer/HUD
var _last_fog_sig := ""
var _last_ui_sig := ""
var _tank_build_queue: int = 0
var _tank_build_time_left: float = 0.0
var _tank_build_active: bool = false
var _tank_build_paused: bool = false
var _tank_build_waiting_spawn: bool = false
var _tank_build_waiting_supply: bool = false
var _mortar_build_queue: int = 0
var _mortar_build_time_left: float = 0.0
var _mortar_build_active: bool = false
var _mortar_build_paused: bool = false
var _mortar_build_waiting_spawn: bool = false
var _mortar_build_waiting_supply: bool = false
var _supply_receiver_index: Dictionary = {}
var _supply_receiver_index_built_at: float = -1.0

func _ready() -> void:
	Game.camera = cam2d
	get_tree().root.size_changed.connect(_on_resize)
	_on_resize()
	overlay.shell_hit.connect(_on_shell_hit)
	_spawn_enemies()
	_spawn_starting_depot()
	hud.build_requested.connect(toggle_build)
	hud.train_tank_requested.connect(_on_train_tank)
	hud.unit_build_requested.connect(_on_unit_build_requested)
	hud.tank_queue_pause_requested.connect(_on_tank_queue_pause_requested)
	hud.tank_queue_cancel_requested.connect(_on_tank_queue_cancel_requested)
	hud.mortar_queue_pause_requested.connect(_on_mortar_queue_pause_requested)
	hud.mortar_queue_cancel_requested.connect(_on_mortar_queue_cancel_requested)
	hud.sync_build_buttons()
	hud.reset_selection()
	hud.reset_unit_panel()
	hud.set_unit_catalog_supply(_player_supply_total())

func _on_resize() -> void:
	var sz := get_viewport_rect().size
	var sc := clampf(minf(sz.x / 1180.0, sz.y / 760.0), 0.72, 1.18)
	cam2d.zoom = Vector2(sc, sc)
	# Origin bias: camera focus at ~24% from top for more downfield visibility
	cam2d.offset = Vector2(0, (sz.y * 0.5 - maxf(90.0, sz.y * 0.24)) / sc)
	_clamp_camera()

# ═══════════════════════════════════════════════════════════════════════════════
#  PROCESS
# ═══════════════════════════════════════════════════════════════════════════════
func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	_update_camera(dt)
	cam2d.position = Game.grid_to_world(Game.cam.x, Game.cam.y)
	if Game.ptr_in and Game.build_mode != "":
		Game.hover_tile = Game.tile_at(Game.ptr_scr.x, Game.ptr_scr.y)
	elif Game.build_mode == "":
		Game.hover_tile = Vector2i(-1, -1)
	_update_enemy_ai()
	_update_units(dt)
	_resolve_collisions()
	_update_combat(dt)
	_remove_dead()
	_update_fog()
	_update_player_detection_visibility()
	_update_player_production(dt)
	_refresh_ui()

# ═══════════════════════════════════════════════════════════════════════════════
#  INPUT  (mouse events only — keyboard panning uses Godot input actions)
# ═══════════════════════════════════════════════════════════════════════════════
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		var key_ev := ev as InputEventKey
		if key_ev.pressed and not key_ev.echo and key_ev.keycode == KEY_F9:
			if Game.enable_reveal_all_cheat():
				_last_fog_sig = ""
				hud.set_status("War fog removed. F9 cheat is now active.")
			else:
				hud.set_status("War fog cheat is already active.")
			return
		if key_ev.pressed and not key_ev.echo and key_ev.keycode == KEY_F10:
			if Game.enable_super_tank_cheat():
				for u: Unit in Game.get_units():
					if _super_tank_cheat_applies(u):
						u.supplies = u.max_supplies
				_flush_instant_tank_production()
				_flush_instant_mortar_production()
				hud.set_status("F10 cheat enabled. All player units now move 10x faster. Player tanks keep unlimited supplies, and unit production is instant.")
			else:
				hud.set_status("Super tank cheat is already active.")
			return
	if ev is InputEventMouseMotion:
		Game.ptr_scr = ev.position
		Game.ptr_in = true
		Game.hover_tile = Game.tile_at(ev.position.x, ev.position.y) if Game.build_mode != "" else Vector2i(-1, -1)
		if Game.drag_on:
			Game.drag_cur = ev.position
			Game.drag_box = Game.drag_start.distance_to(ev.position) >= Game.DRAG_THRESH

	elif ev is InputEventMouseButton:
		Game.ptr_scr = ev.position
		Game.ptr_in = true
		Game.hover_tile = Game.tile_at(ev.position.x, ev.position.y) if Game.build_mode != "" else Vector2i(-1, -1)
		if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			if Game.build_mode != "":
				_cancel_build_mode()
				return
			if ev.ctrl_pressed:
				_issue_force_attack(ev.position)
			else:
				_issue_move(ev.position)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_on_lmb_down(ev.position)
			else:
				_on_lmb_up(ev.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		Game.ptr_in = false
		Game.hover_tile = Vector2i(-1, -1)

func _on_lmb_down(pos: Vector2) -> void:
	var bdef := Game.bldg_def(Game.build_mode)
	if not bdef.is_empty():
		var t := Game.tile_at(pos.x, pos.y)
		if t == Vector2i(-1, -1):
			hud.set_status("Choose a valid tile on the battlefield.")
			return
		_attempt_place(t.x, t.y)
		return
	Game.drag_on = true
	Game.drag_start = pos
	Game.drag_cur = pos
	Game.drag_box = false

func _on_lmb_up(pos: Vector2) -> void:
	if not Game.drag_on: return
	var box := Game.drag_box
	var ds := Game.drag_start
	Game.drag_on = false; Game.drag_box = false
	if box:
		_select_in_rect(ds, pos)
	else:
		_handle_click(pos)

# ═══════════════════════════════════════════════════════════════════════════════
#  CAMERA  (uses Godot input actions instead of raw key tracking)
# ═══════════════════════════════════════════════════════════════════════════════
func _update_camera(dt: float) -> void:
	var px := 0.0; var py := 0.0
	if Input.is_action_pressed("pan_left"):  px -= 1; py += 1
	if Input.is_action_pressed("pan_right"): px += 1; py -= 1
	if Input.is_action_pressed("pan_up"):    px -= 1; py -= 1
	if Input.is_action_pressed("pan_down"):  px += 1; py += 1
	if Game.ptr_in and not Game.drag_on:
		var vp := get_viewport_rect().size
		var edge := 36.0
		if Game.ptr_scr.x <= edge:        px -= 1; py += 1
		if Game.ptr_scr.x >= vp.x - edge: px += 1; py -= 1
		if Game.ptr_scr.y <= edge:        px -= 1; py -= 1
		if Game.ptr_scr.y >= vp.y - edge: px += 1; py += 1
	if px == 0 and py == 0: return
	var mag := Vector2(px, py).length()
	var spd := 14.0 * dt
	Game.cam += Vector2(px / mag, py / mag) * spd
	_clamp_camera()

func _clamp_camera() -> void:
	var vp := get_viewport_rect().size
	var hvp := vp / (2.0 * cam2d.zoom)
	var off := cam2d.offset
	var map_pts := [
		Game.grid_to_world(0, 0),
		Game.grid_to_world(Game.MAP_COLS, 0),
		Game.grid_to_world(Game.MAP_COLS, Game.MAP_ROWS),
		Game.grid_to_world(0, Game.MAP_ROWS),
	]
	var min_x := minf(minf(map_pts[0].x, map_pts[1].x), minf(map_pts[2].x, map_pts[3].x))
	var max_x := maxf(maxf(map_pts[0].x, map_pts[1].x), maxf(map_pts[2].x, map_pts[3].x))
	var min_y := minf(minf(map_pts[0].y, map_pts[1].y), minf(map_pts[2].y, map_pts[3].y)) - Game.elev_units_to_lift(Game.MAX_HILL_ELEV)
	var max_y := maxf(maxf(map_pts[0].y, map_pts[1].y), maxf(map_pts[2].y, map_pts[3].y))
	var cam_world := Game.grid_to_world(Game.cam.x, Game.cam.y)
	var lo_x := min_x + hvp.x - off.x
	var hi_x := max_x - hvp.x - off.x
	var lo_y := min_y + hvp.y - off.y
	var hi_y := max_y - hvp.y - off.y
	cam_world.x = clampf(cam_world.x, lo_x, hi_x) if lo_x <= hi_x else (min_x + max_x) * 0.5
	cam_world.y = clampf(cam_world.y, lo_y, hi_y) if lo_y <= hi_y else (min_y + max_y) * 0.5
	Game.cam = Game.world_to_grid(cam_world.x, cam_world.y)

# ═══════════════════════════════════════════════════════════════════════════════
#  BUILD
# ═══════════════════════════════════════════════════════════════════════════════
func toggle_build(btype: String) -> void:
	if btype == Game.T_PLANT:
		Game.build_mode = ""
		hud.sync_build_buttons()
		hud.set_status("Tank Plants are no longer buildable. Use the Unit Factory panel on the left.")
		return
	var armed := Game.build_mode == btype
	Game.build_mode = "" if armed else btype
	Game.selected_structure = null; Game.selected_units.clear()
	if armed:
		hud.reset_selection(); hud.reset_unit_panel()
		hud.set_status("Placement mode cancelled.")
	else:
		var d := Game.bldg_def(btype)
		if not d.is_empty():
			hud.set_sel_pill("Build mode")
			var build_label: String = d.label
			if btype == Game.T_AIRPORT:
				build_label = d.label + " construction site"
			hud.set_sel_detail(build_label + " selected. Hover the field to preview a " +
				str(d.w) + "x" + str(d.h) + " footprint, then click to deploy it.")
			hud.reset_unit_panel()
			hud.set_status("Placement mode active. Choose an open " +
				str(d.w) + "x" + str(d.h) + " area for the " + build_label + ".")
	hud.sync_build_buttons()

func _cancel_build_mode() -> void:
	if Game.build_mode == "":
		return
	Game.build_mode = ""
	Game.hover_tile = Vector2i(-1, -1)
	Game.selected_structure = null
	Game.selected_units.clear()
	hud.reset_selection()
	hud.reset_unit_panel()
	hud.sync_build_buttons()
	hud.set_status("Placement mode cancelled.")

func _attempt_place(c: int, r: int) -> void:
	var d := Game.bldg_def(Game.build_mode)
	if d.is_empty(): return
	if Game.build_mode == Game.T_PLANT:
		hud.set_status("Tank Plants are no longer buildable.")
		Game.build_mode = ""
		hud.sync_build_buttons()
		return
	if not _footprint_is_explored(c, r, d.w, d.h):
		hud.set_status("That footprint is still under black fog.")
		return
	if not Game.fp_valid(c, r, d.w, d.h):
		hud.set_status("That footprint is blocked or off the map."); return
	var structure: Structure
	match Game.build_mode:
		Game.T_DEPOT:
			structure = SupplyDepotScene.instantiate()
		Game.T_AIRPORT:
			structure = AirportScene.instantiate()
		_:
			hud.set_status("That structure is not available.")
			Game.build_mode = ""
			hud.sync_build_buttons()
			return
	structure.grid_col = c
	structure.grid_row = r
	structure.faction = Game.PLAYER
	structure.entity_id = Game.next_id
	Game.next_id += 1
	entities.add_child(structure)
	# Connect signals after the node enters the tree
	if structure is TankPlant:
		structure.tank_produced.connect(_on_tank_produced)
	if structure is Airport:
		(structure as Airport).construction_completed.connect(_on_airport_construction_completed)
	Game.selected_structure = structure; Game.selected_units.clear()
	Game.build_mode = ""; Game.hover_tile = Vector2i(-1, -1)
	hud.sync_build_buttons()
	if structure is SupplyDepot:
		hud.set_status("Supply Depot deployed with 2000 stored supplies.")
	elif structure is Airport:
		hud.set_status("Airport blueprint placed. Send supply trucks to deliver 1000 build supply.")
	Game.structure_placed.emit(structure)

func _footprint_is_explored(c: int, r: int, w: int, h: int) -> bool:
	for rr in range(r, r + h):
		for cc in range(c, c + w):
			if not Game.fexp(cc, rr):
				return false
	return true

func _on_airport_construction_completed(site: Airport) -> void:
	if site == null or not is_instance_valid(site):
		return
	hud.set_status("Airport construction complete.")

func _on_tank_produced(plant: TankPlant) -> void:
	var sp = Game.find_open(plant.grid_col + plant.grid_w + 0.85, plant.grid_row + plant.grid_h + 0.35)
	var tank := TankScene.instantiate() as Tank
	tank.faction = Game.PLAYER
	tank.entity_id = Game.next_id
	Game.next_id += 1
	tank.gx = clampf(plant.grid_col + plant.grid_w - 0.2, 0.8, Game.MAP_COLS - 0.8)
	tank.gy = clampf(plant.grid_row + plant.grid_h - 0.18, 0.8, Game.MAP_ROWS - 0.8)
	tank.supplies = 100.0
	tank.max_supplies = 100.0
	tank.speed = 0.82 + randf() * 0.16
	tank.heading = Vector2(1.0, 0.0)
	if sp != null:
		_set_move_goal(tank, sp, true)
	entities.add_child(tank)
	Game.unit_spawned.emit(tank)
	hud.set_status("Tank produced from Plant #" + str(plant.entity_id) + ".")

func _on_train_tank() -> void:
	hud.set_status("Tank Plants are no longer used. Build tanks from the Unit Factory panel on the left.")

func _on_unit_build_requested(unit_type: String, amount: int) -> void:
	if amount <= 0:
		hud.set_status("Enter a positive unit count.")
		return
	match unit_type:
		Game.T_TANK:
			_queue_tanks_from_supply_network(amount)
		Game.T_MORTAR:
			_queue_mortars_from_supply_network(amount)
		Game.T_RECON:
			hud.set_status("Reconnaissance Plane production is not implemented yet.")
		_:
			hud.set_status("That unit is not available yet.")

func _queue_tanks_from_supply_network(amount: int) -> void:
	_tank_build_queue += amount
	if _instant_unit_production_active():
		_flush_instant_tank_production()
		if _tank_build_queue <= 0:
			hud.set_status("Queued %d tank%s. Production completed instantly." % [amount, "" if amount == 1 else "s"])
			return
		if _tank_build_waiting_supply:
			hud.set_status("Queued %d tank%s. Instant production is waiting for 500 supply." % [amount, "" if amount == 1 else "s"])
			return
		if _tank_build_waiting_spawn:
			hud.set_status("Queued %d tank%s. Instant production is waiting for a clear spawn point." % [amount, "" if amount == 1 else "s"])
			return
	if _tank_build_paused:
		hud.set_status("Queued %d tank%s. Production remains paused." % [amount, "" if amount == 1 else "s"])
		return
	if not _tank_build_active:
		if _start_next_tank_build():
			hud.set_status("Queued %d tank%s for production." % [amount, "" if amount == 1 else "s"])
			return
		_tank_build_waiting_supply = true
		_tank_build_waiting_spawn = false
		_tank_build_time_left = 0.0
		hud.set_status("Queued %d tank%s. Production is waiting for 500 supply." % [amount, "" if amount == 1 else "s"])
		return
	hud.set_status("Queued %d tank%s for production." % [amount, "" if amount == 1 else "s"])

func _queue_mortars_from_supply_network(amount: int) -> void:
	_mortar_build_queue += amount
	if _instant_unit_production_active():
		_flush_instant_mortar_production()
		if _mortar_build_queue <= 0:
			hud.set_status("Queued %d mortar squad%s. Production completed instantly." % [amount, "" if amount == 1 else "s"])
			return
		if _mortar_build_waiting_supply:
			hud.set_status("Queued %d mortar squad%s. Instant production is waiting for 200 supply." % [amount, "" if amount == 1 else "s"])
			return
		if _mortar_build_waiting_spawn:
			hud.set_status("Queued %d mortar squad%s. Instant production is waiting for a clear spawn point." % [amount, "" if amount == 1 else "s"])
			return
	if _mortar_build_paused:
		hud.set_status("Queued %d mortar squad%s. Production remains paused." % [amount, "" if amount == 1 else "s"])
		return
	if not _mortar_build_active:
		if _start_next_mortar_build():
			hud.set_status("Queued %d mortar squad%s for production." % [amount, "" if amount == 1 else "s"])
			return
		_mortar_build_waiting_supply = true
		_mortar_build_waiting_spawn = false
		_mortar_build_time_left = 0.0
		hud.set_status("Queued %d mortar squad%s. Production is waiting for 200 supply." % [amount, "" if amount == 1 else "s"])
		return
	hud.set_status("Queued %d mortar squad%s for production." % [amount, "" if amount == 1 else "s"])

func _player_supply_total() -> float:
	var total := 0.0
	for s_node in Game.get_structures():
		var depot: SupplyDepot = s_node as SupplyDepot
		if depot == null or depot.faction != Game.PLAYER:
			continue
		total += depot.stored
	return total

func _deduct_player_supply(cost: float) -> bool:
	var remaining := cost
	for s_node in Game.get_structures():
		var depot: SupplyDepot = s_node as SupplyDepot
		if depot == null or depot.faction != Game.PLAYER or depot.stored <= 0.0:
			continue
		var take := minf(depot.stored, remaining)
		depot.stored -= take
		remaining -= take
		if remaining <= 0.001:
			return true
	return false

func _refund_player_supply(amount: float) -> float:
	var remaining := amount
	for s_node in Game.get_structures():
		var depot: SupplyDepot = s_node as SupplyDepot
		if depot == null or depot.faction != Game.PLAYER:
			continue
		var room := maxf(0.0, depot.max_stored - depot.stored)
		if room <= 0.0:
			continue
		var refund := minf(room, remaining)
		depot.stored += refund
		remaining -= refund
		if remaining <= 0.001:
			break
	return amount - remaining

func _start_next_tank_build() -> bool:
	if _tank_build_queue <= 0 or _tank_build_active or _tank_build_paused:
		return false
	if _player_supply_total() + 0.001 < TANK_BUILD_COST:
		return false
	if not _deduct_player_supply(TANK_BUILD_COST):
		return false
	_tank_build_time_left = _effective_tank_build_time()
	_tank_build_active = true
	_tank_build_waiting_spawn = false
	_tank_build_waiting_supply = false
	return true

func _start_next_mortar_build() -> bool:
	if _mortar_build_queue <= 0 or _mortar_build_active or _mortar_build_paused:
		return false
	if _player_supply_total() + 0.001 < MORTAR_BUILD_COST:
		return false
	if not _deduct_player_supply(MORTAR_BUILD_COST):
		return false
	_mortar_build_time_left = _effective_mortar_build_time()
	_mortar_build_active = true
	_mortar_build_waiting_spawn = false
	_mortar_build_waiting_supply = false
	return true

func _on_tank_queue_pause_requested() -> void:
	if _tank_build_queue <= 0:
		hud.set_status("No tank queue is active.")
		return
	_tank_build_paused = not _tank_build_paused
	if _tank_build_paused:
		hud.set_status("Tank queue paused.")
		return
	if not _tank_build_active and _start_next_tank_build():
		hud.set_status("Tank queue resumed.")
		return
	if _tank_build_waiting_supply:
		hud.set_status("Tank queue resumed. Waiting for 500 supply.")
	elif _tank_build_waiting_spawn:
		hud.set_status("Tank queue resumed. Waiting for a clear spawn point.")
	else:
		hud.set_status("Tank queue resumed.")

func _on_tank_queue_cancel_requested() -> void:
	if _tank_build_queue <= 0:
		hud.set_status("No tank queue is active.")
		return
	var had_active_build: bool = _tank_build_active
	var refunded := 0.0
	if had_active_build:
		refunded = _refund_player_supply(TANK_BUILD_COST)
	_tank_build_queue = 0
	_tank_build_time_left = 0.0
	_tank_build_active = false
	_tank_build_paused = false
	_tank_build_waiting_spawn = false
	_tank_build_waiting_supply = false
	if had_active_build and refunded > 0.001:
		hud.set_status("Tank queue cancelled. Refunded %d supply for the in-progress tank." % [roundi(refunded)])
	else:
		hud.set_status("Tank queue cancelled.")

func _on_mortar_queue_pause_requested() -> void:
	if _mortar_build_queue <= 0:
		hud.set_status("No mortar squad queue is active.")
		return
	_mortar_build_paused = not _mortar_build_paused
	if _mortar_build_paused:
		hud.set_status("Mortar squad queue paused.")
		return
	if not _mortar_build_active and _start_next_mortar_build():
		hud.set_status("Mortar squad queue resumed.")
		return
	if _mortar_build_waiting_supply:
		hud.set_status("Mortar squad queue resumed. Waiting for 200 supply.")
	elif _mortar_build_waiting_spawn:
		hud.set_status("Mortar squad queue resumed. Waiting for a clear spawn point.")
	else:
		hud.set_status("Mortar squad queue resumed.")

func _on_mortar_queue_cancel_requested() -> void:
	if _mortar_build_queue <= 0:
		hud.set_status("No mortar squad queue is active.")
		return
	var had_active_build: bool = _mortar_build_active
	var refunded: float = 0.0
	if had_active_build:
		refunded = _refund_player_supply(MORTAR_BUILD_COST)
	_mortar_build_queue = 0
	_mortar_build_time_left = 0.0
	_mortar_build_active = false
	_mortar_build_paused = false
	_mortar_build_waiting_spawn = false
	_mortar_build_waiting_supply = false
	if had_active_build and refunded > 0.001:
		hud.set_status("Mortar squad queue cancelled. Refunded %d supply for the in-progress squad." % [roundi(refunded)])
	else:
		hud.set_status("Mortar squad queue cancelled.")

func _find_spawn_info(radius: float) -> Dictionary:
	var best_depot: SupplyDepot = null
	var best_spawn: Variant = null
	var best_supply: float = -1.0
	for s_node in Game.get_structures():
		var depot: SupplyDepot = s_node as SupplyDepot
		if depot == null or depot.faction != Game.PLAYER:
			continue
		var spawn: Variant = _find_spawn_near_depot(depot, radius)
		if spawn == null:
			continue
		if depot.stored > best_supply:
			best_supply = depot.stored
			best_depot = depot
			best_spawn = spawn
	if best_depot == null or best_spawn == null:
		return {}
	return {"depot": best_depot, "spawn": best_spawn}

func _find_spawn_near_depot(depot: SupplyDepot, radius: float):
	var gx: float = depot.grid_col
	var gy: float = depot.grid_row
	var w: float = depot.grid_w
	var h: float = depot.grid_h
	var offsets := [
		Vector2(gx + w + 0.9, gy + h * 0.5),
		Vector2(gx - 0.9, gy + h * 0.5),
		Vector2(gx + w * 0.5, gy - 0.9),
		Vector2(gx + w * 0.5, gy + h + 0.9),
		Vector2(gx + w + 0.9, gy - 0.1),
		Vector2(gx + w + 0.9, gy + h + 0.1),
		Vector2(gx - 0.9, gy - 0.1),
		Vector2(gx - 0.9, gy + h + 0.1),
	]
	for offset in offsets:
		var spawn: Variant = _find_ground_open_at(offset.x, offset.y, radius)
		if spawn != null:
			return spawn
	return null

func _spawn_player_tank(spawn: Vector2, _depot: SupplyDepot) -> void:
	var tank := TankScene.instantiate() as Tank
	tank.faction = Game.PLAYER
	tank.entity_id = Game.next_id
	Game.next_id += 1
	tank.gx = spawn.x
	tank.gy = spawn.y
	tank.supplies = 100.0
	tank.max_supplies = 100.0
	tank.speed = 0.82 + randf() * 0.16
	tank.heading = Vector2(1.0, 0.0)
	entities.add_child(tank)
	Game.unit_spawned.emit(tank)

func _spawn_player_mortar(spawn: Vector2, _depot: SupplyDepot) -> void:
	var squad := MortarSquadScene.instantiate() as MortarSquad
	squad.faction = Game.PLAYER
	squad.entity_id = Game.next_id
	Game.next_id += 1
	squad.gx = spawn.x
	squad.gy = spawn.y
	squad.supplies = 100.0
	squad.max_supplies = 100.0
	squad.heading = Vector2(1.0, 0.0)
	entities.add_child(squad)
	Game.unit_spawned.emit(squad)

func _update_player_production(dt: float) -> void:
	_update_tank_production(dt)
	_update_mortar_production(dt)

func _update_tank_production(dt: float) -> void:
	if _tank_build_queue <= 0:
		_tank_build_time_left = 0.0
		_tank_build_active = false
		_tank_build_paused = false
		_tank_build_waiting_spawn = false
		_tank_build_waiting_supply = false
		return
	if _instant_unit_production_active():
		_flush_instant_tank_production()
		return
	if _tank_build_paused:
		return
	if not _tank_build_active:
		var was_waiting_supply: bool = _tank_build_waiting_supply
		if _start_next_tank_build():
			if was_waiting_supply:
				hud.set_status("Tank production resumed.")
			return
		if not _tank_build_waiting_supply:
			_tank_build_waiting_supply = true
			hud.set_status("Tank queue waiting for 500 supply.")
		return
	if _tank_build_time_left > 0.0:
		_tank_build_time_left = maxf(0.0, _tank_build_time_left - dt)
		if _tank_build_time_left > 0.0:
			return
	var spawn_ready: Dictionary = _find_spawn_info(Game.TANK_COL_R)
	if spawn_ready.is_empty():
		_tank_build_waiting_spawn = true
		return
	_tank_build_waiting_spawn = false
	_spawn_player_tank(spawn_ready["spawn"], spawn_ready["depot"])
	_tank_build_queue -= 1
	_tank_build_active = false
	if _tank_build_queue <= 0:
		_tank_build_time_left = 0.0
		hud.set_status("Tank production complete.")
		return
	if _start_next_tank_build():
		hud.set_status("Tank completed. %d tank%s remain in queue." % [_tank_build_queue, "" if _tank_build_queue == 1 else "s"])
		return
	_tank_build_time_left = 0.0
	_tank_build_waiting_supply = true
	hud.set_status("Tank completed. %d tank%s remain queued. Waiting for 500 supply." % [_tank_build_queue, "" if _tank_build_queue == 1 else "s"])

func _update_mortar_production(dt: float) -> void:
	if _mortar_build_queue <= 0:
		_mortar_build_time_left = 0.0
		_mortar_build_active = false
		_mortar_build_paused = false
		_mortar_build_waiting_spawn = false
		_mortar_build_waiting_supply = false
		return
	if _instant_unit_production_active():
		_flush_instant_mortar_production()
		return
	if _mortar_build_paused:
		return
	if not _mortar_build_active:
		var was_waiting_supply: bool = _mortar_build_waiting_supply
		if _start_next_mortar_build():
			if was_waiting_supply:
				hud.set_status("Mortar squad production resumed.")
			return
		if not _mortar_build_waiting_supply:
			_mortar_build_waiting_supply = true
			hud.set_status("Mortar squad queue waiting for 200 supply.")
		return
	if _mortar_build_time_left > 0.0:
		_mortar_build_time_left = maxf(0.0, _mortar_build_time_left - dt)
		if _mortar_build_time_left > 0.0:
			return
	var spawn_ready: Dictionary = _find_spawn_info(Game.TRUCK_COL_R)
	if spawn_ready.is_empty():
		_mortar_build_waiting_spawn = true
		return
	_mortar_build_waiting_spawn = false
	_spawn_player_mortar(spawn_ready["spawn"], spawn_ready["depot"])
	_mortar_build_queue -= 1
	_mortar_build_active = false
	if _mortar_build_queue <= 0:
		_mortar_build_time_left = 0.0
		hud.set_status("Mortar squad production complete.")
		return
	if _start_next_mortar_build():
		hud.set_status("Mortar squad completed. %d mortar squad%s remain in queue." % [_mortar_build_queue, "" if _mortar_build_queue == 1 else "s"])
		return
	_mortar_build_time_left = 0.0
	_mortar_build_waiting_supply = true
	hud.set_status("Mortar squad completed. %d mortar squad%s remain queued. Waiting for 200 supply." % [_mortar_build_queue, "" if _mortar_build_queue == 1 else "s"])

# ═══════════════════════════════════════════════════════════════════════════════
#  SELECTION
# ═══════════════════════════════════════════════════════════════════════════════
func _handle_click(pos: Vector2) -> void:
	var hu = Game.unit_at_screen(pos.x, pos.y)
	if hu != null and hu.movable and hu.faction == Game.PLAYER:
		Game.selected_structure = null; Game.selected_units = [hu]
		hud.set_status(hu.label + " selected."); return
	var t := Game.tile_at(pos.x, pos.y)
	if t == Vector2i(-1, -1):
		Game.selected_structure = null; Game.selected_units.clear()
		hud.set_status("Terrain not selected."); return
	var st = Game.struct_at(t.x, t.y)
	if st != null:
		Game.selected_units.clear(); Game.selected_structure = st
		hud.set_status(st.label + " selected."); return
	Game.selected_structure = null; Game.selected_units.clear()
	hud.set_status("No structure selected.")

func _select_in_rect(a: Vector2, b: Vector2) -> void:
	var r: Rect2 = Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)),
				   Vector2(absf(b.x - a.x), absf(b.y - a.y)))
	var selected: Array[Node2D] = []
	for u: Unit in Game.get_units():
		if not (u.movable and u.faction == Game.PLAYER): continue
		var sc := u.screen_pos()
		if r.has_point(sc): selected.append(u)
	if selected.is_empty():
		Game.selected_structure = null; Game.selected_units.clear()
		hud.set_status("No movable units in the drag selection."); return
	Game.selected_structure = null; Game.selected_units = selected
	hud.set_status(str(selected.size()) + " units selected.")

func _show_no_path_warning(pos: Vector2) -> void:
	overlay.show_mouse_warning("No path found", pos)
	hud.set_status("No path found.")

func _can_reach_exact_ground_target(u: Unit, target: Vector2) -> bool:
	var tc := clampi(int(target.x), 0, Game.MAP_COLS - 1)
	var tr := clampi(int(target.y), 0, Game.MAP_ROWS - 1)
	if u.faction == Game.PLAYER and not Game.fexp(tc, tr):
		return false
	if not _ground_clear_at_radius(target.x, target.y, u.get_collision_radius()):
		return false
	return _find_path_points(u, Vector2(u.gx, u.gy), target, u.get_collision_radius(), u.faction == Game.PLAYER) != null

# ═══════════════════════════════════════════════════════════════════════════════
#  MOVE ORDERS
# ═══════════════════════════════════════════════════════════════════════════════
func _issue_move(pos: Vector2) -> void:
	if Game.build_mode != "": return
	var ss = Game.selected_structure
	if ss != null and is_instance_valid(ss) and ss is SupplyDepot:
		_dispatch_truck(ss, pos); return
	var sel: Array = Game.get_selected_units().filter(func(u): return u.movable)
	if sel.is_empty(): return
	var t := Game.tile_at(pos.x, pos.y)
	if t != Vector2i(-1, -1):
		hud.set_order_coordinate(t)
	var target_unit := Game.unit_at_screen(pos.x, pos.y) as Unit
	if target_unit != null and target_unit.faction != Game.PLAYER:
		_issue_attack_order(target_unit, sel)
		return
	if t != Vector2i(-1, -1):
		var target_structure: Structure = Game.struct_at(t.x, t.y) as Structure
		if target_structure != null and target_structure.faction != Game.PLAYER:
			_issue_attack_structure_order(target_structure, sel)
			return
	if t == Vector2i(-1, -1):
		hud.set_status("Move order is outside the battlefield."); return
	var blind_order: bool = not Game.fexp(t.x, t.y)
	var tgt := Vector2(t.x + 0.5, t.y + 0.5)
	if blind_order:
		var blind_tgt := _clamp_ground_target(tgt.x, tgt.y, Game.TANK_COL_R)
		var blind_ordered := 0
		for i in sel.size():
			var off := _formation_off(i, sel.size())
			var unit: Unit = sel[i] as Unit
			if unit == null:
				continue
			var rt := _clamp_ground_target(blind_tgt.x + off.x, blind_tgt.y + off.y, unit.get_collision_radius())
			_clear_attack_goal(unit)
			if not _set_move_goal(unit, rt, true, true):
				continue
			if unit is Truck:
				unit.follow_target = null
				unit.construction_target = null
			blind_ordered += 1
		if blind_ordered == 0:
			_show_no_path_warning(pos)
			return
		hud.set_status(
			sel[0].label + " ordered to explore." if blind_ordered == 1
			else str(blind_ordered) + " units ordered to explore."
		)
		return
	var ordered := 0
	var failed := 0
	for i in sel.size():
		var off := _formation_off(i, sel.size())
		var unit: Unit = sel[i] as Unit
		if unit == null:
			failed += 1
			continue
		var rt := Vector2(tgt.x + off.x, tgt.y + off.y)
		if not _can_reach_exact_ground_target(unit, rt):
			failed += 1
			continue
		_clear_attack_goal(unit)
		if not _set_move_goal(unit, rt, true, false):
			_clear_move_goal(unit)
			failed += 1
			continue
		if unit is Truck:
			unit.follow_target = null
			unit.construction_target = null
		ordered += 1
	if ordered == 0:
		_show_no_path_warning(pos)
		return
	if failed > 0:
		overlay.show_mouse_warning("No path found", pos)
		hud.set_status("%d units ordered to move. %d had no path." % [ordered, failed])
		return
	hud.set_status(
		sel[0].label + " ordered to move." if ordered == 1
		else str(ordered) + " units ordered to move.")

func _issue_attack_order(target_unit: Unit, sel: Array) -> void:
	var ordered := 0
	for unit_node in sel:
		var unit: Unit = unit_node as Unit
		if unit == null or not _unit_can_attack(unit):
			continue
		_clear_attack_goal(unit)
		unit.attack_target = target_unit
		_update_attack_pursuit(unit, true)
		ordered += 1
	if ordered <= 0:
		hud.set_status("Selected units cannot attack that target.")
		return
	var status_text := "Attack order issued on %s #%d." % [target_unit.label, target_unit.entity_id]
	if ordered != 1:
		status_text = "%d units ordered to attack %s #%d." % [ordered, target_unit.label, target_unit.entity_id]
	hud.set_status(status_text)

func _issue_attack_structure_order(target_structure: Structure, sel: Array) -> void:
	var ordered := 0
	for unit_node in sel:
		var unit: Unit = unit_node as Unit
		if unit == null or not _unit_can_attack(unit):
			continue
		_clear_attack_goal(unit)
		unit.attack_structure_target = target_structure
		_update_attack_structure_pursuit(unit, true)
		ordered += 1
	if ordered <= 0:
		hud.set_status("Selected units cannot attack that structure.")
		return
	var status_text := "Attack order issued on %s #%d." % [target_structure.label, target_structure.entity_id]
	if ordered != 1:
		status_text = "%d units ordered to attack %s #%d." % [ordered, target_structure.label, target_structure.entity_id]
	hud.set_status(status_text)

func _issue_force_attack(pos: Vector2) -> void:
	var sel := Game.get_selected_units()
	if sel.is_empty():
		hud.set_status("No units selected.")
		return
	var clicked_unit := Game.unit_at_screen(pos.x, pos.y) as Unit
	var t := Game.tile_at(pos.x, pos.y)
	if t == Vector2i(-1, -1):
		hud.set_status("Attack-ground order is outside the battlefield.")
		return
	hud.set_order_coordinate(t)
	var attack_point := Vector2(t.x + 0.5, t.y + 0.5)
	if clicked_unit != null:
		attack_point = Vector2(clicked_unit.gx, clicked_unit.gy)
	var hit_bridge: bool = Game.bridge_tile_at(t.x, t.y)
	var blind_order: bool = not Game.fexp(t.x, t.y)
	var ordered := 0
	for unit_node in sel:
		var unit: Unit = unit_node as Unit
		if unit == null or not _unit_can_attack(unit):
			continue
		_clear_attack_goal(unit)
		unit.attack_point = attack_point
		unit.attack_point_tile = t
		unit.attack_point_hits_bridge = hit_bridge
		unit.attack_point_blind = blind_order
		_update_ground_attack_pursuit(unit, true)
		ordered += 1
	if ordered <= 0:
		hud.set_status("Selected units cannot force-attack that location.")
		return
	if hit_bridge:
		hud.set_status(
			"Force-attack ordered on bridge tile." if ordered == 1
			else "%d units ordered to force-attack the bridge." % [ordered]
		)
		return
	hud.set_status(
		"Force-attack ordered." if ordered == 1
		else "%d units ordered to force-attack that location." % [ordered]
	)

func _formation_off(idx: int, cnt: int) -> Vector2:
	if cnt <= 1: return Vector2.ZERO
	var cols := ceili(sqrt(float(cnt)))
	var _rows := ceili(float(cnt) / cols)
	var c := idx % cols; var r := idx / cols
	return Vector2((c - (cols - 1) * 0.5) * Game.FORM_SPACE,
				   (r - (_rows - 1) * 0.5) * Game.FORM_SPACE)

func _dispatch_truck(depot: SupplyDepot, pos: Vector2) -> void:
	if depot.stored < Game.TRUCK_CARGO:
		hud.set_status("Supply Depot needs at least 500 supplies to dispatch a truck."); return
	var tu = Game.unit_at_screen(pos.x, pos.y)
	var t := Game.tile_at(pos.x, pos.y)
	var target_site: Airport = null
	if t != Vector2i(-1, -1):
		var st: Structure = Game.struct_at(t.x, t.y) as Structure
		if st is Airport and st.faction == Game.PLAYER and (st as Airport).is_under_construction():
			target_site = st as Airport
	if tu == null and t == Vector2i(-1, -1):
		hud.set_status("Supply order is outside the battlefield."); return
	if t != Vector2i(-1, -1):
		hud.set_order_coordinate(t)
	var sp = Game.find_open(depot.grid_col + depot.grid_w + 0.78,
		depot.grid_row + depot.grid_h * 0.5 + ((randi() % 3) - 1) * 0.36)
	if sp != null:
		sp = _find_ground_open_at(sp.x, sp.y, Game.TRUCK_COL_R)
	if sp == null:
		hud.set_status("The Supply Depot exit is blocked."); return
	var tgt_pt: Variant = null
	var tgt_unit: Node2D = null
	var tgt_lbl := ""
	var blind_order: bool = false
	if tu != null and tu.movable and tu.faction == Game.PLAYER:
		tgt_unit = tu
		tgt_pt = _find_ground_open_at(tu.gx, tu.gy, Game.TRUCK_COL_R)
		tgt_lbl = tu.label + " #" + str(tu.entity_id)
	elif target_site != null:
		tgt_pt = _find_ground_open_near_structure(target_site, Game.TRUCK_COL_R)
		tgt_lbl = "Airport Site #" + str(target_site.entity_id)
	else:
		blind_order = not Game.fexp(t.x, t.y)
		tgt_pt = _clamp_ground_target(t.x + 0.5, t.y + 0.5, Game.TRUCK_COL_R) if blind_order else _find_ground_open_at(t.x + 0.5, t.y + 0.5, Game.TRUCK_COL_R)
	if tgt_pt == null:
		hud.set_status("That supply route is blocked."); return
	depot.stored -= Game.TRUCK_CARGO
	var truck := TruckScene.instantiate() as Truck
	truck.faction = Game.PLAYER
	truck.entity_id = Game.next_id
	Game.next_id += 1
	truck.gx = sp.x
	truck.gy = sp.y
	truck.follow_target = tgt_unit
	truck.construction_target = target_site
	truck.supplies = Game.TRUCK_CARGO
	truck.max_supplies = Game.TRUCK_CARGO
	truck.speed = Game.TRUCK_SPEED
	truck.heading = Vector2(1.0, 0.0)
	var truck_blind_order: bool = blind_order or not Game.fexp(clampi(int(tgt_pt.x), 0, Game.MAP_COLS - 1), clampi(int(tgt_pt.y), 0, Game.MAP_ROWS - 1))
	if not _set_move_goal(truck, tgt_pt, true, truck_blind_order):
		depot.stored += Game.TRUCK_CARGO
		hud.set_status("That supply route has no path.")
		return
	entities.add_child(truck)
	Game.unit_spawned.emit(truck)
	hud.set_status(
		"Supply truck dispatched to " + tgt_lbl + "." if tgt_unit != null or target_site != null
		else "Supply truck dispatched with 500 supplies.")

func _find_ground_open_near_structure(structure: Structure, radius: float):
	var c: float = float(structure.grid_col)
	var r: float = float(structure.grid_row)
	var w: float = float(structure.grid_w)
	var h: float = float(structure.grid_h)
	var candidates: Array[Vector2] = [
		Vector2(c - 0.55, r + h * 0.5),
		Vector2(c + w + 0.55, r + h * 0.5),
		Vector2(c + w * 0.5, r - 0.55),
		Vector2(c + w * 0.5, r + h + 0.55),
		Vector2(c - 0.45, r - 0.45),
		Vector2(c + w + 0.45, r - 0.45),
		Vector2(c - 0.45, r + h + 0.45),
		Vector2(c + w + 0.45, r + h + 0.45),
	]
	for candidate in candidates:
		var open_pt: Variant = _find_ground_open_at(candidate.x, candidate.y, radius)
		if open_pt == null:
			continue
		if Game.struct_at(clampi(int(open_pt.x), 0, Game.MAP_COLS - 1), clampi(int(open_pt.y), 0, Game.MAP_ROWS - 1)) == null:
			return open_pt
	return null

func _distance_to_structure_footprint(wx: float, wy: float, structure: Structure) -> float:
	if structure == null:
		return INF
	var left: float = float(structure.grid_col)
	var top: float = float(structure.grid_row)
	var right: float = left + float(structure.grid_w)
	var bottom: float = top + float(structure.grid_h)
	var nearest_x: float = clampf(wx, left, right)
	var nearest_y: float = clampf(wy, top, bottom)
	return Vector2(wx, wy).distance_to(Vector2(nearest_x, nearest_y))

func _ground_clear_at_radius(wx: float, wy: float, radius: float) -> bool:
	if wx < 0.0 or wy < 0.0 or wx >= Game.MAP_COLS or wy >= Game.MAP_ROWS:
		return false
	var probe := maxf(0.06, radius * 0.78)
	var diag := probe * 0.71
	var samples := [
		Vector2(wx, wy),
		Vector2(wx + probe, wy),
		Vector2(wx - probe, wy),
		Vector2(wx, wy + probe),
		Vector2(wx, wy - probe),
		Vector2(wx + diag, wy + diag),
		Vector2(wx + diag, wy - diag),
		Vector2(wx - diag, wy + diag),
		Vector2(wx - diag, wy - diag),
	]
	for s in samples:
		if not Game.passable(int(s.x), int(s.y)):
			return false
	return true

func _find_ground_open_at(wx: float, wy: float, radius: float):
	var pad := maxf(0.8, radius + 0.2)
	var cx := clampf(wx, pad, Game.MAP_COLS - pad)
	var cy := clampf(wy, pad, Game.MAP_ROWS - pad)
	if _ground_clear_at_radius(cx, cy, radius):
		return Vector2(cx, cy)
	var sc := clampi(int(cx), 0, Game.MAP_COLS - 1)
	var sr := clampi(int(cy), 0, Game.MAP_ROWS - 1)
	for rad in range(1, 8):
		for rr in range(sr - rad, sr + rad + 1):
			for cc in range(sc - rad, sc + rad + 1):
				if maxi(absi(cc - sc), absi(rr - sr)) != rad:
					continue
				var px := clampf(cc + 0.5, pad, Game.MAP_COLS - pad)
				var py := clampf(rr + 0.5, pad, Game.MAP_ROWS - pad)
				if _ground_clear_at_radius(px, py, radius):
					return Vector2(px, py)
	return null

func _clamp_ground_target(wx: float, wy: float, radius: float) -> Vector2:
	var pad := maxf(0.8, radius + 0.2)
	return Vector2(
		clampf(wx, pad, Game.MAP_COLS - pad),
		clampf(wy, pad, Game.MAP_ROWS - pad)
	)

func _unit_max_climb_up_steps(u: Unit) -> int:
	return maxi(0, u.max_climb_up_steps)

func _can_unit_move_between_cells(u: Unit, c1: int, r1: int, c2: int, r2: int) -> bool:
	return Game.can_move_between_cells(c1, r1, c2, r2, _unit_max_climb_up_steps(u))

func _can_unit_move_between_points(u: Unit, ax: float, ay: float, bx: float, by: float) -> bool:
	return Game.can_move_between_points(ax, ay, bx, by, _unit_max_climb_up_steps(u))

func _unit_uphill_speed_multiplier(u: Unit, step: Vector2) -> float:
	if step.length_squared() <= 0.0000001:
		return 1.0
	var c1 := clampi(int(u.gx), 0, Game.MAP_COLS - 1)
	var r1 := clampi(int(u.gy), 0, Game.MAP_ROWS - 1)
	var c2 := clampi(int(u.gx + step.x), 0, Game.MAP_COLS - 1)
	var r2 := clampi(int(u.gy + step.y), 0, Game.MAP_ROWS - 1)
	if c1 == c2 and r1 == r2:
		return 1.0
	if Game.get_elev(c2, r2) > Game.get_elev(c1, r1):
		return clampf(u.uphill_speed_mul, 0.0, 1.0)
	return 1.0

func _apply_ground_step(u: Unit, step: Vector2) -> float:
	if step.length_squared() <= 0.0000001:
		return 0.0
	var slowed_step := step * _unit_uphill_speed_multiplier(u, step)
	var full := Vector2(u.gx + slowed_step.x, u.gy + slowed_step.y)
	if _can_unit_move_between_points(u, u.gx, u.gy, full.x, full.y) and _ground_clear_at_radius(full.x, full.y, u.get_collision_radius()):
		u.gx = full.x
		u.gy = full.y
		return slowed_step.length()
	var can_x := absf(slowed_step.x) > 0.0001 and _can_unit_move_between_points(u, u.gx, u.gy, u.gx + slowed_step.x, u.gy) and _ground_clear_at_radius(u.gx + slowed_step.x, u.gy, u.get_collision_radius())
	var can_y := absf(slowed_step.y) > 0.0001 and _can_unit_move_between_points(u, u.gx, u.gy, u.gx, u.gy + slowed_step.y) and _ground_clear_at_radius(u.gx, u.gy + slowed_step.y, u.get_collision_radius())
	if can_x and can_y and u.destination != null:
		var x_pos := Vector2(u.gx + slowed_step.x, u.gy)
		var y_pos := Vector2(u.gx, u.gy + slowed_step.y)
		if x_pos.distance_to(u.destination) <= y_pos.distance_to(u.destination):
			u.gx = x_pos.x
			return absf(slowed_step.x)
		u.gy = y_pos.y
		return absf(slowed_step.y)
	if can_x:
		u.gx += slowed_step.x
		return absf(slowed_step.x)
	if can_y:
		u.gy += slowed_step.y
		return absf(slowed_step.y)
	return 0.0

func _clear_move_goal(u: Unit) -> void:
	u.destination = null
	u.path.clear()
	u.path_goal = null
	u.next_repath_at = 0.0
	u.blind_move = false

func _clear_attack_goal(u: Unit) -> void:
	u.attack_target = null
	u.attack_structure_target = null
	u.attack_point = null
	u.attack_point_tile = Vector2i(-1, -1)
	u.attack_point_hits_bridge = false
	u.attack_point_blind = false

func _unit_can_attack(u: Unit) -> bool:
	var tank: Tank = u as Tank
	return tank != null and tank.can_attack and tank.hp > 0

func _unit_attack_range(u: Unit) -> float:
	var tank: Tank = u as Tank
	if tank == null:
		return 0.0
	return tank.attack_range

func _unit_distance(a: Unit, b: Unit) -> float:
	return sqrt((b.gx - a.gx) ** 2 + (b.gy - a.gy) ** 2)

func _structure_center(s: Structure) -> Vector2:
	return Vector2(float(s.grid_col) + float(s.grid_w) * 0.5, float(s.grid_row) + float(s.grid_h) * 0.5)

func _structure_target_lift(s: Structure) -> float:
	var center: Vector2 = _structure_center(s)
	return Game.surface_lift_at(center.x, center.y) + 12.0

func _unit_distance_to_structure(u: Unit, s: Structure) -> float:
	return _distance_to_structure_footprint(u.gx, u.gy, s)

func _terrain_height_m_at(wx: float, wy: float) -> float:
	return Game.surface_elev_units_at(wx, wy) * Game.ELEV_METERS_PER_LEVEL

func _eye_height_m_at(wx: float, wy: float, observer_height_m: float) -> float:
	return _terrain_height_m_at(wx, wy) + observer_height_m

func _unit_is_in_forest(u: Unit) -> bool:
	return Game.get_tile(clampi(int(u.gx), 0, Game.MAP_COLS - 1), clampi(int(u.gy), 0, Game.MAP_ROWS - 1)) == Game.Tile.FOREST

func _detection_range_for_target(base_vision_range: float, target: Unit) -> float:
	if target.is_exposed():
		return base_vision_range
	if not _unit_is_in_forest(target):
		return base_vision_range
	return base_vision_range * Game.FOREST_CONCEALMENT * clampf(target.visibility_signature, 0.0, 1.0)

func _observer_can_detect_unit(origin: Vector2, base_vision_range: float, observer_eye_height_m: float, target: Unit) -> bool:
	var detection_range: float = _detection_range_for_target(base_vision_range, target)
	if origin.distance_to(Vector2(target.gx, target.gy)) > detection_range:
		return false
	return _point_visible_from(
		origin,
		detection_range,
		observer_eye_height_m,
		Vector2(target.gx, target.gy),
		_eye_height_m_at(target.gx, target.gy, Game.VIS_OBSERVER_HEIGHT_M))

func _structure_can_detect_unit(s: Structure, target: Unit) -> bool:
	var sx: float = s.grid_col + s.grid_w * 0.5
	var sy: float = s.grid_row + s.grid_h * 0.5
	return _observer_can_detect_unit(
		Vector2(sx, sy),
		Game.VIS_STRUCT,
		_eye_height_m_at(sx, sy, Game.VIS_STRUCT_OBSERVER_HEIGHT_M),
		target)

func _player_can_detect_unit(target: Unit) -> bool:
	if target.faction == Game.PLAYER or Game.cheat_reveal_all:
		return true
	var tc: int = clampi(int(target.gx), 0, Game.MAP_COLS - 1)
	var tr: int = clampi(int(target.gy), 0, Game.MAP_ROWS - 1)
	if not Game.fvis(tc, tr):
		return false
	for s_node in Game.get_structures():
		var s: Structure = s_node as Structure
		if s == null or s.faction != Game.PLAYER:
			continue
		if _structure_can_detect_unit(s, target):
			return true
	for observer in Game.get_units():
		var unit_observer: Unit = observer as Unit
		if unit_observer == null or unit_observer.faction != Game.PLAYER or unit_observer.hp <= 0:
			continue
		if _unit_can_see_hostile(unit_observer, target):
			return true
	return false

func _update_player_detection_visibility() -> void:
	for u_node in Game.get_units():
		var u: Unit = u_node as Unit
		if u == null:
			continue
		u.visible = true if u.faction == Game.PLAYER else _player_can_detect_unit(u)

func _vision_sector_start_angle() -> float:
	return -PI * 0.5

func _vision_sector_step() -> float:
	return TAU / float(VISION_RAY_COUNT)

func _vision_sector_index(origin: Vector2, target: Vector2) -> int:
	var dir: Vector2 = target - origin
	if dir.length_squared() <= 0.0001:
		return 0
	var angle: float = atan2(dir.y, dir.x)
	var wrapped: float = wrapf(angle - _vision_sector_start_angle(), 0.0, TAU)
	return clampi(int(floor((wrapped + _vision_sector_step() * 0.5) / _vision_sector_step())) % VISION_RAY_COUNT, 0, VISION_RAY_COUNT - 1)

func _build_visibility_sector_ranges(origin: Vector2, vision_radius: float, observer_eye_height_m: float) -> PackedFloat32Array:
	var ranges := PackedFloat32Array()
	ranges.resize(VISION_RAY_COUNT)
	ranges.fill(vision_radius)
	var angle_step: float = _vision_sector_step()
	var start_angle: float = _vision_sector_start_angle()
	for sector_idx in range(VISION_RAY_COUNT):
		var angle: float = start_angle + angle_step * float(sector_idx)
		var dir := Vector2(cos(angle), sin(angle))
		var last_tile := Vector2i(-1, -1)
		var dist: float = VISION_RAY_STEP
		while dist <= vision_radius + 0.001:
			var sample: Vector2 = origin + dir * dist
			if sample.x < 0.0 or sample.y < 0.0 or sample.x >= Game.MAP_COLS or sample.y >= Game.MAP_ROWS:
				ranges[sector_idx] = minf(ranges[sector_idx], dist)
				break
			var tile := Vector2i(clampi(int(sample.x), 0, Game.MAP_COLS - 1), clampi(int(sample.y), 0, Game.MAP_ROWS - 1))
			if tile == last_tile:
				dist += VISION_RAY_STEP
				continue
			last_tile = tile
			var tile_center := Vector2(tile.x + 0.5, tile.y + 0.5)
			var tile_dist: float = origin.distance_to(tile_center)
			if tile_dist > vision_radius + 0.75:
				dist += VISION_RAY_STEP
				continue
			var tile_height_m: float = _terrain_height_m_at(sample.x, sample.y)
			if tile_height_m > observer_eye_height_m + VISION_BLOCK_EPS_M:
				ranges[sector_idx] = minf(ranges[sector_idx], tile_dist)
				break
			dist += VISION_RAY_STEP
	return ranges

func _point_visible_from(origin: Vector2, vision_radius: float, observer_eye_height_m: float, target: Vector2, _target_height_m: float) -> bool:
	var total_dist: float = origin.distance_to(target)
	if total_dist > vision_radius + 0.001:
		return false
	if total_dist <= 0.05:
		return true
	var sector_ranges: PackedFloat32Array = _build_visibility_sector_ranges(origin, vision_radius, observer_eye_height_m)
	var sector_idx: int = _vision_sector_index(origin, target)
	return total_dist <= float(sector_ranges[sector_idx]) + 0.001

func _get_valid_attack_target(u: Unit) -> Unit:
	var target := u.attack_target as Unit
	if target == null or not is_instance_valid(target) or target.hp <= 0 or target.faction == u.faction:
		u.attack_target = null
		return null
	return target

func _get_valid_attack_structure_target(u: Unit) -> Structure:
	var target := u.attack_structure_target as Structure
	if target == null or not is_instance_valid(target) or target.hp <= 0.0 or target.faction == u.faction:
		u.attack_structure_target = null
		return null
	return target

func _get_valid_attack_point(u: Unit) -> Variant:
	var point: Variant = u.attack_point
	if point == null:
		return null
	if u.attack_point_hits_bridge:
		var tile: Vector2i = u.attack_point_tile
		if tile == Vector2i(-1, -1) or not Game.bridge_tile_at(tile.x, tile.y):
			_clear_attack_goal(u)
			return null
	return point

func _uses_direct_fire_ballistics(u: Unit) -> bool:
	return u is Tank and not (u is MortarSquad)

func _fire_target_elevation_allowed(u: Unit, fire_point: Vector2) -> bool:
	if not _uses_direct_fire_ballistics(u):
		return true
	var shooter_c: int = clampi(int(u.gx), 0, Game.MAP_COLS - 1)
	var shooter_r: int = clampi(int(u.gy), 0, Game.MAP_ROWS - 1)
	var target_c: int = clampi(int(fire_point.x), 0, Game.MAP_COLS - 1)
	var target_r: int = clampi(int(fire_point.y), 0, Game.MAP_ROWS - 1)
	var shooter_elev: int = Game.get_elev(shooter_c, shooter_r)
	var target_elev: int = Game.get_elev(target_c, target_r)
	return target_elev <= shooter_elev + 1

func _projectile_path_clear(u: Unit, fire_point: Vector2, end_lift: float) -> bool:
	if not _uses_direct_fire_ballistics(u):
		return true
	if not _fire_target_elevation_allowed(u, fire_point):
		return false
	var fire_vec: Vector2 = fire_point - Vector2(u.gx, u.gy)
	var fire_len: float = fire_vec.length()
	if fire_len <= 0.001:
		return true
	var fire_dir: Vector2 = fire_vec / fire_len
	var origin := Vector2(u.gx + fire_dir.x * 0.34, u.gy + fire_dir.y * 0.34)
	var start_lift: float = Game.surface_lift_at(origin.x, origin.y) + 19.0
	var total_len: float = origin.distance_to(fire_point)
	var target_cell := Vector2i(clampi(int(fire_point.x), 0, Game.MAP_COLS - 1), clampi(int(fire_point.y), 0, Game.MAP_ROWS - 1))
	var arc_peak: float = clampf(
		Game.SHELL_ARC_BASE +
		total_len * Game.SHELL_ARC_PER_UNIT +
		maxf(0.0, start_lift - end_lift) * Game.SHELL_ARC_ELEV_BIAS,
		12.0,
		38.0
	)
	var steps: int = maxi(4, ceili(total_len / 0.18))
	for i in range(1, steps):
		var travel_t: float = float(i) / float(steps)
		var sample: Vector2 = origin.lerp(fire_point, travel_t)
		var sample_cell := Vector2i(clampi(int(sample.x), 0, Game.MAP_COLS - 1), clampi(int(sample.y), 0, Game.MAP_ROWS - 1))
		if sample_cell == target_cell:
			continue
		var shell_lift: float = lerpf(start_lift, end_lift, travel_t) + arc_peak * (4.0 * travel_t * (1.0 - travel_t))
		var terrain_lift: float = Game.surface_lift_at(sample.x, sample.y)
		if terrain_lift + 4.0 > shell_lift:
			return false
	return true

func _unit_can_fire_at_target(u: Unit, target: Unit) -> bool:
	return _projectile_path_clear(u, Vector2(target.gx, target.gy), target.get_lift())

func _unit_can_fire_at_structure(u: Unit, target: Structure) -> bool:
	return _projectile_path_clear(u, _structure_center(target), _structure_target_lift(target))

func _unit_can_fire_at_point(u: Unit, fire_point: Vector2) -> bool:
	return _projectile_path_clear(u, fire_point, Game.surface_lift_at(fire_point.x, fire_point.y) + 4.0)

func _update_attack_pursuit(u: Unit, force_repath: bool = false) -> bool:
	var target := _get_valid_attack_target(u)
	if target == null:
		return false
	var target_dist := _unit_distance(u, target)
	var attack_range: float = _unit_attack_range(u)
	if target_dist <= attack_range and _unit_can_see_hostile(u, target) and _unit_can_fire_at_target(u, target):
		_clear_move_goal(u)
		return true
	var offset_dist := maxf(u.get_collision_radius() + target.get_collision_radius() + 0.18, attack_range * 0.82)
	var dir := Vector2(target.gx - u.gx, target.gy - u.gy)
	var dir_len := dir.length()
	var normal := dir / dir_len if dir_len > 0.001 else Vector2(1.0, 0.0)
	var desired := Vector2(target.gx, target.gy) - normal * offset_dist
	var attack_spot: Variant = _find_ground_open_at(desired.x, desired.y, u.get_collision_radius())
	if attack_spot == null:
		attack_spot = _find_ground_open_at(target.gx - normal.x * (u.get_collision_radius() + 0.16), target.gy - normal.y * (u.get_collision_radius() + 0.16), u.get_collision_radius())
	if attack_spot == null:
		return false
	return _set_move_goal(u, attack_spot, force_repath, false)

func _update_attack_structure_pursuit(u: Unit, force_repath: bool = false) -> bool:
	var target := _get_valid_attack_structure_target(u)
	if target == null:
		return false
	var target_dist: float = _unit_distance_to_structure(u, target)
	var attack_range: float = _unit_attack_range(u)
	if target_dist <= attack_range and _unit_can_see_hostile_structure(u, target) and _unit_can_fire_at_structure(u, target):
		_clear_move_goal(u)
		return true
	var center: Vector2 = _structure_center(target)
	var dir := center - Vector2(u.gx, u.gy)
	var dir_len := dir.length()
	var normal := dir / dir_len if dir_len > 0.001 else Vector2(1.0, 0.0)
	var footprint_radius: float = maxf(float(target.grid_w), float(target.grid_h)) * 0.5
	var offset_dist := maxf(u.get_collision_radius() + footprint_radius + 0.18, attack_range * 0.82)
	var desired := center - normal * offset_dist
	var attack_spot: Variant = _find_ground_open_at(desired.x, desired.y, u.get_collision_radius())
	if attack_spot == null:
		attack_spot = _find_ground_open_near_structure(target, u.get_collision_radius())
	if attack_spot == null:
		return false
	return _set_move_goal(u, attack_spot, force_repath, false)

func _update_ground_attack_pursuit(u: Unit, force_repath: bool = false) -> bool:
	var point_var: Variant = _get_valid_attack_point(u)
	if point_var == null:
		return false
	var attack_point: Vector2 = point_var
	var attack_range: float = _unit_attack_range(u)
	var target_dist: float = Vector2(u.gx, u.gy).distance_to(attack_point)
	if target_dist <= attack_range and _unit_can_fire_at_point(u, attack_point):
		_clear_move_goal(u)
		return true
	var dir := attack_point - Vector2(u.gx, u.gy)
	var dir_len := dir.length()
	var normal := dir / dir_len if dir_len > 0.001 else Vector2(1.0, 0.0)
	var offset_dist := maxf(u.get_collision_radius() + 0.24, attack_range * 0.82)
	var desired := attack_point - normal * offset_dist
	var blind_order: bool = u.attack_point_blind
	var attack_spot: Variant = _clamp_ground_target(desired.x, desired.y, u.get_collision_radius()) if blind_order else _find_ground_open_at(desired.x, desired.y, u.get_collision_radius())
	if attack_spot == null and not blind_order:
		attack_spot = _find_ground_open_at(
			attack_point.x - normal.x * (u.get_collision_radius() + 0.16),
			attack_point.y - normal.y * (u.get_collision_radius() + 0.16),
			u.get_collision_radius())
	if attack_spot == null:
		return false
	var attack_spot_blind: bool = blind_order or not Game.fexp(clampi(int(attack_spot.x), 0, Game.MAP_COLS - 1), clampi(int(attack_spot.y), 0, Game.MAP_ROWS - 1))
	return _set_move_goal(u, attack_spot, force_repath, attack_spot_blind)

func _set_move_goal(u: Unit, target: Variant, force_repath: bool = false, blind_move: bool = false) -> bool:
	if target == null:
		_clear_move_goal(u)
		return false
	var target_pos: Vector2 = target
	u.destination = target_pos
	u.blind_move = blind_move
	if u.blind_move:
		u.path.clear()
		u.path_goal = null
		u.next_repath_at = 0.0
		return true
	var changed: bool = force_repath or u.path_goal == null or u.path_goal.distance_to(target_pos) >= PATH_GOAL_EPS
	if changed or (u.path.is_empty() and Game.elapsed >= u.next_repath_at):
		var ok := _repath_unit(u)
		u.next_repath_at = Game.elapsed + PATH_REPATH_S
		return ok
	return true

func _repath_unit(u: Unit) -> bool:
	u.path.clear()
	if u.destination == null:
		u.path_goal = null
		return false
	if u.blind_move:
		u.path_goal = null
		return false
	var require_explored: bool = u.faction == Game.PLAYER
	var goal_cell := Vector2i(clampi(int(u.destination.x), 0, Game.MAP_COLS - 1), clampi(int(u.destination.y), 0, Game.MAP_ROWS - 1))
	if require_explored and not Game.fexp(goal_cell.x, goal_cell.y):
		u.path_goal = null
		return false
	var route: Variant = _find_path_points(u, Vector2(u.gx, u.gy), u.destination, u.get_collision_radius(), require_explored)
	u.path_goal = u.destination
	if route == null:
		return false
	for p in route:
		u.path.append(p)
	return true

func _find_path_points(u: Unit, start: Vector2, goal: Vector2, radius: float, require_explored: bool = false):
	if start.distance_to(goal) <= 0.08:
		return []
	if _ground_segment_clear(u, start, goal, radius, require_explored):
		return [goal]
	var start_cell := Vector2i(clampi(int(start.x), 0, Game.MAP_COLS - 1), clampi(int(start.y), 0, Game.MAP_ROWS - 1))
	var goal_cell := Vector2i(clampi(int(goal.x), 0, Game.MAP_COLS - 1), clampi(int(goal.y), 0, Game.MAP_ROWS - 1))
	if require_explored and not Game.fexp(goal_cell.x, goal_cell.y):
		return null
	var open: Array[Vector2i] = [start_cell]
	var open_has := {}
	open_has[start_cell] = true
	var closed := {}
	var came := {}
	var g_cost := {}
	g_cost[start_cell] = 0.0
	var f_cost := {}
	f_cost[start_cell] = _path_heuristic(start_cell, goal_cell)
	while not open.is_empty():
		var best_idx: int = 0
		var current: Vector2i = open[0]
		var best_f: float = f_cost.get(current, INF)
		for i in range(1, open.size()):
			var cand: Vector2i = open[i]
			var cand_f: float = f_cost.get(cand, INF)
			if cand_f < best_f:
				best_idx = i
				current = cand
				best_f = cand_f
		open.remove_at(best_idx)
		open_has.erase(current)
		if current == goal_cell:
			return _reconstruct_path_points(u, came, current, start, goal, radius, require_explored)
		closed[current] = true
		for dir: Vector2i in PATH_DIRS:
			var nxt: Vector2i = current + dir
			if closed.has(nxt):
				continue
			if not _path_tile_open(nxt.x, nxt.y, radius, require_explored):
				continue
			if not _can_unit_move_between_cells(u, current.x, current.y, nxt.x, nxt.y):
				continue
			var step_cost: float = 1.0
			var cand_g: float = g_cost.get(current, INF) + step_cost
			if cand_g >= g_cost.get(nxt, INF):
				continue
			came[nxt] = current
			g_cost[nxt] = cand_g
			f_cost[nxt] = cand_g + _path_heuristic(nxt, goal_cell)
			if not open_has.has(nxt):
				open.append(nxt)
				open_has[nxt] = true
	return null

func _reconstruct_path_points(u: Unit, came: Dictionary, current: Vector2i, start: Vector2, goal: Vector2, radius: float, require_explored: bool = false):
	var cells: Array[Vector2i] = [current]
	while came.has(current):
		var prev: Vector2i = came[current]
		current = prev
		cells.push_front(current)
	var pts: Array[Vector2] = []
	for i in range(1, cells.size()):
		pts.append(Vector2(cells[i].x + 0.5, cells[i].y + 0.5))
	if pts.is_empty() or pts[pts.size() - 1].distance_to(goal) > 0.05:
		pts.append(goal)
	return _simplify_path_points(u, start, pts, radius, require_explored)

func _simplify_path_points(u: Unit, start: Vector2, pts: Array[Vector2], radius: float, require_explored: bool = false) -> Array[Vector2]:
	if pts.is_empty():
		return pts
	var out: Array[Vector2] = []
	var anchor: Vector2 = start
	var idx: int = 0
	while idx < pts.size():
		var furthest: int = idx
		while furthest + 1 < pts.size() and _ground_segment_clear(u, anchor, pts[furthest + 1], radius, require_explored):
			furthest += 1
		out.append(pts[furthest])
		anchor = pts[furthest]
		idx = furthest + 1
	return out

func _ground_segment_clear(u: Unit, a: Vector2, b: Vector2, radius: float, require_explored: bool = false) -> bool:
	var len: float = a.distance_to(b)
	if len <= 0.0001:
		if require_explored and not Game.fexp(clampi(int(b.x), 0, Game.MAP_COLS - 1), clampi(int(b.y), 0, Game.MAP_ROWS - 1)):
			return false
		return _ground_clear_at_radius(b.x, b.y, radius)
	var steps: int = maxi(1, ceili(len / 0.3))
	var last := a
	for i in range(1, steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		if require_explored and not Game.fexp(clampi(int(p.x), 0, Game.MAP_COLS - 1), clampi(int(p.y), 0, Game.MAP_ROWS - 1)):
			return false
		if not _ground_clear_at_radius(p.x, p.y, radius) or not _can_unit_move_between_points(u, last.x, last.y, p.x, p.y):
			return false
		last = p
	return true

func _path_tile_open(c: int, r: int, radius: float, require_explored: bool = false) -> bool:
	if c < 0 or r < 0 or c >= Game.MAP_COLS or r >= Game.MAP_ROWS:
		return false
	if require_explored and not Game.fexp(c, r):
		return false
	return _ground_clear_at_radius(c + 0.5, r + 0.5, radius)

func _path_heuristic(a: Vector2i, b: Vector2i) -> float:
	return absf(float(a.x - b.x)) + absf(float(a.y - b.y))

# ═══════════════════════════════════════════════════════════════════════════════
#  UNIT MOVEMENT
# ═══════════════════════════════════════════════════════════════════════════════
func _update_units(dt: float) -> void:
	for u: Unit in Game.get_units():
		var super_tank := _super_tank_cheat_applies(u)
		var super_speed: bool = _super_speed_cheat_applies(u)
		if super_tank:
			u.supplies = u.max_supplies
			u.out_of_supply_started_at = -1.0
		if u.consumes_supplies and not super_tank and u.idle_supply_rate > 0.0:
			u.supplies = maxf(0.0, u.supplies - u.idle_supply_rate * dt)
		if u.is_out_of_supply():
			if u.out_of_supply_started_at < 0.0:
				u.out_of_supply_started_at = Game.elapsed
			elif Game.elapsed - u.out_of_supply_started_at >= Game.OUT_OF_SUPPLY_DEATH_S:
				u.hp = 0.0
				continue
		else:
			u.out_of_supply_started_at = -1.0
		var attack_target: Unit = null
		var attack_structure_target: Structure = null
		var attack_point: Variant = null
		if _unit_can_attack(u):
			attack_target = _get_valid_attack_target(u)
			if attack_target == null:
				attack_structure_target = _get_valid_attack_structure_target(u)
			if attack_target == null and attack_structure_target == null:
				attack_point = _get_valid_attack_point(u)
		# truck follow target
		var active_tu: Unit = null
		if u is Truck and u.follow_target != null:
			if is_instance_valid(u.follow_target):
				active_tu = u.follow_target as Unit
				var fd := Vector2(u.gx - active_tu.gx, u.gy - active_tu.gy)
				var fl := fd.length()
				var off := u.get_collision_radius() + active_tu.get_collision_radius() + 0.18
				var n := fd / fl if fl > 0.001 else Vector2(1, 0)
				_set_move_goal(u, _find_ground_open_at(
					active_tu.gx + n.x * off,
					active_tu.gy + n.y * off,
					u.get_collision_radius()))
			else:
				u.follow_target = null
				_clear_move_goal(u)
		var active_site: Airport = null
		if u is Truck and (u as Truck).construction_target != null:
			var site_target: Airport = (u as Truck).construction_target as Airport
			if site_target != null and is_instance_valid(site_target) and site_target.is_under_construction():
				active_site = site_target
				var site_goal: Variant = _find_ground_open_near_structure(site_target, u.get_collision_radius())
				if site_goal != null and Vector2(u.gx, u.gy).distance_to(site_goal) > Game.TRUCK_ARRIVE_R * 0.5:
					_set_move_goal(u, site_goal, false, false)
			else:
				(u as Truck).construction_target = null
				if active_tu == null:
					_clear_move_goal(u)
		if attack_target != null:
			_update_attack_pursuit(u)
		elif attack_structure_target != null:
			_update_attack_structure_pursuit(u)
		elif attack_point != null:
			_update_ground_attack_pursuit(u)
		if u.destination == null:
			if u is Truck: _update_truck_resupply(u as Truck, dt)
			continue
		var move_target: Vector2 = u.path[0] if not u.path.is_empty() else u.destination
		var dx: float = move_target.x - u.gx
		var dy: float = move_target.y - u.gy
		var dist := sqrt(dx * dx + dy * dy)
		var arr_r := Game.TRUCK_ARRIVE_R if u is Truck else 0.06
		if dist < arr_r:
			if not u.path.is_empty():
				u.path.remove_at(0)
				if u.path.is_empty() and u.destination != null and Vector2(u.gx, u.gy).distance_to(u.destination) < arr_r + 0.04:
					if u is Truck:
						if active_tu == null and active_site == null:
							_clear_move_goal(u)
							u.follow_target = null
					else:
						_clear_move_goal(u)
				if u is Truck: _update_truck_resupply(u as Truck, dt)
				continue
			if u is Truck:
				if active_tu == null and active_site == null:
					_clear_move_goal(u); u.follow_target = null
			else:
				_clear_move_goal(u)
		else:
			u.heading = Vector2(dx / dist, dy / dist)
			var max_by_sup: float = dist
			if not super_tank and u.consumes_supplies and u.move_supply_per_unit > 0.0:
				max_by_sup = u.supplies / u.move_supply_per_unit
			var hp_ratio: float = u.hp / u.max_hp if u.max_hp > 0 else 1.0
			var terrain_speed_mul: float = Game.move_speed_mult_at(u.gx, u.gy)
			var speed_mul := Game.SUPER_TANK_SPEED_MUL if super_speed else 1.0
			var travel := minf(dist, minf(u.speed * speed_mul * hp_ratio * terrain_speed_mul * dt, max_by_sup))
			if travel <= 0:
				if u.consumes_supplies and not super_tank and u.move_supply_per_unit > 0.0:
					u.supplies = 0.0
				continue
			var moved := _apply_ground_step(u, u.heading * travel)
			if moved <= 0.0:
				var repathed := _repath_unit(u)
				u.next_repath_at = Game.elapsed + PATH_REPATH_S
				if not repathed and active_tu == null and active_site == null:
					_clear_move_goal(u)
				if u is Truck: _update_truck_resupply(u as Truck, dt)
				continue
			if u.consumes_supplies and not super_tank and u.move_supply_per_unit > 0.0:
				u.supplies = maxf(0.0, u.supplies - moved * u.move_supply_per_unit)
			u.exposed_until = maxf(u.exposed_until, Game.elapsed + Game.EXPOSED_TTL_S)
		if u is Truck: _update_truck_resupply(u as Truck, dt)

func _update_truck_resupply(truck: Truck, dt: float) -> void:
	if truck == null:
		return
	truck.aura_query_accum_s += dt
	var moved_since_query: bool = truck.last_aura_query_pos.distance_to(Vector2(truck.gx, truck.gy)) >= Game.TRUCK_AURA_REQUERY_DIST
	if not moved_since_query and Game.elapsed < truck.next_aura_query_at:
		return
	var query_dt: float = truck.aura_query_accum_s
	truck.aura_query_accum_s = 0.0
	truck.next_aura_query_at = Game.elapsed + Game.TRUCK_AURA_QUERY_S
	truck.last_aura_query_pos = Vector2(truck.gx, truck.gy)
	_truck_aura(truck, query_dt)

func _truck_aura(truck: Truck, dt: float) -> void:
	if truck.supplies <= 0:
		truck.supplies = 0.0
		return
	var target_site: Airport = truck.construction_target as Airport
	if target_site != null:
		if not is_instance_valid(target_site) or not target_site.is_under_construction():
			truck.construction_target = null
		else:
			var site_dist: float = _distance_to_structure_footprint(truck.gx, truck.gy, target_site)
			if site_dist <= Game.TRUCK_RESUPPLY_R:
				var transfer_cap: float = minf(truck.supplies, Game.TRUCK_RESUPPLY_S * dt)
				var sent: float = target_site.receive_build_supply(transfer_cap)
				if sent > 0.0:
					truck.supplies = maxf(0.0, truck.supplies - sent)
				if not target_site.can_receive_build_supply():
					truck.construction_target = null
			return
	var recip: Array = _nearby_supply_receivers(truck)
	if recip.is_empty(): return
	var best_site: Airport = null
	var best_site_dist: float = INF
	var unit_recip: Array = []
	for node in recip:
		var site: Airport = node as Airport
		if site != null:
			var dist_to_site: float = _distance_to_structure_footprint(truck.gx, truck.gy, site)
			if dist_to_site < best_site_dist:
				best_site = site
				best_site_dist = dist_to_site
			continue
		var unit_receiver: Unit = node as Unit
		if unit_receiver != null:
			unit_recip.append(unit_receiver)
	if best_site != null:
		var site_cap: float = minf(truck.supplies, Game.TRUCK_RESUPPLY_S * dt)
		var site_sent: float = best_site.receive_build_supply(site_cap)
		if site_sent > 0.0:
			truck.supplies = maxf(0.0, truck.supplies - site_sent)
		return
	if unit_recip.is_empty():
		return
	var remain := minf(truck.supplies, Game.TRUCK_RESUPPLY_S * dt)
	if remain <= 0: return
	var pool: Array = unit_recip.duplicate()
	while remain > 0.001 and not pool.is_empty():
		var split := remain / pool.size()
		var i := pool.size() - 1
		while i >= 0:
			var u = pool[i]
			var need: float = u.max_supplies - u.supplies
			if need <= 0: pool.remove_at(i); i -= 1; continue
			var g: float = minf(split, minf(need, remain))
			u.supplies += g; remain -= g
			if u.max_supplies - u.supplies <= 0.001: pool.remove_at(i)
			i -= 1
	var xfer := minf(truck.supplies, Game.TRUCK_RESUPPLY_S * dt) - remain
	truck.supplies = maxf(0.0, truck.supplies - xfer)

func _supply_cell_key(wx: float, wy: float) -> Vector2i:
	return Vector2i(int(floor(wx / Game.TRUCK_AURA_CELL)), int(floor(wy / Game.TRUCK_AURA_CELL)))

func _ensure_supply_receiver_index() -> void:
	if _supply_receiver_index_built_at >= 0.0 and Game.elapsed - _supply_receiver_index_built_at < Game.TRUCK_AURA_QUERY_S:
		return
	_supply_receiver_index.clear()
	_supply_receiver_index_built_at = Game.elapsed
	for node in Game.get_units():
		var u: Unit = node as Unit
		if u == null or u.hp <= 0:
			continue
		if not u.accepts_resupply or u.max_supplies <= u.supplies:
			continue
		var key: Vector2i = _supply_cell_key(u.gx, u.gy)
		if not _supply_receiver_index.has(key):
			_supply_receiver_index[key] = []
		(_supply_receiver_index[key] as Array).append(u)
	for node in Game.get_structures():
		var site: Airport = node as Airport
		if site == null or not is_instance_valid(site):
			continue
		if not site.can_receive_build_supply():
			continue
		var sx: float = float(site.grid_col) + float(site.grid_w) * 0.5
		var sy: float = float(site.grid_row) + float(site.grid_h) * 0.5
		var key: Vector2i = _supply_cell_key(sx, sy)
		if not _supply_receiver_index.has(key):
			_supply_receiver_index[key] = []
		(_supply_receiver_index[key] as Array).append(site)

func _nearby_supply_receivers(truck: Truck) -> Array:
	_ensure_supply_receiver_index()
	var recip: Array = []
	var seen := {}
	var center_key: Vector2i = _supply_cell_key(truck.gx, truck.gy)
	var cell_span: int = maxi(1, int(ceili(Game.TRUCK_RESUPPLY_R / Game.TRUCK_AURA_CELL)))
	var max_d_sq: float = Game.TRUCK_RESUPPLY_R * Game.TRUCK_RESUPPLY_R
	for ro in range(-cell_span, cell_span + 1):
		for co in range(-cell_span, cell_span + 1):
			var key := Vector2i(center_key.x + co, center_key.y + ro)
			var bucket: Array = _supply_receiver_index.get(key, [])
			for node in bucket:
				if node == null or not is_instance_valid(node):
					continue
				var node_id: int = node.get_instance_id()
				if seen.has(node_id):
					continue
				var u: Unit = node as Unit
				if u != null:
					if u == truck or u.faction != truck.faction:
						continue
					var dx: float = u.gx - truck.gx
					var dy: float = u.gy - truck.gy
					if dx * dx + dy * dy > max_d_sq:
						continue
					seen[node_id] = true
					recip.append(u)
					continue
				var site: Airport = node as Airport
				if site != null:
					if site.faction != truck.faction:
						continue
					if _distance_to_structure_footprint(truck.gx, truck.gy, site) > Game.TRUCK_RESUPPLY_R:
						continue
					seen[node_id] = true
					recip.append(site)
	return recip

# ═══════════════════════════════════════════════════════════════════════════════
#  COLLISION
# ═══════════════════════════════════════════════════════════════════════════════
func _resolve_collisions() -> void:
	var movs: Array = []
	for u: Unit in Game.get_units():
		if u.movable: movs.append(u)
	if movs.is_empty(): return
	for _iter in Game.COL_ITERS:
		var bk := {}
		for u in movs:
			_clamp_unit(u); _ensure_passable(u)
			var bx := int(u.gx / Game.COL_CELL)
			var by := int(u.gy / Game.COL_CELL)
			var key := Vector2i(bx, by)
			if not bk.has(key): bk[key] = []
			bk[key].append(u)
		for u in movs:
			var bx := int(u.gx / Game.COL_CELL)
			var by := int(u.gy / Game.COL_CELL)
			for ro in range(-1, 2):
				for co in range(-1, 2):
					var nk := Vector2i(bx + co, by + ro)
					if not bk.has(nk): continue
					for o in bk[nk]:
						if o.get_instance_id() <= u.get_instance_id(): continue
						_sep(u, o)
	for u in movs:
		_clamp_unit(u)
		_ensure_passable(u)

func _clamp_unit(u: Unit) -> void:
	var r := u.get_collision_radius()
	var pad := maxf(0.8, r + 0.2)
	u.gx = clampf(u.gx, pad, Game.MAP_COLS - pad)
	u.gy = clampf(u.gy, pad, Game.MAP_ROWS - pad)

func _ensure_passable(u: Unit) -> void:
	if _ground_clear_at_radius(u.gx, u.gy, u.get_collision_radius()):
		return
	var fb = _find_ground_open_at(u.gx, u.gy, u.get_collision_radius())
	if fb != null:
		u.gx = fb.x
		u.gy = fb.y

func _sep(a: Unit, b: Unit) -> void:
	var min_d := a.get_collision_radius() + b.get_collision_radius() + Game.COL_PAD
	var dx: float = b.gx - a.gx; var dy: float = b.gy - a.gy
	var d := sqrt(dx * dx + dy * dy)
	if d >= min_d: return
	var ax0 := a.gx
	var ay0 := a.gy
	var bx0 := b.gx
	var by0 := b.gy
	if d < 0.0001:
		var ang := fmod(float(a.get_instance_id() * 92821 + b.get_instance_id() * 68917), 360.0) * PI / 180.0
		dx = cos(ang); dy = sin(ang); d = 0.0
	else:
		dx /= d; dy /= d
	var s := (min_d - d) * 0.5
	a.gx -= dx * s; a.gy -= dy * s
	b.gx += dx * s; b.gy += dy * s
	if not _can_unit_move_between_points(a, ax0, ay0, a.gx, a.gy):
		a.gx = ax0
		a.gy = ay0
	if not _can_unit_move_between_points(b, bx0, by0, b.gx, b.gy):
		b.gx = bx0
		b.gy = by0
	_clamp_unit(a); _clamp_unit(b)

# ═══════════════════════════════════════════════════════════════════════════════
#  COMBAT
# ═══════════════════════════════════════════════════════════════════════════════
func _update_combat(_dt: float) -> void:
	for unit_node in Game.get_units():
		var tank: Tank = unit_node as Tank
		if tank == null or not tank.can_attack or tank.hp <= 0:
			continue
		var attack_range: float = _unit_attack_range(tank)
		var tgt: Unit = _get_valid_attack_target(tank)
		var structure_tgt: Structure = null
		var attack_point: Variant = null
		if tgt != null and (_unit_distance(tank, tgt) > attack_range or not _unit_can_see_hostile(tank, tgt) or not _unit_can_fire_at_target(tank, tgt)):
			tgt = null
		if tgt == null:
			structure_tgt = _get_valid_attack_structure_target(tank)
		if structure_tgt != null and (_unit_distance_to_structure(tank, structure_tgt) > attack_range or not _unit_can_see_hostile_structure(tank, structure_tgt) or not _unit_can_fire_at_structure(tank, structure_tgt)):
			structure_tgt = null
		if tgt == null and structure_tgt == null:
			attack_point = _get_valid_attack_point(tank)
		if tgt == null and structure_tgt == null and attack_point == null:
			tgt = _nearest_visible_hostile(tank, attack_range)
			if tgt != null and not _unit_can_fire_at_target(tank, tgt):
				tgt = null
		if tgt == null and structure_tgt == null and attack_point == null:
			structure_tgt = _nearest_visible_hostile_structure(tank, attack_range)
			if structure_tgt != null and not _unit_can_fire_at_structure(tank, structure_tgt):
				structure_tgt = null
		if tgt == null and structure_tgt == null and attack_point == null:
			continue
		var fire_point: Vector2
		if tgt != null:
			fire_point = Vector2(tgt.gx, tgt.gy)
		elif structure_tgt != null:
			fire_point = _structure_center(structure_tgt)
		else:
			fire_point = attack_point
			if Vector2(tank.gx, tank.gy).distance_to(fire_point) > attack_range or not _unit_can_fire_at_point(tank, fire_point):
				continue
		var dx: float = fire_point.x - tank.gx
		var dy: float = fire_point.y - tank.gy
		var d := sqrt(dx * dx + dy * dy)
		if d <= 0.001:
			continue
		tank.heading = Vector2(dx / d, dy / d)
		if not tank.attack_timer.is_stopped():
			continue
		var super_tank := _super_tank_cheat_applies(tank)
		if tank.consumes_supplies and not super_tank and tank.attack_supply_per_shot > 0.0 and tank.supplies < tank.attack_supply_per_shot:
			continue
		var atk_hp_ratio: float = tank.hp / tank.max_hp if tank.max_hp > 0 else 1.0
		tank.attack_timer.start(tank.attack_timer.wait_time)
		if tank.consumes_supplies and not super_tank and tank.attack_supply_per_shot > 0.0:
			tank.supplies = maxf(0.0, tank.supplies - tank.attack_supply_per_shot)
		tank.exposed_until = maxf(tank.exposed_until, Game.elapsed + Game.EXPOSED_TTL_S)
		var muzzle_x: float = tank.gx + tank.heading.x * 0.34
		var muzzle_y: float = tank.gy + tank.heading.y * 0.34
		var muzzle_lift: float = Game.surface_lift_at(muzzle_x, muzzle_y) + 19.0
		var target_lift: float = Game.surface_lift_at(fire_point.x, fire_point.y) + 4.0
		if tgt != null:
			target_lift = tgt.get_lift()
		elif structure_tgt != null:
			target_lift = _structure_target_lift(structure_tgt)
		var shell: Dictionary = {
			"faction": tank.faction,
			"sx": muzzle_x, "sy": muzzle_y,
			"sz_lift": muzzle_lift,
			"tx": fire_point.x, "ty": fire_point.y,
			"tz_lift": target_lift,
			"damage": tank.attack_damage * atk_hp_ratio,
			"target": tgt,
		}
		if structure_tgt != null:
			shell["target_structure"] = structure_tgt
		if tank is MortarSquad:
			shell["speed"] = Game.MORTAR_SHELL_SPEED
			shell["arc_base"] = Game.MORTAR_SHELL_ARC_BASE
			shell["arc_per_unit"] = Game.MORTAR_SHELL_ARC_PER_UNIT
			shell["arc_min"] = Game.MORTAR_SHELL_ARC_MIN
			shell["arc_max"] = Game.MORTAR_SHELL_ARC_MAX
		if tgt == null and tank.attack_point_hits_bridge and tank.attack_point_tile != Vector2i(-1, -1):
			shell["bridge_tile"] = tank.attack_point_tile
		overlay.fire_shell(shell)

func _on_shell_hit(shell: Dictionary) -> void:
	var tgt: Variant = shell.get("target", null)
	var hit_unit := tgt as Unit
	if hit_unit != null and is_instance_valid(hit_unit) and hit_unit.hp > 0:
		hit_unit.hp = maxf(0.0, hit_unit.hp - float(shell.get("damage", Game.ATK_DMG)))
		hit_unit.status_display_until = Game.elapsed + Game.DMG_BAR_S
		return
	var structure_target: Structure = shell.get("target_structure", null) as Structure
	if structure_target != null and is_instance_valid(structure_target) and structure_target.hp > 0.0:
		structure_target.hp = maxf(0.0, structure_target.hp - float(shell.get("damage", Game.ATK_DMG)))
		return
	var impact_point := Vector2(float(shell.get("tx", 0.0)), float(shell.get("ty", 0.0)))
	var impact_unit: Unit = _ground_impact_unit_at(impact_point)
	if impact_unit != null:
		impact_unit.hp = maxf(0.0, impact_unit.hp - float(shell.get("damage", Game.ATK_DMG)))
		impact_unit.status_display_until = Game.elapsed + Game.DMG_BAR_S
		return
	var impact_structure: Structure = _ground_impact_structure_at(impact_point)
	if impact_structure != null:
		impact_structure.hp = maxf(0.0, impact_structure.hp - float(shell.get("damage", Game.ATK_DMG)))
		return
	var bridge_tile: Vector2i = shell.get("bridge_tile", Vector2i(-1, -1))
	if bridge_tile != Vector2i(-1, -1) and Game.damage_bridge(bridge_tile.x, bridge_tile.y, float(shell.get("damage", Game.ATK_DMG))):
		hud.set_status("Bridge destroyed.")

func _ground_impact_unit_at(point: Vector2) -> Unit:
	for node in Game.get_units():
		var u: Unit = node as Unit
		if u == null or u.hp <= 0.0:
			continue
		if point.distance_to(Vector2(u.gx, u.gy)) <= u.get_collision_radius():
			return u
	return null

func _ground_impact_structure_at(point: Vector2) -> Structure:
	var tile_c: int = clampi(int(point.x), 0, Game.MAP_COLS - 1)
	var tile_r: int = clampi(int(point.y), 0, Game.MAP_ROWS - 1)
	var tile_structure: Structure = Game.struct_at(tile_c, tile_r) as Structure
	if tile_structure != null and tile_structure.hp > 0.0:
		return tile_structure
	for s_node in Game.get_structures():
		var s: Structure = s_node as Structure
		if s == null or s.hp <= 0.0:
			continue
		if _distance_to_structure_footprint(point.x, point.y, s) <= Game.SHELL_HIT_R:
			return s
	return null

func _nearest_hostile(u: Unit, rng: float) -> Unit:
	var best: Unit = null; var best_d := rng
	for c: Unit in Game.get_units():
		if c == u or c.hp <= 0 or c.faction == u.faction: continue
		var d := sqrt((c.gx - u.gx) ** 2 + (c.gy - u.gy) ** 2)
		if d <= rng and d < best_d: best_d = d; best = c
	return best

func _unit_can_see_hostile(u: Unit, c: Unit) -> bool:
	var vision_radius: float = _unit_vision_radius(u)
	return _observer_can_detect_unit(
		Vector2(u.gx, u.gy),
		vision_radius,
		_eye_height_m_at(u.gx, u.gy, Game.VIS_OBSERVER_HEIGHT_M),
		c)

func _unit_can_see_hostile_structure(u: Unit, s: Structure) -> bool:
	var origin := Vector2(u.gx, u.gy)
	var target_center: Vector2 = _structure_center(s)
	var vision_radius: float = _unit_vision_radius(u)
	if _unit_distance_to_structure(u, s) > vision_radius:
		return false
	return _point_visible_from(
		origin,
		vision_radius,
		_eye_height_m_at(u.gx, u.gy, Game.VIS_OBSERVER_HEIGHT_M),
		target_center,
		_structure_target_lift(s))

func _nearest_visible_hostile(u: Unit, rng: float) -> Unit:
	var best: Unit = null
	var best_d: float = rng
	for c: Unit in Game.get_units():
		if c == u or c.hp <= 0 or c.faction == u.faction:
			continue
		if not _unit_can_see_hostile(u, c):
			continue
		var d: float = _unit_distance(u, c)
		if d <= rng and d < best_d:
			best_d = d
			best = c
	return best

func _nearest_visible_hostile_structure(u: Unit, rng: float) -> Structure:
	var best: Structure = null
	var best_d: float = rng
	for s_node in Game.get_structures():
		var s: Structure = s_node as Structure
		if s == null or s.hp <= 0.0 or s.faction == u.faction:
			continue
		if not _unit_can_see_hostile_structure(u, s):
			continue
		var d: float = _unit_distance_to_structure(u, s)
		if d <= rng and d < best_d:
			best_d = d
			best = s
	return best

func _remove_dead() -> void:
	var enemy_cnt := 0
	var enemy_structure_cnt := 0
	var dead: Array = []
	var dead_structures: Array = []
	for u: Unit in Game.get_units():
		if u.hp <= 0:
			dead.append(u)
			if u.faction == Game.ENEMY: enemy_cnt += 1
	for s_node in Game.get_structures():
		var s: Structure = s_node as Structure
		if s != null and s.hp <= 0.0:
			dead_structures.append(s)
			if s.faction == Game.ENEMY:
				enemy_structure_cnt += 1
	if dead.is_empty() and dead_structures.is_empty():
		return
	for u in dead:
		Game.selected_units.erase(u)
		# Clean up truck follow targets pointing to dead unit
		for other: Unit in Game.get_units():
			if other is Truck and other.follow_target == u:
				other.follow_target = null
				_clear_move_goal(other)
		Game.unit_died.emit(u)
		u.died.emit()
		u.queue_free()
	for s in dead_structures:
		if Game.selected_structure == s:
			Game.selected_structure = null
		for other: Unit in Game.get_units():
			if other is Truck and (other as Truck).construction_target == s:
				(other as Truck).construction_target = null
				_clear_move_goal(other)
			if other.attack_structure_target == s:
				other.attack_structure_target = null
				_clear_move_goal(other)
		s.destroyed.emit()
		s.queue_free()
	if enemy_cnt > 0 and enemy_structure_cnt > 0:
		hud.set_status("%d enemy tanks and %d enemy structures destroyed." % [enemy_cnt, enemy_structure_cnt])
	elif enemy_cnt > 0:
		hud.set_status(
			"Enemy tank destroyed." if enemy_cnt == 1
			else str(enemy_cnt) + " enemy tanks destroyed.")
	elif enemy_structure_cnt > 0:
		hud.set_status(
			"Enemy structure destroyed." if enemy_structure_cnt == 1
			else str(enemy_structure_cnt) + " enemy structures destroyed.")

# ═══════════════════════════════════════════════════════════════════════════════
#  FOG
# ═══════════════════════════════════════════════════════════════════════════════
func _update_fog() -> void:
	if Game.cheat_reveal_all:
		return
	var fog_sig := _fog_signature()
	if fog_sig == _last_fog_sig:
		return
	_last_fog_sig = fog_sig
	var prev_vis: PackedByteArray = Game.fog_vis.duplicate()
	Game.fog_reset_vis()
	for s: Structure in Game.get_structures():
		if s.faction == Game.PLAYER:
			_reveal(s.grid_col + s.grid_w * 0.5, s.grid_row + s.grid_h * 0.5, Game.VIS_STRUCT, Game.VIS_STRUCT_OBSERVER_HEIGHT_M)
	for u: Unit in Game.get_units():
		if u.faction == Game.PLAYER:
			_reveal(u.gx, u.gy, _unit_vision_radius(u), Game.VIS_OBSERVER_HEIGHT_M)
	if prev_vis != Game.fog_vis:
		Game.fog_revision += 1

func _unit_vision_radius(u: Unit) -> float:
	var elev_units: float = maxf(0.0, Game.surface_elev_units_at(u.gx, u.gy))
	if elev_units <= 0.0:
		return u.vision_radius
	var observer_height_m: float = Game.VIS_OBSERVER_HEIGHT_M
	var total_height_m: float = observer_height_m + elev_units * Game.ELEV_METERS_PER_LEVEL
	var vision_mul: float = sqrt(total_height_m / observer_height_m)
	return u.vision_radius * vision_mul

func _fog_signature() -> String:
	var parts: Array[String] = []
	for s: Structure in Game.get_structures():
		if s.faction == Game.PLAYER:
			parts.append("s:%d:%d:%d" % [s.get_instance_id(), s.grid_col, s.grid_row])
	for u: Unit in Game.get_units():
		if u.faction == Game.PLAYER:
			parts.append("u:%d:%d:%d" % [u.get_instance_id(), roundi(u.gx * 4.0), roundi(u.gy * 4.0)])
	return "|".join(parts)

func _reveal(cx: float, cy: float, rad: float, observer_height_m: float = Game.VIS_OBSERVER_HEIGHT_M) -> void:
	if rad <= 0.0:
		return
	var origin := Vector2(cx, cy)
	var origin_tile := Vector2i(clampi(int(cx), 0, Game.MAP_COLS - 1), clampi(int(cy), 0, Game.MAP_ROWS - 1))
	Game.fog_set(origin_tile.x, origin_tile.y)
	var observer_eye_height_m: float = _eye_height_m_at(cx, cy, observer_height_m)
	var sector_ranges: PackedFloat32Array = _build_visibility_sector_ranges(origin, rad, observer_eye_height_m)
	var mnc := clampi(int(cx - rad), 0, Game.MAP_COLS - 1)
	var mxc := clampi(ceili(cx + rad), 0, Game.MAP_COLS - 1)
	var mnr := clampi(int(cy - rad), 0, Game.MAP_ROWS - 1)
	var mxr := clampi(ceili(cy + rad), 0, Game.MAP_ROWS - 1)
	for r in range(mnr, mxr + 1):
		for c in range(mnc, mxc + 1):
			var tile_center := Vector2(c + 0.5, r + 0.5)
			var tile_dist: float = origin.distance_to(tile_center)
			if tile_dist > rad + 0.001:
				continue
			var sector_idx: int = _vision_sector_index(origin, tile_center)
			if tile_dist <= float(sector_ranges[sector_idx]) + 0.001:
				Game.fog_set(c, r)

# ═══════════════════════════════════════════════════════════════════════════════
#  ENEMY AI
# ═══════════════════════════════════════════════════════════════════════════════
func _update_enemy_ai() -> void:
	for u: Unit in Game.get_units():
		if u.faction != Game.ENEMY or not (u is Tank) or u.hp <= 0: continue
		var attack_range: float = _unit_attack_range(u)
		var tgt: Unit = _nearest_visible_hostile(u, attack_range)
		var struct_tgt: Structure = null
		if tgt != null and _unit_can_fire_at_target(u, tgt):
			_clear_move_goal(u)
		else:
			struct_tgt = _nearest_visible_hostile_structure(u, attack_range)
			if struct_tgt != null and _unit_can_fire_at_structure(u, struct_tgt):
				_clear_move_goal(u)
				continue
			var seek_range: float = maxf(Game.ENEMY_SEEK_R, _unit_vision_radius(u))
			var seek: Unit = _nearest_visible_hostile(u, seek_range)
			if seek != null:
				_set_move_goal(u, Vector2(seek.gx, seek.gy))
			else:
				var seek_structure: Structure = _nearest_visible_hostile_structure(u, seek_range)
				if seek_structure != null:
					_set_move_goal(u, _structure_center(seek_structure))
				else:
					_clear_move_goal(u)

# ═══════════════════════════════════════════════════════════════════════════════
#  SPAWN
# ═══════════════════════════════════════════════════════════════════════════════
func _spawn_enemies() -> void:
	for e in Game.INIT_ENEMIES:
		var sp = Game.find_open(e.x, e.y)
		if sp == null: sp = Vector2(clampf(e.x, 0.8, Game.MAP_COLS - 0.8),
									clampf(e.y, 0.8, Game.MAP_ROWS - 0.8))
		var tank := TankScene.instantiate() as Tank
		tank.faction = Game.ENEMY
		tank.entity_id = Game.next_id
		Game.next_id += 1
		tank.gx = sp.x
		tank.gy = sp.y
		tank.consumes_supplies = false
		tank.accepts_resupply = false
		tank.heading = Vector2(e.hx, e.hy)
		entities.add_child(tank)

func _spawn_starting_depot() -> void:
	var depot := SupplyDepotScene.instantiate() as SupplyDepot
	var start_pos: Vector2i = Game.starting_depot_grid_pos()
	depot.grid_col = start_pos.x
	depot.grid_row = start_pos.y
	depot.faction = Game.PLAYER
	depot.entity_id = Game.next_id
	Game.next_id += 1
	entities.add_child(depot)
	Game.structure_placed.emit(depot)
	# Center camera on the depot
	Game.cam = Vector2(depot.grid_col + depot.grid_w * 0.5, depot.grid_row + depot.grid_h * 0.5)

# ═══════════════════════════════════════════════════════════════════════════════
#  UI REFRESH
# ═══════════════════════════════════════════════════════════════════════════════
func _refresh_ui() -> void:
	hud.set_unit_catalog_supply(_player_supply_total())
	hud.set_aerial_units_active(_player_has_completed_airport())
	hud.set_tank_queue_status(_tank_build_queue, _tank_build_progress(), _tank_build_waiting_spawn, _tank_build_paused)
	hud.set_mortar_queue_status(_mortar_build_queue, _mortar_build_progress(), _mortar_build_waiting_spawn, _mortar_build_paused)
	var ui_sig := _ui_signature()
	if ui_sig == _last_ui_sig:
		return
	_last_ui_sig = ui_sig
	var su := Game.get_selected_units()
	if not su.is_empty():
		hud.show_units(su); return
	var ss = Game.selected_structure
	if ss != null and is_instance_valid(ss):
		hud.show_struct(ss); return
	if Game.build_mode != "": return
	hud.reset_selection(); hud.reset_unit_panel()

func _player_has_completed_airport() -> bool:
	for s_node in Game.get_structures():
		var airport: Airport = s_node as Airport
		if airport == null or airport.faction != Game.PLAYER:
			continue
		if not airport.is_under_construction():
			return true
	return false

func _super_tank_cheat_applies(u: Unit) -> bool:
	return Game.cheat_super_tanks and u is Tank and not (u is MortarSquad) and u.faction == Game.PLAYER

func _super_speed_cheat_applies(u: Unit) -> bool:
	return Game.cheat_super_tanks and u.faction == Game.PLAYER and u.movable

func _instant_unit_production_active() -> bool:
	return Game.cheat_super_tanks

func _effective_tank_build_time() -> float:
	return 0.0 if _instant_unit_production_active() else TANK_BUILD_TIME

func _effective_mortar_build_time() -> float:
	return 0.0 if _instant_unit_production_active() else MORTAR_BUILD_TIME

func _flush_instant_tank_production() -> void:
	if not _instant_unit_production_active() or _tank_build_queue <= 0:
		return
	_tank_build_paused = false
	var safety: int = maxi(_tank_build_queue * 2 + 2, 8)
	while _tank_build_queue > 0 and safety > 0:
		safety -= 1
		if not _tank_build_active:
			if not _start_next_tank_build():
				_tank_build_waiting_supply = true
				_tank_build_waiting_spawn = false
				_tank_build_time_left = 0.0
				break
		_tank_build_time_left = 0.0
		var spawn_ready: Dictionary = _find_spawn_info(Game.TANK_COL_R)
		if spawn_ready.is_empty():
			_tank_build_waiting_spawn = true
			_tank_build_waiting_supply = false
			break
		_tank_build_waiting_spawn = false
		_spawn_player_tank(spawn_ready["spawn"], spawn_ready["depot"])
		_tank_build_queue -= 1
		_tank_build_active = false
	if _tank_build_queue <= 0:
		_tank_build_time_left = 0.0
		_tank_build_active = false
		_tank_build_waiting_spawn = false
		_tank_build_waiting_supply = false

func _flush_instant_mortar_production() -> void:
	if not _instant_unit_production_active() or _mortar_build_queue <= 0:
		return
	_mortar_build_paused = false
	var safety: int = maxi(_mortar_build_queue * 2 + 2, 8)
	while _mortar_build_queue > 0 and safety > 0:
		safety -= 1
		if not _mortar_build_active:
			if not _start_next_mortar_build():
				_mortar_build_waiting_supply = true
				_mortar_build_waiting_spawn = false
				_mortar_build_time_left = 0.0
				break
		_mortar_build_time_left = 0.0
		var spawn_ready: Dictionary = _find_spawn_info(Game.TRUCK_COL_R)
		if spawn_ready.is_empty():
			_mortar_build_waiting_spawn = true
			_mortar_build_waiting_supply = false
			break
		_mortar_build_waiting_spawn = false
		_spawn_player_mortar(spawn_ready["spawn"], spawn_ready["depot"])
		_mortar_build_queue -= 1
		_mortar_build_active = false
	if _mortar_build_queue <= 0:
		_mortar_build_time_left = 0.0
		_mortar_build_active = false
		_mortar_build_waiting_spawn = false
		_mortar_build_waiting_supply = false

func _tank_build_progress() -> float:
	if _tank_build_queue <= 0 or not _tank_build_active:
		return 0.0
	var build_time: float = _effective_tank_build_time()
	if build_time <= 0.0:
		return 1.0
	return 1.0 - clampf(_tank_build_time_left / build_time, 0.0, 1.0)

func _mortar_build_progress() -> float:
	if _mortar_build_queue <= 0 or not _mortar_build_active:
		return 0.0
	var build_time: float = _effective_mortar_build_time()
	if build_time <= 0.0:
		return 1.0
	return 1.0 - clampf(_mortar_build_time_left / build_time, 0.0, 1.0)

func _ui_signature() -> String:
	if Game.build_mode != "":
		return "build:%s" % Game.build_mode
	var su := Game.get_selected_units()
	if not su.is_empty():
		if su.size() == 1:
			var u: Unit = su[0] as Unit
			if u != null and is_instance_valid(u):
				return "u:%d:%0.1f:%0.1f:%0.1f:%0.1f" % [
					u.get_instance_id(),
					u.hp,
					u.max_hp,
					u.supplies,
					u.max_supplies,
				]
		var ids: Array[String] = []
		var th := 0.0
		var tmh := 0.0
		var ts := 0.0
		var tms := 0.0
		for node in su:
			var unit: Unit = node as Unit
			if unit == null or not is_instance_valid(unit):
				continue
			ids.append(str(unit.get_instance_id()))
			th += unit.hp
			tmh += unit.max_hp
			ts += unit.supplies
			tms += unit.max_supplies
		return "um:%s:%0.1f:%0.1f:%0.1f:%0.1f" % [",".join(ids), th, tmh, ts, tms]
	var ss = Game.selected_structure
	if ss != null and is_instance_valid(ss):
		if ss is TankPlant:
			return "tp:%d:%s:%d:%0.3f" % [
				ss.get_instance_id(),
				ss.building,
				ss.produced,
				ss.get_production_progress(),
			]
		if ss is SupplyDepot:
			return "sd:%d:%0.1f:%0.1f" % [ss.get_instance_id(), ss.stored, ss.max_stored]
		if ss is Airport:
			var airport: Airport = ss as Airport
			if airport != null:
				return "ap:%d:%s:%0.1f:%0.1f:%0.1f:%0.1f" % [
					ss.get_instance_id(),
					airport.completed,
					airport.hp,
					airport.build_supplied_total,
					airport.build_supply_buffer,
					airport.build_supply_consumed,
				]
		return "st:%d" % ss.get_instance_id()
	return "idle"
