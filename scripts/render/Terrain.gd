extends Node3D
## Ground mesh (chunked, follows the heightmap), water surface, surroundings and forests.

var city: City
var chunks := {}            # Vector2i -> MeshInstance3D
var water_mi: MeshInstance3D
var water_flat_mat: ShaderMaterial
var trees_root: Node3D
var tree_chunks := {}
var _tree_snapshot := PackedByteArray()
var _tree_force := {}
var ground_mat: ShaderMaterial
var noise_tex: NoiseTexture2D
var hm_img: Image
var hm_tex: ImageTexture
var _dirty_chunks := {}
var _trees_dirty := false
var pol_img: Image
var pol_tex: ImageTexture
var _pol_t := 0.0
var sim_img: Image
var sim_tex: ImageTexture
var water_speed := 1.0       # game speed: the water simulation advances with it
var _water_rows := 0.0
const WATER_Y := -0.1
const CHUNK := 16


func setup(c: City) -> void:
	city = c
	city.trees_changed.connect(func(): _trees_dirty = true)
	city.terrain_changed.connect(_on_terrain_changed)
	city.roads_changed.connect(func(cells):
		for cl in cells:
			_on_terrain_changed(Rect2i(cl, Vector2i.ONE)))
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	noise_tex.noise = fn


func rebuild_all() -> void:
	for ch in get_children():
		ch.queue_free()
	chunks.clear()
	_update_heightmap()
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://shaders/ground.gdshader")
	ground_mat.set_shader_parameter("noise_tex", noise_tex)
	for k in [["grass_tex", "aerial_grass_rock"], ["rock_tex", "aerial_rocks_02"], ["sand_tex", "aerial_beach_01"], ["dirt_tex", "dirt_aerial_02"]]:
		ground_mat.set_shader_parameter(k[0], load("res://assets/textures/%s.jpg" % k[1]))
	var nc := ceili(float(city.n) / CHUNK)
	for cy in nc:
		for cx in nc:
			_build_chunk(Vector2i(cx, cy))
	_build_water()
	_build_surroundings()
	var cl := MeshInstance3D.new()
	var cp := PlaneMesh.new()
	cp.size = Vector2(city.n + 300, city.n + 300)
	cl.mesh = cp
	var cm := ShaderMaterial.new()
	cm.shader = load("res://shaders/clouds.gdshader")
	cm.set_shader_parameter("noise_tex", noise_tex)
	cl.material_override = cm
	cl.position = Vector3(city.n * 0.5, 26.0, city.n * 0.5)
	cl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cl)
	trees_root = Node3D.new()
	add_child(trees_root)
	tree_chunks.clear()
	_tree_snapshot = PackedByteArray()
	_rebuild_trees()


func set_grid(alpha: float) -> void:
	if ground_mat:
		ground_mat.set_shader_parameter("grid_alpha", alpha)


func _update_heightmap() -> void:
	var s := city.n + 1
	if hm_img == null or hm_img.get_width() != s:
		hm_img = Image.create(s, s, false, Image.FORMAT_RF)
	for y in s:
		for x in s:
			hm_img.set_pixel(x, y, Color(city.hc(x, y), 0, 0))
	if hm_tex == null or hm_tex.get_width() != s:
		hm_tex = ImageTexture.create_from_image(hm_img)
	else:
		hm_tex.update(hm_img)
	RenderingServer.global_shader_parameter_set("heightmap", hm_tex)
	RenderingServer.global_shader_parameter_set("hm_size", float(s))


func _on_terrain_changed(r: Rect2i) -> void:
	var c0 := Vector2i(maxi(0, r.position.x - 1) / CHUNK, maxi(0, r.position.y - 1) / CHUNK)
	var c1 := Vector2i(mini(city.n - 1, r.end.x) / CHUNK, mini(city.n - 1, r.end.y) / CHUNK)
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			_dirty_chunks[Vector2i(cx, cy)] = true
			if not _heights_same(Vector2i(cx, cy)):
				_tree_force[Vector2i(cx, cy)] = true
	_trees_dirty = true


func _process(_delta: float) -> void:
	Prof.b("terrain")
	_process_inner(_delta)
	Prof.e("terrain")


func _heights_same(_c: Vector2i) -> bool:
	return false


## Polluted water turns brown around sewage outlets.
func _update_water_pol() -> void:
	if pol_img == null:
		return
	for y in city.n:
		for x in city.n:
			pol_img.set_pixel(x, y, Color(city.water_pol[city.idx(x, y)], 0, 0))
	pol_tex.update(pol_img)


func _process_inner(_delta: float) -> void:
	if city == null:
		return
	_step_water(minf(_delta, 0.1))
	_pol_t -= _delta
	if _pol_t <= 0.0:
		_pol_t = 1.0
		_update_water_pol()
	if not _dirty_chunks.is_empty():
		_update_heightmap()
		for c in _dirty_chunks.keys():
			_build_chunk(c)
		_dirty_chunks.clear()
	if _trees_dirty:
		_trees_dirty = false
		_rebuild_trees()


func _tile_color(x: int, y: int, rng: RandomNumberGenerator) -> Color:
	var i := city.idx(x, y)
	var grass := Color("6f9a48").lerp(Color("5f8a3e"), rng.randf() * 0.6)
	if city.terrain[i] == 1:
		return Color("8a7d5a")
	var h := city.tile_h(x, y)
	var slope := city.tile_range(x, y)
	var col := grass
	if h > 2.5:
		col = col.lerp(Color("4d7a3c"), clamp((h - 2.5) / 3.0, 0.0, 1.0))
	if h > 7.0:
		col = col.lerp(Color("8f8a80"), clamp((h - 7.0) / 2.5, 0.0, 1.0))
	if h > 10.5:
		col = col.lerp(Color("f2f4f6"), clamp((h - 10.5) / 1.0, 0.0, 1.0))
	if slope > 0.55:
		col = col.lerp(Color("85765f"), clamp((slope - 0.55) / 0.6, 0.0, 0.85))
	if city.water_near[i] > 0.75 and h < 0.3:
		col = Color("cdbb8a")
	elif city.water_near[i] > 0.6 and h < 0.3:
		col = col.lerp(Color("cdbb8a"), 0.5)
	return col


func _build_chunk(c: Vector2i) -> void:
	if chunks.has(c):
		chunks[c].queue_free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	var x0 := c.x * CHUNK
	var y0 := c.y * CHUNK
	for y in range(y0, mini(y0 + CHUNK, city.n)):
		for x in range(x0, mini(x0 + CHUNK, city.n)):
			rng.seed = city.seed + x * 7349 + y * 1931
			var col := _tile_color(x, y, rng)
			# ground under roads sits a bit lower so road models never z-fight
			var dip := -0.03 if city.road[city.idx(x, y)] > 0 else 0.0
			var p := [
				Vector3(x, city.hc(x, y) + dip, y),
				Vector3(x + 1, city.hc(x + 1, y) + dip, y),
				Vector3(x + 1, city.hc(x + 1, y + 1) + dip, y + 1),
				Vector3(x, city.hc(x, y + 1) + dip, y + 1),
			]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.add_vertex(p[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = ground_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	chunks[c] = mi


func _build_water() -> void:
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	wm.set_shader_parameter("noise_tex", noise_tex)
	pol_img = Image.create(city.n, city.n, false, Image.FORMAT_R8)
	pol_tex = ImageTexture.create_from_image(pol_img)
	wm.set_shader_parameter("pol_tex", pol_tex)
	wm.set_shader_parameter("map_n", float(city.n))
	water_flat_mat = wm
	_update_water_pol()
	# the simulated water surface inside the map: one vertex per tile corner
	var sm: ShaderMaterial = wm.duplicate()
	sim_img = Image.create(city.n, city.n, false, Image.FORMAT_RGBAF)
	_update_sim_tex()
	sm.set_shader_parameter("sim_tex", sim_tex)
	sm.set_shader_parameter("use_sim", true)
	water_mi = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(city.n, city.n)
	pm.subdivide_width = city.n - 1
	pm.subdivide_depth = city.n - 1
	water_mi.mesh = pm
	water_mi.material_override = sm
	water_mi.position = Vector3(city.n * 0.5, 0.0, city.n * 0.5)
	water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mi.custom_aabb = AABB(Vector3(-city.n * 0.5, -8, -city.n * 0.5), Vector3(city.n, 24, city.n))
	add_child(water_mi)
	# flat sea / lakes around the map
	var n := float(city.n)
	var big := 200.0
	for r in [Rect2(-big, -big, n + big * 2, big), Rect2(-big, n, n + big * 2, big), Rect2(-big, 0, big, n), Rect2(n, 0, big, n)]:
		var mi := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = r.size
		mi.mesh = q
		mi.material_override = wm
		mi.position = Vector3(r.position.x + r.size.x * 0.5, WATER_Y, r.position.y + r.size.y * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _update_sim_tex() -> void:
	if city.water_sim == null or sim_img == null:
		return
	sim_img.set_data(city.n, city.n, false, Image.FORMAT_RGBAF, city.water_sim.pack_texture_data())
	if sim_tex == null:
		sim_tex = ImageTexture.create_from_image(sim_img)
	else:
		sim_tex.update(sim_img)


## Advances the water simulation a few rows per frame (about 15 full sweeps per second at speed 1).
func _step_water(delta: float) -> void:
	var ws := city.water_sim
	if ws == null:
		return
	city.water_driven = true
	_water_rows += delta * 15.0 * city.n * water_speed
	var rows := mini(int(_water_rows), city.n * 3)
	if rows <= 0:
		return
	_water_rows -= rows
	var finished := false
	while rows > 0:
		var r := mini(rows, city.n)
		if ws.step_rows(r):
			finished = true
		rows -= r
	if finished:
		_update_sim_tex()


func _build_surroundings() -> void:
	var n := float(city.n)
	var col := Color("587f45")
	var m := Models.mat(col, 1.0)
	var parts := [
		[Vector2(n + 160, 80), Vector3(n * 0.5, 0, -40)],
		[Vector2(n + 160, 80), Vector3(n * 0.5, 0, n + 40)],
		[Vector2(80, n), Vector3(-40, 0, n * 0.5)],
		[Vector2(80, n), Vector3(n + 40, 0, n * 0.5)],
	]
	if city.map_type == "coast":
		parts = [[Vector2(n + 80, 80), Vector3(n * 0.5 - 40, 0, -40)], [Vector2(n + 80, 80), Vector3(n * 0.5 - 40, 0, n + 40)], parts[2]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = p[0]
		mi.mesh = pm
		mi.material_override = m
		mi.position = p[1] + Vector3(0, -0.02, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# map edge "skirt" so hills at the border don't float
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge_col := Color("6b5a43")
	for i in city.n:
		for side in 4:
			var a: Vector2i
			var b: Vector2i
			match side:
				0: a = Vector2i(i, 0); b = Vector2i(i + 1, 0)
				1: a = Vector2i(i + 1, city.n); b = Vector2i(i, city.n)
				2: a = Vector2i(0, i + 1); b = Vector2i(0, i)
				3: a = Vector2i(city.n, i); b = Vector2i(city.n, i + 1)
			var ha := city.hc(a.x, a.y)
			var hb := city.hc(b.x, b.y)
			if ha <= 0.0 and hb <= 0.0:
				continue
			var v := [Vector3(a.x, ha, a.y), Vector3(b.x, hb, b.y), Vector3(b.x, -0.02, b.y), Vector3(a.x, -0.02, a.y)]
			for k in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
				st.set_color(edge_col)
				st.add_vertex(v[k])
	st.generate_normals()
	var skirt := MeshInstance3D.new()
	skirt.mesh = st.commit()
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 1.0
	skirt.material_override = sm
	add_child(skirt)
	# river continues outside the map
	for y in [0, city.n - 1]:
		for x in city.n:
			if city.terrain[city.idx(x, y)] == 1:
				var mi := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(1.02, 80)
				mi.mesh = pm
				mi.material_override = water_flat_mat
				mi.position = Vector3(x + 0.5, WATER_Y + 0.085, (-40.0 if y == 0 else n + 40.0))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
	# decorative forest outside the map
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Models.mesh_of("suburban/tree-large")
	var rng := RandomNumberGenerator.new()
	rng.seed = city.seed + 99
	var xf: Array[Transform3D] = []
	for i in 2600:
		var p := Vector3(rng.randf_range(-45, n + 45), -0.02, rng.randf_range(-45, n + 45))
		if p.x > -1.5 and p.x < n + 1.5 and p.z > -1.5 and p.z < n + 1.5:
			continue
		if city.map_type == "coast" and p.x > n * 0.7:
			continue
		var s := rng.randf_range(1.4, 2.4)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Models.tree_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _rebuild_trees() -> void:
	## Rebuilds only chunks whose trees (or terrain) changed.
	if trees_root == null:
		return
	var nc := ceili(float(city.n) / CHUNK)
	if _tree_snapshot.size() != city.tree.size():
		_tree_snapshot = PackedByteArray()
		_tree_snapshot.resize(city.tree.size())
		_tree_snapshot.fill(255)
	for cy in nc:
		for cx in nc:
			var c := Vector2i(cx, cy)
			var dirty := _tree_force.has(c)
			if not dirty:
				for y in range(cy * CHUNK, mini(city.n, cy * CHUNK + CHUNK)):
					for x in range(cx * CHUNK, mini(city.n, cx * CHUNK + CHUNK)):
						var i := city.idx(x, y)
						if city.tree[i] != _tree_snapshot[i]:
							dirty = true
							break
					if dirty:
						break
			if dirty:
				_build_tree_chunk(c)
	_tree_force.clear()
	_tree_snapshot = city.tree.duplicate()


func _build_tree_chunk(c: Vector2i) -> void:
	if tree_chunks.has(c):
		for n in tree_chunks[c]:
			n.queue_free()
	var rng := RandomNumberGenerator.new()
	var large: Array[Transform3D] = []
	var small: Array[Transform3D] = []
	var pines: Array[Transform3D] = []
	var far: Array[Transform3D] = []
	var pine_k: float = Models.aabb("suburban/tree-large").size.y / Models.aabb("graveyard/pine").size.y * 0.95
	for y in range(c.y * CHUNK, mini(city.n, c.y * CHUNK + CHUNK)):
		for x in range(c.x * CHUNK, mini(city.n, c.x * CHUNK + CHUNK)):
			var i := city.idx(x, y)
			if city.tree[i] == 0:
				continue
			rng.seed = i * 7919 + city.seed
			var cnt := rng.randi_range(1, 3)
			for k in cnt:
				var px := x + rng.randf_range(0.18, 0.82)
				var pz := y + rng.randf_range(0.18, 0.82)
				var p := Vector3(px, city.height_at(px, pz), pz)
				var s := rng.randf_range(1.3, 2.0)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p)
				# firs on the hills, broadleaf trees in the valleys
				var pine_p: float = clamp(0.2 + city.tile_h(x, y) * 0.12, 0.2, 0.85)
				var r := rng.randf()
				if r < pine_p:
					pines.append(Transform3D(xf.basis.scaled(Vector3.ONE * pine_k * rng.randf_range(0.85, 1.15)), p))
				elif r < pine_p + (1.0 - pine_p) * 0.65:
					large.append(xf)
				else:
					small.append(xf)
				if k < 2:
					far.append(Transform3D(xf.basis.scaled(Vector3(1.25, 1.1, 1.25)), p))
	var nodes: Array = []
	for pair in [["suburban/tree-large", large], ["suburban/tree-small", small], ["graveyard/pine", pines]]:
		if (pair[1] as Array).is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _mm(pair[0], pair[1])
		mmi.material_override = Models.pine_mat if pair[0] == "graveyard/pine" else Models.tree_mat
		mmi.visibility_range_end = 46.0
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		trees_root.add_child(mmi)
		nodes.append(mmi)
	var fm := MultiMeshInstance3D.new()
	fm.multimesh = _mm("suburban/tree-large", far)
	fm.material_override = Models.tree_mat
	fm.visibility_range_begin = 46.0
	fm.visibility_range_begin_margin = 6.0
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trees_root.add_child(fm)
	nodes.append(fm)
	tree_chunks[c] = nodes


func _mm(path: String, xfs: Array[Transform3D]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Models.mesh_of(path)
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	return mm
