extends Node2D
## Main scene – input handling, camera, game loop.
## Uses Godot input actions, signals, groups, and node-based entities.

const TankScene := preload("res://scenes/tank.tscn")
const TruckScene := preload("res://scenes/truck.tscn")
const TankPlantScene := preload("res://scenes/tank_plant.tscn")
const SupplyDepotScene := preload("res://scenes/supply_depot.tscn")

@onready var cam2d: Camera2D = $Camera2D
@onready var entities: Node2D = $Entities
@onready var overlay: Overlay = $Overlay
@onready var hud = $UILayer/HUD

func _ready() -> void:
	Game.camera = cam2d
	get_tree().root.size_changed.connect(_on_resize)
	_on_resize()
	_spawn_enemies()
	_spawn_starting_depot()
	hud.build_requested.connect(toggle_build)
	hud.train_tank_requested.connect(_on_train_tank)
	hud.sync_build_buttons()
	hud.reset_selection()
	hud.reset_unit_panel()

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
	cam2d.force_update_scroll()
	if Game.ptr_in:
		Game.hover_tile = Game.tile_at(Game.ptr_scr.x, Game.ptr_scr.y)
	# Tank production handled by Timer nodes on TankPlant instances
	_update_enemy_ai()
	_update_units(dt)
	_resolve_collisions()
	_update_combat(dt)
	_remove_dead()
	_update_fog()
	_refresh_ui()

# ═══════════════════════════════════════════════════════════════════════════════
#  INPUT  (mouse events only — keyboard panning uses Godot input actions)
# ═══════════════════════════════════════════════════════════════════════════════
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		Game.ptr_scr = ev.position
		Game.ptr_in = true
		Game.hover_tile = Game.tile_at(ev.position.x, ev.position.y)
		if Game.drag_on:
			Game.drag_cur = ev.position
			Game.drag_box = Game.drag_start.distance_to(ev.position) >= Game.DRAG_THRESH

	elif ev is InputEventMouseButton:
		Game.ptr_scr = ev.position
		Game.ptr_in = true
		Game.hover_tile = Game.tile_at(ev.position.x, ev.position.y)
		if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
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
	# Grid positions of viewport corners when camera is at grid (0, 0)
	var c := [
		Game.world_to_grid(-hvp.x + off.x, -hvp.y + off.y),
		Game.world_to_grid( hvp.x + off.x, -hvp.y + off.y),
		Game.world_to_grid( hvp.x + off.x,  hvp.y + off.y),
		Game.world_to_grid(-hvp.x + off.x,  hvp.y + off.y),
	]
	var mnx := minf(minf(c[0].x, c[1].x), minf(c[2].x, c[3].x))
	var mxx := maxf(maxf(c[0].x, c[1].x), maxf(c[2].x, c[3].x))
	var mny := minf(minf(c[0].y, c[1].y), minf(c[2].y, c[3].y))
	var mxy := maxf(maxf(c[0].y, c[1].y), maxf(c[2].y, c[3].y))
	var lo_x := -mnx; var hi_x := Game.MAP_COLS - mxx
	var lo_y := -mny; var hi_y := Game.MAP_ROWS - mxy
	Game.cam.x = clampf(Game.cam.x, lo_x, hi_x) if lo_x <= hi_x else Game.MAP_COLS * 0.5
	Game.cam.y = clampf(Game.cam.y, lo_y, hi_y) if lo_y <= hi_y else Game.MAP_ROWS * 0.5

# ═══════════════════════════════════════════════════════════════════════════════
#  BUILD
# ═══════════════════════════════════════════════════════════════════════════════
func toggle_build(btype: String) -> void:
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
			hud.set_sel_detail(d.label + " selected. Hover the field to preview a " +
				str(d.w) + "x" + str(d.h) + " footprint, then click to deploy it.")
			hud.reset_unit_panel()
			hud.set_status("Placement mode active. Choose an open " +
				str(d.w) + "x" + str(d.h) + " area for the " + d.label + ".")
	hud.sync_build_buttons()

func _attempt_place(c: int, r: int) -> void:
	var d := Game.bldg_def(Game.build_mode)
	if d.is_empty(): return
	if not Game.fp_valid(c, r, d.w, d.h):
		hud.set_status("That footprint is blocked or off the map."); return
	var structure: Structure
	if Game.build_mode == Game.T_PLANT:
		structure = TankPlantScene.instantiate()
	else:
		structure = SupplyDepotScene.instantiate()
	structure.grid_col = c
	structure.grid_row = r
	structure.faction = Game.PLAYER
	structure.entity_id = Game.next_id
	Game.next_id += 1
	entities.add_child(structure)
	# Connect signals after the node enters the tree
	if structure is TankPlant:
		structure.tank_produced.connect(_on_tank_produced)
	Game.selected_structure = structure; Game.selected_units.clear()
	Game.build_mode = ""; Game.hover_tile = Vector2i(-1, -1)
	hud.sync_build_buttons()
	hud.set_status(
		"Tank Plant deployed. Click Build Tank to start production." if structure is TankPlant
		else "Supply Depot deployed with 2000 stored supplies.")
	Game.structure_placed.emit(structure)

func _on_tank_produced(plant: TankPlant) -> void:
	var sp = Game.find_open(plant.grid_col + plant.grid_w + 0.85, plant.grid_row + plant.grid_h + 0.35)
	var tank := TankScene.instantiate() as Tank
	tank.faction = Game.PLAYER
	tank.entity_id = Game.next_id
	Game.next_id += 1
	tank.gx = clampf(plant.grid_col + plant.grid_w - 0.2, 0.8, Game.MAP_COLS - 0.8)
	tank.gy = clampf(plant.grid_row + plant.grid_h - 0.18, 0.8, Game.MAP_ROWS - 0.8)
	tank.destination = sp
	tank.supplies = 100.0
	tank.max_supplies = 100.0
	tank.speed = 0.82 + randf() * 0.16
	tank.heading = Vector2(1.0, 0.0)
	entities.add_child(tank)
	Game.unit_spawned.emit(tank)
	hud.set_status("Tank produced from Plant #" + str(plant.entity_id) + ".")

func _on_train_tank() -> void:
	const RESOURCE_NAME := "Supply"
	const DEPOT_NAME := "Supply Depot"
	var ss = Game.selected_structure
	if ss == null or not is_instance_valid(ss) or not (ss is TankPlant):
		hud.set_status("Select a Tank Plant first.")
		return
	if ss.building:
		hud.set_status("Tank Plant is already building.")
		return
	var cost := 500.0  # total build cost; tank spawns fully supplied
	# Centre of the Tank Plant in grid coords
	var px: float = ss.grid_col + ss.grid_w * 0.5
	var py: float = ss.grid_row + ss.grid_h * 0.5
	# Find a nearby depot with enough supply
	var depot: SupplyDepot = null
	var any_nearby := false
	for s: Structure in Game.get_structures():
		if not (s is SupplyDepot) or s.faction != Game.PLAYER: continue
		var dx := (s.grid_col + s.grid_w * 0.5) - px
		var dy := (s.grid_row + s.grid_h * 0.5) - py
		if sqrt(dx * dx + dy * dy) > Game.DEPOT_SUPPLY_R: continue
		any_nearby = true
		if s.stored >= cost:
			depot = s
			break
	if depot == null:
		if not any_nearby:
			hud.show_prod_error("No " + DEPOT_NAME + " nearby.")
		else:
			hud.show_prod_error("Insufficient " + RESOURCE_NAME + ".")
		return
	hud.clear_prod_error()
	depot.stored -= cost
	ss.queue_tank()
	hud.set_status("Tank production started at Plant #" + str(ss.entity_id) + ". " + str(roundi(cost)) + " " + RESOURCE_NAME + " deducted.")

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
	if t == Vector2i(-1, -1):
		hud.set_status("Move order is outside the battlefield."); return
	var wt := Game.screen_to_grid(pos)
	var tgt = Game.find_open(wt.x, wt.y)
	if tgt == null:
		hud.set_status("That move order is blocked."); return
	for i in sel.size():
		var off := _formation_off(i, sel.size())
		var rt = Game.find_open(tgt.x + off.x, tgt.y + off.y)
		if rt == null: rt = tgt
		sel[i].destination = rt
		if sel[i] is Truck:
			sel[i].follow_target = null
	hud.set_status(
		sel[0].label + " ordered to move." if sel.size() == 1
		else str(sel.size()) + " units ordered to move.")

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
	if tu == null and t == Vector2i(-1, -1):
		hud.set_status("Supply order is outside the battlefield."); return
	var sp = Game.find_open(depot.grid_col + depot.grid_w + 0.78,
		depot.grid_row + depot.grid_h * 0.5 + ((randi() % 3) - 1) * 0.36)
	if sp == null:
		hud.set_status("The Supply Depot exit is blocked."); return
	var tgt_pt = null; var tgt_unit: Node2D = null; var tgt_lbl := ""
	if tu != null and tu.movable and tu.faction == Game.PLAYER:
		tgt_unit = tu
		tgt_pt = Vector2(tu.gx, tu.gy)
		tgt_lbl = tu.label + " #" + str(tu.entity_id)
	else:
		var wt := Game.screen_to_grid(pos)
		tgt_pt = Game.find_open(wt.x, wt.y)
	if tgt_pt == null:
		hud.set_status("That supply route is blocked."); return
	depot.stored -= Game.TRUCK_CARGO
	var truck := TruckScene.instantiate() as Truck
	truck.faction = Game.PLAYER
	truck.entity_id = Game.next_id
	Game.next_id += 1
	truck.gx = sp.x
	truck.gy = sp.y
	truck.destination = tgt_pt
	truck.follow_target = tgt_unit
	truck.supplies = Game.TRUCK_CARGO
	truck.max_supplies = Game.TRUCK_CARGO
	truck.speed = Game.TRUCK_SPEED
	truck.heading = Vector2(1.0, 0.0)
	entities.add_child(truck)
	Game.unit_spawned.emit(truck)
	hud.set_status(
		"Supply truck dispatched to " + tgt_lbl + "." if tgt_unit != null
		else "Supply truck dispatched with 500 supplies.")

# ═══════════════════════════════════════════════════════════════════════════════
#  UNIT MOVEMENT
# ═══════════════════════════════════════════════════════════════════════════════
func _update_units(dt: float) -> void:
	for u: Unit in Game.get_units():
		if u.consumes_supplies:
			u.supplies = maxf(0.0, u.supplies - Game.SUP_IDLE_RATE * dt)
		if u.consumes_supplies and u.supplies <= 0:
			u.supplies = 0.0; continue
		# truck follow target
		var active_tu: Unit = null
		if u is Truck and u.follow_target != null:
			if is_instance_valid(u.follow_target):
				active_tu = u.follow_target as Unit
				var fd := Vector2(u.gx - active_tu.gx, u.gy - active_tu.gy)
				var fl := fd.length()
				var off := u.get_collision_radius() + active_tu.get_collision_radius() + 0.18
				var n := fd / fl if fl > 0.001 else Vector2(1, 0)
				u.destination = Vector2(active_tu.gx + n.x * off, active_tu.gy + n.y * off)
			else:
				u.follow_target = null
		if u.destination == null:
			if u is Truck: _truck_aura(u, dt)
			continue
		var dx: float = u.destination.x - u.gx
		var dy: float = u.destination.y - u.gy
		var dist := sqrt(dx * dx + dy * dy)
		var arr_r := Game.TRUCK_ARRIVE_R if u is Truck else 0.06
		if dist < arr_r:
			if u is Truck:
				if active_tu == null:
					u.destination = null; u.follow_target = null
			else:
				u.destination = null
		else:
			u.heading = Vector2(dx / dist, dy / dist)
			var max_by_sup: float = dist if not u.consumes_supplies else u.supplies / Game.SUP_PER_UNIT
			var hp_ratio: float = u.hp / u.max_hp if u.max_hp > 0 else 1.0
			var travel := minf(dist, minf(u.speed * hp_ratio * dt, max_by_sup))
			if travel <= 0:
				if u.consumes_supplies: u.supplies = 0.0
				continue
			u.gx += u.heading.x * travel; u.gy += u.heading.y * travel
			if u.consumes_supplies:
				u.supplies = maxf(0.0, u.supplies - travel * Game.SUP_PER_UNIT)
		if u is Truck: _truck_aura(u, dt)

func _truck_aura(truck: Truck, dt: float) -> void:
	if truck.supplies <= 0: truck.supplies = 0.0; return
	var recip: Array = []
	for u: Unit in Game.get_units():
		if u == truck or u.faction != truck.faction: continue
		if not u.accepts_resupply: continue
		if u.max_supplies <= u.supplies: continue
		var d := sqrt((u.gx - truck.gx) ** 2 + (u.gy - truck.gy) ** 2)
		if d <= Game.TRUCK_RESUPPLY_R: recip.append(u)
	if recip.is_empty(): return
	var remain := minf(truck.supplies, Game.TRUCK_RESUPPLY_S * dt)
	if remain <= 0: return
	var pool: Array = recip.duplicate()
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
	if Game.struct_at(int(u.gx), int(u.gy)) == null: return
	var fb = Game.find_open(u.gx, u.gy)
	if fb != null: u.gx = fb.x; u.gy = fb.y

func _sep(a: Unit, b: Unit) -> void:
	var min_d := a.get_collision_radius() + b.get_collision_radius() + Game.COL_PAD
	var dx: float = b.gx - a.gx; var dy: float = b.gy - a.gy
	var d := sqrt(dx * dx + dy * dy)
	if d >= min_d: return
	if d < 0.0001:
		var ang := fmod(float(a.get_instance_id() * 92821 + b.get_instance_id() * 68917), 360.0) * PI / 180.0
		dx = cos(ang); dy = sin(ang); d = 0.0
	else:
		dx /= d; dy /= d
	var s := (min_d - d) * 0.5
	a.gx -= dx * s; a.gy -= dy * s
	b.gx += dx * s; b.gy += dy * s
	_clamp_unit(a); _clamp_unit(b)

# ═══════════════════════════════════════════════════════════════════════════════
#  COMBAT
# ═══════════════════════════════════════════════════════════════════════════════
func _update_combat(_dt: float) -> void:
	for u: Unit in Game.get_units():
		if not (u is Tank) or not u.can_attack or u.hp <= 0: continue
		var tgt = _nearest_hostile(u, u.attack_range)
		if tgt == null: continue
		var dx: float = tgt.gx - u.gx; var dy: float = tgt.gy - u.gy
		var d := sqrt(dx * dx + dy * dy)
		if d <= 0.001: continue
		u.heading = Vector2(dx / d, dy / d)
		if not u.attack_timer.is_stopped(): continue
		if u.consumes_supplies and u.supplies < Game.SUP_PER_SHOT: continue
		var atk_hp_ratio: float = u.hp / u.max_hp if u.max_hp > 0 else 1.0
		u.attack_timer.start(Game.ATK_CD / maxf(atk_hp_ratio, 0.1))
		if u.consumes_supplies:
			u.supplies = maxf(0.0, u.supplies - Game.SUP_PER_SHOT)
		tgt.hp = maxf(0.0, tgt.hp - u.attack_damage)
		tgt.status_display_until = Game.elapsed + Game.DMG_BAR_S
		overlay.add_burst({
			"faction": u.faction,
			"sx": u.gx + u.heading.x * 0.34, "sy": u.gy + u.heading.y * 0.34,
			"ex": tgt.gx, "ey": tgt.gy,
			"ttl": Game.TRACER_TTL, "max_ttl": Game.TRACER_TTL,
		})

func _nearest_hostile(u: Unit, rng: float) -> Unit:
	var best: Unit = null; var best_d := rng
	for c: Unit in Game.get_units():
		if c == u or c.hp <= 0 or c.faction == u.faction: continue
		var d := sqrt((c.gx - u.gx) ** 2 + (c.gy - u.gy) ** 2)
		if d <= rng and d < best_d: best_d = d; best = c
	return best

func _remove_dead() -> void:
	var enemy_cnt := 0
	var dead: Array = []
	for u: Unit in Game.get_units():
		if u.hp <= 0:
			dead.append(u)
			if u.faction == Game.ENEMY: enemy_cnt += 1
	if dead.is_empty(): return
	for u in dead:
		Game.selected_units.erase(u)
		# Clean up truck follow targets pointing to dead unit
		for other: Unit in Game.get_units():
			if other is Truck and other.follow_target == u:
				other.follow_target = null; other.destination = null
		Game.unit_died.emit(u)
		u.died.emit()
		u.queue_free()
	if enemy_cnt > 0:
		hud.set_status(
			"Enemy tank destroyed." if enemy_cnt == 1
			else str(enemy_cnt) + " enemy tanks destroyed.")

# ═══════════════════════════════════════════════════════════════════════════════
#  FOG
# ═══════════════════════════════════════════════════════════════════════════════
func _update_fog() -> void:
	Game.fog_reset_vis()
	var has_friendly := false
	for s: Structure in Game.get_structures():
		if s.faction == Game.PLAYER:
			has_friendly = true
			_reveal(s.grid_col + s.grid_w * 0.5, s.grid_row + s.grid_h * 0.5, Game.VIS_STRUCT)
	for u: Unit in Game.get_units():
		if u.faction == Game.PLAYER:
			has_friendly = true
			_reveal(u.gx, u.gy, u.vision_radius)
func _reveal(cx: float, cy: float, rad: float) -> void:
	var mnc := clampi(int(cx - rad), 0, Game.MAP_COLS - 1)
	var mxc := clampi(ceili(cx + rad), 0, Game.MAP_COLS - 1)
	var mnr := clampi(int(cy - rad), 0, Game.MAP_ROWS - 1)
	var mxr := clampi(ceili(cy + rad), 0, Game.MAP_ROWS - 1)
	var r2 := rad * rad
	for r in range(mnr, mxr + 1):
		for c in range(mnc, mxc + 1):
			var dx := c + 0.5 - cx; var dy := r + 0.5 - cy
			if dx * dx + dy * dy <= r2:
				Game.fog_set(c, r)

# ═══════════════════════════════════════════════════════════════════════════════
#  ENEMY AI
# ═══════════════════════════════════════════════════════════════════════════════
func _update_enemy_ai() -> void:
	for u: Unit in Game.get_units():
		if u.faction != Game.ENEMY or not (u is Tank) or u.hp <= 0: continue
		var tgt := _nearest_hostile(u, u.attack_range)
		if tgt != null:
			u.destination = Vector2(tgt.gx, tgt.gy)
		else:
			# Seek nearest player unit within a larger detection range
			var seek := _nearest_hostile(u, Game.ENEMY_SEEK_R)
			if seek != null:
				u.destination = Vector2(seek.gx, seek.gy)
			else:
				u.destination = null

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
	depot.grid_col = 10
	depot.grid_row = 48
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
	var su := Game.get_selected_units()
	if not su.is_empty():
		hud.show_units(su); return
	var ss = Game.selected_structure
	if ss != null and is_instance_valid(ss):
		hud.show_struct(ss); return
	if Game.build_mode != "": return
	hud.reset_selection(); hud.reset_unit_panel()
