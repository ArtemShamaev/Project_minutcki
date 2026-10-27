extends SceneTree
func _init():
	for mt in ["river", "coast", "lakes"]:
		var c = City.new()
		c.generate(12345, mt)
		var w = WaterSim.new()
		w.setup(c)
		var vol0 := 0.0
		for v in w.d: vol0 += v
		var t0 := Time.get_ticks_usec()
		for k in 60:
			w.sweep()
		var t1 := Time.get_ticks_usec()
		var vol := 0.0; var wet := 0; var maxv := 0.0; var land_wet := 0
		for i in c.n * c.n:
			vol += w.d[i]
			if w.d[i] > 0.012:
				wet += 1
				if c.terrain[i] == 0 and w.d[i] > 0.05: land_wet += 1
			maxv = max(maxv, w.speed(i))
		print("%s: %.2f ms/sweep vol %.1f -> %.1f wet %d landwet %d maxspeed %.3f fixed %d" % [mt, (t1 - t0) / 60000.0, vol0, vol, wet, land_wet, maxv, w.fixed.size()])
		# sample river profile
		var s := ""
		for y in range(0, c.n, 15):
			var best := -1
			for x in c.n:
				if c.terrain[c.idx(x, y)] == 1 and x > 60: best = c.idx(x, y); break
			if best >= 0: s += "y%d:%.3f/%.3f " % [y, w.surface(best), w.vel[best * 2 + 1]]
		print(s)
	quit()
