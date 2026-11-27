extends Node2D

const PX: float = 4.0
const MAP_M: float = 600.0
const CELL_M: float = 3.0
const NCELL: int = 200
const CT: int = 3
const TEX: int = 600
const SCALE_M: float = 0.12
const HMIN: float = -8.0
const HMAX: float = 12.0

const SPRITE: float = 14.0
const FRAME_TIME: float = 0.12
const SPEED: float = 3.0
const SEL_R: float = 3.0
const IN_R: float = 1.8
const TAP_MOVE: float = 15.0
const START_PER_TEAM: int = 30
const MAX_SOLDIERS: int = 400
const SPAWN_EVERY: float = 0.15
const CHUNK: float = 20.0
const SHOOT_RANGE: float = 40.0
const SHOOT_CD: float = 0.8
const HIT_CHANCE: float = 0.25
const TRACER_EVERY: int = 4
const TRACER_MAX: int = 120
const TRACER_SPEED: float = 2.5
const BUCKET_EVERY: float = 0.3
const BOOM_R: float = 8.0
const BOOM_DMG: float = 120.0
const BOOM_TIME: float = 0.4
const BRUSH_R: float = 6.0
const BRUSH_RATE: float = 6.0
const BUILD_HP: float = 400.0
const PROP_HP: float = 120.0
const MAX_CAT_BUILD: int = 12
const MAX_CAT_OBJ: int = 30
const MAX_BUILDINGS: int = 60
const MAX_PROPS: int = 120
const TEX_UPLOAD: float = 0.15
const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 64.0
const SHARP_ZOOM: float = 4.0
const BTN_ZOOM: float = 1.6

const CATALOG: String = "res://assets/catalog.json"
const INFANTRY: String = "res://assets/infantry.png"
const OBJECTS: String = "res://assets/objects.png"
const LANDSCAPE: String = "res://assets/landscape.png"
const BUILD_PREFIX: String = "res://assets/buildings_"
const BUILD_KEYS: Array = ["base", "damaged", "destroyed", "uncovered"]
const TAB_NAMES: Array = ["Солдаты", "Дома", "Объекты", "Ландшафт", "Взрыв"]
const LAND_NAMES: Array = ["Канава", "Поле", "Трава", "Земля", "Грязь", "Вода", "Рельсы", "Лес"]

const STAND: Vector2i = Vector2i(5, 8)
const PRONE: Vector2i = Vector2i(0, 7)
const DEAD: Vector2i = Vector2i(5, 2)
const WALK: Array = [Vector2i(0, 9), Vector2i(1, 9), Vector2i(2, 9), Vector2i(3, 9), Vector2i(4, 9), Vector2i(5, 9)]
const CRAWL: Array = [Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)]
const WOUNDED: Array = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)]

var cam: Camera2D
var cat: Dictionary = {}
var cat_b: Array = []
var cat_o: Array = []
var infantry_tex: Texture2D
var obj_tex: Texture2D
var land_tex: Texture2D
var land_img: Image
var b_tex: Dictionary = {}
var tile3: Array = []
var ground: PackedInt32Array = PackedInt32Array()
var heights: PackedFloat32Array = PackedFloat32Array()
var bake: Image
var bake_tex: ImageTexture
var dirty: Dictionary = {}
var tex_dirty: bool = false
var tex_timer: float = 0.0
var soldiers: Array = []
var buildings: Array = []
var props: Array = []
var tracers: Array = []
var booms: Array = []
var buckets: Dictionary = {}
var bucket_timer: float = 0.0
var touches: Dictionary = {}
var moved: float = 0.0
var pinch_on: bool = false
var pinch_mid: Vector2 = Vector2.ZERO
var pinch_d: float = 0.0
var brush: Dictionary = {}
var brushing: bool = false
var brush_pos: Vector2 = Vector2.ZERO
var spawn_t: float = 0.0
var brush_label: Label
var panel: PanelContainer
var grid: GridContainer
var tab: int = 0


func _ready() -> void:
	_load_catalog()
	_load_textures()
	_init_terrain()
	cam = Camera2D.new()
	cam.position = Vector2(MAP_M, MAP_M) * PX * 0.5
	cam.zoom = Vector2(1.5, 1.5)
	add_child(cam)
	cam.make_current()
	_make_ui()
	for team in [0, 1]:
		for i in START_PER_TEAM:
			var x: float = randf_range(60.0, 180.0) if team == 0 else randf_range(420.0, 540.0)
			_spawn_soldier(Vector2(x, randf_range(60.0, 540.0)), team)
	for i in min(6, cat_b.size()):
		_place_building(i, Vector2(randf_range(220.0, 380.0), randf_range(120.0, 480.0)))


func _load_catalog() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if parsed is Dictionary:
		cat = parsed
	cat_b = cat.get("buildings", [])
	cat_o = cat.get("objects", [])


func _load_textures() -> void:
	infantry_tex = load(INFANTRY) as Texture2D
	obj_tex = load(OBJECTS) as Texture2D
	land_tex = load(LANDSCAPE) as Texture2D
	for k in BUILD_KEYS:
		b_tex[k] = load(BUILD_PREFIX + k + ".png") as Texture2D
	land_img = land_tex.get_image()


func _init_terrain() -> void:
	tile3 = []
	for t in 8:
		var arr: PackedColorArray = PackedColorArray()
		for v in CT:
			for u in CT:
				arr.append(land_img.get_pixel(t * 64 + int((u + 0.5) * 64.0 / CT), int((v + 0.5) * 64.0 / CT)))
		tile3.append(arr)
	ground.resize(NCELL * NCELL)
	ground.fill(2)
	heights.resize(NCELL * NCELL)
	heights.fill(0.0)
	bake = Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	bake.fill(tile3[2][0])
	bake_tex = ImageTexture.create_from_image(bake)


# ---------- Ландшафт ----------

func _linear(t: int) -> bool:
	return t == 0 or t == 6


func _nt(cx: int, cy: int, dx: int, dy: int) -> int:
	var nx: int = cx + dx
	var ny: int = cy + dy
	if nx < 0 or ny < 0 or nx >= NCELL or ny >= NCELL:
		return -1
	return ground[ny * NCELL + nx]


func _render(cx: int, cy: int) -> void:
	var idx: int = cy * NCELL + cx
	var t: int = ground[idx]
	var shade: float = clamp(1.0 + heights[idx] * 0.02, 0.6, 1.3)
	var horiz: bool = _nt(cx, cy, 1, 0) == t or _nt(cx, cy, -1, 0) == t
	var vert: bool = _nt(cx, cy, 0, 1) == t or _nt(cx, cy, 0, -1) == t
	for v in CT:
		for u in CT:
			var col: Color
			if _linear(t):
				if horiz or not vert:
					col = tile3[t][v * CT + u]
				else:
					col = tile3[t][u * CT + v]
			else:
				col = tile3[t][v * CT + u]
				var dx: int = -1 if u == 0 else (1 if u == CT - 1 else 0)
				var dy: int = -1 if v == 0 else (1 if v == CT - 1 else 0)
				if dx != 0 or dy != 0:
					var nt: int = _nt(cx, cy, dx, dy)
					if nt >= 0 and nt != t and not _linear(nt):
						col = col.lerp(tile3[nt][v * CT + u], 0.5)
			bake.set_pixel(cx * CT + u, cy * CT + v, Color(col.r * shade, col.g * shade, col.b * shade, 1.0))
	tex_dirty = true


func _mark(cx: int, cy: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = cx + dx
			var y: int = cy + dy
			if x >= 0 and y >= 0 and x < NCELL and y < NCELL:
				dirty[y * NCELL + x] = true


func _render_dirty() -> void:
	if dirty.is_empty():
		return
	var keys: Array = dirty.keys()
	dirty.clear()
	for k in keys:
		var ki: int = int(k)
		_render(ki % NCELL, ki / NCELL)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clamp(int(floor(p.x / CELL_M)), 0, NCELL - 1), clamp(int(floor(p.y / CELL_M)), 0, NCELL - 1))


func _hat(p: Vector2) -> float:
	var c: Vector2i = _cell(p)
	return heights[c.y * NCELL + c.x]


func _paint(p: Vector2, t: int) -> void:
	var r: int = int(ceil(BRUSH_R / CELL_M))
	var c: Vector2i = _cell(p)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x: int = c.x + dx
			var y: int = c.y + dy
			if x < 0 or y < 0 or x >= NCELL or y >= NCELL:
				continue
			if Vector2((x + 0.5) * CELL_M, (y + 0.5) * CELL_M).distance_to(p) > BRUSH_R:
				continue
			ground[y * NCELL + x] = t
			_mark(x, y)


func _shape(p: Vector2, sign: float, delta: float) -> void:
	var r: int = int(ceil(BRUSH_R / CELL_M))
	var c: Vector2i = _cell(p)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x: int = c.x + dx
			var y: int = c.y + dy
			if x < 0 or y < 0 or x >= NCELL or y >= NCELL:
				continue
			var d: float = Vector2((x + 0.5) * CELL_M, (y + 0.5) * CELL_M).distance_to(p)
			if d > BRUSH_R:
				continue
			var idx: int = y * NCELL + x
			heights[idx] = clamp(heights[idx] + sign * BRUSH_RATE * (1.0 - d / BRUSH_R) * delta, HMIN, HMAX)
			_mark(x, y)


func _crater(p: Vector2) -> void:
	var c: Vector2i = _cell(p)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x: int = c.x + dx
			var y: int = c.y + dy
			if x < 0 or y < 0 or x >= NCELL or y >= NCELL:
				continue
			var d: float = Vector2((x + 0.5) * CELL_M, (y + 0.5) * CELL_M).distance_to(p)
			if d > 4.0:
				continue
			var idx: int = y * NCELL + x
			heights[idx] = clamp(heights[idx] - 2.0 * (1.0 - d / 4.0), HMIN, HMAX)
			_mark(x, y)


# ---------- Солдаты ----------

func _spawn_soldier(p: Vector2, team: int) -> void:
	if soldiers.size() >= MAX_SOLDIERS:
		return
	soldiers.append({"pos": p, "target": p, "has_target": false, "team": team, "selected": false,
		"hp": 100.0, "prone": randf() < 0.1, "anim": randf() * 2.0, "cd": randf() * SHOOT_CD,
		"shots": 0, "order": "", "house": -1, "inside": -1})


func _alive(s: Dictionary) -> bool:
	return float(s["hp"]) > 0.0


func _frames(s: Dictionary) -> Array:
	if not _alive(s):
		return [DEAD]
	if float(s["hp"]) < 50.0:
		return WOUNDED
	if s["prone"]:
		return CRAWL if s["has_target"] else [PRONE]
	return WALK if s["has_target"] else [STAND]


func _update_orders(delta: float) -> void:
	for s in soldiers:
		if not s["has_target"] or not _alive(s):
			continue
		var pos: Vector2 = s["pos"] as Vector2
		var to_t: Vector2 = (s["target"] as Vector2) - pos
		var dist: float = to_t.length()
		var dir: Vector2 = to_t / dist if dist > 0.001 else Vector2.ZERO
		var mult: float = 1.0
		if int(s["inside"]) < 0:
			mult = clamp(1.0 - (_hat(pos + dir * CELL_M) - _hat(pos)) / CELL_M * 0.8, 0.3, 1.3)
		var step: float = SPEED * mult * delta
		if dist <= step:
			s["pos"] = s["target"]
			s["has_target"] = false
			_arrive(s)
		else:
			s["pos"] = pos + dir * step


func _arrive(s: Dictionary) -> void:
	var bi: int = int(s["house"])
	if s["order"] == "enter" and bi >= 0 and bi < buildings.size() and float(buildings[bi]["hp"]) > 0.0:
		s["inside"] = bi
		s["pos"] = _interior(buildings[bi])
	elif s["order"] == "exit" and bi >= 0 and bi < buildings.size():
		s["pos"] = _door(buildings[bi]) + Vector2(0.0, 1.0)
		s["inside"] = -1
	s["order"] = ""
	s["house"] = -1


func _update_shooting(delta: float) -> void:
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		s["cd"] = max(0.0, float(s["cd"]) - delta)
		if float(s["cd"]) > 0.0 or int(s["inside"]) >= 0 or not _alive(s):
			continue
		var tgt: int = _enemy(i)
		if tgt < 0:
			continue
		s["cd"] = SHOOT_CD * (0.7 + randf() * 0.6)
		s["shots"] = int(s["shots"]) + 1
		var t: Dictionary = soldiers[tgt]
		if int(s["shots"]) % TRACER_EVERY == 0:
			if tracers.size() >= TRACER_MAX:
				tracers.pop_front()
			tracers.append({"a": s["pos"], "b": t["pos"], "t": 0.0})
		if randf() < HIT_CHANCE:
			t["hp"] = float(t["hp"]) - randf_range(15.0, 35.0)


func _enemy(i: int) -> int:
	var me: Dictionary = soldiers[i]
	var mp: Vector2 = me["pos"] as Vector2
	var best: int = -1
	var bd: float = SHOOT_RANGE * SHOOT_RANGE
	var bk: Vector2i = Vector2i(int(floor(mp.x / CHUNK)), int(floor(mp.y / CHUNK)))
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var k: Vector2i = bk + Vector2i(dx, dy)
			if not buckets.has(k):
				continue
			for j in buckets[k]:
				var o: Dictionary = soldiers[j]
				if int(o["team"]) == int(me["team"]):
					continue
				var d: float = (o["pos"] as Vector2).distance_squared_to(mp)
				if d < bd:
					bd = d
					best = j
	return best


func _rebuild_buckets() -> void:
	buckets.clear()
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if int(s["inside"]) >= 0 or not _alive(s):
			continue
		var p: Vector2 = s["pos"] as Vector2
		var k: Vector2i = Vector2i(int(floor(p.x / CHUNK)), int(floor(p.y / CHUNK)))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(i)


func _selected_out() -> Array:
	var out: Array = []
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["selected"] and int(s["inside"]) < 0 and _alive(s):
			out.append(i)
	return out


func _selected_in(bi: int) -> Array:
	var out: Array = []
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["selected"] and int(s["inside"]) == bi and _alive(s):
			out.append(i)
	return out


func _formation(list: Array, c: Vector2, step_y: float) -> void:
	var cols: int = int(ceil(sqrt(float(list.size()))))
	for n in list.size():
		var s: Dictionary = soldiers[list[n]]
		s["target"] = c + Vector2(float(n % cols) - cols * 0.5, float(n / cols) * step_y) * 1.3
		s["has_target"] = true


# ---------- Дома и объекты ----------

func _base_m(b: Dictionary) -> Vector2:
	var r: Array = cat_b[int(b["bid"])]["base"]
	return Vector2(float(r[2]), float(r[3])) * SCALE_M


func _foot(b: Dictionary) -> Rect2:
	var sz: Vector2 = _base_m(b)
	return Rect2((b["pos"] as Vector2) - sz * 0.5, sz)


func _door(b: Dictionary) -> Vector2:
	var sz: Vector2 = _base_m(b)
	var p: Vector2 = b["pos"] as Vector2
	return Vector2(p.x, p.y + sz.y * 0.5 + 0.6)


func _door_rect(b: Dictionary) -> Rect2:
	var d: Vector2 = _door(b)
	return Rect2(d - Vector2(1.5, 0.8), Vector2(3.0, 1.6))


func _interior(b: Dictionary) -> Vector2:
	var fr: Rect2 = _foot(b).grow(-1.0)
	return Vector2(randf_range(fr.position.x, fr.end.x), randf_range(fr.position.y, fr.end.y))


func _place_building(bid: int, p: Vector2) -> void:
	if buildings.size() >= MAX_BUILDINGS or bid >= min(MAX_CAT_BUILD, cat_b.size()):
		return
	buildings.append({"bid": bid, "pos": p, "hp": BUILD_HP, "occ0": 0, "occ1": 0})


func _place_prop(oid: int, p: Vector2) -> void:
	if props.size() >= MAX_PROPS or oid >= min(MAX_CAT_OBJ, cat_o.size()):
		return
	props.append({"oid": oid, "pos": p, "hp": PROP_HP})


func _variant(b: Dictionary) -> String:
	if float(b["hp"]) <= 0.0:
		return "destroyed"
	if int(b["occ0"]) + int(b["occ1"]) > 0:
		return "uncovered"
	if float(b["hp"]) < BUILD_HP * 0.5:
		return "damaged"
	return "base"


func _count_occupants() -> void:
	for b in buildings:
		b["occ0"] = 0
		b["occ1"] = 0
	for s in soldiers:
		var bi: int = int(s["inside"])
		if bi < 0 or not _alive(s):
			continue
		var b: Dictionary = buildings[bi]
		var k: String = "occ0" if int(s["team"]) == 0 else "occ1"
		b[k] = int(b[k]) + 1


func _destroy(bi: int) -> void:
	var b: Dictionary = buildings[bi]
	b["hp"] = 0.0
	for s in soldiers:
		if int(s["inside"]) == bi:
			s["inside"] = -1
			s["hp"] = 0.0
			s["pos"] = b["pos"]
		if int(s["house"]) == bi:
			s["order"] = ""
			s["house"] = -1
			s["has_target"] = false


func _explode(p: Vector2) -> void:
	booms.append({"pos": p, "t": 0.0})
	_crater(p)
	for s in soldiers:
		if not _alive(s) or int(s["inside"]) >= 0:
			continue
		var d: float = (s["pos"] as Vector2).distance_to(p)
		if d < BOOM_R:
			s["hp"] = float(s["hp"]) - BOOM_DMG * (1.0 - d / BOOM_R)
	for bi in buildings.size():
		var b: Dictionary = buildings[bi]
		if float(b["hp"]) <= 0.0:
			continue
		var fr: Rect2 = _foot(b)
		var near: Vector2 = Vector2(clamp(p.x, fr.position.x, fr.end.x), clamp(p.y, fr.position.y, fr.end.y))
		var d2: float = near.distance_to(p)
		if d2 < BOOM_R:
			b["hp"] = float(b["hp"]) - BOOM_DMG * 2.0 * (1.0 - d2 / BOOM_R)
			if float(b["hp"]) <= 0.0:
				_destroy(bi)
	for pr in props:
		if float(pr["hp"]) <= 0.0:
			continue
		var dp: float = (pr["pos"] as Vector2).distance_to(p)
		if dp < BOOM_R:
			pr["hp"] = float(pr["hp"]) - BOOM_DMG * 1.5 * (1.0 - dp / BOOM_R)


# ---------- Касания и камера ----------

func _w_px(sp: Vector2) -> Vector2:
	return cam.position + (sp - get_viewport().get_visible_rect().size * 0.5) / cam.zoom.x


func _w_m(sp: Vector2) -> Vector2:
	return _w_px(sp) / PX


func _zoom_about(sp: Vector2, f: float) -> void:
	var before: Vector2 = _w_px(sp)
	var z: float = clamp(cam.zoom.x * f, MIN_ZOOM, MAX_ZOOM)
	cam.zoom = Vector2(z, z)
	cam.position += before - _w_px(sp)


func _pinch() -> void:
	var keys: Array = touches.keys()
	var p0: Vector2 = touches[keys[0]]
	var p1: Vector2 = touches[keys[1]]
	var mid: Vector2 = (p0 + p1) * 0.5
	var d: float = (p0 - p1).length()
	if pinch_on:
		cam.position -= (mid - pinch_mid) / cam.zoom.x
		if pinch_d > 1.0 and d > 1.0:
			_zoom_about(mid, clamp(d / pinch_d, 0.85, 1.18))
	pinch_on = true
	pinch_mid = mid
	pinch_d = d


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			touches[t.index] = t.position
			pinch_on = false
			if touches.size() == 1:
				moved = 0.0
				brush_pos = _w_m(t.position)
				brushing = not brush.is_empty()
				spawn_t = 0.0
			else:
				brushing = false
		else:
			var single: bool = touches.size() == 1
			touches.erase(t.index)
			pinch_on = false
			brushing = false
			if single and moved < TAP_MOVE:
				if brush.is_empty():
					_select(_w_m(t.position))
				else:
					_brush_tap(_w_m(t.position))
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event as InputEventScreenDrag
		touches[d.index] = d.position
		if touches.size() == 1:
			moved += d.relative.length()
			if brush.is_empty():
				cam.position -= d.relative / cam.zoom.x
			else:
				brush_pos = _w_m(d.position)
		elif touches.size() == 2:
			brushing = false
			_pinch()


func _brush_tap(wp: Vector2) -> void:
	var k: String = str(brush.get("kind", ""))
	if k == "building":
		_place_building(int(brush["id"]), wp)
	elif k == "object":
		_place_prop(int(brush["id"]), wp)
	elif k == "explode":
		_explode(wp)
	elif k == "soldier":
		_spawn_soldier(wp, int(brush["team"]))
	elif k == "ground":
		_paint(wp, int(brush["id"]))
	elif k == "shape":
		_shape(wp, float(brush["sign"]), 0.25)


func _select(wp: Vector2) -> void:
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if int(s["team"]) != 0 or not _alive(s):
			continue
		var r: float = IN_R if int(s["inside"]) >= 0 else SEL_R
		if (s["pos"] as Vector2).distance_to(wp) <= r:
			for o in soldiers:
				o["selected"] = false
			s["selected"] = true
			return
	for bi in buildings.size():
		var b: Dictionary = buildings[bi]
		if float(b["hp"]) <= 0.0:
			continue
		if _door_rect(b).has_point(wp):
			var out: Array = _selected_out()
			if not out.is_empty():
				_order_enter(bi, out)
			else:
				var ins: Array = _selected_in(bi)
				if not ins.is_empty():
					_order_exit(bi, ins)
			return
		if _foot(b).has_point(wp):
			var out2: Array = _selected_out()
			if not out2.is_empty():
				_order_enter(bi, out2)
			else:
				var ins2: Array = _selected_in(bi)
				if not ins2.is_empty():
					var fr: Rect2 = _foot(b).grow(-1.0)
					_formation(ins2, Vector2(clamp(wp.x, fr.position.x, fr.end.x), clamp(wp.y, fr.position.y, fr.end.y)), 0.0)
			return
	var sel: Array = _selected_out()
	if not sel.is_empty():
		for n in sel.size():
			var s2: Dictionary = soldiers[sel[n]]
			s2["order"] = ""
			s2["house"] = -1
		_formation(sel, wp, 1.0)


func _order_enter(bi: int, list: Array) -> void:
	for idx in list:
		var s: Dictionary = soldiers[idx]
		s["order"] = "enter"
		s["house"] = bi
	_formation(list, _door(buildings[bi]), 1.0)


func _order_exit(bi: int, list: Array) -> void:
	for idx in list:
		var s: Dictionary = soldiers[idx]
		s["order"] = "exit"
		s["house"] = bi
	_formation(list, _door(buildings[bi]) + Vector2(0.0, 1.5), 1.0)


# ---------- Отрисовка ----------

func _draw() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size / cam.zoom.x
	var view: Rect2 = Rect2(cam.position - vp * 0.5, vp)

	draw_texture_rect(bake_tex, Rect2(0.0, 0.0, MAP_M * PX, MAP_M * PX), false)

	for b in buildings:
		var key: String = _variant(b)
		var r: Array = cat_b[int(b["bid"])][key]
		var rect: Rect2 = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		var sz: Vector2 = rect.size * SCALE_M * PX
		var dest: Rect2 = Rect2((b["pos"] as Vector2) * PX - sz * 0.5, sz)
		if view.intersects(dest) and b_tex.has(key) and b_tex[key] != null:
			draw_texture_rect_region(b_tex[key], dest, rect)

	for pr in props:
		if float(pr["hp"]) <= 0.0 or obj_tex == null:
			continue
		var r2: Array = cat_o[int(pr["oid"])]["rect"]
		var rect2: Rect2 = Rect2(float(r2[0]), float(r2[1]), float(r2[2]), float(r2[3]))
		var sz2: Vector2 = rect2.size * SCALE_M * PX
		var dest2: Rect2 = Rect2((pr["pos"] as Vector2) * PX - sz2 * 0.5, sz2)
		if view.intersects(dest2):
			var a: float = 1.0 if float(pr["hp"]) >= PROP_HP * 0.5 else 0.55
			draw_texture_rect_region(obj_tex, dest2, rect2, Color(1, 1, 1, a))

	for s in soldiers:
		if int(s["inside"]) < 0 or not _alive(s) or infantry_tex == null:
			continue
		var ip: Vector2 = (s["pos"] as Vector2) * PX
		draw_texture_rect_region(infantry_tex, Rect2(ip - Vector2.ONE * 4.5, Vector2.ONE * 9.0), Rect2(320, 512, 64, 64))
		if s["selected"]:
			draw_arc(ip, 5.0, 0.0, TAU, 12, Color(1, 1, 0), 1.2)

	for s in soldiers:
		if int(s["inside"]) >= 0:
			continue
		var p: Vector2 = (s["pos"] as Vector2) * PX
		if not view.grow(20.0).has_point(p) or infantry_tex == null:
			continue
		var fr: Array = _frames(s)
		var cell: Vector2i = fr[int(float(s["anim"]) / FRAME_TIME) % fr.size()]
		draw_texture_rect_region(infantry_tex, Rect2(p - Vector2.ONE * SPRITE * 0.5, Vector2.ONE * SPRITE), Rect2(cell.x * 64.0, cell.y * 64.0, 64.0, 64.0))
		if s["selected"]:
			draw_arc(p, SPRITE * 0.6, 0.0, TAU, 16, Color(1, 1, 0), 1.5)

	for bo in booms:
		var f: float = float(bo["t"]) / BOOM_TIME
		draw_arc((bo["pos"] as Vector2) * PX, BOOM_R * PX * f, 0.0, TAU, 24, Color(1.0, 0.6, 0.2, 1.0 - f), 2.0)

	for tr in tracers:
		var a2: Vector2 = (tr["a"] as Vector2) * PX
		var b2: Vector2 = (tr["b"] as Vector2) * PX
		var tt: float = float(tr["t"])
		var head: Vector2 = a2.lerp(b2, clamp(tt, 0.0, 1.0))
		var tail: Vector2 = a2.lerp(b2, clamp(tt - 0.25, 0.0, 1.0))
		draw_line(tail, head, Color(1.0, 0.45, 0.1, 0.9), 1.2)
		draw_circle(head, 1.2, Color(1.0, 0.95, 0.6))


# ---------- Цикл ----------

func _process(delta: float) -> void:
	var want: int = CanvasItem.TEXTURE_FILTER_NEAREST if cam.zoom.x >= SHARP_ZOOM else CanvasItem.TEXTURE_FILTER_LINEAR
	if texture_filter != want:
		texture_filter = want
	if brushing and not brush.is_empty():
		var k: String = str(brush.get("kind", ""))
		if k == "soldier":
			spawn_t -= delta
			if spawn_t <= 0.0:
				_spawn_soldier(brush_pos, int(brush["team"]))
				spawn_t = SPAWN_EVERY
		elif k == "ground":
			_paint(brush_pos, int(brush["id"]))
		elif k == "shape":
			_shape(brush_pos, float(brush["sign"]), delta)
	_render_dirty()
	if tex_dirty:
		tex_timer -= delta
		if tex_timer <= 0.0:
			bake_tex.update(bake)
			tex_dirty = false
			tex_timer = TEX_UPLOAD
	_update_orders(delta)
	for i in range(tracers.size() - 1, -1, -1):
		tracers[i]["t"] = float(tracers[i]["t"]) + delta * TRACER_SPEED
		if float(tracers[i]["t"]) > 1.3:
			tracers.remove_at(i)
	for i in range(booms.size() - 1, -1, -1):
		booms[i]["t"] = float(booms[i]["t"]) + delta
		if float(booms[i]["t"]) >= BOOM_TIME:
			booms.remove_at(i)
	bucket_timer -= delta
	if bucket_timer <= 0.0:
		_rebuild_buckets()
		bucket_timer = BUCKET_EVERY
	_update_shooting(delta)
	_count_occupants()
	for s in soldiers:
		s["anim"] = float(s["anim"]) + delta
	queue_redraw()


# ---------- Интерфейс ----------

func _btn(text: String, sz: Vector2, fs: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = sz
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(cb)
	return b


func _make_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	brush_label = Label.new()
	brush_label.position = Vector2(20, 20)
	brush_label.add_theme_font_size_override("font_size", 34)
	brush_label.text = "Выбор"
	layer.add_child(brush_label)

	var left := HBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 20.0
	left.offset_top = -150.0
	left.offset_right = 600.0
	left.offset_bottom = -20.0
	layer.add_child(left)
	left.add_child(_btn("Каталог", Vector2(200, 120), 36, _open))
	left.add_child(_btn("Выбор", Vector2(200, 120), 36, _clear_brush))

	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -170.0
	right.offset_top = -290.0
	right.offset_right = -20.0
	right.offset_bottom = -20.0
	layer.add_child(right)
	right.add_child(_btn("+", Vector2(150, 120), 56, func(): _zoom_about(get_viewport().get_visible_rect().size * 0.5, BTN_ZOOM)))
	right.add_child(_btn("−", Vector2(150, 120), 56, func(): _zoom_about(get_viewport().get_visible_rect().size * 0.5, 1.0 / BTN_ZOOM)))

	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = -16.0
	panel.offset_bottom = -16.0
	panel.visible = false
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	for i in TAB_NAMES.size():
		tabs.add_child(_btn(TAB_NAMES[i], Vector2(0, 90), 26, _tab.bind(i)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	box.add_child(_btn("Закрыть", Vector2(0, 90), 30, _close))


func _open() -> void:
	_fill()
	panel.visible = true


func _close() -> void:
	panel.visible = false


func _tab(i: int) -> void:
	tab = i
	_fill()


func _clear_brush() -> void:
	brush = {}
	brush_label.text = "Выбор"


func _pick(data: Dictionary) -> void:
	brush = data
	panel.visible = false
	brush_label.text = str(data.get("name", ""))


func _atlas(tex: Texture2D, r: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = r
	return a


func _item(icon: Texture2D, text: String, data: Dictionary) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(130, 130)
	b.text = text
	b.add_theme_font_size_override("font_size", 26)
	if icon != null:
		b.icon = icon
		b.expand_icon = true
	b.pressed.connect(_pick.bind(data))
	grid.add_child(b)


func _fill() -> void:
	for c in grid.get_children():
		c.queue_free()
	if tab == 0:
		_item(_atlas(infantry_tex, Rect2(320, 512, 64, 64)), "Синие", {"kind": "soldier", "team": 0, "name": "Спавн: синие"})
		_item(_atlas(infantry_tex, Rect2(320, 512, 64, 64)), "Красные", {"kind": "soldier", "team": 1, "name": "Спавн: красные"})
	elif tab == 1:
		for i in min(MAX_CAT_BUILD, cat_b.size()):
			var r: Array = cat_b[i]["base"]
			_item(_atlas(b_tex["base"], Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))), "", {"kind": "building", "id": i, "name": "Дом #" + str(i)})
	elif tab == 2:
		for i in min(MAX_CAT_OBJ, cat_o.size()):
			var r2: Array = cat_o[i]["rect"]
			_item(_atlas(obj_tex, Rect2(float(r2[0]), float(r2[1]), float(r2[2]), float(r2[3]))), "", {"kind": "object", "id": i, "name": "Объект #" + str(i)})
	elif tab == 3:
		for i in 8:
			_item(_atlas(land_tex, Rect2(i * 64.0, 0.0, 64.0, 64.0)), "", {"kind": "ground", "id": i, "name": "Ландшафт: " + LAND_NAMES[i]})
		_item(null, "Поднять", {"kind": "shape", "sign": 1.0, "name": "Поднять землю"})
		_item(null, "Опустить", {"kind": "shape", "sign": -1.0, "name": "Опустить землю"})
	else:
		_item(null, "Взрыв", {"kind": "explode", "name": "Взрыв"})
