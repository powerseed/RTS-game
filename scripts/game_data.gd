extends Node
## Autoload "Game" — shared constants, coordinate helpers, fog system, and game state.

# ── Signals ──────────────────────────────────────────────────────────────────
signal unit_spawned(unit: Node2D)
signal unit_died(unit: Node2D)
signal structure_placed(structure: Node2D)

# ── Map ──────────────────────────────────────────────────────────────────────
const MAP_COLS := 120
const MAP_ROWS := 100
const BASE_TILE_W := 78.0
const BASE_TILE_H := 39.0
const BASE_SLAB  := 28.0

var camera: Camera2D  # Set by main.gd in _ready()

# ── Building / unit type keys ────────────────────────────────────────────────
const T_PLANT  := "tank_plant"
const T_DEPOT  := "supply_depot"
const T_TRUCK  := "supply_truck"
const T_TANK   := "tank"

const PLAYER := "player"
const ENEMY  := "enemy"

# ── Building definitions ─────────────────────────────────────────────────────
const BLDG := {
	"tank_plant": {
		"label": "Tank Plant", "w": 2, "h": 2,
		"prod_interval": 2.6, "height_px": 82,
	},
	"supply_depot": {
		"label": "Supply Depot", "w": 2, "h": 2,
		"height_px": 64, "storage": 2000,
	},
}

# ── Supply truck stats ───────────────────────────────────────────────────────
const TRUCK_CARGO     := 500.0
const TRUCK_SPEED     := 1.26
const TRUCK_ARRIVE_R  := 0.34
const TRUCK_RESUPPLY_R := 3.0
const DEPOT_SUPPLY_R   := 8.0
const TRUCK_RESUPPLY_S := 60.0

# ── Gameplay tuning ──────────────────────────────────────────────────────────
const SUP_PER_UNIT     := 0.5
const SUP_PER_SHOT     := 5.0
const SUP_IDLE_RATE    := 0.3  # supply consumed per second while idle
const DRAG_THRESH      := 10.0
const FORM_SPACE       := 0.92
const TANK_COL_R       := 0.44
const TRUCK_COL_R      := 0.36
const COL_PAD          := 0.04
const COL_CELL         := 1.2
const COL_ITERS        := 3

const VIS_STRUCT       := 8.5
const VIS_UNIT         := 5.5
const VIS_TRUCK        := 4.4
const VIS_FALLBACK     := 9.0

const ATK_RANGE        := 4.8
const ENEMY_SEEK_R     := 12.0
const ATK_DMG          := 20.0
const ATK_CD           := 0.95
const TRACER_TTL       := 0.16
const DMG_BAR_S        := 1.35

const INIT_ENEMIES := [
	{"x": 17.5, "y": 48.5, "hx": -1.0, "hy": 0.1},
]

# ── Mutable game state ───────────────────────────────────────────────────────
var build_mode          := ""
var hover_tile          := Vector2i(-1, -1)
var selected_structure  : Node2D = null
var selected_units      : Array[Node2D] = []
var next_id             := 1

var cam          := Vector2(60.0, 50.0)
var ptr_scr      := Vector2.ZERO
var ptr_in       := false

var drag_on      := false
var drag_start   := Vector2.ZERO
var drag_cur     := Vector2.ZERO
var drag_box     := false

var elapsed: float:
	get: return Time.get_ticks_msec() / 1000.0

# ── Noise (FastNoiseLite) ───────────────────────────────────────────────────
var noise_a: FastNoiseLite
var noise_b: FastNoiseLite

# ── Fog of war (packed byte arrays, 0/1) ─────────────────────────────────────
var fog_vis : PackedByteArray
var fog_exp : PackedByteArray

func _ready() -> void:
	cam = Vector2(MAP_COLS * 0.5, MAP_ROWS * 0.5)
	noise_a = FastNoiseLite.new()
	noise_a.seed = 1
	noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_b = FastNoiseLite.new()
	noise_b.seed = 2
	noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var sz := MAP_COLS * MAP_ROWS
	fog_vis = PackedByteArray()
	fog_vis.resize(sz); fog_vis.fill(0)
	fog_exp = PackedByteArray()
	fog_exp.resize(sz); fog_exp.fill(0)

# ── Coordinate helpers (Camera2D-based) ──────────────────────────────────────
func grid_to_world(gx: float, gy: float, gz: float = 0.0) -> Vector2:
	return Vector2(
		(gx - gy) * BASE_TILE_W * 0.5,
		(gx + gy) * BASE_TILE_H * 0.5 - gz)

func world_to_grid(wx: float, wy: float) -> Vector2:
	return Vector2(
		(wy / (BASE_TILE_H * 0.5) + wx / (BASE_TILE_W * 0.5)) * 0.5,
		(wy / (BASE_TILE_H * 0.5) - wx / (BASE_TILE_W * 0.5)) * 0.5)

func screen_to_world(sp: Vector2) -> Vector2:
	return camera.get_canvas_transform().affine_inverse() * sp

func world_to_screen(wp: Vector2) -> Vector2:
	return camera.get_canvas_transform() * wp

func screen_to_grid(sp: Vector2) -> Vector2:
	var wp := screen_to_world(sp)
	return world_to_grid(wp.x, wp.y)

func tile_at(sx: float, sy: float) -> Vector2i:
	var g := screen_to_grid(Vector2(sx, sy))
	if g.x < 0 or g.y < 0 or g.x >= MAP_COLS or g.y >= MAP_ROWS:
		return Vector2i(-1, -1)
	return Vector2i(int(g.x), int(g.y))

# ── Fog helpers ──────────────────────────────────────────────────────────────
func _fi(c: int, r: int) -> int:
	return r * MAP_COLS + c

func fvis(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS: return false
	return fog_vis[_fi(c, r)] != 0

func fexp(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS: return false
	return fog_exp[_fi(c, r)] != 0

func fog_set(c: int, r: int) -> void:
	var i := _fi(c, r)
	fog_vis[i] = 1; fog_exp[i] = 1

func fog_reset_vis() -> void:
	fog_vis.fill(0)

func fog_has_vis_neigh(c: int, r: int) -> bool:
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0: continue
			if fvis(c + dc, r + dr): return true
	return false

# ── Building definitions helper ──────────────────────────────────────────────
func bldg_def(btype: String) -> Dictionary:
	return BLDG.get(btype, {})

# ── Scene tree queries (replaces manual arrays) ─────────────────────────────
func get_units() -> Array[Node]:
	return get_tree().get_nodes_in_group("units")

func get_structures() -> Array[Node]:
	return get_tree().get_nodes_in_group("structures")

func struct_at(c: int, r: int) -> Node2D:
	for s: Structure in get_structures():
		if c >= s.grid_col and c < s.grid_col + s.grid_w and r >= s.grid_row and r < s.grid_row + s.grid_h:
			return s
	return null

func fp_valid(c: int, r: int, w: int, h: int) -> bool:
	if c < 0 or r < 0 or c + w > MAP_COLS or r + h > MAP_ROWS: return false
	for s: Structure in get_structures():
		if not (c + w <= s.grid_col or c >= s.grid_col + s.grid_w or r + h <= s.grid_row or r >= s.grid_row + s.grid_h):
			return false
	for u: Unit in get_units():
		if u.gx >= c and u.gx < c + w and u.gy >= r and u.gy < r + h:
			return false
	return true

func passable(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < MAP_COLS and r < MAP_ROWS and struct_at(c, r) == null

func find_open(wx: float, wy: float):
	var cx := clampf(wx, 0.85, MAP_COLS - 0.85)
	var cy := clampf(wy, 0.85, MAP_ROWS - 0.85)
	var sc := clampi(int(cx), 0, MAP_COLS - 1)
	var sr := clampi(int(cy), 0, MAP_ROWS - 1)
	if passable(sc, sr): return Vector2(cx, cy)
	for rad in range(1, 7):
		for rr in range(sr - rad, sr + rad + 1):
			for cc in range(sc - rad, sc + rad + 1):
				if maxi(absi(cc - sc), absi(rr - sr)) != rad: continue
				if passable(cc, rr):
					return Vector2(clampf(cc + 0.5, 0.85, MAP_COLS - 0.85),
									clampf(rr + 0.5, 0.85, MAP_ROWS - 0.85))
	return null

func unit_at_screen(sx: float, sy: float) -> Node2D:
	var best: Node2D = null
	var best_d := 26.0
	for u: Unit in get_units():
		var sc := world_to_screen(grid_to_world(u.gx, u.gy, u.get_lift()))
		var d := sc.distance_to(Vector2(sx, sy))
		if d < best_d:
			best_d = d; best = u
	return best

func get_selected_units() -> Array[Node2D]:
	var valid: Array[Node2D] = []
	for u in selected_units:
		if is_instance_valid(u):
			valid.append(u)
	selected_units = valid
	return valid

func clear_selection() -> void:
	selected_structure = null
	selected_units.clear()
