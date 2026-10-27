extends Node3D
## Vehicles driving along the road network (right-hand traffic).

const MAX_CARS := 260
const LANE := 0.17
const CAR_FOOT := Vector2(0.17, 0.34)
const CARS := ["cars/sedan", "cars/sedan", "cars/suv", "cars/hatchback-sports", "cars/taxi", "cars/van", "cars/sedan-sports", "cars/suv-luxury"]
const TRUCKS := ["cars/delivery", "cars/truck", "cars/truck-flat", "cars/delivery-flat"]

class Car:
	var node: Node3D
	var pts := PackedVector3Array()
	var tiles := PackedInt32Array()   # tile index per point
	var i := 0
	var s := 0.0
	var speed := 1.0
	var wait := 0.0
	var ghost := 0.0
	var kind := "car"
	var target: Building = null
	var home: Building = null
	var pos := Vector3.ZERO
	var fwd := Vector3.FORWARD
	var wheels: Array = []
	var age := 0.0
	var last_tile := -1
	var seed := 0
	var from_b: Building
	var to_b: Building
	var purpose := ""
	var citizen := -1

var city: City
var cars: Array = []
var time_scale := 1.0
var _spawn_t := 0.0
var _service_t := 0.0
var rng := RandomNumberGenerator.new()
var peds                      # Pedestrians renderer (cars give way on zebra crossings)
var trains                    # Trains renderer (cars wait at closed level crossings)
var light_t := 0.0
var _light_state := Vector2i(-1, -1)
var junction := {}            # tile index -> true for signalised junctions
const CYCLE := 8.0


func setup(c: City) -> void:
	city = c
	city.dispatch.connect(_on_dispatch)
	city.roads_changed.connect(_on_roads_changed)
	rng.randomize()
	_rebuild_junctions()


func clear_all() -> void:
	for c in cars:
		c.node.queue_free()
	cars.clear()


func _rebuild_junctions() -> void:
	junction.clear()
	for i in city.n * city.n:
		if city.road[i] > 0 and city.road[i] < 3:
			if signalised(city, Vector2i(i % city.n, i / city.n)):
				junction[i] = true


## Traffic lights stand at four-way crossings and where an avenue meets other roads.
static func signalised(c: City, t: Vector2i) -> bool:
	var i := c.idx(t.x, t.y)
	if c.road[i] == 0 or c.road[i] == 3:
		return false
	var m := c.road_mask(t)
	if m == 15:
		return true
	if not m in [7, 11, 13, 14]:
		return false
	var avenues := 0
	for d in Defs.DIRS:
		if c.is_road(t + d) and c.road[c.idx(t.x + d.x, t.y + d.y)] == 2:
			avenues += 1
	return avenues >= 1 and avenues < 3


## Signal state for traffic travelling along an axis (0 = north-south): 0 green, 1 yellow, 2 red.
func signal_state(axis: int) -> int:
	var ph := fmod(light_t, CYCLE)
	if axis == 1:
		ph = fmod(ph + CYCLE * 0.5, CYCLE)
	if ph < CYCLE * 0.42:
		return 0
	if ph < CYCLE * 0.5:
		return 1
	return 2


func _on_roads_changed(_cells: Array) -> void:
	_rebuild_junctions()
	var keep: Array = []
	for c: Car in cars:
		var ok := true
		for k in range(c.i, c.tiles.size()):
			if city.road[c.tiles[k]] == 0:
				ok = false
				break
		if ok:
			keep.append(c)
		else:
			if c.kind == "fire" and c.target:
				c.target.fire_dispatched = false
			c.node.queue_free()
	cars = keep


func _process(delta: float) -> void:
	Prof.b("traffic")
	_process_inner(delta)
	Prof.e("traffic")


func _process_inner(delta: float) -> void:
	if city == null:
		return
	var dt := delta * time_scale
	light_t += dt
	var ls := Vector2i(signal_state(0), signal_state(1))
	if ls != _light_state:
		_light_state = ls
		Models.set_signals(ls.x, ls.y)
	if time_scale > 0.0:
		_spawn_logic(dt)
	_update_cars(dt, delta)


func _spawn_logic(dt: float) -> void:
	var target := clampi(int((city.population / 7 + city.jobs / 16 + 2) * (1.0 - city.transit_share) * (1.0 - city.walk_share)), 0, MAX_CARS)
	if city.population < 5:
		target = 0
	_spawn_t -= dt
	if cars.size() < target and _spawn_t <= 0.0:
		_spawn_t = 0.12
		_spawn_trip()
	_service_t -= dt
	if _service_t <= 0.0:
		_service_t = 3.0
		_service_trips()


func _spawn_trip() -> void:
	var r := rng.randf()
	var from: Building
	var to: Building
	var models: Array = CARS
	var oc := city.outside_comp
	var who = null
	if r < 0.55:
		from = city.random_building(["r"], -1)
		if from == null: return
		# commuters drive to their own workplace
		who = city.people.pick_traveller(from, true)
		if who and city.buildings.has(who.work):
			to = city.buildings[who.work]
		else:
			to = city.random_building(["c", "i"], city.road_comp[city.idx(from.access.x, from.access.y)])
	elif r < 0.75:
		from = city.random_building(["r"], -1)
		if from == null: return
		to = city.random_building(["c"], city.road_comp[city.idx(from.access.x, from.access.y)])
	elif r < 0.9:
		from = city.random_building(["i"], -1)
		if from == null or city.bpol(from, "truck_ban"): return
		to = city.random_building(["c"], city.road_comp[city.idx(from.access.x, from.access.y)])
		models = TRUCKS
	else:
		# traffic from / to the outside connection
		if oc < 0: return
		var b := city.random_building(["c", "i", "r"], oc)
		if b == null: return
		var p := _path(city.outside, b.access) if rng.randf() < 0.5 else _path(b.access, city.outside)
		if p.size() >= 2:
			var oc_car := _add_car(p, models[rng.randi() % models.size()] if b.kind() != "i" else TRUCKS[rng.randi() % TRUCKS.size()], "car", null)
			oc_car.to_b = b
			oc_car.purpose = "едет из соседнего города" if p[0] == Vector2(city.outside) else "уезжает за город"
		return
	if from == null or to == null or from == to:
		return
	var path := _path(from.access, to.access)
	if path.size() >= 2:
		var m: String = models[rng.randi() % models.size()]
		if r < 0.75 and from.zone == Defs.R_HIGH and rng.randf() < 0.15:
			m = "cars/taxi"
		var car := _add_car(path, m, "car", null)
		car.from_b = from
		car.to_b = to
		if who == null and from.kind() == "r":
			who = city.people.pick_traveller(from, false)
		if who:
			car.citizen = who.id
			car.seed = who.seed
		car.purpose = ["едет на работу", "едет за покупками", "везёт товары"][0 if r < 0.55 else (1 if r < 0.75 else 2)]


func _service_trips() -> void:
	for b: Building in city.buildings.values():
		if not b.is_service() or not b.has_road:
			continue
		var model := ""
		match b.type:
			"police": model = "cars/police"
			"clinic", "hospital": model = "cars/ambulance" if rng.randf() < 0.5 else ""
			"landfill", "recycling", "incinerator": model = "cars/garbage-truck" if not b.emptying and not b.is_full() else ""
			"cemetery", "crematorium": model = "cars/van" if rng.randf() < 0.5 and not b.is_full() else ""
			"cargo": model = "cars/truck" if rng.randf() < 0.5 else "cars/truck-flat"
		if model == "" or rng.randf() > 0.45:
			continue
		var to := city.random_building(["i"] if b.type == "cargo" else ["r", "c"], city.road_comp[city.idx(b.access.x, b.access.y)])
		if to == null:
			continue
		var p := _path(b.access, to.access)
		if p.size() >= 2:
			var car := _add_car(p, model, "service", null)
			match b.type:
				"cemetery", "crematorium":
					Models.set_material(car.node, Models.mat(Color("1b1b1f"), 0.25))
					car.purpose = "катафалк едет за усопшим"
				"cargo": car.purpose = "везёт груз на терминал"
				"landfill", "recycling", "incinerator": car.purpose = "собирает мусор"


func _on_dispatch(kind: String, from_b: Building, to_b: Building) -> void:
	if kind != "fire":
		return
	var p := _path(from_b.access, to_b.access)
	if p.size() < 1:
		to_b.fire_dispatched = false
		return
	if p.size() == 1:
		p.append(p[0])
	var c := _add_car(p, "cars/firetruck", "fire", to_b)
	c.home = from_b
	c.speed = 1.9
	var sp := AudioStreamPlayer3D.new()
	sp.stream = preload("res://scripts/render/AudioManager.gd").siren_stream
	sp.unit_size = 4.0
	sp.max_distance = 45.0
	sp.volume_db = linear_to_db(max(preload("res://scripts/render/AudioManager.gd").sfx_volume, 0.001)) - 6.0
	c.node.add_child(sp)
	if Sfx.enabled:
		sp.play()


func _path(a: Vector2i, b: Vector2i) -> PackedVector2Array:
	return city.find_path(a, b)


static func _right(d: Vector2) -> Vector3:
	return Vector3(-d.y, 0, d.x)


func _add_car(path: PackedVector2Array, model: String, kind: String, target: Building) -> Car:
	var c := Car.new()
	var lp := LanePath.build(path, LANE, city.n)
	c.pts = lp.pts
	c.tiles = lp.tiles
	c.kind = kind
	c.target = target
	c.seed = rng.randi()
	if kind == "fire":
		c.purpose = "мчится на пожар"
	elif kind == "service":
		c.purpose = "на служебном выезде"
	c.speed = rng.randf_range(0.9, 1.25)
	c.node = Models.fit(model, CAR_FOOT, 0, 1.0)
	c.pos = c.pts[0]
	c.node.position = c.pos + Vector3(0, city.height_at(c.pos.x, c.pos.z), 0)
	c.node.scale = Vector3.ONE * 0.01
	var d := c.pts[1] - c.pts[0]
	c.node.rotation.y = atan2(d.x, d.z)
	add_child(c.node)
	Models.set_cast_shadows(c.node, false)
	_add_lights(c.node)
	_set_range(c.node, 55.0)
	_find_wheels(c.node, c.wheels)
	cars.append(c)
	return c


## Stop line logic: red / yellow light ahead, or people on the zebra ahead.
func _must_stop(c: Car, ped_tiles: Dictionary) -> bool:
	var cur: int = c.tiles[mini(c.i, c.tiles.size() - 1)]
	var nxt := -1
	for k in range(c.i + 1, mini(c.i + 8, c.tiles.size())):
		if c.tiles[k] != cur:
			nxt = c.tiles[k]
			break
	if nxt < 0:
		return false
	var nc := Vector2(nxt % city.n + 0.5, nxt / city.n + 0.5)
	var to := nc - Vector2(c.pos.x, c.pos.z)
	var along: float = to.dot(Vector2(c.fwd.x, c.fwd.z)) - 0.5
	if along > 0.3 or along < 0.0:
		return false
	if ped_tiles.has(nxt) and not junction.has(nxt):
		return true
	if trains and trains.closed.has(nxt) and not trains.closed.has(cur):
		return true
	if junction.has(nxt) and not junction.has(cur):
		var axis := 0 if absf(c.fwd.z) > absf(c.fwd.x) else 1
		var st := signal_state(axis)
		# on yellow cars close to the line keep going
		return st == 2 or (st == 1 and along > 0.12)
	return false


func _honk(c: Car) -> void:
	var AM = preload("res://scripts/render/AudioManager.gd")
	if AM.horn_stream == null:
		return
	var hp := AudioStreamPlayer3D.new()
	hp.stream = AM.horn_stream
	hp.unit_size = 2.0
	hp.max_distance = 25.0
	hp.pitch_scale = rng.randf_range(0.85, 1.2)
	hp.volume_db = linear_to_db(max(AM.sfx_volume, 0.001)) - 8.0
	c.node.add_child(hp)
	hp.play()
	hp.finished.connect(hp.queue_free)


static var _light_mesh: BoxMesh


func _add_lights(n: Node3D) -> void:
	if _light_mesh == null:
		_light_mesh = BoxMesh.new()
		_light_mesh.size = Vector3(0.04, 0.025, 0.012)
	for side in [-1.0, 1.0]:
		var h := MeshInstance3D.new()
		h.mesh = _light_mesh
		h.material_override = Models.head_mat
		h.position = Vector3(side * 0.05, 0.05, 0.15)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(h)
		var t := MeshInstance3D.new()
		t.mesh = _light_mesh
		t.material_override = Models.tail_mat
		t.position = Vector3(side * 0.055, 0.055, -0.15)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(t)


static func _set_range(n: Node, r: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = r
	for ch in n.get_children():
		_set_range(ch, r)


func _find_wheels(n: Node, out: Array) -> void:
	if n.name.begins_with("wheel"):
		out.append(n)
	for ch in n.get_children():
		_find_wheels(ch, out)


func _update_cars(dt: float, real_dt: float) -> void:
	# spatial buckets by tile
	var buckets := {}
	for c: Car in cars:
		var ti := int(c.pos.z) * city.n + int(c.pos.x)
		if buckets.has(ti):
			buckets[ti].append(c)
		else:
			buckets[ti] = [c]
	# road tiles where pedestrians are crossing right now
	var ped_tiles := {}
	if peds:
		for p in peds.peds:
			if p.state == 0 and p.i < p.tiles.size():
				var pt: int = p.tiles[p.i]
				if pt >= 0 and city.road[pt] > 0:
					ped_tiles[pt] = true
	var done: Array = []
	for c: Car in cars:
		c.age += real_dt
		if c.age < 0.4:
			c.node.scale = Vector3.ONE * clamp(c.age / 0.3, 0.01, 1.0)
		if dt <= 0.0:
			continue
		var blocked := false
		if c.ghost > 0.0:
			c.ghost -= dt
		elif c.kind != "fire":
			var right := Vector3(-c.fwd.z, 0, c.fwd.x)
			var ahead := c.pos + c.fwd * 0.4
			var keys := [int(c.pos.z) * city.n + int(c.pos.x), int(ahead.z) * city.n + int(ahead.x)]
			if keys[0] == keys[1]:
				keys.pop_back()
			for k in keys:
				if not buckets.has(k):
					continue
				for o: Car in buckets[k]:
					if o == c:
						continue
					var rel := o.pos - c.pos
					var f := rel.dot(c.fwd)
					if f > 0.02 and f < 0.36 and abs(rel.dot(right)) < 0.11:
						blocked = true
						break
				if blocked:
					break
		if not blocked and c.kind != "fire":
			blocked = _must_stop(c, ped_tiles)
			if blocked:
				c.wait = 0.0
				continue
		if blocked:
			c.wait += dt
			if c.wait > 1.4 and rng.randf() < 0.004 and Sfx.enabled:
				_honk(c)
			if c.wait > 6.0:
				c.ghost = 0.8
				c.wait = 0.0
			continue
		c.wait = 0.0
		var rt: int = city.road[c.tiles[mini(c.i, c.tiles.size() - 1)]]
		var cg := city.congestion(c.tiles[mini(c.i, c.tiles.size() - 1)])
		var jam: float = 1.0 / (1.0 + max(0.0, cg - 0.6) * 0.9)
		var dist: float = jam * (0.75 if city.weather == "snow" else 1.0) * c.speed * dt * (Defs.ROAD_TYPES[rt].speed if rt > 0 else 1.0)
		while dist > 0.0 and c.i < c.pts.size() - 1:
			var a := c.pts[c.i]
			var b := c.pts[c.i + 1]
			var L := a.distance_to(b)
			var rem := L - c.s
			if dist < rem:
				c.s += dist
				dist = 0.0
			else:
				dist -= rem
				c.i += 1
				c.s = 0.0
		if c.i >= c.pts.size() - 1:
			done.append(c)
			continue
		var a2 := c.pts[c.i]
		var b2 := c.pts[c.i + 1]
		var seg := b2 - a2
		var L2 := seg.length()
		if L2 > 0.0001:
			c.fwd = seg / L2
			c.pos = a2 + c.fwd * c.s
		var hy := city.height_at(c.pos.x, c.pos.z)
		c.node.position = Vector3(c.pos.x, hy + 0.01, c.pos.z)
		var ahead_h := city.height_at(c.pos.x + c.fwd.x * 0.15, c.pos.z + c.fwd.z * 0.15)
		c.node.rotation.x = -atan2(ahead_h - hy, 0.15)
		var target_yaw := atan2(c.fwd.x, c.fwd.z)
		c.node.rotation.y = lerp_angle(c.node.rotation.y, target_yaw, clamp(dt * 10.0, 0.0, 1.0))
		for w in c.wheels:
			(w as Node3D).rotate_x(dt * 12.0)
		var ti2 := c.tiles[c.i]
		if ti2 != c.last_tile:
			c.last_tile = ti2
			city.add_traffic(ti2)
	for c: Car in done:
		cars.erase(c)
		if c.kind == "fire" and c.target:
			city.extinguish(c.target)
			if c.home and city.buildings.has(c.home.id):
				var p := _path(c.target.access, c.home.access)
				if p.size() >= 2:
					_add_car(p, "cars/firetruck", "service", null)
		var nd := c.node
		var tw := create_tween()
		tw.tween_property(nd, "scale", Vector3.ONE * 0.01, 0.25)
		tw.tween_callback(nd.queue_free)
