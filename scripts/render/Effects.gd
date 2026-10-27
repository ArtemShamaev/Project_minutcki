class_name Effects
## Particle effect factory.

static var _mats := {}


static func _quad_mat(color: Color, additive: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), additive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


static func _soft_dot() -> Texture2D:
	if _mats.has("dot"):
		return _mats["dot"]
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 64
	g.height = 64
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	_mats["dot"] = g
	return g


static func _ramp(cols: Array) -> GradientTexture1D:
	var gr := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / (cols.size() - 1))
		cs.append(cols[i])
	gr.offsets = offs
	gr.colors = cs
	var t := GradientTexture1D.new()
	t.gradient = gr
	return t


static func _make(amount: int, life: float, size: float, color_ramp: Array, vel: float, spread: float, gravity: Vector3, additive: bool, box: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = vel * 0.6
	pm.initial_velocity_max = vel
	pm.gravity = gravity
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.4))
	cv.add_point(Vector2(0.3, 1.0))
	cv.add_point(Vector2(1, 1.6))
	sc.curve = cv
	pm.scale_curve = sc
	pm.color_ramp = _ramp(color_ramp)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _quad_mat(Color.WHITE, additive)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
	return p


static func fire(extent: Vector3) -> Node3D:
	var root := Node3D.new()
	var f := _make(28, 0.9, 0.35, [Color(1, 0.9, 0.4, 0.0), Color(1, 0.6, 0.1, 0.9), Color(0.9, 0.2, 0.05, 0.6), Color(0.3, 0.1, 0.05, 0.0)],
		0.7, 15.0, Vector3(0, 0.3, 0), true, extent)
	root.add_child(f)
	var s := _make(20, 3.0, 0.55, [Color(0.2, 0.2, 0.2, 0.0), Color(0.15, 0.15, 0.15, 0.6), Color(0.3, 0.3, 0.3, 0.3), Color(0.4, 0.4, 0.4, 0.0)],
		0.6, 12.0, Vector3(0.15, 0.1, 0.05), false, extent * 0.6)
	s.position.y = 0.3
	root.add_child(s)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.55, 0.2)
	light.light_energy = 2.0
	light.omni_range = 2.5
	light.position.y = 0.3
	root.add_child(light)
	return root


static func smoke(amount: int = 10, dark: float = 0.5) -> GPUParticles3D:
	var c := 0.85 - dark * 0.5
	return _make(amount, 4.0, 0.4, [Color(c, c, c, 0.0), Color(c, c, c, 0.55), Color(c + 0.1, c + 0.1, c + 0.1, 0.25), Color(1, 1, 1, 0.0)],
		0.35, 10.0, Vector3(0.12, 0.05, 0.04), false, Vector3(0.03, 0.0, 0.03))


static func dust(extent: Vector3) -> GPUParticles3D:
	var p := _make(40, 1.6, 0.5, [Color(0.6, 0.55, 0.45, 0.0), Color(0.65, 0.6, 0.5, 0.7), Color(0.7, 0.65, 0.55, 0.0)],
		0.8, 70.0, Vector3(0, -0.4, 0), false, extent)
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = true
	return p


static func fountain() -> GPUParticles3D:
	var p := _make(40, 1.0, 0.08, [Color(0.8, 0.9, 1.0, 0.0), Color(0.85, 0.95, 1.0, 0.8), Color(0.8, 0.9, 1.0, 0.0)],
		1.4, 8.0, Vector3(0, -3.0, 0), false, Vector3(0.02, 0, 0.02))
	return p
