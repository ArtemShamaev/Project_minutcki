extends Node3D
## Disasters: tornado, earthquake, meteor, flood (logic + visuals).

signal happened(kind: String, text: String)

var city: City
var rig
var terrain
var time_scale := 1.0
var active: Array = []   # dictionaries describing running disasters
var rng := RandomNumberGenerator.new()
var _day_seen := 0


func setup(c: City, r, te) -> void:
	city = c
	rig = r
	terrain = te
	rng.randomize()
	city.day_passed.connect(_on_day)


func _on_day() -> void:
	if city.random_disasters == 0 or city.population < 300:
		return
	var p := 1.0 / (900.0 if city.random_disasters == 1 else 300.0)
	if rng.randf() < p:
		var kinds := Defs.DISASTERS.keys()
		trigger(kinds[rng.randi() % kinds.size()])


func busy() -> bool:
	return not active.is_empty()


func _city_center() -> Vector2:
	var s := Vector2.ZERO
	var c := 0
	for b: Building in city.buildings.values():
		if not b.is_service():
			s += Vector2(b.center().x, b.center().z)
			c += 1
	return s / c if c > 0 else Vector2(city.n * 0.3, city.n * 0.5)


func _random_target() -> Vector2:
	var list: Array = []
	for b: Building in city.buildings.values():
		if not b.is_service() and not b.collapsed:
			list.append(b)
	if list.is_empty():
		return _city_center()
	var b: Building = list[rng.randi() % list.size()]
	return Vector2(b.center().x, b.center().z)


## The weather satellite warns people in advance: less damage from disasters.
func _warn_k() -> float:
	return 0.7 if city.space.has("weather") else 1.0


func trigger(kind: String) -> void:
	match kind:
		"tornado": _start_tornado()
		"earthquake": _start_quake()
		"meteor":
			if city.space.has("shield"):
				happened.emit("meteor_end", "🛡 Орбитальный щит сбил метеорит на подлёте! Город в безопасности.")
				return
			_start_meteor()
		"flood": _start_flood()


# ---------------------------------------------------------------- tornado
func _start_tornado() -> void:
	var target := _city_center()
	var side := rng.randi() % 4
	var start := Vector2.ZERO
	match side:
		0: start = Vector2(rng.randf_range(0, city.n), -4)
		1: start = Vector2(city.n + 4, rng.randf_range(0, city.n))
		2: start = Vector2(rng.randf_range(0, city.n), city.n + 4)
		3: start = Vector2(-4, rng.randf_range(0, city.n))
	var dir := (target - start).normalized().rotated(rng.randf_range(-0.25, 0.25))
	var node := _tornado_visual()
	add_child(node)
	active.append({"kind": "tornado", "pos": start, "dir": dir, "t": 0.0, "node": node, "hits": 0})
	happened.emit("tornado", "🌪 Торнадо приближается к городу!")


func _tornado_visual() -> Node3D:
	var root := Node3D.new()
	for i in 6:
		var p := GPUParticles3D.new()
		p.amount = 90
		p.lifetime = 1.4
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 0.2 + i * 0.35
		pm.emission_ring_inner_radius = 0.1 + i * 0.3
		pm.emission_ring_height = 0.2
		pm.direction = Vector3.UP
		pm.spread = 10
		pm.initial_velocity_min = 1.0
		pm.initial_velocity_max = 1.6
		pm.gravity = Vector3.ZERO
		pm.orbit_velocity_min = 1.2
		pm.orbit_velocity_max = 1.8
		pm.scale_min = 0.8
		pm.scale_max = 1.4
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		gr.colors = PackedColorArray([Color(0.3, 0.28, 0.27, 0.0), Color(0.27, 0.25, 0.24, 0.9), Color(0.36, 0.34, 0.32, 0.0)])
		var gt := GradientTexture1D.new()
		gt.gradient = gr
		pm.color_ramp = gt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.0 + i * 0.25, 1.0 + i * 0.25)
		q.material = Effects._quad_mat(Color.WHITE, false)
		p.draw_pass_1 = q
		p.position.y = i * 1.4
		p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 14, 12))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(p)
	var debris := Effects.dust(Vector3(1.2, 0.2, 1.2))
	debris.one_shot = false
	debris.amount = 30
	root.add_child(debris)
	return root


func _update_tornado(d: Dictionary, dt: float) -> bool:
	d.t += dt
	var wob := Vector2(-d.dir.y, d.dir.x) * sin(d.t * 1.7) * 0.6
	d.pos += (d.dir * 2.2 + wob) * dt
	var p: Vector2 = d.pos
	(d.node as Node3D).position = Vector3(p.x, max(city.height_at(p.x, p.y), 0.0), p.y)
	(d.node as Node3D).rotate_y(dt * 4.0)
	var r := 1.6
	for y in range(floori(p.y - r), ceili(p.y + r)):
		for x in range(floori(p.x - r), ceili(p.x + r)):
			if not city.inb(x, y) or Vector2(x + 0.5, y + 0.5).distance_to(p) > r:
				continue
			var i := city.idx(x, y)
			if city.tree[i] == 1 and rng.randf() < 0.2:
				city.tree[i] = 0
				city.trees_changed.emit()
			var b := city.building_at(Vector2i(x, y))
			if b and not b.collapsed and rng.randf() < 6.0 * dt * _warn_k():
				city.collapse_building(b)
				d.hits += 1
	if p.x < -8 or p.y < -8 or p.x > city.n + 8 or p.y > city.n + 8:
		if d.t > 3.0:
			return false
	return d.t < 60.0


# ---------------------------------------------------------------- earthquake
func _start_quake() -> void:
	var c := _random_target()
	active.append({"kind": "earthquake", "pos": c, "t": 0.0, "hits": 0})
	happened.emit("earthquake", "🌍 Землетрясение! Толчки ощущаются по всему городу.")


func _update_quake(d: Dictionary, dt: float) -> bool:
	d.t += dt
	if rig:
		rig.shake = max(rig.shake, 0.35 * (1.0 - d.t / 6.0))
	var r := 14.0
	if d.t > 0.4:
		for b: Building in city.buildings.values():
			if b.collapsed:
				continue
			var dd := Vector2(b.center().x, b.center().z).distance_to(d.pos)
			if dd < r and rng.randf() < (1.0 - dd / r) * 0.35 * dt * _warn_k():
				city.collapse_building(b)
				d.hits += 1
	return d.t < 6.0


# ---------------------------------------------------------------- meteor
func _start_meteor() -> void:
	var target := _random_target()
	var node := Node3D.new()
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	ball.mesh = sm
	ball.material_override = Models.mat(Color(1.0, 0.45, 0.1), 0.6, 3.0)
	node.add_child(ball)
	var trail := Effects.fire(Vector3(0.4, 0.4, 0.4))
	trail.scale = Vector3.ONE * 2.5
	node.add_child(trail)
	add_child(node)
	var from := Vector3(target.x + 40, 60, target.y - 30)
	active.append({"kind": "meteor", "pos": target, "from": from, "t": 0.0, "node": node})
	happened.emit("meteor", "☄ С неба падает метеорит!")


func _update_meteor(d: Dictionary, dt: float) -> bool:
	d.t += dt
	var dur := 4.0
	var tgt := Vector3(d.pos.x, max(city.height_at(d.pos.x, d.pos.y), 0.0), d.pos.y)
	var k: float = min(d.t / dur, 1.0)
	(d.node as Node3D).position = (d.from as Vector3).lerp(tgt, k * k)
	if k >= 1.0:
		(d.node as Node3D).queue_free()
		city.crater(d.pos, 3.2)
		# fires around
		for b: Building in city.buildings.values():
			if Vector2(b.center().x, b.center().z).distance_to(d.pos) < 7.0 and rng.randf() < 0.5:
				city.ignite(b)
		var boom := Effects.dust(Vector3(3, 0.5, 3))
		boom.amount = 120
		boom.scale = Vector3.ONE * 3.0
		boom.position = tgt
		add_child(boom)
		get_tree().create_timer(4.0).timeout.connect(boom.queue_free)
		if rig:
			rig.shake = 0.5
		Sfx.play("bulldoze", 0.0)
		return false
	return true


# ---------------------------------------------------------------- flood
func _start_flood() -> void:
	active.append({"kind": "flood", "t": 0.0, "peak": 0.55, "done": false})
	happened.emit("flood", "🌊 Наводнение! Вода выходит из берегов.")


func _update_flood(d: Dictionary, dt: float) -> bool:
	# the water physics does the rest: rivers and the sea rise, water spreads over low land
	d.t += dt
	var t: float = d.t
	var lvl := 0.0
	if t < 6.0:
		lvl = d.peak * t / 6.0
	elif t < 18.0:
		lvl = d.peak
	else:
		lvl = d.peak * (1.0 - (t - 18.0) / 8.0)
	city.flood_surge = maxf(lvl, 0.0)
	if city.water_sim:
		city.water_sim.surge = city.flood_surge
		# lakes without rivers fill up from a cloudburst instead
		city.water_sim.rain = 0.0025 if t < 14.0 and city.water_sim.fixed.is_empty() else 0.0
	if t >= 26.0:
		city.flood_surge = 0.0
		if city.water_sim:
			city.water_sim.rain = 0.0
	return t < 26.0


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if city == null or active.is_empty():
		return
	var dt: float = delta * min(time_scale, 2.0)
	if dt <= 0.0:
		return
	for d in active.duplicate():
		var alive := true
		match d.kind:
			"tornado": alive = _update_tornado(d, dt)
			"earthquake": alive = _update_quake(d, dt)
			"meteor": alive = _update_meteor(d, dt)
			"flood": alive = _update_flood(d, dt)
		if not alive:
			if d.has("node") and is_instance_valid(d.node):
				d.node.queue_free()
			active.erase(d)
			happened.emit(d.kind + "_end", "Последствия: %s. Пострадавших за всё время: %d." % [Defs.DISASTERS[d.kind].name, city.casualties])
