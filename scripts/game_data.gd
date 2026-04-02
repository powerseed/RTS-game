extends Node
## Autoload "Game" — shared constants, coordinate helpers, fog system, and game state.

# ── Signals ──────────────────────────────────────────────────────────────────
signal unit_spawned(unit: Node2D)
signal unit_died(unit: Node2D)
signal structure_placed(structure: Node2D)
signal terrain_changed

# ── Map ──────────────────────────────────────────────────────────────────────
const MAP_COLS := 120
const MAP_ROWS := 100
const MAP_SEED := 20260330
const ELEV_METERS_PER_LEVEL := 10.0
const BASE_TILE_W := 78.0
const BASE_TILE_H := 39.0
const BASE_SLAB  := 28.0
const MIN_HILL_ELEV := 1
const MAX_HILL_ELEV := 10
const ELEV_STEP_PX := 14.0
const START_PLAIN_RADIUS := 12.0
const START_CORNER_MARGIN := 2
const RIDGE_STRIKE_MIN_DEG := 18.0
const RIDGE_STRIKE_MAX_DEG := 64.0
const RIDGE_WARP_MAG := 9.0
const RIDGE_PRIMARY_FREQ := 0.235
const RIDGE_SECONDARY_FREQ := 0.121
const MOUNTAIN_TARGET_SHARE := 0.20
const MOUNTAIN_CENTER_X_SPAN := 0.58
const MOUNTAIN_CENTER_Y_SPAN := 0.48

var camera: Camera2D  # Set by main.gd in _ready()

# ── Building / unit type keys ────────────────────────────────────────────────
const T_PLANT  := "tank_plant"
const T_DEPOT  := "supply_depot"
const T_AIRPORT := "airport"
const T_TRUCK  := "supply_truck"
const T_TANK   := "tank"
const T_MORTAR := "mortar_squad"

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
	"airport": {
		"label": "Airport", "w": 4, "h": 3,
		"height_px": 54, "build_time_min": 10,
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
const SWAMP_SPEED_MUL  := 0.5
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
const VIS_OBSERVER_HEIGHT_M := 1.7
const VIS_STRUCT_OBSERVER_HEIGHT_M := 6.0
const VIS_FALLBACK     := 9.0
const FOREST_CONCEALMENT := 0.60
const EXPOSED_TTL_S    := 3.0

const ATK_RANGE        := 9.6
const ENEMY_SEEK_R     := 12.0
const ATK_DMG          := 20.0
const BRIDGE_HP        := ATK_DMG * 3.0
const ATK_CD           := 0.95
const SHELL_SPEED      := 11.5
const SHELL_HIT_R      := 0.18
const SHELL_ARC_BASE   := 10.0
const SHELL_ARC_PER_UNIT := 2.1
const SHELL_ARC_ELEV_BIAS := 0.18
const MORTAR_RANGE_MUL := 2.5
const MORTAR_SHELL_SPEED := 6.2
const MORTAR_SHELL_ARC_BASE := 44.0
const MORTAR_SHELL_ARC_PER_UNIT := 8.2
const MORTAR_SHELL_ARC_MIN := 52.0
const MORTAR_SHELL_ARC_MAX := 148.0
const EXPLOSION_TTL    := 0.34
const OUT_OF_SUPPLY_DEATH_S := 30.0
const DMG_BAR_S        := 1.35
const SUPER_TANK_SPEED_MUL := 10.0

const INIT_ENEMIES := [
	{"x": 25.5, "y": 47.5, "hx": -1.0, "hy": 0.1},
	{"x": 12.5, "y": 14.5, "hx": 0.8, "hy": 0.2},
	{"x": 32.5, "y": 20.5, "hx": 0.2, "hy": 0.9},
	{"x": 52.5, "y": 14.5, "hx": -0.6, "hy": 0.5},
	{"x": 74.5, "y": 24.5, "hx": -0.9, "hy": 0.2},
	{"x": 94.5, "y": 18.5, "hx": -0.7, "hy": 0.4},
	{"x": 14.5, "y": 66.5, "hx": 0.8, "hy": -0.2},
	{"x": 34.5, "y": 82.5, "hx": 0.5, "hy": -0.7},
	{"x": 58.5, "y": 72.5, "hx": -0.2, "hy": -0.9},
	{"x": 82.5, "y": 60.5, "hx": -0.8, "hy": -0.3},
	{"x": 98.5, "y": 84.5, "hx": -0.6, "hy": -0.6},
]

# ── Mutable game state ───────────────────────────────────────────────────────
var build_mode          := ""
var hover_tile          := Vector2i(-1, -1)
var selected_structure  : Node2D = null
var selected_units      : Array[Node2D] = []
var next_id             := 1
var cheat_reveal_all    := false
var cheat_super_tanks   := false

var cam          := Vector2(60.0, 50.0)
var ptr_scr      := Vector2.ZERO
var ptr_in       := false

var drag_on      := false
var drag_start   := Vector2.ZERO
var drag_cur     := Vector2.ZERO
var drag_box     := false

var elapsed: float:
	get: return Time.get_ticks_msec() / 1000.0

# ── Terrain types ─────────────────────────────────────────────────────────────
enum Tile { GRASS, WATER, BRIDGE, SWAMP, FOREST, HILL, CLIFF }
enum Ramp { NONE, NORTH, EAST, SOUTH, WEST }
enum Corner { NW, NE, SE, SW }
var tile_type: PackedByteArray   # per-tile terrain type (Tile enum)
var tile_elev: PackedByteArray   # per-tile elevation (0..MAX_HILL_ELEV)
var tile_ramp: PackedByteArray   # per-tile ramp direction (Ramp enum)
var bridge_hp: PackedFloat32Array

# ── Noise (FastNoiseLite) ───────────────────────────────────────────────────
var noise_a: FastNoiseLite
var noise_b: FastNoiseLite
var noise_c: FastNoiseLite  # elevation
var noise_d: FastNoiseLite  # detail / decorations
var noise_river: FastNoiseLite  # long meandering river paths
var noise_biome: FastNoiseLite  # broad biome regions for forests and swamps

# ── Fog of war (packed byte arrays, 0/1) ─────────────────────────────────────
var fog_vis : PackedByteArray
var fog_exp : PackedByteArray
var fog_revision: int = 0

func _ready() -> void:
	cam = Vector2(MAP_COLS * 0.5, MAP_ROWS * 0.5)
	noise_a = FastNoiseLite.new()
	noise_a.seed = MAP_SEED + 101
	noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_a.frequency = 0.03
	noise_b = FastNoiseLite.new()
	noise_b.seed = MAP_SEED + 211
	noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_b.frequency = 0.025
	noise_c = FastNoiseLite.new()
	noise_c.seed = MAP_SEED + 307
	noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_c.frequency = 0.018
	noise_d = FastNoiseLite.new()
	noise_d.seed = MAP_SEED + 401
	noise_d.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_d.frequency = 0.06
	noise_river = FastNoiseLite.new()
	noise_river.seed = MAP_SEED + 503
	noise_river.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_river.frequency = 0.022
	noise_biome = FastNoiseLite.new()
	noise_biome.seed = MAP_SEED + 601
	noise_biome.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_biome.frequency = 0.013
	_bake_tile_data()
	var sz := MAP_COLS * MAP_ROWS
	fog_vis = PackedByteArray()
	fog_vis.resize(sz); fog_vis.fill(0)
	fog_exp = PackedByteArray()
	fog_exp.resize(sz); fog_exp.fill(0)

func _in_start_plain(c: int, r: int) -> bool:
	var center: Vector2 = starting_plain_center()
	var dx: float = (c + 0.5) - center.x
	var dy: float = (r + 0.5) - center.y
	return (dx * dx + dy * dy) < START_PLAIN_RADIUS * START_PLAIN_RADIUS

func starting_depot_grid_pos() -> Vector2i:
	var depot_def: Dictionary = BLDG[T_DEPOT]
	var depot_w: int = int(depot_def["w"])
	return Vector2i(
		MAP_COLS - depot_w - START_CORNER_MARGIN,
		START_CORNER_MARGIN
	)

func starting_plain_center() -> Vector2:
	var depot_pos: Vector2i = starting_depot_grid_pos()
	var depot_def: Dictionary = BLDG[T_DEPOT]
	var depot_w: int = int(depot_def["w"])
	var depot_h: int = int(depot_def["h"])
	return Vector2(
		float(depot_pos.x) + float(depot_w) * 0.5,
		float(depot_pos.y) + float(depot_h) * 0.5
	)

func _bake_tile_data() -> void:
	var sz := MAP_COLS * MAP_ROWS
	tile_type = PackedByteArray()
	tile_type.resize(sz)
	tile_type.fill(Tile.GRASS)
	tile_elev = PackedByteArray()
	tile_elev.resize(sz)
	tile_elev.fill(0)
	tile_ramp = PackedByteArray()
	tile_ramp.resize(sz)
	tile_ramp.fill(Ramp.NONE)
	bridge_hp = PackedFloat32Array()
	bridge_hp.resize(sz)
	bridge_hp.fill(0.0)
	var blocked := PackedByteArray()
	blocked.resize(sz)
	blocked.fill(0)
	var river_candidates: Array[Vector2] = []
	var forest_candidates: Array[Vector2] = []
	var swamp_candidates: Array[Vector2] = []
	for r in range(MAP_ROWS):
		for c in range(MAP_COLS):
			var i := r * MAP_COLS + c
			var in_spawn: bool = _in_start_plain(c, r)
			if in_spawn:
				blocked[i] = 1
				continue
			var nA := (noise_a.get_noise_2d(c, r) + 1.0) * 0.5
			var nB := (noise_b.get_noise_2d(c, r) + 1.0) * 0.5
			var nD := (noise_d.get_noise_2d(c, r) + 1.0) * 0.5
			var nE := (noise_biome.get_noise_2d(c, r) + 1.0) * 0.5
			var nF := (noise_biome.get_noise_2d(c + 87.0, r - 53.0) + 1.0) * 0.5
			var nG := (noise_biome.get_noise_2d(c - 91.0, r + 67.0) + 1.0) * 0.5
			var river_south_center := _river_center_south(c)
			var river_north_center := _river_center_north(c)
			var river_width := 1.35 + maxf(0.0, nD - 0.42) * 1.55
			var river_south := maxf(0.0, 1.0 - absf(r - river_south_center) / river_width)
			var river_north := maxf(0.0, 1.0 - absf(r - river_north_center) / (river_width * 0.92))
			var river_score := maxf(river_south, river_north)
			var forest_score := clampf(nF * 0.72 + nA * 0.18 + nD * 0.10, 0.0, 1.0)
			var swamp_score := clampf((1.0 - nE) * 0.58 + nG * 0.30 + (1.0 - nB) * 0.12, 0.0, 1.0)
			river_candidates.append(Vector2(river_score, i))
			forest_candidates.append(Vector2(forest_score, i))
			swamp_candidates.append(Vector2(swamp_score, i))
	var water_mask := _select_top_mask(river_candidates, roundi(float(sz) * 0.10), blocked)
	_bake_ridge_valley_mountains(blocked, roundi(float(sz) * MOUNTAIN_TARGET_SHARE))
	var forest_mask := _select_top_mask(forest_candidates, roundi(float(sz) * 0.10), blocked)
	var swamp_mask := _select_top_mask(swamp_candidates, roundi(float(sz) * 0.10), blocked)
	for r in range(MAP_ROWS):
		for c in range(MAP_COLS):
			var i := r * MAP_COLS + c
			if water_mask[i] != 0:
				tile_type[i] = Tile.WATER
				tile_elev[i] = 0
			elif tile_elev[i] > 0:
				tile_type[i] = Tile.HILL
			elif forest_mask[i] != 0:
				tile_type[i] = Tile.FOREST
			elif swamp_mask[i] != 0:
				tile_type[i] = Tile.SWAMP
			else:
				tile_type[i] = Tile.GRASS
	tile_ramp.fill(Ramp.NONE)
	_bake_bridges()

func _bake_bridges() -> void:
	_place_river_bridge(false, roundi(float(MAP_COLS) * 0.30))
	_place_river_bridge(true, roundi(float(MAP_COLS) * 0.70))

func _place_river_bridge(is_north: bool, preferred_col: int) -> void:
	if _scan_bridge_columns(preferred_col, is_north, false):
		return
	_scan_bridge_columns(preferred_col, is_north, true)

func _scan_bridge_columns(preferred_col: int, is_north: bool, force_shores: bool) -> bool:
	for offset in range(MAP_COLS):
		var left_col: int = preferred_col - offset
		if _try_place_bridge_at(left_col, is_north, force_shores):
			return true
		if offset == 0:
			continue
		var right_col: int = preferred_col + offset
		if _try_place_bridge_at(right_col, is_north, force_shores):
			return true
	return false

func _try_place_bridge_at(col: int, is_north: bool, force_shores: bool) -> bool:
	var span: Vector2i = _find_bridge_span(col, is_north)
	if span.x < 0:
		return false
	if not force_shores and (not _bridge_shore_ok(col, span.x - 1) or not _bridge_shore_ok(col, span.y + 1)):
		return false
	if force_shores:
		_make_bridge_landing(col, span.x - 1)
		_make_bridge_landing(col, span.y + 1)
	for r in range(span.x, span.y + 1):
		var i := r * MAP_COLS + col
		tile_type[i] = Tile.BRIDGE
		tile_elev[i] = 0
		tile_ramp[i] = Ramp.NONE
		bridge_hp[i] = BRIDGE_HP
	return true

func _find_bridge_span(col: int, is_north: bool) -> Vector2i:
	if col < 2 or col >= MAP_COLS - 2:
		return Vector2i(-1, -1)
	var center_row_f: float = _river_center_north(float(col)) if is_north else _river_center_south(float(col))
	var center_row: int = clampi(int(round(center_row_f)), 1, MAP_ROWS - 2)
	var water_row: int = -1
	for dist in range(10):
		var up_row: int = center_row - dist
		if up_row >= 0 and get_tile(col, up_row) == Tile.WATER:
			water_row = up_row
			break
		if dist == 0:
			continue
		var down_row: int = center_row + dist
		if down_row < MAP_ROWS and get_tile(col, down_row) == Tile.WATER:
			water_row = down_row
			break
	if water_row < 0:
		return Vector2i(-1, -1)
	var start_row: int = water_row
	while start_row > 0 and get_tile(col, start_row - 1) == Tile.WATER:
		start_row -= 1
	var end_row: int = water_row
	while end_row < MAP_ROWS - 1 and get_tile(col, end_row + 1) == Tile.WATER:
		end_row += 1
	if start_row == 0 or end_row >= MAP_ROWS - 1:
		return Vector2i(-1, -1)
	if end_row - start_row > 8:
		return Vector2i(-1, -1)
	return Vector2i(start_row, end_row)

func _bridge_shore_ok(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS:
		return false
	return (
		get_tile(c, r) != Tile.WATER and
		get_tile(c, r) != Tile.BRIDGE and
		get_ramp(c, r) == Ramp.NONE and
		get_elev(c, r) == 0
	)

func _make_bridge_landing(c: int, r: int) -> void:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS:
		return
	var i := r * MAP_COLS + c
	tile_type[i] = Tile.GRASS
	tile_elev[i] = 0
	tile_ramp[i] = Ramp.NONE

func _smooth_elevation_field(mesa_mask: PackedByteArray) -> void:
	for _iter in range(1):
		var next := tile_elev.duplicate()
		for r in range(MAP_ROWS):
			for c in range(MAP_COLS):
				var i := r * MAP_COLS + c
				if _in_start_plain(c, r) or mesa_mask[i] == 0:
					next[i] = 0
					continue
				var total := 0
				var count := 0
				for rr in range(maxi(0, r - 1), mini(MAP_ROWS - 1, r + 1) + 1):
					for cc in range(maxi(0, c - 1), mini(MAP_COLS - 1, c + 1) + 1):
						var ni := rr * MAP_COLS + cc
						if mesa_mask[ni] == 0:
							continue
						total += int(tile_elev[ni])
						count += 1
				var avg := roundi(float(total) / float(count))
				var cur := int(tile_elev[i])
				next[i] = clampi(maxi(MIN_HILL_ELEV, int(roundi(lerpf(float(cur), float(avg), 0.34)))), MIN_HILL_ELEV, MAX_HILL_ELEV)
		tile_elev = next

func _limit_elevation_steps(mesa_mask: PackedByteArray) -> void:
	for _iter in range(MAX_HILL_ELEV):
		var next := tile_elev.duplicate()
		var changed := false
		for r in range(MAP_ROWS):
			for c in range(MAP_COLS):
				var i := r * MAP_COLS + c
				if _in_start_plain(c, r) or mesa_mask[i] == 0:
					next[i] = 0
					continue
				var cur := int(tile_elev[i])
				var limited := cur
				for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nc: int = c + dir.x
					var nr: int = r + dir.y
					if nc < 0 or nr < 0 or nc >= MAP_COLS or nr >= MAP_ROWS:
						continue
					var ni := nr * MAP_COLS + nc
					if mesa_mask[ni] == 0:
						limited = mini(limited, 1)
					else:
						limited = mini(limited, int(tile_elev[ni]) + 1)
				if limited != cur:
					next[i] = maxi(1, limited)
					changed = true
		tile_elev = next
		if not changed:
			break

func _select_top_mask(candidates: Array[Vector2], target: int, blocked: PackedByteArray) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(MAP_COLS * MAP_ROWS)
	mask.fill(0)
	if target <= 0 or candidates.is_empty():
		return mask
	candidates.sort_custom(Callable(self, "_score_desc"))
	var picked: int = 0
	for cand: Vector2 in candidates:
		if picked >= target:
			break
		var idx: int = int(cand.y)
		if blocked[idx] != 0:
			continue
		mask[idx] = 1
		blocked[idx] = 1
		picked += 1
	return mask

func _score_desc(a: Vector2, b: Vector2) -> bool:
	if not is_equal_approx(a.x, b.x):
		return a.x > b.x
	return a.y > b.y

func _bake_ridge_valley_mountains(blocked: PackedByteArray, target: int) -> void:
	if target <= 0:
		return
	var scores: PackedFloat32Array = _build_ridge_valley_scores(blocked)
	scores = _blur_score_field(scores, blocked)
	scores = _blur_score_field(scores, blocked)
	var candidates: Array[Vector2] = []
	for i in range(MAP_COLS * MAP_ROWS):
		if blocked[i] != 0:
			continue
		candidates.append(Vector2(scores[i], i))
	if candidates.is_empty():
		return
	candidates.sort_custom(Callable(self, "_score_desc"))
	var target_tiles: int = mini(target, candidates.size())
	if target_tiles <= 0:
		return
	var cutoff_score: float = float(candidates[target_tiles - 1].x)
	var score_span: float = maxf(0.001, 1.0 - cutoff_score)
	for cand: Vector2 in candidates:
		var idx: int = int(cand.y)
		if blocked[idx] != 0:
			continue
		var score: float = float(cand.x)
		if score < cutoff_score:
			break
		var c: int = idx % MAP_COLS
		var r: int = int(idx / MAP_COLS)
		var height_t: float = clampf((score - cutoff_score) / score_span, 0.0, 1.0)
		var uplift_t: float = clampf((_mountain_uplift(c, r) - 0.28) / 0.72, 0.0, 1.0)
		var ridge_t: float = clampf(pow(height_t, 0.68) * 0.78 + uplift_t * 0.22, 0.0, 1.0)
		var elev: int = clampi(1 + int(round(ridge_t * float(MAX_HILL_ELEV - 1))), MIN_HILL_ELEV, MAX_HILL_ELEV)
		tile_elev[idx] = maxi(tile_elev[idx], elev)
		blocked[idx] = 1

func _build_ridge_valley_scores(blocked: PackedByteArray) -> PackedFloat32Array:
	var scores: PackedFloat32Array = PackedFloat32Array()
	scores.resize(MAP_COLS * MAP_ROWS)
	scores.fill(0.0)
	for r in range(MAP_ROWS):
		for c in range(MAP_COLS):
			var i: int = r * MAP_COLS + c
			if blocked[i] != 0:
				continue
			scores[i] = _ridge_valley_score(c, r)
	return scores

func _blur_score_field(scores: PackedFloat32Array, blocked: PackedByteArray) -> PackedFloat32Array:
	var next: PackedFloat32Array = PackedFloat32Array()
	next.resize(scores.size())
	next.fill(0.0)
	for r in range(MAP_ROWS):
		for c in range(MAP_COLS):
			var i: int = r * MAP_COLS + c
			if blocked[i] != 0:
				continue
			var accum: float = float(scores[i]) * 4.0
			var weight: float = 4.0
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nc: int = c + dir.x
				var nr: int = r + dir.y
				if nc < 0 or nr < 0 or nc >= MAP_COLS or nr >= MAP_ROWS:
					continue
				var ni: int = nr * MAP_COLS + nc
				if blocked[ni] != 0:
					continue
				accum += float(scores[ni])
				weight += 1.0
			for dir_diag: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var dc: int = c + dir_diag.x
				var dr: int = r + dir_diag.y
				if dc < 0 or dr < 0 or dc >= MAP_COLS or dr >= MAP_ROWS:
					continue
				var di: int = dr * MAP_COLS + dc
				if blocked[di] != 0:
					continue
				accum += float(scores[di]) * 0.6
				weight += 0.6
			next[i] = accum / maxf(weight, 0.001)
	return next

func _mountain_uplift(c: int, r: int) -> float:
	var broad_a: float = (noise_biome.get_noise_2d(c * 0.30 - 203.0, r * 0.30 + 149.0) + 1.0) * 0.5
	var broad_b: float = (noise_c.get_noise_2d(c * 0.18 + 61.0, r * 0.18 - 171.0) + 1.0) * 0.5
	var center_bias: float = _mountain_center_bias(c, r)
	return clampf((broad_a * 0.58 + broad_b * 0.42) * center_bias, 0.0, 1.0)

func _mountain_center_bias(c: int, r: int) -> float:
	var nx: float = ((float(c) + 0.5) / float(MAP_COLS) - 0.5) / MOUNTAIN_CENTER_X_SPAN
	var ny: float = ((float(r) + 0.5) / float(MAP_ROWS) - 0.5) / MOUNTAIN_CENTER_Y_SPAN
	var dist2: float = nx * nx + ny * ny
	var core: float = clampf(1.0 - dist2, 0.0, 1.0)
	var edge_soften: float = pow(core, 0.72)
	var lobe_noise: float = (noise_a.get_noise_2d(c * 0.16 - 19.0, r * 0.16 + 37.0) + 1.0) * 0.5
	return clampf(edge_soften * (0.80 + lobe_noise * 0.20), 0.0, 1.0)

func _ridge_valley_score(c: int, r: int) -> float:
	var sx: float = float(c)
	var sy: float = float(r)
	var warp_x: float = noise_a.get_noise_2d(sx * 0.45 + 47.0, sy * 0.45 - 63.0) * RIDGE_WARP_MAG
	var warp_y: float = noise_b.get_noise_2d(sx * 0.45 - 29.0, sy * 0.45 + 71.0) * RIDGE_WARP_MAG
	var px: float = sx + warp_x
	var py: float = sy + warp_y
	var strike_t: float = (noise_biome.get_noise_2d(sx * 0.22 + 131.0, sy * 0.22 - 97.0) + 1.0) * 0.5
	var strike_angle: float = deg_to_rad(lerpf(RIDGE_STRIKE_MIN_DEG, RIDGE_STRIKE_MAX_DEG, strike_t))
	var strike_cos: float = cos(strike_angle)
	var strike_sin: float = sin(strike_angle)
	var along: float = px * strike_cos + py * strike_sin
	var across: float = -px * strike_sin + py * strike_cos
	var primary_phase: float = across * RIDGE_PRIMARY_FREQ + noise_c.get_noise_2d(px * 0.28 + 13.0, py * 0.28 - 21.0) * 2.4
	var secondary_phase: float = across * RIDGE_SECONDARY_FREQ + along * 0.038 + noise_d.get_noise_2d(px * 0.19 - 77.0, py * 0.19 + 41.0) * 1.8
	var primary_ridge: float = pow(clampf(1.0 - absf(sin(primary_phase)), 0.0, 1.0), 2.6)
	var secondary_ridge: float = pow(clampf(1.0 - absf(sin(secondary_phase)), 0.0, 1.0), 2.0)
	var ridge_strength: float = maxf(primary_ridge, secondary_ridge * 0.82)
	var uplift: float = _mountain_uplift(c, r)
	var continuity: float = clampf(0.55 + ((noise_a.get_noise_2d(px * 0.16 + 211.0, py * 0.16 - 53.0) + 1.0) * 0.5) * 0.45, 0.0, 1.0)
	var erosion_noise: float = (noise_b.get_noise_2d(along * 0.16 - 117.0, across * 0.16 + 83.0) + 1.0) * 0.5
	var erosion: float = clampf(1.0 - maxf(0.0, 0.56 - erosion_noise) * 1.25, 0.35, 1.0)
	var shoulder: float = clampf(0.25 + ridge_strength * 0.75, 0.0, 1.0)
	return clampf(pow(uplift, 1.2) * shoulder * continuity * erosion, 0.0, 1.0)

func _shrink_tableland_edges() -> void:
	var next := tile_elev.duplicate()
	for r in range(MAP_ROWS):
		for c in range(MAP_COLS):
			var i := r * MAP_COLS + c
			if _in_start_plain(c, r):
				next[i] = 0
				continue
			var cur: int = int(tile_elev[i])
			if cur <= 0:
				continue
			var support: int = 0
			var higher_support: int = 0
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nc: int = c + dir.x
				var nr: int = r + dir.y
				if nc < 0 or nr < 0 or nc >= MAP_COLS or nr >= MAP_ROWS:
					continue
				var neigh: int = int(tile_elev[nr * MAP_COLS + nc])
				if neigh > 0:
					support += 1
				if neigh >= cur:
					higher_support += 1
			var edge_noise := (noise_d.get_noise_2d(c - 79.0, r + 127.0) + 1.0) * 0.5
			if cur <= 2 and support == 0:
				next[i] = 0
			elif cur <= 2 and support <= 1 and edge_noise < 0.34:
				next[i] = maxi(0, cur - 1)
			elif cur <= 3 and support <= 2 and edge_noise < 0.54:
				next[i] = maxi(0, cur - 1)
			elif support <= 1 and higher_support <= 1 and edge_noise < 0.40:
				next[i] = maxi(0, cur - 1)
	tile_elev = next

func _bake_ramps() -> void:
	tile_ramp.fill(Ramp.NONE)
	var visited := PackedByteArray()
	visited.resize(MAP_COLS * MAP_ROWS)
	visited.fill(0)
	for r in range(MAP_ROWS):
		for c in range(MAP_COLS):
			var start_i := r * MAP_COLS + c
			if visited[start_i] != 0 or int(tile_elev[start_i]) <= 0 or tile_type[start_i] == Tile.WATER:
				continue
			var massif: Array[Vector2i] = _collect_massif_component(c, r, visited)
			if not _build_massif_paths(massif):
				_flatten_massif(massif)

func _collect_massif_component(c: int, r: int, visited: PackedByteArray) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var queue: Array[Vector2i] = [Vector2i(c, r)]
	visited[r * MAP_COLS + c] = 1
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		out.append(cell)
		for dir: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var nc: int = cell.x + dir.x
			var nr: int = cell.y + dir.y
			if nc < 0 or nr < 0 or nc >= MAP_COLS or nr >= MAP_ROWS:
				continue
			var ni := nr * MAP_COLS + nc
			if visited[ni] != 0 or int(tile_elev[ni]) <= 0 or tile_type[ni] == Tile.WATER:
				continue
			visited[ni] = 1
			queue.append(Vector2i(nc, nr))
	return out

func _build_massif_paths(cells: Array[Vector2i]) -> bool:
	var entries: Array[Vector3i] = _find_massif_entries(cells)
	if entries.is_empty():
		return false
	var cell_set := {}
	for cell: Vector2i in cells:
		cell_set[cell] = true
	var peaks: Array = _collect_peak_plateaus(cells, cell_set)
	if peaks.is_empty():
		return false
	var ramp_plan := {}
	for plateau_any in peaks:
		var plateau: Array[Vector2i] = []
		for cell_any in plateau_any:
			plateau.append(cell_any)
		if not _build_paths_to_plateau(plateau, entries, cell_set, ramp_plan):
			return false
	for key_any in ramp_plan.keys():
		var key_i: int = int(key_any)
		tile_ramp[key_i] = int(ramp_plan[key_i])
	return true

func _find_massif_entries(cells: Array[Vector2i]) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var seen := {}
	for cell: Vector2i in cells:
		if get_elev(cell.x, cell.y) != 1:
			continue
		for dir: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var nc: int = cell.x + dir.x
			var nr: int = cell.y + dir.y
			if nc < 0 or nr < 0 or nc >= MAP_COLS or nr >= MAP_ROWS:
				continue
			var ni := nr * MAP_COLS + nc
			if tile_type[ni] == Tile.WATER or int(tile_elev[ni]) != 0:
				continue
			var cand := Vector3i(cell.x, cell.y, _ramp_dir_from_delta(dir.x, dir.y))
			if seen.has(cand):
				continue
			seen[cand] = true
			out.append(cand)
	return out

func _collect_peak_plateaus(cells: Array[Vector2i], cell_set: Dictionary) -> Array:
	var peak_set := {}
	for cell: Vector2i in cells:
		var elev: int = get_elev(cell.x, cell.y)
		var has_higher := false
		for dir: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var nxt: Vector2i = cell + dir
			if not cell_set.has(nxt):
				continue
			if get_elev(nxt.x, nxt.y) > elev:
				has_higher = true
				break
		if not has_higher:
			peak_set[cell] = true
	var seen := {}
	var out: Array = []
	for cell: Vector2i in cells:
		if not peak_set.has(cell) or seen.has(cell):
			continue
		var plateau: Array[Vector2i] = []
		var queue: Array[Vector2i] = [cell]
		seen[cell] = true
		var peak_elev: int = get_elev(cell.x, cell.y)
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			plateau.append(cur)
			for dir: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var nxt: Vector2i = cur + dir
				if not peak_set.has(nxt) or seen.has(nxt):
					continue
				if get_elev(nxt.x, nxt.y) != peak_elev:
					continue
				seen[nxt] = true
				queue.append(nxt)
		out.append(plateau)
	return out

func _build_paths_to_plateau(plateau: Array[Vector2i], entries: Array[Vector3i], cell_set: Dictionary, ramp_plan: Dictionary) -> bool:
	var target_set := {}
	var target_center := Vector2.ZERO
	for cell: Vector2i in plateau:
		target_set[cell] = true
		target_center += Vector2(cell.x + 0.5, cell.y + 0.5)
	target_center /= maxf(1.0, float(plateau.size()))
	var remaining: Array[Vector3i] = []
	for entry_copy: Vector3i in entries:
		remaining.append(entry_copy)
	var chosen: Array[Vector3i] = []
	var used_cells := {}
	var built: int = 0
	while built < 1 and not remaining.is_empty():
		var best_idx: int = -1
		var best_score: float = -1000000000.0
		for idx in range(remaining.size()):
			var cand: Vector3i = remaining[idx]
			var start := Vector2i(cand.x, cand.y)
			var duplicate_start := false
			for other: Vector3i in chosen:
				if other.x == cand.x and other.y == cand.y:
					duplicate_start = true
					break
			if duplicate_start:
				continue
			var start_i: int = start.y * MAP_COLS + start.x
			var existing_dir := int(ramp_plan.get(start_i, Ramp.NONE))
			if existing_dir != Ramp.NONE and existing_dir != cand.z:
				continue
			var score: float = _entry_candidate_score(cand, chosen, target_center)
			if score > best_score:
				best_score = score
				best_idx = idx
		if best_idx == -1:
			break
		var entry: Vector3i = remaining[best_idx]
		remaining.remove_at(best_idx)
		var path: Array[Vector2i] = _find_massif_path(entry, target_set, cell_set, ramp_plan, used_cells)
		if path.is_empty():
			continue
		_commit_massif_path(entry, path, ramp_plan, used_cells)
		chosen.append(entry)
		built += 1
	return built >= 1

func _entry_candidate_score(cand: Vector3i, chosen: Array[Vector3i], target_center: Vector2) -> float:
	var pos := Vector2(cand.x + 0.5, cand.y + 0.5)
	if chosen.is_empty():
		return pos.distance_squared_to(target_center)
	var min_dist: float = INF
	for other: Vector3i in chosen:
		var other_pos := Vector2(other.x + 0.5, other.y + 0.5)
		min_dist = minf(min_dist, pos.distance_squared_to(other_pos))
	return min_dist * 100.0 + pos.distance_squared_to(target_center)

func _find_massif_path(entry: Vector3i, target_set: Dictionary, cell_set: Dictionary, ramp_plan: Dictionary, used_cells: Dictionary) -> Array[Vector2i]:
	var start := Vector2i(entry.x, entry.y)
	if target_set.has(start):
		return [start]
	var open: Array[Vector2i] = [start]
	var open_has := {}
	open_has[start] = true
	var closed := {}
	var came := {}
	var g_cost := {}
	g_cost[start] = 0.0
	while not open.is_empty():
		var best_idx: int = 0
		var current: Vector2i = open[0]
		var best_cost: float = float(g_cost.get(current, INF))
		for i in range(1, open.size()):
			var cand: Vector2i = open[i]
			var cand_cost: float = float(g_cost.get(cand, INF))
			if cand_cost < best_cost or (is_equal_approx(cand_cost, best_cost) and get_elev(cand.x, cand.y) > get_elev(current.x, current.y)):
				best_idx = i
				current = cand
				best_cost = cand_cost
		open.remove_at(best_idx)
		open_has.erase(current)
		if target_set.has(current):
			return _reconstruct_cell_path(came, current)
		closed[current] = true
		var cur_e: int = get_elev(current.x, current.y)
		for dir: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var nxt: Vector2i = current + dir
			if not cell_set.has(nxt) or closed.has(nxt):
				continue
			var nxt_e: int = get_elev(nxt.x, nxt.y)
			if nxt_e < cur_e or nxt_e > cur_e + 1:
				continue
			if nxt_e > cur_e:
				var need_dir: int = _ramp_dir_from_delta(current.x - nxt.x, current.y - nxt.y)
				var nxt_i: int = nxt.y * MAP_COLS + nxt.x
				var existing_dir := int(ramp_plan.get(nxt_i, Ramp.NONE))
				if existing_dir != Ramp.NONE and existing_dir != need_dir:
					continue
			var step_cost: float = 1.0
			if used_cells.has(nxt):
				step_cost += 6.0
			if nxt_e == cur_e:
				step_cost += 0.18
			var cand_g: float = best_cost + step_cost
			if cand_g >= float(g_cost.get(nxt, INF)):
				continue
			came[nxt] = current
			g_cost[nxt] = cand_g
			if not open_has.has(nxt):
				open.append(nxt)
				open_has[nxt] = true
	return []

func _reconstruct_cell_path(came: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came.has(current):
		var prev: Vector2i = came[current]
		current = prev
		path.push_front(current)
	return path

func _commit_massif_path(entry: Vector3i, path: Array[Vector2i], ramp_plan: Dictionary, used_cells: Dictionary) -> void:
	var start := Vector2i(entry.x, entry.y)
	ramp_plan[start.y * MAP_COLS + start.x] = entry.z
	used_cells[start] = true
	for i in range(1, path.size()):
		var prev: Vector2i = path[i - 1]
		var cur: Vector2i = path[i]
		used_cells[cur] = true
		if get_elev(cur.x, cur.y) > get_elev(prev.x, prev.y):
			ramp_plan[cur.y * MAP_COLS + cur.x] = _ramp_dir_from_delta(prev.x - cur.x, prev.y - cur.y)

func _flatten_massif(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		var i := cell.y * MAP_COLS + cell.x
		tile_elev[i] = 0
		tile_type[i] = Tile.GRASS
		tile_ramp[i] = Ramp.NONE

func _ramp_dir_from_delta(dx: int, dy: int) -> int:
	if dx == 0 and dy == -1: return Ramp.NORTH
	if dx == 1 and dy == 0: return Ramp.EAST
	if dx == 0 and dy == 1: return Ramp.SOUTH
	return Ramp.WEST


func _river_center_south(col: float) -> float:
	return 64.0 + noise_river.get_noise_2d(col, 0.0) * 11.5 + noise_b.get_noise_2d(col * 0.6, 19.0) * 3.0


func _river_center_north(col: float) -> float:
	return 26.0 + noise_river.get_noise_2d(col, 91.0) * 7.5 + noise_a.get_noise_2d(col * 0.55, 47.0) * 2.5

func get_tile(c: int, r: int) -> int:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS: return Tile.GRASS
	return tile_type[r * MAP_COLS + c]

func get_elev(c: int, r: int) -> int:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS: return 0
	return tile_elev[r * MAP_COLS + c]

func get_ramp(c: int, r: int) -> int:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS: return Ramp.NONE
	return tile_ramp[r * MAP_COLS + c]

func is_water(c: int, r: int) -> bool:
	return get_tile(c, r) == Tile.WATER

func bridge_tile_at(c: int, r: int) -> bool:
	return get_tile(c, r) == Tile.BRIDGE

func get_bridge_hp(c: int, r: int) -> float:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS:
		return 0.0
	return bridge_hp[r * MAP_COLS + c]

func damage_bridge(c: int, r: int, damage: float) -> bool:
	if not bridge_tile_at(c, r) or damage <= 0.0:
		return false
	var i := r * MAP_COLS + c
	bridge_hp[i] = maxf(0.0, bridge_hp[i] - damage)
	if bridge_hp[i] > 0.0:
		return false
	tile_type[i] = Tile.WATER
	tile_elev[i] = 0
	tile_ramp[i] = Ramp.NONE
	bridge_hp[i] = 0.0
	emit_signal("terrain_changed")
	return true

func move_speed_mult_at(wx: float, wy: float) -> float:
	var c := clampi(int(wx), 0, MAP_COLS - 1)
	var r := clampi(int(wy), 0, MAP_ROWS - 1)
	return SWAMP_SPEED_MUL if get_tile(c, r) == Tile.SWAMP else 1.0

func elev_units_to_lift(elev_units: float) -> float:
	return elev_units * ELEV_STEP_PX

func corner_elev_units(c: int, r: int, corner: int) -> float:
	var elev := float(get_elev(c, r))
	var ramp := get_ramp(c, r)
	if ramp == Ramp.NONE or elev <= 0.0:
		return elev
	match ramp:
		Ramp.NORTH:
			return elev - 1.0 if corner == Corner.NW or corner == Corner.NE else elev
		Ramp.EAST:
			return elev - 1.0 if corner == Corner.NE or corner == Corner.SE else elev
		Ramp.SOUTH:
			return elev - 1.0 if corner == Corner.SE or corner == Corner.SW else elev
		Ramp.WEST:
			return elev - 1.0 if corner == Corner.SW or corner == Corner.NW else elev
		_:
			return elev

func surface_elev_units_at(wx: float, wy: float) -> float:
	var cx := clampf(wx, 0.0, MAP_COLS - 0.001)
	var cy := clampf(wy, 0.0, MAP_ROWS - 0.001)
	var c := clampi(int(cx), 0, MAP_COLS - 1)
	var r := clampi(int(cy), 0, MAP_ROWS - 1)
	var lx := clampf(cx - float(c), 0.0, 1.0)
	var ly := clampf(cy - float(r), 0.0, 1.0)
	var nw := corner_elev_units(c, r, Corner.NW)
	var ne := corner_elev_units(c, r, Corner.NE)
	var sw := corner_elev_units(c, r, Corner.SW)
	var se := corner_elev_units(c, r, Corner.SE)
	var north := lerpf(nw, ne, lx)
	var south := lerpf(sw, se, lx)
	return lerpf(north, south, ly)

func surface_lift_at(wx: float, wy: float) -> float:
	return elev_units_to_lift(surface_elev_units_at(wx, wy))

func can_move_between_cells(c1: int, r1: int, c2: int, r2: int, max_climb_up_steps: int = 0) -> bool:
	if not passable(c1, r1) or not passable(c2, r2):
		return false
	var dc := c2 - c1
	var dr := r2 - r1
	if abs(dc) + abs(dr) != 1:
		return false
	var e1 := get_elev(c1, r1)
	var e2 := get_elev(c2, r2)
	if e1 == e2:
		return true
	if abs(e1 - e2) != 1:
		return false
	if max_climb_up_steps > 0 and abs(e2 - e1) <= 1:
		return true
	if e2 > e1:
		return _ramp_dir_from_delta(-dc, -dr) == get_ramp(c2, r2)
	return _ramp_dir_from_delta(dc, dr) == get_ramp(c1, r1)

func can_move_between_points(ax: float, ay: float, bx: float, by: float, max_climb_up_steps: int = 0) -> bool:
	var c1 := clampi(int(ax), 0, MAP_COLS - 1)
	var r1 := clampi(int(ay), 0, MAP_ROWS - 1)
	var c2 := clampi(int(bx), 0, MAP_COLS - 1)
	var r2 := clampi(int(by), 0, MAP_ROWS - 1)
	if c1 == c2 and r1 == r2:
		return true
	var dc := c2 - c1
	var dr := r2 - r1
	if abs(dc) > 1 or abs(dr) > 1:
		return false
	if dc != 0 and dr != 0:
		return (
			can_move_between_cells(c1, r1, c1 + dc, r1, max_climb_up_steps) and
			can_move_between_cells(c1 + dc, r1, c2, r2, max_climb_up_steps)
		) or (
			can_move_between_cells(c1, r1, c1, r1 + dr, max_climb_up_steps) and
			can_move_between_cells(c1, r1 + dr, c2, r2, max_climb_up_steps)
		)
	return can_move_between_cells(c1, r1, c2, r2, max_climb_up_steps)

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

func tile_top_poly(c: int, r: int) -> PackedVector2Array:
	return PackedVector2Array([
		grid_to_world(c, r, elev_units_to_lift(corner_elev_units(c, r, Corner.NW))),
		grid_to_world(c + 1, r, elev_units_to_lift(corner_elev_units(c, r, Corner.NE))),
		grid_to_world(c + 1, r + 1, elev_units_to_lift(corner_elev_units(c, r, Corner.SE))),
		grid_to_world(c, r + 1, elev_units_to_lift(corner_elev_units(c, r, Corner.SW))),
	])

func tile_at(sx: float, sy: float) -> Vector2i:
	var wp := screen_to_world(Vector2(sx, sy))
	var g := world_to_grid(wp.x, wp.y)
	var pad := ceili(float(MAX_HILL_ELEV) * ELEV_STEP_PX / (BASE_TILE_H * 0.5)) + 2
	var sc := clampi(int(floor(g.x)) - pad, 0, MAP_COLS - 1)
	var ec := clampi(int(floor(g.x)) + pad, 0, MAP_COLS - 1)
	var sr := clampi(int(floor(g.y)) - pad, 0, MAP_ROWS - 1)
	var er := clampi(int(floor(g.y)) + pad, 0, MAP_ROWS - 1)
	var best := Vector2i(-1, -1)
	var best_elev := -1.0
	for r in range(sr, er + 1):
		for c in range(sc, ec + 1):
			var poly := tile_top_poly(c, r)
			if not Geometry2D.is_point_in_polygon(wp, poly):
				continue
			var avg_elev := (
				corner_elev_units(c, r, Corner.NW) +
				corner_elev_units(c, r, Corner.NE) +
				corner_elev_units(c, r, Corner.SE) +
				corner_elev_units(c, r, Corner.SW)
			) * 0.25
			if avg_elev >= best_elev:
				best = Vector2i(c, r)
				best_elev = avg_elev
	if best != Vector2i(-1, -1):
		return best
	if g.x < 0 or g.y < 0 or g.x >= MAP_COLS or g.y >= MAP_ROWS:
		return Vector2i(-1, -1)
	return Vector2i(int(g.x), int(g.y))

# ── Fog helpers ──────────────────────────────────────────────────────────────
func _fi(c: int, r: int) -> int:
	return r * MAP_COLS + c

func fvis(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS: return false
	if cheat_reveal_all: return true
	return fog_vis[_fi(c, r)] != 0

func fexp(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= MAP_COLS or r >= MAP_ROWS: return false
	if cheat_reveal_all: return true
	return fog_exp[_fi(c, r)] != 0

func fog_set(c: int, r: int) -> void:
	var i := _fi(c, r)
	fog_vis[i] = 1; fog_exp[i] = 1

func fog_reset_vis() -> void:
	if cheat_reveal_all:
		fog_vis.fill(1)
	else:
		fog_vis.fill(0)

func enable_reveal_all_cheat() -> bool:
	if cheat_reveal_all:
		return false
	cheat_reveal_all = true
	fog_vis.fill(1)
	fog_exp.fill(1)
	fog_revision += 1
	return true

func enable_super_tank_cheat() -> bool:
	if cheat_super_tanks:
		return false
	cheat_super_tanks = true
	return true

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
	var base_elev := get_elev(c, r)
	for rr in range(r, r + h):
		for cc in range(c, c + w):
			var tt: int = get_tile(cc, rr)
			if is_water(cc, rr) or tt == Tile.BRIDGE or get_ramp(cc, rr) != Ramp.NONE or get_elev(cc, rr) != base_elev:
				return false
	for s: Structure in get_structures():
		if not (c + w <= s.grid_col or c >= s.grid_col + s.grid_w or r + h <= s.grid_row or r >= s.grid_row + s.grid_h):
			return false
	for u: Unit in get_units():
		if u.gx >= c and u.gx < c + w and u.gy >= r and u.gy < r + h:
			return false
	return true

func passable(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < MAP_COLS and r < MAP_ROWS and struct_at(c, r) == null and not is_water(c, r)

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
		if not u.visible:
			continue
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
