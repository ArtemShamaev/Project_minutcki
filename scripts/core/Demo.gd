class_name Demo
## Builds a small pre-made town (used as the main menu background).

static func build(c: City, days: int = 240) -> void:
	c.money = 1e9
	c.milestone = 3
	c.owned.fill(1)
	c.random_disasters = 0
	var y0 := c.n / 2
	var cells: Array[Vector2i] = []
	for x in range(9, 46):
		cells.append(Vector2i(x, y0))
	c.build_roads(cells, 2)
	for x in [14, 24, 34, 44]:
		c.build_roads(c.road_path(Vector2i(x, y0 - 14), Vector2i(x, y0 + 14)))
	for yy in [y0 - 14, y0 - 7, y0 + 7, y0 + 14]:
		c.build_roads(c.road_path(Vector2i(14, yy), Vector2i(44, yy)))
	var placed := [
		["coal", Vector2i(24, y0 + 15), 0], ["coal", Vector2i(27, y0 + 15), 0],
		["tower", Vector2i(16, y0 - 15), 2], ["tower", Vector2i(17, y0 - 15), 2], ["tower", Vector2i(18, y0 - 15), 2],
		["tower", Vector2i(19, y0 - 15), 2], ["tower", Vector2i(20, y0 - 15), 2], ["tower", Vector2i(21, y0 - 15), 2],
		["tower", Vector2i(22, y0 - 15), 2], ["tower", Vector2i(23, y0 - 15), 2],
		["fire", Vector2i(11, y0 - 2), 2], ["fire", Vector2i(29, y0 + 1), 0],
		["police", Vector2i(29, y0 - 13), 0], ["school", Vector2i(19, y0 - 13), 0], ["clinic", Vector2i(39, y0 - 13), 0],
		["bigpark", Vector2i(19, y0 - 6), 0], ["park", Vector2i(36, y0 - 6), 0], ["park", Vector2i(26, y0 - 6), 0],
		["landfill", Vector2i(45, y0 + 2), 3], ["school", Vector2i(39, y0 + 8), 0],
		["busdepot", Vector2i(20, y0 + 15), 0], ["metro", Vector2i(16, y0 - 8), 2], ["metro", Vector2i(43, y0 - 8), 2],
		["metro", Vector2i(43, y0 + 13), 2], ["tvtower", Vector2i(37, y0 - 6), 0], ["tramdepot", Vector2i(16, y0 + 1), 0], ["cathedral", Vector2i(30, y0 - 6), 0],
	]
	for p in placed:
		var b := c.place_service(p[0], p[1], p[2])
		if b == null:
			push_warning("demo: failed to place %s: %s" % [p[0], c.service_placement(p[0], p[1], p[2]).reason])
	# sewage outlet on the nearest shore, cemetery at the edge of town
	if not place_near(c, "outlet", Vector2i(36, y0 - 14), 40, false):
		var shore: Array[Vector2i] = []
		for x in range(36, 48):
			shore.append(Vector2i(x, y0 - 14))
		for yy in range(y0 - 15, y0 - 30, -1):
			shore.append(Vector2i(36, yy))
			if c.is_water(Vector2i(36, yy - 1)) or c.is_water(Vector2i(35, yy - 1)) or c.is_water(Vector2i(37, yy - 1)):
				break
		c.build_roads(shore)
		place_near(c, "outlet", Vector2i(36, y0 - 20), 40)
	place_near(c, "outlet", Vector2i(36, y0 - 20), 40)
	place_near(c, "recycling", Vector2i(14, y0 - 16), 12)
	place_near(c, "cemetery", Vector2i(30, y0 + 15), 16)
	place_near(c, "cemetery", Vector2i(30, y0 - 15), 16)
	# pedestrian paths through the blocks (crossing the streets on zebras)
	c.build_paths(c.road_path(Vector2i(15, y0 - 10), Vector2i(43, y0 - 10)))
	c.build_paths(c.road_path(Vector2i(29, y0 + 1), Vector2i(29, y0 + 6)))
	c.paint_zone(Rect2i(15, y0 - 13, 9, 6), Defs.R_LOW)
	c.paint_zone(Rect2i(25, y0 - 13, 9, 6), Defs.R_LOW)
	c.paint_zone(Rect2i(15, y0 - 6, 9, 6), Defs.R_HIGH)
	c.paint_zone(Rect2i(25, y0 - 6, 9, 6), Defs.C_HIGH)
	c.paint_zone(Rect2i(35, y0 - 13, 9, 13), Defs.R_LOW)
	c.paint_zone(Rect2i(15, y0 + 1, 9, 6), Defs.R_HIGH)
	c.paint_zone(Rect2i(25, y0 + 1, 9, 6), Defs.C_LOW)
	c.paint_zone(Rect2i(35, y0 + 1, 9, 6), Defs.OFFICE)
	c.paint_zone(Rect2i(15, y0 + 8, 29, 6), Defs.IND)
	c.add_line("bus", [Vector2i(14, y0 - 10), Vector2i(24, y0 - 10), Vector2i(34, y0 - 10), Vector2i(44, y0 - 3),
		Vector2i(34, y0 + 10), Vector2i(24, y0 + 10), Vector2i(14, y0 + 3)])
	c.add_line("tram", [Vector2i(14, y0), Vector2i(29, y0), Vector2i(44, y0)])
	var st: Array = []
	for b: Building in c.buildings.values():
		if b.type == "metro":
			st.append(b.id)
	if st.size() >= 2:
		c.add_line("metro", st)
	var d1 := c.new_district()
	c.paint_district(Vector2(24, y0 - 8), 9.5, d1)
	c.districts[d1].policies.append("greening")
	var d2 := c.new_district()
	c.paint_district(Vector2(32, y0 + 9), 9.0, d2)
	c.districts[d2].policies.append("truck_ban")
	for i in days:
		c.tick_day()
	c.money = 50000
	c.random_disasters = 1


## Places a service at the free spot closest to `at`. Returns true on success.
static func place_near(c: City, id: String, at: Vector2i, radius: int, warn: bool = true) -> bool:
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for y in range(at.y - radius, at.y + radius + 1):
		for x in range(at.x - radius, at.x + radius + 1):
			var p := Vector2i(x, y)
			var d := Vector2(p).distance_to(Vector2(at))
			if d < bd and c.service_placement(id, p, -1).ok:
				bd = d
				best = p
	if best.x < 0:
		if warn:
			push_warning("demo: no place for %s" % id)
		return false
	return c.place_service(id, best, -1) != null
