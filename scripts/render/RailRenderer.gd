extends Node3D
## Railway track: ballast, sleepers and two steel rails following the ground, curves and switches,
## bridges over water and level crossings with barriers that close when a train comes.

var city: City
var _dirty := true
var crossings := {}          # tile index -> {node, arms: Array[Node3D], lamps: Array, k (0 open..1 closed)}
var closed := {}             # set by the trains every frame: tile index -> true
var _blink := 0.0
const BRIDGE_Y := 0.12
const BALLAST := Color("8a7d6b")
const SLEEPER := Color("5b4636")
const STEEL := Color("b8bec4")
static var lamp_on: StandardMaterial3D
static var lamp_off: StandardMaterial3D


func setup(c: City) -> void:
	city = c
	city.rails_changed.connect(func(): _dirty = true)
	city.roads_changed.connect(func(_c): _dirty = true)
	city.terrain_changed.connect(func(_r): _dirty = true)
	if lamp_on == null:
		lamp_on = Models.mat(Color(1.0, 0.15, 0.1), 0.4, 4.0)
		lamp_off = Models.mat(Color(0.3, 0.05, 0.05), 0.6)


func rebuild_all() -> void:
	_dirty = true


static func rail_y(c: City, x: float, z: float) -> float:
	var t := Vector2i(int(floor(x)), int(floor(z)))
	if c.is_water(t):
		return BRIDGE_Y
	var h := c.height_at(x, z)
	return maxf(h, BRIDGE_Y - 0.1) + (0.05 if c.is_road(t) else 0.035)


## Points along one tile from side a to side b (-1 = tile centre), a quadratic curve through the centre.
static func tile_curve(c: City, t: Vector2i, a: int, b: int, steps: int = 6) -> PackedVector3Array:
	var ctr := Vector2(t.x + 0.5, t.y + 0.5)
	var pa: Vector2 = ctr if a < 0 else ctr + Vector2(Defs.DIRS[a]) * 0.5
	var pb: Vector2 = ctr if b < 0 else ctr + Vector2(Defs.DIRS[b]) * 0.5
	var out := PackedVector3Array()
	for k in steps + 1:
		var u := float(k) / steps
		var p := pa.lerp(ctr, u).lerp(ctr.lerp(pb, u), u)
		out.append(Vector3(p.x, rail_y(c, p.x, p.y), p.y))
	return out


## Pieces of track drawn on a tile: pairs of sides (straights, curves, switches).
static func tile_pieces(c: City, t: Vector2i) -> Array:
	var m := c.rail_mask(t)
	var dirs: Array = []
	for d in 4:
		if m & (1 << d):
			dirs.append(d)
	match dirs.size():
		0: return [[-1, -1]]
		1: return [[dirs[0], -1]]
		2: return [[dirs[0], dirs[1]]]
		3:
			var odd := 0
			for d in dirs:
				if not dirs.has((d + 2) % 4):
					odd = d
			return [[(odd + 1) % 4, (odd + 3) % 4], [odd, (odd + 1) % 4], [odd, (odd + 3) % 4]]
	return [[0, 2], [1, 3]]


func _process(delta: float) -> void:
	if _dirty and city:
		_dirty = false
		_rebuild()
	_animate_crossings(delta)


func _rebuild() -> void:
	for ch in get_children():
		ch.queue_free()
	crossings.clear()
	var bal := SurfaceTool.new()
	bal.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stl := SurfaceTool.new()
	stl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sleepers: Array[Transform3D] = []
	var cnt := 0
	for i in city.n * city.n:
		if city.rail[i] == 0:
			continue
		cnt += 1
		var t := Vector2i(i % city.n, i / city.n)
		var road := city.road[i] > 0
		for pc in tile_pieces(city, t):
			var pts := tile_curve(city, t, pc[0], pc[1])
			if not road:
				_ribbon(bal, pts, 0.2, -0.012)
			_ribbon(stl, pts, 0.016, 0.022, 0.075)
			_ribbon(stl, pts, 0.016, 0.022, -0.075)
			# sleepers every ~0.11
			var acc := 0.0
			for k in range(1, pts.size()):
				var seg := pts[k] - pts[k - 1]
				var ln := seg.length()
				acc += ln
				if acc >= 0.11 and not road:
					acc = 0.0
					var fwd := seg.normalized()
					var side := fwd.cross(Vector3.UP).normalized()
					var bs := Basis(side * 0.3, Vector3.UP * 0.025, fwd * 0.05)
					sleepers.append(Transform3D(bs, pts[k] + Vector3(0, 0.0, 0)))
		if pc_is_end(t):
			Models.box(Vector3(0.3, 0.12, 0.08), Color("c62828"), Vector3(t.x + 0.5, rail_y(city, t.x + 0.5, t.y + 0.5), t.y + 0.5), self)
		if city.terrain[i] == 1:
			_bridge(t)
		elif road:
			_crossing(t, i)
	if cnt == 0:
		return
	for pair in [[bal, Models.mat(BALLAST, 1.0)], [stl, Models.mat(STEEL, 0.3)]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if sleepers.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		mm.mesh = bm
		mm.instance_count = sleepers.size()
		for k in sleepers.size():
			mm.set_instance_transform(k, sleepers[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Models.mat(SLEEPER, 0.9)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func pc_is_end(t: Vector2i) -> bool:
	var m := city.rail_mask(t)
	return m in [1, 2, 4, 8]


## A flat strip along the points; off = sideways offset of the strip centre.
func _ribbon(st: SurfaceTool, pts: PackedVector3Array, half: float, dy: float, off: float = 0.0) -> void:
	for k in range(1, pts.size()):
		var a := pts[k - 1]
		var b := pts[k]
		var side := (b - a).cross(Vector3.UP).normalized()
		var a0 := a + side * (off - half) + Vector3(0, dy, 0)
		var a1 := a + side * (off + half) + Vector3(0, dy, 0)
		var b0 := b + side * (off - half) + Vector3(0, dy, 0)
		var b1 := b + side * (off + half) + Vector3(0, dy, 0)
		for v in [a0, b0, b1, a0, b1, a1]:
			st.add_vertex(v)


func _bridge(t: Vector2i) -> void:
	var m := city.rail_mask(t)
	var along_x := (m & 10) != 0
	var c := Vector3(t.x + 0.5, BRIDGE_Y - 0.05, t.y + 0.5)
	var deck := Models.box(Vector3(1.0, 0.07, 0.46) if along_x else Vector3(0.46, 0.07, 1.0), Color("7b6f63"), c, self)
	deck.position.y = BRIDGE_Y - 0.08
	for s in [-1, 1]:
		var g := Models.box(Vector3(1.0, 0.12, 0.04) if along_x else Vector3(0.04, 0.12, 1.0), Color("37474f"), c + (Vector3(0, 0, 0.22 * s) if along_x else Vector3(0.22 * s, 0, 0)), self)
		g.position.y = BRIDGE_Y - 0.02
	if (t.x + t.y) % 2 == 0:
		var p := Models.box(Vector3(0.16, 1.0, 0.16), Color("8d8d8d"), c, self)
		p.position.y = BRIDGE_Y - 1.08


## Level crossing: on both sides of the road a post with a barrier arm and blinking lamps.
func _crossing(t: Vector2i, i: int) -> void:
	var m := city.rail_mask(t)
	var rail_x := (m & 10) != 0        # track runs along X, road along Z
	var ctr := Vector3(t.x + 0.5, 0, t.y + 0.5)
	var arms: Array = []
	var lamps: Array = []
	for s in [-1, 1]:
		# post beside the road, before the track
		var along := Vector3(0.0, 0, 0.42 * s) if rail_x else Vector3(0.42 * s, 0, 0.0)
		var side := Vector3(0.44 * s, 0, 0) if rail_x else Vector3(0, 0, -0.44 * s)
		var base := ctr + along + side
		base.y = city.height_at(base.x, base.z)
		var post := Models.cylinder(0.018, 0.26, Color("eceff1"), base, self, 6)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# X sign
		for k in 2:
			var xb := Models.box(Vector3(0.14, 0.022, 0.006), Color("f5f5f5"), base + Vector3(0, 0.27, 0), self)
			xb.rotation = Vector3(0, 0 if rail_x else PI * 0.5, PI * 0.25 * (1 if k == 0 else -1))
		for k in 2:
			var lp := Models.box(Vector3(0.035, 0.035, 0.035), Color.RED, base + Vector3(0, 0.2, 0) + (Vector3(0.03 * (k * 2 - 1), 0, 0) if not rail_x else Vector3(0, 0, 0.03 * (k * 2 - 1))), self)
			lp.material_override = lamp_off
			lamps.append(lp)
		# the arm turns around a pivot on the post, across the lane
		var pivot := Node3D.new()
		pivot.position = base + Vector3(0, 0.12, 0)
		add_child(pivot)
		var arm := Node3D.new()
		pivot.add_child(arm)
		for k in 4:
			var seg := Models.box(Vector3(0.012, 0.012, 0.1), Color("e53935") if k % 2 == 0 else Color("f5f5f5"), Vector3(0, 0, 0), arm)
			seg.position = Vector3(0, 0, -0.05 - k * 0.1)
		# arm points from the post towards the road centre
		var to_road := -side.normalized()
		pivot.rotation.y = atan2(-to_road.x, -to_road.z)
		arms.append(pivot)
	crossings[i] = {"arms": arms, "lamps": lamps, "k": 0.0}


func _animate_crossings(delta: float) -> void:
	if crossings.is_empty():
		return
	_blink += delta
	var on := fmod(_blink, 0.8) < 0.4
	for i in crossings:
		var cr: Dictionary = crossings[i]
		var want := 1.0 if closed.has(i) else 0.0
		cr.k = move_toward(cr.k, want, delta * 1.2)
		for p in cr.arms:
			# open: arm straight up; closed: horizontal across the lane
			(p.get_child(0) as Node3D).rotation.x = (1.0 - cr.k) * PI * 0.5
		for k in cr.lamps.size():
			var lit: bool = (cr.k > 0.01 or want > 0.0) and (on if k % 2 == 0 else not on)
			cr.lamps[k].material_override = lamp_on if lit else lamp_off
