extends Node2D

# Срез: карта 300 x 300 м, пехота и здания.
# 1 метр = PX пикселей мира.

const PX: float = 4.0
const MAP_SIZE: float = 300.0
const SOLDIERS_PER_TEAM: int = 50
const SPEED: float = 3.0
const SELECT_RADIUS: float = 3.0
const GRID_STEP: float = 10.0
const TAP_MAX_MOVE: float = 15.0

var cam: Camera2D
var soldiers: Array = []
var touches: Dictionary = {}
var moved_during_touch: float = 0.0
var last_pinch_dist: float = 0.0


func _ready() -> void:
	cam = Camera2D.new()
	cam.position = Vector2(MAP_SIZE, MAP_SIZE) * PX * 0.5
	cam.zoom = Vector2(1.5, 1.5)
	add_child(cam)
	cam.make_current()

	for team in [0, 1]:
		for i in SOLDIERS_PER_TEAM:
			var x: float
			if team == 0:
				x = randf_range(20.0, 80.0)
			else:
				x = randf_range(220.0, 280.0)
			var y: float = randf_range(20.0, 280.0)
			soldiers.append({
				"pos": Vector2(x, y),
				"target": Vector2.ZERO,
				"has_target": false,
				"team": team,
				"selected": false,
			})


func _process(delta: float) -> void:
	for s in soldiers:
		if not s["has_target"]:
			continue
		var pos: Vector2 = s["pos"] as Vector2
		var target: Vector2 = s["target"] as Vector2
		var to_target: Vector2 = target - pos
		var step: float = SPEED * delta
		if to_target.length() <= step:
			s["pos"] = target
			s["has_target"] = false
		else:
			s["pos"] = pos + to_target.normalized() * step
	queue_redraw()


func _draw() -> void:
	var view_size: Vector2 = get_viewport_rect().size / cam.zoom
	var view: Rect2 = Rect2(cam.position - view_size * 0.5, view_size)
	var map_rect: Rect2 = Rect2(0.0, 0.0, MAP_SIZE * PX, MAP_SIZE * PX)

	# Земля
	draw_rect(map_rect, Color(0.25, 0.3, 0.2))

	# Сетка: только видимые линии, шаг 10 м
	var grid_col: Color = Color(1, 1, 1, 0.08)
	var step_px: float = GRID_STEP * PX
	var x: float = floorf(view.position.x / step_px) * step_px
	while x <= view.end.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), grid_col)
		x += step_px
	var y: float = floorf(view.position.y / step_px) * step_px
	while y <= view.end.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), grid_col)
		y += step_px

	# Пехота (только видимая)
	for s in soldiers:
		var p: Vector2 = (s["pos"] as Vector2) * PX
		if not view.grow(10.0).has_point(p):
			continue
		var color: Color = Color(0.2, 0.5, 1.0) if s["team"] == 0 else Color(1.0, 0.3, 0.3)
		if s["has_target"]:
			var t: Vector2 = (s["target"] as Vector2) * PX
			draw_line(p, t, Color(1, 1, 1, 0.3), 1.0)
		draw_circle(p, 0.4 * PX, color)
		if s["selected"]:
			draw_arc(p, 0.9 * PX, 0.0, TAU, 16, Color(1, 1, 0), 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			touches[t.index] = t.position
			if touches.size() == 1:
				moved_during_touch = 0.0
			last_pinch_dist = 0.0
		else:
			var was_single: bool = touches.size() == 1
			touches.erase(t.index)
			last_pinch_dist = 0.0
			if was_single and moved_during_touch < TAP_MAX_MOVE:
				_handle_tap(t.position)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event as InputEventScreenDrag
		touches[d.index] = d.position
		if touches.size() == 1:
			cam.position -= d.relative / cam.zoom
			moved_during_touch += d.relative.length()
		elif touches.size() == 2:
			var keys: Array = touches.keys()
			var p0: Vector2 = touches[keys[0]]
			var p1: Vector2 = touches[keys[1]]
			var dist: float = (p0 - p1).length()
			if last_pinch_dist > 0.0 and dist > 0.0:
				var z: float = dist / last_pinch_dist
				cam.zoom = (cam.zoom * z).clamp(Vector2(0.5, 0.5), Vector2(4.0, 4.0))
			last_pinch_dist = dist


func _handle_tap(screen_pos: Vector2) -> void:
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var world_m: Vector2 = world / PX

	# 1) Тап по своему солдату — выбрать его
	var hit: int = -1
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		var spos: Vector2 = s["pos"] as Vector2
		if s["team"] == 0 and spos.distance_to(world_m) <= SELECT_RADIUS:
			hit = i
			break
	if hit >= 0:
		_clear_selection()
		soldiers[hit]["selected"] = true
		return

	# 2) Тап по земле — приказ движения выбранным
	var selected: Array = []
	for i in soldiers.size():
		if soldiers[i]["selected"]:
			selected.append(i)
	if selected.is_empty():
		return

	var cols: int = int(ceil(sqrt(float(selected.size()))))
	for n in selected.size():
		var idx: int = selected[n]
		var offset: Vector2 = Vector2(float(n % cols), float(n / cols)) * 1.5
		soldiers[idx]["target"] = world_m + offset - Vector2(float(cols), float(cols)) * 0.75
		soldiers[idx]["has_target"] = true


func _clear_selection() -> void:
	for s in soldiers:
		s["selected"] = false

