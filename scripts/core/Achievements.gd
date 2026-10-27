class_name Achievements
## Achievements (as in TheoTown / SimCity): unlocked once, shown in the achievements window.

const LIST := {
	"pop100": {"name": "Новосёлы", "desc": "100 жителей", "icon": "zone_r"},
	"pop1k": {"name": "Городок", "desc": "1 000 жителей", "icon": "zone_r"},
	"pop5k": {"name": "Настоящий город", "desc": "5 000 жителей", "icon": "zone_r2"},
	"pop20k": {"name": "Мегаполис", "desc": "20 000 жителей", "icon": "zone_r2"},
	"rich": {"name": "Миллионер", "desc": "₽1 000 000 в казне", "icon": "budget"},
	"debtfree": {"name": "Без долгов", "desc": "Казна в плюсе и ни одного кредита при 2 000+ жителях", "icon": "budget"},
	"happy": {"name": "Счастливый город", "desc": "Счастье выше 85% при 1 000+ жителях", "icon": "health"},
	"green": {"name": "Зелёный город", "desc": "Только ветер, солнце, вода и атом — без угля", "icon": "power"},
	"clean": {"name": "Чистая река", "desc": "Очистные сооружения и ни одного грязного стока", "icon": "water"},
	"transit": {"name": "Пересаживайтесь!", "desc": "Общественным транспортом пользуются 40% жителей", "icon": "bus"},
	"walk": {"name": "Город для людей", "desc": "50 клеток пешеходных дорожек", "icon": "path"},
	"edu": {"name": "Город знаний", "desc": "Образованность 70%", "icon": "edu"},
	"land": {"name": "Землевладелец", "desc": "Купить 10 участков земли", "icon": "land"},
	"capitol": {"name": "Столица", "desc": "Ратуша выросла до Капитолия", "icon": "landmark"},
	"ministries": {"name": "Кабинет министров", "desc": "Открыть все 7 министерств", "icon": "law"},
	"mansion": {"name": "Любимый мэр", "desc": "Получить резиденцию в подарок", "icon": "landmark"},
	"tourist": {"name": "Туристическая мекка", "desc": "Пять знаменитых зданий в городе", "icon": "landmark"},
	"mega": {"name": "Чудо света", "desc": "Достроить любой мегапроект", "icon": "landmark"},
	"orbit": {"name": "Поехали!", "desc": "Первый успешный пилотируемый полёт", "icon": "region"},
	"station": {"name": "Своя станция", "desc": "Собрать орбитальную станцию", "icon": "region"},
	"moon": {"name": "Маленький шаг", "desc": "Высадиться на Луне", "icon": "region"},
	"mars": {"name": "Нам нужно дальше!", "desc": "Добраться до Марса", "icon": "region"},
	"trade": {"name": "Добрые соседи", "desc": "Все соседи дружелюбны", "icon": "region"},
	"styles": {"name": "Архитектор", "desc": "Здания трёх разных стилей в городе", "icon": "style"},
}


static func check(id: String, c) -> bool:
	match id:
		"pop100": return c.population >= 100
		"pop1k": return c.population >= 1000
		"pop5k": return c.population >= 5000
		"pop20k": return c.population >= 20000
		"rich": return c.money >= 1000000.0 and not c.sandbox
		"debtfree": return c.population >= 2000 and c.money > 0 and c.loans.is_empty()
		"happy": return c.population >= 1000 and c.avg_happiness > 85.0
		"green":
			var clean := 0
			for b in c.buildings.values():
				if b.type == "coal":
					return false
				if b.type in ["wind", "solar", "hydro", "nuclear", "fusion"]:
					clean += 1
			return clean >= 3 and c.population >= 500
		"clean":
			var has_treat := false
			for b in c.buildings.values():
				if b.type == "outlet":
					return false
				if b.type == "sewtreat":
					has_treat = true
			return has_treat
		"transit": return c.transit_share >= 0.4
		"walk":
			var n := 0
			for v in c.path:
				n += v
			return n >= 50
		"edu": return c.edu_level >= 0.7 and c.population >= 1000
		"land": return c.owned_count() >= 10
		"capitol":
			var h = c.hall()
			return h != null and h.level >= 3
		"ministries":
			var h = c.hall()
			return h != null and h.ministries.size() >= Defs.MINISTRIES.size()
		"mansion": return c._has_building("mansion")
		"tourist":
			var n := 0
			for b in c.buildings.values():
				if b.type in ["bigben", "liberty", "coliseum", "casino", "pagoda", "heaven", "cathedral", "tvtower", "museum", "zoo", "stadium"]:
					n += 1
			return n >= 5
		"mega":
			for b in c.buildings.values():
				if b.is_service() and Defs.SERVICES[b.type].has("stages") and b.done():
					return true
			return false
		"orbit": return c.space.has("crew")
		"station": return c.space.station_ready()
		"moon": return c.space.has("moon")
		"mars": return c.space.has("mars")
		"trade":
			for nb in c.region.neighbors:
				if nb.mood <= 65.0:
					return false
			return c.region.neighbors.size() > 0
		"styles":
			var st := {}
			for b in c.buildings.values():
				if b.type == "zone":
					st[b.style] = true
			return st.size() >= 3
	return false
