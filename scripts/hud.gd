extends Control
## HUD overlay – build menu, selection info, status bar, unit status panel.
## Communicates with Main via the build_requested signal (no tree-walking).

# ── Signals (connected by Main) ──────────────────────────────────────────────
signal build_requested(btype: String)
signal train_tank_requested

# ── element refs (scene-unique nodes from hud.tscn) ────────────────────────
@onready var brand_panel: PanelContainer = %BrandPanel
@onready var build_panel: PanelContainer = %BuildPanel
@onready var sel_panel: PanelContainer = %SelPanel
@onready var note_panel: PanelContainer = %NotePanel
@onready var status_bar: PanelContainer = %StatusBar
@onready var unit_panel: PanelContainer = %UnitPanel
@onready var btn_plant: Button = %BtnPlant
@onready var btn_depot: Button = %BtnDepot
@onready var lbl_hint: Label = %LblHint
@onready var lbl_sel_pill: Label = %LblSelPill
@onready var lbl_sel_detail: Label = %LblSelDetail
@onready var lbl_status: Label = %LblStatus
@onready var lbl_unit_pill: Label = %LblUnitPill
@onready var lbl_unit_name: Label = %LblUnitName
@onready var lbl_unit_copy: Label = %LblUnitCopy
@onready var hp_row: VBoxContainer = %HpRow
@onready var hp_label: Label = %HpLabel
@onready var hp_value: Label = %HpValue
@onready var hp_bar: ProgressBar = %HpBar
@onready var sup_row: VBoxContainer = %SupRow
@onready var sup_label: Label = %SupLabel
@onready var sup_value: Label = %SupValue
@onready var sup_bar: ProgressBar = %SupBar

# ── production panel (built in code) ─────────────────────────────────────────
var prod_panel: PanelContainer
var btn_train_tank: Button
var prod_progress: ProgressBar
var prod_label: Label
var prod_error: Label

# ── colours ──────────────────────────────────────────────────────────────────
const C_PANEL   := Color(0.204, 0.137, 0.075, 0.80)
const C_LINE    := Color(1.0, 0.961, 0.851, 0.18)
const C_TEXT    := Color(0.973, 0.945, 0.871)
const C_MUTED   := Color(0.835, 0.780, 0.631)
const C_ACCENT  := Color(1.0, 0.855, 0.447)
const C_BTN_BG  := Color(0.373, 0.282, 0.180, 0.55)
const C_BTN_BD  := Color(1.0, 0.855, 0.447, 0.45)
const C_HP_A    := Color(0.455, 0.776, 0.427)
const C_HP_B    := Color(0.831, 0.851, 0.384)
const C_SUP_A   := Color(0.839, 0.663, 0.259)
const C_SUP_B   := Color(0.953, 0.867, 0.388)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# apply styles to scene nodes
	brand_panel.add_theme_stylebox_override("panel", _panel_style(22))
	build_panel.add_theme_stylebox_override("panel", _panel_style())
	sel_panel.add_theme_stylebox_override("panel", _panel_style())
	note_panel.add_theme_stylebox_override("panel", _panel_style())
	status_bar.add_theme_stylebox_override("panel", _panel_style(20))
	unit_panel.add_theme_stylebox_override("panel", _panel_style(22))
	# button styles
	for btn in [btn_plant, btn_depot]:
		btn.add_theme_stylebox_override("normal", _btn_style())
		btn.add_theme_stylebox_override("hover", _btn_style())
		btn.add_theme_stylebox_override("pressed", _btn_style_armed())
		btn.add_theme_stylebox_override("focus", _btn_style())
	btn_plant.pressed.connect(_on_plant)
	btn_depot.pressed.connect(_on_depot)
	# progress bar styles
	hp_bar.add_theme_stylebox_override("background", _bar_bg_style())
	hp_bar.add_theme_stylebox_override("fill", _bar_style(C_HP_A, C_HP_B))
	sup_bar.add_theme_stylebox_override("background", _bar_bg_style())
	sup_bar.add_theme_stylebox_override("fill", _bar_style(C_SUP_A, C_SUP_B))
	_create_prod_panel()

func _create_prod_panel() -> void:
	prod_panel = PanelContainer.new()
	prod_panel.add_theme_stylebox_override("panel", _panel_style(16))
	prod_panel.layout_mode = 1
	prod_panel.anchor_left = 0.5; prod_panel.anchor_right = 0.5
	prod_panel.anchor_top = 1.0; prod_panel.anchor_bottom = 1.0
	prod_panel.offset_left = -100; prod_panel.offset_right = 100
	prod_panel.offset_top = -148; prod_panel.offset_bottom = -118
	prod_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var vbox_outer := VBoxContainer.new()
	vbox_outer.add_theme_constant_override("separation", 6)
	prod_panel.add_child(vbox_outer)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox_outer.add_child(hbox)
	# tank icon button
	btn_train_tank = Button.new()
	btn_train_tank.text = "  Build Tank (500)"
	btn_train_tank.custom_minimum_size = Vector2(140, 0)
	btn_train_tank.focus_mode = Control.FOCUS_NONE
	btn_train_tank.add_theme_stylebox_override("normal", _btn_style())
	btn_train_tank.add_theme_stylebox_override("hover", _btn_style())
	btn_train_tank.add_theme_stylebox_override("pressed", _btn_style_armed())
	btn_train_tank.add_theme_stylebox_override("focus", _btn_style())
	btn_train_tank.add_theme_color_override("font_color", C_TEXT)
	btn_train_tank.add_theme_font_size_override("font_size", 14)
	btn_train_tank.pressed.connect(func(): train_tank_requested.emit())
	hbox.add_child(btn_train_tank)
	# progress bar
	var bar_vbox := VBoxContainer.new()
	bar_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(bar_vbox)
	prod_label = Label.new()
	prod_label.text = "Idle"
	prod_label.add_theme_color_override("font_color", C_ACCENT)
	prod_label.add_theme_font_size_override("font_size", 11)
	bar_vbox.add_child(prod_label)
	prod_progress = ProgressBar.new()
	prod_progress.max_value = 1.0
	prod_progress.show_percentage = false
	prod_progress.custom_minimum_size = Vector2(80, 12)
	prod_progress.add_theme_stylebox_override("background", _bar_bg_style())
	prod_progress.add_theme_stylebox_override("fill", _bar_style(C_ACCENT, C_SUP_B))
	bar_vbox.add_child(prod_progress)
	# error message label
	prod_error = Label.new()
	prod_error.text = ""
	prod_error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	prod_error.add_theme_font_size_override("font_size", 12)
	prod_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prod_error.visible = false
	vbox_outer.add_child(prod_error)
	add_child(prod_panel)
	prod_panel.visible = false

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	_draw_field_hud()
	_draw_sel_rect()

# ── screen-space drawing (CanvasLayer, not affected by Camera2D) ────────────
func _draw_field_hud() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(26, vp.y - 54, 780, 28), Color(0.047, 0.071, 0.047, 0.34))
	draw_rect(Rect2(26, vp.y - 54, 780, 28), Color(1, 0.914, 0.663, 0.25), false, 1)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(40, vp.y - 36),
		"Combat: player tanks auto-fire on enemy tanks in range. Selected trucks show a resupply radius.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.957, 0.831, 0.506))

func _draw_sel_rect() -> void:
	if not Game.drag_on or not Game.drag_box: return
	var r := Rect2(
		Vector2(minf(Game.drag_start.x, Game.drag_cur.x), minf(Game.drag_start.y, Game.drag_cur.y)),
		Vector2(absf(Game.drag_cur.x - Game.drag_start.x), absf(Game.drag_cur.y - Game.drag_start.y)))
	draw_rect(r, Color(1, 0.839, 0.392, 0.12))
	_hud_dashed_rect(r, Color(1, 0.898, 0.561, 0.92), 7, 5, 1.5)

func _hud_dashed_rect(rect: Rect2, col: Color, dash: float, gap: float, w: float) -> void:
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	var pts := [tl, tr, br, bl, tl]
	for i in pts.size() - 1:
		_hud_dashed_seg(pts[i], pts[i + 1], col, dash, gap, w)

func _hud_dashed_seg(a: Vector2, b: Vector2, col: Color, dash: float, gap: float, w: float) -> void:
	var dir := b - a
	var total := dir.length()
	if total < 0.01: return
	dir /= total
	var p := 0.0
	var drawing := true
	while p < total:
		var seg := dash if drawing else gap
		var end := minf(p + seg, total)
		if drawing:
			draw_line(a + dir * p, a + dir * end, col, w)
		p = end
		drawing = not drawing

# ═══════════════════════════════════════════════════════════════════════════════
#  STYLE FACTORIES
# ═══════════════════════════════════════════════════════════════════════════════
func _panel_style(radius: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_PANEL
	s.border_color = C_LINE
	for side in ["left", "top", "right", "bottom"]:
		s.set("border_width_" + side, 1)
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left = 18; s.content_margin_top = 16
	s.content_margin_right = 18; s.content_margin_bottom = 16
	return s

func _btn_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_BTN_BG
	s.border_color = C_BTN_BD
	for side in ["left", "top", "right", "bottom"]:
		s.set("border_width_" + side, 1)
	s.corner_radius_top_left = 18; s.corner_radius_top_right = 18
	s.corner_radius_bottom_left = 18; s.corner_radius_bottom_right = 18
	s.content_margin_left = 16; s.content_margin_top = 12
	s.content_margin_right = 16; s.content_margin_bottom = 12
	return s

func _btn_style_armed() -> StyleBoxFlat:
	var s := _btn_style()
	s.border_color = Color(1, 0.882, 0.573, 0.95)
	s.shadow_color = Color(1, 0.882, 0.573, 0.5)
	s.shadow_size = 1
	return s

func _bar_style(col_a: Color, _col_b: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col_a
	s.corner_radius_top_left = 8; s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
	return s

func _bar_bg_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.051, 0.063, 0.075, 0.78)
	s.border_color = Color(1, 0.906, 0.659, 0.22)
	for side in ["left", "top", "right", "bottom"]:
		s.set("border_width_" + side, 1)
	s.corner_radius_top_left = 8; s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
	return s

# ═══════════════════════════════════════════════════════════════════════════════
#  CALLBACKS  (emit signal instead of walking the scene tree)
# ═══════════════════════════════════════════════════════════════════════════════
func _on_plant() -> void:
	build_requested.emit(Game.T_PLANT)

func _on_depot() -> void:
	build_requested.emit(Game.T_DEPOT)

# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API (called from main.gd)
# ═══════════════════════════════════════════════════════════════════════════════
func set_status(msg: String) -> void:
	lbl_status.text = msg

func set_sel_pill(txt: String) -> void:
	lbl_sel_pill.text = txt

func set_sel_detail(txt: String) -> void:
	lbl_sel_detail.text = txt

func show_prod_error(msg: String) -> void:
	prod_error.text = msg
	prod_error.visible = true

func clear_prod_error() -> void:
	prod_error.text = ""
	prod_error.visible = false

func sync_build_buttons() -> void:
	var armed_plant: bool = Game.build_mode == Game.T_PLANT
	var armed_depot: bool = Game.build_mode == Game.T_DEPOT
	btn_plant.add_theme_stylebox_override("normal", _btn_style_armed() if armed_plant else _btn_style())
	btn_depot.add_theme_stylebox_override("normal", _btn_style_armed() if armed_depot else _btn_style())
	var d := Game.bldg_def(Game.build_mode)
	if not d.is_empty():
		lbl_hint.text = "Click an open " + str(d.w) + "x" + str(d.h) + " footprint on the map to place the " + d.label + "."
	else:
		lbl_hint.text = "Select a structure, then click an open spot on the map."

func reset_selection() -> void:
	lbl_sel_pill.text = "Nothing selected"
	lbl_sel_detail.text = "Choose a structure from the build menu, click a structure, or drag-select movable units to command them."
	prod_panel.visible = false

func reset_unit_panel() -> void:
	lbl_unit_pill.text = "No selection"
	lbl_unit_name.text = "Nothing selected"
	lbl_unit_copy.text = "Click a structure, click a movable unit, or drag across the battlefield to inspect what is selected."
	hp_row.visible = false
	sup_row.visible = false
	prod_panel.visible = false
	hp_value.text = "HP: --"
	sup_value.text = "Supplies: --"
	hp_bar.value = 0; sup_bar.value = 0

func show_struct(s: Node2D) -> void:
	if s is TankPlant:
		lbl_sel_pill.text = s.label
		lbl_sel_detail.text = "Click Build Tank to produce a tank. Units built: " + str(s.produced) + "."
		lbl_unit_pill.text = "Structure selected"
		lbl_unit_name.text = "Tank Plant #" + str(s.entity_id)
		lbl_unit_copy.text = "Production structure. Click the Build Tank button to queue a tank."
		var prog: float = s.get_production_progress()
		hp_row.visible = true
		hp_label.text = "Assembly Progress"
		hp_value.text = "Progress: " + str(roundi(prog * 100)) + "%"
		hp_bar.value = prog
		sup_row.visible = true
		sup_label.text = "Units Built"
		sup_value.text = "Built: " + str(s.produced)
		sup_bar.value = 1.0 if s.produced > 0 else 0.0
		# show production panel
		prod_panel.visible = true
		prod_progress.value = prog
		if s.building:
			prod_label.text = str(roundi(prog * 100)) + "%"
			btn_train_tank.add_theme_stylebox_override("normal", _btn_style_armed())
			prod_error.visible = false
		else:
			prod_label.text = "Idle"
			btn_train_tank.add_theme_stylebox_override("normal", _btn_style())
	elif s is SupplyDepot:
		prod_panel.visible = false
		var ratio: float = s.stored / float(s.max_stored) if s.max_stored > 0 else 0.0
		lbl_sel_pill.text = s.label
		lbl_sel_detail.text = "Non-movable storage structure. Right-click the map or a movable unit to dispatch a 500-supply truck. Supplies stored: " + str(roundi(s.stored)) + " / " + str(roundi(s.max_stored)) + "."
		lbl_unit_pill.text = "Depot selected"
		lbl_unit_name.text = "Supply Depot #" + str(s.entity_id)
		lbl_unit_copy.text = "Non-movable logistics structure. Right-click the map or a movable unit to dispatch a 500-supply truck."
		hp_row.visible = false
		sup_row.visible = true
		sup_label.text = "Stored Supplies"
		sup_value.text = "Supplies: " + str(roundi(s.stored)) + " / " + str(roundi(s.max_stored))
		sup_bar.value = ratio

func show_units(us: Array[Node2D]) -> void:
	prod_panel.visible = false
	if us.size() == 1:
		var u: Unit = us[0] as Unit
		var is_truck: bool = u is Truck
		var ul: String = "Supply Truck" if is_truck else "Tank"
		var sl: String = "Cargo Load" if is_truck else "Supplies"
		var sp: String = "Load: " if is_truck else "Supplies: "
		var uc: String = "Mobile logistics vehicle. Its supplies bar shows cargo only." if is_truck else "Armored vehicle. Supplies consumed as it moves. Auto-fires on enemies."
		lbl_sel_pill.text = ul + " #" + str(u.entity_id)
		lbl_sel_detail.text = "Movable unit selected. Right-click the map to move it."
		lbl_unit_pill.text = ul + " selected"
		lbl_unit_name.text = ul + " #" + str(u.entity_id)
		lbl_unit_copy.text = uc
		hp_row.visible = true
		hp_label.text = "Hull Integrity"
		hp_value.text = "HP: " + str(roundi(u.hp)) + " / " + str(roundi(u.max_hp))
		hp_bar.value = u.hp / u.max_hp if u.max_hp > 0 else 0.0
		sup_row.visible = true
		sup_label.text = sl
		sup_value.text = sp + str(roundi(u.supplies)) + " / " + str(roundi(u.max_supplies))
		sup_bar.value = u.supplies / u.max_supplies if u.max_supplies > 0 else 0.0
		return
	# multiple units
	var th := 0.0; var tmh := 0.0; var ts := 0.0; var tms := 0.0
	var tc := 0; var trc := 0
	for u_node in us:
		var u: Unit = u_node as Unit
		th += u.hp; tmh += u.max_hp; ts += u.supplies; tms += u.max_supplies
		if u is Tank: tc += 1
		elif u is Truck: trc += 1
	var label := str(us.size()) + " Units"
	if tc == us.size(): label = str(us.size()) + " Tanks"
	elif trc == us.size(): label = str(us.size()) + " Trucks"
	lbl_sel_pill.text = label
	lbl_sel_detail.text = "Movable units selected. Right-click to move the group."
	lbl_unit_pill.text = str(us.size()) + " selected"
	lbl_unit_name.text = label
	lbl_unit_copy.text = "Group status shown as combined totals."
	hp_row.visible = true
	hp_label.text = "Hull Integrity"
	hp_value.text = "HP: " + str(roundi(th)) + " / " + str(roundi(tmh))
	hp_bar.value = th / tmh if tmh > 0 else 0.0
	sup_row.visible = true
	sup_label.text = "Supplies"
	sup_value.text = "Supplies: " + str(roundi(ts)) + " / " + str(roundi(tms))
	sup_bar.value = ts / tms if tms > 0 else 0.0
