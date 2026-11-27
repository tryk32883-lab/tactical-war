extends Node2D

# Срез: карта 300 x 300 м, пехота и дома.
# 1 метр = PX пикселей мира.

const PX: float = 4.0
const MAP_SIZE: float = 300.0
const SOLDIERS_PER_TEAM: int = 50
const SPEED: float = 3.0
const SELECT_RADIUS: float = 3.0
const GRID_STEP: float = 10.0
const TAP_MAX_MOVE: float = 15.0
const CHUNK_SIZE: float = 50.0
const SPRITE_SIZE: float = 14.0
const FRAME_TIME: float = 0.12
const HOUSE_COUNT: int = 12

const INFANTRY_TEX_PATH: String = "res://assets/infantry.png"
const HOUSE_TEX_PATH: String = "res://assets/house_tiles.png"
const CELL: float = 64.0
const HOUSE_W: float = 104.0
const HOUSE_H: float = 80.0
const HOUSE_SCALE: float = 0.5

# Кадры листа (колонка, строка), считаем с нуля.
const STAND_ARMED: Vector2i = Vector2i(5, 8)
const PRONE_ARMED: Vector2i = Vector2i(0, 7)
const SHOOT_PRONE: Vector2i = Vector2i(0, 8)
const SUPPRESSED: Vector2i = Vector2i(5, 0)
const DEAD: Vector2i = Vector2i(5, 2)
const WALK_ARMED: Array = [
	Vector2i(0, 9), Vector2i(1, 9), Vector2i(2, 9),
	Vector2i(3, 9), Vector2i(4, 9), Vector2i(5, 9),
]
const CRAWL_ARMED: Array = [
	Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7),
	Vector2i(4, 7), Vector2i(5, 7),
]
const WOUNDED: Array = [
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
]

var cam: Camera2D
var infantry_tex: Texture2D
var house_tex: Texture2D
var soldiers: Array = []
var houses: Array = []
var touches: Dictionary = {}
var moved_during_touch: float = 0.0
var last_pinch_dist: float = 0.0


func _ready() -> void:
	infantry_tex = load(INFANTRY_TEX_PATH) as Texture2D
	house_tex = load(HOUSE_TEX_PATH) as Texture2D
	if infantry_tex == null:
		push_error("Нет спрайта пехоты: " + INFANTRY_TEX_PATH)
	if house_tex == null:
		push_error("Нет спрайтов домов: " + HOUSE_TEX_PATH)

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
			var r: float = randf()
			var st: String = "stand"
			if r < 0.02:
				st = "dead"
			elif r < 0.06:
				st = "wounded"
			elif r < 0.12:
				st = "suppressed"
			elif r < 0.20:
				st = "prone"
			soldiers.append({
				"pos": Vector2(x, y),
				"target": Vector2.ZERO,
				"has_target": false,
				"team": team,
				"selected": false,
				"state": st,
				"anim_t": randf() * 2.0,
			})

	for i in HOUSE_COUNT:
		houses.append({
			"pos": Vector2(randf_range(110.0, 190.0), randf_range(20.0, 280.0)),
			"variant": i % 4,
		})


func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / CHUNK_SIZE), floor(p.y / CHUNK_SIZE))


func get_frames(s: Dictionary) -> Array:
	var moving: bool = s["has_target"]
	match s["state"]:
		"dead":
			return [DEAD]
		"wounded":
			return WOUNDED
		"prone":
			if moving:
				return CRAWL_ARMED
			return [PRONE_ARMED]
		"suppressed":
			if moving:
				return CRAWL_ARMED
			return [SUPPRESSED]
		_:
			if moving:
				return WALK_ARMED
			return [STAND_ARMED]


func _process(delta: float) -> void:
	for s in soldiers:
		s["anim_t"] = float(s["anim_t"]) + delta
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

	draw_rect(map_rect, Color(0.25, 0.3, 0.2))

	var grid_col: Color = Color(1, 1, 1, 0.05)
	var step_px: float = GRID_STEP * PX
	var x: float = floor(view.position.x / step_px) * step_px
	while x <= view.end.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), grid_col)
		x += step_px
	var y: float = floor(view.position.y / step_px) * step_px
	while y <= view.end.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), grid_col)
		y += step_px

	if house_tex != null:
		for h in houses:
			var hp: Vector2 = (h["pos"] as Vector2) * PX
			var size: Vector2 = Vector2(HOUSE_W, HOUSE_H) * HOUSE_SCALE
			if not view.grow(size.length()).has_point(hp):
				continue
			var v: int = h["variant"]
			var src: Rect2 = Rect2((v % 2) * HOUSE_W, (v / 2) * HOUSE_H, HOUSE_W, HOUSE_H)
			var dest: Rect2 = Rect2(hp - size * 0.5, size)
			draw_texture_rect_region(house_tex, dest, src)

	for s in soldiers:
		var p: Vector2 = (s["pos"] as Vector2) * PX
		if not view.grow(20.0).has_point(p):
			continue
		var frames: Array = get_frames(s)
		var idx: int = int(float(s["anim_t"]) / FRAME_TIME) % frames.size()
		var cell: Vector2i = frames[idx]
		if infantry_tex != null:
			var src_s: Rect2 = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
			var dest_s: Rect2 = Rect2(p - Vector2.ONE * SPRITE_SIZE * 0.5, Vector2.ONE * SPRITE_SIZE)
			draw_texture_rect_region(infantry_tex, dest_s, src_s)
		else:
			var color: Color = Color(0.2, 0.5, 1.0) if s["team"] == 0 else Color(1.0, 0.3, 0.3)
			draw_circle(p, 0.4 * PX, color)
		if s["has_target"]:
			var t: Vector2 = (s["target"] as Vector2) * PX
			draw_line(p, t, Color(1, 1, 1, 0.3), 1.0)
		if s["selected"]:
			draw_arc(p, SPRITE_SIZE * 0.6, 0.0, TAU, 16, Color(1, 1, 0), 1.5)


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

	var hit: int = -1
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["team"] != 0 or s["state"] == "dead":
			continue
		var spos: Vector2 = s["pos"] as Vector2
		if spos.distance_to(world_m) <= SELECT_RADIUS:
			hit = i
			break
	if hit >= 0:
		_clear_selection()
		soldiers[hit]["selected"] = true
		return

	var selected: Array = []
	for i in soldiers.size():
		var s2: Dictionary = soldiers[i]
		if s2["selected"] and s2["state"] != "dead" and s2["state"] != "wounded":
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


