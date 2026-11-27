extends Node2D

# Тактика: карта 600 x 600 м. 1 метр = PX пикселей мира.

const PX: float = 4.0
const MAP_SIZE: float = 600.0
const GRID_STEP: float = 10.0
const TAP_MAX_MOVE: float = 15.0
const SELECT_RADIUS: float = 3.0
const SPEED: float = 3.0
const SPRITE_SIZE: float = 14.0
const FRAME_TIME: float = 0.12
const START_PER_TEAM: int = 50
const MAX_SOLDIERS: int = 600
const SPAWN_INTERVAL: float = 0.12
const CHUNK: float = 20.0
const SHOOT_RANGE: float = 40.0
const SHOOT_COOLDOWN: float = 0.8
const HIT_CHANCE: float = 0.25
const TRACER_EVERY: int = 4
const TRACER_MAX: int = 200
const TRACER_SPEED: float = 2.5
const BUCKET_REBUILD: float = 0.25

const TERRAIN_CELL: float = 3.0
const TERRAIN_N: int = 200
const HEIGHT_MIN: float = -8.0
const HEIGHT_MAX: float = 12.0
const BRUSH_RADIUS: float = 6.0
const BRUSH_RATE: float = 6.0

const HOUSE_COUNT: int = 20
const HOUSE_W_M: float = 13.0
const HOUSE_H_M: float = 10.0
const HOUSE_W: float = 104.0
const HOUSE_H: float = 80.0

const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 64.0
const SHARP_ZOOM: float = 4.0
const BUTTON_ZOOM_STEP: float = 1.6

const INFANTRY_TEX_PATH: String = "res://assets/infantry.png"
const HOUSE_TEX_PATH: String = "res://assets/house_tiles.png"
const CELL: float = 64.0

const STAND_ARMED: Vector2i = Vector2i(5, 8)
const PRONE_ARMED: Vector2i = Vector2i(0, 7)
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

const MODE_NAMES: Array = ["Выбор", "Спавн", "Рельеф"]

var cam: Camera2D
var infantry_tex: Texture2D
var house_tex: Texture2D
var terrain_img: Image
var terrain_tex: ImageTexture
var terrain: PackedFloat32Array = PackedFloat32Array()
var terrain_dirty: bool = false
var soldiers: Array = []
var houses: Array = []
var tracers: Array = []
var buckets: Dictionary = {}
var bucket_timer: float = 0.0
var touches: Dictionary = {}
var moved_during_touch: float = 0.0
var last_pinch_dist: float = 0.0
var mode_index: int = 0
var spawn_team: int = 0
var brush_sign: float = 1.0
var brushing: bool = false
var brush_pos: Vector2 = Vector2.ZERO
var spawn_timer: float = 0.0
var mode_btn: Button
var extra_btn: Button


func _ready() -> void:
	infantry_tex = load(INFANTRY_TEX_PATH) as Texture2D
	house_tex = load(HOUSE_TEX_PATH) as Texture2D
	if infantry_tex == null:
		push_error("Нет спрайта пехоты")
	if house_tex == null:
		push_error("Нет спрайтов домов")

	_init_terrain()

	cam = Camera2D.new()
	cam.position = Vector2(MAP_SIZE, MAP_SIZE) * PX * 0.5
	cam.zoom = Vector2(1.5, 1.5)
	add_child(cam)
	cam.make_current()

	_make_ui()

	for team in [0, 1]:
		for i in START_PER_TEAM:
			var x: float = randf_range(40.0, 120.0) if team == 0 else randf_range(480.0, 560.0)
			_spawn_soldier(Vector2(x, randf_range(60.0, 540.0)), team)

	for i in HOUSE_COUNT:
		var variant: int = [0, 2, 3][i % 3]
		houses.append({
			"pos": Vector2(randf_range(160.0, 440.0), randf_range(60.0, 540.0)),
			"variant": variant,
			"occ0": 0,
			"occ1": 0,
		})


func _init_terrain() -> void:
	terrain.resize(TERRAIN_N * TERRAIN_N)
	for y in TERRAIN_N:
		for x in TERRAIN_N:
			var wx: float = (x + 0.5) * TERRAIN_CELL
			var wy: float = (y + 0.5) * TERRAIN_CELL
			terrain[y * TERRAIN_N + x] = 2.5 * sin(wx * 0.02) * cos(wy * 0.017)
	terrain_img = Image.create(TERRAIN_N, TERRAIN_N, false, Image.FORMAT_RGBA8)
	for y in TERRAIN_N:
		for x in TERRAIN_N:
			terrain_img.set_pixel(x, y, _height_color(terrain[y * TERRAIN_N + x]))
	terrain_tex = ImageTexture.create_from_image(terrain_img)


func _height_color(h: float) -> Color:
	var t: float = clamp((h - HEIGHT_MIN) / (HEIGHT_MAX - HEIGHT_MIN), 0.0, 1.0)
	return Color(0.2 + 0.25 * t, 0.3 + 0.12 * t, 0.17 + 0.08 * t)


func _height_at(p: Vector2) -> float:
	var cx: int = clamp(int(floor(p.x / TERRAIN_CELL)), 0, TERRAIN_N - 1)
	var cy: int = clamp(int(floor(p.y / TERRAIN_CELL)), 0, TERRAIN_N - 1)
	return terrain[cy * TERRAIN_N + cx]


func _apply_brush(p: Vector2, delta: float) -> void:
	var cx: int = int(floor(p.x / TERRAIN_CELL))
	var cy: int = int(floor(p.y / TERRAIN_CELL))
	var r: int = int(ceil(BRUSH_RADIUS / TERRAIN_CELL))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or y < 0 or x >= TERRAIN_N or y >= TERRAIN_N:
				continue
			var center: Vector2 = Vector2((x + 0.5) * TERRAIN_CELL, (y + 0.5) * TERRAIN_CELL)
			var d: float = center.distance_to(p)
			if d > BRUSH_RADIUS:
				continue
			var w: float = 1.0 - d / BRUSH_RADIUS
			var idx: int = y * TERRAIN_N + x
			var h: float = clamp(terrain[idx] + brush_sign * BRUSH_RATE * w * delta, HEIGHT_MIN, HEIGHT_MAX)
			terrain[idx] = h
			terrain_img.set_pixel(x, y, _height_color(h))
	terrain_dirty = true


func _spawn_soldier(p: Vector2, team: int) -> void:
	soldiers.append({
		"pos": p,
		"target": p,
		"has_target": false,
		"team": team,
		"selected": false,
		"hp": 100.0,
		"prone": randf() < 0.1,
		"anim_t": randf() * 2.0,
		"cd": randf() * SHOOT_COOLDOWN,
		"shots": 0,
		"order": "",
		"house": -1,
		"inside": -1,
	})


func _state_of(s: Dictionary) -> String:
	if float(s["hp"]) <= 0.0:
		return "dead"
	if float(s["hp"]) < 50.0:
		return "wounded"
	return "stand"


func get_frames(s: Dictionary) -> Array:
	var st: String = _state_of(s)
	var moving: bool = s["has_target"]
	if st == "dead":
		return [DEAD]
	if st == "wounded":
		return WOUNDED
	if s["prone"]:
		if moving:
			return CRAWL_ARMED
		return [PRONE_ARMED]
	if moving:
		return WALK_ARMED
	return [STAND_ARMED]


func _process(delta: float) -> void:
	var want: int = CanvasItem.TEXTURE_FILTER_NEAREST if cam.zoom.x >= SHARP_ZOOM else CanvasItem.TEXTURE_FILTER_LINEAR
	if texture_filter != want:
		texture_filter = want

	if brushing:
		if mode_index == 2:
			_apply_brush(brush_pos, delta)
		elif mode_index == 1:
			spawn_timer -= delta
			if spawn_timer <= 0.0 and soldiers.size() < MAX_SOLDIERS:
				_spawn_soldier(brush_pos, spawn_team)
				spawn_timer = SPAWN_INTERVAL

	if terrain_dirty:
		terrain_tex.update(terrain_img)
		terrain_dirty = false

	_update_orders(delta)
	_update_tracers(delta)

	bucket_timer -= delta
	if bucket_timer <= 0.0:
		_rebuild_buckets()
		bucket_timer = BUCKET_REBUILD

	_update_shooting(delta)
	_count_occupants()

	for s in soldiers:
		s["anim_t"] = float(s["anim_t"]) + delta
	queue_redraw()


func _update_orders(delta: float) -> void:
	for s in soldiers:
		if not s["has_target"]:
			continue
		var pos: Vector2 = s["pos"] as Vector2
		var target: Vector2 = s["target"] as Vector2
		var to_t: Vector2 = target - pos
		var dist: float = to_t.length()
		var dir: Vector2 = Vector2.ZERO
		if dist > 0.001:
			dir = to_t / dist
		var h0: float = _height_at(pos)
		var h1: float = _height_at(pos + dir * TERRAIN_CELL)
		var slope: float = (h1 - h0) / TERRAIN_CELL
		var mult: float = clamp(1.0 - slope * 0.8, 0.3, 1.3)
		var step: float = SPEED * mult * delta
		if dist <= step:
			s["pos"] = target
			s["has_target"] = false
			if s["order"] == "enter":
				s["inside"] = s["house"]
				s["order"] = ""
		else:
			s["pos"] = pos + dir * step


func _update_tracers(delta: float) -> void:
	for i in range(tracers.size() - 1, -1, -1):
		var tr: Dictionary = tracers[i]
		tr["t"] = float(tr["t"]) + delta * TRACER_SPEED
		if float(tr["t"]) > 1.3:
			tracers.remove_at(i)


func _bucket_key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.y / CHUNK)))


func _rebuild_buckets() -> void:
	buckets.clear()
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["inside"] >= 0 or float(s["hp"]) <= 0.0:
			continue
		var k: Vector2i = _bucket_key(s["pos"] as Vector2)
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(i)


func _find_enemy(i: int) -> int:
	var me: Dictionary = soldiers[i]
	var my_pos: Vector2 = me["pos"] as Vector2
	var best: int = -1
	var best_d: float = SHOOT_RANGE * SHOOT_RANGE
	var bk: Vector2i = _bucket_key(my_pos)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var k: Vector2i = bk + Vector2i(dx, dy)
			if not buckets.has(k):
				continue
			for j in buckets[k]:
				var o: Dictionary = soldiers[j]
				if o["team"] == me["team"]:
					continue
				if float(o["hp"]) <= 0.0 or o["inside"] >= 0:
					continue
				var d: float = (o["pos"] as Vector2).distance_squared_to(my_pos)
				if d < best_d:
					best_d = d
					best = j
	return best


func _update_shooting(delta: float) -> void:
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		s["cd"] = max(0.0, float(s["cd"]) - delta)
		if float(s["cd"]) > 0.0 or s["inside"] >= 0 or float(s["hp"]) <= 0.0:
			continue
		var target: int = _find_enemy(i)
		if target < 0:
			continue
		s["cd"] = SHOOT_COOLDOWN * (0.7 + randf() * 0.6)
		s["shots"] = int(s["shots"]) + 1
		var a: Vector2 = s["pos"] as Vector2
		var t: Dictionary = soldiers[target]
		var b: Vector2 = t["pos"] as Vector2
		if int(s["shots"]) % TRACER_EVERY == 0:
			_add_tracer(a, b)
		if randf() < HIT_CHANCE:
			t["hp"] = float(t["hp"]) - randf_range(15.0, 35.0)


func _add_tracer(a: Vector2, b: Vector2) -> void:
	if tracers.size() >= TRACER_MAX:
		tracers.pop_front()
	tracers.append({"a": a, "b": b, "t": 0.0})


func _count_occupants() -> void:
	for h in houses:
		h["occ0"] = 0
		h["occ1"] = 0
	for s in soldiers:
		if s["inside"] < 0 or float(s["hp"]) <= 0.0:
			continue
		var h: Dictionary = houses[s["inside"]]
		if s["team"] == 0:
			h["occ0"] = int(h["occ0"]) + 1
		else:
			h["occ1"] = int(h["occ1"]) + 1


func _house_rect_m(h: Dictionary) -> Rect2:
	var size: Vector2 = Vector2(HOUSE_W_M, HOUSE_H_M)
	return Rect2((h["pos"] as Vector2) - size * 0.5, size)


func _house_door(h: Dictionary) -> Vector2:
	var p: Vector2 = h["pos"] as Vector2
	return Vector2(p.x, p.y + HOUSE_H_M * 0.5 + 0.5)


func _team_color(team: int) -> Color:
	return Color(0.2, 0.5, 1.0) if team == 0 else Color(1.0, 0.3, 0.3)


func _draw() -> void:
	var view_size: Vector2 = get_viewport_rect().size / cam.zoom
	var view: Rect2 = Rect2(cam.position - view_size * 0.5, view_size)
	var map_px: float = MAP_SIZE * PX

	draw_texture_rect(terrain_tex, Rect2(0.0, 0.0, map_px, map_px), false)

	var grid_col: Color = Color(1, 1, 1, 0.05)
	var step_px: float = GRID_STEP * PX
	var gx: float = floor(view.position.x / step_px) * step_px
	while gx <= view.end.x:
		draw_line(Vector2(gx, view.position.y), Vector2(gx, view.end.y), grid_col)
		gx += step_px
	var gy: float = floor(view.position.y / step_px) * step_px
	while gy <= view.end.y:
		draw_line(Vector2(view.position.x, gy), Vector2(view.end.x, gy), grid_col)
		gy += step_px

	if house_tex != null:
		for h in houses:
			var rp: Rect2 = Rect2(_house_rect_m(h).position * PX, _house_rect_m(h).size * PX)
			if not view.intersects(rp):
				continue
			var v: int = int(h["variant"])
			if int(h["occ0"]) + int(h["occ1"]) > 0:
				v = 1
			var src: Rect2 = Rect2((v % 2) * HOUSE_W, (v / 2) * HOUSE_H, HOUSE_W, HOUSE_H)
			draw_texture_rect_region(house_tex, rp, src)

	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["inside"] < 0 or float(s["hp"]) <= 0.0:
			continue
		var hi: Dictionary = houses[s["inside"]]
		var off: Vector2 = Vector2(float(i % 4) * 2.5 - 3.75, float((i / 4) % 3) * 2.5 - 2.5)
		var ip: Vector2 = ((hi["pos"] as Vector2) + off) * PX
		draw_circle(ip, 2.0, _team_color(int(s["team"])))

	for s in soldiers:
		if s["inside"] >= 0:
			continue
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
			draw_circle(p, 1.6, _team_color(int(s["team"])))
		draw_circle(p + Vector2(0.0, SPRITE_SIZE * 0.45), 1.5, _team_color(int(s["team"])))
		if s["has_target"]:
			draw_line(p, (s["target"] as Vector2) * PX, Color(1, 1, 1, 0.25), 1.0)
		if s["selected"]:
			draw_arc(p, SPRITE_SIZE * 0.6, 0.0, TAU, 16, Color(1, 1, 0), 1.5)

	for tr in tracers:
		var a: Vector2 = (tr["a"] as Vector2) * PX
		var b: Vector2 = (tr["b"] as Vector2) * PX
		var tt: float = float(tr["t"])
		var head: Vector2 = a.lerp(b, clamp(tt, 0.0, 1.0))
		var tail: Vector2 = a.lerp(b, clamp(tt - 0.25, 0.0, 1.0))
		draw_line(tail, head, Color(1.0, 0.45, 0.1, 0.9), 1.2)
		draw_circle(head, 1.2, Color(1.0, 0.95, 0.6))


func _screen_to_world_m(screen_pos: Vector2) -> Vector2:
	return (get_viewport().get_canvas_transform().affine_inverse() * screen_pos) / PX


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			touches[t.index] = t.position
			last_pinch_dist = 0.0
			if touches.size() == 1:
				moved_during_touch = 0.0
				brush_pos = _screen_to_world_m(t.position)
				if mode_index != 0:
					brushing = true
					spawn_timer = 0.0
			else:
				brushing = false
		else:
			var was_single: bool = touches.size() == 1
			touches.erase(t.index)
			last_pinch_dist = 0.0
			brushing = false
			if was_single and mode_index == 0 and moved_during_touch < TAP_MAX_MOVE:
				_handle_select_tap(_screen_to_world_m(t.position))
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event as InputEventScreenDrag
		touches[d.index] = d.position
		if touches.size() == 1:
			moved_during_touch += d.relative.length()
			if mode_index != 0:
				brush_pos = _screen_to_world_m(d.position)
			else:
				cam.position -= d.relative / cam.zoom
		elif touches.size() == 2:
			var keys: Array = touches.keys()
			var p0: Vector2 = touches[keys[0]]
			var p1: Vector2 = touches[keys[1]]
			var dist: float = (p0 - p1).length()
			if last_pinch_dist > 0.0 and dist > 0.0:
				_zoom_by(dist / last_pinch_dist)
			last_pinch_dist = dist
			cam.position -= d.relative / cam.zoom


func _handle_select_tap(world_m: Vector2) -> void:
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["team"] != 0 or s["inside"] >= 0 or float(s["hp"]) <= 0.0:
			continue
		if (s["pos"] as Vector2).distance_to(world_m) <= SELECT_RADIUS:
			_clear_selection()
			s["selected"] = true
			return

	for hi in houses.size():
		var h: Dictionary = houses[hi]
		if _house_rect_m(h).has_point(world_m):
			_house_tap(hi)
			return

	_move_selected(world_m)


func _house_tap(hi: int) -> void:
	var h: Dictionary = houses[hi]
	var selected: Array = _selected_outside()
	if not selected.is_empty():
		var door: Vector2 = _house_door(h)
		var cols: int = int(ceil(sqrt(float(selected.size()))))
		for n in selected.size():
			var idx: int = selected[n]
			var s: Dictionary = soldiers[idx]
			s["order"] = "enter"
			s["house"] = hi
			s["target"] = door + Vector2(float(n % cols) - cols * 0.5, float(n / cols)) * 1.2
			s["has_target"] = true
		return

	for i in soldiers.size():
		var s2: Dictionary = soldiers[i]
		if s2["inside"] == hi and s2["team"] == 0 and float(s2["hp"]) > 0.0:
			s2["inside"] = -1
			s2["pos"] = _house_door(h) + Vector2(randf_range(-1.5, 1.5), 1.0)
			s2["target"] = s2["pos"]
			s2["has_target"] = false


func _selected_outside() -> Array:
	var out: Array = []
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["selected"] and s["inside"] < 0 and float(s["hp"]) > 0.0:
			out.append(i)
	return out


func _move_selected(world_m: Vector2) -> void:
	var selected: Array = _selected_outside()
	if selected.is_empty():
		return
	var cols: int = int(ceil(sqrt(float(selected.size()))))
	for n in selected.size():
		var idx: int = selected[n]
		var s: Dictionary = soldiers[idx]
		s["order"] = ""
		s["house"] = -1
		s["target"] = world_m + Vector2(float(n % cols), float(n / cols)) * 1.5 - Vector2(float(cols), float(cols)) * 0.75
		s["has_target"] = true


func _clear_selection() -> void:
	for s in soldiers:
		s["selected"] = false


func _zoom_by(factor: float) -> void:
	var z: float = clamp(cam.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	cam.zoom = Vector2(z, z)


func _make_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var left := HBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 20.0
	left.offset_top = -150.0
	left.offset_right = 520.0
	left.offset_bottom = -20.0
	left.add_theme_constant_override("separation", 16)
	layer.add_child(left)

	mode_btn = _make_button("Выбор", Vector2(190, 120), 40)
	mode_btn.pressed.connect(_on_mode_pressed)
	left.add_child(mode_btn)

	extra_btn = _make_button("", Vector2(190, 120), 40)
	extra_btn.pressed.connect(_on_extra_pressed)
	left.add_child(extra_btn)

	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -170.0
	right.offset_top = -290.0
	right.offset_right = -20.0
	right.offset_bottom = -20.0
	right.add_theme_constant_override("separation", 20)
	layer.add_child(right)

	var plus: Button = _make_button("+", Vector2(150, 120), 56)
	plus.pressed.connect(func(): _zoom_by(BUTTON_ZOOM_STEP))
	right.add_child(plus)

	var minus: Button = _make_button("−", Vector2(150, 120), 56)
	minus.pressed.connect(func(): _zoom_by(1.0 / BUTTON_ZOOM_STEP))
	right.add_child(minus)

	_update_buttons()


func _make_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _on_mode_pressed() -> void:
	mode_index = (mode_index + 1) % 3
	brushing = false
	_update_buttons()


func _on_extra_pressed() -> void:
	if mode_index == 1:
		spawn_team = 1 - spawn_team
	elif mode_index == 2:
		brush_sign = -brush_sign
	_update_buttons()


func _update_buttons() -> void:
	mode_btn.text = MODE_NAMES[mode_index]
	if mode_index == 1:
		extra_btn.visible = true
		extra_btn.text = "Синие" if spawn_team == 0 else "Красные"
	elif mode_index == 2:
		extra_btn.visible = true
		extra_btn.text = "Поднять" if brush_sign > 0.0 else "Опустить"
	else:
		extra_btn.visible = false
