class_name News
## Advisors' advice and newspaper generation.

const ADVISORS := [
	{"id": "fin", "name": "Пётр Деньгин", "role": "Финансы", "color": Color("f9a825"), "icon": "budget"},
	{"id": "plan", "name": "Анна Планова", "role": "Градостроительство", "color": Color("43a047"), "icon": "zone_r"},
	{"id": "util", "name": "Иван Трубин", "role": "Коммунальные службы", "color": Color("1e88e5"), "icon": "power"},
	{"id": "safe", "name": "Ольга Спасова", "role": "Безопасность и здоровье", "color": Color("e53935"), "icon": "police"},
	{"id": "trans", "name": "Михаил Рулёв", "role": "Транспорт и образование", "color": Color("8e24aa"), "icon": "bus"},
]


static func _share(city: City, key: String, thr: float) -> float:
	var tot := 0
	var ok := 0
	for b: Building in city.buildings.values():
		if b.is_service() or b.kind() != "r" or b.collapsed:
			continue
		tot += 1
		if city.avg_cover(b, key) > thr:
			ok += 1
	return float(ok) / max(1, tot)


static func _count_problem(city: City, p: String) -> int:
	var c := 0
	for b: Building in city.buildings.values():
		if p in b.problems:
			c += 1
	return c


static func _has(city: City, type: String) -> bool:
	for b: Building in city.buildings.values():
		if b.type == type:
			return true
	return false


## Returns Array of {"text", "level"} (level: 0 ok, 1 warning, 2 urgent) for an advisor.
static func advice(city: City, id: String) -> Array:
	var out: Array = []
	var bal: float = city.projected.get("income", 0.0) - city.projected.get("expense", 0.0)
	match id:
		"fin":
			if city.money < 0:
				out.append({"text": "Казна пуста! Строительство остановлено. Поднимите налоги или закройте убыточные службы.", "level": 2})
			if bal < 0:
				out.append({"text": "Расходы превышают доходы на ₽%s в месяц." % Defs.fmt_int(-bal), "level": 1 if city.money > 20000 else 2})
			if city.taxes.r > 12 or city.taxes.c > 12 or city.taxes.i > 12:
				out.append({"text": "Налоги выше 12% отпугивают жителей и бизнес.", "level": 1})
			if city.money > 150000 and bal > 0:
				out.append({"text": "Казна полна — самое время для крупных проектов: метро, университет, достопримечательности.", "level": 0})
			if out.is_empty():
				out.append({"text": "Бюджет в порядке: +₽%s в месяц." % Defs.fmt_int(bal), "level": 0})
		"plan":
			if city.demand.r > 60:
				out.append({"text": "Высокий спрос на жильё — разметьте новые жилые зоны.", "level": 1})
			if city.demand.c > 60:
				out.append({"text": "Жителям не хватает магазинов — нужны коммерческие зоны.", "level": 1})
			if city.demand.i > 60:
				out.append({"text": "Людям нужна работа — разметьте промышленные или офисные зоны.", "level": 1})
			if city.unemployment > 0.12:
				out.append({"text": "Безработица %d%%! Нужны рабочие места." % int(city.unemployment * 100), "level": 2})
			var ab := _count_problem(city, "abandoned")
			if ab > 3:
				out.append({"text": "Заброшено зданий: %d. Проверьте услуги и коммунальные сети." % ab, "level": 2})
			if city.goods.sell < 0.85:
				out.append({"text": "Заводам некуда сбывать продукцию (%d%%). Нужны магазины или грузовой терминал для экспорта." % int(city.goods.sell * 100), "level": 1})
			if city.goods.import > 0.4 and city.population > 300:
				out.append({"text": "Магазины завозят %d%% товаров издалека и теряют прибыль. Разметьте промзону." % int(city.goods.import * 100), "level": 1})
			if city.edu_level > 0.55 and city.demand.i > 40:
				out.append({"text": "Жители образованы — офисы растут охотнее заводов.", "level": 0})
			var spec_any := false
			for d in city.districts.values():
				if d.get("spec", "") != "":
					spec_any = true
			if not spec_any and city.population > 800:
				out.append({"text": "Создайте промышленный район на ресурсах (слой «Природные ресурсы») и задайте ему специализацию — это выгоднее.", "level": 0})
			if city.districts.is_empty() and city.population > 1500:
				out.append({"text": "Создайте районы и вводите в них законы — это гибкий инструмент управления.", "level": 0})
			if out.is_empty():
				out.append({"text": "Город развивается сбалансированно.", "level": 0})
		"util":
			if city.power_demand > city.power_supply:
				out.append({"text": "Электричества не хватает: %d из %d МВт. Постройте электростанцию." % [int(city.power_supply), int(city.power_demand)], "level": 2})
			elif city.power_demand > city.power_supply * 0.85:
				out.append({"text": "Электросеть загружена на %d%% — скоро понадобится новая станция." % int(city.power_demand / max(1.0, city.power_supply) * 100), "level": 1})
			if city.water_demand > city.water_supply:
				out.append({"text": "Воды не хватает: %d из %d тыс. м³." % [int(city.water_supply), int(city.water_demand)], "level": 2})
			elif city.water_demand > city.water_supply * 0.85:
				out.append({"text": "Водопровод почти на пределе.", "level": 1})
			if city.sewage_demand > city.sewage_supply and city.population > 30:
				out.append({"text": "Канализация перегружена: %d из %d тыс. м³. Постройте сток у воды — ниже по течению от насосов." % [int(city.sewage_supply), int(city.sewage_demand)], "level": 2})
			elif city.sewage_supply > 0 and city.sewage_demand > city.sewage_supply * 0.85:
				out.append({"text": "Канализация почти на пределе.", "level": 1})
			var dw := _count_problem(city, "dirtywater")
			if dw > 0:
				out.append({"text": "У %d зданий грязная вода! Перенесите насосную станцию выше по течению от стока или постройте очистные." % dw, "level": 2})
			for b: Building in city.buildings.values():
				if b.store_cap() > 0.0 and b.stored / b.store_cap() > 0.85 and not b.emptying:
					out.append({"text": "%s заполнен на %d%%. Постройте новый или опустошите его." % [Defs.SERVICES[b.type].name, int(b.stored / b.store_cap() * 100)], "level": 1 if not b.is_full() else 2})
					break
			var g := _count_problem(city, "garbage")
			if g > 0:
				out.append({"text": "Мусор не вывозится у %d зданий — нужен полигон отходов." % g, "level": 2 if g > 10 else 1})
			var s := _count_problem(city, "sick")
			if s > 0:
				out.append({"text": "Загрязнение вредит здоровью жителей. Отделите промзоны от жилья деревьями или парками.", "level": 1})
			if out.is_empty():
				out.append({"text": "Электричество, вода и мусор — всё под контролем.", "level": 0})
		"safe":
			if city.population > 150:
				var f := _share(city, "fire", 0.05)
				if f < 0.7:
					out.append({"text": "Пожарная охрана покрывает только %d%% жилья." % int(f * 100), "level": 2 if f < 0.4 else 1})
				var p := _share(city, "police", 0.05)
				if p < 0.7:
					out.append({"text": "Полиция покрывает %d%% жилья — растёт преступность." % int(p * 100), "level": 1})
				var h := _share(city, "health", 0.05)
				if h < 0.6:
					out.append({"text": "Медицина доступна лишь %d%% жителей." % int(h * 100), "level": 1})
			var dd := _count_problem(city, "dead")
			if dd > 0:
				out.append({"text": "В %d домах лежат умершие — нужны кладбища или крематорий рядом." % dd, "level": 2 if dd > 5 else 1})
			elif city.milestone >= 1 and not (_has(city, "cemetery") or _has(city, "crematorium")):
				out.append({"text": "Горожане стареют. Постройте кладбище заранее.", "level": 1})
			if city.population > 2000 and not _has(city, "rescue"):
				out.append({"text": "Город вырос — постройте службу спасения на случай катастроф.", "level": 1})
			if out.is_empty():
				out.append({"text": "Горожане чувствуют себя в безопасности.", "level": 0})
		"trans":
			var tot := 0.0
			var cnt := 0
			for i in city.n * city.n:
				if city.road[i] > 0:
					tot += city.traffic[i]
					cnt += 1
			var jams := city.congested_tiles(1.0)
			if jams > 0:
				out.append({"text": "Пробки на %d участках дорог. Замените улицы проспектами (слой «Трафик» покажет где) и запустите автобусы." % jams, "level": 2 if jams > 15 else 1})
			if city.lines.is_empty() and city.population > 800:
				out.append({"text": "Запустите автобусный маршрут — это разгрузит дороги и повысит стоимость земли.", "level": 1})
			if city.population > 400:
				var e := _share(city, "edu", 0.05)
				if e < 0.6:
					out.append({"text": "Образование доступно %d%% семей. Без школ здания не растут." % int(e * 100), "level": 1})
			if city.population > 300 and not (_has(city, "park") or _has(city, "bigpark") or _has(city, "plaza")):
				out.append({"text": "В городе нет парков. Они повышают стоимость земли и настроение.", "level": 1})
			if out.is_empty():
				out.append({"text": "Транспорт и образование работают отлично.", "level": 0})
	return out


## Builds the monthly newspaper.
static func newspaper(city: City, events: Array, prev: Dictionary) -> Dictionary:
	var arts: Array = []
	var dp: int = city.population - int(prev.get("pop", 0))
	# events first (most recent, most important)
	var prio := {"disaster": 5, "milestone": 4, "landmark": 4, "line": 3, "service": 2, "district": 2, "policy": 1}
	var evs := events.duplicate()
	evs.sort_custom(func(a, b): return prio.get(a.kind, 0) > prio.get(b.kind, 0))
	for e in evs:
		arts.append({"title": e.title, "body": e.body})
		if arts.size() >= 3:
			break
	if dp > 50:
		arts.append({"title": "Город растёт: +%s жителей за месяц" % Defs.fmt_int(dp), "body": "Новосёлы продолжают прибывать. Население достигло %s человек." % Defs.fmt_int(city.population)})
	elif dp < -30:
		arts.append({"title": "Жители покидают город", "body": "За месяц население сократилось на %s человек. Эксперты винят нехватку услуг." % Defs.fmt_int(-dp)})
	var bal: float = city.projected.get("income", 0.0) - city.projected.get("expense", 0.0)
	if bal < 0:
		arts.append({"title": "Бюджет в минусе", "body": "Мэрия тратит на ₽%s больше, чем зарабатывает. Горожане обеспокоены." % Defs.fmt_int(-bal)})
	else:
		arts.append({"title": "Казна пополняется", "body": "Профицит бюджета составил ₽%s в месяц." % Defs.fmt_int(bal)})
	if city.avg_happiness > 70:
		arts.append({"title": "Опрос: горожане довольны", "body": "%d%% жителей оценивают жизнь в городе как хорошую." % int(city.avg_happiness)})
	elif city.avg_happiness < 45:
		arts.append({"title": "Недовольство растёт", "body": "Уровень счастья упал до %d%%. Жители требуют перемен." % int(city.avg_happiness)})
	if arts.is_empty():
		arts.append({"title": "Спокойный месяц в городе", "body": "Никаких происшествий. Горожане наслаждаются тишиной."})
	var wmap := {"clear": "ясно", "rain": "дождь", "snow": "снегопад"}
	var _w: String = ["☀ Солнечно, +24°", "⛅ Переменная облачность, +18°", "🌧 Дождь, +12°", "❄ Снег, −5°", "🌤 Ясно, +7°"][((city.day / Defs.DAYS_PER_MONTH) % 12) / 3 % 5]
	return {"date": Defs.date_string(city.day), "issue": city.day / Defs.DAYS_PER_MONTH, "articles": arts.slice(0, 4), "weather": "%s, %s" % [city.season_name(), wmap.get(city.weather, "")],
		"stats": "Население %s · Счастье %d%% · Казна ₽%s" % [Defs.fmt_int(city.population), int(city.avg_happiness), Defs.fmt_int(city.money)]}
