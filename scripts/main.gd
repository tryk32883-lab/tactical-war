extends Node2D

# Срез: карта 300 x 300 м, пехота и здания.
# 1 метр = PX пикселей мира.

const PX := 4.0
const MAP_SIZE := 300.0
const SOLDIERS_PER_TEAM := 50
const SPEED := 3.0            # м/с, базовая скорость пехоты
const SELECT_RADIUS := 3.0    # м, радиус выбора отряда касанием
const GRID_STEP := 10.0       # м, шаг линий сетки
const TAP_MAX_MOVE := 15.0    # px экрана, дальше — это уже перетаскивание

var cam: Camera2D
var soldiers: Array = []      # Dictionary: pos, target, has_target, team, selected
var touches: Dictionary = {}  # index -> screen position
var moved_during_touch := 0.0
var last_pinch_dist := 0.0


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
			var y := randf_range(20.0, 280.0)
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
		var to_target: Vector2 = s["target"] - s["pos"]
		var step := SPEED * delta
		if to_target.length() <= step:
			s["pos"] = s["target"]
			s["has_target"] = false
		else:
			s["pos"] += to_target.normalized() * step
	queue_redraw()


func _draw() -> void:
	var view_size := get_viewport_rect().size / cam.zoom
	var view := Rect2(cam.position - view_size * 0.5, view_size)
	var map_rect := Rect2(0, 0, MAP_SIZE * PX, MAP_SIZE * PX)

	# Земля
	draw_rect(map_rect, Color(0.25, 0.3, 0.2))

	# Сетка: только видимые линии, шаг 10 м
	var grid_col := Color(1, 1, 1, 0.08)
	var step_px := GRID_STEP * PX
	var x_start := floor(view.position.x / step_px) * step_px
	var x := x_start
	while x <= view.end.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), grid_col)
		x += step_px
	var y_start := floor(view.position.y / step_px) * step_px
	var y := y_start
	while y <= view.end.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), grid_col)
		y += step_px

	# Пехота (только видимая)
	for s in soldiers:
		var p: Vector2 = s["pos"] * PX
		if not view.grow(10.0).has_point(p):
			continue
		var color := Color(0.2, 0.5, 1.0) if s["team"] == 0 else Color(1.0, 0.3, 0.3)
		if s["has_target"]:
			draw_line(p, (s["target"] as Vector2) * PX, Color(1, 1, 1, 0.3), 1.0)
		draw_circle(p, 0.4 * PX, color)
		if s["selected"]:
			draw_arc(p, 0.9 * PX, 0.0, TAU, 16, Color(1, 1, 0), 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			touches[t.index] = t.position
			if touches.size() == 1:
				moved_during_touch = 0.0
			last_pinch_dist = 0.0
		else:
			var was_single := touches.size() == 1
			touches.erase(t.index)
			last_pinch_dist = 0.0
			if was_single and moved_during_touch < TAP_MAX_MOVE:
				_handle_tap(t.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		touches[d.index] = d.position
		if touches.size() == 1:
			cam.position -= d.relative / cam.zoom
			moved_during_touch += d.relative.length()
		elif touches.size() == 2:
			var keys := touches.keys()
			var dist: float = (touches[keys[0]] - touches[keys[1]]).length()
			if last_pinch_dist > 0.0 and dist > 0.0:
				cam.zoom *= dist / last_pinch_dist
				cam.zoom = cam.zoom.clamp(Vector2(0.5, 0.5), Vector2(4.0, 4.0))
			last_pinch_dist = dist


func _handle_tap(screen_pos: Vector2) -> void:
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var world_m := world / PX

	# 1) Тап по своему солдату — выбрать его (отменяя старый выбор)
	var hit := -1
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["team"] == 0 and (s["pos"] as Vector2).distance_to(world_m) <= SELECT_RADIUS:
			hit = i
			break
	if hit >= 0:
		_clear_selection()
		soldiers[hit]["selected"] = true
		return

	# 2) Тап по земле — приказ движения выбранным
	var selected_indices: Array = []
	for i in soldiers.size():
		if soldiers[i]["selected"]:
			selected_indices.append(i)
	if selected_indices.is_empty():
		return

	var cols := int(ceil(sqrt(float(selected_indices.size()))))
	for n in selected_indices.size():
		var idx: int = selected_indices[n]
		var offset := Vector2(n % cols, n / cols) * 1.5
		soldiers[idx]["target"] = world_m + offset - Vector2(cols, cols) * 0.75
		soldiers[idx]["has_target"] = true


func _clear_selection() -> void:
	for s in soldiers:
		s["selected"] = false
