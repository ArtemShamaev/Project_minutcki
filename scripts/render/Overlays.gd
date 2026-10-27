extends Node3D
## Zone cells display and information overlays (heatmaps).

var city: City
var zone_img: Image
var zone_tex: ImageTexture
var zone_mat: ShaderMaterial
var own_img: Image
var own_tex: ImageTexture


func refresh_land() -> void:
	for y in City.LAND_N:
		for x in City.LAND_N:
			own_img.set_pixel(x, y, Color(float(city.owned[y * City.LAND_N + x]), 0, 0))
	own_tex.update(own_img)


func set_land_view(on: bool) -> void:
	zone_mat.set_shader_parameter("land_view", 1.0 if on else 0.0)
var data_img: Image
var data_tex: ImageTexture
var data_mi: MeshInstance3D
var mode := "none"
var show_area := false
var _zones_dirty := false
var _zt := 0.0
var dist_img: Image
var dist_tex: ImageTexture
var labels: Node3D


func setup(c: City) -> void:
	city = c
	city.zones_changed.connect(func(): _zones_dirty = true)
	city.roads_changed.connect(func(_c): _zones_dirty = true)
	city.building_added.connect(func(_b): _zones_dirty = true)
	city.building_removed.connect(func(_b, _r): _zones_dirty = true)
	var n := city.n
	zone_img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	zone_tex = ImageTexture.create_from_image(zone_img)
	data_img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	data_tex = ImageTexture.create_from_image(data_img)
	var zm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(n, n)
	pm.subdivide_width = n - 1
	pm.subdivide_depth = n - 1
	zm.mesh = pm
	zm.position = Vector3(n * 0.5, 0.012, n * 0.5)
	zone_mat = ShaderMaterial.new()
	zone_mat.shader = load("res://shaders/zones.gdshader")
	zone_mat.set_shader_parameter("zone_tex", zone_tex)
	zone_mat.set_shader_parameter("n", float(n))
	dist_img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	dist_tex = ImageTexture.create_from_image(dist_img)
	zone_mat.set_shader_parameter("district_tex", dist_tex)
	own_img = Image.create(City.LAND_N, City.LAND_N, false, Image.FORMAT_R8)
	own_tex = ImageTexture.create_from_image(own_img)
	zone_mat.set_shader_parameter("owned_tex", own_tex)
	zone_mat.set_shader_parameter("land_n", float(City.LAND_N))
	refresh_land()
	city.land_changed.connect(refresh_land)
	labels = Node3D.new()
	add_child(labels)
	city.districts_changed.connect(refresh_districts)
	zm.material_override = zone_mat
	zm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(zm)
	data_mi = MeshInstance3D.new()
	data_mi.mesh = pm
	data_mi.position = Vector3(n * 0.5, 0.06, n * 0.5)
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/overlay.gdshader")
	dm.set_shader_parameter("data_tex", data_tex)
	dm.render_priority = 2
	data_mi.material_override = dm
	data_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	data_mi.visible = false
	add_child(data_mi)
	city.day_passed.connect(func(): if mode != "none" and city.day % 2 == 0: refresh_data())


func _process(delta: float) -> void:
	_zt -= delta
	if _zones_dirty and _zt <= 0.0:
		_zt = 0.15
		_zones_dirty = false
		refresh_zones()


func set_district_fill(on: bool) -> void:
	zone_mat.set_shader_parameter("district_fill", 1.0 if on else 0.0)


func refresh_districts() -> void:
	var n := city.n
	var sums := {}
	for y in n:
		for x in n:
			var d := city.district[city.idx(x, y)]
			var c := Color(0, 0, 0, 0)
			if d > 0 and city.districts.has(d):
				c = city.districts[d].color
				c.a = 1.0
				var s: Vector3 = sums.get(d, Vector3.ZERO)
				sums[d] = s + Vector3(x + 0.5, y + 0.5, 1)
			dist_img.set_pixel(x, y, c)
	dist_tex.update(dist_img)
	for ch in labels.get_children():
		ch.queue_free()
	for d in sums:
		var s: Vector3 = sums[d]
		var p := Vector2(s.x / s.z, s.y / s.z)
		var l := Label3D.new()
		l.text = city.districts[d].name
		l.font_size = 30
		l.pixel_size = 0.0011
		l.outline_size = 8
		l.modulate = Color(1, 1, 1, 0.92)
		l.outline_modulate = Color(0, 0, 0, 0.6)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.position = Vector3(p.x, max(city.height_at(p.x, p.y), 0.0) + 2.5, p.y)
		labels.add_child(l)


func set_show_area(on: bool) -> void:
	show_area = on
	zone_mat.set_shader_parameter("show_area", 1.0 if on else 0.0)


func refresh_zones() -> void:
	var n := city.n
	for y in n:
		for x in n:
			var i := city.idx(x, y)
			var z := city.zone[i]
			var c := Color(0, 0, 0, 0)
			if city.bld[i] == -1 and city.road[i] == 0:
				if z != 0:
					c = Defs.ZONES[z].color
					c.a = 1.0
				elif city.terrain[i] == 0 and city.road_dist[i] >= 1 and city.road_dist[i] <= Defs.ZONE_DEPTH:
					c = Color(1, 1, 1, 0.4)
			zone_img.set_pixel(x, y, c)
	zone_tex.update(zone_img)


func set_mode(m: String) -> void:
	mode = m
	data_mi.visible = m != "none"
	if m != "none":
		refresh_data()


static func _heat(v: float) -> Color:
	# green (good) -> yellow -> red (bad)
	v = clamp(v, 0.0, 1.0)
	if v < 0.5:
		return Color(0.15, 0.8, 0.25).lerp(Color(1.0, 0.85, 0.1), v * 2.0)
	return Color(1.0, 0.85, 0.1).lerp(Color(0.95, 0.15, 0.1), (v - 0.5) * 2.0)


func refresh_data() -> void:
	var n := city.n
	var maxt := 1.0
	if mode == "traffic":
		for i in n * n:
			maxt = max(maxt, city.traffic[i])
		maxt = max(maxt, 20.0)
	for y in n:
		for x in n:
			var i := city.idx(x, y)
			var c := Color(0, 0, 0, 0)
			match mode:
				"power", "water", "sewage":
					var v: int = city.power[i] if mode == "power" else (city.water[i] if mode == "water" else city.sewage[i])
					if v == 1: c = Color(0.2, 0.85, 0.3, 0.8)
					elif v == 2: c = Color(0.95, 0.2, 0.15, 0.9)
					elif v == 3: c = {"power": Color(1.0, 0.85, 0.2, 0.75), "water": Color(0.3, 0.7, 1.0, 0.75), "sewage": Color(0.65, 0.45, 0.25, 0.8)}[mode]
					if mode == "sewage" and v == 3:
						# pipes coloured by load: light = free, red = overloaded (sewage overflows)
						var ld := city.sew_load[i]
						c = Color(0.55, 0.42, 0.3, 0.8).lerp(Color(0.95, 0.55, 0.1, 0.9), clampf(ld * 1.2, 0.0, 1.0))
						if city.sew_spill[i] > 0.0:
							c = Color(0.95, 0.12, 0.1, 0.95)
				"flood":
					var dd: float = city.water_sim.d[i] if city.water_sim else 0.0
					if dd > 0.012:
						c = Color(0.25, 0.55, 1.0, 0.35).lerp(Color(0.05, 0.15, 0.7, 0.9), clampf(dd / 0.6, 0.0, 1.0))
						if city.terrain[i] == 0:
							c = Color(0.95, 0.2, 0.15, clampf(0.4 + dd * 4.0, 0.0, 0.95))
				"waterpol":
					if city.terrain[i] == 1:
						var v := city.water_pol[i]
						c = Color(0.2, 0.6, 1.0, 0.55).lerp(Color(0.45, 0.3, 0.05, 0.95), clamp(v * 1.4, 0.0, 1.0))
					else:
						var bw := city.building_at(Vector2i(x, y))
						if bw and bw.type in ["pump", "tower"]:
							c = Color(0.95, 0.2, 0.15, 0.95) if city.pump_dirty(bw) > 0.25 else Color(0.2, 0.85, 0.3, 0.95)
						elif bw and Defs.SERVICES.get(bw.type, {}).has("wpol"):
							c = Color(0.55, 0.35, 0.1, 0.95)
				"resources":
					var r := city.resource[i]
					if r > 0:
						c = Defs.RESOURCES[r].color
						c.a = 0.75 if r <= 2 else 0.25 + 0.6 * city.res_amt[i]
				"landvalue":
					c = _heat(1.0 - city.land_value[i] / 80.0); c.a = 0.55
				"pollution":
					var v := city.pollution[i]
					c = Color(0.55, 0.35, 0.1, v * 0.9)
				"noise":
					var v := city.noise[i]
					c = Color(0.7, 0.3, 0.9, v * 0.9)
				"traffic":
					if city.road[i] > 0:
						c = _heat(city.congestion(i) / 1.3)
						c.a = 0.9
				"happiness":
					var b := city.building_at(Vector2i(x, y))
					if b and not b.is_service():
						c = _heat(1.0 - b.happiness / 100.0); c.a = 0.85
				_:
					if city.cov.has(mode):
						var v: float = city.cov[mode][i]
						c = Color(0.2, 0.6, 1.0, v * 0.75) if v > 0.01 else Color(0.9, 0.2, 0.15, 0.2 if city.bld[i] != -1 else 0.0)
			data_img.set_pixel(x, y, c)
	data_tex.update(data_img)
