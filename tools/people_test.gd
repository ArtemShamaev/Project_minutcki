extends SceneTree
func _init():
	var c = City.new()
	c.generate(12345)
	Demo.build(c, 60)
	for m in 8:
		for i in 30: c.tick_day()
		var emp := 0
		for p in c.people.persons.values():
			if p.work >= 0: emp += 1
		print("month %d pop %d people %d employed %d ages %s edu %s births %d grads %d" % [m, c.population, c.people.count(), emp, str(c.people.age_groups()), str(c.people.edu_groups()), c.people.births_month, c.people.graduates_month])
	var b = null
	for x in c.buildings.values():
		if x.kind() == "r" and x.occ > 3: b = x; break
	for id in c.people.residents(b):
		var p = c.people.get_person(id)
		print("  ", c.people.full_name(p), ", ", p.age, ", ", People.EDU_NAMES[p.edu], ", ", c.people.occupation(p))
	var t0 := Time.get_ticks_usec()
	c.people.sync()
	print("sync ms ", (Time.get_ticks_usec() - t0) / 1000.0)
	var d = c.to_dict()
	var c2 = City.new()
	c2.from_dict(d)
	print("load people ", c2.people.count(), " == ", c.people.count())
	quit()
