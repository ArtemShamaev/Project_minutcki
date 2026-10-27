extends Node3D
## Pedestrian paths: paved strips following the ground, footbridges over water,
## street lamps and benches along the way.

var city: City
var mesh_mi: MeshInstance3D
var lamps: MultiMeshInstance3D
var bulbs: MultiMeshInstance3D
var benches: MultiMeshInstance3D
var _dirty := true
const HALF := 0.17          # half width of the paved strip
const STONE := Color("cbbfa8")
const EDGE := Color("8f8676")
const DECK := Color("9c7b55")


func setup(c: City) -> void:
	city = c
	city.paths_changed.connect(func(): _dirty = true)
	city.roads_changed.connect(func(_c): _dirty = true)
	city.terrain_changed.connect(func(_r): _dirty = true)
	city.building_added.connect(func(b): if b.type in City.PARK_WALK: _dirty = true)


func rebuild_all() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and city:
		_dirty = false
		_rebuild()


func _conn(p: Vector2i) -> bool:
	if not city.inb(p.x, p.y):
		return false
	var i := city.idx(p.x, p.y)
	if city.path[i] > 0 or (city.road[i] > 0 and city.road[i] < 3):
		return true
	var b := city.building_at(p)
	return b != null and b.type in City.PARK_WALK


func _y(x: float, z: float, bridge: bool) -> float:
	if bridge:
		return WaterSim.SEA + 0.16
	return city.height_at(x, z) + 0.025


func _rebuild() -> void:
	for ch in get_children():
		ch.queue_free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lamp_xf: Array[Transform3D] = []
	var bench_xf: Array[Transform3D] = []
	var rail := SurfaceTool.new()
	rail.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cnt := 0
	for i in city.n * city.n:
		if city.path[i] == 0:
			continue
		cnt += 1
		var t := Vector2i(i % city.n, i / city.n)
		var bridge: bool = city.terrain[i] == 1
		var cx := t.x + 0.5
		var cz := t.y + 0.5
		var m := 0
		for d in 4:
			if _conn(t + Defs.DIRS[d]):
				m |= 1 << d
		# centre square and an arm towards every connected neighbour
		_quad(st, cx - HALF, cz - HALF, cx + HALF, cz + HALF, bridge)
		var arms := [Rect2(cx - HALF, t.y, HALF * 2, 0.5 - HALF), Rect2(cx + HALF, cz - HALF, 0.5 - HALF, HALF * 2),
			Rect2(cx - HALF, cz + HALF, HALF * 2, 0.5 - HALF), Rect2(t.x, cz - HALF, 0.5 - HALF, HALF * 2)]
		for d in 4:
			if m & (1 << d):
				var r: Rect2 = arms[d]
				_quad(st, r.position.x, r.position.y, r.end.x, r.end.y, bridge)
		var h := (t.x * 73856093) ^ (t.y * 19349663)
		if bridge:
			_bridge_rails(rail, t, m, cx, cz)
		elif m in [5, 10] and h % 3 == 0:
			# a lamp on one side, a bench on the other
			var side := Vector3(1, 0, 0) if m == 5 else Vector3(0, 0, 1)
			var p := Vector3(cx, 0, cz) + side * (HALF + 0.06)
			p.y = city.height_at(p.x, p.z)
			lamp_xf.append(Transform3D(Basis(Vector3.UP, 0.0 if m == 5 else PI * 0.5).scaled(Vector3.ONE * 0.32), p))
			if h % 2 == 0:
				var q := Vector3(cx, 0, cz) - side * (HALF + 0.07)
				q.y = city.height_at(q.x, q.z)
				var yaw := PI * 0.5 if m == 5 else 0.0
				bench_xf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 0.16), q))
	# zebra crossings where a path meets a road
	var zeb := SurfaceTool.new()
	zeb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zc := 0
	for i in city.n * city.n:
		if city.road[i] == 0 or city.road[i] == 3 or city.terrain[i] == 1:
			continue
		var t := Vector2i(i % city.n, i / city.n)
		for d in 2:
			var dv: Vector2i = Defs.DIRS[d]
			if not (city.is_path(t + dv) or city.is_path(t - dv)):
				continue
			zc += 1
			var across := Vector2(dv)           # walking direction
			var along := Vector2(-dv.y, dv.x)   # traffic direction
			for k in 7:
				var c := Vector2(t.x + 0.5, t.y + 0.5) + across * (-0.39 + k * 0.13)
				var p0 := c - along * 0.15 - across * 0.035
				var p1 := c + along * 0.15 - across * 0.035
				var p2 := c + along * 0.15 + across * 0.035
				var p3 := c - along * 0.15 + across * 0.035
				var q := [p0, p2, p1, p0, p3, p2]
				for v: Vector2 in q:
					zeb.set_normal(Vector3.UP)
					zeb.add_vertex(Vector3(v.x, city.height_at(v.x, v.y) + 0.042, v.y))
	if zc > 0:
		var zmi := MeshInstance3D.new()
		zmi.mesh = zeb.commit()
		var zm := StandardMaterial3D.new()
		zm.albedo_color = Color(0.93, 0.93, 0.9)
		zm.roughness = 0.7
		zm.cull_mode = BaseMaterial3D.CULL_DISABLED
		zmi.material_override = zm
		zmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(zmi)
	if cnt == 0:
		return
	st.generate_normals()
	mesh_mi = MeshInstance3D.new()
	mesh_mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/paving.gdshader")
	mesh_mi.material_override = mat
	mesh_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_mi)
	var rm := rail.commit()
	if rm.get_surface_count() > 0:
		var rmi := MeshInstance3D.new()
		rmi.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.vertex_color_use_as_albedo = true
		rmat.roughness = 0.8
		rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		rmi.material_override = rmat
		add_child(rmi)
	lamps = _multi(Models.mesh_of("roads/light-square"), lamp_xf, 40.0)
	benches = _multi(Models.mesh_of("graveyard/bench"), bench_xf, 25.0)


func _multi(mesh: Mesh, xf: Array[Transform3D], vis: float) -> MultiMeshInstance3D:
	if mesh == null or xf.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = vis
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## A paved rectangle split into 2x2 cells so it follows the slope; the outer rim is darker.
func _quad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, bridge: bool) -> void:
	if x1 - x0 < 0.001 or z1 - z0 < 0.001:
		return
	var col := DECK if bridge else STONE
	var xs := [x0, (x0 + x1) * 0.5, x1]
	var zs := [z0, (z0 + z1) * 0.5, z1]
	for a in 2:
		for b in 2:
			var p := [Vector3(xs[a], 0, zs[b]), Vector3(xs[a + 1], 0, zs[b]), Vector3(xs[a + 1], 0, zs[b + 1]), Vector3(xs[a], 0, zs[b + 1])]
			for k in 4:
				p[k].y = _y(p[k].x, p[k].z, bridge)
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.add_vertex(p[k])


func _bridge_rails(st: SurfaceTool, t: Vector2i, m: int, cx: float, cz: float) -> void:
	var y := WaterSim.SEA + 0.16
	var c := Color("5d4a36")
	# rails along the sides that are not connected
	var along_x := (m & 2) != 0 or (m & 8) != 0
	for s in [-1.0, 1.0]:
		if along_x:
			_box(st, Vector3(cx, y + 0.06, cz + s * (HALF - 0.01)), Vector3(1.0, 0.015, 0.015), c)
		else:
			_box(st, Vector3(cx + s * (HALF - 0.01), y + 0.06, cz), Vector3(0.015, 0.015, 1.0), c)
	# a pillar into the water
	_box(st, Vector3(cx, y - 0.35, cz), Vector3(0.08, 0.7, 0.08), Color("8e8a80"))


func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	var normals := [Vector3.BACK * -1, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]
	for fi in 6:
		var f: Array = faces[fi]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(normals[fi])
			st.add_vertex(c + v[f[k]])
