extends Node3D
## Trains on the railway: commuter trains between stations, long-distance and retro steam trains
## from the outside world, cargo trains with containers and coal. They come in from the map edge,
## stop at the platforms, reverse at dead-end stations and close the level crossings on their way.

const RailR := preload("res://scripts/render/RailRenderer.gd")

var city: City
var rails
var time_scale := 1.0
var trains: Array = []       # {cars, offs, pts, cum, s, v, stops: Array[float], wait, leg: Array, kind}
var closed := {}             # tile index -> true: crossings a train is close to
var _spawn_t := 3.0
var rng := RandomNumberGenerator.new()
const SPEED := 2.4
const LEAD := 7.0            # track continues this far beyond the map edge

# model, length axis is X (true) or Z, flip so the nose looks forward
const CARS := {
	"electric": ["train/train-electric-city-a", false, false],
	"diesel": ["train/train-diesel-a", false, false],
	"container_r": ["train/train-carriage-container-red", false, false],
	"container_b": ["train/train-carriage-container-blue", false, false],
	"express": ["poly/train_express", true, true],
	"express_car": ["poly/train_express_car", true, true],
	"coal": ["poly/train_coal", true, true],
	"steam": ["poly/train_steam", true, true],
	"retro_car": ["poly/train_retro_car", true, true],
}


func setup(c: City, r) -> void:
	city = c
	rails = r
	rng.randomize()
	city.rails_changed.connect(_clear)
	city.building_removed.connect(func(_b, _r): _clear())


func _clear() -> void:
	for t in trains:
		for car in t.cars:
			car.queue_free()
	trains.clear()


func _car(kind: String) -> Node3D:
	var d: Array = CARS[kind]
	var holder := Node3D.new()
	var ab: AABB = Models.aabb(d[0])
	var wdt: float = ab.size.z if d[1] else ab.size.x
	var m := Models.fit(d[0], Vector2(10, 10), 0, 0.3 / wdt)
	if d[1]:
		m.rotation.y = PI * 0.5 if not d[2] else -PI * 0.5
	elif d[2]:
		m.rotation.y = PI
	holder.add_child(m)
	var ln: float = (ab.size.x if d[1] else ab.size.z) * 0.3 / wdt
	holder.set_meta("len", ln)
	add_child(holder)
	return holder


# ------------------------------------------------------------------ routes
## Points of a route through tiles; exits at the ends are extended beyond the map edge.
func _route_points(tiles: Array[Vector2i], from_out: bool, to_out: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var nn := tiles.size()
	for k in nn:
		var t: Vector2i = tiles[k]
		var a := -1
		var b := -1
		if k > 0:
			a = Defs.DIRS.find(tiles[k - 1] - t)
		elif from_out:
			a = _edge_dir(t)
		if k < nn - 1:
			b = Defs.DIRS.find(tiles[k + 1] - t)
		elif to_out:
			b = _edge_dir(t)
		var cv := RailR.tile_curve(city, t, a, b, 5)
		for j in cv.size():
			if pts.size() > 0 and j == 0:
				continue
			pts.append(cv[j])
	if from_out:
		var d: Vector2 = Vector2(Defs.DIRS[_edge_dir(tiles[0])])
		var p0 := pts[0]
		pts.insert(0, p0 + Vector3(d.x, 0, d.y) * LEAD)
	if to_out:
		var d: Vector2 = Vector2(Defs.DIRS[_edge_dir(tiles[nn - 1])])
		var p1 := pts[pts.size() - 1]
		pts.append(p1 + Vector3(d.x, 0, d.y) * LEAD)
	return pts


func _edge_dir(t: Vector2i) -> int:
	if t.y == 0: return 0
	if t.x == city.n - 1: return 1
	if t.y == city.n - 1: return 2
	return 3


func _cum(pts: PackedVector3Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	return cum


## Distance along the points where the tile's centre is passed.
func _dist_at(pts: PackedVector3Array, cum: PackedFloat32Array, t: Vector2i) -> float:
	var c := Vector3(t.x + 0.5, 0, t.y + 0.5)
	var best := 1e9
	var at := 0.0
	for k in pts.size():
		var d := Vector2(pts[k].x - c.x, pts[k].z - c.z).length()
		if d < best:
			best = d
			at = cum[k]
	return at


func _length(t: Dictionary) -> float:
	return t.offs[t.offs.size() - 1] + t.cars[t.cars.size() - 1].get_meta("len") * 0.5


# ------------------------------------------------------------------ spawning
func _spawn() -> void:
	var cap := 2
	var cand: Array = []
	for type in ["train_station", "cargo_station"]:
		for b in city.rail_stations(type):
			var lk := city.station_link(b)
			if lk.platform.x < 0 or (not lk.out and lk.peers == 0):
				continue
			cand.append([b, lk])
			cap += 2
	if cand.is_empty() or trains.size() >= mini(cap, 8):
		return
	var pick: Array = cand[rng.randi() % cand.size()]
	var b: Building = pick[0]
	var lk: Dictionary = pick[1]
	var cargo := b.type == "cargo_station"
	var plat: Vector2i = lk.platform
	var exits := city.rail_exits(lk.comp)
	# stops: [start, platform, ..., end]; start/end are either exits or other stations
	var peers: Array[Vector2i] = []
	for o in city.rail_stations(b.type):
		if o != b:
			var q := city.station_platform(o)
			if q.x >= 0 and city.rail_comp[city.idx(q.x, q.y)] == lk.comp:
				peers.append(q)
	var start: Vector2i
	var end: Vector2i
	var from_out := false
	var to_out := false
	if exits.size() > 0 and (peers.is_empty() or rng.randf() < 0.55):
		start = exits[rng.randi() % exits.size()]
		from_out = true
		if peers.size() > 0 and rng.randf() < 0.5:
			end = peers[rng.randi() % peers.size()]
		else:
			end = exits[rng.randi() % exits.size()]
			to_out = true
	else:
		if peers.is_empty():
			return
		start = peers[rng.randi() % peers.size()]
		end = start
	var kinds: Array = []
	if cargo:
		kinds = ["diesel"]
		for k in rng.randi_range(3, 5):
			kinds.append(["container_r", "container_b", "coal"][rng.randi() % 3])
	elif from_out and rng.randf() < 0.2:
		kinds = ["steam", "retro_car", "retro_car"]
	elif from_out and rng.randf() < 0.5:
		kinds = ["express", "express_car", "express_car"]
	else:
		kinds = ["electric", "electric", "electric"]
	var t := {"cars": [], "offs": [], "s": 0.0, "v": SPEED * 0.6, "wait": 0.0, "kind": "cargo" if cargo else "pax",
		"legs": [plat, end], "to_out": to_out, "pts": PackedVector3Array(), "cum": PackedFloat32Array(), "stop": -1.0, "cur": start}
	var off := 0.0
	for k in kinds:
		var car := _car(k)
		var ln: float = car.get_meta("len")
		if t.cars.size() > 0:
			off += (t.cars[t.cars.size() - 1].get_meta("len") + ln) * 0.5 + 0.03
		t.cars.append(car)
		t.offs.append(off)
	var tiles := city.rail_route(start, plat)
	if tiles.size() < 2 and not from_out:
		_free(t)
		return
	t.pts = _route_points(tiles, from_out, false)
	t.cum = _cum(t.pts)
	# from outside the whole train starts beyond the edge; from a station it stands at the platform
	t.s = _length(t)
	t.stop = _stop_dist(t, plat)
	t.legs = [end]
	t.cur = plat
	trains.append(t)


func _stop_dist(t: Dictionary, plat: Vector2i) -> float:
	# the middle of the train stands at the platform
	return minf(_dist_at(t.pts, t.cum, plat) + _length(t) * 0.5, t.cum[t.cum.size() - 1])


func _free(t: Dictionary) -> void:
	for car in t.cars:
		car.queue_free()


## After a stop: the next leg either goes on through the station or back the way it came.
func _next_leg(t: Dictionary) -> bool:
	if t.legs.is_empty():
		return false
	var dest: Vector2i = t.legs.pop_front()
	var to_out: bool = t.legs.is_empty() and t.to_out
	var tiles := city.rail_route(t.cur, dest)
	if tiles.size() < 2:
		return false
	# which way does the train face: the tile just behind the head
	var head := _sample(t, t.s)
	var behind := _sample(t, t.s - 0.6)
	var fwd := Vector2(head.x - behind.x, head.z - behind.z)
	var step := Vector2(tiles[1] - tiles[0])
	var new_pts := _route_points(tiles, false, to_out)
	if fwd.dot(step) < 0.0:
		# reverse at a dead end: the last car becomes the head and the train drives back.
		# New leg starts at the platform centre; the old tail is (L - overshoot) along it.
		var dp := _dist_at(t.pts, t.cum, t.cur)
		var overshoot: float = t.s - dp
		t.cars.reverse()
		var off := 0.0
		var offs: Array = [0.0]
		for k in range(1, t.cars.size()):
			off += (t.cars[k - 1].get_meta("len") + t.cars[k].get_meta("len")) * 0.5 + 0.03
			offs.append(off)
		t.offs = offs
		t.pts = new_pts
		t.cum = _cum(new_pts)
		t.s = _length(t) - overshoot
	else:
		# go on: keep the stretch behind the head, then the new leg
		var back := _length(t) + 0.2
		var pts2 := PackedVector3Array()
		var steps := int(ceil(back / 0.1))
		for k in steps:
			pts2.append(_sample(t, t.s - back + k * 0.1))
		for k in new_pts.size():
			pts2.append(new_pts[k])
		t.pts = pts2
		t.cum = _cum(pts2)
		t.s = back
	t.cur = dest
	t.stop = -1.0 if to_out else _stop_dist(t, dest)
	t.wait = 0.0
	return true


func _sample(t: Dictionary, s: float) -> Vector3:
	var pts: PackedVector3Array = t.pts
	var cum: PackedFloat32Array = t.cum
	var n := pts.size()
	if s <= 0.0:
		var d := (pts[1] - pts[0]).normalized()
		return pts[0] + d * s
	if s >= cum[n - 1]:
		var d := (pts[n - 1] - pts[n - 2]).normalized()
		return pts[n - 1] + d * (s - cum[n - 1])
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var u := (s - cum[lo]) / maxf(cum[hi] - cum[lo], 0.0001)
	return pts[lo].lerp(pts[hi], u)


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if city == null:
		return
	var dt := delta * time_scale
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_spawn_t = rng.randf_range(5.0, 12.0)
		_spawn()
	closed.clear()
	var crs: Dictionary = rails.crossings if rails else {}
	for t in trains.duplicate():
		var end: float = t.cum[t.cum.size() - 1]
		if t.stop >= 0.0:
			var left: float = t.stop - t.s
			if left <= 0.02:
				t.v = 0.0
				t.wait += dt
				if t.wait > 4.0 and not _next_leg(t):
					t.stop = -1.0
			else:
				t.v = minf(move_toward(t.v, SPEED, dt * 0.8), maxf(0.25, left * 1.1))
		else:
			t.v = move_toward(t.v, SPEED, dt * 0.8)
		t.s = minf(t.s + t.v * dt, t.stop if t.stop >= 0.0 else 1e9)
		if t.stop < 0.0 and t.s - _length(t) > end - 0.5:
			_free(t)
			trains.erase(t)
			continue
		for k in t.cars.size():
			var s: float = t.s - t.offs[k]
			var car: Node3D = t.cars[k]
			var p := _sample(t, s)
			var q := _sample(t, s + 0.15)
			car.position = p
			car.visible = p.x > -2.0 and p.z > -2.0 and p.x < city.n + 2.0 and p.z < city.n + 2.0
			if q.distance_to(p) > 0.001:
				car.look_at(Vector3(q.x, p.y, q.z), Vector3.UP)
			if crs.size() > 0:
				var ti := Vector2i(int(floor(p.x)), int(floor(p.z)))
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var tt := ti + Vector2i(dx, dy)
						if city.inb(tt.x, tt.y):
							var ii := city.idx(tt.x, tt.y)
							if crs.has(ii):
								closed[ii] = true
	if rails:
		rails.closed = closed
