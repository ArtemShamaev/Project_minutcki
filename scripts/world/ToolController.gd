extends Node3D
## Handles mouse interaction with the world: building tools, previews, selection.

signal tooltip(text: String, ok: bool)
signal selected(b: Building)
signal tool_changed(tool: Dictionary)
signal action_done(kind: String)
signal agent_selected(agent)
signal road_selected(tile: Vector2i)

var city: City
var rig
var overlays
var terrain
var brender
var tool := {"type": "select"}
var hover := Vector2i(-1, -1)
var hover_b: Building = null
var selected_b: Building = null
var dragging := false
var drag_start := Vector2i.ZERO
var rot_dir := -1
var imesh: ImmediateMesh
var preview: MeshInstance3D
var ghost: Node3D
var ghost_key := ""
var _last_tree := Vector2i(-1, -1)
var hover_f := Vector2(-1, -1)      # precise ground point (x, z)
var brush := 3.0
var _level_target := 0.0
var _tf_cost_acc := 0.0
var line_stops: Array = []
var cur_district := 0
var _road_axis := -1      # axis of the first drag movement
var _road_locked := false
var _road_flip := false
var traffic
var peds
var selected_agent = null
var _line_err := ""

const C_OK := Color(0.3, 0.95, 0.45, 0.45)
const C_BAD := Color(1.0, 0.25, 0.2, 0.5)
const C_DEL := Color(1.0, 0.35, 0.2, 0.45)
const C_SEL := Color(0.3, 0.8, 1.0, 0.5)
const C_HOVER := Color(1.0, 0.95, 0.5, 0.35)


func setup(c: City, r, ov, te, br) -> void:
	city = c
	rig = r
	overlays = ov
	terrain = te
	brender = br
	imesh = ImmediateMesh.new()
	preview = MeshInstance3D.new()
	preview.mesh = imesh
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/preview.gdshader")
	m.render_priority = 5
	preview.material_override = m
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	city.building_removed.connect(func(b, _r):
		if selected_b == b:
			select(null))


func set_tool(t: Dictionary) -> void:
	tool = t
	dragging = false
	rot_dir = -1
	line_stops.clear()
	_line_err = ""
	_clear_ghost()
	var zoning: bool = t.type == "zone" or t.type == "dezone"
	overlays.set_show_area(zoning)
	overlays.set_district_fill(t.type == "district")
	terrain.set_grid(0.35 if t.type in ["road", "path", "rail", "zone", "dezone", "service"] else 0.0)
	if t.type != "select":
		select(null)
	tool_changed.emit(t)
	tooltip.emit("", true)


func select(b: Building) -> void:
	selected_b = b
	selected.emit(b)


func _clear_ghost() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
	ghost_key = ""


func _mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press()
			else:
				_release()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and dragging:
			dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and tool.type == "line" and line_stops.size() > 0:
			_finish_line()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_R and not k.shift_pressed and tool.type == "service":
			rot_dir = 0 if rot_dir < 0 else (rot_dir + 1) % 4
			get_viewport().set_input_as_handled()
		elif tool.type in ["road", "path", "rail"] and k.keycode == KEY_TAB:
			_road_flip = not _road_flip
			get_viewport().set_input_as_handled()
		elif tool.type == "line" and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and line_stops.size() > 0:
			_finish_line()
			get_viewport().set_input_as_handled()
		elif tool.type in ["terraform", "district"] and (k.keycode == KEY_BRACKETLEFT or k.keycode == KEY_BRACKETRIGHT):
			brush = clamp(brush + (1.0 if k.keycode == KEY_BRACKETRIGHT else -1.0), 1.0, 8.0)
			get_viewport().set_input_as_handled()


func _press() -> void:
	if hover.x < 0:
		return
	match tool.type:
		"select":
			var ag = _pick_agent(get_viewport().get_mouse_position())
			if ag != null:
				select(null)
				selected_agent = ag
				agent_selected.emit(ag)
			elif hover_b == null and city.is_road(hover):
				select(null)
				road_selected.emit(hover)
			else:
				select(hover_b)
		"road", "path", "rail", "zone", "dezone", "bulldoze":
			dragging = true
			drag_start = hover
			_road_axis = -1
			_road_locked = false
			_road_flip = false
		"tree":
			dragging = true
			_plant(hover)
		"line":
			_line_click()
		"district":
			if tool.mode == "new" or (tool.mode == "paint" and not city.districts.has(cur_district)):
				cur_district = city.new_district()
				tool = {"type": "district", "mode": "paint"}
				tool_changed.emit(tool)
			elif tool.mode == "paint":
				var d := city.district[city.idx(hover.x, hover.y)]
				if d > 0 and Input.is_key_pressed(KEY_CTRL):
					cur_district = d
			dragging = true
		"terraform":
			dragging = true
			_level_target = city.height_at(hover_f.x, hover_f.y)
			_tf_cost_acc = 0.0
		"service":
			var b: Building = city.place_service(tool.id, hover, rot_dir)
			if b:
				action_done.emit("place")
			else:
				action_done.emit("error")


func _release() -> void:
	if not dragging:
		return
	dragging = false
	match tool.type:
		"road":
			var path := city.road_path(drag_start, hover, _road_mode())
			if city.build_roads(path, tool.get("rtype", 1)):
				action_done.emit("road")
			else:
				action_done.emit("error")
		"path":
			if city.build_paths(city.road_path(drag_start, hover, _road_mode())):
				action_done.emit("road")
			else:
				action_done.emit("error")
		"rail":
			if city.build_rails(city.road_path(drag_start, hover, _road_mode())):
				action_done.emit("road")
			else:
				action_done.emit("error")
		"zone":
			if city.paint_zone(_drag_rect(), tool.zone) > 0:
				action_done.emit("zone")
		"dezone":
			if city.paint_zone(_drag_rect(), 0) > 0:
				action_done.emit("zone")
		"bulldoze":
			if city.bulldoze(_drag_rect()) > 0:
				action_done.emit("bulldoze")
		"terraform":
			if _tf_cost_acc > 0.0:
				action_done.emit("terraform")


func _line_stop_at(p: Vector2i) -> Variant:
	if tool.kind != "metro":
		return p if city.is_road(p) else null
	var b := city.building_at(p)
	return b.id if b and b.type == "metro" else null


func _line_click() -> void:
	var s = _line_stop_at(hover)
	if s == null:
		_line_err = "Кликните по дороге" if tool.kind != "metro" else "Кликните по станции метро"
		action_done.emit("error")
		return
	if line_stops.size() >= 2 and s == line_stops[0]:
		_finish_line()
		return
	if line_stops.size() > 0 and s == line_stops[-1]:
		return
	line_stops.append(s)
	_line_err = ""
	action_done.emit("zone")


func _finish_line() -> void:
	var reason := city.check_line(tool.kind, line_stops)
	if reason != "":
		_line_err = reason
		action_done.emit("error")
		if line_stops.size() < 2:
			line_stops.clear()
		return
	city.add_line(tool.kind, line_stops)
	line_stops.clear()
	_line_err = ""
	action_done.emit("place")


func _road_mode() -> int:
	var m := _road_axis if _road_axis >= 0 else -1
	if m < 0:
		return -1
	return 1 - m if _road_flip else m


func _plant(p: Vector2i) -> void:
	if p == _last_tree:
		return
	_last_tree = p
	city.plant_tree(p)


func _drag_rect() -> Rect2i:
	var a := Vector2i(mini(drag_start.x, hover.x), mini(drag_start.y, hover.y))
	var b := Vector2i(maxi(drag_start.x, hover.x), maxi(drag_start.y, hover.y))
	return Rect2i(a, b - a + Vector2i.ONE)


func _process(delta: float) -> void:
	Prof.b("tools")
	_process_inner(delta)
	Prof.e("tools")


func _process_inner(delta: float) -> void:
	if city == null or rig == null:
		return
	var mp := get_viewport().get_mouse_position()
	if has_meta("debug_hover"):
		hover = get_meta("debug_hover")
		_draw_preview()
		return
	if _mouse_over_ui() and not dragging:
		hover = Vector2i(-1, -1)
		hover_b = null
	else:
		var gp = rig.ground_point(mp)
		if gp != null:
			hover_f = Vector2(gp.x, gp.z)
			var t := Vector2i(floori(gp.x), floori(gp.z))
			if dragging:
				t = Vector2i(clampi(t.x, 0, city.n - 1), clampi(t.y, 0, city.n - 1))
			hover = t if city.inb(t.x, t.y) else Vector2i(-1, -1)
		else:
			hover = Vector2i(-1, -1)
		hover_b = _pick_building(mp) if tool.type == "select" else null
	if dragging and tool.type in ["road", "path", "rail"] and hover.x >= 0 and hover != drag_start and not _road_locked:
		# the road starts along the dominant drag direction; it is re-evaluated until the
		# cursor is 3 tiles away, so a slightly diagonal first move doesn't flip the corner
		var dd := hover - drag_start
		if abs(dd.x) != abs(dd.y):
			_road_axis = 0 if abs(dd.x) > abs(dd.y) else 1
		elif _road_axis < 0:
			_road_axis = 0
		if abs(dd.x) + abs(dd.y) >= 3:
			_road_locked = true
	if dragging and tool.type == "tree" and hover.x >= 0:
		_plant(hover)
	if dragging and tool.type == "district" and hover.x >= 0:
		city.paint_district(hover_f, brush * 0.7, 0 if tool.mode == "erase" else cur_district)
	if dragging and tool.type == "terraform" and hover.x >= 0:
		var c := city.terraform(hover_f, brush, tool.mode, 1.4 * delta, _level_target)
		if c > 0.0:
			_tf_cost_acc += c
	_draw_preview()


func _pick_agent(mp: Vector2):
	var cam: Camera3D = rig.cam
	var best = null
	var bd := 18.0
	var lists: Array = []
	if traffic:
		lists.append(traffic.cars)
	if peds:
		lists.append(peds.peds)
	for l in lists:
		for a in l:
			var wp: Vector3 = a.node.global_position + Vector3(0, 0.05, 0)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			var d := sp.distance_to(mp)
			if d < bd:
				bd = d
				best = a
	return best


func _pick_building(mp: Vector2) -> Building:
	var r: Array = rig.ray(mp)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if d.y >= 0:
		return null
	# march from y = 16 down to the ground
	var t0 := (16.0 - o.y) / d.y
	var t1 := (-1.0 - o.y) / d.y
	t0 = max(t0, 0.0)
	var t := t0
	while t <= t1:
		var p := o + d * t
		var b := city.building_at(Vector2i(floori(p.x), floori(p.z)))
		if b:
			var nd: Node3D = brender.nodes.get(b.id)
			var h: float = nd.get_meta("height", 1.0) if nd else 1.0
			if p.y <= b.base_y + h:
				return b
		elif p.y < city.height_at(p.x, p.z) - 0.05:
			return null
		t += 0.08
	return null


# ---------------------------------------------------------------- preview
func _quad(r: Rect2, y: float, c: Color) -> void:
	## Quad draped over the terrain (split along tile lines).
	if y < -1.0:
		for v in [Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y)]:
			imesh.surface_set_color(c)
			imesh.surface_add_vertex(v)
		return
	var xs := _splits(r.position.x, r.end.x)
	var zs := _splits(r.position.y, r.end.y)
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			var a := Vector3(x0, city.height_at(x0, z0) + y, z0)
			var b := Vector3(x1, city.height_at(x1, z0) + y, z0)
			var cc := Vector3(x1, city.height_at(x1, z1) + y, z1)
			var d := Vector3(x0, city.height_at(x0, z1) + y, z1)
			for v in [a, b, cc, a, cc, d]:
				imesh.surface_set_color(c)
				imesh.surface_add_vertex(v)


func _stop_tile(s) -> Vector2i:
	if s is Vector2i:
		return s
	var b: Building = city.buildings.get(int(s))
	return Vector2i(b.x, b.y) if b else Vector2i.ZERO


func _seg(a: Vector3, b: Vector3, c: Color) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var side := Vector3(-d.z, 0, d.x).normalized() * 0.1
	var ha: float = max(city.height_at(a.x, a.z), 0.0) + 0.4
	var hb: float = max(city.height_at(b.x, b.z), 0.0) + 0.4
	var A := Vector3(a.x, ha, a.z)
	var B := Vector3(b.x, hb, b.z)
	for v in [A - side, B - side, B + side, A - side, B + side, A + side]:
		imesh.surface_set_color(c)
		imesh.surface_add_vertex(v)


func _splits(a: float, b: float) -> Array:
	var out := [a]
	var k := floori(a) + 1
	while k < b:
		out.append(float(k))
		k += 1
	out.append(b)
	return out


func _cell(p: Vector2i, c: Color, y: float = 0.05) -> void:
	_quad(Rect2(p.x + 0.06, p.y + 0.06, 0.88, 0.88), y, c)


func _outline(r: Rect2, c: Color, w: float = 0.07, y: float = 0.06) -> void:
	_quad(Rect2(r.position.x, r.position.y, r.size.x, w), y, c)
	_quad(Rect2(r.position.x, r.end.y - w, r.size.x, w), y, c)
	_quad(Rect2(r.position.x, r.position.y, w, r.size.y), y, c)
	_quad(Rect2(r.end.x - w, r.position.y, w, r.size.y), y, c)


func _ring(center: Vector3, radius: float, c: Color) -> void:
	var segs := 64
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * radius
		var q0 := center + Vector3(cos(a0), 0, sin(a0)) * (radius - 0.15)
		var q1 := center + Vector3(cos(a1), 0, sin(a1)) * (radius - 0.15)
		for v in [p0, p1, q1, p0, q1, q0]:
			imesh.surface_set_color(c)
			imesh.surface_add_vertex(Vector3(v.x, city.height_at(v.x, v.z) + 0.08, v.z))


func _draw_preview() -> void:
	imesh.clear_surfaces()
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := ""
	var ok := true
	# keep at least one triangle so the surface is valid
	_quad(Rect2(-1000, -1000, 0.001, 0.001), -5.0, Color(0, 0, 0, 0))
	if selected_b and city.buildings.has(selected_b.id):
		_outline(Rect2(selected_b.rect()), C_SEL)
		if selected_b.is_service() and Defs.SERVICES[selected_b.type].has("radius"):
			_ring(selected_b.center(), Defs.SERVICES[selected_b.type].radius, Color(0.3, 0.8, 1.0, 0.5))
	if hover.x >= 0:
		match tool.type:
			"select":
				if hover_b and hover_b != selected_b:
					_outline(Rect2(hover_b.rect()), C_HOVER)
			"road":
				var path: Array[Vector2i] = []
				if dragging:
					path = city.road_path(drag_start, hover, _road_mode())
				else:
					path.append(hover)
				var rt: int = tool.get("rtype", 1)
				var res := city.check_roads(path, rt)
				var bad := {}
				for b in res.bad:
					bad[b] = true
				for p in path:
					_cell(p, C_BAD if bad.has(p) or not res.ok else C_OK)
				ok = res.ok
				var rname: String = Defs.ROAD_TYPES[rt].name
				if dragging:
					tip = "%s: %d клеток — ₽%s\n[Tab] — повернуть угол в другую сторону" % [rname, res.new.size(), Defs.fmt_int(res.cost)]
				else:
					tip = "%s ₽%d/клетка. Тяните мышью. Поверх дороги — замена типа." % [rname, Defs.ROAD_TYPES[rt].cost]
				if not res.ok and res.reason != "":
					tip += "\n" + res.reason
			"path":
				var pth: Array[Vector2i] = []
				if dragging:
					pth = city.road_path(drag_start, hover, _road_mode())
				else:
					pth.append(hover)
				var pres := city.check_paths(pth)
				var pbad := {}
				for b in pres.bad:
					pbad[b] = true
				for p in pth:
					_cell(p, C_BAD if pbad.has(p) or not pres.ok else Color(0.95, 0.85, 0.55, 0.6))
				ok = pres.ok
				tip = "Пешеходная дорожка: %d клеток — ₽%s\nПересекает дороги по зебре, над водой — мостик. [Tab] — угол" % [pres.new.size(), Defs.fmt_int(pres.cost)] if dragging else "Пешеходная дорожка ₽%d/клетка. Люди ходят по ней пешком вместо поездок на машине." % City.PATH_COST
				if not pres.ok and pres.reason != "":
					tip += "\n" + pres.reason
			"rail":
				var rp: Array[Vector2i] = []
				if dragging:
					rp = city.road_path(drag_start, hover, _road_mode())
				else:
					rp.append(hover)
				var rres := city.check_rails(rp)
				var rbad := {}
				for b in rres.bad:
					rbad[b] = true
				for p in rp:
					_cell(p, C_BAD if rbad.has(p) or not rres.ok else Color(0.75, 0.6, 0.45, 0.6))
				ok = rres.ok
				tip = "Ж/д путь: %d клеток — ₽%s\nПоперёк дороги — переезд, над водой — мост. [Tab] — угол" % [rres.new.size(), Defs.fmt_int(rres.cost)] if dragging else "Ж/д путь ₽%d/клетка. Выведите пути за край карты — так город свяжется с внешним миром." % City.RAIL_COST
				if not rres.ok and rres.reason != "":
					tip += "\n" + rres.reason
			"zone", "dezone":
				var r := _drag_rect() if dragging else Rect2i(hover, Vector2i.ONE)
				var cnt := 0
				for y in range(r.position.y, r.end.y):
					for x in range(r.position.x, r.end.x):
						var p := Vector2i(x, y)
						if tool.type == "zone":
							if city.can_zone(p):
								var c: Color = Defs.ZONES[tool.zone].color
								c.a = 0.6
								_cell(p, c)
								cnt += 1
						elif city.inb(x, y) and city.zone[city.idx(x, y)] != 0:
							_cell(p, C_DEL)
							cnt += 1
				_outline(Rect2(r), Color(1, 1, 1, 0.5), 0.05)
				tip = ("%s: %d клеток" % [Defs.ZONES[tool.zone].short, cnt]) if tool.type == "zone" else "Снять зону: %d клеток" % cnt
				if tool.type == "zone" and cnt == 0 and not dragging:
					tip += "\nЗонировать можно рядом с дорогой (до %d клеток)" % Defs.ZONE_DEPTH
					ok = false
			"bulldoze":
				var r := _drag_rect() if dragging else Rect2i(hover, Vector2i.ONE)
				_quad(Rect2(r), 0.06, C_DEL)
				var pv := city.bulldoze_preview(r)
				tip = "Снос: %d объектов" % pv.items
				if pv.refund > 0:
					tip += ", возврат ₽%s" % Defs.fmt_int(pv.refund)
			"district":
				var col: Color = Color(1, 1, 1, 0.8)
				if tool.mode != "erase" and city.districts.has(cur_district):
					col = city.districts[cur_district].color
				_ring(Vector3(hover_f.x, 0, hover_f.y), brush * 0.7, Color(col, 0.85))
				var dh := city.district[city.idx(hover.x, hover.y)]
				var under: String = city.districts[dh].name if city.districts.has(dh) else "—"
				match tool.mode:
					"erase": tip = "Стереть район · кисть %d ([ ])" % int(brush)
					"new": tip = "Новый район: нажмите и рисуйте"
					_: tip = "Рисовать район «%s» · кисть %d ([ ])\nCtrl+клик — выбрать существующий" % [city.districts[cur_district].name if city.districts.has(cur_district) else "новый", int(brush)]
				tip += "\nЗдесь: " + under
			"line":
				var col: Color = Defs.LINE_COLORS[(city.next_line_id - 1) % Defs.LINE_COLORS.size()]
				var pts: Array = line_stops.duplicate()
				var hs = _line_stop_at(hover)
				if hs != null:
					pts.append(hs)
				for k in pts.size():
					var a = pts[k]
					var ta := _stop_tile(a)
					_cell(ta, Color(col, 0.9), 0.1)
					if k > 0:
						var tb := _stop_tile(pts[k - 1])
						if tool.kind != "metro":
							for p in city.find_path(tb, ta):
								_cell(Vector2i(p), Color(col, 0.45), 0.08)
						else:
							_seg(Vector3(tb.x + 0.5, 0, tb.y + 0.5), Vector3(ta.x + 0.5, 0, ta.y + 0.5), Color(col, 0.6))
				var kname: String = {"bus": "автобусного маршрута", "tram": "трамвайного маршрута", "metro": "линии метро"}[tool.kind]
				tip = "Создание %s: остановок %d\nЛКМ — добавить, клик по первой — замкнуть, ПКМ/Enter — готово" % [kname, line_stops.size()]
				if _line_err != "":
					tip += "\n" + _line_err
					ok = false
			"terraform":
				_ring(Vector3(hover_f.x, 0, hover_f.y), brush, Color(1.0, 0.85, 0.3, 0.7))
				_ring(Vector3(hover_f.x, 0, hover_f.y), brush * 0.4, Color(1.0, 0.85, 0.3, 0.35))
				var names := {"raise": "Поднять землю", "lower": "Опустить землю", "level": "Выровнять", "smooth": "Сгладить"}
				tip = "%s · кисть %d  ([ и ] — размер)\nВысота: %.1f м" % [names.get(tool.mode, ""), int(brush), city.height_at(hover_f.x, hover_f.y) * 10.0]
				if dragging:
					tip += "\nПотрачено: ₽%s" % Defs.fmt_int(_tf_cost_acc)
			"tree":
				var can := city.inb(hover.x, hover.y) and city.terrain[city.idx(hover.x, hover.y)] == 0 and city.road[city.idx(hover.x, hover.y)] == 0 and city.bld[city.idx(hover.x, hover.y)] == -1
				_cell(hover, C_OK if can else C_BAD)
				tip = "Посадить деревья: ₽%d за клетку" % Defs.TREE_COST
				ok = can
			"service":
				var pl := city.service_placement(tool.id, hover, rot_dir)
				var def: Dictionary = Defs.SERVICES[tool.id]
				ok = pl.ok
				var r: Rect2i = pl.rect
				_quad(Rect2(r), 0.05, C_OK if ok else C_BAD)
				# front indicator
				var F := Defs.DIRS[pl.dir]
				var fc := Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5) + Vector3(F.x * r.size.x, 0, F.y * r.size.y) * 0.5
				_quad(Rect2(fc.x - 0.15, fc.z - 0.15, 0.3, 0.3), 0.08, Color(1, 1, 1, 0.8))
				if def.has("radius"):
					var c3 := Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
					_ring(c3, def.radius, Color(0.3, 0.8, 1.0, 0.6))
				tip = "%s — ₽%s (содержание ₽%s/мес)" % [def.name, Defs.fmt_int(def.cost), Defs.fmt_int(def.upkeep)]
				if not ok:
					tip += "\n" + pl.reason
				tip += "\n[R] — повернуть"
				_update_ghost(tool.id, pl, ok)
	if tool.type != "service" or hover.x < 0:
		if ghost:
			ghost.visible = false
	imesh.surface_end()
	tooltip.emit(tip, ok)


func _update_ghost(id: String, pl: Dictionary, ok: bool) -> void:
	var key := "%s_%d_%s" % [id, pl.dir, ok]
	if key != ghost_key:
		_clear_ghost()
		ghost_key = key
		var b := Building.new()
		b.type = id
		var def: Dictionary = Defs.SERVICES[id]
		b.w = def.w
		b.d = def.d
		b.dir = pl.dir
		b.seed = 1
		var r: Rect2i = pl.rect
		b.x = r.position.x; b.y = r.position.y; b.sx = r.size.x; b.sy = r.size.y
		ghost = Node3D.new()
		ghost.rotation.y = -pl.dir * PI * 0.5
		var content := Node3D.new()
		ghost.add_child(content)
		brender._build_service(b, content, RandomNumberGenerator.new())
		brender.spinners = brender.spinners.filter(func(s): return is_instance_valid(s[0]) and not content.is_ancestor_of(s[0]))
		_ghostify(content, Models.ghost_ok if ok else Models.ghost_bad)
		add_child(ghost)
	var r2: Rect2i = pl.rect
	ghost.visible = true
	var gy := -1e9
	for t in city.rect_tiles(r2):
		gy = max(gy, city.tile_h(t.x, t.y))
	ghost.position = Vector3(r2.position.x + r2.size.x * 0.5, max(gy, 0.0), r2.position.y + r2.size.y * 0.5)


func _ghostify(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = m
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = null
	if n is GPUParticles3D:
		(n as GPUParticles3D).emitting = false
	for c in n.get_children():
		_ghostify(c, m)
