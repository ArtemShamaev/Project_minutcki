extends SceneTree
## Railway: laying track, crossings, stations, outside connection, riders, export, save/load.
func _init():
	var c = City.new()
	c.generate(12345)
	Demo.build(c, 30)
	c.money = 1e7
	c.milestone = 5
	# find a row from the west edge that can take a straight track
	var row := -1
	for y in range(5, c.n - 5):
		var cells: Array[Vector2i] = c.road_path(Vector2i(0, y), Vector2i(40, y), 0)
		var r: Dictionary = c.check_rails(cells)
		if r.ok:
			row = y
			print("row ", y, " cost ", r.cost)
			c.build_rails(cells)
			break
		elif y < 8:
			print("row ", y, " bad: ", r.reason)
	print("rail tiles ", Array(c.rail).count(1), " mask at end ", c.rail_mask(Vector2i(40, row)), " at edge ", c.rail_mask(Vector2i(0, row)))
	var rd: Array[Vector2i] = c.road_path(Vector2i(2, row + 3), Vector2i(40, row + 3), 0)
	print("parallel road ", c.build_roads(rd, 1))
	var st = null
	var cs = null
	for x in range(2, 40):
		for dy in [-2, 2, -1, 1, 3, -3]:
			if st == null and c.service_placement("train_station", Vector2i(x, row + dy), -1).ok:
				st = c.place_service("train_station", Vector2i(x, row + dy), -1)
			elif cs == null and c.service_placement("cargo_station", Vector2i(x, row + dy), -1).ok:
				cs = c.place_service("cargo_station", Vector2i(x, row + dy), -1)
	print("station ", st != null, " cargo ", cs != null)
	print("far station placement: ", c.service_placement("train_station", Vector2i(60, 60), -1).reason)
	if st:
		print("link ", c.station_link(st))
		print("route len ", c.rail_route(Vector2i(0, row), c.station_platform(st)).size())
	for i in 30: c.tick_day()
	print("rail stats ", c.rail_stats, " goods export cap ", c.goods.export_cap)
	print("income rail ", c._income_month().get("Железная дорога", 0.0))
	# zone on rail not allowed, crossing check
	print("can zone on rail ", c.can_zone(Vector2i(10, row)))
	var vert: Array[Vector2i] = c.road_path(Vector2i(20, row - 3), Vector2i(20, row + 3), 1)
	print("road across rail: ", c.check_roads(vert, 1).reason, " ok=", c.check_roads(vert, 1).ok)
	var along: Array[Vector2i] = c.road_path(Vector2i(18, row), Vector2i(22, row), 0)
	print("road along rail: ", c.check_roads(along, 1).reason)
	var d = c.to_dict()
	var c2 = City.new()
	c2.from_dict(d)
	print("load rail tiles ", Array(c2.rail).count(1), " link ", c2.station_link(c2.buildings[st.id]).out if st else "")
	print("bulldoze ", c.bulldoze(Rect2i(5, row, 3, 1)), " tiles now ", Array(c.rail).count(1), " link ", c.station_link(st).out if st else "")
	quit()
