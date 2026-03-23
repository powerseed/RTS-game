# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Field Foundry RTS** — a 2D isometric real-time strategy game built in Godot 4.6 with pure GDScript. All rendering is procedural (immediate-mode `_draw()` with polygons/shapes, no sprites or atlases). No external plugins or dependencies.

## Running the Project

Open in Godot 4.6 editor and press F5. Main scene: `res://scenes/main.tscn`. There is no build system, test framework, or CI pipeline.

## Architecture

### Scene Tree (main.tscn)

```
Main (Node2D)  →  scripts/main.gd   — game loop, input, combat, movement, fog
├── Camera2D                         — isometric viewport, zoom, panning
├── Terrain (Node2D)                 — procedural isometric ground tiles
├── Entities (Node2D, y_sort)        — all units and structures live here
├── Overlay (Node2D)                 — fog of war, weapon tracers, build ghost
└── UILayer (CanvasLayer)
    └── HUD (Control)                — build menu, selection panels, status bar
```

### Autoload Singleton: `Game` (scripts/game_data.gd)

Central hub for constants, coordinate math, fog system, and mutable game state. Referenced everywhere as `Game.xxx`. Key responsibilities:
- **Coordinate helpers**: `grid_to_world()`, `world_to_grid()`, `screen_to_grid()`, `tile_at()` — all game logic uses grid coords; display uses world/screen
- **Fog of war**: `fog_vis`/`fog_exp` PackedByteArrays, queried with `fvis()`/`fexp()`
- **Game state**: selections, camera position, build mode, drag state
- **Scene tree queries**: `get_units()`, `get_structures()`, `struct_at()`, `unit_at_screen()` — all use Godot groups, not manual arrays
- **Building/unit stats**: `BLDG` dictionary, combat/supply constants

### Entity Hierarchy

```
DrawHelpers (Node2D)   — shared isometric drawing: _prism(), _poly_fill(), _ellipse_fill(), etc.
├── Unit               — base movable entity (gx/gy grid position, heading, health, supply)
│   ├── Tank           — combat unit, auto-targets enemies, fires with cooldown
│   └── Truck          — logistics unit, radius-based resupply, follows targets
└── Structure          — base building (grid_col/grid_row, grid_w/grid_h)
    ├── TankPlant      — produces tanks via Timer node
    └── SupplyDepot    — stores supplies, can dispatch trucks
```

Each entity type has a matching PackedScene in `scenes/` (tank.tscn, truck.tscn, etc.).

### Communication Patterns

- **Signals over direct calls**: `Game.unit_spawned`, `Game.unit_died`, `Game.structure_placed`; HUD emits `build_requested`; TankPlant emits `tank_produced`
- **Groups for queries**: entities self-register into groups (`units`, `structures`, `player_units`, `enemy_units`) in `_ready()`
- **No Godot physics**: collision uses custom spatial bucketing (`COL_CELL = 1.2`) with separation iterations

### Coordinate System

Isometric projection with grid-based game logic:
- **Grid**: 120x100 tiles, all gameplay in grid coordinates (float gx/gy)
- **World**: isometric pixel space via `grid_to_world(gx, gy, gz)` — gz provides vertical lift for depth
- **Screen**: viewport pixels, converted through `Camera2D` transform
- **Tile dimensions**: 78x39 px base, 28px slab height

### Game Loop (main.gd `_process`)

Each frame: camera update → unit movement/supply → collision resolution → combat → remove dead → fog of war → UI refresh. Delta is clamped to 0.05s.

## Code Conventions

- **Type hints everywhere**: function signatures, variables, typed arrays (`Array[Node2D]`)
- **Class names on all entities**: `class_name Tank`, `class_name Unit`, etc.
- **Section dividers**: `# ═══...` separating major code sections
- **Constants**: `UPPER_SNAKE_CASE` in Game singleton
- **Null safety**: `is_instance_valid()` before using stored references
- **World-space drawing**: entities use `draw_set_transform(-position, angle)` so draw calls use world coordinates directly
