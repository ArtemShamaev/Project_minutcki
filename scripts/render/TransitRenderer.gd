extends Node3D
## Public transport visuals: bus stops, buses driving their routes, metro lines.

const LANE := 0.17
const BUS_YAW := 0.0   # turns the bus model so its front points to +Z

class Bus:
	var node: Node3D
	var line_id := 0
	var pts := PackedVector3Array()
	var stop_idx := PackedInt32Array()   # point indices that are stops
	var i := 0
	var s := 0.0
	var wait := 0.0
	var fwd := Vector3.FORWARD
	var pos := Vector3.ZERO

class Train:
	var node: Node3D
	var line_id := 0
	var pts := PackedVector3Array()
	var t := 0.0
	var dir := 1

var city: City
var time_scale := 1.0
var stops_root: Node3D
var metro_root: Node3D
var buses: Array = []
var trains: Array = []
var show_metro := false
var _bus_meshes := {}


func setup(c: City) -> void:
	city = c
	stops_root = Node3D.new()
	add_child(stops_root)
	metro_root = Node3D.new()
	add_child(metro_root)
	city.lines_changed.connect(rebuild_all)
	city.roads_changed.connect(func(_c): rebuild_all())


func rebuild_all() -> void:
	for ch in stops_root.get_children():
		ch.queue_free()
	for ch in metro_root.get_children():
		ch.queue_free()
	for b in buses:
		b.node.queue_free()
	buses.clear()
	for t in trains:
		t.node.queue_free()
	trains.clear()
	for l in city.lines:
		if l.kind != "metro":
			_build_bus_line(l)
		else:
			_build_metro_line(l)
	metro_root.visible = show_metro


func set_show_metro(on: bool) -> void:
	show_metro = on
	metro_root.visible = on


# ---------------------------------------------------------------- bus
func _build_bus_line(l: Dictionary) -> void:
	var col: Color = l.color
	for s in l.stops:
		_make_stop(s, col)
	# full loop route through all stops
	var route := PackedVector2Array()
	var stop_tiles: Array = []
	var n: int = l.stops.size()
	for k in n:
		var a: Vector2i = l.stops[k]
		var b: Vector2i = l.stops[(k + 1) % n]
		var p := city.find_path(a, b)
		if p.size() == 0:
			return
		if route.size() > 0:
			p.remove_at(0)
		stop_tiles.append(route.size() if route.size() > 0 else 0)
		route.append_array(p)
	if route.size() < 3:
		return
	if route.size() > 1 and route[route.size() - 1] == route[0]:
		route.remove_at(route.size() - 1)
	var lp := LanePath.build(route, LANE, city.n, 0.35, 0.3, true)
	var pts: PackedVector3Array = lp.pts
	var stop_pts := PackedInt32Array()
	for st in stop_tiles:
		stop_pts.append(lp.first[mini(st, lp.first.size() - 1)])
	if l.kind == "tram":
		_rails(pts)
	var nv := city.line_vehicles(l)
	for v in nv:
		var bus := Bus.new()
		bus.line_id = l.id
		bus.pts = pts
		bus.stop_idx = stop_pts
		bus.i = int(float(pts.size()) * v / nv) % (pts.size() - 1)
		bus.node = _tram_model(col) if l.kind == "tram" else _bus_model(col)
		bus.pos = pts[bus.i]
		bus.node.position = bus.pos
		add_child(bus.node)
		buses.append(bus)


static func _right(d: Vector2) -> Vector3:
	return Vector3(-d.y, 0, d.x)


func _rails(pts: PackedVector3Array) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for k in n:
		var a := pts[k]
		var b := pts[(k + 1) % n]
		var d := b - a
		d.y = 0
		if d.length() < 0.001 or d.length() > 1.5:
			continue
		var side := Vector3(-d.z, 0, d.x).normalized()
		for off: float in [-0.045, 0.045]:
			var a0 := a + side * (off - 0.008)
			var a1 := a + side * (off + 0.008)
			var b0 := b + side * (off - 0.008)
			var b1 := b + side * (off + 0.008)
			var q := [a0, b0, b1, a0, b1, a1]
			for v in q:
				im.surface_add_vertex(Vector3(v.x, city.height_at(v.x, v.z) + 0.027, v.z))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = Models.mat(Color("5d5f63"), 0.4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 60.0
	stops_root.add_child(mi)


static func _tram_model(col: Color) -> Node3D:
	var root := Node3D.new()
	var m := Models.fit("train/train-tram-modern", Vector2(0.2, 0.62), 0, 1.0)
	root.add_child(m)
	# line colour stripe along the sides
	for x in [-0.098, 0.098]:
		Models.box(Vector3(0.004, 0.02, 0.5), col, Vector3(x, 0.05, 0), root)
	Models.set_cast_shadows(root, false)
	return root


func _make_stop(t: Vector2i, col: Color) -> void:
	var mask := city.road_mask(t)
	var root := Node3D.new()
	var off := Vector3(0, 0, 0.43) if (mask & 10) and not (mask & 5) else Vector3(0.43, 0, 0)
	var px := t.x + 0.5 + off.x
	var pz := t.y + 0.5 + off.z
	root.position = Vector3(px, city.height_at(px, pz), pz)
	if off.x != 0.0:
		root.rotation.y = PI * 0.5
	stops_root.add_child(root)
	# shelter
	var sh := Models.fit("poly/bus_stop", Vector2(0.24, 0.1), 0, 1.0)
	sh.rotation.y = PI
	root.add_child(sh)
	Models.box(Vector3(0.012, 0.24, 0.012), Color("e0e0e0"), Vector3(0.14, 0, -0.01), root)
	var sign := Models.box(Vector3(0.06, 0.06, 0.012), col, Vector3(0.14, 0.22, -0.01), root)
	sign.material_override = Models.mat(col, 0.5, 0.6)


func _bus_model(col: Color) -> Node3D:
	var root := Node3D.new()
	var m := Models.fit("poly/bus", Vector2(0.19, 0.48), 0, 1.0)
	m.get_child(0).rotation.y = BUS_YAW
	root.add_child(m)
	for x in [-0.097, 0.097]:
		Models.box(Vector3(0.004, 0.025, 0.4), col, Vector3(x, 0.035, 0), root)
	Models.set_cast_shadows(root, false)
	return root


# ---------------------------------------------------------------- metro
func _build_metro_line(l: Dictionary) -> void:
	var pts2 := city.line_stop_points(l)
	if pts2.size() < 2:
		return
	var col: Color = l.color
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 3
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	metro_root.add_child(mi)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var path := PackedVector3Array()
	for k in pts2.size():
		path.append(Vector3(pts2[k].x, max(city.height_at(pts2[k].x, pts2[k].y), 0.0) + 0.4, pts2[k].y))
	for k in path.size() - 1:
		_ribbon(im, path[k], path[k + 1], 0.12)
	im.surface_end()
	for p in path:
		var dot := Models.cylinder(0.25, 0.05, col, p - Vector3(0, 0.02, 0), metro_root, 16)
		dot.material_override = m
	for v in city.line_vehicles(l):
		var tr := Train.new()
		tr.line_id = l.id
		tr.pts = path
		tr.t = float(v) / max(1, city.line_vehicles(l)) * (path.size() - 1)
		tr.node = Models.fit("train/train-electric-subway-a", Vector2(0.24, 0.6), 0, 1.0)
		metro_root.add_child(tr.node)
		trains.append(tr)


func _ribbon(im: ImmediateMesh, a: Vector3, b: Vector3, w: float) -> void:
	var d := (b - a)
	d.y = 0
	if d.length() < 0.001:
		return
	var side := Vector3(-d.z, 0, d.x).normalized() * w
	for v in [a - side, b - side, b + side, a - side, b + side, a + side]:
		im.surface_add_vertex(v)


# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	Prof.b("transit")
	_process_inner(delta)
	Prof.e("transit")


func _process_inner(delta: float) -> void:
	var dt := delta * time_scale
	if dt <= 0.0:
		return
	for bus: Bus in buses:
		if bus.wait > 0.0:
			bus.wait -= dt
			continue
		var dist := 1.0 * dt
		var n := bus.pts.size()
		while dist > 0.0:
			var a := bus.pts[bus.i]
			var b := bus.pts[(bus.i + 1) % n]
			var L := a.distance_to(b)
			var rem := L - bus.s
			if dist < rem:
				bus.s += dist
				dist = 0.0
			else:
				dist -= rem
				bus.i = (bus.i + 1) % n
				bus.s = 0.0
				if bus.i in bus.stop_idx:
					bus.wait = 1.2
					break
		var a2 := bus.pts[bus.i]
		var b2 := bus.pts[(bus.i + 1) % n]
		var seg := b2 - a2
		if seg.length() > 0.0001:
			bus.fwd = seg.normalized()
			bus.pos = a2 + bus.fwd * bus.s
		var hy := city.height_at(bus.pos.x, bus.pos.z)
		bus.node.position = Vector3(bus.pos.x, hy + 0.01, bus.pos.z)
		bus.node.rotation.y = lerp_angle(bus.node.rotation.y, atan2(bus.fwd.x, bus.fwd.z), clamp(dt * 8.0, 0.0, 1.0))
		var ah := city.height_at(bus.pos.x + bus.fwd.x * 0.2, bus.pos.z + bus.fwd.z * 0.2)
		bus.node.rotation.x = -atan2(ah - hy, 0.2)
	if show_metro:
		for tr: Train in trains:
			var segs := tr.pts.size() - 1
			tr.t += dt * 1.2 / max(1.0, tr.pts[clampi(int(tr.t), 0, segs - 1)].distance_to(tr.pts[clampi(int(tr.t) + 1, 1, segs)])) * tr.dir
			if tr.t >= segs:
				tr.t = segs
				tr.dir = -1
			elif tr.t <= 0:
				tr.t = 0
				tr.dir = 1
			var k := clampi(int(tr.t), 0, segs - 1)
			var f := tr.t - k
			var p := tr.pts[k].lerp(tr.pts[k + 1], f)
			tr.node.position = p + Vector3(0, -0.06, 0)
			var d := tr.pts[k + 1] - tr.pts[k]
			tr.node.rotation.y = atan2(d.x, d.z)
