class_name City
extends RefCounted
## City state and simulation: grid, roads, zones, buildings, utilities,
## services coverage, pollution, land value, demand, growth and economy.

signal roads_changed(cells: Array)
signal zones_changed
signal trees_changed
signal building_added(b: Building)
signal building_removed(b: Building, reason: String)
signal building_updated(b: Building)
signal notify(text: String, kind: String)
signal milestone_reached(index: int)
signal dispatch(kind: String, from_b: Building, to_b: Building)
signal day_passed
signal terrain_changed(rect: Rect2i)
signal lines_changed
signal districts_changed
signal month_ended
signal quest_done(q: Dictionary)
signal paths_changed
signal rails_changed
signal land_changed
signal achievement_unlocked(id: String)

var n := Defs.N
var seed := 0
var rng := RandomNumberGenerator.new()

# --- grid layers (index = y * n + x) ---
var terrain := PackedByteArray()     # 0 land, 1 water
var height := PackedFloat32Array()   # corner heights, (n+1)*(n+1)
var road := PackedByteArray()        # 0 none, 1 street, 2 avenue, 3 highway
var zone := PackedByteArray()        # Defs zone enum
var bld := PackedInt32Array()        # building id or -1
var tree := PackedByteArray()        # 0/1
var path := PackedByteArray()        # 1 = pedestrian path
var owned := PackedByteArray()       # land plots (LAND_N x LAND_N): 1 = bought
const LAND := 24                     # plot size in tiles
const LAND_N := 5
var road_dist := PackedByteArray()   # distance to nearest road over land (255 = far)
var road_comp := PackedInt32Array()  # connected component of road tiles (-1)
var water_near := PackedFloat32Array()  # 0..1 proximity to water (static)
var power := PackedByteArray()       # 1 if powered (overlay)
var water := PackedByteArray()       # 1 if water supplied (overlay)
var cov := {}                        # cover name -> PackedFloat32Array
var pollution := PackedFloat32Array()
var noise := PackedFloat32Array()
var land_value := PackedFloat32Array()
var traffic := PackedFloat32Array()
var sewage := PackedByteArray()      # 1 served, 2 not served, 3 network (overlay)
var water_pol := PackedFloat32Array()  # 0..1 pollution of water tiles
var resource := PackedByteArray()    # Defs.RESOURCES key (0 none)
var res_amt := PackedFloat32Array()  # remaining amount of ore / oil (0..1)
var cov_src := {}                    # cover name -> PackedInt32Array (id of the service giving the coverage)

var buildings := {}                  # id -> Building
var next_id := 1
var outside := Vector2i(0, 0)        # outside connection tile (map edge)
var outside_comp := -1
var astar := AStar2D.new()

# --- economy / stats ---
var money := Defs.START_MONEY
var city_name := "Новоградск"
var map_type := "river"
var difficulty := 1
var sandbox := false
var day := 0
var taxes := {"r": 9, "c": 9, "i": 9, "o": 9}
var demand := {"r": 60.0, "c": 25.0, "i": 45.0}
var population := 0
var working_pop := 0
var jobs := 0
var employed := 0
var unemployment := 0.0
var avg_happiness := 60.0
var power_supply := 0.0
var power_demand := 0.0
var water_supply := 0.0
var water_demand := 0.0
var income_month := {}               # accumulated current month
var last_month := {"income": {}, "expense": {}, "total_in": 0.0, "total_out": 0.0}
var projected := {"income": 0.0, "expense": 0.0}
var history: Array = []              # monthly snapshots
var milestone := 0
var road_count := 0

var district := PackedByteArray()    # district id per tile (0 none)
var districts := {}                  # id -> {name, color, policies: Array}
var next_district := 1
var city_policies: Array = []
var lines: Array = []                # public transport lines
var next_line_id := 1
var transit_riders := 0
var transit_share := 0.0
var transit_income := 0.0
var events: Array = []               # newsworthy events of the current month
var quests_done: Array = []
var loans: Array = []                # {left: months, pay: per month, amount}
var weather := "clear"               # clear, rain, snow
var weather_days := 0
var snow_cover := 0.0
var random_disasters := 1          # 0 off, 1 rare, 2 frequent
var casualties := 0
var budget := {"power": 100, "water": 100, "safety": 100, "health": 100, "edu": 100, "park": 100, "transport": 100}
var auto_demolish := false
var city_style := "modern"            # default architecture style (districts may override)
var sewage_supply := 0.0
var sewage_demand := 0.0
var dirty_comp := {}                 # road component -> share of polluted drinking water
var goods := {"prod": 0.0, "need": 0.0, "raw_prod": 0.0, "raw_need": 0.0, "export_cap": 0.0, "import": 0.0, "sell": 1.0}
var edu_level := 0.0                 # population-weighted education coverage
var deaths_month := 0
var deaths_last := 0
var _death_acc := 0.0
var water_sim: WaterSim               # shallow-water physics (rivers, lakes, floods)
var people := People.new()            # individual citizens (names, ages, families, jobs)
var region := Region.new()            # neighbouring towns: trade deals, commuters, news
var rail := PackedByteArray()          # railway track tiles
var rail_comp := PackedInt32Array()     # connected track networks
var rail_out: Array = []                # network -> touches the map edge (outside world)
var _rail_dirty := true
var rail_stats := {"riders": 0.0, "income": 0.0, "tourism": 0.0}
const RAIL_COST := 60
const RAIL_BRIDGE_COST := 400
const RAIL_UNLOCK := 1000
const STATION_RADIUS := 22.0
var space := Space.new()              # space program (DSA)
var subsidies := {}                   # subsidy id -> level 0..2
var achievements := {}                # achievement id -> day unlocked
var mansion_awarded := false
var water_driven := false             # true when the renderer advances the water every frame
var flood_surge := 0.0                # extra level on rivers / sea during a flood disaster
var sew_load := PackedFloat32Array()  # sewer load / capacity per road tile
var sew_spill := PackedFloat32Array() # sewage overflowing from pipes per road tile
var sew_overflow := 0.0               # total sewage spilled from overloaded pipes
var flooded_count := 0
var ped_astar := AStar2D.new()        # walking network: sidewalks, pedestrian paths, parks
var _ped_dirty := true
var walk_trips := 0                   # trips made on foot this month (instead of by car)
var walk_share := 0.0
var path_near := PackedFloat32Array() # 0..1 how close pedestrian paths are
var _walk_acc := Vector2.ZERO
var _garbage_out := 0.0
const PATH_COST := 4
const PARK_WALK := ["park", "bigpark", "plaza", "playground", "sports"]
const SEWER_CAP := [0.0, 520.0, 1300.0, 2600.0]   # pipe capacity per road type
var _cov_dirty := true
var _roads_dirty := true
var _notify_last := {}


func _init() -> void:
	_alloc()
	terrain_changed.connect(func(r: Rect2i):
		if water_sim:
			water_sim.update_ground(self, r.grow(1)))


func _init_people() -> void:
	people = People.new()
	people.setup(self)


func _init_water() -> void:
	water_sim = WaterSim.new()
	water_sim.setup(self)


func _alloc() -> void:
	var c := n * n
	terrain.resize(c); terrain.fill(0)
	district.resize(c); district.fill(0)
	height.resize((n + 1) * (n + 1)); height.fill(0)
	road.resize(c); road.fill(0)
	zone.resize(c); zone.fill(0)
	bld.resize(c); bld.fill(-1)
	tree.resize(c); tree.fill(0)
	path.resize(c); path.fill(0)
	rail.resize(c); rail.fill(0)
	_rail_dirty = true
	owned.resize(LAND_N * LAND_N); owned.fill(1)
	path_near.resize(c); path_near.fill(0)
	road_dist.resize(c); road_dist.fill(255)
	road_comp.resize(c); road_comp.fill(-1)
	water_near.resize(c); water_near.fill(0)
	power.resize(c); power.fill(0)
	water.resize(c); water.fill(0)
	pollution.resize(c); pollution.fill(0)
	noise.resize(c); noise.fill(0)
	land_value.resize(c); land_value.fill(30)
	traffic.resize(c); traffic.fill(0)
	sewage.resize(c); sewage.fill(0)
	water_pol.resize(c); water_pol.fill(0)
	sew_load.resize(c); sew_load.fill(0)
	sew_spill.resize(c); sew_spill.fill(0)
	resource.resize(c); resource.fill(0)
	res_amt.resize(c); res_amt.fill(0)
	for k in Defs.COVERS:
		var a := PackedFloat32Array(); a.resize(c); a.fill(0)
		cov[k] = a
		var src := PackedInt32Array(); src.resize(c); src.fill(-1)
		cov_src[k] = src
	var tr := PackedFloat32Array(); tr.resize(c); tr.fill(0)
	cov["transit"] = tr


# ------------------------------------------------------------------ helpers
func idx(x: int, y: int) -> int:
	return y * n + x


func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < n and y < n


func is_road(p: Vector2i) -> bool:
	return inb(p.x, p.y) and road[idx(p.x, p.y)] > 0


## Street or avenue: roads buildings can be accessed from.
func is_local_road(p: Vector2i) -> bool:
	return inb(p.x, p.y) and (road[idx(p.x, p.y)] == 1 or road[idx(p.x, p.y)] == 2)


func is_water(p: Vector2i) -> bool:
	return inb(p.x, p.y) and terrain[idx(p.x, p.y)] == 1


func building_at(p: Vector2i) -> Building:
	if not inb(p.x, p.y):
		return null
	var id := bld[idx(p.x, p.y)]
	return buildings.get(id) if id >= 0 else null


func road_mask(p: Vector2i) -> int:
	var m := 0
	for d in 4:
		if is_road(p + Defs.DIRS[d]):
			m |= 1 << d
	if p == outside:
		# the outside connection continues off the map
		if p.x == 0: m |= 8
		elif p.x == n - 1: m |= 2
		elif p.y == 0: m |= 1
		else: m |= 4
	return m


# ------------------------------------------------------------------ generation
func generate(new_seed: int, mtype: String = "river") -> void:
	seed = new_seed
	map_type = mtype
	rng.seed = new_seed
	_alloc()
	var nr := FastNoiseLite.new()
	nr.seed = new_seed
	nr.frequency = 0.012
	var nt := FastNoiseLite.new()
	nt.seed = new_seed + 7
	nt.frequency = 0.045
	nt.fractal_octaves = 3
	var nl := FastNoiseLite.new()
	nl.seed = new_seed + 13
	nl.frequency = 0.08

	if mtype in ["river", "mountains"]:
		# river running north-south on the east side
		var wk := 0.7 if mtype == "mountains" else 1.0
		for y in n:
			var cx := n * 0.72 + nr.get_noise_1d(y * 1.3) * n * 0.16
			var wdt := (2.6 + (nr.get_noise_1d(y * 2.0 + 500.0) + 1.0) * 1.3) * wk
			for x in n:
				if abs(x + 0.5 - cx) < wdt:
					terrain[idx(x, y)] = 1
	if mtype == "coast":
		# open sea along the east edge with an irregular coastline
		for y in n:
			var cx := n * 0.74 + nr.get_noise_1d(y * 0.9) * n * 0.1
			for x in n:
				if x + 0.5 > cx:
					terrain[idx(x, y)] = 1
		# a small river flowing into the sea
		for x in range(int(n * 0.45), n):
			var cy := n * 0.22 + nr.get_noise_1d(x * 1.7 + 300.0) * 6.0
			for y in n:
				if abs(y + 0.5 - cy) < 1.6:
					terrain[idx(x, y)] = 1
	var lakes: Array = [[Vector2(n * 0.3, n * 0.3), 7.5]]
	if mtype == "lakes":
		lakes = []
		var lr := RandomNumberGenerator.new()
		lr.seed = new_seed + 99
		var tries := 0
		while lakes.size() < 7 and tries < 200:
			tries += 1
			var c := Vector2(lr.randf_range(10, n - 10), lr.randf_range(10, n - 10))
			if c.distance_to(Vector2(10, n / 2)) < 28:
				continue
			lakes.append([c, lr.randf_range(4.0, 9.0)])
	for lk in lakes:
		var lc: Vector2 = lk[0]
		for y in n:
			for x in n:
				var dd := Vector2(x, y).distance_to(lc) + nl.get_noise_2d(x, y) * 4.0
				if dd < lk[1]:
					terrain[idx(x, y)] = 1

	# outside connection: a road entering from the west edge
	outside = Vector2i(0, n / 2)
	# keep entrance area dry
	for y in range(n / 2 - 3, n / 2 + 4):
		for x in range(0, 20):
			terrain[idx(x, y)] = 0

	# forests
	for y in n:
		for x in n:
			var i := idx(x, y)
			if terrain[i] == 1:
				continue
			var f := nt.get_noise_2d(x, y)
			if (f > 0.18 and rng.randf() < 0.85) or rng.randf() < 0.025:
				tree[i] = 1

	_generate_heights(new_seed)
	_compute_water_near()
	_generate_resources(new_seed)

	var cells: Array[Vector2i] = []
	for x in range(0, 16):
		cells.append(Vector2i(x, n / 2))
	for c in cells:
		_set_road(c, true, 3 if c.x < 9 else 1)
		for dy in range(-1, 2):
			if inb(c.x, c.y + dy):
				tree[idx(c.x, c.y + dy)] = 0
	_recompute_roads()
	_init_water()
	_init_people()
	# the city starts on two plots at the highway entrance (as in C:S)
	owned.fill(0)
	owned[land_of(outside.x, outside.y)] = 1
	owned[land_of(outside.x + LAND, outside.y)] = 1
	region.generate(self)
	money = Defs.START_MONEY
	day = 0
	_cov_dirty = true


## Natural resources: fertile soil near water, forests, ore in the hills, oil fields on plains.
func _generate_resources(sd: int) -> void:
	resource.fill(0)
	res_amt.fill(0)
	var no := FastNoiseLite.new()
	no.seed = sd + 303
	no.frequency = 0.05
	var nf := FastNoiseLite.new()
	nf.seed = sd + 404
	nf.frequency = 0.035
	var nfo := FastNoiseLite.new()
	nfo.seed = sd + 7
	nfo.frequency = 0.045
	nfo.fractal_octaves = 3
	var start := Vector2(8, n / 2)
	for y in n:
		for x in n:
			var i := idx(x, y)
			if terrain[i] == 1:
				continue
			var h := tile_h(x, y)
			var far := Vector2(x, y).distance_to(start) > 14.0
			var ov := no.get_noise_2d(x, y)
			var fv := nf.get_noise_2d(x, y)
			if far and h > 2.2 and ov > 0.1:
				resource[i] = 3
				res_amt[i] = 1.0
			elif far and h < 1.2 and ov < -0.42:
				resource[i] = 4
				res_amt[i] = 1.0
			elif h < 1.5 and (water_near[i] > 0.15 or fv > 0.3) and fv > -0.15:
				resource[i] = 1
			elif nfo.get_noise_2d(x, y) > 0.22:
				resource[i] = 2


func _compute_water_near(r: Rect2i = Rect2i(0, 0, 0, 0)) -> void:
	# distance-based proximity to water within 5 tiles
	if r.size == Vector2i.ZERO:
		r = Rect2i(0, 0, n, n)
	r = r.intersection(Rect2i(0, 0, n, n))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var best := 99.0
			for dy in range(-5, 6):
				for dx in range(-5, 6):
					var px := x + dx
					var py := y + dy
					if inb(px, py) and terrain[idx(px, py)] == 1:
						best = min(best, sqrt(dx * dx + dy * dy))
			water_near[idx(x, y)] = clamp(1.0 - best / 6.0, 0.0, 1.0) if terrain[idx(x, y)] == 0 else 0.0


# ------------------------------------------------------------------ heights
func hc(x: int, y: int) -> float:
	return height[clampi(y, 0, n) * (n + 1) + clampi(x, 0, n)]


func _set_hc(x: int, y: int, v: float) -> void:
	height[y * (n + 1) + x] = v


func tile_h(x: int, y: int) -> float:
	return (hc(x, y) + hc(x + 1, y) + hc(x, y + 1) + hc(x + 1, y + 1)) * 0.25


func tile_range(x: int, y: int) -> float:
	var a := hc(x, y); var b := hc(x + 1, y); var c := hc(x, y + 1); var d := hc(x + 1, y + 1)
	return max(max(a, b), max(c, d)) - min(min(a, b), min(c, d))


## Height at a world position, matching the ground mesh triangulation.
func height_at(px: float, pz: float) -> float:
	var x := clampi(floori(px), 0, n - 1)
	var y := clampi(floori(pz), 0, n - 1)
	var u: float = clamp(px - x, 0.0, 1.0)
	var v: float = clamp(pz - y, 0.0, 1.0)
	var h0 := hc(x, y); var h1 := hc(x + 1, y); var h2 := hc(x + 1, y + 1); var h3 := hc(x, y + 1)
	if u >= v:
		return h0 + u * (h1 - h0) + v * (h2 - h1)
	return h0 + v * (h3 - h0) + u * (h2 - h3)


func _lot_corners(tiles: Array[Vector2i]) -> Array:
	var cs := {}
	for t in tiles:
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			cs[t + d] = true
	return cs.keys()


func lot_range(tiles: Array[Vector2i]) -> float:
	var mn := 1e9
	var mx := -1e9
	for c in _lot_corners(tiles):
		var h := hc(c.x, c.y)
		mn = min(mn, h); mx = max(mx, h)
	return mx - mn


func rect_tiles(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


func _corner_locked(c: Vector2i, exclude_id: int) -> bool:
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var t: Vector2i = c + d
		if not inb(t.x, t.y):
			continue
		var i := idx(t.x, t.y)
		if road[i] > 0:
			return true
		if bld[i] != -1 and bld[i] != exclude_id:
			return true
	return false


## Flattens a lot (where corners are not locked by neighbours); returns base height.
func _flatten(tiles: Array[Vector2i], id: int) -> float:
	var cs := _lot_corners(tiles)
	var sum := 0.0
	for c in cs:
		sum += hc(c.x, c.y)
	var target: float = max(sum / cs.size(), 0.0)
	var mx := -1e9
	var changed := false
	for c in cs:
		if not _corner_locked(c, id) and abs(hc(c.x, c.y) - target) > 0.001:
			_set_hc(c.x, c.y, target)
			changed = true
		mx = max(mx, hc(c.x, c.y))
	if changed:
		terrain_changed.emit(_rect_of(tiles).grow(1))
	return mx


func _mount_k() -> float:
	return {"river": 1.0, "coast": 0.55, "mountains": 1.9, "lakes": 0.4}.get(map_type, 1.0)


func _generate_heights(sd: int) -> void:
	var nh := FastNoiseLite.new()
	nh.seed = sd + 101
	nh.frequency = 0.03
	nh.fractal_octaves = 4
	var nm := FastNoiseLite.new()
	nm.seed = sd + 202
	nm.frequency = 0.012
	# distance from each tile to water (BFS)
	var wd := PackedInt32Array()
	wd.resize(n * n)
	wd.fill(99)
	var q: Array[int] = []
	for i in n * n:
		if terrain[i] == 1:
			wd[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var cur := q[head]; head += 1
		if wd[cur] >= 10:
			continue
		for d in Defs.DIRS:
			var p: Vector2i = Vector2i(cur % n, cur / n) + d
			if inb(p.x, p.y) and wd[idx(p.x, p.y)] > wd[cur] + 1:
				wd[idx(p.x, p.y)] = wd[cur] + 1
				q.append(idx(p.x, p.y))
	var start := Vector2(8, n / 2)
	for cy in n + 1:
		for cx in n + 1:
			var wc := 0
			var tot := 0
			var mind := 99
			for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var t: Vector2i = Vector2i(cx, cy) + d
				if inb(t.x, t.y):
					tot += 1
					if terrain[idx(t.x, t.y)] == 1:
						wc += 1
					mind = mini(mind, wd[idx(t.x, t.y)])
			var h := 0.0
			if wc == tot:
				h = -0.45 - abs(nh.get_noise_2d(cx * 3.0, cy * 3.0)) * 0.15
			elif wc > 0:
				h = -0.04
			else:
				var land := nh.get_noise_2d(cx, cy) * 0.5 + 0.5
				var mask := smoothstep(-0.05, 0.4, nm.get_noise_2d(cx, cy))
				h = land * 1.8 + mask * pow(land, 1.3) * 12.0 * _mount_k() - 0.6
				h = max(h, 0.0)
				h *= smoothstep(1.0, 7.0, float(mind))
				h *= smoothstep(22.0, 46.0, Vector2(cx, cy).distance_to(start))
			_set_hc(cx, cy, snappedf(h, 0.01))


## Terraforming brush. mode: raise, lower, level, smooth. Returns cost (or -1 when not enough money).
func terraform(center: Vector2, radius: float, mode: String, amount: float, target: float, dry_run: bool = false) -> float:
	var changes := {}
	var cost := 0.0
	for cy in range(maxi(0, floori(center.y - radius)), mini(n, ceili(center.y + radius)) + 1):
		for cx in range(maxi(0, floori(center.x - radius)), mini(n, ceili(center.x + radius)) + 1):
			var dd := Vector2(cx, cy).distance_to(center)
			if dd > radius or _corner_locked(Vector2i(cx, cy), -1) or not owns(Vector2i(mini(cx, n - 1), mini(cy, n - 1))):
				continue
			var f: float = 1.0 - smoothstep(radius * 0.4, radius, dd)
			var h := hc(cx, cy)
			var nh := h
			match mode:
				"raise": nh = h + amount * f
				"lower": nh = h - amount * f
				"level": nh = move_toward(h, target, amount * 2.0 * f)
				"smooth":
					var avg := (hc(cx - 1, cy) + hc(cx + 1, cy) + hc(cx, cy - 1) + hc(cx, cy + 1)) * 0.25
					nh = lerp(h, avg, clamp(amount * 4.0 * f, 0.0, 1.0))
			nh = clamp(nh, -0.7, 16.0)
			if abs(nh - h) > 0.0001:
				changes[Vector2i(cx, cy)] = nh
				cost += abs(nh - h) * 40.0
	if dry_run or changes.is_empty():
		return cost
	if cost > money:
		return -1.0
	money -= cost
	for c in changes:
		_set_hc(c.x, c.y, changes[c])
	var r := Rect2i(floori(center.x - radius) - 1, floori(center.y - radius) - 1, ceili(radius * 2) + 3, ceili(radius * 2) + 3)
	_update_water_flags(r)
	terrain_changed.emit(r)
	return cost


func _update_water_flags(r: Rect2i) -> void:
	r = r.intersection(Rect2i(0, 0, n, n))
	var changed := false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := idx(x, y)
			if road[i] > 0 or bld[i] != -1:
				continue
			var w := 1 if tile_h(x, y) < -0.15 else 0
			if w != terrain[i]:
				terrain[i] = w
				changed = true
				if w == 1:
					zone[i] = 0
					tree[i] = 0
	if changed:
		_compute_water_near(r.grow(6))
		_recompute_roads()
		zones_changed.emit()
		trees_changed.emit()


# ------------------------------------------------------------------ roads
## mode: -1 auto (longer axis first), 0 horizontal first, 1 vertical first
func road_path(a: Vector2i, b: Vector2i, mode: int = -1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := b.x - a.x
	var dy := b.y - a.y
	var p := a
	out.append(p)
	var x_first: bool = abs(dx) >= abs(dy) if mode < 0 else mode == 0
	if x_first:
		while p.x != b.x:
			p.x += signi(dx); out.append(p)
		while p.y != b.y:
			p.y += signi(dy); out.append(p)
	else:
		while p.y != b.y:
			p.y += signi(dy); out.append(p)
		while p.x != b.x:
			p.x += signi(dx); out.append(p)
	return out


## Returns {ok, cost, bad: Array[Vector2i], new: Array[Vector2i], reason}
func check_roads(cells: Array[Vector2i], rtype: int = 1) -> Dictionary:
	var res := {"ok": true, "cost": 0, "bad": [], "new": [], "reason": ""}
	var rdef: Dictionary = Defs.ROAD_TYPES[rtype]
	if milestone_pop() < rdef.unlock:
		res.ok = false
		res.reason = "Откроется при %d жителях" % rdef.unlock
		return res
	var set := {}
	for c in cells:
		set[c] = true
	for c in cells:
		if not inb(c.x, c.y):
			res.bad.append(c); continue
		var i := idx(c.x, c.y)
		if road[i] == rtype:
			continue
		if not owns(c):
			res.bad.append(c); res.reason = "Участок не куплен (меню «Участки», клавиша L)"; continue
		if road[i] > 0:
			# upgrade / downgrade an existing road
			if Vector2i(c.x, c.y) == outside:
				continue
			res.new.append(c)
			res.cost += rdef.cost
			continue
		if bld[i] != -1:
			res.bad.append(c); res.reason = "Мешает здание"; continue
		if path[i] > 0:
			res.bad.append(c); res.reason = "Мешает пешеходная дорожка (снесите её)"; continue
		if rail[i] > 0:
			var rm := rail_mask(c)
			var ax := _track_axis(cells, cells.find(c))
			if rtype == 3 or ax < 0 or not ((rm == 5 and ax == 0) or (rm == 10 and ax == 1)):
				res.bad.append(c); res.reason = "Дорога пересекает рельсы только прямо и поперёк (переезд)"; continue
		if terrain[i] == 0 and tile_range(c.x, c.y) > 0.85:
			res.bad.append(c); res.reason = "Слишком крутой склон"; continue
		res.new.append(c)
		res.cost += Defs.BRIDGE_COST * (1 + rtype) / 2 if terrain[i] == 1 else rdef.cost
	# bridges must stay straight
	var check := {}
	for c in cells:
		for d in 5:
			var p: Vector2i = c if d == 4 else c + Defs.DIRS[d]
			if is_water(p) and (set.has(p) or is_road(p)):
				check[p] = true
	for p in check.keys():
		var m := 0
		for d in 4:
			var q: Vector2i = p + Defs.DIRS[d]
			if set.has(q) or is_road(q):
				m |= 1 << d
		if not (m in [0, 1, 2, 4, 8, 5, 10]):
			res.bad.append(p); res.reason = "Мост должен быть прямым"
	if res.bad.size() > 0:
		res.ok = false
	elif res.cost > money:
		res.ok = false; res.reason = "Недостаточно денег"
	return res


func build_roads(cells: Array[Vector2i], rtype: int = 1) -> bool:
	var r := check_roads(cells, rtype)
	if not r.ok or r.new.is_empty():
		return false
	money -= r.cost
	for c in r.new:
		_set_road(c, true, rtype)
		tree[idx(c.x, c.y)] = 0
		zone[idx(c.x, c.y)] = 0
	_recompute_roads()
	var changed: Array = []
	for c in r.new:
		changed.append(c)
	roads_changed.emit(changed)
	trees_changed.emit()
	return true


func _set_road(c: Vector2i, on: bool, rtype: int = 1) -> void:
	var i := idx(c.x, c.y)
	if on and road[i] > 0 and road[i] != rtype:
		road[i] = rtype
		astar.set_point_weight_scale(i, 1.0 / Defs.ROAD_TYPES[rtype].speed)
		return
	if on and road[i] == 0:
		road[i] = rtype
		road_count += 1
		astar.add_point(i, Vector2(c.x, c.y), 1.0 / Defs.ROAD_TYPES[rtype].speed)
		for d in 4:
			var q: Vector2i = c + Defs.DIRS[d]
			if is_road(q):
				astar.connect_points(i, idx(q.x, q.y))
	elif not on and road[i] > 0:
		road[i] = 0
		road_count -= 1
		astar.remove_point(i)
		traffic[i] = 0


func remove_road(c: Vector2i) -> bool:
	if not is_road(c) or c == outside:
		return false
	money += (Defs.BRIDGE_COST if is_water(c) else Defs.ROAD_TYPES[road[idx(c.x, c.y)]].cost) * 0.5
	_set_road(c, false)
	return true


func _recompute_roads() -> void:
	_ped_dirty = true
	# connected components
	road_comp.fill(-1)
	var comp := 0
	for i in n * n:
		if road[i] > 0 and road_comp[i] == -1:
			var stack := [i]
			road_comp[i] = comp
			while stack.size() > 0:
				var cur: int = stack.pop_back()
				var cx := cur % n
				var cy := cur / n
				for d in 4:
					var q: Vector2i = Vector2i(cx, cy) + Defs.DIRS[d]
					if is_road(q):
						var qi := idx(q.x, q.y)
						if road_comp[qi] == -1:
							road_comp[qi] = comp
							stack.append(qi)
			comp += 1
	outside_comp = road_comp[idx(outside.x, outside.y)] if is_road(outside) else -1
	# distance to road over land
	road_dist.fill(255)
	var q: Array[int] = []
	for i in n * n:
		if road[i] > 0:
			road_dist[i] = 0
			if road[i] != 3:
				q.append(i)
	var head := 0
	while head < q.size():
		var cur := q[head]; head += 1
		var dist := road_dist[cur]
		if dist >= Defs.ZONE_DEPTH:
			continue
		var cx := cur % n
		var cy := cur / n
		for d in 4:
			var p: Vector2i = Vector2i(cx, cy) + Defs.DIRS[d]
			if not inb(p.x, p.y):
				continue
			var pi := idx(p.x, p.y)
			if terrain[pi] == 1 or road_dist[pi] != 255:
				continue
			road_dist[pi] = dist + 1
			q.append(pi)
	# zones that lost road access disappear (empty tiles only)
	var zchanged := false
	for i in n * n:
		if zone[i] != 0 and road_dist[i] == 255 and bld[i] == -1:
			zone[i] = 0
			zchanged = true
	# buildings check road access
	for b: Building in buildings.values():
		var had := b.has_road
		b.has_road = is_road(b.access)
		if had != b.has_road:
			building_updated.emit(b)
	_roads_dirty = false
	_cands_dirty = true
	if zchanged:
		zones_changed.emit()


# ------------------------------------------------------------------ zoning
func can_zone(p: Vector2i) -> bool:
	if not inb(p.x, p.y):
		return false
	var i := idx(p.x, p.y)
	return terrain[i] == 0 and road[i] == 0 and path[i] == 0 and rail[i] == 0 and bld[i] == -1 and road_dist[i] >= 1 and road_dist[i] <= Defs.ZONE_DEPTH and owns(p)


func paint_zone(r: Rect2i, z: int) -> int:
	var cnt := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not inb(x, y):
				continue
			var i := idx(x, y)
			if z == 0:
				if zone[i] != 0:
					var b := building_at(Vector2i(x, y))
					if b and b.type == "zone":
						remove_building(b, "dezone")
					zone[i] = 0
					cnt += 1
			elif can_zone(Vector2i(x, y)) and zone[i] != z:
				zone[i] = z
				cnt += 1
	if cnt > 0:
		_cands_dirty = true
		zones_changed.emit()
	return cnt


# ------------------------------------------------------------------ bulldoze & trees
func bulldoze_preview(r: Rect2i) -> Dictionary:
	var res := {"refund": 0, "items": 0}
	var seen := {}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not inb(x, y):
				continue
			var i := idx(x, y)
			if bld[i] != -1 and not seen.has(bld[i]):
				seen[bld[i]] = true
				var b: Building = buildings[bld[i]]
				if b.is_service():
					res.refund += int(Defs.SERVICES[b.type].cost * 0.5)
				res.items += 1
			elif road[i] > 0 and Vector2i(x, y) != outside:
				res.refund += int((Defs.BRIDGE_COST if terrain[i] == 1 else Defs.ROAD_TYPES[road[i]].cost) * 0.5)
				res.items += 1
			elif rail[i] > 0:
				res.refund += int((RAIL_BRIDGE_COST if terrain[i] == 1 else RAIL_COST) * 0.5)
				res.items += 1
			elif path[i] > 0:
				res.refund += PATH_COST / 2
				res.items += 1
			elif tree[i] == 1:
				res.items += 1
	return res


func bulldoze(r: Rect2i) -> int:
	var cnt := 0
	var roads_removed: Array = []
	var trees_removed := false
	var paths_removed := false
	var rails_removed := false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not inb(x, y):
				continue
			var i := idx(x, y)
			if bld[i] != -1:
				var b: Building = buildings[bld[i]]
				if b.is_service():
					money += Defs.SERVICES[b.type].cost * 0.5
				remove_building(b, "bulldoze")
				cnt += 1
			elif road[i] > 0:
				if remove_road(Vector2i(x, y)):
					roads_removed.append(Vector2i(x, y))
					cnt += 1
				if rail[i] > 0 and remove_rail(Vector2i(x, y)):
					rails_removed = true
			elif rail[i] > 0:
				if remove_rail(Vector2i(x, y)):
					rails_removed = true
					cnt += 1
			elif path[i] > 0:
				path[i] = 0
				paths_removed = true
				money += PATH_COST * 0.5
				cnt += 1
			elif tree[i] == 1:
				tree[i] = 0
				trees_removed = true
				cnt += 1
	if paths_removed:
		_ped_dirty = true
		paths_changed.emit()
	if rails_removed:
		rails_changed.emit()
	if roads_removed.size() > 0:
		_recompute_roads()
		roads_changed.emit(roads_removed)
		_cov_dirty = true
		_validate_lines()
	if trees_removed:
		trees_changed.emit()
	return cnt


# ------------------------------------------------------------------ railway (like Cities: Skylines trains)
func is_rail(p: Vector2i) -> bool:
	return inb(p.x, p.y) and rail[idx(p.x, p.y)] > 0


func rail_mask(p: Vector2i) -> int:
	var m := 0
	for d in 4:
		if is_rail(p + Defs.DIRS[d]):
			m |= 1 << d
	# a track on the map edge continues to the outside world
	if is_rail(p):
		if p.y == 0: m |= 1
		if p.x == n - 1: m |= 2
		if p.y == n - 1: m |= 4
		if p.x == 0: m |= 8
	return m


func is_crossing(p: Vector2i) -> bool:
	return is_rail(p) and is_road(p)


## Returns {ok, cost, bad, new, reason} for laying track along the cells.
func check_rails(cells: Array[Vector2i]) -> Dictionary:
	var res := {"ok": true, "cost": 0, "bad": [], "new": [], "reason": ""}
	if milestone_pop() < RAIL_UNLOCK:
		res.ok = false
		res.reason = "Откроется при %s жителях" % Defs.fmt_int(RAIL_UNLOCK)
		return res
	var set := {}
	for c in cells:
		set[c] = true
	for k in cells.size():
		var c: Vector2i = cells[k]
		if not inb(c.x, c.y):
			res.bad.append(c); continue
		var i := idx(c.x, c.y)
		if rail[i] > 0:
			continue
		if not owns(c):
			res.bad.append(c); res.reason = "Участок не куплен (меню «Участки», клавиша L)"; continue
		if bld[i] != -1:
			res.bad.append(c); res.reason = "Мешает здание"; continue
		if path[i] > 0:
			res.bad.append(c); res.reason = "Мешает пешеходная дорожка"; continue
		if road[i] > 0:
			# level crossing: straight track across a straight street or avenue
			var along := _track_axis(cells, k)
			var rm := road_mask(c)
			if road[i] == 3:
				res.bad.append(c); res.reason = "Шоссе нельзя пересекать по переезду"; continue
			if along < 0 or not ((rm == 5 and along == 1) or (rm == 10 and along == 0)):
				res.bad.append(c); res.reason = "Переезд — только прямо и поперёк прямой дороги"; continue
		elif terrain[i] == 0 and tile_range(c.x, c.y) > 0.7:
			res.bad.append(c); res.reason = "Слишком крутой склон для поезда"; continue
		res.new.append(c)
		res.cost += RAIL_BRIDGE_COST if terrain[i] == 1 else RAIL_COST
	# bridges must stay straight
	for c in cells:
		if is_water(c):
			var m := 0
			for d in 4:
				var q: Vector2i = c + Defs.DIRS[d]
				if set.has(q) or is_rail(q):
					m |= 1 << d
			if not (m in [0, 1, 2, 4, 8, 5, 10]):
				res.bad.append(c); res.reason = "Ж/д мост должен быть прямым"
	if res.bad.size() > 0:
		res.ok = false
	elif res.cost > money:
		res.ok = false; res.reason = "Недостаточно денег"
	return res


## Axis of the drawn track at cells[k]: 0 east-west, 1 north-south, -1 a corner.
func _track_axis(cells: Array[Vector2i], k: int) -> int:
	var axes := {}
	for j in [k - 1, k + 1]:
		if j >= 0 and j < cells.size():
			var d: Vector2i = cells[j] - cells[k]
			axes[0 if d.y == 0 else 1] = true
	if axes.size() != 1:
		return -1 if axes.size() > 1 else 0
	return axes.keys()[0]


func build_rails(cells: Array[Vector2i]) -> bool:
	var r := check_rails(cells)
	if not r.ok or r.new.is_empty():
		return false
	money -= r.cost
	for c in r.new:
		var i := idx(c.x, c.y)
		rail[i] = 1
		tree[i] = 0
		zone[i] = 0
	_rail_dirty = true
	rails_changed.emit()
	trees_changed.emit()
	zones_changed.emit()
	return true


func remove_rail(c: Vector2i) -> bool:
	if not is_rail(c):
		return false
	var i := idx(c.x, c.y)
	rail[i] = 0
	money += (RAIL_BRIDGE_COST if terrain[i] == 1 else RAIL_COST) * 0.5
	_rail_dirty = true
	return true


func _recompute_rail() -> void:
	_rail_dirty = false
	rail_comp.resize(n * n)
	rail_comp.fill(-1)
	rail_out.clear()
	var comp := 0
	for i in n * n:
		if rail[i] == 0 or rail_comp[i] != -1:
			continue
		var stack := [i]
		rail_comp[i] = comp
		var out := false
		while stack.size() > 0:
			var j: int = stack.pop_back()
			var x := j % n
			var y := j / n
			if x == 0 or y == 0 or x == n - 1 or y == n - 1:
				out = true
			for d in 4:
				var q: Vector2i = Vector2i(x, y) + Defs.DIRS[d]
				if is_rail(q):
					var k := idx(q.x, q.y)
					if rail_comp[k] == -1:
						rail_comp[k] = comp
						stack.append(k)
		rail_out.append(out)
		comp += 1


## Track tile next to a station where trains stop (behind or beside the building).
func station_platform(b: Building) -> Vector2i:
	var r := b.rect()
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var p := Vector2i(x, y)
			if r.has_point(p) or not is_rail(p):
				continue
			# corners don't count
			if (x < r.position.x or x >= r.end.x) and (y < r.position.y or y >= r.end.y):
				continue
			return p
	return Vector2i(-1, -1)


## {out: connected to the outside world, peers: other stations of the same kind on the network, comp}
func station_link(b: Building) -> Dictionary:
	if _rail_dirty:
		_recompute_rail()
	var res := {"out": false, "peers": 0, "comp": -1, "platform": station_platform(b)}
	var p: Vector2i = res.platform
	if p.x < 0:
		return res
	res.comp = rail_comp[idx(p.x, p.y)]
	res.out = rail_out[res.comp]
	for o: Building in buildings.values():
		if o != b and o.type == b.type:
			var q := station_platform(o)
			if q.x >= 0 and rail_comp[idx(q.x, q.y)] == res.comp:
				res.peers += 1
	return res


func rail_stations(type: String) -> Array:
	var out: Array = []
	for b: Building in buildings.values():
		if b.type == type and b.done():
			out.append(b)
	return out


## Track tiles on the map edge in a rail network (where trains come from and leave to).
func rail_exits(comp: int) -> Array[Vector2i]:
	if _rail_dirty:
		_recompute_rail()
	var out: Array[Vector2i] = []
	for k in n:
		for p in [Vector2i(k, 0), Vector2i(k, n - 1), Vector2i(0, k), Vector2i(n - 1, k)]:
			if is_rail(p) and rail_comp[idx(p.x, p.y)] == comp and not out.has(p):
				out.append(p)
	return out


## Shortest route along the track (BFS), [] if there is none.
func rail_route(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_rail(a) or not is_rail(b):
		return out
	var prev := {a: a}
	var q: Array[Vector2i] = [a]
	var h := 0
	while h < q.size():
		var c: Vector2i = q[h]
		h += 1
		if c == b:
			break
		for d in 4:
			var nb: Vector2i = c + Defs.DIRS[d]
			if is_rail(nb) and not prev.has(nb):
				prev[nb] = c
				q.append(nb)
	if not prev.has(b):
		return out
	var c := b
	while c != a:
		out.push_front(c)
		c = prev[c]
	out.push_front(a)
	return out


func _rail_month() -> Dictionary:
	# passenger stations: commuters along the line, tourists from the outside world
	var res := {"riders": 0.0, "income": 0.0, "tourism": 0.0}
	for b: Building in rail_stations("train_station"):
		var lk := station_link(b)
		if not lk.out and lk.peers == 0:
			continue
		var c := Vector2(b.center().x, b.center().z)
		var pop := 0.0
		for o: Building in buildings.values():
			if not o.is_service() and not o.abandoned and Vector2(o.center().x, o.center().z).distance_to(c) <= STATION_RADIUS:
				pop += o.occ
		var riders := minf(pop * 0.12 * (1.0 + 0.1 * subsidy("transit")) + (400.0 if lk.out else 0.0), 2400.0)
		res.riders += riders
		res.income += riders * 4.0
		if lk.out:
			res.tourism += 900.0
	return res


# ------------------------------------------------------------------ pedestrian paths
func check_paths(cells: Array[Vector2i]) -> Dictionary:
	var res := {"ok": true, "cost": 0, "bad": [], "new": [], "reason": ""}
	for c in cells:
		if not inb(c.x, c.y):
			res.bad.append(c); continue
		var i := idx(c.x, c.y)
		if path[i] > 0:
			continue
		if not owns(c):
			res.bad.append(c); res.reason = "Участок не куплен"; continue
		if road[i] > 0:
			continue          # crossing a road: walkers use the zebra crossing
		if bld[i] != -1:
			res.bad.append(c); res.reason = "Мешает здание"; continue
		if terrain[i] == 0 and tile_range(c.x, c.y) > 1.3:
			res.bad.append(c); res.reason = "Слишком крутой склон"; continue
		res.new.append(c)
		res.cost += PATH_COST * (4 if terrain[i] == 1 else 1)
	if res.bad.size() > 0:
		res.ok = false
	elif res.cost > money:
		res.ok = false; res.reason = "Недостаточно денег"
	return res


func build_paths(cells: Array[Vector2i]) -> bool:
	var r := check_paths(cells)
	if not r.ok or r.new.is_empty():
		return false
	money -= r.cost
	for c in r.new:
		var i := idx(c.x, c.y)
		path[i] = 1
		tree[i] = 0
		zone[i] = 0
	_ped_dirty = true
	paths_changed.emit()
	trees_changed.emit()
	zones_changed.emit()
	return true


func is_path(p: Vector2i) -> bool:
	return inb(p.x, p.y) and path[idx(p.x, p.y)] > 0


## Tiles people can walk on: pedestrian paths, sidewalks of local roads, parks.
func walkable(i: int) -> bool:
	if path[i] > 0:
		return true
	if road[i] > 0:
		return road[i] < 3
	if bld[i] != -1:
		var b: Building = buildings.get(bld[i])
		return b != null and b.type in PARK_WALK
	return false


func _rebuild_ped_graph() -> void:
	_ped_dirty = false
	ped_astar.clear()
	ped_astar.reserve_space(n * n / 3)
	for i in n * n:
		if walkable(i):
			# paths and parks are pleasant: walkers prefer them over sidewalks
			var w := 0.75 if path[i] > 0 else (0.85 if road[i] == 0 else 1.0)
			ped_astar.add_point(i, Vector2(i % n, i / n), w)
	for i in n * n:
		if not ped_astar.has_point(i):
			continue
		var x := i % n
		if x < n - 1 and ped_astar.has_point(i + 1):
			ped_astar.connect_points(i, i + 1)
		if i + n < n * n and ped_astar.has_point(i + n):
			ped_astar.connect_points(i, i + n)


## Where people leave / enter a building: a pedestrian path next to it if there is one, else its road.
func door(b: Building) -> Vector2i:
	for y in range(b.y - 1, b.y + b.sy + 1):
		for x in range(b.x - 1, b.x + b.sx + 1):
			var corner := (x == b.x - 1 or x == b.x + b.sx) and (y == b.y - 1 or y == b.y + b.sy)
			if not corner and is_path(Vector2i(x, y)):
				return Vector2i(x, y)
	return b.access


func ped_route(a: Vector2i, b: Vector2i) -> PackedVector2Array:
	if _ped_dirty:
		_rebuild_ped_graph()
	var ia := idx(a.x, a.y)
	var ib := idx(b.x, b.y)
	if not ped_astar.has_point(ia) or not ped_astar.has_point(ib):
		return PackedVector2Array()
	return ped_astar.get_point_path(ia, ib)


# ------------------------------------------------------------------ land plots
func land_of(x: int, y: int) -> int:
	return clampi(y / LAND, 0, LAND_N - 1) * LAND_N + clampi(x / LAND, 0, LAND_N - 1)


func owns(p: Vector2i) -> bool:
	return inb(p.x, p.y) and owned[land_of(p.x, p.y)] == 1


func owned_count() -> int:
	var c := 0
	for v in owned:
		c += v
	return c


## How many plots the city may own: more with every milestone.
func land_limit() -> int:
	if sandbox:
		return LAND_N * LAND_N
	return 2 + milestone * 2 + (1 if milestone >= 5 else 0)


func land_price(t: int) -> float:
	return roundf(8000.0 * pow(owned_count(), 1.25) / 500.0) * 500.0


func can_buy_land(t: int) -> Dictionary:
	if owned[t] == 1:
		return {"ok": false, "reason": "Уже ваш"}
	var tx := t % LAND_N
	var ty := t / LAND_N
	var adj := false
	for d in Defs.DIRS:
		var x: int = tx + d.x
		var y: int = ty + d.y
		if x >= 0 and y >= 0 and x < LAND_N and y < LAND_N and owned[y * LAND_N + x] == 1:
			adj = true
	if not adj:
		return {"ok": false, "reason": "Можно купить только соседний участок"}
	if owned_count() >= land_limit():
		return {"ok": false, "reason": "Новый участок откроется на следующем этапе развития города"}
	if money < land_price(t):
		return {"ok": false, "reason": "Недостаточно денег"}
	return {"ok": true, "reason": ""}


func buy_land(t: int) -> bool:
	var c := can_buy_land(t)
	if not c.ok:
		return false
	money -= land_price(t)
	owned[t] = 1
	log_event("land", "Город купил новый участок земли", "Территория города расширилась: теперь участков %d." % owned_count())
	land_changed.emit()
	_cands_dirty = true
	return true


## What a plot holds (shown before buying): water, forest, fertile land, ore, oil, how hilly it is.
func land_info(t: int) -> Dictionary:
	var tx := (t % LAND_N) * LAND
	var ty := (t / LAND_N) * LAND
	var cnt := {"water": 0, "forest": 0, "fertile": 0, "ore": 0, "oil": 0, "hills": 0}
	var tot := LAND * LAND
	for y in range(ty, ty + LAND):
		for x in range(tx, tx + LAND):
			var i := idx(x, y)
			if terrain[i] == 1: cnt.water += 1
			if tree[i] == 1: cnt.forest += 1
			if resource[i] == 1: cnt.fertile += 1
			if resource[i] == 3: cnt.ore += 1
			if resource[i] == 4: cnt.oil += 1
			if tile_range(x, y) > 0.6 or tile_h(x, y) > 3.0: cnt.hills += 1
	for k in cnt:
		cnt[k] = int(cnt[k] * 100.0 / tot)
	return cnt


func plant_tree(p: Vector2i) -> bool:
	if not inb(p.x, p.y):
		return false
	var i := idx(p.x, p.y)
	if terrain[i] == 1 or road[i] > 0 or path[i] > 0 or rail[i] > 0 or bld[i] != -1 or tree[i] == 1 or money < Defs.TREE_COST or not owns(p):
		return false
	tree[i] = 1
	money -= Defs.TREE_COST
	trees_changed.emit()
	return true


# ------------------------------------------------------------------ buildings
func lot_tiles(f: Vector2i, dir: int, w: int, d: int, flip: int = 1) -> Array[Vector2i]:
	var F := Defs.DIRS[dir]
	var back := -F
	var side := Vector2i(-F.y, F.x) * flip
	var out: Array[Vector2i] = []
	for j in d:
		for i in w:
			out.append(f + side * i + back * j)
	return out


func _rect_of(tiles: Array[Vector2i]) -> Rect2i:
	var mn := tiles[0]
	var mx := tiles[0]
	for t in tiles:
		mn = Vector2i(mini(mn.x, t.x), mini(mn.y, t.y))
		mx = Vector2i(maxi(mx.x, t.x), maxi(mx.y, t.y))
	return Rect2i(mn, mx - mn + Vector2i.ONE)


func _new_building(type: String, z: int, tiles: Array[Vector2i], dir: int, w: int, d: int, access: Vector2i) -> Building:
	var b := Building.new()
	b.id = next_id
	next_id += 1
	if type in PARK_WALK:
		_ped_dirty = true
	b.type = type
	b.zone = z
	b.dir = dir
	b.w = w
	b.d = d
	b.access = access
	b.seed = rng.randi()
	var r := _rect_of(tiles)
	b.x = r.position.x; b.y = r.position.y; b.sx = r.size.x; b.sy = r.size.y
	var trees_hit := false
	for t in tiles:
		var i := idx(t.x, t.y)
		bld[i] = b.id
		if tree[i] == 1:
			tree[i] = 0
			trees_hit = true
	buildings[b.id] = b
	b.base_y = _flatten(tiles, b.id)
	if trees_hit:
		trees_changed.emit()
	return b


func _calc_cap(b: Building) -> int:
	if b.type != "zone":
		return 0
	return int(round(Defs.ZONES[b.zone].cap * b.area() * (1.0 + (b.level - 1) * 0.7)))


func remove_building(b: Building, reason: String = "") -> void:
	if not buildings.has(b.id):
		return
	if b.type in PARK_WALK:
		_ped_dirty = true
	for t in b.tiles():
		var i := idx(t.x, t.y)
		if bld[i] == b.id:
			bld[i] = -1
	buildings.erase(b.id)
	_cands_dirty = true
	if b.is_service():
		_cov_dirty = true
	building_removed.emit(b, reason)
	if b.type == "metro":
		_validate_lines()


## Finds a valid placement for a service building around the cursor.
func service_placement(id: String, c: Vector2i, pref_dir: int) -> Dictionary:
	var def: Dictionary = Defs.SERVICES[id]
	var dirs: Array = [pref_dir] if pref_dir >= 0 else [2, 0, 1, 3]
	var best := {}
	for dir in dirs:
		var ns: bool = dir == 0 or dir == 2
		var sx: int = def.w if ns else def.d
		var sy: int = def.d if ns else def.w
		var r := Rect2i(c.x - (sx - 1) / 2, c.y - (sy - 1) / 2, sx, sy)
		var res := {"ok": true, "rect": r, "dir": dir, "access": Vector2i(-1, -1), "reason": "", "cost": def.cost}
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if not inb(x, y):
					res.ok = false; res.reason = "За пределами карты"; continue
				var i := idx(x, y)
				if terrain[i] == 1 or road[i] > 0 or bld[i] != -1 or path[i] > 0 or rail[i] > 0:
					res.ok = false; res.reason = "Место занято"
				elif not owns(Vector2i(x, y)):
					res.ok = false; res.reason = "Участок не куплен"
		# front edge must touch a road
		var F := Defs.DIRS[dir]
		var front: Array[Vector2i] = []
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var p := Vector2i(x, y)
				if not r.has_point(p + F):
					front.append(p + F)
		for p in front:
			if is_local_road(p):
				res.access = p
				break
		if res.ok and res.access == Vector2i(-1, -1):
			res.ok = false; res.reason = "Нужен выход к дороге"
		if res.ok and def.get("need_rail", false):
			var has_track := false
			for y in range(r.position.y - 1, r.end.y + 1):
				for x in range(r.position.x - 1, r.end.x + 1):
					if not r.has_point(Vector2i(x, y)) and is_rail(Vector2i(x, y)) and not ((x < r.position.x or x >= r.end.x) and (y < r.position.y or y >= r.end.y)):
						has_track = true
			if not has_track:
				res.ok = false; res.reason = "Поставьте рядом с ж/д путями (пути вплотную к зданию)"
		if res.ok and def.get("need_water", false):
			var near := false
			for y in range(r.position.y - 1, r.end.y + 1):
				for x in range(r.position.x - 1, r.end.x + 1):
					if is_water(Vector2i(x, y)):
						near = true
			if not near:
				res.ok = false; res.reason = "Нужно поставить у воды"
		if res.ok and lot_range(rect_tiles(r)) > 1.4:
			res.ok = false; res.reason = "Слишком неровная местность"
		if res.ok and money < def.cost:
			res.ok = false; res.reason = "Недостаточно денег"
		if def.get("unique", false):
			for ob: Building in buildings.values():
				if ob.type == id:
					res.ok = false
					res.reason = "Уже построено — только одно на город"
		var ul := service_unlock(id)
		if milestone_pop() < ul:
			res.ok = false
			res.reason = "Нужно Министерство науки и космоса" if ul >= 999999 else "Откроется при %d жителях" % ul
		var sr := space.unlock_reason(id)
		if sr != "":
			res.ok = false; res.reason = sr
		if def.has("needs") and not _has_building(def.needs):
			res.ok = false; res.reason = "Сначала постройте: %s" % Defs.SERVICES[def.needs].name
		if def.has("max") and _count_building(id) >= int(def.max):
			res.ok = false; res.reason = "Не больше %d в городе" % int(def.max)
		if def.get("award", false) and not mansion_awarded:
			res.ok = false; res.reason = "Это награда: горожане подарят её, когда будут очень довольны (счастье > 75%, от 2 500 жителей)"
		if res.ok:
			return res
		if best.is_empty():
			best = res
	return best


func place_service(id: String, c: Vector2i, pref_dir: int) -> Building:
	var p := service_placement(id, c, pref_dir)
	if not p.ok:
		return null
	var def: Dictionary = Defs.SERVICES[id]
	var r: Rect2i = p.rect
	var tiles: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			tiles.append(Vector2i(x, y))
			zone[idx(x, y)] = 0
	var b := _new_building(id, 0, tiles, p.dir, def.w, def.d, p.access)
	b.powered = true
	b.watered = true
	money -= def.cost
	_cov_dirty = true
	if def.get("unique", false):
		log_event("landmark", "Торжественное открытие: %s!" % def.name, "Горожане собрались на церемонию. %s" % def.desc)
	elif not id in ["park", "tower", "wind", "metro"]:
		log_event("service", "Открыт новый объект: %s" % def.name, "Мэрия вложила ₽%s в строительство. %s" % [Defs.fmt_int(def.cost), def.desc])
	building_added.emit(b)
	zones_changed.emit()
	_compute_utilities()
	return b


## Budget multiplier of a service category (0.5..1.5).
func bud(cat: String) -> float:
	return float(budget.get(cat, 100)) / 100.0


func svc_cat(b: Building) -> String:
	return Defs.SERVICES[b.type].cat if b.is_service() else ""


## Wind is stronger on hills and in bad weather; solar depends on season and clouds.
func env_factor(b: Building) -> float:
	match b.type:
		"wind":
			var h := tile_h(b.x, b.y)
			return clamp(0.7 + h / 8.0, 0.7, 1.6) * (1.2 if weather != "clear" else 1.0)
		"solar":
			return [0.55, 0.95, 1.15, 0.8][season()] * (0.65 if weather != "clear" else 1.0)
		"hydro":
			return b.eff
	return 1.0


func _env_green(b: Building) -> float:
	return 1.0 + 0.08 * subsidy("green") if b.type in ["wind", "solar"] else 1.0


## Actual output of a service building for "power", "water" or "sewage".
func svc_output(b: Building, key: String) -> float:
	var def: Dictionary = Defs.SERVICES[b.type]
	if not def.has(key):
		return 0.0
	var v: float = def[key] * bud(def.cat)
	if b.flooded or not b.done():
		return 0.0
	if key == "power":
		v *= env_factor(b) * _env_green(b) * space.power_factor(b)
	if key == "water" and def.get("need_water", false):
		v *= b.eff
	return v


func svc_radius(b: Building) -> float:
	var def: Dictionary = Defs.SERVICES[b.type]
	if def.cat == "landmark":
		return def.get("radius", 0.0)
	var k := 1.15 if has_ministry("safety") and def.cat in ["safety", "health"] else 1.0
	return def.get("radius", 0.0) * (0.55 + 0.45 * bud(def.cat)) * k


## Is a pump drawing polluted water?
func pump_dirty(b: Building) -> float:
	if b.type == "tower":
		# water towers draw ground water: polluted soil spoils it
		return avg_field(b, pollution) * 1.2
	if b.type != "pump":
		return 0.0
	var best := 0.0
	for y in range(b.y - 1, b.y + b.sy + 1):
		for x in range(b.x - 1, b.x + b.sx + 1):
			if inb(x, y) and water_sim and water_sim.d[idx(x, y)] > WaterSim.DRY:
				best = max(best, water_pol[idx(x, y)])
	return best


func ind_spec(b: Building) -> String:
	if b.type != "zone" or b.zone != Defs.IND:
		return ""
	var d := district[idx(b.x, b.y)]
	if d > 0 and districts.has(d):
		return districts[d].get("spec", "")
	return ""


## Share of a building's tiles with the resource needed by its specialization (0..1).
func spec_resource(b: Building, spec: String) -> float:
	var r: int = Defs.SPECS[spec].res
	var dep: bool = Defs.SPECS[spec].deplete
	var s := 0.0
	for t in b.tiles():
		var i := idx(t.x, t.y)
		if resource[i] == r:
			s += res_amt[i] if dep else 1.0
	return s / b.area()


func set_district_spec(id: int, spec: String) -> void:
	if not districts.has(id):
		return
	districts[id]["spec"] = spec
	if spec != "":
		log_event("policy", "Район «%s» специализируется: %s" % [districts[id].name, Defs.SPECS[spec].name], Defs.SPECS[spec].desc)
	for b: Building in buildings.values():
		if b.type == "zone" and b.zone == Defs.IND and district[idx(b.x, b.y)] == id:
			building_updated.emit(b)
	_cov_dirty = true


## Megaprojects: each stage is paid when money is available, then takes about a month
## (faster when the city's industry produces plenty of goods).
func _update_mega() -> void:
	for b: Building in buildings.values():
		if not b.is_service():
			continue
		var def: Dictionary = Defs.SERVICES[b.type]
		var stages := int(def.get("stages", 0))
		if b.stage >= stages:
			continue
		if not b.funded:
			var cost: float = def.stage_cost[b.stage]
			if money >= cost:
				money -= cost
				b.funded = true
				log_event("mega", "%s: начат этап %d из %d" % [def.name, b.stage + 1, stages], "Город выделил ₽%s на строительство." % Defs.fmt_int(cost))
			else:
				_notify_once("mega_money_" + b.type, "🏗 %s ждёт финансирования этапа %d: нужно ₽%s." % [def.name, b.stage + 1, Defs.fmt_int(cost)], "info", 20)
			continue
		var rate: float = 1.0 + clampf(goods.prod / 1500.0, 0.0, 1.0)
		b.stage_days += rate
		if b.stage_days >= Defs.DAYS_PER_MONTH:
			b.stage += 1
			b.stage_days = 0.0
			b.funded = false
			_cov_dirty = true
			building_updated.emit(b)
			if b.stage >= stages:
				log_event("mega", "Мегапроект завершён: %s!" % def.name, "Весь регион говорит о новом чуде. %s" % def.desc)
				notify.emit("🎉 Построено: %s!" % def.name, "good")
			else:
				notify.emit("🏗 %s: этап %d из %d готов." % [def.name, b.stage, stages], "good")


## Architecture style for new buildings at a tile: the district's own, else the city's.
func style_at(t: Vector2i) -> String:
	var d := district[idx(t.x, t.y)] if inb(t.x, t.y) else 0
	if districts.has(d) and districts[d].get("style", "") != "":
		return districts[d].style
	return city_style


const RESTYLE_COST := 300

## Rebuilds one building in a chosen style ("" = follow the district / city again).
func set_building_style(b: Building, style: String) -> bool:
	if b.type != "zone" or money < RESTYLE_COST:
		return false
	var ns := style if style != "" else style_at(Vector2i(b.x, b.y))
	b.style_lock = style != ""
	if ns == b.style:
		return true
	money -= RESTYLE_COST
	b.style = ns
	building_updated.emit(b)
	return true


## Changes a style (district id 0 = whole city). Existing buildings rebuild in the new style
## gradually, when they upgrade; `now` restyles them immediately (costs money).
func set_style(d: int, style: String, now: bool = false) -> void:
	if d == 0:
		city_style = style
	elif districts.has(d):
		districts[d]["style"] = style
	else:
		return
	log_event("policy", "Новый архитектурный стиль: %s" % Defs.STYLES.get(style, {"name": "как в городе"}).name,
		"%s Новые и перестраиваемые здания будут строиться в этом стиле." % ("Район «%s»." % districts[d].name if d > 0 else "Весь город."))
	if now:
		for b: Building in buildings.values():
			if b.type == "zone" and not b.abandoned and not b.style_lock and (d == 0 or district[idx(b.x, b.y)] == d):
				var ns := style_at(Vector2i(b.x, b.y))
				if ns != b.style:
					b.style = ns
					building_updated.emit(b)


func set_emptying(b: Building, on: bool) -> void:
	b.emptying = on
	_cov_dirty = true
	building_updated.emit(b)


func milestone_pop() -> int:
	return Defs.MILESTONES[milestone].pop if milestone < Defs.MILESTONES.size() else 0


func is_unlocked(unlock: int) -> bool:
	return milestone_pop() >= unlock


## Population needed for a service; ministries open their buildings earlier.
func service_unlock(id: String) -> int:
	var def: Dictionary = Defs.SERVICES[id]
	var ul: int = def.unlock
	var m: String = def.get("ministry", "")
	if m != "" and has_ministry(m):
		var best := 0
		for ms in Defs.MILESTONES:
			if ms.pop <= ul / 3:
				best = ms.pop
		return best
	return ul


func _near_casino(b: Building) -> bool:
	for o: Building in buildings.values():
		if o.type == "casino" and o.center().distance_to(b.center()) < 9.0:
			return true
	return false


func _has_building(type: String) -> bool:
	return _count_building(type) > 0


func _count_building(type: String) -> int:
	var c := 0
	for b: Building in buildings.values():
		if b.type == type:
			c += 1
	return c


# ------------------------------------------------------------------ government (SimCity city hall)
func hall() -> Building:
	for b: Building in buildings.values():
		if b.type == "cityhall":
			return b
	return null


func has_ministry(m: String) -> bool:
	var h := hall()
	return h != null and m in h.ministries


func hall_slots() -> int:
	var h := hall()
	return Defs.HALL_LEVELS[clampi(h.level, 1, 3) - 1].slots if h else 0


func upgrade_hall_state() -> Dictionary:
	var h := hall()
	if h == null:
		return {"ok": false, "reason": "Сначала постройте ратушу"}
	if h.level >= Defs.HALL_LEVELS.size():
		return {"ok": false, "reason": "Высший уровень"}
	var nxt: Dictionary = Defs.HALL_LEVELS[h.level]
	if population < nxt.pop:
		return {"ok": false, "reason": "Нужно %s жителей" % Defs.fmt_int(nxt.pop)}
	if money < nxt.cost:
		return {"ok": false, "reason": "Недостаточно денег"}
	return {"ok": true, "reason": ""}


func upgrade_hall() -> bool:
	if not upgrade_hall_state().ok:
		return false
	var h := hall()
	var nxt: Dictionary = Defs.HALL_LEVELS[h.level]
	money -= nxt.cost
	h.level += 1
	log_event("policy", "Ратуша выросла: теперь это %s!" % nxt.name, "Новое здание открывает места для министерств: всего %d." % nxt.slots)
	building_updated.emit(h)
	return true


func build_ministry(m: String) -> bool:
	var h := hall()
	var def: Dictionary = Defs.MINISTRIES[m]
	if h == null or m in h.ministries or h.ministries.size() >= hall_slots() or money < def.cost:
		return false
	money -= def.cost
	h.ministries.append(m)
	log_event("policy", "Открыто: %s" % def.name, def.desc)
	building_updated.emit(h)
	_cov_dirty = true
	return true


func subsidy(id: String) -> int:
	return int(subsidies.get(id, 0))


## Mayor's mansion as a reward, achievements.
func _check_awards() -> void:
	if not mansion_awarded and population >= 2500 and avg_happiness > 75.0:
		mansion_awarded = true
		notify.emit("🏛 Благодарные горожане дарят мэру резиденцию! Постройте её бесплатно: «Уникальные» → «Резиденция мэра».", "good")
		log_event("policy", "Подарок мэру", "Горожане скинулись на резиденцию для любимого мэра.")
	if day % 5 == 0:
		for id in Achievements.LIST:
			if not achievements.has(id) and Achievements.check(id, self):
				achievements[id] = day
				notify.emit("🏆 Достижение: «%s» — %s" % [Achievements.LIST[id].name, Achievements.LIST[id].desc], "good")
				achievement_unlocked.emit(id)


# ------------------------------------------------------------------ public transport
func has_policy(id: String, at: Vector2i = Vector2i(-1, -1)) -> bool:
	if id in city_policies:
		return true
	if at.x >= 0 and inb(at.x, at.y):
		var d := district[idx(at.x, at.y)]
		if d > 0 and districts.has(d) and id in districts[d].policies:
			return true
	return false


func bpol(b: Building, id: String) -> bool:
	return has_policy(id, Vector2i(b.x, b.y))


func toggle_policy(id: String, target: int) -> void:
	## target 0 = whole city, otherwise district id
	var arr: Array = city_policies if target == 0 else districts[target].policies
	if id in arr:
		arr.erase(id)
	else:
		arr.append(id)
		log_event("policy", "Новый закон: «%s»" % Defs.POLICIES[id].name, "%s Действует: %s." % [Defs.POLICIES[id].desc, "во всём городе" if target == 0 else "в районе «%s»" % districts[target].name])
	_cov_dirty = true
	_compute_transit()


func new_district() -> int:
	var id := next_district
	next_district += 1
	var used := []
	for d in districts.values():
		used.append(d.name)
	var name: String = Defs.DISTRICT_NAMES[rng.randi() % Defs.DISTRICT_NAMES.size()]
	var tries := 0
	while name in used and tries < 40:
		name = Defs.DISTRICT_NAMES[rng.randi() % Defs.DISTRICT_NAMES.size()]
		tries += 1
	if name in used:
		name += " %d" % id
	log_event("district", "Появился новый район — «%s»" % name, "Жители обсуждают, каким станет новый район.")
	districts[id] = {"name": name, "color": Defs.DISTRICT_COLORS[(id - 1) % Defs.DISTRICT_COLORS.size()], "policies": []}
	districts_changed.emit()
	return id


func paint_district(center: Vector2, radius: float, id: int) -> void:
	var changed := false
	for y in range(maxi(0, floori(center.y - radius)), mini(n, ceili(center.y + radius))):
		for x in range(maxi(0, floori(center.x - radius)), mini(n, ceili(center.x + radius))):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				var i := idx(x, y)
				if district[i] != id:
					district[i] = id
					changed = true
	if changed:
		# drop districts that no longer have tiles
		var alive := {}
		for v in district:
			alive[v] = true
		for d in districts.keys():
			if not alive.has(d):
				districts.erase(d)
		districts_changed.emit()


func district_tiles_count(id: int) -> int:
	var c := 0
	for v in district:
		if v == id:
			c += 1
	return c


func line_vehicles(l: Dictionary) -> int:
	var base: int = clampi(int(ceil(l.stops.size() / 2.0)), 1, 8) if l.kind != "metro" else clampi(l.stops.size() - 1, 1, 6)
	return maxi(1, int(round(base * bud("transport"))))


func line_stop_tiles(l: Dictionary) -> Array[Vector2i]:
	## Road tiles of bus stops / access tiles of metro stations.
	var out: Array[Vector2i] = []
	for s in l.stops:
		if l.kind != "metro":
			out.append(s)
		else:
			var b: Building = buildings.get(int(s))
			if b:
				out.append(b.access)
	return out


func line_stop_points(l: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for s in l.stops:
		if l.kind != "metro":
			out.append(Vector2(s.x + 0.5, s.y + 0.5))
		else:
			var b: Building = buildings.get(int(s))
			if b:
				out.append(Vector2(b.center().x, b.center().z))
	return out


func has_service_in_comp(type: String, comp: int) -> bool:
	for b: Building in buildings.values():
		if b.type == type and b.has_road and road_comp[idx(b.access.x, b.access.y)] == comp:
			return true
	return false


## Validates a line; returns "" if ok or a reason.
func check_line(kind: String, stops: Array) -> String:
	if stops.size() < 2:
		return "Нужно минимум 2 остановки"
	if kind != "metro":
		var comp := -1
		for s in stops:
			if not is_road(s):
				return "Остановка должна быть на дороге"
			var c := road_comp[idx(s.x, s.y)]
			if comp >= 0 and c != comp:
				return "Остановки не соединены дорогами"
			comp = c
		var depot := "busdepot" if kind == "bus" else "tramdepot"
		if not has_service_in_comp(depot, comp):
			return "Нужен %s, соединённый с маршрутом" % ("автобусный парк" if kind == "bus" else "трамвайное депо")
		for i in stops.size():
			var a: Vector2i = stops[i]
			var b: Vector2i = stops[(i + 1) % stops.size()]
			if a != b and find_path(a, b).size() == 0:
				return "Нет пути между остановками"
	else:
		for s in stops:
			var b: Building = buildings.get(int(s))
			if b == null or b.type != "metro":
				return "Линия метро соединяет только станции"
	return ""


func add_line(kind: String, stops: Array) -> Dictionary:
	if check_line(kind, stops) != "":
		return {}
	var l := {"id": next_line_id, "kind": kind, "stops": stops.duplicate(), "riders": 0,
		"color": Defs.LINE_COLORS[(next_line_id - 1) % Defs.LINE_COLORS.size()],
		"name": {"bus": "Автобус №%d", "tram": "Трамвай №%d", "metro": "Линия метро %d"}[kind] % next_line_id}
	next_line_id += 1
	lines.append(l)
	log_event("line", "Запущен маршрут «%s»" % l.name, "Новый маршрут соединил %d остановок. Горожане оценили удобство." % stops.size())
	_compute_transit()
	lines_changed.emit()
	return l


func remove_line(id: int) -> void:
	for l in lines:
		if l.id == id:
			lines.erase(l)
			break
	_compute_transit()
	lines_changed.emit()


func _validate_lines() -> void:
	var changed := false
	for l in lines.duplicate():
		var keep: Array = []
		for s in l.stops:
			var ok: bool = is_road(s) if l.kind != "metro" else (buildings.has(int(s)) and buildings[int(s)].type == "metro")
			if ok:
				keep.append(s)
		if keep.size() != l.stops.size():
			changed = true
			l.stops = keep
		if l.stops.size() < 2:
			lines.erase(l)
			changed = true
			_notify_once("line_removed", "🚌 Маршрут «%s» закрыт: остановки снесены." % l.name, "bad", 1)
	if changed:
		_compute_transit()
		lines_changed.emit()


func _compute_transit() -> void:
	var tcov: PackedFloat32Array = PackedFloat32Array()
	tcov.resize(n * n)
	tcov.fill(0)
	transit_riders = 0
	var free: bool = has_policy("free_transit")
	transit_income = 0.0
	for l in lines:
		var td: Dictionary = Defs.TRANSIT[l.kind]
		var r: float = td.radius
		var pts := line_stop_points(l)
		for p in pts:
			for y in range(maxi(0, int(p.y - r)), mini(n, int(p.y + r) + 1)):
				for x in range(maxi(0, int(p.x - r)), mini(n, int(p.x + r) + 1)):
					var dd := Vector2(x + 0.5, y + 0.5).distance_to(p)
					if dd <= r:
						var i := idx(x, y)
						tcov[i] = max(tcov[i], clamp(1.2 * (1.0 - dd / r), 0.0, 1.0) * (1.0 if l.kind == "metro" else 0.7))
		var pop_cov := 0.0
		var job_cov := 0.0
		for b: Building in buildings.values():
			if b.is_service() or b.abandoned:
				continue
			var c := Vector2(b.center().x, b.center().z)
			var near := false
			for p in pts:
				if c.distance_to(p) <= r:
					near = true
					break
			if near:
				if b.kind() == "r":
					pop_cov += b.occ
				else:
					job_cov += b.occ
		var riders: float = (pop_cov * 0.3 + job_cov * 0.25) * td.rate * (1.35 if free else 1.0) * (1.15 if has_ministry("transport") else 1.0) * (1.0 + 0.1 * subsidy("transit"))
		riders = min(riders, td.per_vehicle * line_vehicles(l))
		l.riders = int(riders)
		transit_riders += l.riders
		if not free:
			transit_income += riders * td.price * 0.5
	# railway stations
	rail_stats = _rail_month()
	for b: Building in rail_stations("train_station"):
		var lk := station_link(b)
		if not lk.out and lk.peers == 0:
			continue
		var p := Vector2(b.center().x, b.center().z)
		var r := STATION_RADIUS
		for y in range(maxi(0, int(p.y - r)), mini(n, int(p.y + r) + 1)):
			for x in range(maxi(0, int(p.x - r)), mini(n, int(p.x + r) + 1)):
				var dd := Vector2(x + 0.5, y + 0.5).distance_to(p)
				if dd <= r:
					var i := idx(x, y)
					tcov[i] = max(tcov[i], clamp(1.2 * (1.0 - dd / r), 0.0, 1.0))
	transit_riders += int(rail_stats.riders)
	cov["transit"] = tcov
	transit_share = clamp(transit_riders / max(1.0, population * 0.6 + jobs * 0.2), 0.0, 0.65)


# ------------------------------------------------------------------ simulation
func tick_day() -> void:
	day += 1
	if sandbox:
		money = max(money, 9999999.0)
	if _roads_dirty:
		_recompute_roads()
	if _cov_dirty:
		_compute_coverage()
	if day % 3 == 0:
		_compute_fields()
	if day % 5 == 0:
		_compute_transit()
	_update_weather()
	_water_day()
	_update_mega()
	space.day(self)
	_check_awards()
	if day % 3 == 0:
		people.sync()
	_compute_utilities()
	_update_buildings()
	_compute_stats()
	_grow()
	_daily_budget()
	for i in n * n:
		if traffic[i] > 0.0:
			traffic[i] *= 0.92
	if day % Defs.DAYS_PER_MONTH == 0:
		_end_month()
	_check_milestones()
	if day % 2 == 0:
		_check_quests()
	day_passed.emit()


func _compute_coverage() -> void:
	for k in Defs.COVERS:
		var a := PackedFloat32Array(); a.resize(n * n); a.fill(0)
		cov[k] = a
		var sa := PackedInt32Array(); sa.resize(n * n); sa.fill(-1)
		cov_src[k] = sa
	for b: Building in buildings.values():
		if not b.is_service():
			continue
		var def: Dictionary = Defs.SERVICES[b.type]
		if not def.has("cover"):
			continue
		if b.emptying or b.is_full() or b.flooded or not b.done():
			continue
		var arr: PackedFloat32Array = cov[def.cover]
		var src: PackedInt32Array = cov_src[def.cover]
		var r: float = svc_radius(b)
		var strength: float = 1.0 if def.cat == "landmark" else clamp(0.7 + 0.3 * bud(def.cat), 0.8, 1.15)
		var c := b.center()
		for y in range(maxi(0, int(c.z - r)), mini(n, int(c.z + r) + 1)):
			for x in range(maxi(0, int(c.x - r)), mini(n, int(c.x + r) + 1)):
				var dd := Vector2(x + 0.5 - c.x, y + 0.5 - c.z).length()
				if dd > r:
					continue
				var v: float = clamp(1.25 * (1.0 - dd / r), 0.0, 1.0) * strength
				var i := idx(x, y)
				if v > arr[i]:
					arr[i] = v
					src[i] = b.id
		cov[def.cover] = arr
		cov_src[def.cover] = src
	_cov_dirty = false
	_compute_fields()


func _compute_fields() -> void:
	pollution.fill(0)
	noise.fill(0)
	for b: Building in buildings.values():
		var src := 0.0
		var rad := 0.0
		if b.type == "zone" and b.zone == Defs.IND and b.build_days == 0 and not b.abandoned:
			src = 0.35 + 0.12 * b.level
			rad = 4.0 + b.area() * 0.5
			var sp := ind_spec(b)
			if sp != "":
				src *= Defs.SPECS[sp].pol
			if bpol(b, "ind_filters"):
				src *= 0.6
		elif b.is_service() and Defs.SERVICES[b.type].has("pollution"):
			src = Defs.SERVICES[b.type].pollution
			rad = Defs.SERVICES[b.type].prad
		if src <= 0.0:
			continue
		var c := b.center()
		for y in range(maxi(0, int(c.z - rad)), mini(n, int(c.z + rad) + 1)):
			for x in range(maxi(0, int(c.x - rad)), mini(n, int(c.x + rad) + 1)):
				var dd := Vector2(x + 0.5 - c.x, y + 0.5 - c.z).length()
				if dd <= rad:
					var i := idx(x, y)
					pollution[i] = min(1.0, pollution[i] + src * (1.0 - dd / rad))
	# pedestrian paths nearby
	path_near.fill(0)
	for i in n * n:
		if path[i] == 0:
			continue
		var px := i % n
		var py := i / n
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var qx := px + dx
				var qy := py + dy
				if qx >= 0 and qy >= 0 and qx < n and qy < n:
					var j := qy * n + qx
					path_near[j] = minf(1.0, path_near[j] + (1.0 - (absi(dx) + absi(dy)) / 7.0) * 0.18)
	# overflowing sewers stink
	for i in n * n:
		if sew_spill[i] > 0.0:
			var sp := clampf(sew_spill[i] / 120.0, 0.1, 0.8)
			for d in [0, 1, -1, n, -n]:
				var j: int = i + d
				if j >= 0 and j < n * n:
					pollution[j] = minf(1.0, pollution[j] + sp * (1.0 if d == 0 else 0.5))
	# traffic noise and commercial noise
	for y in n:
		for x in n:
			var i := idx(x, y)
			var s := 0.0
			if road[i] > 0:
				s = clamp(traffic[i] / 25.0, 0.0, 1.0) * 0.7 + [0.0, 0.0, 0.12, 0.45][road[i]]
			elif rail[i] > 0:
				s = 0.3
			elif bld[i] != -1:
				var b: Building = buildings[bld[i]]
				if b.zone == Defs.C_HIGH or b.zone == Defs.C_LOW:
					s = 0.15 * b.level
			if s <= 0.02:
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var px := x + dx
					var py := y + dy
					if inb(px, py):
						var f: float = 1.0 - (abs(dx) + abs(dy)) / 5.0
						var j := idx(px, py)
						noise[j] = min(1.0, noise[j] + s * f * 0.5)
	# trees absorb pollution; land value
	var park: PackedFloat32Array = cov.park
	var fire: PackedFloat32Array = cov.fire
	var police: PackedFloat32Array = cov.police
	var health: PackedFloat32Array = cov.health
	var edu: PackedFloat32Array = cov.edu
	for i in n * n:
		if tree[i] == 1:
			pollution[i] *= 0.7
		var tp := Vector2i(i % n, i / n)
		var greening := has_policy("greening", tp)
		if greening:
			pollution[i] *= 0.8
		if has_policy("recycling", tp):
			pollution[i] *= 0.9
		if has_policy("truck_ban", tp):
			noise[i] *= 0.7
		if has_policy("tourism", tp):
			noise[i] = min(1.0, noise[i] * 1.2 + 0.03)
		var lv := 28.0 + (6.0 if greening else 0.0) + park[i] * 30.0 + (fire[i] + police[i] + health[i]) * 8.0 + edu[i] * 12.0
		lv += water_near[i] * 14.0 + tree[i] * 3.0 + (cov.transit as PackedFloat32Array)[i] * 10.0 + path_near[i] * 7.0
		lv -= pollution[i] * 50.0 + noise[i] * 18.0
		land_value[i] = clamp(lv, 0.0, 100.0)


## Deepest water cell next to a building (pumps, outlets, hydro plants), -1 if none.
func water_cell(b: Building) -> int:
	var best := -1
	var bd := 0.0
	for y in range(b.y - 1, b.y + b.sy + 1):
		for x in range(b.x - 1, b.x + b.sx + 1):
			if not inb(x, y) or b.rect().has_point(Vector2i(x, y)):
				continue
			var i := idx(x, y)
			var dd := water_sim.d[i] if water_sim else (1.0 if terrain[i] == 1 else 0.0)
			if dd > bd:
				bd = dd
				best = i
	return best


## Daily link between the city and the water physics: pumps drain water, outlets
## discharge sewage, rain and floods raise rivers, flooded buildings stop working.
func _water_day() -> void:
	if water_sim == null:
		return
	water_sim.surge = flood_surge + (0.03 if weather == "rain" else 0.0)
	water_sim.rain = 0.00015 if weather == "rain" else 0.0
	if not water_driven:
		water_sim.sweep()
		water_sim.sweep()
	water_sim.inject.clear()
	water_sim.drain.clear()
	for b: Building in buildings.values():
		if not b.is_service() or not b.has_road or b.collapsed:
			continue
		var def: Dictionary = Defs.SERVICES[b.type]
		if not def.get("need_water", false):
			continue
		var wc := water_cell(b)
		if wc < 0:
			b.eff = 0.0
			continue
		if def.has("water"):
			var want: float = def.water * bud(def.cat) * 0.000006
			var got: float = water_sim.drained.get(wc, want)
			b.eff = clampf(got / want, 0.0, 1.0) if want > 0.0 else 1.0
			water_sim.drain[wc] = water_sim.drain.get(wc, 0.0) + want
		if def.has("sewage"):
			var c: float = def.get("wpol", 1.0) * (0.45 if bpol(b, "sewage_filter") else 1.0) * 6.0
			var vol := b.sew_in * 0.000008
			if vol > 0.0:
				var old: Array = water_sim.inject.get(wc, [0.0, 0.0])
				var tot: float = old[0] + vol
				water_sim.inject[wc] = [tot, (old[0] * old[1] + vol * c) / tot]
		if b.type == "hydro":
			var sp := 0.0
			var cnt := 0
			for y in range(b.y - 1, b.y + b.sy + 1):
				for x in range(b.x - 1, b.x + b.sx + 1):
					if inb(x, y) and water_sim.d[idx(x, y)] > 0.1:
						sp += water_sim.speed(idx(x, y))
						cnt += 1
			b.eff = clampf((sp / maxf(cnt, 1)) / 0.025, 0.15, 1.5) if cnt > 0 else 0.0
	# pollution of water: carried by the flow; polluted ground leaks into it
	for i in n * n:
		var dd := water_sim.d[i]
		if dd > WaterSim.DRY:
			if pollution[i] > 0.05:
				water_sim.pm[i] = minf(water_sim.pm[i] + dd * pollution[i] * 0.03, dd)
			water_pol[i] = water_sim.conc(i)
		else:
			water_pol[i] = 0.0
	# floods
	flooded_count = 0
	for b: Building in buildings.values():
		var deep := 0.0
		for t in b.tiles():
			var i := idx(t.x, t.y)
			if terrain[i] == 0:
				deep = maxf(deep, water_sim.d[i])
		var was := b.flooded
		b.flooded = deep > 0.06 and not b.type in ["outlet", "pump", "watertreat", "sewtreat", "hydro", "port"]
		if b.flooded:
			b.flooded_days += 1
			flooded_count += 1
		else:
			b.flooded_days = 0
		if was != b.flooded:
			_cov_dirty = true
			building_updated.emit(b)
	if flooded_count > 0:
		_notify_once("flood", "🌊 Затоплено зданий: %d. Поднимите берег или постройте дамбу (инструмент «Поднять землю»)." % flooded_count, "bad", 10)


func _consumption(b: Building) -> Vector2:
	if b.type != "zone" or b.build_days > 0 or b.abandoned or b.collapsed:
		return Vector2.ZERO
	var z: Dictionary = Defs.ZONES[b.zone]
	var f := b.area() * (1.0 + (b.level - 1) * 0.5) * 0.6
	if bpol(b, "green_energy"):
		f *= 0.8
	var pw := f
	if season() == 0:
		pw *= 1.15
	return Vector2(z.power * pw, z.water * f)


func _compute_utilities() -> void:
	var psup := {}
	var wsup := {}
	var wdirty := {}
	power_supply = 0; water_supply = 0; power_demand = 0; water_demand = 0
	sewage_supply = 0; sewage_demand = 0
	for b: Building in buildings.values():
		if not b.is_service() or not b.has_road:
			continue
		var def: Dictionary = Defs.SERVICES[b.type]
		var c := road_comp[idx(b.access.x, b.access.y)]
		if def.has("power"):
			var pv := svc_output(b, "power")
			psup[c] = psup.get(c, 0.0) + pv
			power_supply += pv
		if def.has("water"):
			var wv := svc_output(b, "water")
			wsup[c] = wsup.get(c, 0.0) + wv
			water_supply += wv
			if pump_dirty(b) > 0.25:
				wdirty[c] = wdirty.get(c, 0.0) + wv
		if def.has("sewage"):
			sewage_supply += svc_output(b, "sewage")
	# neighbours supply the shortfall (deals in the region window)
	var oc := outside_comp
	var p_imp := region.power_cap() if region.deals.get("buy_power", false) and oc >= 0 else 0.0
	var w_imp := region.water_cap() if region.deals.get("buy_water", false) and oc >= 0 else 0.0
	if p_imp > 0.0:
		psup[oc] = psup.get(oc, 0.0) + p_imp
	if w_imp > 0.0:
		wsup[oc] = wsup.get(oc, 0.0) + w_imp
	dirty_comp.clear()
	for c in wdirty:
		dirty_comp[c] = wdirty[c] / max(1.0, wsup[c])
	power.fill(0)
	water.fill(0)
	sewage.fill(0)
	var ids := buildings.keys()
	ids.sort()
	var sew_need := {}
	for id in ids:
		var b: Building = buildings[id]
		if b.is_service():
			continue
		var need := _consumption(b)
		if b.flooded:
			need = Vector2.ZERO
		power_demand += need.x
		water_demand += need.y
		var c := road_comp[idx(b.access.x, b.access.y)] if b.has_road else -2
		var pav: float = psup.get(c, 0.0)
		var wav: float = wsup.get(c, 0.0)
		sewage_demand += need.y
		sew_need[b] = need.y
		b.powered = b.has_road and pav >= need.x and pav > 0.0 and not b.flooded
		b.watered = b.has_road and wav >= need.y and wav > 0.0 and not b.flooded
		if b.powered:
			psup[c] = pav - need.x
		if b.watered:
			wsup[c] = wav - need.y
		var pv := 1 if b.powered else 2
		var wv := 1 if b.watered else 2
		for t in b.tiles():
			power[idx(t.x, t.y)] = pv
			water[idx(t.x, t.y)] = wv
	_compute_sewers(sew_need)
	region.used.power_in = clampf(p_imp - psup.get(oc, 0.0), 0.0, p_imp) if p_imp > 0.0 else 0.0
	region.used.water_in = clampf(w_imp - wsup.get(oc, 0.0), 0.0, w_imp) if w_imp > 0.0 else 0.0
	region.used.power_out = maxf(power_supply - power_demand, 0.0) if region.deals.get("sell_power", false) and oc >= 0 else 0.0
	region.used.water_out = maxf(water_supply - water_demand, 0.0) if region.deals.get("sell_water", false) and oc >= 0 else 0.0
	for i in n * n:
		if road[i] > 0:
			var c := road_comp[i]
			if psup.has(c):
				power[i] = 3
			if wsup.has(c):
				water[i] = 3
	for b: Building in buildings.values():
		if b.is_service():
			for t in b.tiles():
				power[idx(t.x, t.y)] = 1
				water[idx(t.x, t.y)] = 1
				sewage[idx(t.x, t.y)] = 1


## Sewage physics: every building's sewage enters the pipe under its road and flows
## along the shortest pipe route to the nearest outlet. Pipes have a capacity (bigger
## under avenues); overloaded pipes and outlets back up and overflow onto the street.
## Rain adds storm water to the pipes.
func _compute_sewers(need: Dictionary) -> void:
	var cnt := n * n
	var parent := PackedInt32Array(); parent.resize(cnt); parent.fill(-2)
	var acc := PackedFloat32Array(); acc.resize(cnt); acc.fill(0)
	var share := PackedFloat32Array(); share.resize(cnt); share.fill(0)
	sew_load.fill(0)
	sew_spill.fill(0)
	sew_overflow = 0.0
	var order: Array[int] = []
	var root_cap := {}       # root road tile -> outlet capacity
	var root_out := {}       # root road tile -> [outlets]
	for b: Building in buildings.values():
		b.sew_in = 0.0
		if not b.is_service() or not b.has_road or not Defs.SERVICES[b.type].has("sewage"):
			continue
		var r := idx(b.access.x, b.access.y)
		root_cap[r] = root_cap.get(r, 0.0) + svc_output(b, "sewage")
		if not root_out.has(r):
			root_out[r] = []
			parent[r] = -1
			order.append(r)
		root_out[r].append(b)
	# multi-source BFS through the pipe network (= road network)
	var head := 0
	while head < order.size():
		var c := order[head]; head += 1
		var x := c % n
		for j in [c - 1 if x > 0 else -1, c + 1 if x < n - 1 else -1, c - n, c + n]:
			if j >= 0 and j < cnt and parent[j] == -2 and road[j] > 0:
				parent[j] = c
				order.append(j)
	# collect sewage (and storm water when it rains)
	var storm := 0.25 if weather == "rain" else 0.0
	for b: Building in need:
		if b.has_road:
			var a := idx(b.access.x, b.access.y)
			acc[a] += need[b]
	if storm > 0.0:
		for c in order:
			acc[c] += storm
	# flows run downstream: accumulate from the far ends towards the outlets
	for k in range(order.size() - 1, -1, -1):
		var c := order[k]
		var cap: float = SEWER_CAP[road[c]]
		var f := acc[c]
		sew_load[c] = f / cap
		if f > cap:
			sew_spill[c] = f - cap
			sew_overflow += f - cap
			f = cap
		if parent[c] >= 0:
			acc[parent[c]] += f
		else:
			acc[c] = f
	# share of sewage that reaches an outlet, from the outlets upstream
	for c in order:
		var cap: float = SEWER_CAP[road[c]]
		var own := minf(1.0, 1.0 / maxf(sew_load[c], 0.001))
		if parent[c] < 0:
			var oc: float = root_cap[c]
			var got := acc[c]
			var ok := minf(1.0, oc / maxf(got, 0.001))
			for o: Building in root_out[c]:
				o.sew_in = minf(got, oc) * svc_output(o, "sewage") / maxf(oc, 0.001)
			if got > oc:
				sew_overflow += got - oc
			share[c] = own * ok
		else:
			share[c] = own * share[parent[c]]
		sewage[c] = 3
	for b: Building in need:
		var a := idx(b.access.x, b.access.y) if b.has_road else -1
		b.sew_pass = share[a] if a >= 0 and parent[a] != -2 else 0.0
		b.sewered = b.has_road and b.sew_pass >= 0.7 and not b.flooded
		var sv := 1 if b.sewered else 2
		for t in b.tiles():
			sewage[idx(t.x, t.y)] = sv


func avg_cover(b: Building, k: String) -> float:
	var arr: PackedFloat32Array = cov[k]
	var s := 0.0
	for t in b.tiles():
		s += arr[idx(t.x, t.y)]
	return s / b.area()


func avg_field(b: Building, arr: PackedFloat32Array) -> float:
	var s := 0.0
	for t in b.tiles():
		s += arr[idx(t.x, t.y)]
	return s / b.area()


func _target_level(b: Building, lv: float) -> int:
	var t := _target_level_raw(b, lv)
	if bpol(b, "high_rise_ban") and b.zone in [Defs.R_HIGH, Defs.C_HIGH, Defs.OFFICE]:
		t = mini(t, 2)
	return t


func _target_level_raw(b: Building, lv: float) -> int:
	var edu := avg_cover(b, "edu") + (0.15 if bpol(b, "edu_boost") else 0.0)
	var health := avg_cover(b, "health")
	match b.zone:
		Defs.R_LOW, Defs.R_HIGH:
			if lv >= 62 and edu >= 0.45 and health >= 0.15: return 3
			if lv >= 42 and edu >= 0.2: return 2
		Defs.C_LOW, Defs.C_HIGH:
			if lv >= 58 and population > 800: return 3
			if lv >= 38: return 2
		Defs.IND, Defs.AGRI:
			if ind_spec(b) != "":
				# raw-material industry needs land value, not education
				if lv >= 50: return 3
				if lv >= 34: return 2
				return 1
			if edu >= 0.45: return 3
			if edu >= 0.2: return 2
		Defs.OFFICE:
			if lv >= 60 and edu >= 0.55: return 3
			if lv >= 42 and edu >= 0.3: return 2
	return 1


func _update_buildings() -> void:
	_walk_acc = Vector2.ZERO
	_garbage_out = 0.0
	var to_remove: Array = []
	var garbage_cov: PackedFloat32Array = cov.garbage
	var garbage_src: PackedInt32Array = cov_src.garbage
	var death_cov: PackedFloat32Array = cov.death
	var death_src: PackedInt32Array = cov_src.death
	var deaths_on := milestone >= 1
	var sewage_on := milestone >= 1
	_update_storage()
	for b: Building in buildings.values():
		if b.is_service():
			continue
		var changed := false
		var old_problems := b.problems.duplicate()
		if b.build_days > 0:
			b.build_days -= 1
			if b.build_days == 0:
				building_updated.emit(b)
			continue
		# fire
		if b.fire > 0:
			b.fire -= 1
			if b.fire_dispatched == false:
				_dispatch_fire(b)
			# spread
			if rng.randf() < 0.03:
				_spread_fire(b)
			if b.fire == 0:
				to_remove.append(b)
				_notify_once("burn", "🔥 Здание сгорело дотла: %s" % b.display_name(), "bad", 8)
			continue
		if not b.abandoned:
			var fc := avg_cover(b, "fire")
			var p := 0.00004 + 0.00035 * pow(1.0 - fc, 2.0) * (0.6 + 0.4 * b.level)
			if b.zone == Defs.IND:
				p *= 1.6
			if weather == "rain":
				p *= 0.3
			if rng.randf() < p:
				_ignite(b)
				continue
		var lv := avg_field(b, land_value)
		var pol := avg_field(b, pollution)
		var noi := avg_field(b, noise)
		b.problems.clear()
		if b.collapsed:
			b.abandoned_days += 1
			var fast := avg_cover(b, "rescue") > 0.05
			if b.abandoned_days > (6 if fast else 40):
				to_remove.append(b)
			continue
		if b.abandoned:
			b.abandoned_days += 1
			b.problems.append("abandoned")
			if b.abandoned_days > (3 if auto_demolish else 45):
				to_remove.append(b)
			if b.problems != old_problems:
				building_updated.emit(b)
			continue
		# flood water standing in the building
		if b.flooded:
			b.problems.append("flood")
			if b.flooded_days > 12 and rng.randf() < 0.15:
				collapse_building(b)
				log_event("disaster", "Наводнение разрушило здание", "%s не выдержало многодневного затопления." % b.display_name())
				continue
		# utilities
		if not b.has_road:
			b.problems.append("noroad")
		if not b.powered:
			b.no_power_days += 1
			b.problems.append("power")
		else:
			b.no_power_days = 0
		if not b.watered:
			b.no_water_days += 1
			b.problems.append("water")
		else:
			b.no_water_days = 0
		if not b.sewered and sewage_on:
			b.no_sewage_days += 1
			if b.no_sewage_days > 3:
				b.problems.append("sewage")
		else:
			b.no_sewage_days = 0
		var ai := idx(b.access.x, b.access.y)
		var dirty: bool = b.watered and b.has_road and dirty_comp.get(road_comp[ai], 0.0) > 0.3
		if dirty:
			b.problems.append("dirtywater")
		# garbage: collected garbage goes to the service that covers the building
		var gc: float = garbage_cov[ai] if b.has_road else 0.0
		var gen := 0.25 * b.level * (1.0 if population > 250 else 0.2) * (0.5 if bpol(b, "recycling") else 1.0)
		if gc > 0.15:
			var took: float = min(b.garbage, 3.0) + gen
			b.garbage = max(0.0, b.garbage - 3.0)
			var gs: Building = buildings.get(garbage_src[ai])
			if gs and gs.store_cap() > 0.0:
				gs.stored += took
		elif region.deals.get("garbage", false) and b.has_road and road_comp[ai] == outside_comp:
			_garbage_out += b.garbage + gen
			b.garbage = 0.0
		else:
			b.garbage += gen
		if b.garbage > 30:
			b.problems.append("garbage")
		# deathcare
		if deaths_on and b.kind() == "r" and b.occ > 0:
			var rate: float = 0.00035 + pol * 0.0008 + (1.0 - min(1.0, avg_cover(b, "health"))) * 0.00025
			var before := floorf(b.dead)
			b.dead += b.occ * rate
			if floorf(b.dead) > before:
				b.occ = maxi(0, b.occ - 1)
				people.die_in(b)
		if b.dead >= 1.0:
			var dc: float = death_cov[ai] if b.has_road else 0.0
			var ds: Building = buildings.get(death_src[ai]) if dc > 0.1 else null
			if ds:
				var nd := floorf(b.dead)
				deaths_month += int(nd)
				if ds.store_cap() > 0.0:
					ds.stored += nd
				b.dead -= nd
				b.dead_days = 0
			else:
				b.dead_days += 1
				if b.dead_days > 3:
					b.problems.append("dead")
		else:
			b.dead_days = 0
		# raw materials run out
		var sp := ind_spec(b)
		if sp != "":
			var sr := spec_resource(b, sp)
			if sr < 0.05:
				var had := false
				for t in b.tiles():
					if resource[idx(t.x, t.y)] == Defs.SPECS[sp].res:
						had = true
				b.problems.append("depleted" if had and Defs.SPECS[sp].deplete else "nores")
			elif Defs.SPECS[sp].deplete and b.occ > 0:
				for t in b.tiles():
					var ti := idx(t.x, t.y)
					if resource[ti] == Defs.SPECS[sp].res:
						res_amt[ti] = max(0.0, res_amt[ti] - 0.0012 * b.level)
		elif b.zone == Defs.IND and goods.sell < 0.85 and b.seed % 3 == 0:
			b.problems.append("nobuyers")
		# happiness
		var k := b.kind()
		var h := 52.0
		h += 12.0 * avg_cover(b, "fire") + 12.0 * avg_cover(b, "police") + 12.0 * avg_cover(b, "health")
		if k == "r":
			h += 8.0 * avg_cover(b, "edu") + 10.0 * avg_cover(b, "park") + 5.0 * avg_cover(b, "transit")
			h -= 45.0 * pol + 18.0 * noi
			h -= (taxes.r - 9) * 2.5
		elif k == "c":
			h -= 20.0 * pol
			h -= (taxes.c - 9) * 2.5
			if demand.c < 5 and b.occ < b.cap * 0.5:
				h -= 10
		else:
			h -= 5.0 * pol
			h -= ((taxes.o if b.zone == Defs.OFFICE else taxes.i) - 9) * 2.5
		h += (lv - 40.0) * 0.2
		if k == "r" and bpol(b, "smoke_ban"): h += 5
		if bpol(b, "high_rise_ban"): h += 3
		if not b.powered: h -= 30
		if not b.watered: h -= 30
		if not b.has_road: h -= 40
		if b.garbage > 30: h -= 15
		if "sewage" in b.problems: h -= 22
		if b.flooded: h -= 35
		if space.crew_days > 0: h += 3
		if space.mourn_days > 0: h -= 3
		if mansion_awarded and _has_building("mansion"): h += 3
		if k == "r":
			# walkable neighbourhood: paths and parks nearby make people walk instead of drive
			var walk := clampf(avg_field(b, path_near) + avg_cover(b, "park") * 0.4, 0.0, 1.0)
			h += 6.0 * walk
			_walk_acc += Vector2(walk * maxi(b.occ, 1), maxi(b.occ, 1))
		if "dead" in b.problems: h -= 20
		if dirty:
			h -= 12
			if k == "r" and not "sick" in b.problems:
				b.problems.append("sick")
		var cg := congestion(idx(b.access.x, b.access.y)) if b.has_road else 0.0
		if cg > 1.0:
			b.problems.append("traffic")
			h -= 6.0 * (min(cg, 2.0) - 0.4)
			_notify_once("traffic", "🚗 Пробки! Жители опаздывают на работу. Стройте проспекты и общественный транспорт.", "bad", 45)
		if k == "r" and pol > 0.35 and avg_cover(b, "health") < 0.2:
			b.problems.append("sick")
			h -= 10
		if k == "r" and _near_casino(b) and avg_cover(b, "police") < 0.5 and b.seed % 3 == 0:
			b.problems.append("crime")
			h -= 6
		elif k == "r" and avg_cover(b, "police") < 0.05 and population > 600 and not bpol(b, "watch"):
			if b.seed % 4 == 0:
				b.problems.append("crime")
				h -= 8
		b.happiness = lerp(b.happiness, clamp(h, 0.0, 100.0), 0.25)
		if b.happiness < 18:
			b.unhappy_days += 1
		else:
			b.unhappy_days = max(0, b.unhappy_days - 1)
		# abandonment
		if b.no_power_days > 70 or b.no_water_days > 70 or b.no_sewage_days > 90 or b.dead_days > 60 or b.unhappy_days > 45 or (not b.has_road and rng.randf() < 0.05):
			b.abandoned = true
			b.occ = 0
			b.abandoned_days = 0
			b.problems = ["abandoned"]
			_notify_once("abandon", "🏚 Жители покидают дома: проверьте услуги и коммунальные сети.", "bad", 20)
			building_updated.emit(b)
			continue
		# occupancy
		if k == "r":
			var utils: bool = b.powered and b.watered
			if demand.r > 8 and b.occ < b.cap and (utils or rng.randf() < 0.3):
				b.occ = mini(b.cap, b.occ + maxi(1, int(ceil(b.cap * (0.12 if utils else 0.06)))))
			elif (demand.r < 3 or b.happiness < 30) and b.occ > 0 and rng.randf() < 0.15:
				b.occ -= 1
		# leveling
		if (day + b.id) % 7 == 0:
			var tl := _target_level(b, lv)
			if tl > b.level and b.happiness > 45 and b.powered and b.watered and rng.randf() < 0.4:
				b.level += 1
				if not b.style_lock:
					b.style = style_at(Vector2i(b.x, b.y))
				b.cap = _calc_cap(b)
				b.build_days = 3
				changed = true
				if b.level == 3:
					_notify_once("lvl3", "⭐ Здания достигают максимального уровня!", "good", 60)
		if changed or b.problems != old_problems:
			building_updated.emit(b)
		# notification for problems
		if "power" in b.problems and b.no_power_days > 5:
			_notify_once("power", "⚡ Горожане без электричества! Постройте электростанцию и соедините её дорогой.", "bad", 25)
		if "water" in b.problems and b.no_water_days > 5:
			_notify_once("water", "💧 В домах нет воды! Нужна насосная станция или водонапорная башня.", "bad", 25)
		if "garbage" in b.problems:
			_notify_once("garbage", "🗑 Мусор копится на улицах. Постройте полигон отходов.", "bad", 40)
		if "sick" in b.problems:
			if dirty:
				_notify_once("dirtywater", "🚱 Из кранов течёт грязная вода! Насосная станция забирает воду рядом со стоком.", "bad", 40)
			else:
				_notify_once("sick", "🤒 Жители болеют из-за загрязнения. Нужна поликлиника.", "bad", 40)
		if "sewage" in b.problems:
			_notify_once("sewage", "🚽 Канализация переполнена! Постройте канализационный сток у воды.", "bad", 25)
		if "dead" in b.problems:
			_notify_once("dead", "⚰ Умерших некому забрать. Постройте кладбище или крематорий.", "bad", 30)
		if "depleted" in b.problems:
			_notify_once("depleted", "⛏ Месторождение истощилось. Предприятия теряют доход — смените специализацию района.", "bad", 90)
		if "crime" in b.problems:
			_notify_once("crime", "🚨 Растёт преступность. Нужен полицейский участок.", "bad", 40)
	for b in to_remove:
		remove_building(b, "collapse")


var _full_ids := {}


## Landfills and cemeteries fill up; emptying moves the contents to incinerators / crematoriums.
func _update_storage() -> void:
	var proc := {}
	for b: Building in buildings.values():
		if b.is_service() and b.has_road and Defs.SERVICES[b.type].get("process", false):
			proc[Defs.SERVICES[b.type].cover] = true
	for b: Building in buildings.values():
		var cap := b.store_cap()
		if cap <= 0.0:
			continue
		var cv: String = Defs.SERVICES[b.type].cover
		if b.emptying:
			if proc.has(cv):
				b.stored = max(0.0, b.stored - cap * 0.02 * bud(svc_cat(b)))
				if b.stored <= 0.0:
					b.emptying = false
					_cov_dirty = true
					_notify_once("emptied_%d" % b.id, "✅ %s опустошён(о) и снова принимает." % Defs.SERVICES[b.type].name, "good", 5)
					building_updated.emit(b)
			else:
				_notify_once("noproc_%s" % cv, "%s Некуда вывозить: нужен %s." % ["🗑" if cv == "garbage" else "⚰", "мусоросжигательный завод или центр переработки" if cv == "garbage" else "крематорий"], "bad", 30)
		var full := b.is_full()
		if full and not _full_ids.has(b.id):
			_full_ids[b.id] = true
			_cov_dirty = true
			_notify_once("full_%s" % cv, "%s %s переполнен(о)! Постройте новое или опустошите его." % ["🗑" if cv == "garbage" else "⚰", Defs.SERVICES[b.type].name], "bad", 20)
			building_updated.emit(b)
		elif not full and _full_ids.has(b.id):
			_full_ids.erase(b.id)
			_cov_dirty = true


func ignite(b: Building) -> void:
	_ignite(b)


func _ignite(b: Building) -> void:
	if b.fire > 0 or b.is_service() or b.build_days > 0 or b.collapsed:
		return
	b.fire = 14
	b.fire_dispatched = false
	b.problems = ["fire"]
	building_updated.emit(b)
	_notify_once("fire", "🔥 Пожар! %s горит." % b.display_name(), "bad", 5)
	_dispatch_fire(b)


func _dispatch_fire(b: Building) -> void:
	if avg_cover(b, "fire") <= 0.02 or not b.has_road:
		return
	var best: Building = null
	var bd := 1e9
	for s: Building in buildings.values():
		if s.type == "fire" and s.has_road and road_comp[idx(s.access.x, s.access.y)] == road_comp[idx(b.access.x, b.access.y)]:
			var dd := s.center().distance_to(b.center())
			if dd < bd:
				bd = dd; best = s
	if best:
		b.fire_dispatched = true
		dispatch.emit("fire", best, b)


func _spread_fire(b: Building) -> void:
	var c := b.center()
	for dd in Defs.DIRS:
		var p := Vector2i(int(c.x) + dd.x * (b.sx / 2 + 1), int(c.z) + dd.y * (b.sy / 2 + 1))
		var o := building_at(p)
		if o and o != b and rng.randf() < 0.5:
			_ignite(o)
			return


## Destroys a building, leaving ruins. Returns affected residents.
func collapse_building(b: Building) -> int:
	if not buildings.has(b.id) or b.collapsed:
		return 0
	if b.is_service():
		notify.emit("💥 Разрушено: %s! Постройте заново." % Defs.SERVICES[b.type].name, "bad")
		remove_building(b, "collapse")
		return 0
	var hurt := b.occ
	var rescue := avg_cover(b, "rescue") > 0.05
	casualties += int(hurt * (0.05 if rescue else 0.3))
	b.collapsed = true
	b.abandoned = true
	b.fire = 0
	b.occ = 0
	b.abandoned_days = 0
	b.build_days = 0
	b.problems = []
	building_updated.emit(b)
	return hurt


## Meteor crater: removes everything in radius and lowers the terrain.
func crater(center: Vector2, radius: float) -> void:
	var removed_roads: Array = []
	for y in range(maxi(0, floori(center.y - radius)), mini(n, ceili(center.y + radius) + 1)):
		for x in range(maxi(0, floori(center.x - radius)), mini(n, ceili(center.x + radius) + 1)):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) > radius:
				continue
			var i := idx(x, y)
			if bld[i] != -1 and buildings.has(bld[i]):
				var b: Building = buildings[bld[i]]
				casualties += int(b.occ * 0.5)
				remove_building(b, "collapse")
			if road[i] > 0 and Vector2i(x, y) != outside:
				_set_road(Vector2i(x, y), false)
				removed_roads.append(Vector2i(x, y))
			tree[i] = 0
			zone[i] = 0
	for cy in range(maxi(0, floori(center.y - radius)), mini(n, ceili(center.y + radius)) + 1):
		for cx in range(maxi(0, floori(center.x - radius)), mini(n, ceili(center.x + radius)) + 1):
			var dd := Vector2(cx, cy).distance_to(center)
			if dd < radius and not _corner_locked(Vector2i(cx, cy), -1):
				var k := 1.0 - (dd / radius) * (dd / radius)
				_set_hc(cx, cy, hc(cx, cy) - 0.9 * k)
	var r := Rect2i(floori(center.x - radius) - 1, floori(center.y - radius) - 1, ceili(radius * 2) + 3, ceili(radius * 2) + 3)
	_update_water_flags(r)
	_recompute_roads()
	if removed_roads.size() > 0:
		roads_changed.emit(removed_roads)
		_validate_lines()
	terrain_changed.emit(r)
	zones_changed.emit()
	trees_changed.emit()
	_cov_dirty = true


func extinguish(b: Building) -> void:
	if buildings.has(b.id) and b.fire > 0:
		b.fire = 0
		b.fire_dispatched = false
		b.problems.clear()
		b.happiness = max(10.0, b.happiness - 15.0)
		building_updated.emit(b)
		_notify_once("ext", "🚒 Пожарные потушили пожар.", "good", 20)


func _compute_stats() -> void:
	if _walk_acc.y > 0.0:
		walk_share = lerpf(walk_share, clampf(_walk_acc.x / _walk_acc.y * 0.4, 0.0, 0.4), 0.2)
	population = 0
	jobs = 0
	var hsum := 0.0
	var hcnt := 0
	var ccap := 0
	for b: Building in buildings.values():
		if b.is_service() or b.build_days > 0 and b.level == 1 or b.abandoned:
			continue
		if b.kind() == "r":
			population += b.occ
			hsum += b.happiness * max(1, b.occ)
			hcnt += max(1, b.occ)
		else:
			jobs += b.cap
			if b.kind() == "c":
				ccap += b.cap
	# megaproject housing (arcology)
	for b: Building in buildings.values():
		if b.is_service() and b.done() and Defs.SERVICES[b.type].has("residents"):
			population += Defs.SERVICES[b.type].residents
			hsum += 80.0 * Defs.SERVICES[b.type].residents
			hcnt += Defs.SERVICES[b.type].residents
	_compute_goods()
	working_pop = int(population * 0.58)
	employed = mini(working_pop, jobs)
	unemployment = float(working_pop - employed) / max(1, working_pop)
	avg_happiness = hsum / hcnt if hcnt > 0 else 60.0
	region.used.garbage = lerpf(region.used.garbage, _garbage_out * 0.1 * Defs.DAYS_PER_MONTH, 0.15)
	var commuters := 0
	if region.deals.get("workers", false):
		commuters = mini(maxi(jobs - working_pop, 0), region.workers_cap())
	region.used.workers = commuters
	# fill workplaces according to available workers (+ commuters from outside)
	var share: float = clamp(float(working_pop + 20 + commuters) / max(1, jobs), 0.0, 1.0)
	for b: Building in buildings.values():
		if b.is_service() or b.kind() == "r" or b.abandoned:
			continue
		b.occ = int(round(b.cap * share)) if b.build_days == 0 or b.level > 1 else 0
	# demand
	var wp: float = max(working_pop, 25)
	var tr: float = 35.0 + (jobs - working_pop) / wp * 55.0 - unemployment * 70.0 + (avg_happiness - 50.0) * 0.6 - (taxes.r - 9) * 4.0
	if population < 60:
		tr = max(tr, 70.0)
	var need_c := population * 0.22 + 10
	var tc: float = (need_c - ccap) / max(need_c, 20.0) * 110.0 + 5.0 - (taxes.c - 9) * 4.0
	var ti: float = (working_pop - jobs) / wp * 100.0 + 25.0 - (taxes.i - 9) * 4.0
	if goods.sell < 0.85:
		ti -= (0.85 - goods.sell) * 60.0
	if population < 60:
		ti = max(ti, 50.0)
	for b: Building in buildings.values():
		if b.is_service() and b.has_road and (b.type != "cargo_station" or station_link(b).out):
			tc += Defs.SERVICES[b.type].get("dem_c", 0.0)
			ti += Defs.SERVICES[b.type].get("dem_i", 0.0)
	tr += 8.0 * subsidy("housing")
	tc += 8.0 * subsidy("business")
	ti += 7.0 * subsidy("industry") + 4.0 * subsidy("tech")
	demand.r = lerp(float(demand.r), clamp(tr, 0.0, 100.0), 0.2)
	demand.c = lerp(float(demand.c), clamp(tc, 0.0, 100.0), 0.2)
	demand.i = lerp(float(demand.i), clamp(ti, 0.0, 100.0), 0.2)


## Goods chain: specialized industry -> raw materials -> generic industry -> goods -> shops.
func _compute_goods() -> void:
	var gen := 0.0
	var spec := 0.0
	var agri := 0.0
	var com := 0.0
	var ecap := 0.0
	var esum := 0.0
	var ecnt := 0
	for b: Building in buildings.values():
		if b.abandoned or b.collapsed:
			continue
		if b.is_service():
			if b.has_road and (b.type != "cargo_station" or station_link(b).out):
				ecap += Defs.SERVICES[b.type].get("export_cap", 0)
			continue
		match b.zone:
			Defs.IND:
				if ind_spec(b) != "": spec += b.occ
				else: gen += b.occ
			Defs.AGRI: agri += b.occ
			Defs.C_LOW, Defs.C_HIGH: com += b.occ
			Defs.R_LOW, Defs.R_HIGH:
				esum += avg_cover(b, "edu") * b.occ
				ecnt += b.occ
	edu_level = clamp(esum / max(1, ecnt), 0.0, 1.0)
	for b: Building in buildings.values():
		if b.is_service() and b.done():
			edu_level = minf(1.0, edu_level + Defs.SERVICES[b.type].get("edu_bonus", 0.0))
	if has_ministry("edu"):
		edu_level = minf(1.0, edu_level + 0.1)
	if has_ministry("science"):
		edu_level = minf(1.0, edu_level + 0.05)
	if space.station_ready():
		edu_level = minf(1.0, edu_level + 0.05)
	var prod := gen * 1.0 + agri * 0.6
	var need := com * 0.9
	var export_cap := 60.0 + prod * 0.3 + ecap
	goods = {"prod": prod, "need": need, "raw_prod": spec * 1.4 + agri * 0.4, "raw_need": gen * 0.5, "export_cap": export_cap,
		"import": clamp((need - prod) / max(need, 1.0), 0.0, 1.0),
		"sell": clamp((need + export_cap) / max(prod, 1.0), 0.0, 1.0)}


var _cands := {}
var _cands_dirty := true


func _grow() -> void:
	if outside_comp < 0:
		_notify_once("nooutside", "🛣 Город отрезан от внешнего мира! Восстановите дорогу к шоссе.", "bad", 30)
		return
	if _cands_dirty or day % 15 == 0:
		_rebuild_candidates()
	var cands := _cands
	for k in ["r", "c", "i"]:
		var list: Array = cands[k]
		var keep: Array = []
		for c in list:
			if bld[idx(c.x, c.y)] == -1 and zone[idx(c.x, c.y)] != 0:
				keep.append(c)
		cands[k] = keep
	_grow_from(cands)


func _rebuild_candidates() -> void:
	_cands_dirty = false
	var cands := {"r": [], "c": [], "i": []}
	for y in n:
		for x in n:
			var i := idx(x, y)
			var z := zone[i]
			if z == 0 or bld[i] != -1 or road_dist[i] != 1:
				continue
			for d in 4:
				var q: Vector2i = Vector2i(x, y) + Defs.DIRS[d]
				if is_local_road(q) and road_comp[idx(q.x, q.y)] == outside_comp:
					cands[Defs.zone_kind(z)].append(Vector3i(x, y, d))
					break
	_cands = cands


func _grow_from(cands: Dictionary) -> void:
	for k in ["r", "c", "i"]:
		var list: Array = cands[k]
		if list.is_empty():
			continue
		var dem: float = demand[k]
		var attempts := int(dem / 22.0)
		if rng.randf() < fmod(dem / 22.0, 1.0):
			attempts += 1
		for a in attempts:
			var c: Vector3i = list[rng.randi() % list.size()]
			var i := idx(c.x, c.y)
			if bld[i] != -1:
				continue
			# offices need educated workers, factories prefer uneducated ones
			if zone[i] == Defs.OFFICE and rng.randf() > clamp(0.25 + edu_level * 1.3, 0.25, 1.0):
				continue
			if zone[i] == Defs.IND and rng.randf() > clamp(1.35 - edu_level, 0.45, 1.0):
				continue
			_try_lot(Vector2i(c.x, c.y), c.z, zone[i])


func _lot_tile_ok(t: Vector2i, z: int) -> bool:
	if not inb(t.x, t.y):
		return false
	var i := idx(t.x, t.y)
	return zone[i] == z and bld[i] == -1 and road[i] == 0 and path[i] == 0 and rail[i] == 0 and terrain[i] == 0


func _try_lot(f: Vector2i, dir: int, z: int) -> bool:
	var F := Defs.DIRS[dir]
	var shapes: Array = Defs.LOTS[z]
	for si in shapes.size():
		var s: Array = shapes[si]
		if si < shapes.size() - 1 and rng.randf() < 0.35:
			continue
		var flips := [1, -1] if rng.randf() < 0.5 else [-1, 1]
		for flip in flips:
			var tiles := lot_tiles(f, dir, s[0], s[1], flip)
			var ok := true
			for ti in tiles.size():
				var t := tiles[ti]
				if not _lot_tile_ok(t, z):
					ok = false; break
				if ti < s[0] and not is_local_road(t + F):
					ok = false; break
			if ok and lot_range(tiles) > 0.7:
				ok = false
			if ok:
				var b := _new_building("zone", z, tiles, dir, s[0], s[1], f + F)
				b.level = 1
				b.style = style_at(Vector2i(b.x, b.y))
				b.cap = _calc_cap(b)
				b.build_days = rng.randi_range(3, 7)
				b.happiness = 60.0
				building_added.emit(b)
				return true
			if s[0] == 1:
				break
	return false


func _upkeep_month() -> Dictionary:
	var rc := 0.0
	for i in n * n:
		if road[i] > 0:
			rc += Defs.ROAD_TYPES[road[i]].upkeep
		elif path[i] > 0:
			rc += 0.6
	var e := {"Дороги": rc}
	var tu := 0.0
	for l in lines:
		var td: Dictionary = Defs.TRANSIT[l.kind]
		tu += td.line_upkeep * bud("transport") + td.vehicle_upkeep * line_vehicles(l)
	if tu > 0.0:
		e["Транспорт"] = tu
	var pc := 0.0
	for b: Building in buildings.values():
		if b.is_service():
			continue
		for pid in Defs.POLICIES:
			if Defs.POLICIES[pid].cost > 0.0 and bpol(b, pid):
				pc += Defs.POLICIES[pid].cost
	if pc > 0.0:
		e["Законы"] = pc
	var lp := 0.0
	for l in loans:
		lp += l.pay
	if lp > 0.0:
		e["Кредиты"] = lp
	for b: Building in buildings.values():
		if b.is_service():
			var cat: String = Defs.SERVICES[b.type].cat
			var names := {"power": "Электричество", "water": "Водоснабжение", "safety": "Безопасность", "transport": "Транспорт", "landmark": "Достопримечательности", "ugk": "УГК (космос)",
				"health": "Здравоохранение", "edu": "Образование", "park": "Парки"}
			var key: String = names.get(cat, cat)
			e[key] = e.get(key, 0.0) + Defs.SERVICES[b.type].upkeep * (1.0 if cat == "landmark" else bud(cat))
	var rm := region.monthly_money()
	if rm.y > 0.0:
		e["Закупки у соседей"] = rm.y
	var h := hall()
	if h and h.ministries.size() > 0:
		var mu := 0.0
		for m in h.ministries:
			mu += Defs.MINISTRIES[m].upkeep
		e["Министерства"] = mu
	if has_ministry("utility"):
		for k in ["Электричество", "Водоснабжение"]:
			if e.has(k):
				e[k] *= 0.85
	if has_ministry("transport") and e.has("Транспорт"):
		e["Транспорт"] *= 0.8
	var sub := 0.0
	var inc := _income_month_base()
	for sid in subsidies:
		var lv := subsidy(sid)
		if lv > 0:
			var base_k: String = {"r": "Жилые зоны", "c": "Коммерция", "i": "Промышленность", "o": "Офисы"}[Defs.SUBSIDIES[sid].base]
			sub += Defs.SUBSIDIES[sid].pct * lv * maxf(inc.get(base_k, 0.0), 2000.0)
	if sub > 0.0:
		e["Субсидии"] = sub
	return e


func _income_month_base() -> Dictionary:
	var inc := {"Жилые зоны": 0.0, "Коммерция": 0.0, "Промышленность": 0.0, "Офисы": 0.0}
	for b: Building in buildings.values():
		if b.is_service() or b.abandoned:
			continue
		match b.kind():
			"r": inc["Жилые зоны"] += b.occ * taxes.r * 0.75
			"c": inc["Коммерция"] += b.occ * taxes.c * 0.85
			"i":
				if b.zone == Defs.OFFICE: inc["Офисы"] += b.occ * taxes.o
				else: inc["Промышленность"] += b.occ * taxes.i * 0.75
	return inc


func _income_month() -> Dictionary:
	var inc := {"Жилые зоны": 0.0, "Коммерция": 0.0, "Промышленность": 0.0, "Офисы": 0.0}
	# imported goods eat the shops' margin; unsold goods and local raw materials affect factories
	var gk_c: float = 1.0 - 0.2 * goods.import
	var gk_i: float = (0.6 + 0.4 * goods.sell) * (1.0 + 0.15 * clamp(goods.raw_prod / max(goods.raw_need, 1.0), 0.0, 1.0))
	for b: Building in buildings.values():
		if b.is_service() or b.abandoned or b.fire > 0:
			continue
		var lf := 0.8 + 0.25 * b.level
		match b.kind():
			"r": inc["Жилые зоны"] += b.occ * taxes.r * 0.75 * lf
			"c": inc["Коммерция"] += b.occ * taxes.c * 0.85 * lf * (0.88 if "traffic" in b.problems else 1.0) * (0.95 if bpol(b, "smoke_ban") else 1.0) * (1.15 if bpol(b, "tourism") else 1.0) * gk_c
			"i":
				if b.zone == Defs.OFFICE:
					inc["Офисы"] += b.occ * taxes.o * 1.0 * lf
				else:
					var sk := gk_i if b.zone == Defs.IND else 1.0
					var sp := ind_spec(b)
					if sp != "":
						var sr := spec_resource(b, sp)
						sk = Defs.SPECS[sp].income if sr >= 0.05 else 0.65
					inc["Промышленность"] += b.occ * taxes.i * 0.75 * lf * (0.9 if bpol(b, "truck_ban") else 1.0) * (0.92 if bpol(b, "ind_filters") else 1.0) * sk
	if transit_income > 0.0:
		inc["Билеты"] = transit_income
	var tour := 0.0
	var exp_inc := 0.0
	var tax_bonus := 0.0
	for b: Building in buildings.values():
		if b.is_service() and b.has_road and b.done():
			var d: Dictionary = Defs.SERVICES[b.type]
			tour += d.get("tourism", 0) * clamp(population / 3000.0, 0.3, 1.5)
			exp_inc += d.get("export", 0) * clamp(jobs / 2000.0, 0.3, 1.5)
			tax_bonus += d.get("tax_bonus", 0.0)
	if has_ministry("finance"):
		tax_bonus += 0.08
	if tax_bonus > 0.0:
		for k in ["Жилые зоны", "Коммерция", "Промышленность", "Офисы"]:
			inc[k] *= 1.0 + tax_bonus
	var sat := 0.04 * space.comsats()
	inc["Коммерция"] *= 1.0 + sat
	inc["Офисы"] *= 1.0 + sat + 0.1 * subsidy("tech")
	inc["Промышленность"] *= 1.0 + 0.05 * subsidy("farming")
	tour += space.tourism() + rail_stats.tourism
	if rail_stats.income > 0.0:
		inc["Железная дорога"] = rail_stats.income
	if has_ministry("tourism"):
		tour *= 1.3
	if space.income() > 0.0:
		inc["Космос"] = space.income()
	if tour > 0.0:
		inc["Туризм"] = tour
	if exp_inc > 0.0:
		inc["Экспорт"] = exp_inc
	var rm := region.monthly_money()
	if rm.x > 0.0:
		inc["Продажи соседям"] = rm.x
	return inc


func _daily_budget() -> void:
	var inc := _income_month()
	var exp := _upkeep_month()
	var ti := 0.0
	var te := 0.0
	var im: float = Defs.DIFFICULTY[clampi(difficulty, 0, 3)].income
	for k in inc:
		inc[k] *= im
		ti += inc[k]
	for k in exp: te += exp[k]
	projected = {"income": ti, "expense": te, "inc": inc, "exp": exp}
	money += (ti - te) / Defs.DAYS_PER_MONTH


func _end_month() -> void:
	last_month = projected.duplicate(true)
	deaths_last = deaths_month
	deaths_month = 0
	people.month()
	region.month(self)
	history.append({"day": day, "pop": population, "money": money, "income": projected.income, "expense": projected.expense,
		"happy": avg_happiness, "jobs": jobs})
	if history.size() > 240:
		history.pop_front()
	for l in loans.duplicate():
		l.left -= 1
		if l.left <= 0:
			loans.erase(l)
			_notify_once("loan_done", "🏦 Кредит полностью погашен.", "good", 1)
	month_ended.emit()
	if money < 0:
		_notify_once("debt", "💸 Казна города пуста! Поднимите налоги или сократите расходы.", "bad", 30)


func _check_milestones() -> void:
	while milestone + 1 < Defs.MILESTONES.size() and population >= Defs.MILESTONES[milestone + 1].pop:
		milestone += 1
		money += Defs.MILESTONES[milestone].reward
		log_event("milestone", "Наш город теперь — «%s»!" % Defs.MILESTONES[milestone].name,
			"Население превысило %s человек. Мэрия получила награду ₽%s." % [Defs.fmt_int(Defs.MILESTONES[milestone].pop), Defs.fmt_int(Defs.MILESTONES[milestone].reward)])
		milestone_reached.emit(milestone)


## 0 winter, 1 spring, 2 summer, 3 autumn
func season() -> int:
	var m := (day / Defs.DAYS_PER_MONTH) % 12
	if m == 11 or m <= 1: return 0
	if m <= 4: return 1
	if m <= 7: return 2
	return 3


func season_name() -> String:
	return ["Зима", "Весна", "Лето", "Осень"][season()]


func _update_weather() -> void:
	weather_days -= 1
	if weather_days <= 0:
		var s := season()
		var r := rng.randf()
		if s == 0:
			weather = "snow" if r < 0.45 else ("clear" if r < 0.9 else "rain")
		else:
			weather = "rain" if r < (0.35 if s != 2 else 0.18) else "clear"
		weather_days = rng.randi_range(3, 8)
	if weather == "snow" and season() == 0:
		snow_cover = min(1.0, snow_cover + 0.12)
	else:
		snow_cover = max(0.0, snow_cover - (0.05 if season() == 0 else 0.15))


func _check_quests() -> void:
	for q in Quests.LIST:
		if q.id in quests_done:
			continue
		if Quests.progress(self, q.id) >= 1.0:
			quests_done.append(q.id)
			money += q.reward
			log_event("milestone", "Задание выполнено: «%s»" % q.name, "%s. Мэрия получила ₽%s." % [q.desc, Defs.fmt_int(q.reward)])
			quest_done.emit(q)


func active_quests(count: int = 3) -> Array:
	var out: Array = []
	for q in Quests.LIST:
		if not q.id in quests_done:
			out.append(q)
			if out.size() >= count:
				break
	return out


## Upgrades a straight run of road around tile t to a new type.
func road_segment(t: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [t]
	var m := road_mask(t)
	var axis: Array = []
	if m == 10 or m == 2 or m == 8: axis = [Vector2i(1, 0), Vector2i(-1, 0)]
	elif m == 5 or m == 1 or m == 4: axis = [Vector2i(0, 1), Vector2i(0, -1)]
	var rt := road[idx(t.x, t.y)]
	for d in axis:
		var p: Vector2i = t + d
		while is_road(p) and road[idx(p.x, p.y)] == rt:
			out.append(p)
			var pm := road_mask(p)
			if pm != 10 and pm != 5:
				break
			p += d
	return out


func take_loan(amount: float) -> bool:
	if loans.size() >= 3:
		return false
	money += amount
	loans.append({"amount": amount, "pay": amount * (1.105 if has_ministry("finance") else 1.15) / 24.0, "left": 24})
	log_event("policy", "Мэрия взяла кредит ₽%s" % Defs.fmt_int(amount), "Кредит выдан на 2 года под 15%.")
	return true


func log_event(kind: String, title: String, body: String) -> void:
	events.append({"day": day, "kind": kind, "title": title, "body": body})
	if events.size() > 30:
		events.pop_front()


func _notify_once(key: String, text: String, kind: String, gap: int) -> void:
	if _notify_last.has(key) and day - int(_notify_last[key]) < gap:
		return
	_notify_last[key] = day
	notify.emit(text, kind)


## Road load: 1.0 = at capacity.
func congestion(i: int) -> float:
	if i < 0 or i >= road.size() or road[i] == 0:
		return 0.0
	return traffic[i] / Defs.ROAD_TYPES[road[i]].cap * (0.9 if space.has("gps") else 1.0)


func congested_tiles(thr: float = 1.0) -> int:
	var c := 0
	for i in n * n:
		if road[i] > 0 and traffic[i] / Defs.ROAD_TYPES[road[i]].cap > thr:
			c += 1
	return c


func add_traffic(i: int) -> void:
	if i >= 0 and i < traffic.size():
		traffic[i] += 1.0


# ------------------------------------------------------------------ queries for traffic
func random_building(kinds: Array, comp: int) -> Building:
	var list: Array = []
	for b: Building in buildings.values():
		if b.abandoned or b.build_days > 0 or b.fire > 0 or not b.has_road:
			continue
		if b.kind() in kinds and (comp < 0 or road_comp[idx(b.access.x, b.access.y)] == comp):
			list.append(b)
	if list.is_empty():
		return null
	return list[rng.randi() % list.size()]


func find_path(a: Vector2i, b: Vector2i) -> PackedVector2Array:
	if not is_road(a) or not is_road(b):
		return PackedVector2Array()
	return astar.get_point_path(idx(a.x, a.y), idx(b.x, b.y))


# ------------------------------------------------------------------ save / load
func to_dict() -> Dictionary:
	var bl: Array = []
	for b: Building in buildings.values():
		bl.append(b.to_dict())
	return {
		"version": 1, "n": n, "seed": seed, "terrain": terrain, "height": height, "road": road, "zone": zone, "tree": tree,
		"buildings": bl, "next_id": next_id, "outside": outside, "money": money, "day": day,
		"taxes": taxes, "demand": demand, "quests_done": quests_done, "city_name": city_name, "map_type": map_type, "difficulty": difficulty, "sandbox": sandbox, "loans": loans, "weather": weather, "weather_days": weather_days, "snow_cover": snow_cover, "random_disasters": random_disasters, "casualties": casualties, "lines": lines, "next_line_id": next_line_id,
		"district": district, "districts": districts, "next_district": next_district, "city_policies": city_policies, "history": history, "milestone": milestone, "traffic": traffic,
		"resource": resource, "res_amt": res_amt, "budget": budget, "auto_demolish": auto_demolish, "deaths_last": deaths_last,
		"water_sim": water_sim.to_dict() if water_sim else {},
		"path": path, "rail": rail, "owned": owned, "walk_share": walk_share, "city_style": city_style, "people": people.to_dict(), "region": region.to_dict(), "space": space.to_dict(), "subsidies": subsidies, "achievements": achievements, "mansion": mansion_awarded,
	}


func from_dict(dd: Dictionary) -> void:
	n = int(dd.n)
	seed = int(dd.seed)
	_alloc()
	terrain = dd.terrain; zone = dd.zone; tree = dd.tree
	if dd.has("path"):
		path = dd.path
	if dd.has("rail"):
		rail = dd.rail
	if dd.has("owned"):
		owned = dd.owned
	walk_share = float(dd.get("walk_share", 0.0))
	city_style = dd.get("city_style", "modern")
	if dd.has("height"):
		height = dd.height
	traffic = dd.get("traffic", traffic)
	outside = dd.outside
	money = float(dd.money); day = int(dd.day)
	taxes = dd.taxes; demand = dd.demand; history = dd.history; milestone = int(dd.milestone)
	next_id = int(dd.next_id)
	quests_done = dd.get("quests_done", [])
	city_name = dd.get("city_name", "Новоградск")
	map_type = dd.get("map_type", "river")
	difficulty = int(dd.get("difficulty", 1))
	sandbox = bool(dd.get("sandbox", false))
	loans = dd.get("loans", [])
	weather = dd.get("weather", "clear")
	weather_days = int(dd.get("weather_days", 0))
	snow_cover = float(dd.get("snow_cover", 0.0))
	random_disasters = int(dd.get("random_disasters", 1))
	casualties = int(dd.get("casualties", 0))
	lines = dd.get("lines", [])
	if dd.has("district"):
		district = dd.district
	districts = dd.get("districts", {})
	next_district = int(dd.get("next_district", 1))
	city_policies = dd.get("city_policies", [])
	next_line_id = int(dd.get("next_line_id", 1))
	budget = dd.get("budget", budget)
	auto_demolish = bool(dd.get("auto_demolish", false))
	deaths_last = int(dd.get("deaths_last", 0))
	var rd: PackedByteArray = dd.road
	astar.clear()
	road_count = 0
	for i in n * n:
		if rd[i] > 0:
			_set_road(Vector2i(i % n, i / n), true, rd[i])
	for bd in dd.buildings:
		var b := Building.from_dict(bd)
		if b.is_service():
			b.powered = true
			b.watered = true
		buildings[b.id] = b
		for t in b.tiles():
			bld[idx(t.x, t.y)] = b.id
	_compute_water_near()
	if dd.has("resource"):
		resource = dd.resource
		res_amt = dd.res_amt
	else:
		_generate_resources(seed)
	_recompute_roads()
	_init_water()
	water_sim.from_dict(dd.get("water_sim", {}))
	_init_people()
	people.from_dict(dd.get("people", {}))
	region = Region.new()
	region.from_dict(dd.get("region", {}), self)
	space = Space.new()
	space.from_dict(dd.get("space", {}))
	subsidies = dd.get("subsidies", {})
	achievements = dd.get("achievements", {})
	mansion_awarded = bool(dd.get("mansion", false))
	_compute_coverage()
	_compute_utilities()
	_compute_stats()
	_compute_transit()
