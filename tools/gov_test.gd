extends SceneTree
func _init():
	var c = City.new()
	c.generate(12345)
	Demo.build(c, 30)
	c.money = 1e7
	c.milestone = 6
	var h = null
	for y in range(30, 90):
		for x in range(8, 50):
			if h == null and c.service_placement("cityhall", Vector2i(x, y), -1).ok:
				h = c.place_service("cityhall", Vector2i(x, y), -1)
	print("hall ", h != null, " slots ", c.hall_slots())
	var lvl_ok := c.upgrade_hall()
	print("upgrade to city hall ", lvl_ok, " slots ", c.hall_slots(), " state3 ", c.upgrade_hall_state().reason)
	h.level = 3
	for m in ["finance", "science", "tourism"]:
		print("ministry ", m, " ", c.build_ministry(m))
	print("casino unlock ", c.service_unlock("casino"), " dsa unlock ", c.service_unlock("dsa_hq"))
	var inc0: float = c._income_month()["Жилые зоны"]
	c.subsidies["housing"] = 2
	for i in 5: c.tick_day()
	print("subsidy cost ", c._upkeep_month().get("Субсидии", 0.0), " demand r ", c.demand.r)
	# space program
	var placed := {}
	for t in ["dsa_hq", "launchpad", "mission_control"]:
		for y in range(20, 100):
			for x in range(5, 60):
				if not placed.has(t) and c.service_placement(t, Vector2i(x, y), -1).ok:
					placed[t] = c.place_service(t, Vector2i(x, y), -1)
		if not placed.has(t):
			print(t, " not placed: ", c.service_placement(t, Vector2i(30, 80), -1).reason)
	print("space agency ", c.space.has_agency(c), " pads ", c.space.pads(c).size(), " rp/month ", c.space.rp_month(c))
	c.space.supplies = 1000.0
	print("launch test: ", c.space.launch(c, "test"), " state comsat: ", c.space.mission_state(c, "comsat"))
	c.space.target = "manned"
	for i in 120: c.tick_day()
	print("done ", c.space.done, " researched ", c.space.researched.keys())
	print("achievements ", c.achievements.keys())
	var d = c.to_dict()
	var c2 = City.new()
	c2.from_dict(d)
	print("load: ministries ", c2.hall().ministries, " space ", c2.space.done, " subsidies ", c2.subsidies)
	quit()
