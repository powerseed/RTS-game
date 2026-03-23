class_name DrawHelpers
extends Node2D
## Shared drawing utilities for isometric rendering.

func _poly_fill(pts: Array, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), col)

func _poly_stroke(pts: Array, col: Color, w: float = 1.0) -> void:
	var pv := PackedVector2Array(pts)
	pv.append(pts[0])
	draw_polyline(pv, col, w)

func _ellipse_fill(center: Vector2, rx: float, ry: float, col: Color, segs: int = 28) -> void:
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * i / segs
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

func _ellipse_stroke(center: Vector2, rx: float, ry: float, col: Color, w: float = 1.0, segs: int = 28) -> void:
	var pts := PackedVector2Array()
	for i in segs + 1:
		var a := TAU * i / segs
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, w)

func _dashed_poly(pts: Array, col: Color, dash: float, gap: float, w: float) -> void:
	var all_pts := pts.duplicate()
	all_pts.append(pts[0])
	for i in all_pts.size() - 1:
		_dashed_seg(all_pts[i], all_pts[i + 1], col, dash, gap, w)

func _dashed_seg(a: Vector2, b: Vector2, col: Color, dash: float, gap: float, w: float) -> void:
	var dir := b - a
	var total := dir.length()
	if total < 0.01: return
	dir /= total
	var pos := 0.0
	var drawing := true
	while pos < total:
		var seg := dash if drawing else gap
		var end := minf(pos + seg, total)
		if drawing:
			draw_line(a + dir * pos, a + dir * end, col, w)
		pos = end
		drawing = not drawing

func _dashed_rect(rect: Rect2, col: Color, dash: float, gap: float, w: float) -> void:
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	_dashed_poly([tl, tr, br, bl], col, dash, gap, w)

func _fp(c: float, r: float, w: float, h: float, z: float) -> Dictionary:
	return {
		"nw": Game.grid_to_world(c, r, z), "ne": Game.grid_to_world(c + w, r, z),
		"se": Game.grid_to_world(c + w, r + h, z), "sw": Game.grid_to_world(c, r + h, z),
	}

func _off_pts(pts: Array, ox: float, oy: float) -> Array:
	var out := []
	for p in pts: out.append(Vector2(p.x + ox, p.y + oy))
	return out

func _mix(a: Vector2, b: Vector2, t: float) -> Vector2:
	return a + (b - a) * t

func _prism(base: Dictionary, h: float, top_c: Color, east_c: Color, south_c: Color) -> void:
	var t := {
		"nw": Vector2(base.nw.x, base.nw.y - h),
		"ne": Vector2(base.ne.x, base.ne.y - h),
		"se": Vector2(base.se.x, base.se.y - h),
		"sw": Vector2(base.sw.x, base.sw.y - h),
	}
	_poly_fill([t.sw, t.se, base.se, base.sw], south_c)
	_poly_fill([t.ne, t.se, base.se, base.ne], east_c)
	_poly_fill([t.nw, t.ne, t.se, t.sw], top_c)
	_poly_stroke([t.nw, t.ne, t.se, t.sw], Color(0.094, 0.118, 0.129, 0.34), 1)

func _progress_bar(x: float, y: float, w: float, ratio: float) -> void:
	draw_rect(Rect2(x, y, w, 8), Color(0.059, 0.071, 0.090, 0.85))
	draw_rect(Rect2(x + 1, y + 1, (w - 2) * clampf(ratio, 0, 1), 6), Color(0.949, 0.749, 0.302))
	draw_rect(Rect2(x, y, w, 8), Color(1, 0.91, 0.682, 0.45), false, 1)
