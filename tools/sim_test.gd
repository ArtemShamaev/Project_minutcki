extends SceneTree
func _init():
	var c = City.new()
	c.generate(12345)
	Demo.build(c, 0)
	for d in 720:
		c.tick_day()
		if d % 60 == 0:
			var ab = 0; var cons = 0; var nopw = 0; var nowt = 0; var lv = [0,0,0,0]
			for b in c.buildings.values():
				if b.abandoned: ab += 1
				if b.build_days > 0: cons += 1
				if not b.is_service() and not b.powered: nopw += 1
				if not b.is_service() and not b.watered: nowt += 1
				lv[b.level] += 1
			print("day %d pop %d jobs %d bld %d aband %d constr %d nopow %d nowat %d | P %d/%d W %d/%d | dem r%.0f c%.0f i%.0f | happy %.0f money %.0f/%.0f lv %s" % [c.day, c.population, c.jobs, c.buildings.size(), ab, cons, nopw, nowt, c.power_demand, c.power_supply, c.water_demand, c.water_supply, c.demand.r, c.demand.c, c.demand.i, c.avg_happiness, c.projected.get("income",0), c.projected.get("expense",0), str(lv)])
	quit()
