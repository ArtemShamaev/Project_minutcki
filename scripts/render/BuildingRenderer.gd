extends Node3D
## Creates and updates the visual representation of buildings.

var city: City
var nodes := {}          # id -> Node3D
var keys := {}           # id -> visual key string
var icons := {}          # id -> Sprite3D
var spinners: Array = [] # [node, axis, speed]
var rocket_pads := {}       # spaceport id -> rocket node standing on the pad
var _launch_t := 25.0
var _flights: Array = []    # [node, speed, smoke]
var _orbit_root: Node3D = null
var _orbiters: Array = []   # [node, angle, speed, height, radius]
var blinkers: Array = []
var airports: Array = []
var nodders: Array = []  # [node, phase] pumpjack beams
var _t := 0.0

const R_LOW_MODELS := [
	["suburban/building-type-a", "suburban/building-type-c", "suburban/building-type-h", "suburban/building-type-i", "suburban/building-type-g", "suburban/building-type-k", "suburban/building-type-p", "suburban/building-type-q"],
	["suburban/building-type-b", "suburban/building-type-e", "suburban/building-type-j", "suburban/building-type-o", "suburban/building-type-r", "suburban/building-type-l", "suburban/building-type-u"],
	["suburban/building-type-d", "suburban/building-type-f", "suburban/building-type-m", "suburban/building-type-n", "suburban/building-type-t", "suburban/building-type-s"],
]
const C_LOW_MODELS := [
	["commercial/building-a", "commercial/building-b", "commercial/building-c", "commercial/building-d", "commercial/building-h", "commercial/building-e"],
	["commercial/building-f", "commercial/building-g", "commercial/building-i", "commercial/building-k", "commercial/building-j"],
	["commercial/building-l", "commercial/building-m", "commercial/building-n"],
]
const C_HIGH_MODELS := [
	["commercial/building-i", "commercial/building-l", "commercial/building-m", "commercial/building-n"],
	["commercial/building-skyscraper-a", "commercial/building-skyscraper-c", "commercial/building-skyscraper-e"],
	["commercial/building-skyscraper-b", "commercial/building-skyscraper-d", "commercial/building-skyscraper-c"],
]
const IND_MODELS := [
	["industrial/building-h", "industrial/building-i", "industrial/building-j", "industrial/building-k", "industrial/building-o", "industrial/building-p", "industrial/building-s", "industrial/building-d"],
	["industrial/building-a", "industrial/building-b", "industrial/building-e", "industrial/building-g", "industrial/building-m", "industrial/building-t"],
	["industrial/building-c", "industrial/building-f", "industrial/building-l", "industrial/building-n", "industrial/building-q", "industrial/building-r"],
]
# downloaded apartment blocks and towers (assets/poly, modular), by building level
const R_HIGH_MODELS := [
	["poly/kk_a", "poly/kk_b", "poly/kk_e", "poly/small_c", "poly/small_d", "poly/small_e", "poly/brick_a", "modular/building-sample-tower-a", "modular/building-sample-tower-b"],
	["poly/large_b", "poly/large_c", "poly/large_e", "poly/large_f", "poly/brick_b", "poly/brick_c", "poly/brick_d", "modular/building-sample-tower-c", "modular/building-sample-tower-d", "poly/kk_b"],
	["poly/large_a", "poly/large_d", "poly/sky_a", "poly/sky_e", "poly/large_h", "poly/brick_c"],
]
const OFFICE_MODELS := [
	["poly/small_a", "poly/small_b", "poly/large_g", "poly/large_e"],
	["poly/sky_e", "poly/sky_h", "poly/sky_b", "poly/large_a", "poly/sky_a"],
	["poly/sky_f", "poly/sky_g", "poly/sky_b", "poly/sky_h", "poly/sky_a"],
]
# wall colours for the grey Kenney blocks
const WALLS := [Color("c4c4c4"), Color("e3d5bb"), Color("d9b8a3"), Color("b9cbd9"), Color("ece4d0"), Color("cdb79e"), Color("c9d3c0")]
const PLANE_YAW := 0.0   # turns the airplane model so its nose points to +Z
const CARS := ["cars/sedan", "cars/suv", "cars/hatchback-sports", "cars/van", "cars/taxi", "cars/sedan-sports", "cars/suv-luxury"]
const FACADE_COLORS := [Color("e8dcc4"), Color("d9a77f"), Color("c9cfd6"), Color("efe3a8"), Color("b8d4e3"), Color("d7b9a6"), Color("f2efe9"), Color("c4a484")]
const OFFICE_COLORS := [Color("8fa5b8"), Color("6d8aa3"), Color("a7b8c4"), Color("5f7d8c"), Color("9db3b0")]


func setup(c: City) -> void:
	city = c
	city.building_added.connect(_on_added)
	city.building_removed.connect(_on_removed)
	city.building_updated.connect(_on_updated)


func clear_all() -> void:
	for n in nodes.values():
		n.queue_free()
	nodes.clear()
	keys.clear()
	icons.clear()
	spinners.clear()
	rocket_pads.clear()
	blinkers.clear()
	airports.clear()
	nodders.clear()


func rebuild_all() -> void:
	clear_all()
	for b: Building in city.buildings.values():
		_build(b, false)


func _process(delta: float) -> void:
	Prof.b("brender")
	_process_inner(delta)
	Prof.e("brender")


func _process_inner(delta: float) -> void:
	_t += delta
	_update_rockets(delta)
	_update_orbiters(delta)
	var dead := false
	for s in spinners:
		var nd = s[0]
		if is_instance_valid(nd):
			nd.rotate_object_local(s[1], s[2] * delta)
		else:
			dead = true
	if dead:
		spinners = spinners.filter(func(s): return is_instance_valid(s[0]))
	for nd in nodders:
		if is_instance_valid(nd[0]):
			nd[0].rotation.x = sin(_t * 1.8 + nd[1]) * 0.35
	for bl in blinkers:
		if is_instance_valid(bl):
			bl.visible = fmod(_t, 1.5) < 0.4
	_update_airports(delta)
	for id in icons:
		var sp: Sprite3D = icons[id]
		if is_instance_valid(sp):
			sp.position.y = sp.get_meta("base_y") + sin(_t * 3.0 + id) * 0.06


func _visual_key(b: Building) -> String:
	var extra := city.ind_spec(b)
	if b.type == "cityhall":
		extra = ",".join(b.ministries)
	if b.store_cap() > 0.0:
		extra = str(int(clamp(b.stored / b.store_cap(), 0.0, 1.0) * 4.0))
	return "%d_%s_%s_%s_%s_%s_%s_%d" % [b.level, b.abandoned, b.build_days > 0 and b.type == "zone", b.fire > 0, b.collapsed, extra, b.style, b.stage]


func _on_added(b: Building) -> void:
	_build(b, true)


func _on_removed(b: Building, reason: String) -> void:
	if nodes.has(b.id):
		var n: Node3D = nodes[b.id]
		if reason in ["bulldoze", "collapse", "dezone"]:
			var d := Effects.dust(Vector3(b.sx * 0.4, 0.1, b.sy * 0.4))
			d.position = b.center() + Vector3(0, b.base_y + 0.1, 0)
			add_child(d)
			get_tree().create_timer(2.5).timeout.connect(d.queue_free)
		n.queue_free()
		nodes.erase(b.id)
		keys.erase(b.id)
		icons.erase(b.id)


func _on_updated(b: Building) -> void:
	if not nodes.has(b.id):
		return
	if keys.get(b.id, "") != _visual_key(b):
		var animate: bool = b.build_days == 0 and keys.get(b.id, "").contains("_true_") and not b.abandoned
		nodes[b.id].queue_free()
		nodes.erase(b.id)
		icons.erase(b.id)
		_build(b, animate)
	else:
		_update_icon(b)


func _build(b: Building, animate: bool) -> void:
	var root := Node3D.new()
	root.position = b.center() + Vector3(0, b.base_y, 0)
	root.rotation.y = -b.dir * PI * 0.5
	add_child(root)
	nodes[b.id] = root
	keys[b.id] = _visual_key(b)
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var content := Node3D.new()
	root.add_child(content)
	if city.lot_range(b.tiles()) > 0.02:
		var fnd := Models.box(Vector3(b.w * 0.99, 1.2, b.d * 0.99), Color("8a8478"), Vector3(0, -1.2, 0), root)
		fnd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var h := 1.0
	if b.collapsed:
		h = _build_ruins(b, content, rng)
	elif b.is_service():
		h = _build_service(b, content, rng)
	elif b.build_days > 0:
		h = _build_construction(b, content, rng)
	else:
		h = _build_zoned(b, content, rng)
	root.set_meta("height", h)
	_apply_lod(content)
	if b.abandoned and not b.collapsed:
		Models.set_overlay(content, Models.tint_mat)
		_set_facade_dark(content)
	if b.fire > 0:
		var f := Effects.fire(Vector3(b.w * 0.3, 0.1, b.d * 0.3))
		f.position.y = h * 0.6
		root.add_child(f)
	if animate:
		content.scale = Vector3(1, 0.05, 1)
		var tw := create_tween()
		tw.tween_property(content, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_update_icon(b)


## Small decorations disappear when the camera is far away.
func _apply_lod(n: Node) -> void:
	if n is GeometryInstance3D and not n is GPUParticles3D:
		var gi := n as GeometryInstance3D
		var ab := gi.get_aabb()
		var sc := gi.global_transform.basis.get_scale()
		var sz := Vector3(ab.size.x * sc.x, ab.size.y * sc.y, ab.size.z * sc.z)
		if max(sz.x, max(sz.y, sz.z)) < 0.42:
			gi.visibility_range_end = 32.0
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			gi.visibility_range_end = 220.0
	elif n is GPUParticles3D:
		(n as GPUParticles3D).visibility_range_end = 60.0
	for c in n.get_children():
		_apply_lod(c)


func _set_facade_dark(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial:
		(n as MeshInstance3D).set_instance_shader_parameter("dark", 1.0)
	for c in n.get_children():
		_set_facade_dark(c)


func _update_icon(b: Building) -> void:
	var prob := ""
	for p in ["fire", "flood", "noroad", "power", "water", "sewage", "abandoned", "dead", "garbage", "dirtywater", "sick", "crime", "depleted", "nores", "nobuyers", "traffic", "full"]:
		if p in b.problems:
			prob = p
			break
	if b.fire > 0:
		prob = "fire"
	if prob == "" and b.is_service() and (b.is_full() or (b.type in ["pump", "tower"] and city.pump_dirty(b) > 0.25)):
		prob = "full" if b.is_full() else "dirtywater"
	var root: Node3D = nodes.get(b.id)
	if root == null:
		return
	var sp: Sprite3D = icons.get(b.id)
	if prob == "":
		if sp:
			sp.queue_free()
			icons.erase(b.id)
		return
	if sp == null:
		sp = Sprite3D.new()
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.no_depth_test = true
		sp.fixed_size = true
		sp.pixel_size = 0.00045
		sp.render_priority = 10
		sp.shaded = false
		root.add_child(sp)
		icons[b.id] = sp
		var by: float = float(root.get_meta("height", 1.0)) + 0.35
		sp.set_meta("base_y", by)
		sp.position.y = by
	sp.texture = Icons.get_tex("st_" + prob, 48)


# ---------------------------------------------------------------- megaprojects
## A construction site: fences, a growing concrete core with scaffolding and tower cranes.
func _build_mega_site(b: Building, content: Node3D, rng: RandomNumberGenerator) -> float:
	var def: Dictionary = Defs.SERVICES[b.type]
	var k := float(b.stage) / float(def.stages)
	_pad(content, b, Color("8a7d64"))
	var w := float(b.w)
	var d := float(b.d)
	var hh := 0.3 + k * 2.2
	Models.box(Vector3(w * 0.55, hh, d * 0.55), Color("a8a39a"), Vector3(0, 0, 0), content)
	# scaffolding around the core
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			for lv in int(hh / 0.3) + 1:
				Models.box(Vector3(0.04, 0.3, 0.04), Color("d4a017"), Vector3(sx * w * 0.3, lv * 0.3, sz * d * 0.3), content)
	for c in 2:
		var cr := Node3D.new()
		cr.position = Vector3((-0.4 + c * 0.8) * w * 0.5, 0, (0.4 - c * 0.8) * d * 0.5)
		content.add_child(cr)
		var mast := hh + 1.2
		for lv in int(mast / 0.25):
			Models.box(Vector3(0.07, 0.25, 0.07), Color("f1c40f"), Vector3(0, lv * 0.25, 0), cr)
		var jib := Node3D.new()
		jib.position.y = mast
		cr.add_child(jib)
		Models.box(Vector3(1.6, 0.05, 0.06), Color("f1c40f"), Vector3(0.5, 0, 0), jib)
		Models.box(Vector3(0.18, 0.12, 0.12), Color("7f8c8d"), Vector3(-0.3, 0.02, 0), jib)
		spinners.append([jib, Vector3.UP, 0.15 + rng.randf() * 0.2])
	var f := Models.fit("suburban/fence-3x3", Vector2(w * 0.98, d * 0.98), 0, 4.0)
	content.add_child(f)
	return hh + 1.3


func _rocket() -> Node3D:
	var r := Node3D.new()
	Models.cylinder(0.11, 1.6, Color("f5f6f7"), Vector3(0, 0, 0), r, 12)
	Models.cylinder(0.115, 0.25, Color("2c3e50"), Vector3(0, 0.55, 0), r, 12)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0; cm.bottom_radius = 0.11; cm.height = 0.35; cm.radial_segments = 12
	cone.mesh = cm
	cone.material_override = Models.mat(Color("c0392b"), 0.5)
	cone.position.y = 1.6 + 0.175
	r.add_child(cone)
	for k in 4:
		var fin := Models.box(Vector3(0.02, 0.25, 0.14), Color("2c3e50"), Vector3(0, 0, 0), r)
		fin.position = Vector3(cos(TAU * k / 4.0), 0, sin(TAU * k / 4.0)) * 0.13
		fin.rotation.y = -TAU * k / 4.0
	return r


## A space mission starts from a launch complex: a Saturn V lifts off.
func launch_from(pad_id: int) -> void:
	var rk = rocket_pads.get(pad_id)
	if rk == null or not is_instance_valid(rk):
		return
	var fl: Node3D = Models.fit("poly/saturn5", Vector2(0.35, 0.35), 0, 12.0)
	add_child(fl)
	fl.global_transform = rk.global_transform
	var sm := Effects.smoke(50, 0.15)
	sm.scale = Vector3.ONE * 3.5
	fl.add_child(sm)
	var fire := Models.cylinder(0.09, 0.4, Color(1.0, 0.6, 0.1), Vector3(0, -0.4, 0), fl, 8)
	fire.material_override = Models.mat(Color(1.0, 0.6, 0.15), 0.5, 4.0)
	_flights.append([fl, 0.15, null])


## A test rocket explodes on the pad: fireball, fire and a column of smoke.
func explode_at(pad_id: int) -> void:
	var rk = rocket_pads.get(pad_id)
	if rk == null or not is_instance_valid(rk):
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = rk.global_position + Vector3(0, 0.6, 0)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5; sm.height = 1.0
	ball.mesh = sm
	ball.material_override = Models.mat(Color(1.0, 0.55, 0.1), 0.5, 6.0)
	root.add_child(ball)
	var fire := Effects.fire(Vector3(1.0, 0.4, 1.0))
	root.add_child(fire)
	var smk := Effects.smoke(60, 0.1)
	smk.scale = Vector3.ONE * 4.0
	root.add_child(smk)
	var tw := root.create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * 3.0, 0.6)
	tw.parallel().tween_property(ball, "transparency", 1.0, 0.8)
	tw.tween_interval(6.0)
	tw.tween_callback(root.queue_free)


## Satellites and the space station circle high above the city.
func update_orbiters(list: Array) -> void:
	if _orbit_root == null:
		_orbit_root = Node3D.new()
		add_child(_orbit_root)
	for ch in _orbit_root.get_children():
		ch.queue_free()
	_orbiters.clear()
	var n := float(city.n)
	for i in list.size():
		var big: bool = list[i] == "station"
		var m: Node3D = Models.fit("poly/iss" if big else "poly/satellite", Vector2(6.0, 6.0) if big else Vector2(2.2, 2.2), 0, 100.0)
		_orbit_root.add_child(m)
		_orbiters.append([m, i * TAU / maxf(list.size(), 1.0), 0.03 + 0.01 * (i % 3), 75.0 + 6.0 * (i % 4), n * (0.35 + 0.05 * (i % 3))])


func _update_orbiters(delta: float) -> void:
	var n := float(city.n)
	for o in _orbiters:
		o[1] += o[2] * delta
		var nd: Node3D = o[0]
		nd.position = Vector3(n * 0.5 + cos(o[1]) * o[4], o[3], n * 0.5 + sin(o[1]) * o[4])
		nd.rotation.y = -o[1]


## Rocket launches from finished spaceports: the rocket lifts off with a smoke trail and a new one is rolled out.
func _update_rockets(delta: float) -> void:
	_launch_t -= delta
	if _launch_t <= 0.0:
		_launch_t = randf_range(50.0, 90.0)
		for id in rocket_pads.keys():
			var rk = rocket_pads[id]
			if not is_instance_valid(rk):
				rocket_pads.erase(id)
				continue
			if not rk.visible:
				continue
			var fl := _rocket()
			add_child(fl)
			fl.global_transform = rk.global_transform
			rk.visible = false
			var sm := Effects.smoke(40, 0.2)
			sm.scale = Vector3.ONE * 3.0
			fl.add_child(sm)
			var fire := Models.cylinder(0.08, 0.3, Color(1.0, 0.6, 0.1), Vector3(0, -0.3, 0), fl, 8)
			fire.material_override = Models.mat(Color(1.0, 0.6, 0.15), 0.5, 4.0)
			_flights.append([fl, 0.2, rk])
			city.notify.emit("🚀 С космодрома стартовала ракета!", "good")
	for f in _flights.duplicate():
		var nd = f[0]
		if not is_instance_valid(nd):
			_flights.erase(f)
			continue
		f[1] = f[1] + delta * 1.6
		nd.position.y += f[1] * delta
		nd.rotation.z = min(nd.position.y * 0.004, 0.5)
		if nd.position.y > 60.0:
			nd.queue_free()
			if f[2] != null and is_instance_valid(f[2]):
				f[2].visible = true
			_flights.erase(f)


# ---------------------------------------------------------------- zoned
func _pad(content: Node3D, b: Building, col: Color) -> void:
	var p := Models.plane(Vector2(b.w * 0.98, b.d * 0.98), col, Vector3(0, 0.006, 0), content)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	return list[rng.randi() % list.size()]


func _build_ruins(b: Building, content: Node3D, rng: RandomNumberGenerator) -> float:
	_pad(content, b, Color("6d655a"))
	var cols := [Color("8a8278"), Color("a39a8c"), Color("6b5f52"), Color("b8ae9e"), Color("4f4a44")]
	for i in 10 + b.area() * 6:
		var s := Vector3(rng.randf_range(0.06, 0.22), rng.randf_range(0.03, 0.12), rng.randf_range(0.06, 0.22))
		var bx := Models.box(s, cols[rng.randi() % cols.size()], Vector3(rng.randf_range(-0.42, 0.42) * b.w, 0, rng.randf_range(-0.42, 0.42) * b.d), content)
		bx.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
	for i in 2:
		var wall := Models.box(Vector3(rng.randf_range(0.2, 0.4), rng.randf_range(0.15, 0.35), 0.04), cols[0], Vector3(rng.randf_range(-0.3, 0.3) * b.w, 0, rng.randf_range(-0.3, 0.3) * b.d), content)
		wall.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, 0)
	var sm := Effects.smoke(6, 0.3)
	sm.position.y = 0.1
	content.add_child(sm)
	return 0.3


func _build_construction(b: Building, content: Node3D, rng: RandomNumberGenerator) -> float:
	_pad(content, b, Color("9b8365"))
	var fw := b.w * 0.7
	var fd := minf(b.d, 2.0) * 0.6
	var hh := 0.25 + 0.2 * b.level
	# scaffold frame
	var col := Color("e0a030")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Models.box(Vector3(0.03, hh, 0.03), col, Vector3(sx * fw * 0.5, 0, sz * fd * 0.5), content)
	for yy in [hh * 0.5, hh]:
		Models.box(Vector3(fw, 0.025, 0.03), col, Vector3(0, yy, -fd * 0.5), content)
		Models.box(Vector3(fw, 0.025, 0.03), col, Vector3(0, yy, fd * 0.5), content)
	Models.box(Vector3(fw * 0.9, hh * 0.45, fd * 0.9), Color("b0aaa0"), Vector3.ZERO, content)
	var cone := Models.fit("roads/construction-cone", Vector2(0.08, 0.08), 0, 1.0)
	cone.position = Vector3(-b.w * 0.4, 0, -b.d * 0.45)
	content.add_child(cone)
	if b.w > 1 or b.d > 1:
		# small crane
		Models.box(Vector3(0.05, hh + 0.8, 0.05), Color("f2c230"), Vector3(fw * 0.35, 0, fd * 0.2), content)
		Models.box(Vector3(0.9, 0.04, 0.04), Color("f2c230"), Vector3(fw * 0.35 - 0.25, hh + 0.78, fd * 0.2), content)
	return hh + 0.2


# Architecture styles: zone -> [level 1, level 2, level 3] model lists
const STYLE_MODELS := {
	"soviet": {
		Defs.R_LOW: [["style/sov_izba_a", "style/sov_izba_b"], ["style/sov_izba_a", "style/sov_izba_b"], ["style/sov_izba_b", "style/sov_izba_a"]],
		Defs.R_HIGH: [["style/sov_p5"], ["style/sov_p5", "style/sov_p9"], ["style/sov_p9", "style/sov_p16"]],
		Defs.C_LOW: [["style/sov_shop"], ["style/sov_shop"], ["style/sov_shop", "style/sov_univermag"]],
		Defs.C_HIGH: [["style/sov_univermag"], ["style/sov_univermag"], ["style/sov_univermag", "style/sov_nii"]],
		Defs.OFFICE: [["style/sov_nii"], ["style/sov_nii"], ["style/sov_nii"]],
	},
	"euro": {
		Defs.R_LOW: [["style/eu_half_a", "style/eu_half_c", "style/eu_town_a"], ["style/eu_half_a", "style/eu_half_b", "style/eu_half_c", "style/eu_town_a"], ["style/eu_half_b", "style/eu_town_a", "style/eu_town_c"]],
		Defs.R_HIGH: [["style/eu_town_b", "style/eu_town_c", "poly/brick_a"], ["style/eu_block_a", "style/eu_town_b", "poly/brick_c", "poly/brick_d"], ["poly/classic_big", "style/eu_block_a", "style/eu_town_b"]],
		Defs.C_LOW: [["style/eu_shop_a", "style/eu_shop_b"], ["style/eu_shop_a", "style/eu_shop_b"], ["style/eu_shop_a", "style/eu_town_c"]],
		Defs.C_HIGH: [["style/eu_block_a", "poly/brick_b"], ["style/eu_block_a", "style/eu_town_b", "poly/classic_big"], ["poly/classic_big", "style/eu_block_a"]],
	},
	"american": {
		Defs.R_LOW: [["style/us_house_b", "suburban/building-type-a", "suburban/building-type-c"], ["style/us_house_a", "style/us_house_b", "suburban/building-type-e"], ["style/us_house_a", "suburban/building-type-m"]],
		Defs.R_HIGH: [["style/us_apt", "poly/brick_a"], ["style/us_apt", "poly/brick_c"], ["style/us_apt", "poly/brick_d", "poly/large_b"]],
		Defs.C_LOW: [["style/us_cinema", "commercial/building-a", "commercial/building-c"], ["style/us_cinema", "commercial/building-f"], ["style/us_cinema", "commercial/building-l"]],
		Defs.C_HIGH: [["style/us_tower", "commercial/building-skyscraper-a"], ["style/us_empire", "style/us_tower"], ["style/us_empire", "style/us_tower", "commercial/building-skyscraper-b"]],
		Defs.OFFICE: [["style/us_tower"], ["style/us_tower", "style/us_empire"], ["style/us_empire", "style/us_tower"]],
	},
	"chinese": {
		Defs.R_LOW: [["style/chn_house_a", "style/chn_house_b"], ["style/chn_house_a", "style/chn_house_b"], ["style/chn_house_b", "style/chn_house_a"]],
		Defs.R_HIGH: [["style/chn_mid"], ["style/chn_mid", "style/chn_tower_a"], ["style/chn_tower_a", "style/chn_tower_b", "style/chn_tower_c"]],
		Defs.C_LOW: [["style/chn_shop_a", "style/chn_shop_b", "style/chn_shop_c"], ["style/chn_shop_a", "style/chn_shop_b", "style/chn_shop_c"], ["style/chn_shop_a", "style/chn_shop_c", "style/chn_mid"]],
		Defs.C_HIGH: [["style/chn_mall"], ["style/chn_mall", "style/chn_mid"], ["style/chn_mall", "style/chn_tower_c"]],
		Defs.OFFICE: [["style/chn_tower_c"], ["style/chn_tower_a", "style/chn_tower_c"], ["style/chn_tower_c", "style/chn_tower_b"]],
	},
}
const STYLE_MAX_H := [1.1, 2.2, 3.4]


## Zoned building in an architecture style; returns -1 when the style has no models for the zone.
func _build_style(b: Building, content: Node3D, rng: RandomNumberGenerator, lvl: int) -> float:
	var table: Dictionary = STYLE_MODELS.get(b.style, {})
	if not table.has(b.zone):
		return -1.0
	var list: Array = table[b.zone][lvl]
	var low: bool = b.zone == Defs.R_LOW or b.zone == Defs.C_LOW
	var pad := {Defs.R_LOW: Color("7fb35a"), Defs.R_HIGH: Color("a9a59c"), Defs.C_LOW: Color("a3a3a3"), Defs.C_HIGH: Color("9a9a9a"), Defs.OFFICE: Color("9ea3a8")}
	_pad(content, b, pad.get(b.zone, Color("9a9a9a")))
	var count := b.w if b.w >= 2 and b.d == 1 else 1
	var bw := float(b.w) / count
	var depth := 0.82 if low else b.d * 0.84
	var h := 0.3
	for i in count:
		var path: String = _pick(list, rng)
		var m := Models.fit(path, Vector2(bw * 0.86, depth), rng.randi_range(0, 3), 1.6 + 0.6 * (b.d - 1), rng.randf())
		var mh: float = m.get_meta("height")
		var hmax: float = STYLE_MAX_H[lvl] * (1.0 if not low else 0.6) * (1.0 + 0.3 * (b.d - 1))
		if mh > hmax:
			m.scale = Vector3.ONE * (hmax / mh)
			mh = hmax
		m.position = Vector3(-b.w * 0.5 + bw * (i + 0.5), 0, (-b.d * 0.5 + 0.5) if low else 0.0)
		if path.begins_with("poly/"):
			Models.recolor(m, Color("c4c4c4"), WALLS[rng.randi() % WALLS.size()])
		content.add_child(m)
		h = max(h, mh)
	if low and b.d >= 2:
		_lot_trees(content, b, rng, 2)
	elif not low:
		_lot_trees(content, b, rng, 1)
	return h


func _build_zoned(b: Building, content: Node3D, rng: RandomNumberGenerator) -> float:
	var lvl := clampi(b.level, 1, 3) - 1
	var variant := rng.randi_range(0, 3)
	var h := 1.0
	var front_z := -b.d * 0.5
	if b.style != "modern":
		var sh := _build_style(b, content, rng, lvl)
		if sh >= 0.0:
			return sh
	match b.zone:
		Defs.R_LOW:
			_pad(content, b, Color("7fb35a"))
			var path := _pick(R_LOW_MODELS[lvl], rng)
			var m := Models.fit(path, Vector2(b.w * 0.8, 0.8), variant, 1.0, rng.randf())
			m.position.z = front_z + 0.5
			content.add_child(m)
			h = m.get_meta("height")
			if b.d >= 2:
				# back garden
				for i in rng.randi_range(1, 3):
					var t := Models.fit("suburban/tree-large" if rng.randf() < 0.6 else "suburban/tree-small", Vector2(0.3, 0.3), 0, 1.6)
					t.position = Vector3(rng.randf_range(-0.35, 0.35), 0, front_z + 1.2 + rng.randf_range(0, 0.6))
					content.add_child(t)
				var fence := Models.fit("suburban/fence-2x2", Vector2(b.w * 0.95, 0.95), 0, 2.0)
				fence.position.z = front_z + 1.5
				content.add_child(fence)
				if rng.randf() < 0.5:
					var pl := Models.fit("suburban/planter", Vector2(0.25, 0.25))
					pl.position = Vector3(0.3, 0, front_z + 1.1)
					content.add_child(pl)
		Defs.R_HIGH:
			_pad(content, b, Color("a9a59c"))
			h = _blocks(content, b, rng, R_HIGH_MODELS[lvl], [1.0, 1.25, 1.6][lvl])
			_lot_trees(content, b, rng, 2)
		Defs.C_LOW:
			_pad(content, b, Color("a3a3a3"))
			var m := Models.fit(_pick(C_LOW_MODELS[lvl], rng), Vector2(b.w * 0.88, 0.88), variant, 1.3, rng.randf())
			m.position.z = front_z + 0.5
			content.add_child(m)
			h = m.get_meta("height")
			if b.d >= 2:
				_parking(content, Vector3(0, 0, front_z + 1.5), b.w, rng)
			if rng.randf() < 0.5:
				var aw := Models.fit("commercial/detail-awning-wide", Vector2(b.w * 0.7, 0.2))
				aw.position = Vector3(0, 0.12, front_z + 0.07)
				content.add_child(aw)
		Defs.C_HIGH:
			_pad(content, b, Color("9a9a9a"))
			var m := Models.fit(_pick(C_HIGH_MODELS[lvl], rng), Vector2(b.w * 0.88, b.d * 0.88), variant, 1.45 if b.w > 1 else 1.0, rng.randf())
			content.add_child(m)
			h = m.get_meta("height")
		Defs.OFFICE:
			_pad(content, b, Color("9ea3a8"))
			h = _blocks(content, b, rng, OFFICE_MODELS[lvl], [1.1, 1.4, 1.8][lvl])
			_lot_trees(content, b, rng, 2)
		Defs.AGRI:
			h = _build_farm(b, content, rng)
		Defs.IND:
			var sp := city.ind_spec(b)
			h = _build_spec(b, sp, content, rng) if sp != "" else _build_zoned_ind(b, content, rng, lvl, variant)
	return h


## Apartment / office blocks from downloaded models: one big block on square lots,
## a row of blocks along the street on long ones.
func _blocks(content: Node3D, b: Building, rng: RandomNumberGenerator, list: Array, max_s: float) -> float:
	var h := 0.5
	var wall: Color = WALLS[rng.randi() % WALLS.size()]
	var count := 1
	if b.w >= 2 and b.d == 1:
		count = b.w
	var bw := float(b.w) / count
	for i in count:
		var path := _pick(list, rng)
		var m := Models.fit(path, Vector2(bw * 0.86, b.d * 0.84), 0, max_s * (1.0 + 0.6 * (b.d - 1)), rng.randf())
		m.position.x = -b.w * 0.5 + bw * (i + 0.5)
		if path.begins_with("poly/"):
			Models.recolor(m, Color("c4c4c4"), wall)
		content.add_child(m)
		h = max(h, m.get_meta("height"))
	return h


func _build_farm(b: Building, content: Node3D, rng: RandomNumberGenerator) -> float:
	var front_z := -b.d * 0.5
	var h := 0.5
	var crops := [Color("d4b84a"), Color("8bbf4a"), Color("6d9b3a"), Color("b58b4c"), Color("c9d65a")]
	_pad(content, b, Color("7a6a4a"))
	var rows := b.d * 4
	var cc: Color = crops[rng.randi() % crops.size()]
	for r2 in rows:
		var zc := -b.d * 0.5 + (r2 + 0.5) * (float(b.d) / rows)
		if zc < front_z + 0.55:
			continue
		Models.box(Vector3(b.w * 0.9, 0.025, float(b.d) / rows * 0.7), cc.darkened(0.08 * (r2 % 2)), Vector3(0, 0.0, zc), content)
	Models.box(Vector3(0.38, 0.3, 0.3), Color("b23a2e"), Vector3(-b.w * 0.5 + 0.28, 0, front_z + 0.25), content)
	var roof := Models.box(Vector3(0.42, 0.06, 0.34), Color("eeeeee"), Vector3(-b.w * 0.5 + 0.28, 0.3, front_z + 0.25), content)
	Models.cylinder(0.09, 0.5, Color("cfd8dc"), Vector3(-b.w * 0.5 + 0.6, 0, front_z + 0.22), content, 10)
	var tr := Models.fit("cars/tractor", Vector2(0.22, 0.32))
	tr.position = Vector3(rng.randf_range(-0.3, 0.3) * b.w, 0, front_z + 0.9 + rng.randf() * (b.d - 1.2))
	tr.rotation.y = rng.randf() * TAU
	content.add_child(tr)
	h = 0.5
	return h


## Raw-material industry of specialized districts.
func _build_spec(b: Building, sp: String, content: Node3D, rng: RandomNumberGenerator) -> float:
	var w := float(b.w)
	var d := float(b.d)
	var fz := -d * 0.5
	var h := 0.6
	match sp:
		"farming":
			return _build_farm(b, content, rng)
		"forest":
			_pad(content, b, Color("7a6a4a"))
			Models.facade(Vector3(w * 0.75, 0.38, 0.6), Color("8d6e63"), Color("4e342e"), 2.0, 40.0 + b.seed % 7, Vector3(0, 0, fz + 0.4), content)
			Models.box(Vector3(w * 0.8, 0.05, 0.7), Color("5d4037"), Vector3(0, 0.38, fz + 0.4), content)
			for i in 3 + b.level * 2:
				var lg := Models.cylinder(0.05, w * 0.55, Color("a1887f").darkened(rng.randf() * 0.25), Vector3(0, 0, 0), content, 8)
				lg.rotation.z = PI * 0.5
				lg.position = Vector3(rng.randf_range(-0.1, 0.1) * w, 0.05 + (i % 3) * 0.09, fz + 0.95 + (i / 3) * 0.13)
			for i in maxi(1, int(d) * 2 - 2):
				var t := Models.fit("suburban/tree-large", Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3(rng.randf_range(-0.4, 0.4) * w, 0, fz + 1.4 + rng.randf() * maxf(0.1, d - 1.6))
				content.add_child(t)
			var tr := Models.fit("cars/truck-flat", Vector2(0.22, 0.45))
			tr.position = Vector3(w * 0.35, 0, fz + 0.15)
			tr.rotation.y = PI * 0.5
			content.add_child(tr)
			h = 0.5
		"ore":
			_pad(content, b, Color("6d6258"))
			# headframe with a spinning wheel
			for x in [-0.12, 0.12]:
				Models.box(Vector3(0.04, 0.9, 0.04), Color("455a64"), Vector3(x - w * 0.2, 0, fz + 0.6), content)
			Models.box(Vector3(0.3, 0.04, 0.06), Color("455a64"), Vector3(-w * 0.2, 0.88, fz + 0.6), content)
			var wheel := Models.cylinder(0.13, 0.03, Color("b0bec5"), Vector3(-w * 0.2, 0.92, fz + 0.6), content, 14)
			wheel.rotation.x = PI * 0.5
			var piv := Node3D.new()
			piv.position = wheel.position
			content.add_child(piv)
			wheel.reparent(piv)
			wheel.position = Vector3.ZERO
			spinners.append([piv, Vector3.FORWARD, 1.5])
			Models.facade(Vector3(0.6, 0.3, 0.5), Color("a1887f"), Color("5d4037"), 2.0, 50.0 + b.seed % 5, Vector3(w * 0.2, 0, fz + 0.35), content)
			for i in 1 + b.level:
				var heap := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.02; cm.bottom_radius = rng.randf_range(0.22, 0.32); cm.height = rng.randf_range(0.2, 0.32); cm.radial_segments = 10
				heap.mesh = cm
				heap.material_override = Models.mat([Color("8d6e63"), Color("6d4c41"), Color("90a4ae")][i % 3])
				heap.position = Vector3(rng.randf_range(-0.35, 0.35) * w, cm.height * 0.5, fz + 1.1 + rng.randf() * maxf(0.1, d - 1.4))
				content.add_child(heap)
			var dt := Models.fit("cars/truck", Vector2(0.22, 0.45))
			dt.position = Vector3(w * 0.3, 0, fz + 0.9)
			content.add_child(dt)
			h = 1.0
		"oil":
			_pad(content, b, Color("8a8070"))
			var jacks := clampi(b.area() / 2 + b.level - 1, 1, 5)
			for i in jacks:
				var jp := Vector3(rng.randf_range(-0.3, 0.3) * w, 0, fz + 0.45 + (float(i) / max(1, jacks - 1)) * (d - 0.9) if jacks > 1 else fz + d * 0.5)
				var jk := Node3D.new()
				jk.position = jp
				jk.rotation.y = rng.randf() * TAU
				content.add_child(jk)
				Models.box(Vector3(0.12, 0.05, 0.42), Color("37474f"), Vector3(0, 0, 0), jk)
				Models.box(Vector3(0.04, 0.26, 0.04), Color("ffb300"), Vector3(0, 0.05, 0), jk)
				var beam := Node3D.new()
				beam.position = Vector3(0, 0.3, 0)
				jk.add_child(beam)
				Models.box(Vector3(0.05, 0.05, 0.42), Color("ffb300"), Vector3(0, -0.025, 0), beam)
				Models.box(Vector3(0.07, 0.11, 0.05), Color("263238"), Vector3(0, -0.1, 0.2), beam)
				Models.box(Vector3(0.08, 0.08, 0.08), Color("c62828"), Vector3(0, -0.05, -0.2), beam)
				nodders.append([beam, rng.randf() * TAU])
			var tk := Models.fit("industrial/detail-tank-large", Vector2(0.5, 0.5), 0, 1.0)
			tk.position = Vector3(w * 0.35, 0, fz + 0.3)
			content.add_child(tk)
			h = 0.7
	return h


func _build_zoned_ind(b: Building, content: Node3D, rng: RandomNumberGenerator, lvl: int, variant: int) -> float:
	var front_z := -b.d * 0.5
	var h := 1.0
	_pad(content, b, Color("8d8a80"))
	var bd := minf(b.d, 2.0)
	var m := Models.fit(_pick(IND_MODELS[lvl], rng), Vector2(b.w * 0.88, bd * 0.88), variant, 1.3, rng.randf())
	m.position.z = front_z + bd * 0.5
	content.add_child(m)
	h = m.get_meta("height")
	if b.d >= 3 or (b.d == 2 and bd < b.d):
		_yard(content, Vector3(0, 0, front_z + bd + 0.5), b.w, rng)
	if rng.randf() < 0.55:
		var ch := Models.fit("industrial/chimney-medium" if rng.randf() < 0.5 else "industrial/chimney-small", Vector2(0.25, 0.25), 0, 1.2)
		ch.position = Vector3(b.w * 0.35, 0, front_z + bd * 0.75)
		content.add_child(ch)
		var sm := Effects.smoke(8, 0.6)
		sm.position = ch.position + Vector3(0, ch.get_meta("height") + 0.05, 0)
		content.add_child(sm)
	return h


func _tower(content: Node3D, fp: Vector2, floors: int, fh: float, col: Color, style: float, rng: RandomNumberGenerator, offset: Vector3 = Vector3.ZERO) -> float:
	var h := floors * fh + 0.05
	var accent := col.darkened(0.45)
	var t := Models.facade(Vector3(fp.x, h, fp.y), col, accent, style, rng.randf() * 100.0, offset, content)
	# base podium
	if floors > 6:
		Models.facade(Vector3(fp.x + 0.12, 0.22, fp.y + 0.12), col.darkened(0.15), accent, 2.0, rng.randf() * 100.0, offset, content)
	# rooftop
	Models.box(Vector3(fp.x * 0.35, 0.12, fp.y * 0.35), Color("8a8f96"), offset + Vector3(fp.x * 0.15, h, 0), content)
	if style > 0.5 and floors > 10:
		Models.box(Vector3(0.025, 0.4, 0.025), Color("d0d0d0"), offset + Vector3(-fp.x * 0.2, h, -fp.y * 0.2), content)
	return h + 0.12


func _lot_trees(content: Node3D, b: Building, rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var t := Models.fit("suburban/tree-small", Vector2(0.25, 0.25), 0, 1.4)
		var sx := (rng.randf() - 0.5) * b.w * 0.85
		t.position = Vector3(sx, 0, -b.d * 0.45 + 0.04)
		t.position.x = -b.w * 0.44 if i == 0 else b.w * 0.44
		content.add_child(t)


func _parking(content: Node3D, at: Vector3, w: int, rng: RandomNumberGenerator) -> void:
	Models.plane(Vector2(w * 0.9, 0.85), Color("4d5157"), at + Vector3(0, 0.009, 0), content)
	for i in w * 3:
		Models.box(Vector3(0.015, 0.002, 0.3), Color("e8e8e8"), at + Vector3(-w * 0.42 + i * 0.3 + 0.0, 0.01, 0.15), content)
		if rng.randf() < 0.6:
			var car := Models.fit(_pick(CARS, rng), Vector2(0.2, 0.4))
			car.position = at + Vector3(-w * 0.42 + i * 0.3 + 0.15, 0.01, 0.15)
			car.rotation.y = PI if rng.randf() < 0.5 else 0.0
			content.add_child(car)


func _plane_model() -> Node3D:
	var root := Models.fit("poly/airplane", Vector2(0.95, 0.95), 0, 99.0)
	root.get_child(0).rotation.y = PLANE_YAW
	Models.set_cast_shadows(root, true)
	return root


func _update_airports(delta: float) -> void:
	for a in airports.duplicate():
		var root: Node3D = a.root
		if not is_instance_valid(root):
			airports.erase(a)
			continue
		a.t += delta
		var fz: float = a.fz
		var cyc := 22.0
		var t: float = fmod(a.t, cyc)
		if a.plane == null:
			a.plane = _plane_model()
			a.plane.scale = Vector3.ONE * 1.3
			root.add_child(a.plane)
		var pl: Node3D = a.plane
		# 0..8 take-off roll & climb, 8..14 away (hidden), 14..22 approach & land
		if t < 8.0:
			var k := t / 8.0
			var z: float = fz + 0.6 + k * k * 40.0
			var y: float = 0.05 + max(0.0, k - 0.25) * max(0.0, k - 0.25) * 30.0
			pl.visible = true
			pl.position = Vector3(1.2, y, z)
			pl.rotation = Vector3(-min(0.25, max(0.0, k - 0.25) * 1.2), 0, 0)
		elif t < 14.0:
			pl.visible = false
		else:
			var k := (t - 14.0) / 8.0
			var z: float = fz - 40.0 * (1.0 - k) * (1.0 - k) + 0.6 + 4.5 * k
			var y: float = 0.05 + (1.0 - k) * (1.0 - k) * 14.0
			pl.visible = true
			pl.position = Vector3(1.2, y, z)
			pl.rotation = Vector3(-0.05 * (1.0 - k), 0, 0)


func _bus_prop(col: Color) -> Node3D:
	var root := Node3D.new()
	Models.box(Vector3(0.17, 0.12, 0.46), col, Vector3(0, 0.03, 0), root)
	Models.box(Vector3(0.172, 0.045, 0.4), Color("1f2a36"), Vector3(0, 0.085, 0.01), root)
	Models.box(Vector3(0.16, 0.012, 0.42), Color("f2f2f2"), Vector3(0, 0.15, 0), root)
	return root


func _yard(content: Node3D, at: Vector3, w: int, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(2, 5):
		var opts := ["industrial/shipping-container-a", "industrial/shipping-container-b", "industrial/shipping-container-c", "industrial/detail-tank"]
		var m := Models.fit(_pick(opts, rng), Vector2(0.5, 0.5), 0, 0.9)
		m.position = at + Vector3(rng.randf_range(-w * 0.38, w * 0.38), 0, rng.randf_range(-0.3, 0.3))
		m.rotation.y = PI * 0.5 * rng.randi_range(0, 1)
		content.add_child(m)


# ---------------------------------------------------------------- services
func _build_service(b: Building, content: Node3D, rng: RandomNumberGenerator) -> float:
	var w := float(b.w)
	var d := float(b.d)
	var fz := -d * 0.5
	var h := 1.0
	if not b.done():
		return _build_mega_site(b, content, rng)
	match b.type:
		"spaceport":
			_pad(content, b, Color("8f8c86"))
			Models.box(Vector3(1.6, 0.06, 1.6), Color("6e6b66"), Vector3(0.6, 0, 0.6), content)
			# launch tower and the rocket on the pad
			for k in 6:
				Models.box(Vector3(0.18, 0.5, 0.18), Color("c0392b") if k % 2 == 0 else Color("ecf0f1"), Vector3(1.05, 0.06 + k * 0.5, 0.6), content)
			var rk := _rocket()
			rk.position = Vector3(0.6, 0.06, 0.6)
			content.add_child(rk)
			rocket_pads[b.id] = rk
			# hangar, control centre and a dish
			var hg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.45; cm.bottom_radius = 0.45; cm.height = 1.2; cm.radial_segments = 16
			hg.mesh = cm
			hg.material_override = Models.mat(Color("b0b6bd"), 0.5, 0.0)
			hg.rotation.z = PI * 0.5
			hg.position = Vector3(-0.9, 0.0, -0.6)
			content.add_child(hg)
			Models.facade(Vector3(1.0, 0.45, 0.6), Color("eef1f4"), Color("2f5bd3"), 3.0, 7.0, Vector3(-0.8, 0, fz + 0.45), content)
			Models.cylinder(0.03, 0.4, Color("bdc3c7"), Vector3(-1.5, 0, 1.3), content)
			var dish := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.25; sm.height = 0.18; sm.is_hemisphere = true
			dish.mesh = sm
			dish.material_override = Models.mat(Color("ecf0f1"), 0.4)
			dish.position = Vector3(-1.5, 0.45, 1.3)
			dish.rotation.x = 2.3
			content.add_child(dish)
			spinners.append([dish, Vector3.UP, 0.2])
			h = 3.2
		"arcology":
			_pad(content, b, Color("7fb35a"))
			var y := 0.0
			for t in 5:
				var sz := 2.7 - t * 0.48
				var hh := 0.9 - t * 0.08
				Models.facade(Vector3(sz, hh, sz), Color("e8ecef") if t % 2 == 0 else Color("cfd8dc"), Color("26a69a"), 4.0, 11.0 + t, Vector3(0, y, 0), content)
				# garden terrace on every step
				Models.box(Vector3(sz + 0.05, 0.05, sz + 0.05), Color("4f8a3e"), Vector3(0, y + hh, 0), content)
				for k in 4:
					var tr := Models.fit("suburban/tree-small", Vector2(0.18, 0.18), 0, 1.0)
					var a := TAU * k / 4.0 + t
					tr.position = Vector3(cos(a), 0, sin(a)) * (sz * 0.5 - 0.12) + Vector3(0, y + hh + 0.05, 0)
					content.add_child(tr)
				y += hh + 0.05
			var crown := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.02; cyl.bottom_radius = 0.35; cyl.height = 1.4; cyl.radial_segments = 8
			crown.mesh = cyl
			crown.material_override = Models.mat(Color("80deea"), 0.1, 0.4)
			crown.position.y = y + 0.7
			content.add_child(crown)
			h = y + 1.4
		"fusion":
			_pad(content, b, Color("9a9a9a"))
			var dome := MeshInstance3D.new()
			var ds := SphereMesh.new()
			ds.radius = 0.95; ds.height = 1.9; ds.is_hemisphere = true; ds.radial_segments = 24; ds.rings = 10
			dome.mesh = ds
			dome.material_override = Models.mat(Color("eceff1"), 0.3)
			dome.position = Vector3(-0.3, 0, 0.2)
			content.add_child(dome)
			var ring := MeshInstance3D.new()
			var tm2 := TorusMesh.new()
			tm2.inner_radius = 0.42; tm2.outer_radius = 0.62; tm2.rings = 24; tm2.ring_segments = 10
			ring.mesh = tm2
			ring.material_override = Models.mat(Color("7e57c2"), 0.2, 2.5)
			ring.position = Vector3(-0.3, 1.0, 0.2)
			content.add_child(ring)
			spinners.append([ring, Vector3.UP, 0.6])
			Models.facade(Vector3(0.9, 0.5, 2.6), Color("cfd8dc"), Color("5e35b1"), 2.0, 9.0, Vector3(1.0, 0, 0), content)
			h = 1.6
		"wind":
			_pad(content, b, Color("7fb35a"))
			# modern three-blade turbine: tower, nacelle and a spinning rotor
			var tw := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.025; tm.bottom_radius = 0.06; tm.height = 1.5; tm.radial_segments = 10
			tw.mesh = tm
			tw.material_override = Models.mat(Color("f2f4f5"), 0.5)
			tw.position.y = 0.75
			content.add_child(tw)
			Models.box(Vector3(0.09, 0.08, 0.22), Color("eceff1"), Vector3(0, 1.48, 0.02), content)
			var hub := Node3D.new()
			hub.position = Vector3(0, 1.52, -0.11)
			content.add_child(hub)
			var nose := Models.cylinder(0.035, 0.05, Color("cfd8dc"), Vector3.ZERO, hub, 10)
			nose.rotation.x = PI * 0.5
			for k in 3:
				var arm := Node3D.new()
				arm.rotation.z = TAU * k / 3.0
				hub.add_child(arm)
				var bl := Models.box(Vector3(0.045, 0.62, 0.012), Color("fafafa"), Vector3(0.0, 0.02, 0), arm)
				bl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			spinners.append([hub, Vector3.FORWARD, rng.randf_range(1.2, 2.0)])
			Models.box(Vector3(0.25, 0.1, 0.18), Color("cfd8dc"), Vector3(0.25, 0, 0.3), content)
			h = 2.1
		"coal":
			_pad(content, b, Color("6e6a64"))
			var m := Models.fit("industrial/building-l", Vector2(w * 0.9, d * 0.55), 2, 1.3)
			m.position.z = fz + d * 0.3
			content.add_child(m)
			for i in 2:
				var ch := Models.fit("industrial/chimney-large", Vector2(0.55, 0.55), 0, 1.8)
				ch.position = Vector3(-0.45 + i * 0.9, 0, fz + d * 0.78)
				content.add_child(ch)
				var sm := Effects.smoke(16, 0.95)
				sm.position = ch.position + Vector3(0, ch.get_meta("height") + 0.05, 0)
				sm.scale = Vector3.ONE * 1.6
				content.add_child(sm)
				h = max(h, ch.get_meta("height"))
			var pile := Models.box(Vector3(0.5, 0.12, 0.35), Color("1d1d1d"), Vector3(0.6, 0, fz + 0.25), content)
		"solar":
			_pad(content, b, Color("8fae6a"))
			for i in 2:
				for j in 2:
					var p := Models.fit("industrial/solar-panel-landscape-group", Vector2(0.9, 0.8), 0, 1.0)
					p.position = Vector3(-0.5 + i, 0, -0.5 + j)
					content.add_child(p)
			h = 0.4
		"tower":
			_pad(content, b, Color("7fb35a"))
			var m := Models.fit("industrial/water-tower", Vector2(0.8, 0.8), 0, 1.0)
			content.add_child(m)
			h = m.get_meta("height")
		"pump":
			_pad(content, b, Color("9a978e"))
			Models.facade(Vector3(0.7, 0.35, 0.6), Color("d8dde2"), Color("3d6e9e"), 2.0, 3.0, Vector3(0, 0, fz + 0.45), content)
			Models.box(Vector3(0.74, 0.04, 0.64), Color("3d6e9e"), Vector3(0, 0.35, fz + 0.45), content)
			var tank := Models.fit("industrial/detail-tank", Vector2(0.7, 0.45), 0, 1.0)
			tank.position = Vector3(0, 0, fz + 1.25)
			content.add_child(tank)
			var pipe := Models.cylinder(0.05, 1.2, Color("5b7fa6"), Vector3(0.25, 0.05, fz + 1.4), content)
			pipe.rotation.x = PI * 0.5
			h = 0.5
		"pagoda", "heaven":
			_pad(content, b, Color("b9b2a3"))
			var m := Models.fit("style/chn_pagoda" if b.type == "pagoda" else "style/chn_temple", Vector2(w * 0.8, d * 0.8), 0, 4.0, rng.randf())
			content.add_child(m)
			h = m.get_meta("height")
			for i in 4:
				var t := Models.fit("suburban/tree-large", Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3((-0.85 if i % 2 == 0 else 0.85), 0, (-0.85 if i < 2 else 0.85))
				content.add_child(t)
		"hydro":
			# run-of-river power house: concrete hall, penstocks and turbine outlets, switchyard
			_pad(content, b, Color("8d8a83"))
			Models.facade(Vector3(1.7, 0.5, 0.9), Color("c9c6bd"), Color("37474f"), 6.0, 2.0, Vector3(0, 0, fz + 0.75), content)
			Models.box(Vector3(1.76, 0.06, 0.96), Color("78909c"), Vector3(0, 0.5, fz + 0.75), content)
			Models.box(Vector3(1.9, 0.22, 0.5), Color("b0aca2"), Vector3(0, 0, fz + 1.5), content)
			for i in 3:
				var px := -0.55 + i * 0.55
				var pen := Models.cylinder(0.09, 0.62, Color("5d6d7e"), Vector3(px, 0.2, fz + 1.45), content)
				pen.rotation.x = PI * 0.5
				Models.box(Vector3(0.3, 0.3, 0.06), Color("263238"), Vector3(px, 0.05, fz + 1.76), content)
			# switchyard with transformers in front
			for i in 3:
				Models.box(Vector3(0.16, 0.14, 0.12), Color("546e7a"), Vector3(-0.55 + i * 0.55, 0, fz + 0.18), content)
				Models.box(Vector3(0.02, 0.32, 0.02), Color("90a4ae"), Vector3(-0.55 + i * 0.55, 0, fz + 0.1), content)
			Models.box(Vector3(1.6, 0.02, 0.02), Color("90a4ae"), Vector3(0, 0.32, fz + 0.1), content)
			h = 0.6
		"fire":
			_pad(content, b, Color("9a9a9a"))
			var m := Models.fit("poly/firestation", Vector2(w * 0.95, d * 0.9), 0, 3.0)
			content.add_child(m)
			h = m.get_meta("height")
		"police":
			_pad(content, b, Color("9a9a9a"))
			var m := Models.fit("poly/large_g", Vector2(w * 0.92, d * 0.62), 0, 3.0, rng.randf())
			m.position.z = fz + d * 0.36
			Models.recolor(m, Color("55bd9b"), Color("2f5bd3"))
			Models.recolor(m, Color("c4c4c4"), Color("dfe4ea"))
			content.add_child(m)
			Models.box(Vector3(0.5, 0.12, 0.03), Color("2f5bd3"), Vector3(0, m.get_meta("height") * 0.55, fz + 0.04), content)
			for i in 3:
				var car := Models.fit("cars/police", Vector2(0.2, 0.4))
				car.position = Vector3(-0.55 + i * 0.4, 0, fz + d * 0.84)
				car.rotation.y = PI * 0.5
				content.add_child(car)
			h = m.get_meta("height")
		"clinic":
			_pad(content, b, Color("a8b0a0"))
			Models.facade(Vector3(0.8, 0.55, 1.2), Color("f4f4f4"), Color("c62828"), 2.0, 5.0, Vector3(0, 0, fz + 1.0), content)
			Models.box(Vector3(0.24, 0.07, 0.02), Color("e53935"), Vector3(0, 0.38, fz + 0.39), content)
			Models.box(Vector3(0.07, 0.24, 0.02), Color("e53935"), Vector3(0, 0.3, fz + 0.39), content)
			var amb := Models.fit("cars/ambulance", Vector2(0.22, 0.45))
			amb.position = Vector3(0.25, 0, fz + 0.15)
			amb.rotation.y = PI * 0.5
			content.add_child(amb)
			h = 0.6
		"hospital":
			_pad(content, b, Color("a8b0a0"))
			var m := Models.fit("poly/hospital", Vector2(w * 0.95, d * 0.95), 0, 3.0)
			m.rotation.y = PI * 0.5
			content.add_child(m)
			h = m.get_meta("height")
		"landfill":
			_pad(content, b, Color("7a6a50"))
			var mound := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var lf: float = clamp(b.stored / b.store_cap(), 0.0, 1.0)
			sm.radius = 0.5 + 0.3 * lf; sm.height = 0.3 + 0.7 * lf; sm.radial_segments = 10; sm.rings = 5
			mound.mesh = sm
			mound.material_override = Models.mat(Color("6b5d45"))
			mound.position = Vector3(0, -0.08, 0.15)
			content.add_child(mound)
			for i in 14:
				var c := Color.from_hsv(rng.randf(), 0.5, rng.randf_range(0.4, 0.8))
				var bx := Models.box(Vector3(0.1, 0.06, 0.08), c, Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.05, 0.18), rng.randf_range(-0.3, 0.6)), content)
				bx.rotation.y = rng.randf() * TAU
			var gt := Models.fit("cars/garbage-truck", Vector2(0.24, 0.5))
			gt.position = Vector3(-0.7, 0, fz + 0.3)
			content.add_child(gt)
			var f := Models.fit("suburban/fence-3x3", Vector2(w * 0.98, d * 0.98), 0, 3.0)
			content.add_child(f)
			h = 0.5
		"school":
			_pad(content, b, Color("a9a59c"))
			var m := Models.fit("poly/classic_big", Vector2(w * 0.62, d * 0.55), 0, 3.0, rng.randf())
			m.position = Vector3(-w * 0.18, 0, fz + d * 0.3)
			Models.recolor(m, Color("7e594a"), Color("c0703f"))
			content.add_child(m)
			h = m.get_meta("height")
			# sports field
			Models.plane(Vector2(0.95, 0.8), Color("4caf50"), Vector3(0.38, 0.012, fz + 1.4), content)
			Models.box(Vector3(0.85, 0.003, 0.02), Color("ffffff"), Vector3(0.38, 0.013, fz + 1.4), content)
			Models.cylinder(0.12, 0.004, Color("ffffff"), Vector3(0.38, 0.013, fz + 1.4), content, 16)
			Models.cylinder(0.012, 0.7, Color("dddddd"), Vector3(0.75, 0, fz + 0.45), content, 6)
			Models.box(Vector3(0.002, 0.1, 0.16), Color("1565c0"), Vector3(0.75, 0.6, fz + 0.53), content)
			for i in 2:
				var t := Models.fit("nature/tree_oak", Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3(-0.75 + i * 0.4, 0, fz + 1.65)
				content.add_child(t)
		"university":
			_pad(content, b, Color("7fb35a"))
			Models.facade(Vector3(2.4, 0.8, 0.9), Color("e8dcc4"), Color("8b6f47"), 2.0, 10.0, Vector3(0, 0, fz + 1.6), content)
			for i in 6:
				Models.cylinder(0.05, 0.6, Color("f4efe4"), Vector3(-0.75 + i * 0.3, 0, fz + 1.08), content, 8)
			Models.box(Vector3(1.8, 0.1, 0.25), Color("efe6d4"), Vector3(0, 0.6, fz + 1.1), content)
			var dome := MeshInstance3D.new()
			var sm2 := SphereMesh.new()
			sm2.radius = 0.35; sm2.height = 0.7; sm2.is_hemisphere = true
			dome.mesh = sm2
			dome.material_override = Models.mat(Color("5c8f8a"), 0.4)
			dome.position = Vector3(0, 0.8, fz + 1.6)
			content.add_child(dome)
			Models.facade(Vector3(0.6, 0.6, 1.0), Color("e8dcc4"), Color("8b6f47"), 2.0, 11.0, Vector3(-1.0, 0, fz + 2.4), content)
			Models.facade(Vector3(0.6, 0.6, 1.0), Color("e8dcc4"), Color("8b6f47"), 2.0, 12.0, Vector3(1.0, 0, fz + 2.4), content)
			for i in 6:
				var t := Models.fit("suburban/tree-large", Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3(-1.2 + i * 0.48, 0, fz + 0.35)
				content.add_child(t)
			h = 1.2
		"nuclear":
			_pad(content, b, Color("9e9e9e"))
			for p in [Vector2(-0.8, 0.5), Vector2(0.6, 0.6)]:
				var ct := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.42; cm.bottom_radius = 0.6; cm.height = 1.6; cm.radial_segments = 20
				ct.mesh = cm
				ct.material_override = Models.mat(Color("d7d7d2"))
				ct.position = Vector3(p.x, 0.8, p.y)
				content.add_child(ct)
				var st := Effects.smoke(14, 0.0)
				st.position = Vector3(p.x, 1.65, p.y)
				st.scale = Vector3.ONE * 2.2
				content.add_child(st)
			var dm := MeshInstance3D.new()
			var sm3 := SphereMesh.new()
			sm3.radius = 0.45; sm3.height = 0.9; sm3.is_hemisphere = true
			dm.mesh = sm3
			dm.material_override = Models.mat(Color("eceff1"), 0.4)
			dm.position = Vector3(-0.2, 0.0, fz + 0.7)
			content.add_child(dm)
			Models.facade(Vector3(1.0, 0.4, 0.5), Color("cfd8dc"), Color("1565c0"), 2.0, 30.0, Vector3(0.8, 0, fz + 0.4), content)
			h = 1.7
		"watertreat":
			_pad(content, b, Color("9a978e"))
			for p in [Vector2(-0.45, -0.3), Vector2(0.45, -0.3), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
				Models.cylinder(0.38, 0.12, Color("b0bec5"), Vector3(p.x, 0, p.y), content, 20)
				var wtr := Models.cylinder(0.34, 0.125, Color("4fa3d1"), Vector3(p.x, 0, p.y), content, 20)
				wtr.material_override = Models.mat(Color("4fa3d1"), 0.1)
			Models.facade(Vector3(0.5, 0.3, 0.3), Color("eceff1"), Color("0277bd"), 2.0, 31.0, Vector3(0, 0, fz + 0.2), content)
			h = 0.4
		"recycling":
			_pad(content, b, Color("8d8a80"))
			Models.facade(Vector3(1.5, 0.5, 0.9), Color("a5d6a7"), Color("2e7d32"), 2.0, 32.0, Vector3(0, 0, fz + 0.8), content)
			Models.box(Vector3(1.54, 0.05, 0.94), Color("2e7d32"), Vector3(0, 0.5, fz + 0.8), content)
			for i in 4:
				var c: Color = [Color("1e88e5"), Color("fdd835"), Color("43a047"), Color("e53935")][i]
				Models.box(Vector3(0.22, 0.18, 0.22), c, Vector3(-0.6 + i * 0.4, 0, fz + 1.65), content)
			var gt2 := Models.fit("cars/garbage-truck", Vector2(0.24, 0.5))
			gt2.position = Vector3(0.6, 0, fz + 0.2)
			content.add_child(gt2)
			h = 0.6
		"incinerator":
			_pad(content, b, Color("8d8a80"))
			Models.facade(Vector3(1.4, 0.6, 1.0), Color("90a4ae"), Color("37474f"), 2.0, 33.0, Vector3(-0.2, 0, fz + 0.9), content)
			var chn := Models.fit("industrial/chimney-large", Vector2(0.5, 0.5), 0, 1.8)
			chn.position = Vector3(0.65, 0, fz + 1.3)
			content.add_child(chn)
			var smk := Effects.smoke(12, 0.7)
			smk.position = chn.position + Vector3(0, chn.get_meta("height") + 0.05, 0)
			content.add_child(smk)
			var gt3 := Models.fit("cars/garbage-truck", Vector2(0.24, 0.5))
			gt3.position = Vector3(-0.6, 0, fz + 0.2)
			content.add_child(gt3)
			h = 1.6
		"library":
			_pad(content, b, Color("cfc6b4"))
			Models.facade(Vector3(0.8, 0.4, 0.6), Color("d7ccc8"), Color("5d4037"), 2.0, 34.0, Vector3(0, 0, fz + 0.5), content)
			for i in 4:
				Models.cylinder(0.025, 0.38, Color("f5f0e6"), Vector3(-0.3 + i * 0.2, 0, fz + 0.18), content, 6)
			Models.box(Vector3(0.86, 0.06, 0.16), Color("efebe9"), Vector3(0, 0.38, fz + 0.18), content)
			h = 0.5
		"college":
			_pad(content, b, Color("a9a59c"))
			for i in 2:
				var m := Models.fit("poly/classic_big", Vector2(w * 0.4, d * 0.6), 0, 3.0, rng.randf())
				m.position = Vector3(-w * 0.25 + i * w * 0.5, 0, fz + d * 0.32)
				content.add_child(m)
				h = m.get_meta("height")
			Models.plane(Vector2(2.2, 0.6), Color("4caf50"), Vector3(0, 0.012, fz + 1.62), content)
			for i in 4:
				var t := Models.fit("nature/tree_detailed", Vector2(0.3, 0.3), 0, 1.6)
				t.position = Vector3(-1.1 + i * 0.73, 0, fz + 1.7)
				content.add_child(t)
		"playground":
			_pad(content, b, Color("c2a878"))
			Models.box(Vector3(0.3, 0.02, 0.12), Color("e53935"), Vector3(-0.15, 0.12, 0.1), content).rotation.z = 0.5
			Models.box(Vector3(0.04, 0.2, 0.04), Color("1e88e5"), Vector3(0.0, 0, 0.1), content)
			for x in [-0.25, 0.25]:
				Models.box(Vector3(0.02, 0.22, 0.02), Color("fdd835"), Vector3(x, 0, -0.22), content)
			Models.box(Vector3(0.52, 0.02, 0.02), Color("fdd835"), Vector3(0, 0.22, -0.22), content)
			Models.cylinder(0.09, 0.03, Color("ffcc80"), Vector3(0.22, 0, 0.25), content, 12)
			var tp := Models.fit("suburban/tree-small", Vector2(0.25, 0.25), 0, 1.4)
			tp.position = Vector3(-0.32, 0, 0.32)
			content.add_child(tp)
			h = 0.4
		"sports":
			_pad(content, b, Color("9e9e9e"))
			Models.plane(Vector2(b.w * 0.85, b.d * 0.8), Color("e57373"), Vector3(0, 0.012, 0), content)
			Models.box(Vector3(0.01, 0.003, b.d * 0.75), Color("ffffff"), Vector3(0, 0.014, 0), content)
			for x in [-0.8, 0.8]:
				Models.box(Vector3(0.02, 0.15, 0.2), Color("ffffff"), Vector3(x, 0, 0), content)
			h = 0.3
		"zoo":
			_pad(content, b, Color("8bc34a"))
			Models.cylinder(0.6, 0.01, Color("4fa3d1"), Vector3(0.6, 0.012, 0.6), content, 20).material_override = Models.mat(Color("4fa3d1"), 0.1)
			var fence := Models.fit("suburban/fence-3x3", Vector2(2.95, 2.95), 0, 4.0)
			content.add_child(fence)
			for i in 8:
				var t := Models.fit("suburban/tree-large", Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3(rng.randf_range(-1.3, 1.3), 0, rng.randf_range(-1.3, 0.2))
				content.add_child(t)
			for i in 6:
				var an := Node3D.new()
				var col: Color = [Color("ffb300"), Color("8d6e63"), Color("9e9e9e")][i % 3]
				Models.box(Vector3(0.12, 0.08, 0.2), col, Vector3(0, 0.06, 0), an)
				Models.box(Vector3(0.05, 0.14 if i % 3 == 0 else 0.06, 0.05), col, Vector3(0, 0.12, 0.1), an)
				an.position = Vector3(rng.randf_range(-1.0, 0.2), 0, rng.randf_range(-0.8, 1.0))
				an.rotation.y = rng.randf() * TAU
				content.add_child(an)
			Models.facade(Vector3(0.8, 0.35, 0.4), Color("ffe0b2"), Color("6d4c41"), 2.0, 37.0, Vector3(-0.8, 0, fz + 0.3), content)
			h = 0.8
		"cityhall":
			# Town Hall -> City Hall -> Capitol, with ministry wings around the square
			_pad(content, b, Color("cfc6b4"))
			var lv := clampi(b.level, 1, 3)
			var big := w >= 3
			var m := Models.fit("style/gov_hall%d" % lv, Vector2(w * (0.62 if big else 0.92), d * (0.5 if big else 0.7)), 0, 6.0, rng.randf())
			m.position.z = fz + d * (0.62 if big else 0.45)
			content.add_child(m)
			h = m.get_meta("height")
			var spots := [Vector2(-1.05, 0.95), Vector2(1.05, 0.95), Vector2(-1.05, -0.05), Vector2(1.05, -0.05), Vector2(-1.05, -1.0), Vector2(1.05, -1.0), Vector2(0.0, 1.05)]
			for k in b.ministries.size():
				if k >= spots.size() or not big:
					break
				var sp: Vector2 = spots[k]
				var wing := Models.fit("style/gov_min_%s" % b.ministries[k], Vector2(0.78, 0.7), 0, 3.0, rng.randf())
				wing.position = Vector3(sp.x, 0, sp.y)
				wing.rotation.y = PI * 0.5 if sp.x < 0 else (-PI * 0.5 if sp.x > 0 else PI)
				content.add_child(wing)
			if big:
				# fountain on the square in front
				Models.cylinder(0.28, 0.06, Color("b0a99a"), Vector3(0, 0, fz + 0.45), content, 16)
				var wtr := Models.cylinder(0.24, 0.065, Color("4fa3d8"), Vector3(0, 0.01, fz + 0.45), content, 16)
				wtr.material_override = Models.mat(Color("4fa3d8"), 0.1)
		"dsa_hq":
			_pad(content, b, Color("bfc3c7"))
			var m := Models.fit("style/dsa_hq", Vector2(w * 0.8, d * 0.8), 0, 6.0, rng.randf())
			content.add_child(m)
			h = m.get_meta("height")
			var dish := Models.fit("poly/dish_small", Vector2(0.5, 0.5), 0, 3.0)
			dish.position = Vector3(1.1, 0, -1.1)
			content.add_child(dish)
		"launchpad":
			_pad(content, b, Color("8f8c86"))
			Models.box(Vector3(w * 0.7, 0.08, d * 0.7), Color("6e6b66"), Vector3(0, 0, 0), content)
			var m := Models.fit("poly/launch_tower", Vector2(w * 0.6, d * 0.6), 0, 8.0)
			content.add_child(m)
			h = m.get_meta("height")
			var marker := Node3D.new()
			marker.position = Vector3(0.15, 0.08, 0.0)
			content.add_child(marker)
			rocket_pads[b.id] = marker
			for k in 2:
				var tk := Models.fit("industrial/detail-tank", Vector2(0.4, 0.4), 0, 2.0)
				tk.position = Vector3(-1.1, 0, -0.9 + k * 0.6)
				content.add_child(tk)
		"mission_control":
			_pad(content, b, Color("a7aaae"))
			var m := Models.fit("poly/dish_big", Vector2(w * 0.6, d * 0.6), 0, 4.0)
			m.position = Vector3(0.3, 0, 0.3)
			content.add_child(m)
			Models.facade(Vector3(0.8, 0.35, 0.5), Color("eef1f4"), Color("1565c0"), 3.0, 4.0, Vector3(-0.45, 0, fz + 0.35), content)
			h = m.get_meta("height")
		"train_station":
			_pad(content, b, Color("a9a39a"))
			var m := Models.fit("poly/rail_station", Vector2(w * 0.95, d * 0.95), 0, 3.0, rng.randf())
			content.add_child(m)
			h = m.get_meta("height")
			var clock := Models.cylinder(0.12, 0.03, Color("f5f5f5"), Vector3(0, h + 0.02, fz + 0.1), content, 16)
			clock.rotation.x = PI * 0.5
		"cargo_station":
			_pad(content, b, Color("8f8c86"))
			var cols := [Color("c62828"), Color("1565c0"), Color("2e7d32"), Color("f9a825"), Color("6d4c41")]
			for gx in 4:
				for gz in 2:
					for lv in rng.randi_range(1, 3):
						Models.box(Vector3(0.5, 0.2, 0.22), cols[rng.randi() % cols.size()], Vector3(-0.9 + gx * 0.6 - 0.0, lv * 0.2 - 0.2, -0.45 + gz * 0.28), content)
			var cr := Models.fit("poly/rail_crane", Vector2(0.3, w * 0.95), 0, 3.0)
			cr.rotation.y = PI * 0.5
			cr.position.z = -0.25
			content.add_child(cr)
			h = cr.get_meta("height")
		"rocket_factory":
			_pad(content, b, Color("8f8c86"))
			var m := Models.fit("poly/rocket_factory", Vector2(w * 0.62, d * 0.62), 0, 3.0, rng.randf())
			m.position = Vector3(-0.35, 0, -0.3)
			content.add_child(m)
			h = m.get_meta("height")
			# finished rocket stages waiting for the trucks
			for k in 2:
				var st := Models.cylinder(0.13, 1.1, Color("eceff1"), Vector3.ZERO, content, 12)
				st.rotation.z = PI * 0.5
				st.position = Vector3(0.75, 0.14, 0.55 + k * 0.32)
				Models.cylinder(0.135, 0.12, Color("c62828"), Vector3(0.75 + 0.42, 0.01, 0.55 + k * 0.32), content, 12).rotation.z = PI * 0.5
			for k in 2:
				var tk := Models.fit("industrial/detail-tank", Vector2(0.4, 0.4), 0, 2.0)
				tk.position = Vector3(1.05, 0, -0.9 + k * 0.5)
				content.add_child(tk)
		"astro_center":
			_pad(content, b, Color("a7aaae"))
			var m := Models.fit("poly/astro_dome", Vector2(w * 0.72, d * 0.72), 0, 3.0, rng.randf())
			m.position.z = -0.12
			content.add_child(m)
			h = m.get_meta("height")
			var a := Models.fit("poly/astronaut", Vector2(0.22, 0.22), 0, 3.0)
			if a.get_meta("height") > 0.4:
				a.scale = Vector3.ONE * (0.4 / a.get_meta("height"))
			a.position = Vector3(0.0, 0.0, fz + 0.15)
			content.add_child(a)
		"observatory":
			_pad(content, b, Color("7fb35a"))
			var m := Models.fit("poly/observatory", Vector2(w * 0.78, d * 0.78), 0, 3.0, rng.randf())
			content.add_child(m)
			h = m.get_meta("height")
		"rectenna":
			_pad(content, b, Color("7fb35a"))
			# a field of receiving antennas around the tower
			for gy in 5:
				for gx in 5:
					if abs(gx - 2) <= 0 and abs(gy - 2) <= 0:
						continue
					var pn := Models.box(Vector3(0.42, 0.04, 0.42), Color("90a4ae"), Vector3((gx - 2) * 0.55, 0.12, (gy - 2) * 0.55), content)
					pn.rotation.x = -0.35
					Models.box(Vector3(0.04, 0.12, 0.04), Color("607d8b"), Vector3((gx - 2) * 0.55, 0, (gy - 2) * 0.55), content)
			var m := Models.fit("poly/rectenna", Vector2(0.5, 0.5), 0, 3.0)
			if m.get_meta("height") > 2.2:
				m.scale = Vector3.ONE * (2.2 / m.get_meta("height"))
			content.add_child(m)
			h = minf(m.get_meta("height"), 2.2)
			var lamp := Models.box(Vector3(0.06, 0.06, 0.06), Color(1, 0.3, 0.2), Vector3(0, h, 0), content)
			lamp.material_override = Models.lamp_mat
			blinkers.append(lamp)
		"space_museum":
			_pad(content, b, Color("b9b2a3"))
			Models.facade(Vector3(1.6, 0.55, 0.9), Color("eceff1"), Color("1a237e"), 2.0, 5.0, Vector3(-0.15, 0, -0.35), content)
			var m := Models.fit("poly/museum_rocket", Vector2(0.45, 0.45), 0, 3.0)
			var rh: float = m.get_meta("height")
			if rh > 1.8:
				m.scale = Vector3.ONE * (1.8 / rh)
			m.position = Vector3(0.62, 0, fz + 0.32)
			content.add_child(m)
			h = 1.8
		"he3_plant":
			_pad(content, b, Color("9a9a9a"))
			for k in 2:
				var dome := MeshInstance3D.new()
				var ds := SphereMesh.new()
				ds.radius = 0.55; ds.height = 1.1; ds.is_hemisphere = true; ds.radial_segments = 20; ds.rings = 8
				dome.mesh = ds
				dome.material_override = Models.mat(Color("e3f2fd"), 0.3)
				dome.position = Vector3(-0.6 + k * 1.1, 0, -0.4)
				content.add_child(dome)
				var ring := MeshInstance3D.new()
				var tm2 := TorusMesh.new()
				tm2.inner_radius = 0.28; tm2.outer_radius = 0.38; tm2.rings = 20; tm2.ring_segments = 8
				ring.mesh = tm2
				ring.material_override = Models.mat(Color("4fc3f7"), 0.2, 3.0)
				ring.position = Vector3(-0.6 + k * 1.1, 0.62, -0.4)
				content.add_child(ring)
				spinners.append([ring, Vector3.UP, 0.8 - k * 1.6])
			for k in 3:
				Models.cylinder(0.16, 0.5, Color("4fc3f7"), Vector3(-0.8 + k * 0.4, 0, 0.75), content, 12)
			Models.facade(Vector3(0.7, 0.4, 0.5), Color("cfd8dc"), Color("0277bd"), 2.0, 9.0, Vector3(0.9, 0, 0.7), content)
			h = 1.2
		"casino", "bigben", "liberty", "coliseum", "lighthouse", "mansion":
			var pads := {"casino": Color("5b5b5b"), "bigben": Color("b9b2a3"), "liberty": Color("7fb35a"), "coliseum": Color("cbbf9f"), "lighthouse": Color("cdbb8a"), "mansion": Color("7fb35a")}
			_pad(content, b, pads[b.type])
			var foot := 0.95 if b.type in ["casino", "coliseum", "mansion"] else 0.75
			var m := Models.fit("poly/" + b.type, Vector2(w * foot, d * foot), 0, 8.0, rng.randf())
			content.add_child(m)
			h = m.get_meta("height")
			var cap: float = {"bigben": 2.8, "liberty": 2.1, "casino": 1.3, "coliseum": 0.9, "mansion": 0.8, "lighthouse": 1.4}[b.type]
			if h > cap:
				m.scale = Vector3.ONE * (cap / h)
				h = cap
			if b.type == "lighthouse":
				var beam := Models.box(Vector3(0.05, 0.05, 0.05), Color(1.0, 0.95, 0.7), Vector3(0, h * 0.9, 0), content)
				beam.material_override = Models.lamp_mat
				blinkers.append(beam)
		"tvtower":
			_pad(content, b, Color("9a9a9a"))
			for i in 6:
				var c := Color("e53935") if i % 2 == 0 else Color("f5f5f5")
				Models.cylinder(0.09 - i * 0.008, 0.9, c, Vector3(0, i * 0.9, 0), content, 12)
			var pod := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = 0.28; pm.height = 0.35
			pod.mesh = pm
			pod.material_override = Models.mat(Color("cfd8dc"), 0.3)
			pod.position = Vector3(0, 4.3, 0)
			content.add_child(pod)
			Models.cylinder(0.3, 0.06, Color("37474f"), Vector3(0, 4.2, 0), content, 20)
			Models.cylinder(0.015, 1.2, Color("dddddd"), Vector3(0, 5.4, 0), content, 6)
			var lamp := Models.box(Vector3(0.06, 0.06, 0.06), Color("ff1744"), Vector3(0, 6.6, 0), content)
			lamp.material_override = Models.mat(Color("ff1744"), 0.5, 4.0)
			blinkers.append(lamp)
			h = 6.7
		"cathedral":
			_pad(content, b, Color("cfc6b4"))
			Models.box(Vector3(0.9, 0.7, 1.4), Color("f5f1e8"), Vector3(0, 0, fz + 1.05), content)
			Models.box(Vector3(1.4, 0.55, 0.5), Color("f5f1e8"), Vector3(0, 0, fz + 1.05), content)
			var roof := Models.box(Vector3(0.94, 0.06, 1.44), Color("2e7d32"), Vector3(0, 0.7, fz + 1.05), content)
			for p in [Vector3(0, 0, 0), Vector3(-0.5, 0, -0.45), Vector3(0.5, 0, -0.45), Vector3(-0.5, 0, 0.45), Vector3(0.5, 0, 0.45)]:
				var main_d: bool = p == Vector3.ZERO
				var dh := 0.55 if main_d else 0.35
				var base := Vector3(p.x * 0.7, 0.7, fz + 1.05 + p.z)
				Models.cylinder(0.14 if main_d else 0.09, dh, Color("f5f1e8"), base, content, 12)
				var onion := MeshInstance3D.new()
				var om := SphereMesh.new()
				om.radius = 0.19 if main_d else 0.12
				om.height = om.radius * 2.4
				onion.mesh = om
				onion.material_override = Models.mat(Color("ffca28"), 0.25)
				(onion.material_override as StandardMaterial3D).metallic = 0.8
				onion.position = base + Vector3(0, dh + om.radius * 0.9, 0)
				content.add_child(onion)
				var spike := Models.cylinder(0.012, 0.22, Color("ffd54f"), onion.position + Vector3(0, om.radius * 1.1, 0), content, 4)
				Models.box(Vector3(0.1, 0.012, 0.012), Color("ffd54f"), spike.position + Vector3(0, 0.05, 0), content)
			h = 2.0
		"museum":
			_pad(content, b, Color("d8d0bf"))
			Models.facade(Vector3(1.7, 0.5, 1.2), Color("e9e4da"), Color("7b6a52"), 2.0, 21.0, Vector3(0, 0, fz + 1.1), content)
			for i in 8:
				Models.cylinder(0.035, 0.45, Color("faf7f0"), Vector3(-0.75 + i * 0.214, 0, fz + 0.45), content, 8)
			Models.box(Vector3(1.75, 0.07, 0.18), Color("efe9dc"), Vector3(0, 0.45, fz + 0.46), content)
			var pyr := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0; cm.bottom_radius = 0.42; cm.height = 0.45; cm.radial_segments = 4; cm.rings = 1
			pyr.mesh = cm
			var gm := Models.mat(Color(0.55, 0.75, 0.9), 0.1)
			gm.metallic = 0.6
			pyr.material_override = gm
			pyr.position = Vector3(0, 0.5 + 0.225, fz + 1.2)
			pyr.rotation.y = PI * 0.25
			content.add_child(pyr)
			h = 1.0
		"stadium":
			_pad(content, b, Color("9e9e9e"))
			var m := Models.fit("poly/stadium", Vector2(w * 0.98, d * 0.98), 0, 99.0)
			content.add_child(m)
			for p in [Vector2(-1.35, -1.35), Vector2(1.35, -1.35), Vector2(-1.35, 1.35), Vector2(1.35, 1.35)]:
				Models.cylinder(0.025, 1.3, Color("9e9e9e"), Vector3(p.x, 0, p.y), content, 6)
				var fl := Models.box(Vector3(0.22, 0.12, 0.04), Color("fffde7"), Vector3(p.x, 1.3, p.y), content)
				fl.material_override = Models.mat(Color("fffde7"), 0.5, 2.5)
			h = 1.4
		"port":
			_pad(content, b, Color("8d8a80"))
			for i in 3:
				for j in 2:
					for k in rng.randi_range(1, 3):
						var opts := ["industrial/shipping-container-a", "industrial/shipping-container-b", "industrial/shipping-container-c"]
						var cn := Models.fit(opts[rng.randi() % 3], Vector2(0.4, 0.8), 0, 1.0)
						cn.position = Vector3(-1.1 + i * 0.45, k * 0.17, fz + 0.5 + j * 0.0)
						content.add_child(cn)
			for i in 2:
				var cx := 0.4 + i * 0.7
				Models.box(Vector3(0.05, 1.2, 0.05), Color("f9a825"), Vector3(cx - 0.15, 0, fz + 1.5), content)
				Models.box(Vector3(0.05, 1.2, 0.05), Color("f9a825"), Vector3(cx + 0.15, 0, fz + 1.5), content)
				Models.box(Vector3(0.08, 0.08, 1.5), Color("f9a825"), Vector3(cx, 1.2, fz + 1.8), content)
			var hull := Models.box(Vector3(0.7, 0.3, 2.2), Color("b71c1c"), Vector3(0, -0.2, fz + 2.6), content)
			hull.rotation.y = PI * 0.5
			hull.position = Vector3(0.2, -0.2, fz + 2.55)
			Models.box(Vector3(2.0, 0.04, 0.6), Color("37474f"), Vector3(0.2, 0.1, fz + 2.55), content)
			Models.box(Vector3(0.4, 0.4, 0.5), Color("eceff1"), Vector3(1.0, 0.1, fz + 2.55), content)
			h = 1.3
		"airport":
			_pad(content, b, Color("8bc34a"))
			Models.plane(Vector2(0.9, 5.6), Color("3c3f44"), Vector3(1.2, 0.012, fz + 3.0), content)
			for k in 10:
				Models.box(Vector3(0.04, 0.002, 0.25), Color("ffffff"), Vector3(1.2, 0.014, fz + 0.6 + k * 0.52), content)
			Models.plane(Vector2(2.2, 2.4), Color("9e9e9e"), Vector3(-0.6, 0.011, fz + 2.2), content)
			Models.facade(Vector3(2.4, 0.4, 0.7), Color("dfe7ee"), Color("546e7a"), 1.0, 22.0, Vector3(-0.6, 0, fz + 0.5), content)
			Models.box(Vector3(2.5, 0.05, 0.8), Color("90a4ae"), Vector3(-0.6, 0.4, fz + 0.5), content)
			Models.cylinder(0.1, 1.2, Color("eceff1"), Vector3(0.4, 0, fz + 1.2), content, 10)
			var cab := Models.cylinder(0.2, 0.18, Color(0.4, 0.6, 0.75), Vector3(0.4, 1.2, fz + 1.2), content, 10)
			for k in 3:
				var pl := _plane_model()
				pl.position = Vector3(-1.3 + k * 0.7, 0.05, fz + 2.2)
				pl.rotation.y = PI
				content.add_child(pl)
			airports.append({"root": content, "fz": fz, "t": rng.randf() * 10.0, "plane": null})
			h = 1.4
		"outlet":
			_pad(content, b, Color("8f8a80"))
			Models.box(Vector3(0.55, 0.22, 0.4), Color("9e9e9e"), Vector3(0, 0, fz + 0.3), content)
			Models.box(Vector3(0.6, 0.04, 0.45), Color("757575"), Vector3(0, 0.22, fz + 0.3), content)
			var pipe2 := Models.cylinder(0.12, 0.75, Color("6d6d6d"), Vector3(0, 0.12, fz + 0.75), content, 12)
			pipe2.rotation.x = PI * 0.5
			var mouth := Models.cylinder(0.09, 0.02, Color("3e2f1c"), Vector3(0, 0.12, fz + 1.13), content, 12)
			mouth.rotation.x = PI * 0.5
			var sludge := Models.plane(Vector2(0.5, 0.35), Color("5d4a2a"), Vector3(0, 0.01, fz + 1.2), content)
			sludge.material_override = Models.mat(Color("5d4a2a"), 0.2)
			h = 0.3
		"sewtreat":
			_pad(content, b, Color("9a978e"))
			for p in [Vector2(-0.45, -0.3), Vector2(0.45, -0.3), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
				Models.cylinder(0.38, 0.14, Color("a1a1a1"), Vector3(p.x, 0, p.y), content, 20)
				var sw := Models.cylinder(0.34, 0.145, Color("7a6a3a"), Vector3(p.x, 0, p.y), content, 20)
				sw.material_override = Models.mat(Color("7d7040") if p.y < 0 else Color("5e8f7a"), 0.15)
				var arm := Models.box(Vector3(0.66, 0.03, 0.04), Color("eceff1"), Vector3(0, 0.18, 0), content)
				var piv2 := Node3D.new()
				piv2.position = Vector3(p.x, 0, p.y)
				content.add_child(piv2)
				arm.reparent(piv2)
				arm.position = Vector3(0, 0.18, 0)
				spinners.append([piv2, Vector3.UP, rng.randf_range(0.3, 0.6)])
			Models.facade(Vector3(0.5, 0.3, 0.3), Color("cfd8dc"), Color("5d4037"), 2.0, 37.0, Vector3(0, 0, fz + 0.2), content)
			h = 0.4
		"cemetery":
			_pad(content, b, Color("6f9c4f"))
			Models.box(Vector3(0.14, 0.004, d * 0.9), Color("bfb5a0"), Vector3(0, 0.008, 0), content)
			var cr := Models.fit("graveyard/crypt-small", Vector2(0.55, 0.55), 0, 3.0)
			cr.position = Vector3(-w * 0.3, 0, fz + 0.35)
			content.add_child(cr)
			var fill: float = clamp(b.stored / b.store_cap(), 0.0, 1.0)
			var stones := ["graveyard/gravestone-cross", "graveyard/gravestone-round", "graveyard/gravestone-bevel", "graveyard/gravestone-roof", "graveyard/gravestone-decorative"]
			var rows2 := 5
			var cols2 := 6
			var shown := int(rows2 * cols2 * (0.25 + 0.75 * fill))
			var k := 0
			for r2 in rows2:
				for c2 in cols2:
					if k >= shown:
						break
					var gx := (-0.42 + (c2 + 0.5) / cols2 * 0.84) * w
					if abs(gx) < 0.12:
						continue
					var gz := fz + 0.8 + r2 * (d - 1.0) / rows2
					var st := Models.fit(stones[rng.randi() % stones.size()], Vector2(0.12, 0.08), 0, 1.0)
					st.position = Vector3(gx, 0, gz)
					st.rotation.y = PI
					content.add_child(st)
					k += 1
			if fill > 0.6:
				var cl := Models.fit("graveyard/crypt", Vector2(0.3, 0.4), 0, 3.0)
				cl.position = Vector3(w * 0.3, 0, fz + 0.35)
				content.add_child(cl)
			for i in 4:
				var t := Models.fit("graveyard/pine", Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3((-0.43 if i % 2 == 0 else 0.43) * w, 0, fz + 0.9 + (i / 2) * (d - 1.2))
				content.add_child(t)
			for side in 4:
				for j in int(w if side % 2 == 0 else d):
					var sx := w if side % 2 == 0 else d
					var along := -sx * 0.5 + j + 0.5
					if side == 0 and abs(along) < 0.6:
						continue
					var fe := Models.fit("graveyard/iron-fence", Vector2(0.98, 0.08), 0, 3.0)
					match side:
						0: fe.position = Vector3(along, 0, -d * 0.49)
						1: fe.position = Vector3(w * 0.49, 0, along); fe.rotation.y = PI * 0.5
						2: fe.position = Vector3(along, 0, d * 0.49)
						3: fe.position = Vector3(-w * 0.49, 0, along); fe.rotation.y = PI * 0.5
					content.add_child(fe)
			h = 0.75
		"crematorium":
			_pad(content, b, Color("8f9c84"))
			Models.facade(Vector3(1.3, 0.45, 0.8), Color("b0a999"), Color("4e4a44"), 2.0, 39.0, Vector3(0, 0, fz + 0.6), content)
			Models.box(Vector3(1.34, 0.05, 0.84), Color("5d5850"), Vector3(0, 0.45, fz + 0.6), content)
			var chm := Models.fit("industrial/chimney-medium", Vector2(0.3, 0.3), 0, 1.5)
			chm.position = Vector3(0.45, 0, fz + 1.2)
			content.add_child(chm)
			var smc := Effects.smoke(5, 0.2)
			smc.position = chm.position + Vector3(0, chm.get_meta("height") + 0.05, 0)
			content.add_child(smc)
			for i in 3:
				var t := Models.fit("suburban/tree-large", Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3(-0.6 + i * 0.4, 0, fz + 1.55)
				content.add_child(t)
			h = 1.0
		"cargo":
			_pad(content, b, Color("7d7d7d"))
			var copts := ["industrial/shipping-container-a", "industrial/shipping-container-b", "industrial/shipping-container-c"]
			for i in 10:
				var ct := Models.fit(_pick(copts, rng), Vector2(0.5, 0.25), 0, 1.0)
				ct.position = Vector3(-w * 0.4 + (i % 5) * 0.32, (i / 5) * 0.16, fz + 1.2 + rng.randf_range(-0.05, 0.05))
				content.add_child(ct)
			# gantry crane
			for x in [-w * 0.45, w * 0.45]:
				Models.box(Vector3(0.05, 0.85, 0.05), Color("f9a825"), Vector3(x, 0, fz + 0.75), content)
				Models.box(Vector3(0.05, 0.85, 0.05), Color("f9a825"), Vector3(x, 0, fz + 1.6), content)
			Models.box(Vector3(w * 0.95, 0.07, 0.07), Color("f9a825"), Vector3(0, 0.85, fz + 0.75), content)
			Models.box(Vector3(w * 0.95, 0.07, 0.07), Color("f9a825"), Vector3(0, 0.85, fz + 1.6), content)
			Models.box(Vector3(0.25, 0.1, 0.95), Color("e65100"), Vector3(0.3, 0.8, fz + 1.18), content)
			for i in 3:
				var tr := Models.fit("cars/truck", Vector2(0.22, 0.45))
				tr.position = Vector3(-0.8 + i * 0.6, 0, fz + 0.25)
				tr.rotation.y = PI * 0.5
				content.add_child(tr)
			h = 0.95
		"rescue":
			_pad(content, b, Color("9a9a9a"))
			Models.facade(Vector3(1.5, 0.5, 1.0), Color("ff8f00"), Color("37474f"), 2.0, 16.0, Vector3(0, 0, fz + 0.9), content)
			Models.box(Vector3(1.54, 0.06, 0.12), Color("eceff1"), Vector3(0, 0.35, fz + 0.4), content)
			Models.cylinder(0.25, 0.02, Color("37474f"), Vector3(0.45, 0.5, fz + 1.0), content, 18)
			var heli := Models.box(Vector3(0.12, 0.08, 0.3), Color("d32f2f"), Vector3(0.45, 0.52, fz + 1.0), content)
			Models.box(Vector3(0.5, 0.008, 0.03), Color("222222"), Vector3(0.45, 0.62, fz + 1.0), content)
			for i in 2:
				var tr := Models.fit("cars/truck", Vector2(0.24, 0.48))
				tr.position = Vector3(-0.5 + i * 0.35, 0, fz + 0.15)
				content.add_child(tr)
			h = 0.65
		"busdepot":
			_pad(content, b, Color("8c8c8c"))
			Models.facade(Vector3(1.6, 0.45, 0.9), Color("e8e2d6"), Color("e67e22"), 2.0, 14.0, Vector3(0, 0, fz + 1.3), content)
			Models.box(Vector3(1.64, 0.05, 0.94), Color("e67e22"), Vector3(0, 0.45, fz + 1.3), content)
			for i in 3:
				Models.box(Vector3(0.38, 0.32, 0.02), Color("3a3a3a"), Vector3(-0.5 + i * 0.5, 0, fz + 0.84), content)
				var bus := _bus_prop(Color("fb8c00"))
				bus.position = Vector3(-0.5 + i * 0.5, 0, fz + 0.4)
				content.add_child(bus)
			h = 0.55
		"tramdepot":
			_pad(content, b, Color("8c8c8c"))
			Models.facade(Vector3(1.7, 0.5, 1.0), Color("e8d9c4"), Color("b71c1c"), 2.0, 40.0, Vector3(0, 0, fz + 1.2), content)
			var rf := Models.cylinder(0.5, 1.72, Color("8d6e63"), Vector3(0, 0.38, fz + 1.2), content, 3)
			rf.rotation.z = PI * 0.5
			rf.scale = Vector3(0.55, 1, 0.3)
			for i in 2:
				var tm: Node3D = preload("res://scripts/render/TransitRenderer.gd")._tram_model(Color("e53935"))
				tm.position = Vector3(-0.4 + i * 0.8, 0, fz + 0.4)
				content.add_child(tm)
			h = 0.7
		"metro":
			_pad(content, b, Color("bdbdbd"))
			Models.box(Vector3(0.7, 0.04, 0.5), Color("37474f"), Vector3(0, 0.3, fz + 0.5), content)
			Models.facade(Vector3(0.5, 0.3, 0.35), Color("eceff1"), Color("c62828"), 2.0, 15.0, Vector3(0, 0, fz + 0.55), content)
			Models.box(Vector3(0.3, 0.12, 0.02), Color("1f2a36"), Vector3(0, 0.0, fz + 0.37), content)
			Models.box(Vector3(0.03, 0.5, 0.03), Color("9e9e9e"), Vector3(0.3, 0, fz + 0.15), content)
			var sg := Models.cylinder(0.08, 0.02, Color("e53935"), Vector3(0.3, 0.5, fz + 0.15), content, 16)
			sg.rotation.x = PI * 0.5
			sg.material_override = Models.mat(Color("e53935"), 0.4, 0.8)
			h = 0.6
		"park":
			_pad(content, b, Color("5aa845"))
			Models.box(Vector3(0.9, 0.006, 0.12), Color("d9c9a3"), Vector3(0, 0.008, 0), content)
			Models.box(Vector3(0.12, 0.006, 0.9), Color("d9c9a3"), Vector3(0, 0.008, 0), content)
			var trees := ["nature/tree_oak", "nature/tree_default", "nature/tree_detailed", "nature/tree_fat"]
			for p in [Vector2(-0.28, -0.28), Vector2(0.28, 0.28), Vector2(0.28, -0.28)]:
				var t := Models.fit(trees[rng.randi() % trees.size()], Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3(p.x, 0, p.y)
				t.rotation.y = rng.randf() * TAU
				content.add_child(t)
			var bn := Models.fit("graveyard/bench", Vector2(0.22, 0.12), 0, 1.0)
			bn.position = Vector3(-0.28, 0, 0.22)
			content.add_child(bn)
			for i in 3:
				var f := Models.fit(["nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA"][i], Vector2(0.08, 0.08), 0, 1.0)
				f.position = Vector3(-0.38 + i * 0.07, 0, 0.36)
				content.add_child(f)
			h = 0.8
		"bigpark":
			_pad(content, b, Color("5aa845"))
			var pond := Models.cylinder(0.45, 0.01, Color("3f8fc0"), Vector3(0.2, 0.008, 0.2), content, 24)
			pond.material_override = Models.mat(Color("3f8fc0"), 0.1)
			Models.box(Vector3(1.9, 0.006, 0.1), Color("d9c9a3"), Vector3(0, 0.008, -0.55), content)
			Models.box(Vector3(0.1, 0.006, 1.9), Color("d9c9a3"), Vector3(-0.55, 0.008, 0), content)
			var trees := ["nature/tree_oak", "nature/tree_default", "nature/tree_detailed", "nature/tree_fat", "nature/tree_plateau", "nature/tree_pineRoundA"]
			for i in 9:
				var t := Models.fit(trees[rng.randi() % trees.size()], Vector2(0.32, 0.32), 0, 1.8)
				var a := rng.randf() * TAU
				t.position = Vector3(0.2 + cos(a) * rng.randf_range(0.6, 0.8), 0, 0.2 + sin(a) * rng.randf_range(0.6, 0.8))
				t.position = t.position.clamp(Vector3(-0.92, 0, -0.92), Vector3(0.92, 0, 0.92))
				t.rotation.y = rng.randf() * TAU
				content.add_child(t)
			for i in 5:
				var bu := Models.fit("nature/plant_bushDetailed" if i % 2 == 0 else "nature/plant_bush", Vector2(0.14, 0.14), 0, 1.0)
				bu.position = Vector3(-0.85 + i * 0.12, 0, 0.85)
				content.add_child(bu)
			for i in 2:
				var bn := Models.fit("graveyard/bench", Vector2(0.22, 0.12), 0, 1.0)
				bn.position = Vector3(-0.8 + i * 0.4, 0, -0.42)
				content.add_child(bn)
			h = 0.9
		"plaza":
			_pad(content, b, Color("cfc6b4"))
			Models.cylinder(0.45, 0.08, Color("bdb6a6"), Vector3(0, 0, 0), content, 24)
			var pool := Models.cylinder(0.4, 0.09, Color("4a9fd0"), Vector3(0, 0, 0), content, 24)
			pool.material_override = Models.mat(Color("4a9fd0"), 0.1)
			Models.cylinder(0.06, 0.35, Color("e0dbd0"), Vector3(0, 0.08, 0), content, 10)
			Models.cylinder(0.16, 0.03, Color("e0dbd0"), Vector3(0, 0.32, 0), content, 16)
			var ft := Effects.fountain()
			ft.position = Vector3(0, 0.4, 0)
			content.add_child(ft)
			for p in [Vector2(-0.75, -0.75), Vector2(0.75, -0.75), Vector2(-0.75, 0.75), Vector2(0.75, 0.75)]:
				var t := Models.fit("suburban/tree-large", Vector2(0.3, 0.3), 0, 1.8)
				t.position = Vector3(p.x, 0, p.y)
				content.add_child(t)
			for p in [Vector2(-0.6, 0.0), Vector2(0.6, 0.0)]:
				var ps := Models.fit("commercial/detail-parasol-b", Vector2(0.25, 0.25), 0, 1.0)
				ps.position = Vector3(p.x, 0, p.y)
				content.add_child(ps)
			h = 0.8
	return h
