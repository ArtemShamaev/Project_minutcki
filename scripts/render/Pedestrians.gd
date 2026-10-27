extends Node3D
## Pedestrians: citizens who walk instead of driving. Trips depend on the time of day
## (to work in the morning, home in the evening, shops and parks in between). Routes go
## over the walking network (pedestrian paths, sidewalks, parks), people wait at crossings
## until cars pass, sit on benches in parks and keep their own lane so crowds don't overlap.

const SIDE := 0.478           # sidewalk offset from the road centre
const MAX_PEDS := 150
const WALK_RANGE := 22        # max route length in tiles
const MODELS := ["man", "woman_casual", "woman_dress", "woman_tank"]
const HEIGHT := 0.13          # body height in world units (a floor is ~0.3)
const ANIM_DIST := 22.0       # animate only near the camera
const VIS_DIST := 30.0

enum { WALK, WAIT, SIT, STOP }

class Ped:
	var node: Node3D
	var anim: AnimationPlayer
	var pts := PackedVector3Array()
	var tiles := PackedInt32Array()
	var i := 0
	var s := 0.0
	var speed := 0.3
	var pos := Vector3.ZERO
	var fwd := Vector3.FORWARD
	var seed := 0
	var home: Building
	var dest: Building
	var purpose := ""
	var t := 0.0
	var state := WALK
	var timer := 0.0
	var lane := 0.0           # personal lateral offset
	var sit_at := -1          # point index where the person sits down (parks)
	var crossed := {}         # tiles where the person already waited
	var cur_anim := ""
	var citizen := -1        # People id of the person walking
	var line_id := -1        # waiting for a bus / tram of this line
	var stop_at := -1        # point index of the stop

var city: City
var traffic                   # Traffic renderer (cars to give way to)
var transit                   # TransitRenderer (buses / trams people board)
var peds: Array = []
var time_scale := 1.0
var rng := RandomNumberGenerator.new()
var _spawn_t := 0.0
var _scenes := {}
var _mat_cache := {}
var _cam_t := 0.0
var _cam_pos := Vector3.ZERO
const SHIRTS := [Color("c62828"), Color("1565c0"), Color("2e7d32"), Color("f9a825"), Color("6a1b9a"), Color("ef6c00"), Color("eceff1"),
	Color("37474f"), Color("00838f"), Color("ad1457"), Color("5d4037"), Color("9e9d24"), Color("283593"), Color("212121")]
const PANTS := [Color("263238"), Color("1a237e"), Color("3e2723"), Color("424242"), Color("546e7a"), Color("1b1b1b"), Color("6d4c41"), Color("0d47a1")]
const SKIN := [Color("f1c8a8"), Color("e0ac69"), Color("c68642"), Color("ffdbac"), Color("8d5524"), Color("d9a17c"), Color("a86b45")]
const HAIR := [Color("2b1b10"), Color("120c08"), Color("6b4423"), Color("c9a25d"), Color("8a8a8a"), Color("4a2a12"), Color("a0522d")]


func setup(c: City) -> void:
	city = c
	rng.randomize()
	for m in MODELS:
		_scenes[m] = load("res://assets/people/%s.glb" % m)
	city.roads_changed.connect(func(_c): _clear())
	city.paths_changed.connect(_clear)


func _clear() -> void:
	for p in peds:
		p.node.queue_free()
	peds.clear()


func _process(delta: float) -> void:
	Prof.b("peds")
	_process_inner(delta)
	Prof.e("peds")


## Share of the population on the streets at this time of day.
func _activity() -> float:
	var tod := fposmod(float(city.day) / Defs.DAY_CYCLE, 1.0)
	if tod < 0.2 or tod > 0.9:
		return 0.2
	return 0.65 + 0.35 * sin((tod - 0.2) / 0.7 * PI)


func _process_inner(delta: float) -> void:
	if city == null:
		return
	var dt := delta * time_scale
	_cam_t -= delta
	if _cam_t <= 0.0:
		_cam_t = 0.3
		var cam := get_viewport().get_camera_3d()
		if cam:
			_cam_pos = cam.global_position
		for p: Ped in peds:
			_update_lod(p)
	if dt <= 0.0:
		for p: Ped in peds:
			if p.anim and p.anim.is_playing():
				p.anim.pause()
		return
	var target := mini(int(city.population / 13 * _activity() * (0.5 + city.walk_share * 2.0)), MAX_PEDS)
	_spawn_t -= dt
	if peds.size() < target and _spawn_t <= 0.0:
		_spawn_t = 0.15
		_spawn()
	var done: Array = []
	for p: Ped in peds:
		p.t += dt
		match p.state:
			WAIT:
				p.timer -= dt
				if p.timer <= 0.0 and not _car_near(p):
					p.state = WALK
			STOP:
				# waiting at the stop: board the first bus / tram of the line that halts here
				p.timer -= dt
				if _bus_here(p) or p.timer <= 0.0:
					done.append(p)
					continue
			SIT:
				p.timer -= dt
				if p.timer <= 0.0:
					p.state = WALK
					p.sit_at = -1
			WALK:
				if _advance(p, p.speed * dt):
					done.append(p)
					continue
		_place(p)
	for p in done:
		peds.erase(p)
		p.node.queue_free()


## Moves along the polyline; returns true at the end of the route.
func _advance(p: Ped, dist: float) -> bool:
	while dist > 0.0 and p.i < p.pts.size() - 1:
		var a := p.pts[p.i]
		var b := p.pts[p.i + 1]
		var L := a.distance_to(b)
		var rem := L - p.s
		if dist < rem:
			p.s += dist
			dist = 0.0
		else:
			dist -= rem
			p.i += 1
			p.s = 0.0
			if _arrive_point(p):
				return false
	if p.i >= p.pts.size() - 1:
		return true
	var seg := p.pts[p.i + 1] - p.pts[p.i]
	if seg.length() > 0.0001:
		p.fwd = seg.normalized()
		p.pos = p.pts[p.i] + p.fwd * p.s
	return false


## Reaching a route point may make the person stop: bench in a park, kerb at a crossing.
func _arrive_point(p: Ped) -> bool:
	if p.i == p.stop_at:
		p.state = STOP
		p.timer = 45.0
		p.fwd = Vector3(-p.fwd.z, 0, p.fwd.x)
		return true
	if p.i == p.sit_at:
		p.state = SIT
		p.timer = rng.randf_range(4.0, 9.0)
		return true
	var ti: int = p.tiles[p.i] if p.i < p.tiles.size() else -1
	if ti < 0 or p.crossed.has(ti):
		return false
	if city.road[ti] > 0:
		var m := city.road_mask(Vector2i(ti % city.n, ti / city.n))
		var junction := m in [7, 11, 13, 14, 15]
		var zebra := city.path[ti] == 0 and _is_zebra(ti)
		if junction or zebra:
			p.crossed[ti] = true
			if zebra or rng.randf() < 0.45:
				p.state = WAIT
				p.timer = rng.randf_range(0.3, 1.2) if zebra else rng.randf_range(0.6, 1.8)
				return true
	return false


## A road tile next to a pedestrian path: walkers cross it on a zebra.
func _is_zebra(ti: int) -> bool:
	var t := Vector2i(ti % city.n, ti / city.n)
	for d in Defs.DIRS:
		if city.is_path(t + d):
			return true
	return false


func _bus_here(p: Ped) -> bool:
	if transit == null:
		return false
	for b in transit.buses:
		if b.line_id == p.line_id and b.wait > 0.0 and b.pos.distance_to(p.pos) < 0.9:
			return true
	return false


## A trip to the nearest bus / tram stop: the person waits there and rides away.
func _spawn_transit(from: Building) -> bool:
	if transit == null or city.lines.is_empty():
		return false
	var best_t := Vector2i(-1, -1)
	var best_l := -1
	var bd := 9.0
	for l in city.lines:
		if l.kind == "metro":
			continue
		for t in city.line_stop_tiles(l):
			var d := Vector2(t).distance_to(Vector2(from.access))
			if d < bd:
				bd = d
				best_t = t
				best_l = l.id
	if best_l < 0:
		return false
	var route := city.ped_route(city.door(from), best_t)
	if route.size() < 2:
		return false
	var p := Ped.new()
	p.home = from
	p.seed = rng.randi()
	p.purpose = "идёт на остановку"
	p.line_id = best_l
	var who = city.people.pick_traveller(from, false)
	if who:
		p.citizen = who.id
		p.seed = who.seed
	p.lane = rng.randf_range(-0.04, 0.04)
	p.speed = rng.randf_range(0.22, 0.32)
	if not _build_route(p, route, from, from):
		return false
	# stop at the kerb of the stop tile instead of entering a building
	p.pts.remove_at(p.pts.size() - 1)
	p.tiles.remove_at(p.tiles.size() - 1)
	p.stop_at = p.pts.size() - 1
	p.sit_at = -1
	p.node = _figure(p)
	p.pos = p.pts[0]
	p.fwd = (p.pts[1] - p.pts[0]).normalized() if p.pts.size() > 1 else Vector3.FORWARD
	add_child(p.node)
	if p.anim:
		p.anim.play(p.cur_anim)
		p.anim.seek(rng.randf() * 0.8, true)
	_place(p)
	_update_lod(p)
	peds.append(p)
	return true


func _car_near(p: Ped) -> bool:
	if traffic == null:
		return false
	for c in traffic.cars:
		if absf(c.pos.x - p.pos.x) < 0.9 and absf(c.pos.z - p.pos.z) < 0.9:
			return p.t < 60.0
	return false


func _place(p: Ped) -> void:
	var side := Vector3(-p.fwd.z, 0, p.fwd.x) * p.lane
	var q := p.pos + side
	p.node.position = Vector3(q.x, _ground(q, p), q.z)
	p.node.rotation.y = atan2(p.fwd.x, p.fwd.z) + (PI if p.state == SIT else 0.0)
	var want := "walk" if p.state == WALK else ("sit" if p.state == SIT else "idle")
	if p.state == STOP:
		p.purpose = "ждёт транспорт на остановке"
	if want != p.cur_anim and p.anim:
		p.cur_anim = want
		p.anim.play(want, 0.25)
	if p.anim:
		p.anim.speed_scale = (p.speed / 0.3 * 1.15 if p.state == WALK else 1.0) * time_scale


func _ground(q: Vector3, p: Ped) -> float:
	var ti: int = p.tiles[mini(p.i, p.tiles.size() - 1)] if p.tiles.size() > 0 else -1
	if ti >= 0 and city.path[ti] > 0 and city.terrain[ti] == 1:
		return WaterSim.SEA + 0.165
	if ti >= 0 and city.road[ti] > 0 and city.terrain[ti] == 1:
		return city.height_at(q.x, q.z) + 0.22
	return city.height_at(q.x, q.z) + (0.058 if ti >= 0 and city.road[ti] > 0 else 0.025)


func _update_lod(p: Ped) -> void:
	var d := _cam_pos.distance_to(p.node.position)
	if p.anim:
		if d < ANIM_DIST:
			if not p.anim.is_playing():
				p.anim.play(p.cur_anim if p.cur_anim != "" else "walk")
		elif p.anim.is_playing():
			# apply the current pose before freezing, so far-away people never stand in a T-pose
			p.anim.seek(p.anim.current_animation_position, true)
			p.anim.pause()


# ---------------------------------------------------------------- trips
func _spawn() -> void:
	var tod := fposmod(float(city.day) / Defs.DAY_CYCLE, 1.0)
	var from: Building = null
	var best: Building = null
	var purpose := ""
	var pre_citizen := -1
	var r := rng.randf()
	if tod > 0.62 and tod < 0.85 and r < 0.5:
		# evening: from work back home
		from = city.random_building(["c", "i"], -1)
		if from:
			best = _near(from, ["r"], 14.0)
			purpose = "возвращается домой с работы"
	else:
		from = city.random_building(["r"], -1)
		if from == null:
			return
		if r > 0.85 and _spawn_transit(from):
			return
		if tod > 0.22 and tod < 0.42 and r < 0.6:
			# a real resident walks to their own job if it is close enough
			var w = city.people.pick_traveller(from, true)
			if w and city.buildings.has(w.work) and Vector2(city.buildings[w.work].access).distance_to(Vector2(from.access)) < 16.0:
				best = city.buildings[w.work]
				purpose = "идёт на работу"
				pre_citizen = w.id
		elif r < 0.75:
			best = _near_park(from)
			purpose = "гуляет в парке"
		if best == null:
			best = _near(from, ["c"], 12.0)
			purpose = "идёт в магазин"
		if best == null:
			best = _near(from, ["r"], 8.0)
			purpose = "идёт в гости"
	if from == null or best == null:
		return
	var a := city.door(from)
	var b := city.door(best)
	var route := city.ped_route(a, b)
	if route.size() < 2 or route.size() > WALK_RANGE * 1.6:
		return
	var p := Ped.new()
	p.home = from
	p.dest = best
	p.seed = rng.randi()
	p.purpose = purpose
	if pre_citizen >= 0:
		p.citizen = pre_citizen
	elif from.kind() == "r":
		var who = city.people.pick_traveller(from, false)
		if who:
			p.citizen = who.id
	if p.citizen >= 0:
		p.seed = city.people.get_person(p.citizen).seed
	p.lane = rng.randf_range(-0.06, 0.06)
	p.speed = rng.randf_range(0.2, 0.32)
	if not _build_route(p, route, from, best):
		return
	p.node = _figure(p)
	p.pos = p.pts[0]
	p.fwd = (p.pts[1] - p.pts[0]).normalized() if p.pts.size() > 1 else Vector3.FORWARD
	add_child(p.node)
	if p.anim:
		p.anim.play(p.cur_anim)
		p.anim.seek(rng.randf() * 0.8, true)
	_place(p)
	_update_lod(p)
	peds.append(p)


func _near(from: Building, kinds: Array, maxd: float) -> Building:
	for k in 8:
		var cand := city.random_building(kinds, -1)
		if cand and cand != from and Vector2(cand.access).distance_to(Vector2(from.access)) < maxd:
			return cand
	return null


func _near_park(from: Building) -> Building:
	var best: Building = null
	var bd := 16.0
	for b: Building in city.buildings.values():
		if b.type in City.PARK_WALK:
			var d := Vector2(b.access).distance_to(Vector2(from.access))
			if d < bd:
				bd = d
				best = b
	return best


## Converts a tile route into a walking line: sidewalks along roads (on the person's
## right), the middle of paths and parks, from the building's door to the destination's.
func _build_route(p: Ped, route: PackedVector2Array, from: Building, to: Building) -> bool:
	var runs: Array = []
	var cur := PackedVector2Array()
	var cur_road := false
	for k in route.size():
		var t := Vector2i(route[k])
		var ti := city.idx(t.x, t.y)
		var on_road: bool = city.road[ti] > 0 and city.path[ti] == 0
		if k > 0 and on_road != cur_road:
			runs.append([cur, cur_road])
			cur = PackedVector2Array()
		cur_road = on_road
		cur.append(route[k])
	runs.append([cur, cur_road])
	var pts := PackedVector3Array()
	var tiles := PackedInt32Array()
	pts.append(_edge_point(from, Vector2i(route[0])))
	tiles.append(-1)
	for run in runs:
		var tp: PackedVector2Array = run[0]
		var on_road: bool = run[1]
		if tp.size() == 1:
			pts.append(Vector3(tp[0].x + 0.5, 0, tp[0].y + 0.5))
			tiles.append(city.idx(int(tp[0].x), int(tp[0].y)))
			continue
		var lp: Dictionary = LanePath.build(tp, SIDE if on_road else 0.0, city.n, 0.0, 0.0)
		var lpts: PackedVector3Array = lp.pts
		var ltiles: PackedInt32Array = lp.tiles
		pts.append_array(lpts)
		tiles.append_array(ltiles)
	# park visit: stroll to a spot inside the park and sit down on a bench
	if to.type in City.PARK_WALK:
		var c := to.center()
		var spot := Vector3(c.x + rng.randf_range(-0.3, 0.3) * to.sx, 0, c.z + rng.randf_range(-0.3, 0.3) * to.sy)
		pts.append(spot)
		tiles.append(city.idx(clampi(int(spot.x), 0, city.n - 1), clampi(int(spot.z), 0, city.n - 1)))
		p.sit_at = pts.size() - 1
		var spot2 := Vector3(c.x + rng.randf_range(-0.35, 0.35) * to.sx, 0, c.z + rng.randf_range(-0.35, 0.35) * to.sy)
		pts.append(spot2)
		tiles.append(tiles[tiles.size() - 1])
	else:
		pts.append(_edge_point(to, Vector2i(route[route.size() - 1])))
		tiles.append(-1)
	if pts.size() < 2:
		return false
	p.pts = pts
	p.tiles = tiles
	return true


## Point on the edge of a lot facing the door tile (where people step out of the building).
func _edge_point(b: Building, door: Vector2i) -> Vector3:
	var c := b.center()
	var dvec := Vector2(door.x + 0.5 - c.x, door.y + 0.5 - c.z)
	var hx := b.sx * 0.5 - 0.08
	var hz := b.sy * 0.5 - 0.08
	var k := minf(hx / maxf(absf(dvec.x), 0.001), hz / maxf(absf(dvec.y), 0.001))
	k = minf(k, 1.0)
	return Vector3(c.x + dvec.x * k, 0, c.z + dvec.y * k)


func _figure(p: Ped) -> Node3D:
	var model: String = MODELS[p.seed % MODELS.size()]
	var inst: Node3D = _scenes[model].instantiate()
	var root := Node3D.new()
	root.add_child(inst)
	var k := HEIGHT / 5.7
	inst.scale = Vector3.ONE * k
	var r := RandomNumberGenerator.new()
	r.seed = p.seed
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent() is Skeleton3D:
			mi.material_override = _mat(model, mi)
			mi.set_instance_shader_parameter("skin_col", SKIN[r.randi() % SKIN.size()])
			mi.set_instance_shader_parameter("shirt_col", SHIRTS[r.randi() % SHIRTS.size()])
			mi.set_instance_shader_parameter("pants_col", PANTS[r.randi() % PANTS.size()])
			mi.set_instance_shader_parameter("hair_col", HAIR[r.randi() % HAIR.size()])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = VIS_DIST
		else:
			mi.visible = false
	p.anim = inst.find_child("AnimationPlayer", true, false)
	if p.anim:
		for a in ["walk", "idle"]:
			if p.anim.has_animation(a):
				p.anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		p.anim.play("walk")
		p.anim.seek(r.randf() * 0.8, true)
		p.cur_anim = "walk"
	return root


func _mat(model: String, mi: MeshInstance3D) -> ShaderMaterial:
	if _mat_cache.has(model):
		return _mat_cache[model]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ped.gdshader")
	var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
	if src and src.albedo_texture:
		m.set_shader_parameter("palette", src.albedo_texture)
	_mat_cache[model] = m
	return m
