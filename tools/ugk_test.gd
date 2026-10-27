extends SceneTree
## УГК: ministries without the science ministry, supplies, tests, astronauts, the lunar program, colonies.
func _place(c, t: String):
	for y in range(10, 110):
		for x in range(5, 110):
			if c.service_placement(t, Vector2i(x, y), -1).ok:
				return c.place_service(t, Vector2i(x, y), -1)
	print(t, " NOT placed: ", c.service_placement(t, Vector2i(40, 60), -1).reason)
	return null


func _init():
	var c = City.new()
	c.generate(12345)
	Demo.build(c, 30)
	c.money = 1e8
	c.milestone = 4
	var h = _place(c, "cityhall")
	print("hall slots ", c.hall_slots(), " science ministry ", c.build_ministry("science"), " finance (no slot) ", c.build_ministry("finance"))
	print("dsa unlock w/ science ", c.service_unlock("dsa_hq"))
	for t in ["dsa_hq", "launchpad", "rocket_factory", "astro_center", "mission_control", "observatory"]:
		print(t, " -> ", _place(c, t) != null)
	print("rectenna lock: ", c.service_placement("rectenna", Vector2i(50, 50), -1).reason)
	var sp: Space = c.space
	print("rate/day ", sp.supply_rate(c), " cap ", sp.supply_cap(c), " rp ", sp.rp_month(c))
	print("test state: ", sp.mission_state(c, "test"))
	for i in 10: c.tick_day()
	print("supplies after 10d ", int(sp.supplies), " astronauts ", sp.astronauts, " test state '", sp.mission_state(c, "test"), "'")
	print("crew before test: ", sp.mission_state(c, "crew"))
	var ok := 0
	for k in 8:
		sp.supplies = sp.supply_cap(c)
		if sp.launch(c, "test"):
			for i in 4: c.tick_day()
		if sp.has("test"): break
	print("tests done ", sp.done.get("test", 0), " fails ", sp.fails.get("test", 0), " chance weather ", sp.chance(c, "weather"))
	# research all and run the lunar program
	for r in Defs.RESEARCH: sp.researched[r] = true
	sp.astronauts = 10
	for mid in ["lunar_probe", "lunar_orbit", "moon", "moonbase"]:
		for tries in 6:
			sp.supplies = 1e6
			var st: String = sp.mission_state(c, mid)
			if st != "":
				print("  ", mid, " state: ", st)
				break
			sp.launch(c, mid)
			for i in Defs.MISSIONS[mid].days + 1: c.tick_day()
			if sp.has(mid): break
		print(mid, " done=", sp.has(mid), " astronauts ", sp.astronauts, " lost ", sp.lost)
	print("moon colony open ", sp.colony_open("moon"), " museum lock '", sp.unlock_reason("space_museum"), "'")
	var col: Dictionary = sp.colonies.get("moon", {})
	if not col.is_empty():
		var n := 0
		for i in col.tiles.size():
			if col.tiles[i] == 2 and n < 2 and sp.colony_build(c, "moon", i, "mine"): n += 1
		for i in col.tiles.size():
			if col.tiles[i] == 3 and sp.colony_build(c, "moon", i, "ice"): break
		for k in 4:
			for i in col.tiles.size():
				if sp.colony_build(c, "moon", i, "solar"): break
		for k in 2:
			for i in col.tiles.size():
				if sp.colony_build(c, "moon", i, "hab"): break
		for i in col.tiles.size():
			if sp.colony_build(c, "moon", i, "port"): break
		print("mine on plain: ", sp.build_state(c, "moon", 0, "mine"))
		print("colony stats ", sp.colony_stats("moon"))
		for i in 120: c.tick_day()
		print("exported ", sp.exported("moon"), " he3 ", sp.he3, " income ", sp.income(), " he3 lock '", sp.unlock_reason("he3_plant"), "'")
	print("upkeep ugk ", c._upkeep_month().get("УГК (космос)", 0.0), " income space ", c._income_month().get("Космос", 0.0))
	var d = c.to_dict()
	var c2 = City.new()
	c2.from_dict(str_to_var(var_to_str(d)))
	print("load: colonies ", c2.space.colonies.keys(), " astronauts ", c2.space.astronauts, " tile type ", typeof(c2.space.colonies["moon"].tiles[0]), " stats ", c2.space.colony_stats("moon").prod)
	quit()
