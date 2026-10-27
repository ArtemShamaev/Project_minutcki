class_name People
extends RefCounted
## Individual citizens: every resident has a name, age, education, family, home and job.
## A year of a citizen's life passes in one game month, so families grow, children go to
## school, graduate, find work, retire and pass away while you play. Kept in sync with the
## occupancy of residential buildings (the economy simulation stays aggregate).

const EDU_NAMES := ["без образования", "школа", "колледж", "университет"]

class Person:
	var id := 0
	var seed := 0
	var female := false
	var first := ""
	var last := ""
	var age := 0           # years
	var edu := 0           # 0 none, 1 school, 2 college, 3 university
	var home := -1         # building id
	var work := -1         # building id
	var family := 0        # household id
	var partner := -1
	var parents: Array = []

var city
var persons := {}          # id -> Person
var by_home := {}          # building id -> Array of person ids
var by_work := {}          # building id -> Array of person ids
var next_id := 1
var next_family := 1
var rng := RandomNumberGenerator.new()
var births_month := 0
var graduates_month := 0


func setup(c) -> void:
	city = c
	rng.seed = c.seed + 4242


func count() -> int:
	return persons.size()


func get_person(id: int) -> Person:
	return persons.get(id)


func residents(b) -> Array:
	return by_home.get(b.id, [])


func workers(b) -> Array:
	return by_work.get(b.id, [])


# ------------------------------------------------------------------ creation
func _new_person(age: int, female: bool, last: String, home: int, family: int) -> Person:
	var p := Person.new()
	p.id = next_id
	next_id += 1
	p.seed = rng.randi()
	p.female = female
	var r := RandomNumberGenerator.new()
	r.seed = p.seed
	p.first = (Citizens.FIRST_F if female else Citizens.FIRST_M)[r.randi() % Citizens.FIRST_M.size()]
	p.last = last + ("а" if female and not last.ends_with("а") else "")
	p.age = age
	p.home = home
	p.family = family
	persons[p.id] = p
	if not by_home.has(home):
		by_home[home] = []
	by_home[home].append(p.id)
	return p


func _surname() -> String:
	return Citizens.LAST[rng.randi() % Citizens.LAST.size()]


## A household moving in: a single person, a couple, a family with children or pensioners.
func _move_in(b, room: int) -> int:
	var fam := next_family
	next_family += 1
	var last := _surname()
	var edu_home: float = city.avg_cover(b, "edu")
	var roll := rng.randf()
	var made := 0
	if roll < 0.2 or room == 1:
		var p := _new_person(rng.randi_range(19, 40), rng.randf() < 0.5, last, b.id, fam)
		p.edu = _start_edu(p.age, edu_home)
		made = 1
	elif roll < 0.85:
		var a := _new_person(rng.randi_range(23, 50), false, last, b.id, fam)
		var w := _new_person(clampi(a.age + rng.randi_range(-5, 3), 20, 60), true, last, b.id, fam)
		a.partner = w.id; w.partner = a.id
		a.edu = _start_edu(a.age, edu_home); w.edu = _start_edu(w.age, edu_home)
		made = 2
		var kids := mini(rng.randi_range(0, 3), room - 2)
		for k in kids:
			var age := rng.randi_range(0, mini(17, w.age - 19))
			var ch := _new_person(maxi(age, 0), rng.randf() < 0.5, last, b.id, fam)
			ch.parents = [a.id, w.id]
			ch.edu = 1 if ch.age >= 17 and edu_home > 0.3 else 0
			made += 1
	else:
		var a := _new_person(rng.randi_range(65, 80), false, last, b.id, fam)
		a.edu = _start_edu(40, edu_home)
		made = 1
		if room >= 2 and rng.randf() < 0.6:
			var w := _new_person(clampi(a.age + rng.randi_range(-4, 2), 62, 85), true, last, b.id, fam)
			w.edu = a.edu
			a.partner = w.id; w.partner = a.id
			made = 2
	return made


func _start_edu(age: int, cover: float) -> int:
	if age < 18:
		return 0
	var e := 1 if rng.randf() < 0.55 + cover * 0.4 else 0
	if e == 1 and age >= 21 and rng.randf() < 0.25 + cover * 0.4:
		e = 2
	if e == 2 and age >= 23 and rng.randf() < 0.2 + cover * 0.4:
		e = 3
	return e


func _remove(p: Person) -> void:
	persons.erase(p.id)
	if by_home.has(p.home):
		by_home[p.home].erase(p.id)
	if p.work >= 0 and by_work.has(p.work):
		by_work[p.work].erase(p.id)
	if p.partner >= 0 and persons.has(p.partner):
		persons[p.partner].partner = -1


## A whole family leaves the city.
func _move_out(home_id: int) -> int:
	var ids: Array = by_home.get(home_id, [])
	if ids.is_empty():
		return 0
	var fam: int = persons[ids[ids.size() - 1]].family
	var gone := 0
	for id in ids.duplicate():
		var p: Person = persons[id]
		if p.family == fam:
			_remove(p)
			gone += 1
	return gone


# ------------------------------------------------------------------ sync with the city
## Matches residents to building occupancy, drops people of demolished buildings, fills jobs.
func sync() -> void:
	var alive := {}
	for b in city.buildings.values():
		if b.type != "zone":
			continue
		alive[b.id] = true
		if b.kind() != "r":
			continue
		var have: int = by_home.get(b.id, []).size()
		var guard := 0
		while have < b.occ and guard < 20:
			have += _move_in(b, b.occ - have)
			guard += 1
		guard = 0
		while have > b.occ and guard < 20:
			have -= _move_out(b.id)
			guard += 1
	for hid in by_home.keys():
		if not alive.has(hid):
			for id in by_home[hid].duplicate():
				_remove(persons[id])
			by_home.erase(hid)
	for wid in by_work.keys():
		if not alive.has(wid) or not city.buildings.has(wid):
			for id in by_work[wid]:
				if persons.has(id):
					persons[id].work = -1
			by_work.erase(wid)
	_assign_jobs()


func _job_slots() -> Array:
	var out: Array = []
	for b in city.buildings.values():
		if b.type == "zone" and b.kind() != "r" and not b.abandoned and b.build_days == 0 and b.cap > 0:
			var free: int = b.cap - by_work.get(b.id, []).size()
			if free > 0:
				out.append([b, free])
	return out


## Adults look for work that fits their education (offices want graduates, factories don't).
func _assign_jobs() -> void:
	var slots := _job_slots()
	if slots.is_empty():
		return
	var tries := 0
	for p: Person in persons.values():
		if p.work >= 0 or p.age < 18 or p.age >= 65 or is_student(p):
			if p.work >= 0 and (p.age >= 65):
				retire(p)
			continue
		tries += 1
		if tries > 400:
			break
		var best = null
		var bs := -1.0
		for k in 6:
			var s: Array = slots[rng.randi() % slots.size()]
			if s[1] <= 0:
				continue
			var b = s[0]
			var want := 2 if b.zone == Defs.OFFICE else (0 if b.zone == Defs.IND or b.zone == Defs.AGRI else 1)
			var score := 1.0 - absf(p.edu - want) * 0.3 + rng.randf() * 0.3
			if score > bs:
				bs = score
				best = s
		if best == null:
			continue
		p.work = best[0].id
		best[1] -= 1
		if not by_work.has(p.work):
			by_work[p.work] = []
		by_work[p.work].append(p.id)


func retire(p: Person) -> void:
	if p.work >= 0 and by_work.has(p.work):
		by_work[p.work].erase(p.id)
	p.work = -1


func is_student(p: Person) -> bool:
	return p.age >= 18 and p.age <= 23 and p.edu < 3 and city.edu_level > 0.25 and (p.seed % 3 == 0)


## One citizen died in building b (called by the death care simulation).
func die_in(b) -> Person:
	var ids: Array = by_home.get(b.id, [])
	var oldest: Person = null
	for id in ids:
		var p: Person = persons[id]
		if oldest == null or p.age > oldest.age:
			oldest = p
	if oldest:
		_remove(oldest)
	return oldest


# ------------------------------------------------------------------ a year passes (every game month)
func month() -> void:
	births_month = 0
	graduates_month = 0
	var newborn: Array = []
	for p: Person in persons.values():
		p.age += 1
		var cover: float = 0.0
		var hb = city.buildings.get(p.home)
		if hb:
			cover = city.avg_cover(hb, "edu")
		# education milestones
		if p.age == 17 and cover > 0.25 and p.edu == 0:
			p.edu = 1
			graduates_month += 1
		elif p.age == 21 and p.edu == 1 and cover > 0.45 and rng.randf() < 0.6:
			p.edu = 2
			graduates_month += 1
		elif p.age == 23 and p.edu == 2 and cover > 0.65 and rng.randf() < 0.5:
			p.edu = 3
			graduates_month += 1
		if p.age >= 65 and p.work >= 0:
			retire(p)
		# a couple may have a child if the flat has room
		if p.female and p.partner >= 0 and p.age >= 20 and p.age <= 40 and hb and rng.randf() < 0.05:
			if hb.occ < hb.cap:
				newborn.append(p)
	for mom: Person in newborn:
		var hb = city.buildings.get(mom.home)
		if hb == null:
			continue
		if hb.occ >= hb.cap:
			# a grown-up child moves out to make room for the baby
			var leaver: Person = null
			for id in by_home.get(hb.id, []):
				var o: Person = persons[id]
				if o.age >= 18 and o.parents.size() > 0:
					leaver = o
					break
			if leaver == null:
				continue
			_remove(leaver)
			hb.occ -= 1
		var ch := _new_person(0, rng.randf() < 0.5, mom.last.trim_suffix("а") if mom.last.ends_with("ва") or mom.last.ends_with("на") else mom.last, mom.home, mom.family)
		ch.parents = [mom.id, mom.partner]
		hb.occ += 1
		births_month += 1
	# young adults sometimes find a partner in the same building
	_assign_jobs()


# ------------------------------------------------------------------ queries for the UI
func occupation(p: Person) -> String:
	if p.age < 7:
		return "дошкольник"
	if p.age < 18:
		return "школьник"
	if is_student(p):
		return "студент"
	if p.age >= 65:
		return "пенсионер"
	if p.work >= 0 and city.buildings.has(p.work):
		return "работает: " + city.buildings[p.work].display_name()
	return "ищет работу"


func full_name(p: Person) -> String:
	return "%s %s" % [p.first, p.last]


func family_of(p: Person) -> Array:
	var out: Array = []
	for id in by_home.get(p.home, []):
		var o: Person = persons[id]
		if o.family == p.family and o.id != p.id:
			out.append(o)
	return out


## A resident of building b suited for a trip (workers for commuting, anyone otherwise).
func pick_traveller(b, to_work: bool) -> Person:
	var ids: Array = by_home.get(b.id, [])
	if ids.is_empty():
		return null
	for k in 6:
		var p: Person = persons[ids[rng.randi() % ids.size()]]
		if not to_work or p.work >= 0:
			if p.age >= 6:
				return p
	return null


func age_groups() -> Array:
	var g := [0, 0, 0, 0, 0]   # children, teens, young adults, adults, seniors
	for p: Person in persons.values():
		var k := 0 if p.age < 13 else (1 if p.age < 18 else (2 if p.age < 30 else (3 if p.age < 65 else 4)))
		g[k] += 1
	return g


func edu_groups() -> Array:
	var g := [0, 0, 0, 0]
	for p: Person in persons.values():
		if p.age >= 18:
			g[p.edu] += 1
	return g


# ------------------------------------------------------------------ save / load
func to_dict() -> Dictionary:
	var arr := PackedInt32Array()
	for p: Person in persons.values():
		arr.append_array([p.id, p.seed, 1 if p.female else 0, p.age, p.edu, p.home, p.work, p.family, p.partner,
			p.parents[0] if p.parents.size() > 0 else -1, p.parents[1] if p.parents.size() > 1 else -1])
	var names := PackedStringArray()
	for p: Person in persons.values():
		names.append(p.first + "|" + p.last)
	return {"a": arr, "n": names, "next": next_id, "fam": next_family}


func from_dict(d: Dictionary) -> void:
	persons.clear(); by_home.clear(); by_work.clear()
	if not d.has("a"):
		return
	var a: PackedInt32Array = d.a
	var names: PackedStringArray = d.n
	var k := 0
	for i in range(0, a.size(), 11):
		var p := Person.new()
		p.id = a[i]; p.seed = a[i + 1]; p.female = a[i + 2] == 1; p.age = a[i + 3]; p.edu = a[i + 4]
		p.home = a[i + 5]; p.work = a[i + 6]; p.family = a[i + 7]; p.partner = a[i + 8]
		if a[i + 9] >= 0: p.parents.append(a[i + 9])
		if a[i + 10] >= 0: p.parents.append(a[i + 10])
		var nm := names[k].split("|")
		p.first = nm[0]; p.last = nm[1] if nm.size() > 1 else ""
		k += 1
		persons[p.id] = p
		if not by_home.has(p.home): by_home[p.home] = []
		by_home[p.home].append(p.id)
		if p.work >= 0:
			if not by_work.has(p.work): by_work[p.work] = []
			by_work[p.work].append(p.id)
	next_id = int(d.get("next", next_id))
	next_family = int(d.get("fam", next_family))
