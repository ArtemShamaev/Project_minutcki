class_name WaterSim
## Shallow-water simulation on the tile grid ("virtual pipes" with inertia).
## Water flows downhill, rivers run from their source edge to their mouth, outlets
## dump sewage that is carried downstream, pumps drain water and floods spread
## over low land. Runs incrementally (a few rows per frame) to stay cheap.

const SEA := -0.1           # rest level of the sea / lakes
const DRY := 0.004          # depth below which a cell counts as dry
var k := 0.2              # pipe conductance
var damp := 0.8           # flux inertia (0 = pure diffusion)
const MAXF := 0.24          # max share of a cell's water leaving through one edge per step

var n := 0
var g := PackedFloat32Array()     # ground height at tile centre
var d := PackedFloat32Array()     # water depth
var fr := PackedFloat32Array()    # flux to the east neighbour
var fd := PackedFloat32Array()    # flux to the south neighbour
var pm := PackedFloat32Array()    # pollutant mass (concentration = pm / d)
var vel := PackedFloat32Array()   # 2 floats per cell: smoothed flow velocity (x, z)
var fixed := {}                   # cell -> target surface level (map-edge sources / sinks)
var fixed_base := {}              # cell -> base level (before flood surges)
var inject := {}                  # cell -> [volume per step, pollutant concentration]
var drain := {}                   # cell -> volume per step requested by pumps
var drained := {}                 # cell -> volume actually removed during the last sweep
var surge := 0.0                  # extra level on all sources (flood disaster)
var rain := 0.0                   # depth added per sweep to every cell
var steps := 0                    # full sweeps done
var span := PackedInt32Array()    # per row: first and last column that needs simulating
var _row := 0


func setup(city) -> void:
	n = city.n
	g.resize(n * n); d.resize(n * n); fr.resize(n * n); fd.resize(n * n); pm.resize(n * n)
	vel.resize(n * n * 2)
	d.fill(0); fr.fill(0); fd.fill(0); pm.fill(0); vel.fill(0)
	update_ground(city, Rect2i(0, 0, n, n))
	for i in n * n:
		if g[i] < SEA:
			d[i] = SEA - g[i]
	_find_boundaries(city)
	_init_levels()
	span.resize(n * 2)
	_update_spans()


## Initial river slope: every wet cell gets a level interpolated between the nearest
## source and the nearest sink (distances through water), so rivers flow at once.
func _init_levels() -> void:
	if fixed.is_empty():
		return
	var hi := -1e9
	var lo := 1e9
	for i in fixed:
		hi = maxf(hi, fixed[i]); lo = minf(lo, fixed[i])
	var da := _bfs(func(i): return fixed[i] > hi - 0.001)
	var db := _bfs(func(i): return fixed[i] < lo + 0.001)
	for i in n * n:
		if d[i] <= 0.0 or da[i] < 0:
			continue
		var lvl := hi
		if db[i] >= 0 and hi - lo > 0.001:
			lvl = lerpf(hi, lo, float(da[i]) / float(da[i] + db[i]))
		d[i] = maxf(lvl - g[i], 0.0)


func _bfs(is_src: Callable) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(n * n)
	dist.fill(-1)
	var q: Array[int] = []
	for i in fixed:
		if is_src.call(i):
			dist[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var c := q[head]; head += 1
		var x := c % n
		for j in [c - 1 if x > 0 else -1, c + 1 if x < n - 1 else -1, c - n, c + n]:
			if j >= 0 and j < n * n and dist[j] < 0 and d[j] > 0.0:
				dist[j] = dist[c] + 1
				q.append(j)
	return dist


func update_ground(city, r: Rect2i) -> void:
	r = r.intersection(Rect2i(0, 0, n, n))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * n + x
			var h: float = city.tile_h(x, y)
			# bridges / roads on water keep the river bed; buildings are raised platforms
			g[i] = h
	if span.size() == n * 2:
		for y in range(maxi(r.position.y - 1, 0), mini(r.end.y + 1, n)):
			span[y * 2] = 0
			span[y * 2 + 1] = n - 1


## Rows only need simulating around wet cells (plus a margin for spreading water).
func _update_spans() -> void:
	for y in n:
		var a := n
		var b := -1
		for yy in range(maxi(y - 1, 0), mini(y + 2, n)):
			var row := yy * n
			for x in n:
				if d[row + x] > DRY:
					a = mini(a, x); break
			for x in range(n - 1, -1, -1):
				if d[row + x] > DRY:
					b = maxi(b, x); break
		span[y * 2] = maxi(a - 2, 0)
		span[y * 2 + 1] = mini(b + 2, n - 1)


## Water entering / leaving the map: rivers get a higher level at their source
## edge and a lower one at their mouth, the sea is held at sea level.
func _find_boundaries(city) -> void:
	fixed.clear()
	var mt: String = city.map_type
	for k in n:
		var edges := [[k, 0, "n"], [k, n - 1, "s"], [0, k, "w"], [n - 1, k, "e"]]
		for e in edges:
			var i: int = e[1] * n + e[0]
			if city.terrain[i] != 1:
				continue
			var lvl := SEA
			match mt:
				"river", "mountains":
					lvl = SEA + (0.05 if e[2] == "n" else -0.08)
			fixed[i] = lvl
	if mt == "coast":
		# the small river starts from a spring inland
		var x0 := int(n * 0.45)
		for y in n:
			var i := y * n + x0
			if city.terrain[i] == 1:
				fixed[i] = SEA + 0.05
	fixed_base = fixed.duplicate()


func surface(i: int) -> float:
	return g[i] + d[i]


func depth_at(x: int, y: int) -> float:
	return d[y * n + x] if x >= 0 and y >= 0 and x < n and y < n else 0.0


func conc(i: int) -> float:
	return clamp(pm[i] / d[i], 0.0, 1.0) if d[i] > DRY else 0.0


func speed(i: int) -> float:
	return Vector2(vel[i * 2], vel[i * 2 + 1]).length()


## Process up to `rows` rows (one full sweep = n rows). Returns true when a sweep finished.
func step_rows(rows: int) -> bool:
	var done := false
	var end := mini(_row + rows, n)
	_sweep(_row, end)
	_row = end
	if _row >= n:
		_row = 0
		_finish_sweep()
		done = true
	return done


func sweep() -> void:
	_sweep(0, n)
	_row = 0
	_finish_sweep()


func _sweep(y0: int, y1: int) -> void:
	var nn := n
	for y in range(y0, y1):
		var row := y * nn
		var xa := span[y * 2]
		var xb := span[y * 2 + 1]
		if xb < xa:
			continue
		for x in range(xa, xb + 1):
			var i := row + x
			var di := d[i]
			var si := g[i] + di
			# east edge
			if x < nn - 1:
				var j := i + 1
				var dj := d[j]
				if di > DRY or dj > DRY:
					var f := fr[i] * damp + k * (si - g[j] - dj)
					if f > 0.0:
						f = minf(f, di * MAXF)
					else:
						f = maxf(f, -dj * MAXF)
					fr[i] = f
					var c := pm[i] / di if f > 0.0 else (pm[j] / dj if dj > 0.0 else 0.0)
					# pollution also mixes slowly between neighbours (still water)
					var mix := 0.0
					if di > DRY and dj > DRY:
						mix = (pm[i] / di - pm[j] / dj) * 0.15 * minf(di, dj)
					if f != 0.0 or mix != 0.0:
						di -= f
						d[j] = dj + f
						pm[i] -= f * c + mix
						pm[j] += f * c + mix
						si = g[i] + di
				else:
					fr[i] = 0.0
			# south edge
			if y < nn - 1:
				var j := i + nn
				var dj := d[j]
				if di > DRY or dj > DRY:
					var f := fd[i] * damp + k * (si - g[j] - dj)
					if f > 0.0:
						f = minf(f, di * MAXF)
					else:
						f = maxf(f, -dj * MAXF)
					fd[i] = f
					var c := pm[i] / di if f > 0.0 else (pm[j] / dj if dj > 0.0 else 0.0)
					# pollution also mixes slowly between neighbours (still water)
					var mix := 0.0
					if di > DRY and dj > DRY:
						mix = (pm[i] / di - pm[j] / dj) * 0.15 * minf(di, dj)
					if f != 0.0 or mix != 0.0:
						di -= f
						d[j] = dj + f
						pm[i] -= f * c + mix
						pm[j] += f * c + mix
				else:
					fd[i] = 0.0
			d[i] = di


func _finish_sweep() -> void:
	steps += 1
	# map-edge sources and sinks
	for i in fixed:
		var lvl: float = fixed[i] + surge
		d[i] = maxf(lvl - g[i], 0.0)
		pm[i] = 0.0
	# outlets and pumps
	for i in inject:
		var v: Array = inject[i]
		d[i] += v[0]
		pm[i] += v[0] * v[1]
	drained.clear()
	for i in drain:
		var take := minf(drain[i], maxf(d[i] - 0.02, 0.0))
		if take > 0.0:
			var c := conc(i)
			d[i] -= take
			pm[i] = maxf(pm[i] - take * c, 0.0)
		drained[i] = take
	# rain on open water, evaporation of puddles, slow self-purification, velocity estimate
	var nn := n
	for i in nn * nn:
		var di := d[i]
		if di <= 0.0:
			continue
		if rain > 0.0 and di > 0.05:
			di += rain
		# lakes: evaporation above the rest level, ground water refills below it
		if di > 0.05:
			var sf := g[i] + di
			if sf > SEA + 0.02:
				di -= minf(0.00015, (sf - SEA - 0.02) * 0.004)
			elif sf < SEA and g[i] < SEA:
				di += minf(0.00006, (SEA - sf) * 0.002)
		# flood water on dry land soaks into the ground
		if g[i] > SEA + 0.02 and not fixed.has(i):
			di = maxf(di - 0.0004, 0.0)
		if di < 0.03:
			di = maxf(di - 0.0006, 0.0)
		d[i] = di
		if di <= DRY:
			pm[i] = 0.0
			vel[i * 2] = 0.0
			vel[i * 2 + 1] = 0.0
			continue
		pm[i] = minf(pm[i] * 0.9985, di)
		var fx := fr[i] + (fr[i - 1] if i % nn > 0 else 0.0)
		var fz := fd[i] + (fd[i - nn] if i >= nn else 0.0)
		var inv := 0.5 / maxf(di, 0.08)
		vel[i * 2] = lerpf(vel[i * 2], fx * inv, 0.3)
		vel[i * 2 + 1] = lerpf(vel[i * 2 + 1], fz * inv, 0.3)
	if steps % 4 == 0:
		_update_spans()


## Packs data for the water shader: R = surface (or far below when dry), G = depth, B/A = velocity.
func pack_texture_data() -> PackedByteArray:
	var out := PackedFloat32Array()
	out.resize(n * n * 4)
	for i in n * n:
		var di := d[i]
		var k := i * 4
		if di > 0.012:
			out[k] = g[i] + di
			out[k + 1] = di
		else:
			out[k] = -9.0
			out[k + 1] = 0.0
		out[k + 2] = vel[i * 2]
		out[k + 3] = vel[i * 2 + 1]
	return out.to_byte_array()


func to_dict() -> Dictionary:
	return {"d": Marshalls.raw_to_base64(d.to_byte_array()), "pm": Marshalls.raw_to_base64(pm.to_byte_array())}


func from_dict(dd: Dictionary) -> void:
	if dd.has("d"):
		var a := Marshalls.base64_to_raw(dd.d).to_float32_array()
		if a.size() == n * n:
			d = a
	if dd.has("pm"):
		var b := Marshalls.base64_to_raw(dd.pm).to_float32_array()
		if b.size() == n * n:
			pm = b
	fr.fill(0); fd.fill(0)
	_update_spans()
