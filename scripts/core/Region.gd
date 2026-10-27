class_name Region
extends RefCounted
## The region around the city (as in SimCity): neighbouring towns that grow on their own,
## trade electricity and water with you, take your garbage and send commuters.
## They like good deals and dislike the sewage your river carries to them.

const SPECS := {
	"industry": {"name": "Промышленный центр", "power": 0.9, "water": 0.6, "workers": 1.2},
	"tourism": {"name": "Курортный город", "power": 0.5, "water": 0.9, "workers": 0.6},
	"energy": {"name": "Энергетическая столица", "power": 2.0, "water": 0.7, "workers": 0.8},
	"farming": {"name": "Аграрный край", "power": 0.6, "water": 1.6, "workers": 0.7},
	"suburb": {"name": "Спальный пригород", "power": 0.6, "water": 0.8, "workers": 1.6},
}
const DEALS := {
	"sell_power": {"name": "Продавать излишки электричества", "desc": "Соседи покупают всё, что ваши станции производят сверх нужд города: ₽9 за МВт в месяц."},
	"buy_power": {"name": "Покупать электричество", "desc": "Недостающую энергию поставляют соседи (до %d МВт): ₽24 за МВт в месяц."},
	"sell_water": {"name": "Продавать воду", "desc": "Излишки воды уходят соседям: ₽7 за тыс. м³ в месяц."},
	"buy_water": {"name": "Покупать воду", "desc": "Соседи подают воду, когда своей не хватает (до %d тыс. м³): ₽18 за тыс. м³."},
	"garbage": {"name": "Вывозить мусор к соседям", "desc": "Мусор из домов без вывоза увозят на полигоны соседей: ₽40 за тонну."},
	"workers": {"name": "Пускать работников из пригородов", "desc": "Жители соседних городов приезжают на ваши свободные рабочие места (до %d человек). Больше машин на въезде."},
}
const SELL_POWER := 9.0
const BUY_POWER := 24.0
const SELL_WATER := 7.0
const BUY_WATER := 18.0
const GARBAGE := 40.0

var neighbors: Array = []     # {name, pop, spec, mood (0..100), dir}
var deals := {}               # deal id -> bool
var used := {"power_in": 0.0, "water_in": 0.0, "power_out": 0.0, "water_out": 0.0, "garbage": 0.0, "workers": 0}
var news: Array = []          # recent regional events (shown in the region window)


func generate(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = c.seed + 777
	neighbors.clear()
	var names: Array = Defs.CITY_NAMES.duplicate()
	names.erase(c.city_name)
	var specs: Array = SPECS.keys()
	var dirs := ["на западе", "на севере", "на юге"]
	for k in 3:
		var nm: String = names[r.randi() % names.size()]
		names.erase(nm)
		var sp: String = specs[r.randi() % specs.size()]
		specs.erase(sp)
		neighbors.append({"name": nm, "pop": r.randi_range(4000, 26000), "spec": sp, "mood": 55.0, "dir": dirs[k]})
	for d in DEALS:
		deals[d] = false


func total_pop() -> int:
	var s := 0
	for nb in neighbors:
		s += int(nb.pop)
	return s


func _cap(key: String, base: float) -> float:
	var s := 0.0
	for nb in neighbors:
		s += nb.pop * SPECS[nb.spec][key]
	return roundf(s * base)


func power_cap() -> float:
	return _cap("power", 0.012)


func water_cap() -> float:
	return _cap("water", 0.009)


func workers_cap() -> int:
	return int(_cap("workers", 0.03))


func deal_desc(d: String) -> String:
	var t: String = DEALS[d].desc
	if d == "buy_power":
		return t % int(power_cap())
	if d == "buy_water":
		return t % int(water_cap())
	if d == "workers":
		return t % workers_cap()
	return t


## Money flows of the deals per month: [income, expense].
func monthly_money() -> Vector2:
	var inc: float = used.power_out * SELL_POWER + used.water_out * SELL_WATER
	var exp: float = used.power_in * BUY_POWER + used.water_in * BUY_WATER + used.garbage * GARBAGE
	return Vector2(inc, exp)


## A month passes in the region: towns grow, moods change, sometimes something happens.
func month(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = c.seed + c.day
	# water leaving the map near its edges: the neighbours get what your river carries
	var river_dirty := 0.0
	var n: int = c.n
	var cnt := 0
	for i in n * n:
		var x := i % n
		var y := i / n
		if c.terrain[i] == 1 and (x < 4 or y < 4 or x > n - 5 or y > n - 5):
			river_dirty += c.water_pol[i]
			cnt += 1
	river_dirty = river_dirty / maxf(cnt, 1) * 3.0
	for nb in neighbors:
		nb.pop = int(nb.pop * r.randf_range(1.0, 1.025))
		var target := 55.0
		for d in deals:
			if deals[d]:
				target += 5.0
		target -= river_dirty * 40.0
		nb.mood = clampf(lerpf(nb.mood, target, 0.25), 0.0, 100.0)
	if river_dirty > 0.3:
		_news(c, "Соседи жалуются: река приносит к ним грязную воду из вашего города.")
	if r.randf() < 0.25:
		var nb: Dictionary = neighbors[r.randi() % neighbors.size()]
		var ev := ["построил новый стадион", "открыл университет", "запустил новую электростанцию", "провёл городской фестиваль",
			"расширил промзону", "открыл аквапарк", "выбрал нового мэра", "проложил новое шоссе к вашему городу"]
		_news(c, "«%s» %s." % [nb.name, ev[r.randi() % ev.size()]])


func _news(c, text: String) -> void:
	news.push_front("%s: %s" % [Defs.date_string(c.day), text])
	if news.size() > 6:
		news.pop_back()
	c.log_event("region", "Новости региона", text)


func to_dict() -> Dictionary:
	return {"neighbors": neighbors, "deals": deals, "news": news}


func from_dict(d: Dictionary, c) -> void:
	if d.is_empty():
		generate(c)
		return
	neighbors = d.get("neighbors", [])
	deals = d.get("deals", {})
	news = d.get("news", [])
	for k in DEALS:
		if not deals.has(k):
			deals[k] = false
