extends SceneTree
func _init():
	var c = City.new()
	c.generate(12345)
	Demo.build(c, 30)
	c.milestone = 6
	c.money = 1e7
	var b = null
	for y in range(30, 90):
		for x in range(8, 50):
			if b == null and c.service_placement("spaceport", Vector2i(x, y), -1).ok:
				b = c.place_service("spaceport", Vector2i(x, y), -1)
	print("placed ", b != null)
	var pop0: int = c.population
	var e0: float = c.edu_level
	for i in 140: c.tick_day()
	print("stage ", b.stage, "/", Defs.SERVICES.spaceport.stages, " done ", b.done(), " edu %.2f -> %.2f" % [e0, c.edu_level])
	print("land: owned ", c.owned_count(), " limit ", c.land_limit())
	c.region.deals.sell_power = true
	c.region.deals.workers = true
	for i in 31: c.tick_day()
	print("region used ", c.region.used, " money/month ", c.region.monthly_money(), " news ", c.region.news.size())
	print("MEGA ", "OK" if b.done() else "FAIL")
	quit()
