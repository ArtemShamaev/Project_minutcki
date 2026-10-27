class_name Models
## Model library: loads Kenney GLB models, fits them into lots, applies colour
## variations and the night-window overlay. Also builds procedural meshes.

const ROOT := "res://assets/kenney/"
const VARIANTS := {
	"commercial": ["variation-a.png", "variation-b.png"],
	"industrial": ["variation-a.png", "variation-b.png", "variation-c.png"],
	"suburban": ["variation-a.png", "variation-b.png", "variation-c.png"],
}

# models whose front must be turned (radians) to face the street
const YAW := {"poly/classic_big": PI}
# procedural style models are built facing +Z: turn them to the street (-Z)
const STYLE_FLIP := ["style/chn_", "style/sov_izba", "style/sov_shop", "style/sov_univermag", "style/sov_nii", "style/eu_half", "style/eu_shop", "style/eu_town", "style/eu_block"]
# Kenney nature kit is pastel cyan: repaint it to the game's foliage palette
const NATURE_COLORS := {"70e6d6": "3f8f5c", "72d3d5": "2f7a5a", "73eddd": "4f9f5a", "f2be9e": "7a4e34", "e7b5a3": "6e4632",
	"ffc78a": "d98b32", "fff9f0": "7a4e34"}
static var _scenes := {}
static var _aabbs := {}
static var _var_mats := {}
static var _night_mats := {}
static var _std_mats := {}
static var _meshes := {}
static var facade_shader: Shader
static var tint_mat: ShaderMaterial
static var burnt_mat: ShaderMaterial
static var highlight_mat: ShaderMaterial
static var ghost_ok: ShaderMaterial
static var ghost_bad: ShaderMaterial
static var drape_mat: ShaderMaterial
static var drape_mats := {}
static var lamp_mat: ShaderMaterial
static var head_mat: ShaderMaterial
static var tail_mat: ShaderMaterial
static var tree_mat: ShaderMaterial
static var pine_mat: ShaderMaterial
# traffic signal lamps: [axis 0 = north-south, 1 = east-west] -> [stop lamp, go lamp]
static var signal_mats: Array = []


static func signal_mat(axis: int, go: bool) -> StandardMaterial3D:
	if signal_mats.is_empty():
		for a in 2:
			var pair: Array = []
			for k in 2:
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.albedo_color = Color(0.15, 0.15, 0.15)
				pair.append(m)
			signal_mats.append(pair)
	return signal_mats[axis][1 if go else 0]


## state per axis: 0 green, 1 yellow, 2 red
static func set_signals(ns: int, ew: int) -> void:
	signal_mat(0, true)
	var st := [ns, ew]
	for a in 2:
		var stop: StandardMaterial3D = signal_mats[a][0]
		var go: StandardMaterial3D = signal_mats[a][1]
		stop.albedo_color = Color(1.0, 0.12, 0.08) * 1.6 if st[a] == 2 else Color(0.25, 0.06, 0.05)
		go.albedo_color = (Color(0.2, 1.0, 0.35) * 1.4 if st[a] == 0 else (Color(1.0, 0.7, 0.1) * 1.5 if st[a] == 1 else Color(0.05, 0.2, 0.08)))


static func init() -> void:
	if facade_shader:
		return
	RenderingServer.global_shader_parameter_add("night", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	for gname in ["snow", "clouds", "wind", "wet"]:
		RenderingServer.global_shader_parameter_add(gname, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	lamp_mat = ShaderMaterial.new()
	lamp_mat.shader = load("res://shaders/lamp.gdshader")
	head_mat = lamp_mat.duplicate()
	head_mat.set_shader_parameter("color", Color(1.0, 0.95, 0.8))
	head_mat.set_shader_parameter("day_level", 0.35)
	tail_mat = lamp_mat.duplicate()
	tail_mat.set_shader_parameter("color", Color(0.9, 0.1, 0.08))
	tail_mat.set_shader_parameter("day_level", 0.25)
	tree_mat = ShaderMaterial.new()
	tree_mat.shader = load("res://shaders/tree.gdshader")
	tree_mat.set_shader_parameter("albedo_tex", load(ROOT + "suburban/Textures/colormap.png"))
	pine_mat = tree_mat.duplicate()
	pine_mat.set_shader_parameter("albedo_tex", load(ROOT + "graveyard/Textures/colormap.png"))
	var blank := Image.create(2, 2, false, Image.FORMAT_RF)
	RenderingServer.global_shader_parameter_add("heightmap", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, ImageTexture.create_from_image(blank))
	RenderingServer.global_shader_parameter_add("hm_size", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 2.0)
	drape_mat = ShaderMaterial.new()
	drape_mat.shader = load("res://shaders/drape.gdshader")
	drape_mat.set_shader_parameter("albedo_tex", load(ROOT + "roads/Textures/colormap.png"))
	drape_mat.set_shader_parameter("asphalt_tex", load("res://assets/textures/aerial_asphalt_01.jpg"))
	drape_mat.set_shader_parameter("pave_tex", load("res://assets/textures/concrete_pavement.jpg"))
	drape_mats[1] = drape_mat
	drape_mats[2] = drape_mat.duplicate()
	drape_mats[2].set_shader_parameter("tint", Color(0.9, 0.9, 0.92))
	drape_mats[3] = drape_mat.duplicate()
	drape_mats[3].set_shader_parameter("tint", Color(0.8, 0.8, 0.84))
	facade_shader = load("res://shaders/facade.gdshader")
	tint_mat = ShaderMaterial.new()
	tint_mat.shader = load("res://shaders/tint.gdshader")
	burnt_mat = ShaderMaterial.new()
	burnt_mat.shader = tint_mat.shader
	burnt_mat.set_shader_parameter("tint", Color(0.22, 0.2, 0.19))
	highlight_mat = ShaderMaterial.new()
	highlight_mat.shader = load("res://shaders/highlight.gdshader")
	ghost_ok = ShaderMaterial.new()
	ghost_ok.shader = load("res://shaders/ghost.gdshader")
	ghost_bad = ghost_ok.duplicate()
	ghost_bad.set_shader_parameter("color", Color(1.0, 0.3, 0.25, 0.45))


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		if path.begins_with("style/"):
			# architecture style packs: textured facades with lit windows at night
			_scenes[path] = _flatten(load("res://assets/" + path + ".glb"), true, {}, true)
		elif path.begins_with("poly/"):
			# downloaded models: merged into a single mesh (few draw calls), glowing windows
			_scenes[path] = _flatten(load("res://assets/" + path + ".glb"), true)
		elif path.begins_with("train/"):
			_scenes[path] = _flatten(load(ROOT + path + ".glb"), false)
		elif path.begins_with("nature/"):
			_scenes[path] = _flatten(load(ROOT + path + ".glb"), false, NATURE_COLORS)
		else:
			_scenes[path] = load(ROOT + path + ".glb")
	return _scenes[path]


static var _win_mats := {}
static var _recolor := {}


## Merges every mesh of a model into one MeshInstance3D (one surface per material).
static func _flatten(ps: PackedScene, windows: bool, remap: Dictionary = {}, facades: bool = false) -> PackedScene:
	var src: Node = ps.instantiate()
	var groups := {}       # material key -> [SurfaceTool, material]
	var order: Array = []
	_collect(src, Transform3D.IDENTITY, groups, order, true)
	var am := ArrayMesh.new()
	for key in order:
		var st: SurfaceTool = groups[key][0]
		var mat: Material = groups[key][1]
		st.index()
		st.commit(am)
		var m: Material = mat
		if facades and mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
			m = _facade_mat(mat as StandardMaterial3D)
		elif mat is StandardMaterial3D and remap.has((mat as StandardMaterial3D).albedo_color.to_html(false)):
			var rc: StandardMaterial3D = mat.duplicate()
			rc.albedo_color = Color(remap[(mat as StandardMaterial3D).albedo_color.to_html(false)])
			m = rc
		elif windows and mat is StandardMaterial3D and _is_window((mat as StandardMaterial3D).albedo_color) and (mat as StandardMaterial3D).albedo_texture == null:
			m = _window_mat((mat as StandardMaterial3D).albedo_color)
		am.surface_set_material(am.get_surface_count() - 1, m)
	src.free()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "mesh"
	mi.mesh = am
	root.add_child(mi)
	mi.owner = root
	var out := PackedScene.new()
	out.pack(root)
	root.free()
	return out


static var _facade_mats := {}


## Style pack materials: F_ = tiled facade, A_ = baked atlas, S_ = sign, T_ = roof texture.
static func _facade_mat(src: StandardMaterial3D) -> Material:
	var key := src.get_instance_id()
	if _facade_mats.has(key):
		return _facade_mats[key]
	var nm := src.resource_name
	var out: Material = src
	if src.emission_enabled and src.emission_texture != null:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/facade_tex.gdshader")
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		sm.set_shader_parameter("emit_tex", src.emission_texture)
		sm.set_shader_parameter("cells", Vector2(48.0, 64.0) if nm.begins_with("A_") else Vector2(2.0, 1.0))
		sm.set_shader_parameter("always_lit", 1.0 if nm.begins_with("S_") else 0.0)
		out = sm
	else:
		var d: StandardMaterial3D = src.duplicate()
		d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		out = d
	_facade_mats[key] = out
	return out


static func _collect(n: Node, xf: Transform3D, groups: Dictionary, order: Array, is_root: bool) -> void:
	var t := xf
	if n is Node3D and not is_root:
		t = xf * (n as Node3D).transform
	elif n is Node3D:
		t = (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = (n as MeshInstance3D).get_surface_override_material(si)
			if mat == null:
				mat = mesh.surface_get_material(si)
			if mat == null:
				mat = mat_default()
			# identical-looking materials share one surface
			var key: Variant = mat
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				key = "%s_%s_%d_%.2f" % [sm.albedo_color.to_html(), str(sm.albedo_texture.get_rid()) if sm.albedo_texture else "", sm.transparency, sm.metallic]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = [st, mat]
				order.append(key)
			(groups[key][0] as SurfaceTool).append_from(mesh, si, t)
	for c in n.get_children():
		_collect(c, t, groups, order, false)


static var _mat_default: StandardMaterial3D


static func mat_default() -> StandardMaterial3D:
	if _mat_default == null:
		_mat_default = StandardMaterial3D.new()
	return _mat_default


static func _is_window(c: Color) -> bool:
	return c.b > 0.75 and c.b - c.r > 0.08 and c.g > 0.6


static func _window_mat(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if not _win_mats.has(key):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/window_flat.gdshader")
		sm.set_shader_parameter("albedo", c)
		_win_mats[key] = sm
	return _win_mats[key]


## Repaints surfaces whose colour is close to `from` (e.g. the grey walls of a model).
static func recolor(n: Node, from: Color, to: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si)
			if mat is StandardMaterial3D:
				var c: Color = (mat as StandardMaterial3D).albedo_color
				if abs(c.r - from.r) + abs(c.g - from.g) + abs(c.b - from.b) < 0.06:
					var key := "%d_%s" % [mat.get_instance_id(), to.to_html()]
					if not _recolor.has(key):
						var dup: StandardMaterial3D = mat.duplicate()
						dup.albedo_color = to
						_recolor[key] = dup
					mi.set_surface_override_material(si, _recolor[key])
	for c in n.get_children():
		recolor(c, from, to)


## Sets the per-building seed used by glowing windows.
static func set_lit_seed(n: Node, sd: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("lit_seed", sd)
	for c in n.get_children():
		set_lit_seed(c, sd)


static func aabb(path: String) -> AABB:
	if not _aabbs.has(path):
		var n: Node = scene(path).instantiate()
		_aabbs[path] = _calc_aabb(n, Transform3D.IDENTITY)
		n.free()
	return _aabbs[path]


static func _calc_aabb(n: Node, xf: Transform3D) -> AABB:
	var r := AABB()
	var first := true
	var t := xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is MeshInstance3D:
		r = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var a := _calc_aabb(c, t)
		if a.size != Vector3.ZERO:
			r = a if first else r.merge(a)
			first = false
	return r


static func mesh_of(path: String) -> Mesh:
	## First mesh of a model (for MultiMesh use).
	if not _meshes.has(path):
		var n: Node = scene(path).instantiate()
		var mi := _find_mesh(n)
		_meshes[path] = mi.mesh if mi else null
		n.free()
	return _meshes[path]


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null


## Instantiates a model centred on the origin with its base at y=0.
## foot = available footprint (local X, local Z). Returns a holder Node3D.
static func fit(path: String, foot: Vector2, variant: int = 0, max_scale: float = 1.6, night_seed: float = -1.0) -> Node3D:
	var holder := Node3D.new()
	var m: Node3D = scene(path).instantiate()
	var yaw: float = YAW.get(path, 0.0)
	for pre in STYLE_FLIP:
		if path.begins_with(pre):
			yaw = PI
	if yaw != 0.0:
		# some downloaded models face away from the street: turn them around their centre
		var inner := Node3D.new()
		inner.add_child(m)
		inner.rotation.y = yaw
		holder.set_meta("inner", inner)
	var ab := aabb(path)
	var s: float = min(foot.x / max(ab.size.x, 0.01), foot.y / max(ab.size.z, 0.01))
	s = min(s, max_scale)
	m.scale = Vector3.ONE * s
	m.position = -Vector3(ab.position.x + ab.size.x * 0.5, ab.position.y, ab.position.z + ab.size.z * 0.5) * s
	holder.add_child(holder.get_meta("inner") if holder.has_meta("inner") else m)
	var pack := path.get_slice("/", 0)
	if variant > 0 and VARIANTS.has(pack):
		var vlist: Array = VARIANTS[pack]
		_apply_variant(m, pack, vlist[(variant - 1) % vlist.size()])
	if pack in REAL_PACKS:
		if path.contains("/tree"):
			set_material(m, tree_mat)
		else:
			_realify(m)
	if night_seed >= 0.0:
		if pack == "poly" or pack == "style":
			set_lit_seed(m, night_seed)
		else:
			_apply_night(m, pack, variant, night_seed)
	holder.set_meta("height", ab.size.y * s)
	return holder


const REAL_PACKS := ["suburban", "commercial", "industrial", "cars", "roads", "graveyard"]
static var _real_mats := {}
static var grain_tex: NoiseTexture2D


## Swaps the toon colormap materials of a Kenney model for the realistic finish.
static func _realify(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(si)
			if mat == null:
				mat = mi.mesh.surface_get_material(si)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
				var tex: Texture2D = (mat as StandardMaterial3D).albedo_texture
				var key := tex.get_instance_id()
				if not _real_mats.has(key):
					if grain_tex == null:
						grain_tex = NoiseTexture2D.new()
						grain_tex.seamless = true
						var fn := FastNoiseLite.new()
						fn.frequency = 0.08
						grain_tex.noise = fn
					var sm := ShaderMaterial.new()
					sm.shader = load("res://shaders/kenney_real.gdshader")
					sm.set_shader_parameter("albedo_tex", tex)
					sm.set_shader_parameter("grain_tex", grain_tex)
					_real_mats[key] = sm
				mi.set_surface_override_material(si, _real_mats[key])
	for c in n.get_children():
		_realify(c)


static func _apply_variant(n: Node, pack: String, tex_name: String) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si)
			if mat is StandardMaterial3D:
				var key := "%d_%s_%s" % [mat.get_instance_id(), pack, tex_name]
				if not _var_mats.has(key):
					var dup: StandardMaterial3D = mat.duplicate()
					dup.albedo_texture = load(ROOT + pack + "/Textures/" + tex_name)
					_var_mats[key] = dup
				mi.set_surface_override_material(si, _var_mats[key])
	for c in n.get_children():
		_apply_variant(c, pack, tex_name)


static func _apply_night(n: Node, pack: String, variant: int, sd: float) -> void:
	var tex_path := ROOT + pack + "/Textures/colormap.png"
	if variant > 0 and VARIANTS.has(pack):
		var vlist: Array = VARIANTS[pack]
		tex_path = ROOT + pack + "/Textures/" + vlist[(variant - 1) % vlist.size()]
	if not _night_mats.has(tex_path):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/night_windows.gdshader")
		sm.set_shader_parameter("tex", load(tex_path))
		_night_mats[tex_path] = sm
	_set_overlay(n, _night_mats[tex_path], sd)


static func _set_overlay(n: Node, mat: Material, sd: float) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = mat
		if sd >= 0.0:
			(n as MeshInstance3D).set_instance_shader_parameter("lit_seed", sd)
	for c in n.get_children():
		_set_overlay(c, mat, sd)


## Sets overlay material on all meshes (null restores night windows is caller's job).
static func set_overlay(n: Node, mat: Material) -> void:
	_set_overlay(n, mat, -1.0)


static func set_material(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = m
	for c in n.get_children():
		set_material(c, m)


static func set_cast_shadows(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		set_cast_shadows(c, on)


# ------------------------------------------------------------------ procedural
static func mat(c: Color, rough: float = 0.85, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [c.to_html(), rough, emission]
	if not _std_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		if emission > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emission
		_std_mats[key] = m
	return _std_mats[key]


static func box(size: Vector3, c: Color, pos: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	## Box with base at pos.y.
	var key := "box_%s" % size
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = mat(c)
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	if parent:
		parent.add_child(mi)
	return mi


static func cylinder(r: float, h: float, c: Color, pos: Vector3 = Vector3.ZERO, parent: Node3D = null, segs: int = 12) -> MeshInstance3D:
	var key := "cyl_%.3f_%.3f_%d" % [r, h, segs]
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = segs
		cm.rings = 1
		_meshes[key] = cm
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = mat(c)
	mi.position = pos + Vector3(0, h * 0.5, 0)
	if parent:
		parent.add_child(mi)
	return mi


static func plane(size: Vector2, c: Color, pos: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var key := "plane_%s" % size
	if not _meshes.has(key):
		var pm := PlaneMesh.new()
		pm.size = size
		_meshes[key] = pm
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.material_override = mat(c, 0.95)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent:
		parent.add_child(mi)
	return mi


## Box whose walls use the procedural facade shader (UV in world units).
static func facade_mesh(size: Vector3) -> ArrayMesh:
	var key := "facade_%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := size.y
	# walls: (corner a, corner b, normal)
	var walls := [
		[Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(0, 0, 1)],
		[Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), Vector3(0, 0, -1)],
		[Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(1, 0, 0)],
		[Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(-1, 0, 0)],
	]
	for wl in walls:
		var a: Vector3 = wl[0]
		var b: Vector3 = wl[1]
		var nrm: Vector3 = wl[2]
		var L := a.distance_to(b)
		var verts := [a, b, b + Vector3(0, h, 0), a + Vector3(0, h, 0)]
		var uvs := [Vector2(0, 0), Vector2(L, 0), Vector2(L, h), Vector2(0, h)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nrm)
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(0, 0))
			st.add_vertex(verts[k])
	var top := [Vector3(-hx, h, -hz), Vector3(hx, h, -hz), Vector3(hx, h, hz), Vector3(-hx, h, hz)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(top[k].x, top[k].z))
		st.set_uv2(Vector2(1, 0))
		st.add_vertex(top[k])
	var m := st.commit()
	_meshes[key] = m
	return m


static func facade(size: Vector3, wall: Color, accent: Color, style: float, sd: float, pos: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = facade_mesh(size)
	if not _std_mats.has("facade_sm"):
		var sm := ShaderMaterial.new()
		sm.shader = facade_shader
		_std_mats["facade_sm"] = sm
	mi.material_override = _std_mats["facade_sm"]
	mi.set_instance_shader_parameter("wall_color", wall)
	mi.set_instance_shader_parameter("accent_color", accent)
	mi.set_instance_shader_parameter("style", style)
	mi.set_instance_shader_parameter("seed", sd)
	mi.position = pos
	if parent:
		parent.add_child(mi)
	return mi
