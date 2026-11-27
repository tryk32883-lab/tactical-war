extends Node2D

# Тактика: карта 600 x 600 м. 1 метр = PX пикселей мира.

const PX: float = 4.0
const MAP_M: float = 600.0
const CELL_M: float = 3.0
const NCELL: int = 200
const CELL_TEX: int = 6
const TEX_W: int = 1200
const SCALE_M: float = 0.12
const HEIGHT_MIN: float = -8.0
const HEIGHT_MAX: float = 12.0

const SPRITE_SIZE: float = 14.0
const FRAME_TIME: float = 0.12
const SPEED: float = 3.0
const SELECT_RADIUS: float = 3.0
const INSIDE_RADIUS: float = 1.8
const TAP_MAX_MOVE: float = 15.0
const START_PER_TEAM: int = 40
const MAX_SOLDIERS: int = 600
const MAX_BUILDINGS: int = 300
const MAX_PROPS: int = 600
const SPAWN_INTERVAL: float = 0.12
const CHUNK: float = 20.0
const SHOOT_RANGE: float = 40.0
const SHOOT_COOLDOWN: float = 0.8
const HIT_CHANCE: float = 0.25
const TRACER_EVERY: int = 4
const TRACER_MAX: int = 200
const TRACER_SPEED: float = 2.5
const BUCKET_REBUILD: float = 0.25
const EXPLOSION_RADIUS: float = 8.0
const EXPLOSION_DAMAGE: float = 120.0
const EXPLOSION_TIME: float = 0.4
const BRUSH_RADIUS: float = 6.0
const BRUSH_RATE: float = 6.0
const BUILD_HP: float = 400.0
const PROP_HP: float = 120.0
const TEX_UPLOAD_TIME: float = 0.1
const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 64.0
const SHARP_ZOOM: float = 4.0
const BUTTON_ZOOM_STEP: float = 1.6

const CATALOG_PATH: String = "res://assets/catalog.json"
const INFANTRY_PATH: String = "res://assets/infantry.png"
const OBJECTS_PATH: String = "res://assets/objects.png"
const LANDSCAPE_PATH: String = "res://assets/landscape.png"
const BUILD_PREFIX: String = "res://assets/buildings_"
const BUILD_KEYS: Array = ["base", "damaged", "destroyed", "uncovered"]
const TAB_NAMES: Array = ["Солдаты", "Здания", "Объекты", "Ландшафт", "Взрыв"]

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

var cam: Camera2D
var cat: Dictionary = {}
var cat_b: Array = []
var cat_o: Array = []
var cat_l: Array = []
var infantry_tex: Texture2D
var obj_tex: Texture2D
var land_tex: Texture2D
var land_img: Image
var b_tex: Dictionary = {}
var tile6: Array = []
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
var explosions: Array = []
var buckets: Dictionary = {}
var bucket_timer: float = 0.0
var touches: Dictionary = {}
var moved: float = 0.0
var pinch_active: bool = false
var pinch_mid: Vector2 = Vector2.ZERO
var pinch_dist: float = 0.0
var brush: Dictionary = {}
var brushing: bool = false
var brush_pos: Vector2 = Vector2.ZERO
var spawn_timer: float = 0.0
var brush_label: Label
var catalog_panel: PanelContainer
var catalog_grid: GridContainer
var tab_index: int = 0


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

	if cat_b.size() > 0:
		for i in 8:
			_place_building(randi() % cat_b.size(), Vector2(randf_range(220.0, 380.0), randf_range(120.0, 480.0)))


func _load_catalog() -> void:
	var txt: String = FileAccess.get_file_as_string(CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		cat = parsed
	else:
		push_error("Не загрузился каталог " + CATALOG_PATH)
	cat_b = cat.get("buildings", [])
	cat_o = cat.get("objects", [])
	cat_l = cat.get("landscape", [])


func _load_textures() -> void:
	infantry_tex = load(INFANTRY_PATH) as Texture2D
	obj_tex = load(OBJECTS_PATH) as Texture2D
	land_tex = load(LANDSCAPE_PATH) as Texture2D
	for k in BUILD_KEYS:
		b_tex[k] = load(BUILD_PREFIX + k + ".png") as Texture2D
	land_img = land_tex.get_image()


func _init_terrain() -> void:
	tile6 = []
	for t in 8:
		var arr: PackedColorArray = PackedColorArray()
		for v in CELL_TEX:
			for u in CELL_TEX:
				var sx: int = t * 64 + int((float(u) + 0.5) * 64.0 / float(CELL_TEX))
				var sy: int = int((float(v) + 0.5) * 64.0 / float(CELL_TEX))
				arr.append(land_img.get_pixel(sx, sy))
		tile6.append(arr)
	ground.resize(NCELL * NCELL)
	ground.fill(2)
	heights.resize(NCELL * NCELL)
	heights.fill(0.0)
	bake = Image.create(TEX_W, TEX_W, false, Image.FORMAT_RGBA8)
	bake.fill(tile6[2][0])
	bake_tex = ImageTexture.create_from_image(bake)


# ---------- Ландшафт ----------

func _is_linear(t: int) -> bool:
	return t == 0 or t == 6


func _ntype(cx: int, cy: int, dx: int, dy: int) -> int:
	var nx: int = cx + dx
	var ny: int = cy + dy
	if nx < 0 or ny < 0 or nx >= NCELL or ny >= NCELL:
		return -1
	return ground[ny * NCELL + nx]


func _linked(cx: int, cy: int, t: int, dx: int, dy: int) -> bool:
	return _ntype(cx, cy, dx, dy) == t


func _linear_color(cx: int, cy: int, t: int, u: int, v: int) -> Color:
	var horiz: bool = _linked(cx, cy, t, 1, 0) or _linked(cx, cy, t, -1, 0)
	var vert: bool = _linked(cx, cy, t, 0, 1) or _linked(cx, cy, t, 0, -1)
	if horiz or not vert:
		return tile6[t][v * CELL_TEX + u]
	return tile6[t][u * CELL_TEX + v]


func _render_cell(cx: int, cy: int) -> void:
	var idx: int = cy * NCELL + cx
	var t: int = ground[idx]
	var shade: float = clamp(1.0 + heights[idx] * 0.02, 0.55, 1.35)
	for v in CELL_TEX:
		for u in CELL_TEX:
			var col: Color
			if _is_linear(t):
				col = _linear_color(cx, cy, t, u, v)
			else:
				col = tile6[t][v * CELL_TEX + u]
				var dx: int = 0
				var dy: int = 0
				if u == 0:
					dx = -1
				elif u == CELL_TEX - 1:
					dx = 1
				if v == 0:
					dy = -1
				elif v == CELL_TEX - 1:
					dy = 1
				if dx != 0 or dy != 0:
					var nt: int = _ntype(cx, cy, dx, dy)
					if nt >= 0 and nt != t and not _is_linear(nt):
						col = col.lerp(tile6[nt][v * CELL_TEX + u], 0.5)
			col = Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			bake.set_pixel(cx * CELL_TEX + u, cy * CELL_TEX + v, col)
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
		_render_cell(ki % NCELL, ki / NCELL)


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clamp(int(floor(p.x / CELL_M)), 0, NCELL - 1), clamp(int(floor(p.y / CELL_M)), 0, NCELL - 1))


func _terrain_h(p: Vector2) -> float:
	var c: Vector2i = _cell_of(p)
	return heights[c.y * NCELL + c.x]


func _paint_ground(p: Vector2, t: int) -> void:
	var r: int = int(ceil(BRUSH_RADIUS / CELL_M))
	var c: Vector2i = _cell_of(p)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x: int = c.x + dx
			var y: int = c.y + dy
			if x < 0 or y < 0 or x >= NCELL or y >= NCELL:
				continue
			var center: Vector2 = Vector2((float(x) + 0.5) * CELL_M, (float(y) + 0.5) * CELL_M)
			if center.distance_to(p) > BRUSH_RADIUS:
				continue
			ground[y * NCELL + x] = t
			_mark(x, y)


func _shape(p: Vector2, sign: float, delta: float) -> void:
	var r: int = int(ceil(BRUSH_RADIUS / CELL_M))
	var c: Vector2i = _cell_of(p)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x: int = c.x + dx
			var y: int = c.y + dy
			if x < 0 or y < 0 or x >= NCELL or y >= NCELL:
				continue
			var center: Vector2 = Vector2((float(x) + 0.5) * CELL_M, (float(y) + 0.5) * CELL_M)
			var d: float = center.distance_to(p)
			if d > BRUSH_RADIUS:
				continue
			var w: float = 1.0 - d / BRUSH_RADIUS
			var idx: int = y * NCELL + x
			heights[idx] = clamp(heights[idx] + sign * BRUSH_RATE * w * delta, HEIGHT_MIN, HEIGHT_MAX)
			_mark(x, y)


func _crater(p: Vector2) -> void:
	var c: Vector2i = _cell_of(p)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x: int = c.x + dx
			var y: int = c.y + dy
			if x < 0 or y < 0 or x >= NCELL or y >= NCELL:
				continue
			var center: Vector2 = Vector2((float(x) + 0.5) * CELL_M, (float(y) + 0.5) * CELL_M)
			var d: float = center.distance_to(p)
			if d > 4.0:
				continue
			var idx: int = y * NCELL + x
			heights[idx] = clamp(heights[idx] - 2.0 * (1.0 - d / 4.0), HEIGHT_MIN, HEIGHT_MAX)
			_mark(x, y)


# ---------- Солдаты ----------

func _spawn_soldier(p: Vector2, team: int) -> void:
	if soldiers.size() >= MAX_SOLDIERS:
		return
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


func _alive(s: Dictionary) -> bool:
	return float(s["hp"]) > 0.0


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


func _update_orders(delta: float) -> void:
	for s in soldiers:
		if not s["has_target"] or not _alive(s):
			continue
		var pos: Vector2 = s["pos"] as Vector2
		var target: Vector2 = s["target"] as Vector2
		var to_t: Vector2 = target - pos
		var dist: float = to_t.length()
		var dir: Vector2 = Vector2.ZERO
		if dist > 0.001:
			dir = to_t / dist
		var mult: float = 1.0
		if int(s["inside"]) < 0:
			var slope: float = (_terrain_h(pos + dir * CELL_M) - _terrain_h(pos)) / CELL_M
			mult = clamp(1.0 - slope * 0.8, 0.3, 1.3)
		var step: float = SPEED * mult * delta
		if dist <= step:
			s["pos"] = target
			s["has_target"] = false
			_arrive(s)
		else:
			s["pos"] = pos + dir * step


func _arrive(s: Dictionary) -> void:
	var ord: String = s["order"]
	var bi: int = int(s["house"])
	if ord == "enter":
		if bi >= 0 and bi < buildings.size() and float(buildings[bi]["hp"]) > 0.0:
			s["inside"] = bi
			s["pos"] = _interior_point(buildings[bi])
	elif ord == "exit":
		if bi >= 0 and bi < buildings.size():
			s["pos"] = _bdoor(buildings[bi]) + Vector2(0.0, 1.0)
		s["inside"] = -1
	s["order"] = ""
	s["house"] = -1


func _update_tracers(delta: float) -> void:
	for i in range(tracers.size() - 1, -1, -1):
		var tr: Dictionary = tracers[i]
		tr["t"] = float(tr["t"]) + delta * TRACER_SPEED
		if float(tr["t"]) > 1.3:
			tracers.remove_at(i)


func _update_explosions(delta: float) -> void:
	for i in range(explosions.size() - 1, -1, -1):
		var ex: Dictionary = explosions[i]
		ex["t"] = float(ex["t"]) + delta
		if float(ex["t"]) >= EXPLOSION_TIME:
			explosions.remove_at(i)


func _bucket_key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.y / CHUNK)))


func _rebuild_buckets() -> void:
	buckets.clear()
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if int(s["inside"]) >= 0 or not _alive(s):
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
				if int(o["team"]) == int(me["team"]):
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
		if float(s["cd"]) > 0.0 or int(s["inside"]) >= 0 or not _alive(s):
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


func _selected_outside() -> Array:
	var out: Array = []
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["selected"] and int(s["inside"]) < 0 and _alive(s):
			out.append(i)
	return out


func _selected_inside(bi: int) -> Array:
	var out: Array = []
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if s["selected"] and int(s["inside"]) == bi and _alive(s):
			out.append(i)
	return out


func _clear_selection() -> void:
	for s in soldiers:
		s["selected"] = false


func _move_selected(wp: Vector2) -> void:
	var sel: Array = _selected_outside()
	if sel.is_empty():
		return
	var cols: int = int(ceil(sqrt(float(sel.size()))))
	for n in sel.size():
		var s: Dictionary = soldiers[sel[n]]
		s["order"] = ""
		s["house"] = -1
		s["target"] = wp + Vector2(float(n % cols), float(n / cols)) * 1.5 - Vector2(float(cols), float(cols)) * 0.75
		s["has_target"] = true


# ---------- Здания и объекты ----------

func _rect_of(arr: Array) -> Rect2:
	return Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))


func _base_size_m(b: Dictionary) -> Vector2:
	var r: Rect2 = _rect_of(cat_b[int(b["bid"])]["base"])
	return r.size * SCALE_M


func _bfoot(b: Dictionary) -> Rect2:
	var sz: Vector2 = _base_size_m(b)
	return Rect2((b["pos"] as Vector2) - sz * 0.5, sz)


func _bdoor(b: Dictionary) -> Vector2:
	var sz: Vector2 = _base_size_m(b)
	var p: Vector2 = b["pos"] as Vector2
	return Vector2(p.x, p.y + sz.y * 0.5 + 0.6)


func _door_rect(b: Dictionary) -> Rect2:
	var d: Vector2 = _bdoor(b)
	return Rect2(d - Vector2(1.5, 0.8), Vector2(3.0, 1.6))


func _interior_point(b: Dictionary) -> Vector2:
	var fr: Rect2 = _bfoot(b).grow(-1.0)
	return Vector2(randf_range(fr.position.x, fr.end.x), randf_range(fr.position.y, fr.end.y))


func _clamp_in(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clamp(p.x, r.position.x, r.end.x), clamp(p.y, r.position.y, r.end.y))


func _place_building(bid: int, p: Vector2) -> void:
	if buildings.size() >= MAX_BUILDINGS or bid < 0 or bid >= cat_b.size():
		return
	buildings.append({"bid": bid, "pos": p, "hp": BUILD_HP, "occ0": 0, "occ1": 0})


func _place_prop(oid: int, p: Vector2) -> void:
	if props.size() >= MAX_PROPS or oid < 0 or oid >= cat_o.size():
		return
	props.append({"oid": oid, "pos": p, "hp": PROP_HP})


func _building_variant(b: Dictionary) -> String:
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
		if int(s["team"]) == 0:
			b["occ0"] = int(b["occ0"]) + 1
		else:
			b["occ1"] = int(b["occ1"]) + 1


func _destroy_building(bi: int) -> void:
	var b: Dictionary = buildings[bi]
	b["hp"] = 0.0
	var c: Vector2 = b["pos"] as Vector2
	for s in soldiers:
		if int(s["inside"]) == bi:
			s["inside"] = -1
			s["hp"] = 0.0
			s["pos"] = c
		if int(s["house"]) == bi and s["order"] != "":
			s["order"] = ""
			s["house"] = -1
			s["has_target"] = false


func _order_enter(bi: int, list: Array) -> void:
	var b: Dictionary = buildings[bi]
	var door: Vector2 = _bdoor(b)
	var cols: int = int(ceil(sqrt(float(list.size()))))
	for n in list.size():
		var s: Dictionary = soldiers[list[n]]
		s["order"] = "enter"
		s["house"] = bi
		s["target"] = door + Vector2(float(n % cols) - cols * 0.5, float(n / cols)) * 1.2
		s["has_target"] = true


func _order_exit(bi: int, list: Array) -> void:
	var b: Dictionary = buildings[bi]
	var door: Vector2 = _bdoor(b)
	var cols: int = int(ceil(sqrt(float(list.size()))))
	for n in list.size():
		var s: Dictionary = soldiers[list[n]]
		s["order"] = "exit"
		s["house"] = bi
		s["target"] = door + Vector2(float(n % cols) - cols * 0.5, float(n / cols) + 1.0) * 1.2
		s["has_target"] = true


func _door_tap(bi: int) -> void:
	var out: Array = _selected_outside()
	if not out.is_empty():
		_order_enter(bi, out)
		return
	var ins: Array = _selected_inside(bi)
	if not ins.is_empty():
		_order_exit(bi, ins)


func _building_tap(bi: int, wp: Vector2) -> void:
	var out: Array = _selected_outside()
	if not out.is_empty():
		_order_enter(bi, out)
		return
	var ins: Array = _selected_inside(bi)
	if ins.is_empty():
		return
	var fr: Rect2 = _bfoot(buildings[bi]).grow(-1.0)
	var tp: Vector2 = _clamp_in(wp, fr)
	var cols: int = int(ceil(sqrt(float(ins.size()))))
	for n in ins.size():
		var s: Dictionary = soldiers[ins[n]]
		var off: Vector2 = Vector2(float(n % cols) - cols * 0.5, float(n / cols)) * 1.2
		s["order"] = ""
		s["house"] = -1
		s["target"] = _clamp_in(tp + off, fr)
		s["has_target"] = true


func _explode(p: Vector2) -> void:
	explosions.append({"pos": p, "t": 0.0})
	_crater(p)
	for s in soldiers:
		if not _alive(s) or int(s["inside"]) >= 0:
			continue
		var d: float = (s["pos"] as Vector2).distance_to(p)
		if d < EXPLOSION_RADIUS:
			s["hp"] = float(s["hp"]) - EXPLOSION_DAMAGE * (1.0 - d / EXPLOSION_RADIUS)
	for bi in buildings.size():
		var b: Dictionary = buildings[bi]
		if float(b["hp"]) <= 0.0:
			continue
		var fr: Rect2 = _bfoot(b)
		var near: Vector2 = _clamp_in(p, fr)
		var d2: float = near.distance_to(p)
		if d2 < EXPLOSION_RADIUS:
			b["hp"] = float(b["hp"]) - EXPLOSION_DAMAGE * 2.0 * (1.0 - d2 / EXPLOSION_RADIUS)
			if float(b["hp"]) <= 0.0:
				_destroy_building(bi)
	for pr in props:
		if float(pr["hp"]) <= 0.0:
			continue
		var dp: float = (pr["pos"] as Vector2).distance_to(p)
		if dp < EXPLOSION_RADIUS:
			pr["hp"] = float(pr["hp"]) - EXPLOSION_DAMAGE * 1.5 * (1.0 - dp / EXPLOSION_RADIUS)


# ---------- Касания и камера ----------

func _to_world_px(sp: Vector2) -> Vector2:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	return cam.position + (sp - vs * 0.5) / cam.zoom.x


func _to_world_m(sp: Vector2) -> Vector2:
	return _to_world_px(sp) / PX


func _zoom_about(sp: Vector2, factor: float) -> void:
	var before: Vector2 = _to_world_px(sp)
	var z: float = clamp(cam.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	cam.zoom = Vector2(z, z)
	var after: Vector2 = _to_world_px(sp)
	cam.position += before - after


func _zoom_center(factor: float) -> void:
	_zoom_about(get_viewport().get_visible_rect().size * 0.5, factor)


func _pinch() -> void:
	var keys: Array = touches.keys()
	var p0: Vector2 = touches[keys[0]]
	var p1: Vector2 = touches[keys[1]]
	var mid: Vector2 = (p0 + p1) * 0.5
	var dist: float = (p0 - p1).length()
	if pinch_active:
		cam.position -= (mid - pinch_mid) / cam.zoom.x
		if pinch_dist > 1.0 and dist > 1.0:
			var f: float = clamp(dist / pinch_dist, 0.85, 1.18)
			_zoom_about(mid, f)
	pinch_active = true
	pinch_mid = mid
	pinch_dist = dist


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			touches[t.index] = t.position
			pinch_active = false
			if touches.size() == 1:
				moved = 0.0
				brush_pos = _to_world_m(t.position)
				brushing = not brush.is_empty()
				spawn_timer = 0.0
			else:
				brushing = false
		else:
			var was_single: bool = touches.size() == 1
			touches.erase(t.index)
			pinch_active = false
			brushing = false
			if was_single and moved < TAP_MAX_MOVE:
				var wp: Vector2 = _to_world_m(t.position)
				if brush.is_empty():
					_select_tap(wp)
				else:
					_brush_tap(wp)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event as InputEventScreenDrag
		touches[d.index] = d.position
		if touches.size() == 1:
			moved += d.relative.length()
			if brush.is_empty():
				cam.position -= d.relative / cam.zoom.x
			else:
				brush_pos = _to_world_m(d.position)
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
		_paint_ground(wp, int(brush["id"]))
	elif k == "shape":
		_shape(wp, float(brush["sign"]), 0.25)


func _select_tap(wp: Vector2) -> void:
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		if int(s["team"]) != 0 or not _alive(s):
			continue
		var r: float = INSIDE_RADIUS if int(s["inside"]) >= 0 else SELECT_RADIUS
		if (s["pos"] as Vector2).distance_to(wp) <= r:
			_clear_selection()
			s["selected"] = true
			return
	for bi in buildings.size():
		var b: Dictionary = buildings[bi]
		if float(b["hp"]) <= 0.0:
			continue
		if _door_rect(b).has_point(wp):
			_door_tap(bi)
			return
		if _bfoot(b).has_point(wp):
			_building_tap(bi, wp)
			return
	_move_selected(wp)


# ---------- Отрисовка ----------

func _draw() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var vp: Vector2 = vs / cam.zoom.x
	var view: Rect2 = Rect2(cam.position - vp * 0.5, vp)

	draw_texture_rect(bake_tex, Rect2(0.0, 0.0, MAP_M * PX, MAP_M * PX), false)

	for bi in buildings.size():
		var b: Dictionary = buildings[bi]
		var key: String = _building_variant(b)
		var rect: Rect2 = _rect_of(cat_b[int(b["bid"])][key])
		var sz: Vector2 = rect.size * SCALE_M * PX
		var c: Vector2 = (b["pos"] as Vector2) * PX
		var dest: Rect2 = Rect2(c - sz * 0.5, sz)
		if not view.intersects(dest):
			continue
		var tex: Texture2D = b_tex[key]
		if tex != null:
			draw_texture_rect_region(tex, dest, rect)

	for pr in props:
		if float(pr["hp"]) <= 0.0:
			continue
		var prect: Rect2 = _rect_of(cat_o[int(pr["oid"])]["rect"])
		var psz: Vector2 = prect.size * SCALE_M * PX
		var pc: Vector2 = (pr["pos"] as Vector2) * PX
		var pdest: Rect2 = Rect2(pc - psz * 0.5, psz)
		if not view.intersects(pdest):
			continue
		var a: float = 1.0 if float(pr["hp"]) >= PROP_HP * 0.5 else 0.55
		if obj_tex != null:
			draw_texture_rect_region(obj_tex, pdest, prect, Color(1, 1, 1, a))

	for s in soldiers:
		if int(s["inside"]) < 0 or not _alive(s):
			continue
		var bi: int = int(s["inside"])
		var ip: Vector2 = (s["pos"] as Vector2) * PX
		if infantry_tex != null:
			var src_i: Rect2 = Rect2(STAND_ARMED.x * 64.0, STAND_ARMED.y * 64.0, 64.0, 64.0)
			var dest_i: Rect2 = Rect2(ip - Vector2.ONE * 4.5, Vector2.ONE * 9.0)
			draw_texture_rect_region(infantry_tex, dest_i, src_i)
		if s["selected"]:
			draw_arc(ip, 5.0, 0.0, TAU, 12, Color(1, 1, 0), 1.2)

	for s in soldiers:
		if int(s["inside"]) >= 0:
			continue
		var p: Vector2 = (s["pos"] as Vector2) * PX
		if not view.grow(20.0).has_point(p):
			continue
		var frames: Array = get_frames(s)
		var idx: int = int(float(s["anim_t"]) / FRAME_TIME) % frames.size()
		var cell: Vector2i = frames[idx]
		if infantry_tex != null:
			var src_s: Rect2 = Rect2(cell.x * 64.0, cell.y * 64.0, 64.0, 64.0)
			var dest_s: Rect2 = Rect2(p - Vector2.ONE * SPRITE_SIZE * 0.5, Vector2.ONE * SPRITE_SIZE)
			draw_texture_rect_region(infantry_tex, dest_s, src_s)
		if s["has_target"]:
			draw_line(p, (s["target"] as Vector2) * PX, Color(1, 1, 1, 0.25), 1.0)
		if s["selected"]:
			draw_arc(p, SPRITE_SIZE * 0.6, 0.0, TAU, 16, Color(1, 1, 0), 1.5)

	for ex in explosions:
		var f: float = float(ex["t"]) / EXPLOSION_TIME
		var ep: Vector2 = (ex["pos"] as Vector2) * PX
		draw_arc(ep, EXPLOSION_RADIUS * PX * f, 0.0, TAU, 24, Color(1.0, 0.6, 0.2, 1.0 - f), 2.0)

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
			spawn_timer -= delta
			if spawn_timer <= 0.0:
				_spawn_soldier(brush_pos, int(brush["team"]))
				spawn_timer = SPAWN_INTERVAL
		elif k == "ground":
			_paint_ground(brush_pos, int(brush["id"]))
		elif k == "shape":
			_shape(brush_pos, float(brush["sign"]), delta)

	_render_dirty()
	if tex_dirty:
		tex_timer -= delta
		if tex_timer <= 0.0:
			bake_tex.update(bake)
			tex_dirty = false
			tex_timer = TEX_UPLOAD_TIME

	_update_orders(delta)
	_update_tracers(delta)
	_update_explosions(delta)

	bucket_timer -= delta
	if bucket_timer <= 0.0:
		_rebuild_buckets()
		bucket_timer = BUCKET_REBUILD

	_update_shooting(delta)
	_count_occupants()

	for s in soldiers:
		s["anim_t"] = float(s["anim_t"]) + delta
	queue_redraw()


# ---------- Интерфейс ----------

func _make_button(text: String, min_sz: Vector2, font_size: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_sz
	b.add_theme_font_size_override("font_size", font_size)
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
	left.offset_right = 620.0
	left.offset_bottom = -20.0
	left.add_theme_constant_override("separation", 16)
	layer.add_child(left)
	left.add_child(_make_button("Каталог", Vector2(200, 120), 36, _open_catalog))
	left.add_child(_make_button("Выбор", Vector2(200, 120), 36, _clear_brush))

	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -170.0
	right.offset_top = -290.0
	right.offset_right = -20.0
	right.offset_bottom = -20.0
	right.add_theme_constant_override("separation", 20)
	layer.add_child(right)
	right.add_child(_make_button("+", Vector2(150, 120), 56, func(): _zoom_center(BUTTON_ZOOM_STEP)))
	right.add_child(_make_button("−", Vector2(150, 120), 56, func(): _zoom_center(1.0 / BUTTON_ZOOM_STEP)))

	catalog_panel = PanelContainer.new()
	catalog_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catalog_panel.offset_left = 16.0
	catalog_panel.offset_top = 16.0
	catalog_panel.offset_right = -16.0
	catalog_panel.offset_bottom = -16.0
	catalog_panel.visible = false
	layer.add_child(catalog_panel)

	var box := VBoxContainer.new()
	catalog_panel.add_child(box)

	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	for i in TAB_NAMES.size():
		tabs.add_child(_make_button(TAB_NAMES[i], Vector2(0, 90), 26, _set_tab.bind(i)))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	catalog_grid = GridContainer.new()
	catalog_grid.columns = 4
	catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(catalog_grid)

	box.add_child(_make_button("Закрыть", Vector2(0, 90), 30, _close_catalog))


func _open_catalog() -> void:
	_fill_catalog()
	catalog_panel.visible = true


func _close_catalog() -> void:
	catalog_panel.visible = false


func _set_tab(i: int) -> void:
	tab_index = i
	_fill_catalog()


func _clear_brush() -> void:
	brush = {}
	brush_label.text = "Выбор"


func _on_item(data: Dictionary) -> void:
	brush = data
	catalog_panel.visible = false
	brush_label.text = str(data.get("name", ""))


func _atlas(tex: Texture2D, r: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = r
	return a


func _add_item(icon: Texture2D, text: String, data: Dictionary) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(130, 130)
	b.text = text
	b.add_theme_font_size_override("font_size", 26)
	if icon != null:
		b.icon = icon
		b.expand_icon = true
	b.pressed.connect(_on_item.bind(data))
	catalog_grid.add_child(b)


func _fill_catalog() -> void:
	for c in catalog_grid.get_children():
		c.queue_free()
	if tab_index == 0:
		_add_item(_atlas(infantry_tex, Rect2(5 * 64.0, 8 * 64.0, 64.0, 64.0)), "Синие", {"kind": "soldier", "team": 0, "name": "Спавн: синие"})
		_add_item(_atlas(infantry_tex, Rect2(5 * 64.0, 8 * 64.0, 64.0, 64.0)), "Красные", {"kind": "soldier", "team": 1, "name": "Спавн: красные"})
	elif tab_index == 1:
		for i in cat_b.size():
			var r: Rect2 = _rect_of(cat_b[i]["base"])
			_add_item(_atlas(b_tex["base"], r), "", {"kind": "building", "id": i, "name": "Дом #" + str(i)})
	elif tab_index == 2:
		for i in cat_o.size():
			var r2: Rect2 = _rect_of(cat_o[i]["rect"])
			_add_item(_atlas(obj_tex, r2), "", {"kind": "object", "id": i, "name": "Объект #" + str(i)})
	elif tab_index == 3:
		for i in cat_l.size():
			_add_item(_atlas(land_tex, Rect2(i * 64.0, 0.0, 64.0, 64.0)), "", {"kind": "ground", "id": i, "name": "Ландшафт: " + str(cat_l[i])})
		_add_item(null, "Поднять", {"kind": "shape", "sign": 1.0, "name": "Поднять землю"})
		_add_item(null, "Опустить", {"kind": "shape", "sign": -1.0, "name": "Опустить землю"})
	else:
		_add_item(null, "Взрыв", {"kind": "explode", "name": "Взрыв"})

