extends SceneTree
## Update 8: water physics, sewers, pedestrian paths, architecture styles.
func _init():
	var c = City.new()
	c.generate(12345)
	Demo.build(c, 90)
	var ok := true
	# styles
	c.set_style(1, "soviet", true)
	var st := {}
	for b in c.buildings.values():
		if b.type == "zone":
			st[b.style] = st.get(b.style, 0) + 1
	print("styles ", st)
	ok = ok and st.get("soviet", 0) > 0
	# one building in its own style survives a district restyle and save/load
	var one = null
	for b in c.buildings.values():
		if b.type == "zone" and b.zone == Defs.R_HIGH and not b.abandoned:
			one = b; break
	c.money = 1e9
	c.set_building_style(one, "american")
	c.set_style(0, "euro", true)
	print("single building style ", one.style, " locked ", one.style_lock)
	ok = ok and one.style == "american" and one.style_lock
	# paths and walking
	var pc := 0
	for i in c.n * c.n: pc += c.path[i]
	var r = c.ped_route(Vector2i(14, 50), Vector2i(34, 50))
	print("path tiles ", pc, " ped route len ", r.size(), " walk share ", snappedf(c.walk_share, 0.01))
	ok = ok and pc > 20 and r.size() > 10
	# hydro on the river: road from the town to the east bank
	# hydro plant on a fresh map: a short road along the river bank
	var c3 = City.new()
	c3.generate(777)
	c3.money = 1e9
	c3.owned.fill(1)
	c3.milestone = 5
	var hb = null
	for yy in range(10, c3.n - 10, 3):
		if hb: break
		var xx := -1
		for x in range(60, c3.n):
			if c3.is_water(Vector2i(x, yy)):
				xx = x; break
		if xx < 0: continue
		var rp = c3.road_path(Vector2i(xx - 3, yy - 2), Vector2i(xx - 3, yy + 3))
		if not c3.check_roads(rp).ok: continue
		c3.build_roads(rp)
		for dy in range(-1, 3):
			if hb == null and c3.service_placement("hydro", Vector2i(xx - 2, yy + dy), 1).ok:
				hb = c3.place_service("hydro", Vector2i(xx - 2, yy + dy), 1)
	for i in 8: c3.tick_day()
	if hb:
		print("hydro eff ", snappedf(hb.eff, 0.01), " power ", int(c3.svc_output(hb, "power")), " MW")
	else:
		print("hydro: not placed")
	ok = ok and hb != null and hb.eff > 0.1
	# flood
	var wet0 := 0
	for i in c.n * c.n:
		if c.terrain[i] == 0 and c.water_sim.d[i] > 0.05: wet0 += 1
	c.water_sim.surge = 0.6
	for i in 150: c.water_sim.sweep()
	var wet1 := 0
	for i in c.n * c.n:
		if c.terrain[i] == 0 and c.water_sim.d[i] > 0.05: wet1 += 1
	c.water_sim.surge = 0.0
	for i in 300: c.water_sim.sweep()
	var wet2 := 0
	for i in c.n * c.n:
		if c.terrain[i] == 0 and c.water_sim.d[i] > 0.05: wet2 += 1
	print("flooded land tiles: before ", wet0, " during ", wet1, " after ", wet2)
	ok = ok and wet1 > wet0 + 20 and wet2 < wet1
	# sewers in rain
	c.weather = "rain"; c.weather_days = 5
	c.tick_day()
	var mx := 0.0
	for i in c.n * c.n: mx = max(mx, c.sew_load[i])
	print("sewer max load in rain ", snappedf(mx, 0.01), " overflow ", int(c.sew_overflow))
	# save / load
	var d = c.to_dict()
	var c2 = City.new()
	c2.from_dict(d)
	var same_w: bool = c2.water_sim.d == c.water_sim.d
	var st2 := 0
	for b in c2.buildings.values():
		if b.style == "soviet": st2 += 1
	print("load: water same ", same_w, " paths same ", c2.path == c.path, " city_style ", c2.city_style, " soviet bld ", st2)
	ok = ok and c2.buildings[one.id].style == "american" and c2.buildings[one.id].style_lock
	ok = ok and same_w and c2.path == c.path and c2.city_style == "euro" and st2 == st.get("soviet", 0)
	for i in 20: c2.tick_day()
	print("after load pop ", c2.population)
	print("UPDATE8 ", "OK" if ok else "FAIL")
	quit()
