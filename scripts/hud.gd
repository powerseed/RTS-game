extends Control
## HUD overlay – build menu, selection info, status bar, unit status panel.
## Communicates with Main via the build_requested signal (no tree-walking).

# ── Signals (connected by Main) ──────────────────────────────────────────────
signal build_requested(btype: String)
signal train_tank_requested
signal unit_build_requested(unit_type: String, amount: int)
signal tank_queue_pause_requested
signal tank_queue_cancel_requested

const MiniMapScript := preload("res://scripts/minimap.gd")
const UnitIconScript := preload("res://scripts/unit_icon.gd")

# ── element refs (scene-unique nodes from hud.tscn) ────────────────────────
@onready var brand_panel: PanelContainer = %BrandPanel
@onready var build_panel: PanelContainer = %BuildPanel
@onready var sel_panel: PanelContainer = %SelPanel
@onready var note_panel: PanelContainer = %NotePanel
@onready var left_column: Control = $Left
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
var minimap_panel: PanelContainer
var minimap_view: MiniMap
var unit_catalog_panel: PanelContainer
var unit_catalog_supply_label: Label
var airport_icon_button: Button
var tank_count_input: SpinBox
var tank_count_line_edit: LineEdit
var tank_build_button: Button
var tank_pause_button: Button
var tank_cancel_button: Button
var tank_queue_bar: ProgressBar
var tank_queue_count_label: Label
var _tank_count_text_guard: bool = false

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
const C_PAUSE_BG := Color(0.867, 0.729, 0.255, 0.94)
const C_PAUSE_BD := Color(0.992, 0.914, 0.620, 0.96)
const C_PAUSE_TX := Color(0.212, 0.153, 0.082)
const C_CANCEL_BG := Color(0.757, 0.255, 0.212, 0.94)
const C_CANCEL_BD := Color(0.957, 0.675, 0.631, 0.96)
const C_CANCEL_TX := Color(0.992, 0.957, 0.929)
const UI_FONT_SCALE := 1.5
const MINIMAP_SCREEN_W := 0.18
const MINIMAP_GAP := 12.0
const MINIMAP_EDGE := 24.0
const MINIMAP_HEAD_H := 72.0
var _last_drag_sig := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_column.visible = false
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
	_create_unit_catalog_panel()
	_create_minimap_panel()
	_create_prod_panel()
	_layout_minimap_panel()
	unit_panel.offset_top = -150.0
	_scale_all_ui_fonts()
	queue_redraw()

func _scaled_font_size(base_size: int) -> int:
	return maxi(1, int(round(float(base_size) * UI_FONT_SCALE)))

func _scale_all_ui_fonts() -> void:
	_scale_control_font_recursive(self)
	if tank_queue_bar != null:
		tank_queue_bar.custom_minimum_size.y = 32.0
	if prod_progress != null:
		prod_progress.custom_minimum_size.y = 18.0

func _scale_control_font_recursive(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit or node is SpinBox:
		var control := node as Control
		var base_size := control.get_theme_font_size("font_size")
		if base_size > 0:
			control.add_theme_font_size_override("font_size", _scaled_font_size(base_size))
	for child in node.get_children():
		_scale_control_font_recursive(child)

func _create_unit_catalog_panel() -> void:
	unit_catalog_panel = PanelContainer.new()
	unit_catalog_panel.add_theme_stylebox_override("panel", _panel_style(20))
	unit_catalog_panel.layout_mode = 1
	unit_catalog_panel.anchor_left = 0.0
	unit_catalog_panel.anchor_top = 0.0
	unit_catalog_panel.anchor_right = 0.0
	unit_catalog_panel.anchor_bottom = 1.0
	unit_catalog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	unit_catalog_panel.add_child(root)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	root.add_child(head)
	var title := Label.new()
	title.text = "Unit Factory"
	title.add_theme_color_override("font_color", C_TEXT)
	title.add_theme_font_size_override("font_size", 18)
	head.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Build units directly from the supply network."
	subtitle.add_theme_color_override("font_color", C_MUTED)
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(subtitle)
	unit_catalog_supply_label = Label.new()
	unit_catalog_supply_label.text = "Supply Pool: 0"
	unit_catalog_supply_label.add_theme_color_override("font_color", C_ACCENT)
	unit_catalog_supply_label.add_theme_font_size_override("font_size", 13)
	head.add_child(unit_catalog_supply_label)
	root.add_child(_build_building_category())
	root.add_child(_build_unit_category(
		"Ground Vehicles",
		"Tracked and wheeled combat units.",
		true
	))
	root.add_child(_build_unit_category(
		"Ground Troops",
		"No units available yet.",
		false
	))
	root.add_child(_build_unit_category(
		"Aerial Units",
		"No units available yet.",
		false
	))
	add_child(unit_catalog_panel)

func _build_building_category() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(14))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Building"
	title.add_theme_color_override("font_color", C_TEXT)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)
	var body := Label.new()
	body.text = "Deployable structures and base infrastructure."
	body.add_theme_color_override("font_color", C_MUTED)
	body.add_theme_font_size_override("font_size", 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	vbox.add_child(_build_airport_row())
	return panel

func _build_unit_category(title_text: String, body_text: String, include_tank: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(14))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = title_text
	title.add_theme_color_override("font_color", C_TEXT)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.add_theme_color_override("font_color", C_MUTED)
	body.add_theme_font_size_override("font_size", 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	if include_tank:
		vbox.add_child(_build_tank_row())
	return panel

func _build_airport_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	airport_icon_button = Button.new()
	airport_icon_button.custom_minimum_size = Vector2(56, 56)
	airport_icon_button.focus_mode = Control.FOCUS_NONE
	airport_icon_button.text = ""
	airport_icon_button.add_theme_stylebox_override("normal", _icon_btn_style())
	airport_icon_button.add_theme_stylebox_override("hover", _icon_btn_style())
	airport_icon_button.add_theme_stylebox_override("pressed", _icon_btn_style_armed())
	airport_icon_button.add_theme_stylebox_override("focus", _icon_btn_style())
	airport_icon_button.pressed.connect(_on_build_airport_pressed)
	var icon_wrap := CenterContainer.new()
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	airport_icon_button.add_child(icon_wrap)
	var icon := UnitIconScript.new() as UnitIcon
	icon.unit_type = Game.T_AIRPORT
	icon.custom_minimum_size = Vector2(44, 44)
	icon_wrap.add_child(icon)
	row.add_child(airport_icon_button)
	var name := Label.new()
	name.text = "Airport"
	name.custom_minimum_size = Vector2(108, 0)
	name.add_theme_color_override("font_color", C_TEXT)
	name.add_theme_font_size_override("font_size", 14)
	row.add_child(name)
	var build_time := Label.new()
	build_time.text = "10 mins"
	build_time.add_theme_color_override("font_color", C_ACCENT)
	build_time.add_theme_font_size_override("font_size", 13)
	row.add_child(build_time)
	return row

func _build_tank_row() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var icon := UnitIconScript.new() as UnitIcon
	icon.unit_type = Game.T_TANK
	row.add_child(icon)
	var name := Label.new()
	name.text = "Tank (1 min)"
	name.custom_minimum_size = Vector2(108, 0)
	name.add_theme_color_override("font_color", C_TEXT)
	name.add_theme_font_size_override("font_size", 14)
	row.add_child(name)
	tank_count_input = SpinBox.new()
	tank_count_input.min_value = 1
	tank_count_input.max_value = 99999
	tank_count_input.step = 1
	tank_count_input.rounded = true
	tank_count_input.value = 1
	tank_count_input.custom_minimum_size = Vector2(72, 0)
	tank_count_line_edit = tank_count_input.get_line_edit()
	if tank_count_line_edit != null:
		tank_count_line_edit.text = "1"
		tank_count_line_edit.max_length = 5
		tank_count_line_edit.text_changed.connect(_on_tank_count_text_changed)
		tank_count_line_edit.focus_exited.connect(_normalize_tank_count_input)
	row.add_child(tank_count_input)
	tank_build_button = Button.new()
	tank_build_button.text = "Build"
	tank_build_button.focus_mode = Control.FOCUS_NONE
	tank_build_button.add_theme_stylebox_override("normal", _btn_style())
	tank_build_button.add_theme_stylebox_override("hover", _btn_style())
	tank_build_button.add_theme_stylebox_override("pressed", _btn_style_armed())
	tank_build_button.add_theme_stylebox_override("focus", _btn_style())
	tank_build_button.add_theme_color_override("font_color", C_TEXT)
	tank_build_button.add_theme_font_size_override("font_size", 13)
	tank_build_button.pressed.connect(_on_build_tank_pressed)
	row.add_child(tank_build_button)
	tank_pause_button = Button.new()
	tank_pause_button.text = "Pause"
	tank_pause_button.focus_mode = Control.FOCUS_NONE
	tank_pause_button.add_theme_stylebox_override("normal", _btn_style_tinted(C_PAUSE_BG, C_PAUSE_BD))
	tank_pause_button.add_theme_stylebox_override("hover", _btn_style_tinted(C_PAUSE_BG, C_PAUSE_BD))
	tank_pause_button.add_theme_stylebox_override("pressed", _btn_style_tinted(C_PAUSE_BD, C_PAUSE_BD))
	tank_pause_button.add_theme_stylebox_override("focus", _btn_style_tinted(C_PAUSE_BG, C_PAUSE_BD))
	tank_pause_button.add_theme_color_override("font_color", C_PAUSE_TX)
	tank_pause_button.add_theme_font_size_override("font_size", 13)
	tank_pause_button.disabled = true
	tank_pause_button.pressed.connect(_on_pause_tank_queue_pressed)
	row.add_child(tank_pause_button)
	tank_cancel_button = Button.new()
	tank_cancel_button.text = "Cancel"
	tank_cancel_button.focus_mode = Control.FOCUS_NONE
	tank_cancel_button.add_theme_stylebox_override("normal", _btn_style_tinted(C_CANCEL_BG, C_CANCEL_BD))
	tank_cancel_button.add_theme_stylebox_override("hover", _btn_style_tinted(C_CANCEL_BG, C_CANCEL_BD))
	tank_cancel_button.add_theme_stylebox_override("pressed", _btn_style_tinted(C_CANCEL_BD, C_CANCEL_BD))
	tank_cancel_button.add_theme_stylebox_override("focus", _btn_style_tinted(C_CANCEL_BG, C_CANCEL_BD))
	tank_cancel_button.add_theme_color_override("font_color", C_CANCEL_TX)
	tank_cancel_button.add_theme_font_size_override("font_size", 13)
	tank_cancel_button.disabled = true
	tank_cancel_button.pressed.connect(_on_cancel_tank_queue_pressed)
	row.add_child(tank_cancel_button)
	wrap.add_child(row)
	tank_queue_bar = ProgressBar.new()
	tank_queue_bar.max_value = 1.0
	tank_queue_bar.show_percentage = false
	tank_queue_bar.value = 0.0
	tank_queue_bar.custom_minimum_size = Vector2(0, 22)
	tank_queue_bar.add_theme_stylebox_override("background", _bar_bg_style())
	tank_queue_bar.add_theme_stylebox_override("fill", _bar_style(C_ACCENT, C_SUP_B))
	wrap.add_child(tank_queue_bar)
	tank_queue_count_label = Label.new()
	tank_queue_count_label.text = ""
	tank_queue_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tank_queue_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tank_queue_count_label.anchor_right = 1.0
	tank_queue_count_label.anchor_bottom = 1.0
	tank_queue_count_label.add_theme_color_override("font_color", Color(0.180, 0.125, 0.071))
	tank_queue_count_label.add_theme_color_override("font_outline_color", C_TEXT)
	tank_queue_count_label.add_theme_constant_override("outline_size", 2)
	tank_queue_count_label.add_theme_font_size_override("font_size", 13)
	tank_queue_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tank_queue_bar.add_child(tank_queue_count_label)
	return wrap

func _create_minimap_panel() -> void:
	minimap_panel = PanelContainer.new()
	minimap_panel.add_theme_stylebox_override("panel", _panel_style(20))
	minimap_panel.layout_mode = 1
	minimap_panel.anchor_left = 0.0
	minimap_panel.anchor_top = 1.0
	minimap_panel.anchor_right = 0.0
	minimap_panel.anchor_bottom = 1.0
	minimap_panel.offset_left = 0.0
	minimap_panel.offset_top = 0.0
	minimap_panel.offset_right = 0.0
	minimap_panel.offset_bottom = 0.0
	minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_panel.add_child(vbox)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var title := Label.new()
	title.text = "Mini Map"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", C_TEXT)
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var pill := Label.new()
	pill.text = "Live"
	pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pill.add_theme_color_override("font_color", C_ACCENT)
	pill.add_theme_font_size_override("font_size", 13)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(pill)
	minimap_view = MiniMapScript.new()
	minimap_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(minimap_view)
	add_child(minimap_panel)
	_layout_minimap_panel()

func _layout_minimap_panel() -> void:
	if minimap_panel == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	var panel_w: float = vp.x * MINIMAP_SCREEN_W
	var map_h: float = panel_w * float(Game.MAP_ROWS) / float(Game.MAP_COLS)
	var panel_h: float = map_h + MINIMAP_HEAD_H
	minimap_panel.offset_left = MINIMAP_EDGE
	minimap_panel.offset_right = MINIMAP_EDGE + panel_w
	minimap_panel.offset_bottom = -MINIMAP_EDGE
	minimap_panel.offset_top = -(MINIMAP_EDGE + panel_h)
	if unit_catalog_panel != null:
		unit_catalog_panel.offset_left = MINIMAP_EDGE
		unit_catalog_panel.offset_right = MINIMAP_EDGE + panel_w
		unit_catalog_panel.offset_top = MINIMAP_EDGE
		unit_catalog_panel.offset_bottom = -(MINIMAP_EDGE + panel_h + MINIMAP_GAP)
	unit_panel.offset_left = MINIMAP_EDGE + panel_w + MINIMAP_GAP

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
	if not Game.drag_on:
		if _last_drag_sig != "":
			_last_drag_sig = ""
			queue_redraw()
		return
	var drag_sig := "%s|%s|%s|%s|%s|%s" % [
		Game.drag_on,
		Game.drag_box,
		Game.drag_start.x,
		Game.drag_start.y,
		Game.drag_cur.x,
		Game.drag_cur.y,
	]
	if drag_sig != _last_drag_sig:
		_last_drag_sig = drag_sig
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_minimap_panel()
		queue_redraw()

func _draw() -> void:
	_draw_field_hud()
	_draw_sel_rect()

# ── screen-space drawing (CanvasLayer, not affected by Camera2D) ────────────
func _draw_field_hud() -> void:
	var vp := get_viewport_rect().size
	var font_size := _scaled_font_size(14)
	var panel_h := 42.0
	var panel_y := vp.y - 68.0
	var panel_w := minf(vp.x - 52.0, 1180.0)
	draw_rect(Rect2(26, panel_y, panel_w, panel_h), Color(0.047, 0.071, 0.047, 0.34))
	draw_rect(Rect2(26, panel_y, panel_w, panel_h), Color(1, 0.914, 0.663, 0.25), false, 1)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(40, panel_y + 28.0),
		"Combat: player tanks auto-fire on enemy tanks in range. Selected trucks show a resupply radius.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.957, 0.831, 0.506))

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

func _icon_btn_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.071, 0.086, 0.098, 0.88)
	s.border_color = Color(1.0, 0.906, 0.659, 0.20)
	for side in ["left", "top", "right", "bottom"]:
		s.set("border_width_" + side, 1)
	s.corner_radius_top_left = 12; s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12; s.corner_radius_bottom_right = 12
	s.content_margin_left = 4; s.content_margin_top = 4
	s.content_margin_right = 4; s.content_margin_bottom = 4
	return s

func _icon_btn_style_armed() -> StyleBoxFlat:
	var s := _icon_btn_style()
	s.border_color = Color(1, 0.882, 0.573, 0.95)
	s.shadow_color = Color(1, 0.882, 0.573, 0.35)
	s.shadow_size = 1
	return s

func _btn_style_armed() -> StyleBoxFlat:
	var s := _btn_style()
	s.border_color = Color(1, 0.882, 0.573, 0.95)
	s.shadow_color = Color(1, 0.882, 0.573, 0.5)
	s.shadow_size = 1
	return s

func _btn_style_tinted(bg: Color, border: Color) -> StyleBoxFlat:
	var s := _btn_style()
	s.bg_color = bg
	s.border_color = border
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

func _on_build_airport_pressed() -> void:
	build_requested.emit(Game.T_AIRPORT)

func _on_tank_count_text_changed(new_text: String) -> void:
	if _tank_count_text_guard:
		return
	var digits_only := _digits_only_text(new_text)
	if digits_only.length() > 5:
		digits_only = digits_only.substr(0, 5)
	if digits_only != new_text and tank_count_line_edit != null:
		_tank_count_text_guard = true
		tank_count_line_edit.text = digits_only
		_tank_count_text_guard = false
	if digits_only.is_empty():
		return
	var next_value: int = clampi(int(digits_only), int(tank_count_input.min_value), int(tank_count_input.max_value))
	_set_tank_count_value(next_value)

func _normalize_tank_count_input() -> void:
	if tank_count_input == null:
		return
	if tank_count_line_edit == null:
		_set_tank_count_value(maxi(1, int(round(tank_count_input.value))))
		return
	var digits_only := _digits_only_text(tank_count_line_edit.text)
	var next_value: int = 1 if digits_only.is_empty() else clampi(int(digits_only), int(tank_count_input.min_value), int(tank_count_input.max_value))
	_set_tank_count_value(next_value)

func _set_tank_count_value(value: int) -> void:
	var clamped_value: int = clampi(value, int(tank_count_input.min_value), int(tank_count_input.max_value))
	_tank_count_text_guard = true
	tank_count_input.value = clamped_value
	if tank_count_line_edit != null:
		tank_count_line_edit.text = str(clamped_value)
	_tank_count_text_guard = false

func _digits_only_text(raw_text: String) -> String:
	var digits_only := ""
	for i in range(raw_text.length()):
		var code: int = raw_text.unicode_at(i)
		if code >= 48 and code <= 57:
			digits_only += raw_text.substr(i, 1)
	return digits_only

func _on_build_tank_pressed() -> void:
	_normalize_tank_count_input()
	var amount: int = maxi(1, int(round(tank_count_input.value)))
	unit_build_requested.emit(Game.T_TANK, amount)

func _on_pause_tank_queue_pressed() -> void:
	tank_queue_pause_requested.emit()

func _on_cancel_tank_queue_pressed() -> void:
	tank_queue_cancel_requested.emit()

# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API (called from main.gd)
# ═══════════════════════════════════════════════════════════════════════════════
func set_status(msg: String) -> void:
	lbl_status.text = msg

func set_unit_catalog_supply(current: float) -> void:
	if unit_catalog_supply_label != null:
		unit_catalog_supply_label.text = "Supply Pool: " + str(roundi(current))

func set_tank_queue_status(queue_count: int, progress: float, waiting_for_space: bool, paused: bool) -> void:
	if tank_queue_bar == null or tank_queue_count_label == null:
		return
	if tank_pause_button != null:
		tank_pause_button.disabled = queue_count <= 0
		tank_pause_button.text = "Resume" if paused and queue_count > 0 else "Pause"
	if tank_cancel_button != null:
		tank_cancel_button.disabled = queue_count <= 0
	if queue_count <= 0:
		tank_queue_bar.value = 0.0
		tank_queue_count_label.text = ""
		return
	if waiting_for_space and not paused:
		tank_queue_bar.value = 1.0
		tank_queue_count_label.text = str(queue_count)
		return
	tank_queue_bar.value = clampf(progress, 0.0, 1.0)
	tank_queue_count_label.text = str(queue_count)

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
	var armed_airport: bool = Game.build_mode == Game.T_AIRPORT
	var airport_style: StyleBoxFlat = _icon_btn_style_armed() if armed_airport else _icon_btn_style()
	btn_plant.add_theme_stylebox_override("normal", _btn_style_armed() if armed_plant else _btn_style())
	btn_depot.add_theme_stylebox_override("normal", _btn_style_armed() if armed_depot else _btn_style())
	if airport_icon_button != null:
		airport_icon_button.add_theme_stylebox_override("normal", airport_style)
		airport_icon_button.add_theme_stylebox_override("hover", airport_style)
		airport_icon_button.add_theme_stylebox_override("focus", airport_style)
		airport_icon_button.add_theme_stylebox_override("pressed", _icon_btn_style_armed())
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
	elif s is Airport:
		prod_panel.visible = false
		lbl_sel_pill.text = s.label
		lbl_sel_detail.text = "Non-movable airfield structure. Placement uses the map build mode. Build time listed in the factory panel: 10 mins."
		lbl_unit_pill.text = "Airport selected"
		lbl_unit_name.text = "Airport #" + str(s.entity_id)
		lbl_unit_copy.text = "Airfield structure reserved for future aerial unit production."
		hp_row.visible = false
		sup_row.visible = false

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
