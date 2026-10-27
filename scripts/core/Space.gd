class_name Space
extends RefCounted
## УГК — Управление городской космонавтики (like the DSA in TheoTown).
## Trucks bring supplies from factories to the launch pads, rockets are tested first, astronauts
## are trained, research opens new missions, and missions give lasting bonuses: satellites,
## a space station, an orbital power plant, a lunar program of four missions that opens a Moon
## colony (helium-3 mining, exports to Earth), and finally Mars.

const TRAIN_DAYS := 20.0
const CREW_PER_CENTER := 4

var researched := {"rockets": true}
var target := ""                # topic being researched
var progress := 0.0             # research points spent on the target
var done := {}                  # mission id -> successful launches
var fails := {}                 # mission id -> failed launches
var active: Array = []          # {id, left (days), days, pad (building id), crew}
var log: Array = []             # recent space news
var crew_days := 0              # happiness boost after a crewed flight
var mourn_days := 0             # the city mourns lost astronauts
var supplies := 0.0             # rocket supplies stored at the pads
var astronauts := 0             # trained, ready to fly
var lost := 0                   # astronauts lost in accidents
var train := 0.0                # training progress, days
var he3 := 0.0                  # helium-3 in the city's storage (for the helium power plants)
var colonies := {}              # "moon"/"mars" -> {tiles: Array, build: Array, stock, exported}
var version := 0                # bumps when a colony changes (the UI rebuilds its 3D view)
signal launched(pad_id: int, ok: bool)
signal exploded(pad_id: int)
signal orbit_changed


# ------------------------------------------------------------------ buildings
func _count(c, type: String) -> int:
	var n := 0
	for b in c.buildings.values():
		if b.type == type and b.is_service() and b.done():
			n += 1
	return n


func has_agency(c) -> bool:
	return _count(c, "dsa_hq") > 0


func pads(c) -> Array:
	var out: Array = []
	for b in c.buildings.values():
		if (b.type == "launchpad" or b.type == "spaceport") and b.done():
			out.append(b)
	return out


func free_pad(c):
	for b in pads(c):
		var busy := false
		for a in active:
			if a.pad == b.id:
				busy = true
		if not busy:
			return b
	return null


## Research points per month.
func rp_month(c) -> float:
	var r := 0.0
	for b in c.buildings.values():
		if not b.is_service() or not b.done():
			continue
		match b.type:
			"dsa_hq": r += 12.0
			"mission_control": r += 5.0
			"observatory": r += 4.0
			"university": r += 3.0
			"college": r += 1.0
	if c.has_ministry("science"):
		r += 5.0
	if station_ready():
		r += 15.0
	if has("telescope"):
		r += 10.0
	for cid in colonies:
		r += colony_stats(cid).rp
	return r * (0.6 + c.edu_level)


# ------------------------------------------------------------------ supplies (TheoTown: trucks bring them to the pad)
func supply_cap(c) -> float:
	var cap := 0.0
	for b in pads(c):
		cap += 8000.0 if b.type == "spaceport" else 4000.0
	return cap + (2000.0 if cap > 0.0 else 0.0)


## Supplies per day: rocket factories plus industry near the pads and factories.
func supply_rate(c) -> float:
	var ps := pads(c)
	if ps.is_empty():
		return 0.0
	var hubs: Array = ps.duplicate()
	var factories := 0
	for b in c.buildings.values():
		if b.type == "rocket_factory" and b.done():
			hubs.append(b)
			factories += 1
	var ind := 0.0
	for b in c.buildings.values():
		if b.type != "zone" or b.zone != Defs.IND or b.occ <= 0 or not b.has_road:
			continue
		for h in hubs:
			if b.center().distance_to(h.center()) < 40.0:
				ind += b.occ
				break
	var r := 8.0 + minf(ind * 0.05, 80.0)
	r += factories * 60.0 * (1.0 + minf(ind / 400.0, 1.0))
	return r


func supplies_need(id: String) -> float:
	return Defs.MISSIONS[id].get("supplies", 0) * (0.75 if researched.has("reusable") else 1.0)


# ------------------------------------------------------------------ astronauts
func crew_flying() -> int:
	var n := 0
	for a in active:
		n += int(a.get("crew", 0))
	return n


func crew_capacity(c) -> int:
	return _count(c, "astro_center") * CREW_PER_CENTER


# ------------------------------------------------------------------ research & missions
func can_research(id: String) -> bool:
	var r: Dictionary = Defs.RESEARCH[id]
	return not researched.has(id) and (not r.has("need") or researched.has(r.need)) and (not r.has("need2") or researched.has(r.need2))


func mission_state(c, id: String) -> String:
	var m: Dictionary = Defs.MISSIONS[id]
	if not researched.has(m.need):
		return "Нужно исследование «%s»" % Defs.RESEARCH[m.need].name
	if m.has("after") and done.get(m.after, 0) == 0:
		return "Сначала — «%s»" % Defs.MISSIONS[m.after].name
	if m.get("once", false) and done.get(id, 0) > 0:
		return "Выполнено"
	if m.has("max") and done.get(id, 0) >= m.max:
		return "Выполнено (%d/%d)" % [m.max, m.max]
	for a in active:
		if a.id == id:
			return "Летит…"
	if not has_agency(c):
		return "Нужен штаб УГК"
	if pads(c).is_empty():
		return "Нужен стартовый стол"
	if free_pad(c) == null:
		return "Все стартовые столы заняты"
	var cr: int = m.get("crew", 0)
	if cr > 0 and crew_capacity(c) == 0:
		return "Нужен центр подготовки космонавтов"
	if cr > astronauts:
		return "Нужно космонавтов: %d (готово %d)" % [cr, astronauts]
	if supplies < supplies_need(id):
		return "Снабжение: %s из %s" % [Defs.fmt_int(supplies), Defs.fmt_int(supplies_need(id))]
	if c.money < cost(id):
		return "Недостаточно денег"
	return ""


func cost(id: String) -> float:
	return Defs.MISSIONS[id].cost * (0.6 if researched.has("reusable") else 1.0)


func tests_ok() -> int:
	return mini(done.get("test", 0), 3)


func chance(c, id: String) -> float:
	var ch: float = Defs.MISSIONS[id].chance
	ch += 0.05 * mini(_count(c, "mission_control"), 2)
	ch += 0.05 * tests_ok()
	ch += 0.02 * done.get(id, 0) + 0.03 * fails.get(id, 0)   # experience, lessons learned
	return clampf(ch, 0.05, 0.98)


func launch(c, id: String) -> bool:
	if mission_state(c, id) != "":
		return false
	var pad = free_pad(c)
	var m: Dictionary = Defs.MISSIONS[id]
	c.money -= cost(id)
	supplies -= supplies_need(id)
	var cr: int = m.get("crew", 0)
	astronauts -= cr
	active.append({"id": id, "left": int(m.days), "days": int(m.days), "pad": pad.id, "crew": cr})
	_news(c, "Старт: %s" % m.name + (" (экипаж: %d)" % cr if cr > 0 else ""))
	launched.emit(pad.id, true)
	return true


## A day passes: supplies arrive, astronauts train, research advances, missions fly.
func day(c) -> void:
	if crew_days > 0:
		crew_days -= 1
	if mourn_days > 0:
		mourn_days -= 1
	supplies = minf(supplies + supply_rate(c), supply_cap(c))
	var centers := _count(c, "astro_center")
	if centers > 0 and astronauts + crew_flying() < centers * CREW_PER_CENTER:
		train += centers
		if train >= TRAIN_DAYS:
			train = 0.0
			astronauts += 1
			if astronauts == 1 and done.is_empty():
				c.notify.emit("👨‍🚀 Первый космонавт города готов к полёту!", "good")
	if target != "" and has_agency(c):
		progress += rp_month(c) / Defs.DAYS_PER_MONTH
		if progress >= Defs.RESEARCH[target].rp:
			researched[target] = true
			_news(c, "Исследование завершено: %s" % Defs.RESEARCH[target].name)
			c.notify.emit("🔬 УГК: «%s» изучено!" % Defs.RESEARCH[target].name, "good")
			target = ""
			progress = 0.0
	_helium_day(c)
	for a in active.duplicate():
		a.left -= 1
		if a.left > 0:
			continue
		active.erase(a)
		var m: Dictionary = Defs.MISSIONS[a.id]
		var cr: int = a.get("crew", 0)
		if randf() < chance(c, a.id):
			done[a.id] = done.get(a.id, 0) + 1
			astronauts += cr
			if a.id == "crew":
				crew_days = 360
			_news(c, "Успех: %s" % m.name)
			orbit_changed.emit()
			c.notify.emit("🚀 Миссия «%s» выполнена! %s" % [m.name, m.desc], "good")
			c.log_event("space", "УГК: «%s» — успех!" % m.name, m.desc)
			if a.id == "moonbase":
				open_colony(c, "moon")
			elif a.id == "colony":
				open_colony(c, "mars")
		else:
			fails[a.id] = fails.get(a.id, 0) + 1
			if a.id == "test":
				exploded.emit(a.pad)
			_news(c, "Авария: %s" % m.name)
			if cr > 0:
				lost += cr
				mourn_days = 90
				c.notify.emit("🕯 Трагедия: миссия «%s» потеряна вместе с экипажем (%d чел.). Город в трауре." % [m.name, cr], "bad")
				c.log_event("space", "Трагедия в космосе: «%s»" % m.name, "Экипаж из %d космонавтов погиб. Комиссия УГК выясняет причины, следующие полёты станут надёжнее." % cr)
			else:
				c.notify.emit("💥 Миссия «%s» потерпела неудачу. Деньги и снабжение потеряны, но опыт остался (+3%% к надёжности)." % m.name, "bad")
				c.log_event("space", "УГК: авария миссии «%s»" % m.name, "Комиссия выясняет причины. Следующий запуск будет надёжнее.")
	for k in [["moonbase", "moon"], ["colony", "mars"]]:
		if has(k[0]) and not colonies.has(k[1]):
			open_colony(c, k[1])
	if c.day % Defs.DAYS_PER_MONTH == 0:
		_colonies_month(c)


func _news(c, t: String) -> void:
	log.push_front("%s: %s" % [Defs.date_string(c.day), t])
	if log.size() > 12:
		log.pop_back()


## Locked УГК buildings: "" when it can be built, otherwise the reason.
func unlock_reason(id: String) -> String:
	match id:
		"rectenna":
			return "" if researched.has("space_power") else "Нужно исследование «Космическая энергетика»"
		"space_museum":
			return "" if has("moon") else "Откроется после высадки на Луну"
		"he3_plant":
			return "" if exported("moon") >= 100.0 else "Откроется после экспорта 100 т гелия-3 с Луны (сейчас %d)" % int(exported("moon"))
	return ""


## Space-powered buildings work only when the space part is there.
func power_factor(b) -> float:
	match b.type:
		"rectenna":
			return 1.0 if has("solarsat") else 0.0
		"he3_plant":
			return 1.0 if he3 >= 2.0 else 0.0
	return 1.0


func _helium_day(c) -> void:
	var n := _count(c, "he3_plant")
	if n > 0:
		he3 = maxf(0.0, he3 - 2.0 * n)


# ------------------------------------------------------------------ colonies (TheoTown's Moon)
func colony_open(cid: String) -> bool:
	return colonies.has(cid)


func exported(cid: String) -> float:
	return float(colonies[cid].get("exported", 0.0)) if colonies.has(cid) else 0.0


func open_colony(c, cid: String) -> void:
	if colonies.has(cid):
		return
	var sz := Defs.COLONY_SIZE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cid) + int(c.seed)
	var tiles: Array = []
	tiles.resize(sz.x * sz.y)
	tiles.fill(0)
	# craters, then clusters of ore and ice
	for k in 7:
		var p := Vector2i(rng.randi_range(0, sz.x - 1), rng.randi_range(0, sz.y - 1))
		tiles[p.y * sz.x + p.x] = 1
		if rng.randf() < 0.5 and p.x + 1 < sz.x:
			tiles[p.y * sz.x + p.x + 1] = 1
	for kind in [2, 2, 2, 3, 3]:
		var p := Vector2i(rng.randi_range(1, sz.x - 2), rng.randi_range(1, sz.y - 2))
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if rng.randf() < 0.8 or d == Vector2i.ZERO:
				tiles[(p.y + d.y) * sz.x + p.x + d.x] = kind
	var build: Array = []
	build.resize(sz.x * sz.y)
	build.fill("")
	# the base from the mission: one module with a solar farm next to it
	var ctr := Vector2i(sz.x / 2, sz.y / 2)
	for d in [Vector2i.ZERO, Vector2i(1, 0)]:
		var i: int = (ctr.y + d.y) * sz.x + ctr.x + d.x
		tiles[i] = 0
	build[ctr.y * sz.x + ctr.x] = "hab"
	build[ctr.y * sz.x + ctr.x + 1] = "solar"
	colonies[cid] = {"tiles": tiles, "build": build, "stock": 0.0, "exported": 0.0}
	version += 1
	var cd: Dictionary = Defs.COLONIES[cid]
	c.notify.emit("🌕 Колония «%s» основана! Откройте УГК [K] → вкладка «%s»." % [cd.name, cd.name], "good")


func colony_count(cid: String, bid: String) -> int:
	if not colonies.has(cid):
		return 0
	return (colonies[cid].build as Array).count(bid)


## Colony economy: energy, water, colonists and workers decide how well everything works.
func colony_stats(cid: String) -> Dictionary:
	var st := {"pop": 0, "power_prod": 0.0, "power_use": 0.0, "workers": 0, "habs": 0, "habs_ok": 0, "eff": 0.0, "prod": 0.0, "rp": 0.0, "income": 0.0}
	if not colonies.has(cid):
		return st
	for bid in colonies[cid].build:
		if bid == "":
			continue
		var bd: Dictionary = Defs.COLONY_BUILD[bid]
		var pw: float = bd.get("power", 0)
		if pw > 0.0:
			st.power_prod += pw
		else:
			st.power_use -= pw
		st.workers += int(bd.get("workers", 0))
	st.habs = colony_count(cid, "hab")
	st.habs_ok = mini(st.habs, 1 + 4 * colony_count(cid, "ice"))
	var per := 40 if researched.has("life") else 20
	var p_eff := clampf(st.power_prod / maxf(st.power_use, 0.01), 0.0, 1.0)
	st.pop = int(st.habs_ok * per * p_eff)
	var w_eff := clampf(float(st.pop) / maxf(st.workers, 1.0), 0.0, 1.0)
	st.eff = minf(p_eff, w_eff)
	st.prod = colony_count(cid, "mine") * 30.0 * st.eff * (2.0 if cid == "moon" and researched.has("he3") else 1.0)
	st.rp = colony_count(cid, "lab") * 10.0 * st.eff
	if colony_count(cid, "port") > 0:
		st.income = st.prod * Defs.COLONIES[cid].price
	return st


func build_state(c, cid: String, i: int, bid: String) -> String:
	if not colonies.has(cid):
		return "Колонии ещё нет"
	var col: Dictionary = colonies[cid]
	var bd: Dictionary = Defs.COLONY_BUILD[bid]
	if col.build[i] != "":
		return "Клетка занята"
	var t: int = col.tiles[i]
	if t == 1:
		return "Здесь кратер"
	var need: int = bd.get("tile", 0)
	if need != t:
		return "Только на месторождение" if need == 2 else ("Только на лёд" if need == 3 else "Не занимайте месторождения — для них есть шахты")
	if bd.has("max") and colony_count(cid, bid) >= int(bd.max):
		return "Уже построено"
	if c.money < bd.cost:
		return "Недостаточно денег"
	return ""


func colony_build(c, cid: String, i: int, bid: String) -> bool:
	if build_state(c, cid, i, bid) != "":
		return false
	c.money -= Defs.COLONY_BUILD[bid].cost
	colonies[cid].build[i] = bid
	version += 1
	return true


func colony_demolish(cid: String, i: int) -> bool:
	if not colonies.has(cid) or colonies[cid].build[i] == "":
		return false
	if colonies[cid].build[i] == "hab" and colony_count(cid, "hab") <= 1:
		return false
	colonies[cid].build[i] = ""
	version += 1
	return true


func _colonies_month(c) -> void:
	for cid in colonies:
		var st := colony_stats(cid)
		var col: Dictionary = colonies[cid]
		if colony_count(cid, "port") > 0:
			col.exported = float(col.exported) + st.prod
			if cid == "moon":
				he3 += st.prod
		else:
			col.stock = float(col.stock) + st.prod


# ------------------------------------------------------------------ effects used by the city
func has(id: String) -> bool:
	return done.get(id, 0) > 0


func comsats() -> int:
	return mini(done.get("comsat", 0), 3)


func station_ready() -> bool:
	return done.get("module", 0) >= 3


## Satellites and stations in orbit (for the 3D sky).
func orbiters() -> Array:
	var out: Array = []
	for k in ["weather", "gps", "telescope", "solarsat", "shield"]:
		if has(k):
			out.append(k)
	for i in comsats():
		out.append("comsat")
	if done.get("module", 0) > 0:
		out.append("station")
	return out


func tourism() -> float:
	var t := 1000.0 if crew_days > 0 else 0.0
	for k in [["telescope", 500.0], ["lunar_orbit", 1500.0], ["moon", 3000.0], ["mars", 6000.0]]:
		if has(k[0]):
			t += k[1]
	return t


func income() -> float:
	var r := 0.0
	for cid in colonies:
		r += colony_stats(cid).income
	return r


func to_dict() -> Dictionary:
	return {"researched": researched, "target": target, "progress": progress, "done": done, "fails": fails, "active": active, "log": log, "crew": crew_days,
		"mourn": mourn_days, "supplies": supplies, "astronauts": astronauts, "lost": lost, "train": train, "he3": he3, "colonies": colonies}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	researched = d.get("researched", researched)
	target = d.get("target", "")
	progress = float(d.get("progress", 0.0))
	done = d.get("done", {})
	fails = d.get("fails", {})
	active = d.get("active", [])
	log = d.get("log", [])
	crew_days = int(d.get("crew", 0))
	mourn_days = int(d.get("mourn", 0))
	supplies = float(d.get("supplies", 0.0))
	astronauts = int(d.get("astronauts", 0))
	lost = int(d.get("lost", 0))
	train = float(d.get("train", 0.0))
	he3 = float(d.get("he3", 0.0))
	colonies = d.get("colonies", {})
	for a in active:
		a.left = int(a.left)
		a.pad = int(a.pad)
		a.crew = int(a.get("crew", 0))
		a.days = int(a.get("days", a.left))
	for cid in colonies:
		var col: Dictionary = colonies[cid]
		for i in col.tiles.size():
			col.tiles[i] = int(col.tiles[i])
	# saves from before the УГК: missions that existed then were already flown without tests
	if not done.is_empty() and not done.has("test"):
		done["test"] = 1
