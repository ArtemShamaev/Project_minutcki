class_name Quests
## Goals guiding the player, with rewards.

const LIST := [
	{"id": "pop50", "name": "Первые жители", "desc": "Население 50 человек", "reward": 5000},
	{"id": "power", "name": "Да будет свет", "desc": "Обеспечьте электричеством все дома", "reward": 4000},
	{"id": "water", "name": "Чистая вода", "desc": "Обеспечьте водой все дома", "reward": 4000},
	{"id": "sewage", "name": "Канализация", "desc": "Подключите все дома к канализации", "reward": 4000},
	{"id": "shops", "name": "Торговая улица", "desc": "10 коммерческих зданий", "reward": 5000},
	{"id": "factories", "name": "Рабочие места", "desc": "8 промышленных или офисных зданий", "reward": 5000},
	{"id": "safety", "name": "Под защитой", "desc": "Постройте пожарную часть и полицию", "reward": 6000},
	{"id": "cemetery", "name": "Вечный покой", "desc": "Постройте кладбище или крематорий", "reward": 4000},
	{"id": "school", "name": "Знание — сила", "desc": "Постройте школу", "reward": 6000},
	{"id": "park", "name": "Зелёный город", "desc": "Постройте 3 парка или площадки", "reward": 5000},
	{"id": "pop1000", "name": "Тысяча жителей", "desc": "Население 1 000 человек", "reward": 15000},
	{"id": "bus", "name": "Общественный транспорт", "desc": "Запустите автобусный маршрут", "reward": 8000},
	{"id": "district", "name": "Свой район", "desc": "Создайте район и введите в нём закон", "reward": 6000},
	{"id": "spec", "name": "Ресурсный район", "desc": "Задайте району промышленную специализацию", "reward": 10000},
	{"id": "rail", "name": "Стук колёс", "desc": "Постройте вокзал и выведите пути за край карты", "reward": 15000},
	{"id": "happy", "name": "Счастливый город", "desc": "Счастье 75% при населении от 1 500", "reward": 12000},
	{"id": "level3", "name": "Вверх!", "desc": "5 зданий 3-го уровня", "reward": 15000},
	{"id": "landmark", "name": "Гордость города", "desc": "Постройте уникальное здание", "reward": 15000},
	{"id": "cargo", "name": "На экспорт", "desc": "Постройте грузовой терминал", "reward": 15000},
	{"id": "nojam", "name": "Без пробок", "desc": "Население от 3 000 и меньше 3 пробок", "reward": 20000},
	{"id": "green", "name": "Чистая энергия", "desc": "80% электричества без угля", "reward": 20000},
	{"id": "metro", "name": "Подземка", "desc": "Откройте линию метро", "reward": 25000},
	{"id": "pop6000", "name": "Крупный город", "desc": "Население 6 000 человек", "reward": 40000},
	{"id": "pop12000", "name": "Мегаполис", "desc": "Население 12 000 человек", "reward": 100000},
]


static func _count(city: City, f: Callable) -> int:
	var c := 0
	for b: Building in city.buildings.values():
		if f.call(b):
			c += 1
	return c


static func _has(city: City, types: Array) -> bool:
	for b: Building in city.buildings.values():
		if b.type in types:
			return true
	return false


static func progress(city: City, id: String) -> float:
	## 0..1
	match id:
		"pop50": return city.population / 50.0
		"pop1000": return city.population / 1000.0
		"pop6000": return city.population / 6000.0
		"pop12000": return city.population / 12000.0
		"power", "water":
			var tot := _count(city, func(b): return b.type == "zone" and b.build_days == 0 and not b.abandoned)
			if tot < 5:
				return 0.0
			var ok := _count(city, func(b): return b.type == "zone" and b.build_days == 0 and not b.abandoned and (b.powered if id == "power" else b.watered))
			return float(ok) / tot if ok < tot else 1.0
		"sewage":
			var tot := _count(city, func(b): return b.type == "zone" and b.build_days == 0 and not b.abandoned)
			if tot < 5:
				return 0.0
			var ok := _count(city, func(b): return b.type == "zone" and b.build_days == 0 and not b.abandoned and b.sewered)
			return float(ok) / tot if ok < tot else 1.0
		"cemetery": return 1.0 if _has(city, ["cemetery", "crematorium"]) else 0.0
		"spec":
			for d in city.districts.values():
				if d.get("spec", "") != "":
					return 1.0
			return 0.0
		"cargo": return 1.0 if _has(city, ["cargo"]) else 0.0
		"shops": return _count(city, func(b): return b.kind() == "c" and not b.abandoned) / 10.0
		"factories": return _count(city, func(b): return b.kind() == "i" and not b.abandoned) / 8.0
		"safety": return (0.5 if _has(city, ["fire"]) else 0.0) + (0.5 if _has(city, ["police"]) else 0.0)
		"school": return 1.0 if _has(city, ["school", "university", "college"]) else 0.0
		"park": return _count(city, func(b): return b.type in ["park", "bigpark", "plaza", "playground", "sports"]) / 3.0
		"bus":
			for l in city.lines:
				if l.kind == "bus":
					return 1.0
			return 0.0
		"metro":
			for l in city.lines:
				if l.kind == "metro":
					return 1.0
			return 0.0
		"district":
			for d in city.districts.values():
				if not d.policies.is_empty():
					return 1.0
			return 0.5 if not city.districts.is_empty() else 0.0
		"happy":
			if city.population < 1500:
				return min(0.9, city.population / 1500.0)
			return city.avg_happiness / 75.0
		"level3": return _count(city, func(b): return b.type == "zone" and b.level == 3) / 5.0
		"landmark":
			for b: Building in city.buildings.values():
				if b.is_service() and Defs.SERVICES[b.type].get("unique", false):
					return 1.0
			return 0.0
		"rail":
			for b in city.rail_stations("train_station"):
				var lk := city.station_link(b)
				if lk.out:
					return 1.0
				return 0.6
			return 0.3 if city.rail.count(1) > 0 else 0.0
		"nojam":
			if city.population < 3000:
				return min(0.9, city.population / 3000.0)
			return 1.0 if city.congested_tiles(1.0) < 3 else 0.5
		"green":
			var coal := 0.0
			var tot := 0.0
			for b: Building in city.buildings.values():
				if b.is_service() and Defs.SERVICES[b.type].has("power"):
					tot += Defs.SERVICES[b.type].power
					if b.type == "coal":
						coal += Defs.SERVICES[b.type].power
			if tot < 100.0:
				return 0.0
			return min(1.0, (1.0 - coal / tot) / 0.8)
	return 0.0
