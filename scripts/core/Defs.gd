class_name Defs
## Static game definitions: map constants, zones, services, milestones.

const N := 120                     # map size in tiles
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]  # N E S W
const ZONE_DEPTH := 3              # how far from a road zoning is allowed
const ROAD_COST := 12
const ROAD_TYPES := {
	1: {"name": "Улица", "cost": 12, "upkeep": 3.0, "speed": 1.0, "cap": 16.0, "unlock": 0, "icon": "road",
		"desc": "Двухполосная улица. Вдоль неё можно зонировать."},
	2: {"name": "Проспект", "cost": 30, "upkeep": 6.0, "speed": 1.5, "cap": 30.0, "unlock": 120, "icon": "avenue",
		"desc": "Широкий проспект с деревьями: быстрее и вместительнее, но шумнее."},
	3: {"name": "Шоссе", "cost": 45, "upkeep": 9.0, "speed": 2.4, "cap": 45.0, "unlock": 400, "icon": "highway",
		"desc": "Скоростное шоссе с отбойниками. Вдоль него нельзя строить."},
}
const LINE_COLORS := [Color("e53935"), Color("1e88e5"), Color("43a047"), Color("fb8c00"), Color("8e24aa"), Color("00acc1"), Color("fdd835"), Color("6d4c41")]
const TRANSIT := {
	"bus": {"name": "Автобус", "radius": 4.5, "rate": 0.55, "per_vehicle": 140, "price": 2.0, "line_upkeep": 250.0, "vehicle_upkeep": 70.0},
	"tram": {"name": "Трамвай", "radius": 5.5, "rate": 0.8, "per_vehicle": 320, "price": 2.5, "line_upkeep": 500.0, "vehicle_upkeep": 120.0},
	"metro": {"name": "Метро", "radius": 8.0, "rate": 1.0, "per_vehicle": 1400, "price": 3.0, "line_upkeep": 900.0, "vehicle_upkeep": 0.0},
}
const BRIDGE_COST := 60
const ROAD_UPKEEP := 0.25          # per tile per month... multiplied below
const TREE_COST := 15
const START_MONEY := 70000.0
const DAYS_PER_MONTH := 30
const DAY_CYCLE := 48.0            # game days per day/night cycle

enum { NONE, R_LOW, R_HIGH, C_LOW, C_HIGH, IND, OFFICE, AGRI }

const ZONES := {
	R_LOW:  {"name": "Жилая зона (низкая плотность)", "short": "Жилая", "kind": "r", "color": Color("5fd35f"), "cap": 4,  "ministry": "transport", "unlock": 0,    "icon": "zone_r",  "power": 1, "water": 1},
	R_HIGH: {"name": "Жилая зона (высокая плотность)", "short": "Жилая+", "kind": "r", "color": Color("1f9a3a"), "cap": 14, "unlock": 400,  "icon": "zone_r2", "power": 2, "water": 2},
	C_LOW:  {"name": "Коммерческая (низкая плотность)", "short": "Торговля", "kind": "c", "color": Color("4fa3ff"), "cap": 5,  "unlock": 0,    "icon": "zone_c",  "power": 2, "water": 1},
	C_HIGH: {"name": "Коммерческая (высокая плотность)", "short": "Торговля+", "kind": "c", "color": Color("2058d0"), "cap": 13, "unlock": 400,  "icon": "zone_c2", "power": 3, "water": 2},
	IND:    {"name": "Промышленная зона", "short": "Промзона", "kind": "i", "color": Color("f2c230"), "cap": 8,  "unlock": 0,    "icon": "zone_i",  "power": 3, "water": 2},
	AGRI:   {"name": "Сельхозугодья", "short": "Ферма", "kind": "i", "color": Color("9ccc65"), "cap": 2, "unlock": 120, "icon": "zone_a", "power": 1, "water": 1},
	OFFICE: {"name": "Офисная зона", "short": "Офисы", "kind": "i", "color": Color("a86cff"), "cap": 12, "unlock": 1000, "icon": "zone_o",  "power": 2, "water": 1},
}

# Lot shapes allowed for each zone: [width, depth]
const LOTS := {
	R_LOW:  [[1, 2], [1, 1]],
	R_HIGH: [[2, 2], [1, 2], [1, 1]],
	C_LOW:  [[1, 2], [1, 1]],
	C_HIGH: [[2, 2], [1, 2], [1, 1]],
	IND:    [[2, 3], [2, 2], [1, 2], [1, 1]],
	OFFICE: [[2, 2], [1, 2], [1, 1]],
	AGRI:   [[2, 3], [3, 3], [2, 2], [1, 2]],
}

# Service buildings. cover = coverage map name, radius in tiles.
const SERVICES := {
	"wind":     {"name": "Ветрогенератор", "cat": "power", "cost": 3000, "upkeep": 150, "w": 1, "d": 1, "power": 40, "unlock": 0,
				 "desc": "Чистая энергия, 40 МВт."},
	"coal":     {"name": "Угольная электростанция", "cat": "power", "cost": 16000, "upkeep": 1200, "w": 2, "d": 2, "power": 400, "unlock": 0,
				 "pollution": 1.0, "prad": 10, "desc": "400 МВт, но сильно загрязняет."},
	"nuclear":  {"name": "Атомная электростанция", "cat": "power", "cost": 120000, "upkeep": 4500, "w": 3, "d": 3, "power": 1600, "unlock": 6000,
				 "desc": "1600 МВт чистой энергии. Дорого, но надолго."},
	"solar":    {"name": "Солнечная электростанция", "cat": "power", "cost": 22000, "upkeep": 700, "w": 2, "d": 2, "power": 220, "unlock": 1000,
				 "desc": "220 МВт без загрязнения."},
	"hydro":    {"name": "Русловая ГЭС", "cat": "power", "cost": 26000, "upkeep": 900, "w": 2, "d": 2, "power": 380, "unlock": 1000,
				 "need_water": true, "desc": "До 570 МВт чистой энергии. Мощность зависит от скорости течения: ставьте на быстрой реке, а не у озера."},
	"tower":    {"name": "Водонапорная башня", "cat": "water", "cost": 2500, "upkeep": 140, "w": 1, "d": 1, "water": 60, "unlock": 0,
				 "desc": "Небольшой запас воды: 60 тыс. м³."},
	"pump":     {"name": "Насосная станция", "cat": "water", "cost": 5000, "upkeep": 320, "w": 1, "d": 2, "water": 320, "unlock": 0,
				 "need_water": true, "desc": "320 тыс. м³. Ставится у берега."},
	"watertreat": {"name": "Станция водоочистки", "cat": "water", "cost": 24000, "upkeep": 1300, "w": 2, "d": 2, "water": 900, "ministry": "utility", "unlock": 1000,
				 "need_water": true, "desc": "900 тыс. м³ чистой воды. Ставится у берега."},
	"outlet":   {"name": "Канализационный сток", "cat": "water", "cost": 2500, "upkeep": 120, "w": 1, "d": 1, "sewage": 300, "unlock": 0,
				 "need_water": true, "wpol": 1.0, "desc": "Сбрасывает сточные воды (300 тыс. м³) в водоём. Загрязняет воду ниже по течению — не ставьте рядом с насосами!"},
	"sewtreat": {"name": "Очистные сооружения", "cat": "water", "cost": 20000, "upkeep": 1000, "w": 2, "d": 2, "sewage": 900, "ministry": "utility", "unlock": 1000,
				 "need_water": true, "wpol": 0.12, "desc": "Очищают 900 тыс. м³ стоков. Почти не загрязняют воду."},
	"fire":     {"name": "Пожарная часть", "cat": "safety", "cost": 7000, "upkeep": 600, "w": 2, "d": 2, "cover": "fire", "radius": 16, "unlock": 120,
				 "desc": "Тушит пожары, отправляет машины."},
	"police":   {"name": "Полицейский участок", "cat": "safety", "cost": 7000, "upkeep": 600, "w": 2, "d": 2, "cover": "police", "radius": 16, "unlock": 120,
				 "desc": "Снижает преступность."},
	"clinic":   {"name": "Поликлиника", "cat": "health", "cost": 6000, "upkeep": 650, "w": 1, "d": 2, "cover": "health", "radius": 13, "unlock": 120,
				 "desc": "Медицинская помощь рядом."},
	"hospital": {"name": "Больница", "cat": "health", "cost": 18000, "upkeep": 1500, "w": 2, "d": 2, "cover": "health", "radius": 26, "unlock": 1000,
				 "desc": "Большой радиус покрытия."},
	"landfill": {"name": "Полигон отходов", "cat": "health", "cost": 5000, "upkeep": 450, "w": 2, "d": 2, "cover": "garbage", "radius": 30, "unlock": 120,
				 "pollution": 0.35, "prad": 3.5, "store": 40000, "desc": "Дешёвый вывоз мусора, но полигон постепенно заполняется. Немного загрязняет ближайшие клетки."},
	"recycling": {"name": "Центр переработки", "cat": "health", "cost": 14000, "upkeep": 700, "w": 2, "d": 2, "cover": "garbage", "radius": 26, "unlock": 400,
				 "process": true, "desc": "Вывоз мусора без загрязнения."},
	"incinerator": {"name": "Мусоросжигательный завод", "cat": "health", "cost": 20000, "upkeep": 900, "w": 2, "d": 2, "cover": "garbage", "radius": 40, "unlock": 1000,
				 "process": true, "power": 60, "pollution": 0.25, "prad": 3, "desc": "Огромный радиус вывоза мусора и 60 МВт электричества."},
	"cemetery": {"name": "Кладбище", "cat": "health", "cost": 4500, "upkeep": 300, "w": 2, "d": 2, "cover": "death", "radius": 22, "unlock": 120,
				 "store": 1500, "desc": "Катафалки забирают умерших. Место на кладбище постепенно заканчивается."},
	"crematorium": {"name": "Крематорий", "cat": "health", "cost": 14000, "upkeep": 800, "w": 2, "d": 2, "cover": "death", "radius": 30, "unlock": 1000,
				 "process": true, "desc": "Не заполняется. Может принять умерших с переполненных кладбищ."},
	"rescue":   {"name": "Служба спасения", "cat": "safety", "cost": 12000, "upkeep": 900, "w": 2, "d": 2, "cover": "rescue", "radius": 32, "ministry": "safety", "unlock": 1000,
				 "desc": "Быстро разбирает завалы после катастроф и спасает жителей."},
	"school":   {"name": "Школа", "cat": "edu", "cost": 9000, "upkeep": 800, "w": 2, "d": 2, "cover": "edu", "radius": 15, "unlock": 400,
				 "desc": "Образование позволяет зданиям расти."},
	"library":  {"name": "Библиотека", "cat": "edu", "cost": 4000, "upkeep": 250, "w": 1, "d": 1, "cover": "edu", "radius": 9, "unlock": 120,
				 "desc": "Небольшой радиус образования."},
	"college":  {"name": "Колледж", "cat": "edu", "cost": 18000, "upkeep": 1300, "w": 3, "d": 2, "cover": "edu", "radius": 24, "ministry": "edu", "unlock": 1000,
				 "desc": "Среднее профессиональное образование."},
	"university": {"name": "Университет", "cat": "edu", "cost": 30000, "upkeep": 2200, "w": 3, "d": 3, "cover": "edu", "radius": 34, "ministry": "edu", "unlock": 2500,
				 "desc": "Высшее образование для всего района."},
	"busdepot": {"name": "Автобусный парк", "cat": "transport", "cost": 6000, "upkeep": 400, "w": 2, "d": 2, "unlock": 400,
				 "desc": "Нужен для автобусных маршрутов."},
	"tramdepot": {"name": "Трамвайное депо", "cat": "transport", "cost": 12000, "upkeep": 600, "w": 2, "d": 2, "ministry": "transport", "unlock": 1000,
				 "desc": "Нужно для трамвайных маршрутов."},
	"cargo":    {"name": "Грузовой терминал", "cat": "transport", "cost": 18000, "upkeep": 800, "w": 3, "d": 2, "unlock": 1000, "export_cap": 600, "dem_i": 8.0,
				 "desc": "Отправляет товары за пределы города: промышленности есть куда сбывать продукцию."},
	"train_station": {"name": "Вокзал", "cat": "transport", "cost": 30000, "upkeep": 1200, "w": 3, "d": 2, "unlock": 1000, "need_rail": true,
				 "desc": "Пассажирская станция. Ставится вплотную к ж/д путям. Электрички возят жителей между вокзалами, а если пути выходят за край карты — приезжают туристы и дальние поезда."},
	"cargo_station": {"name": "Грузовая ж/д станция", "cat": "transport", "cost": 25000, "upkeep": 900, "w": 3, "d": 2, "unlock": 1000, "need_rail": true,
				 "export_cap": 1500, "dem_i": 10.0, "desc": "Козловой кран грузит контейнеры в поезда. Если пути выходят за край карты — заводы отправляют товары по железной дороге (+1 500 к экспорту, спрос на промышленность)."},
	"metro":    {"name": "Станция метро", "cat": "transport", "cost": 9000, "upkeep": 450, "w": 1, "d": 1, "unlock": 1000,
				 "desc": "Соединяйте станции линиями метро."},
	"cityhall": {"name": "Ратуша", "cat": "landmark", "cost": 8000, "upkeep": 300, "w": 3, "d": 3, "cover": "park", "radius": 12, "unlock": 0,
				 "unique": true, "tax_bonus": 0.05, "desc": "Сердце города: +5% ко всем налогам. Растёт до Мэрии и Капитолия, к ней пристраиваются министерства."},
	"dsa_hq":   {"name": "Штаб УГК", "cat": "ugk", "cost": 50000, "upkeep": 2000, "w": 3, "d": 3, "cover": "edu", "radius": 14, "unlock": 2500,
				 "unique": true, "ministry": "science", "tourism": 800,
				 "desc": "Управление городской космонавтики (как DSA в TheoTown): исследования, испытания ракет, спутники, Луна и Марс. Окно УГК — клавиша [K]."},
	"launchpad": {"name": "Стартовый стол", "cat": "ugk", "cost": 40000, "upkeep": 1500, "w": 3, "d": 3, "unlock": 2500, "needs": "dsa_hq", "max": 3,
				 "desc": "Башня обслуживания и ракета Saturn V. Сюда грузовики везут снабжение с заводов; отсюда стартуют миссии. +4 000 к складу снабжения."},
	"mission_control": {"name": "Центр управления полётами", "cat": "ugk", "cost": 25000, "upkeep": 900, "w": 2, "d": 2, "unlock": 2500, "needs": "dsa_hq", "max": 2,
				 "desc": "Антенна дальней связи: +5% к надёжности миссий и +5 очков исследований в месяц."},
	"rocket_factory": {"name": "Ракетный завод", "cat": "ugk", "cost": 35000, "upkeep": 1200, "w": 3, "d": 3, "unlock": 2500, "needs": "dsa_hq", "max": 3,
				 "desc": "Собирает ступени и топливо для ракет: +60 ед. снабжения в день (больше, если рядом промышленность)."},
	"astro_center": {"name": "Центр подготовки космонавтов", "cat": "ugk", "cost": 30000, "upkeep": 1000, "w": 2, "d": 2, "cover": "edu", "radius": 10, "unlock": 2500,
				 "needs": "dsa_hq", "max": 2, "desc": "Купол с центрифугой и бассейном невесомости. Готовит одного космонавта за 20 дней (до 4 на центр). Без космонавтов пилотируемые полёты невозможны."},
	"observatory": {"name": "Обсерватория", "cat": "ugk", "cost": 18000, "upkeep": 400, "w": 2, "d": 2, "cover": "edu", "radius": 14, "unlock": 1000, "tourism": 300, "max": 3,
				 "desc": "Телескоп под куполом: +4 очка исследований УГК в месяц, школьники смотрят на звёзды."},
	"rectenna": {"name": "Приёмная ректенна", "cat": "ugk", "cost": 30000, "upkeep": 400, "w": 3, "d": 3, "unlock": 6000, "needs": "dsa_hq", "power": 2500, "max": 2, "space_need": "solarsat",
				 "desc": "Принимает энергию с орбитальной солнечной электростанции: 2 500 МВт без дыма. Работает после миссии «Орбитальная электростанция»."},
	"space_museum": {"name": "Музей космонавтики", "cat": "ugk", "cost": 40000, "upkeep": 700, "w": 2, "d": 2, "cover": "edu", "radius": 20, "unlock": 2500, "unique": true,
				 "tourism": 2500, "space_need": "moon", "desc": "Настоящая ракета у входа и лунный грунт в витрине. Открывается после высадки на Луну. Туристы и образование."},
	"he3_plant": {"name": "Гелиевая электростанция", "cat": "ugk", "cost": 120000, "upkeep": 3000, "w": 3, "d": 3, "unlock": 6000, "power": 6000, "max": 2, "space_need": "he3",
				 "desc": "Термоядерный реактор на лунном гелии-3: 6 000 МВт без отходов. Сжигает 2 т гелия-3 в день, привезённого с Луны. Открывается после экспорта 100 т."},
	"casino":   {"name": "Казино", "cat": "landmark", "cost": 35000, "upkeep": 600, "w": 3, "d": 3, "cover": "park", "radius": 10, "unlock": 2500,
				 "unique": true, "tourism": 2600, "ministry": "tourism", "crime": 0.35,
				 "desc": "Огни, рулетка и туристы (как в SimCity). Много денег, но вокруг растёт преступность."},
	"bigben":   {"name": "Часовая башня", "cat": "landmark", "cost": 30000, "upkeep": 500, "w": 2, "d": 2, "cover": "park", "radius": 16, "unlock": 2500,
				 "unique": true, "tourism": 1300, "ministry": "tourism", "desc": "Знаменитая лондонская часовая башня — копия в вашем городе."},
	"liberty":  {"name": "Статуя Свободы", "cat": "landmark", "cost": 32000, "upkeep": 400, "w": 2, "d": 2, "cover": "park", "radius": 16, "unlock": 2500,
				 "unique": true, "tourism": 1500, "ministry": "tourism", "desc": "Символ свободы с факелом. Туристы делают селфи."},
	"coliseum": {"name": "Колизей", "cat": "landmark", "cost": 38000, "upkeep": 700, "w": 3, "d": 3, "cover": "park", "radius": 18, "unlock": 6000,
				 "unique": true, "tourism": 2400, "ministry": "tourism", "desc": "Античный амфитеатр. Летом здесь проходят концерты."},
	"lighthouse": {"name": "Маяк", "cat": "landmark", "cost": 9000, "upkeep": 150, "w": 1, "d": 1, "cover": "park", "radius": 8, "unlock": 1000,
				 "need_water": true, "tourism": 400, "desc": "Полосатый маяк на берегу. Ночью светит кораблям."},
	"mansion":  {"name": "Резиденция мэра", "cat": "landmark", "cost": 0, "upkeep": 200, "w": 2, "d": 2, "cover": "park", "radius": 12, "unlock": 0,
				 "unique": true, "award": true, "desc": "Награда от благодарных горожан (как в SimCity): даётся, когда город счастлив. +3 к счастью во всём городе."},
	"tvtower":  {"name": "Телебашня", "cat": "landmark", "cost": 25000, "upkeep": 600, "w": 1, "d": 1, "cover": "park", "radius": 18, "ministry": "tourism", "unlock": 1000,
				 "unique": true, "tourism": 500, "desc": "Видна издалека. Повышает стоимость земли."},
	"cathedral": {"name": "Собор", "cat": "landmark", "cost": 30000, "upkeep": 400, "w": 2, "d": 2, "cover": "park", "radius": 16, "ministry": "tourism", "unlock": 1000,
				 "unique": true, "tourism": 900, "desc": "Белокаменный собор с золотыми куполами. Туристы и счастье."},
	"museum":   {"name": "Музей", "cat": "landmark", "cost": 28000, "upkeep": 700, "w": 2, "d": 2, "cover": "edu", "radius": 22, "ministry": "tourism", "unlock": 2500,
				 "unique": true, "tourism": 1100, "desc": "Образование и культура. Привлекает туристов."},
	"pagoda":   {"name": "Пагода", "cat": "landmark", "cost": 26000, "upkeep": 500, "w": 2, "d": 2, "cover": "park", "radius": 16, "ministry": "tourism", "unlock": 1000,
				 "unique": true, "tourism": 1000, "desc": "Пятиярусная пагода с красными галереями. Туристы и тихие сады вокруг."},
	"heaven":   {"name": "Храм Неба", "cat": "landmark", "cost": 32000, "upkeep": 600, "w": 2, "d": 2, "cover": "park", "radius": 18, "ministry": "tourism", "unlock": 2500,
				 "unique": true, "tourism": 1400, "desc": "Круглый храм под тремя зелёными крышами. Повышает счастье и стоимость земли."},
	# megaprojects: built in stages, each stage needs money and a month of work
	"spaceport": {"name": "Космодром", "cat": "ugk", "cost": 40000, "upkeep": 3000, "w": 4, "d": 4, "cover": "park", "radius": 24, "unlock": 6000,
				 "unique": true, "tourism": 6000, "stages": 4, "stage_cost": [60000, 90000, 120000, 150000], "edu_bonus": 0.12,
				 "desc": "Мегапроект в 4 этапа. Ракеты взлетают с площадки, туристы съезжаются со всего региона, школьники мечтают стать инженерами (+12% к образованию)."},
	"arcology": {"name": "Аркология", "cat": "landmark", "cost": 30000, "upkeep": 2500, "w": 3, "d": 3, "cover": "park", "radius": 20, "unlock": 6000,
				 "unique": true, "residents": 3000, "stages": 3, "stage_cost": [50000, 80000, 110000],
				 "desc": "Мегапроект в 3 этапа: город-башня с садами на террасах на 3 000 жителей."},
	"fusion":   {"name": "Термоядерная станция", "cat": "power", "cost": 50000, "upkeep": 6000, "w": 3, "d": 3, "power": 4000, "unlock": 12000,
				 "stages": 3, "stage_cost": [80000, 120000, 160000],
				 "desc": "Мегапроект в 3 этапа: 4 000 МВт чистой энергии — хватит и себе, и на продажу соседям."},
	"stadium":  {"name": "Стадион", "cat": "landmark", "cost": 45000, "upkeep": 1500, "w": 3, "d": 3, "cover": "park", "radius": 20, "ministry": "tourism", "unlock": 2500,
				 "unique": true, "tourism": 2200, "desc": "Матчи по выходным собирают весь город."},
	"zoo":      {"name": "Зоопарк", "cat": "landmark", "cost": 35000, "upkeep": 1000, "w": 3, "d": 3, "cover": "park", "radius": 18, "ministry": "tourism", "unlock": 2500,
				 "unique": true, "tourism": 1600, "desc": "Жирафы, слоны и пингвины. Туристы обожают!"},
	"port":     {"name": "Грузовой порт", "cat": "landmark", "cost": 40000, "upkeep": 1200, "w": 3, "d": 2, "unlock": 2500, "need_water": true,
				 "unique": true, "dem_i": 20.0, "export": 1800, "export_cap": 1200, "pollution": 0.4, "prad": 6, "desc": "Экспорт товаров: спрос на промышленность +20."},
	"airport":  {"name": "Аэропорт", "cat": "landmark", "cost": 90000, "upkeep": 2500, "w": 4, "d": 6, "unlock": 6000,
				 "unique": true, "dem_c": 20.0, "tourism": 4500, "pollution": 0.3, "prad": 8, "desc": "Самолёты, туристы, бизнес: спрос на торговлю +20."},
	"park":     {"name": "Сквер", "cat": "park", "cost": 1200, "upkeep": 60, "w": 1, "d": 1, "cover": "park", "radius": 6, "unlock": 0,
				 "desc": "Повышает стоимость земли."},
	"playground": {"name": "Детская площадка", "cat": "park", "cost": 800, "upkeep": 40, "w": 1, "d": 1, "cover": "park", "radius": 5, "unlock": 0,
				 "desc": "Радость для семей с детьми."},
	"sports":   {"name": "Спортплощадка", "cat": "park", "cost": 2500, "upkeep": 110, "w": 2, "d": 1, "cover": "park", "radius": 8, "unlock": 120,
				 "desc": "Футбол и баскетбол во дворе."},
	"bigpark":  {"name": "Городской парк", "cat": "park", "cost": 6000, "upkeep": 250, "w": 2, "d": 2, "cover": "park", "radius": 12, "unlock": 400,
				 "desc": "Большой парк с прудом."},
	"plaza":    {"name": "Площадь с фонтаном", "cat": "park", "cost": 9000, "upkeep": 350, "w": 2, "d": 2, "cover": "park", "radius": 14, "unlock": 2500,
				 "desc": "Привлекает туристов и бизнес."},
}

const POLICIES := {
	"free_transit": {"name": "Бесплатный проезд", "cost": 0.0, "icon": "bus",
		"desc": "На 35% больше пассажиров, но нет дохода от билетов."},
	"smoke_ban": {"name": "Запрет курения", "cost": 0.0, "icon": "health",
		"desc": "+5 к счастью жителей, торговля теряет 5% дохода."},
	"recycling": {"name": "Переработка мусора", "cost": 2.0, "icon": "garbage",
		"desc": "Мусора вдвое меньше, загрязнение −10%."},
	"green_energy": {"name": "Энергосбережение", "cost": 2.0, "icon": "power",
		"desc": "Потребление электричества и воды −20%."},
	"greening": {"name": "Озеленение", "cost": 3.0, "icon": "park",
		"desc": "Стоимость земли +6, загрязнение −20%."},
	"truck_ban": {"name": "Запрет грузовиков", "cost": 0.0, "icon": "highway",
		"desc": "Шум −30%, доход промышленности −10%."},
	"tourism": {"name": "Туристический район", "cost": 1.0, "icon": "zone_c",
		"desc": "Доход торговли +15%, шума больше."},
	"high_rise_ban": {"name": "Ограничение этажности", "cost": 0.0, "icon": "zone_r2",
		"desc": "Плотная застройка не выше 2 уровня, +3 к счастью."},
	"watch": {"name": "Народная дружина", "cost": 1.0, "icon": "police",
		"desc": "Преступность исчезает даже без полиции."},
	"ind_filters": {"name": "Промышленные фильтры", "cost": 1.0, "icon": "zone_i",
		"desc": "Загрязнение от промышленности −40%, доход промышленности −8%."},
	"sewage_filter": {"name": "Фильтрация стоков", "cost": 1.0, "icon": "sewage",
		"desc": "Сбросы канализационных стоков загрязняют воду вдвое меньше."},
	"edu_boost": {"name": "Школьные программы", "cost": 3.0, "icon": "edu",
		"desc": "Образование +15%: здания быстрее растут в уровне."},
}
const DISTRICT_NAMES := ["Заречье", "Сосновка", "Центральный", "Северный", "Южный", "Лесной", "Набережная", "Холмы",
	"Солнечный", "Старый город", "Черёмушки", "Озёрный", "Промзона", "Зелёный", "Луговой", "Вишнёвый", "Берёзовка",
	"Тихий уголок", "Новостройки", "Купеческий", "Светлый", "Ясная поляна"]
const DISTRICT_COLORS := [Color("ff7043"), Color("ab47bc"), Color("26c6da"), Color("d4e157"), Color("ec407a"), Color("5c6bc0"), Color("ffca28"), Color("66bb6a")]

# Architecture styles of zoned buildings (per city or per district)
const STYLES := {
	"modern": {"name": "Современный", "desc": "Стекло, бетон и пригородные коттеджи."},
	"soviet": {"name": "Советский", "desc": "Панельные хрущёвки и девятиэтажки, избы, «Продукты» и универмаг."},
	"euro": {"name": "Европейский", "desc": "Фахверковые дома под черепицей и доходные дома XIX века."},
	"american": {"name": "Американский", "desc": "Дома с гаражами, кирпич Нью-Йорка, ар-деко небоскрёбы."},
	"chinese": {"name": "Китайский", "desc": "Дворики под изогнутыми крышами, лавки с фонарями и башни-высотки."},
}

# City hall levels (SimCity: Town Hall -> City Hall -> Capitol) and ministries (department wings)
const HALL_LEVELS := [
	{"name": "Ратуша", "pop": 0, "cost": 0, "slots": 1},
	{"name": "Мэрия", "pop": 2500, "cost": 40000, "slots": 3},
	{"name": "Капитолий", "pop": 12000, "cost": 120000, "slots": 7},
]
const MINISTRIES := {
	"finance": {"name": "Министерство финансов", "cost": 20000, "upkeep": 600, "color": Color("2e7d32"),
		"desc": "+8% ко всем налогам, кредиты на 30% дешевле. Открывает субсидии."},
	"utility": {"name": "Министерство ЖКХ", "cost": 18000, "upkeep": 500, "color": Color("1565c0"),
		"desc": "Содержание электростанций, водоснабжения и стоков −15%. Очистные и водоочистка доступны раньше."},
	"safety": {"name": "Министерство безопасности", "cost": 18000, "upkeep": 500, "color": Color("c62828"),
		"desc": "Радиус пожарных, полиции и больниц +15%. Служба спасения доступна раньше."},
	"edu": {"name": "Министерство образования", "cost": 22000, "upkeep": 600, "color": Color("ffa000"),
		"desc": "Образованность +10%. Колледж и университет доступны раньше."},
	"transport": {"name": "Министерство транспорта", "cost": 20000, "upkeep": 500, "color": Color("00838f"),
		"desc": "Пассажиров +15%, содержание транспорта −20%. Метро и трамвай доступны раньше."},
	"tourism": {"name": "Министерство туризма", "cost": 20000, "upkeep": 500, "color": Color("8e24aa"),
		"desc": "Доход от туризма +30%. Открывает казино и знаменитые здания мира раньше."},
	"science": {"name": "Министерство науки и космоса", "cost": 30000, "upkeep": 800, "color": Color("37474f"),
		"desc": "Штаб УГК можно построить раньше, +5 очков исследований УГК в месяц, образованность +5%."},
}
# Subsidies (SimCity): money spent each month to boost a sector
const SUBSIDIES := {
	"housing": {"name": "Жилищные субсидии", "desc": "Спрос на жильё", "pct": 0.04, "base": "r"},
	"business": {"name": "Поддержка малого бизнеса", "desc": "Спрос на торговлю", "pct": 0.05, "base": "c"},
	"industry": {"name": "Промышленные субсидии", "desc": "Спрос на промышленность", "pct": 0.05, "base": "i"},
	"farming": {"name": "Аграрные субсидии", "desc": "Фермы приносят больше дохода", "pct": 0.03, "base": "i"},
	"tech": {"name": "Гранты высоким технологиям", "desc": "Офисы растут и приносят больше", "pct": 0.05, "base": "o"},
	"transit": {"name": "Дотации транспорту", "desc": "Больше пассажиров", "pct": 0.03, "base": "r"},
	"green": {"name": "Зелёная энергетика", "desc": "Ветряки и солнечные станции +15%", "pct": 0.02, "base": "r"},
}
const SUBSIDY_LEVELS := ["Нет", "Умеренные", "Щедрые"]

# Space program (УГК, like the DSA in TheoTown): research topics and missions.
# supplies: units of rocket supplies that trucks must bring to the launch pads first; crew: astronauts on board
const RESEARCH := {
	"rockets": {"name": "Ракеты-носители", "rp": 0, "desc": "Основа программы: испытательные пуски и спутники."},
	"probes": {"name": "Автоматические станции", "rp": 50, "need": "rockets", "desc": "Зонды к Луне и Марсу, космический телескоп."},
	"manned": {"name": "Пилотируемые полёты", "rp": 70, "need": "rockets", "desc": "Открывает полёты космонавтов."},
	"reusable": {"name": "Многоразовые ракеты", "rp": 90, "need": "rockets", "desc": "Запуски дешевле на 40%, снабжения нужно на 25% меньше."},
	"station": {"name": "Орбитальные станции", "rp": 120, "need": "manned", "desc": "Сборка орбитальной станции из модулей."},
	"space_power": {"name": "Космическая энергетика", "rp": 160, "need": "station", "desc": "Орбитальная солнечная электростанция и приёмная ректенна."},
	"shield": {"name": "Орбитальный щит", "rp": 150, "need": "station", "desc": "Противометеоритная защита на орбите."},
	"moon": {"name": "Лунная программа", "rp": 200, "need": "probes", "need2": "station", "desc": "Четыре миссии к Луне — и лунная колония."},
	"he3": {"name": "Добыча гелия-3", "rp": 180, "need": "moon", "desc": "Добывающие станции на Луне производят вдвое больше."},
	"life": {"name": "Замкнутое жизнеобеспечение", "rp": 220, "need": "moon", "desc": "Жилые модули колоний вмещают вдвое больше колонистов."},
	"mars": {"name": "Межпланетные перелёты", "rp": 320, "need": "moon", "desc": "Марсоход, экспедиция на Марс и марсианская колония."},
}
const MISSIONS := {
	"test": {"name": "Испытательный пуск", "cost": 6000, "days": 3, "need": "rockets", "chance": 0.6, "max": 3, "supplies": 150,
		"desc": "Проверка ракеты (как в TheoTown). Каждый удачный пуск: +5% к надёжности всех миссий. Нужен хотя бы один, чтобы выйти на орбиту."},
	"weather": {"name": "Метеоспутник", "cost": 20000, "days": 8, "need": "rockets", "after": "test", "chance": 0.9, "once": true, "supplies": 300,
		"desc": "Прогноз погоды и раннее предупреждение: катастрофы наносят на 30% меньше ущерба."},
	"comsat": {"name": "Спутник связи", "cost": 30000, "days": 8, "need": "rockets", "after": "test", "chance": 0.9, "max": 3, "supplies": 400,
		"desc": "Связь и интернет: доход офисов и торговли +4% за каждый (до 3)."},
	"gps": {"name": "Навигационная группировка", "cost": 45000, "days": 10, "need": "rockets", "after": "comsat", "chance": 0.88, "once": true, "supplies": 600,
		"desc": "Навигаторы прокладывают маршруты в обход пробок: заторы −10%."},
	"telescope": {"name": "Космический телескоп", "cost": 60000, "days": 10, "need": "probes", "after": "test", "chance": 0.85, "once": true, "supplies": 700,
		"desc": "Снимки далёких галактик: +10 очков исследований в месяц, туризм +500."},
	"crew": {"name": "Пилотируемый полёт", "cost": 60000, "days": 12, "need": "manned", "after": "test", "chance": 0.85, "crew": 1, "supplies": 800,
		"desc": "Город следит за полётом своего космонавта: туризм +1 000 и +3 к счастью на год."},
	"module": {"name": "Модуль орбитальной станции", "cost": 80000, "days": 14, "need": "station", "after": "crew", "chance": 0.85, "max": 3, "crew": 1, "supplies": 1200,
		"desc": "Три модуля — и станция готова: +15 очков исследований в месяц, образованность +5%."},
	"solarsat": {"name": "Орбитальная электростанция", "cost": 120000, "days": 14, "need": "space_power", "chance": 0.82, "once": true, "supplies": 1500,
		"desc": "Солнечные панели в километр шириной передают энергию на ректенны города."},
	"shield": {"name": "Орбитальный щит (SDI)", "cost": 150000, "days": 18, "need": "shield", "chance": 0.8, "once": true, "supplies": 2000,
		"desc": "Метеориты сбиваются на орбите и больше не падают на город."},
	"lunar_probe": {"name": "Луна-1: автоматическая станция", "cost": 50000, "days": 10, "need": "moon", "chance": 0.82, "once": true, "supplies": 1000,
		"desc": "Первая миссия лунной программы: зонд фотографирует место посадки и находит гелий-3."},
	"lunar_orbit": {"name": "Луна-2: облёт с экипажем", "cost": 120000, "days": 16, "need": "moon", "after": "lunar_probe", "chance": 0.8, "once": true, "crew": 2, "supplies": 3000,
		"desc": "Экипаж облетает Луну и возвращается. Туризм +1 500."},
	"moon": {"name": "Луна-3: высадка", "cost": 200000, "days": 20, "need": "moon", "after": "lunar_orbit", "chance": 0.75, "once": true, "crew": 2, "supplies": 6500,
		"desc": "Флаг города на Луне! Туризм +3 000, открывается Музей космонавтики."},
	"moonbase": {"name": "Луна-4: лунная база", "cost": 300000, "days": 24, "need": "moon", "after": "moon", "chance": 0.8, "once": true, "crew": 3, "supplies": 8000,
		"desc": "Первый жилой модуль на Луне. Открывается вкладка «Луна»: стройте колонию и добывайте гелий-3."},
	"mars_probe": {"name": "Марсоход", "cost": 150000, "days": 30, "need": "mars", "chance": 0.75, "once": true, "supplies": 3000,
		"desc": "Ровер ищет воду и места для посадки."},
	"mars": {"name": "Экспедиция на Марс", "cost": 500000, "days": 40, "need": "mars", "after": "mars_probe", "chance": 0.68, "once": true, "crew": 4, "supplies": 12000,
		"desc": "Первые люди на Марсе — и они из вашего города! Туризм +6 000."},
	"colony": {"name": "Колония на Марсе", "cost": 800000, "days": 50, "need": "mars", "after": "mars", "chance": 0.72, "once": true, "crew": 4, "supplies": 16000,
		"desc": "Открывается вкладка «Марс»: колония добывает руду и воду на другой планете."},
}
# Off-world colonies (TheoTown's Moon map): buildings placed on a small tile map in the УГК window.
# Tiles: 0 plain, 1 crater (can't build), 2 main resource (Moon: helium-3, Mars: iron ore), 3 ice
const COLONY_SIZE := Vector2i(14, 9)
const COLONIES := {
	"moon": {"name": "Луна", "mission": "moonbase", "res": "гелий-3", "price": 400.0, "ground": Color("8d8d8d"), "crater": Color("5e5e5e"), "ore": Color("4fc3f7"), "ice": Color("9ccc65")},
	"mars": {"name": "Марс", "mission": "colony", "res": "руда", "price": 350.0, "ground": Color("b5562e"), "crater": Color("7a3418"), "ore": Color("90a4ae"), "ice": Color("e3f2fd")},
}
const COLONY_BUILD := {
	"hab": {"name": "Жилой модуль", "cost": 60000, "power": -2, "pop": 20, "icon": "zone_r", "model": "poly/moon_modules",
		"desc": "Дом для 20 колонистов. Нужны электричество и вода (1 ледяная шахта на 4 модуля)."},
	"solar": {"name": "Солнечная ферма", "cost": 25000, "power": 8, "icon": "sun", "model": "poly/solar_panel", "desc": "+8 ед. энергии колонии."},
	"mine": {"name": "Добывающая станция", "cost": 100000, "power": -3, "workers": 10, "tile": 2, "icon": "zone_i", "model": "poly/moon_lander",
		"desc": "Ставится на месторождение (голубые камни на Луне, серые на Марсе). Добывает 30 т в месяц."},
	"ice": {"name": "Ледяная шахта", "cost": 50000, "power": -2, "workers": 4, "tile": 3, "icon": "water", "model": "poly/space_rover",
		"desc": "Ставится на лёд (зелёные камни). Вода и кислород для 4 жилых модулей."},
	"lab": {"name": "Научная лаборатория", "cost": 80000, "power": -2, "workers": 6, "icon": "edu", "model": "poly/astro_dome",
		"desc": "+10 очков исследований УГК в месяц."},
	"port": {"name": "Космопорт колонии", "cost": 150000, "power": -2, "workers": 6, "icon": "space", "model": "poly/museum_rocket", "max": 1,
		"desc": "Отправляет добычу на Землю: доход каждый месяц. Гелий-3 идёт на гелиевую электростанцию города."},
}

const COVERS := ["fire", "police", "health", "edu", "park", "garbage", "rescue", "death"]

# Service budget categories (percent sliders 50..150)
const BUDGET_CATS := [["power", "Электричество"], ["water", "Водоснабжение и стоки"], ["safety", "Безопасность"], ["health", "Здоровье, мусор, ритуальные"],
	["edu", "Образование"], ["park", "Парки"], ["transport", "Общественный транспорт"]]

# Natural resources (City.resource values)
const RESOURCES := {
	1: {"name": "Плодородная земля", "color": Color("c8b432")},
	2: {"name": "Лес", "color": Color("1f6b2a")},
	3: {"name": "Руда", "color": Color("8e7cc3")},
	4: {"name": "Нефть", "color": Color("1c1c1c")},
}
# Industry specializations for districts: res = required resource
const SPECS := {
	"forest": {"name": "Лесная промышленность", "res": 2, "income": 1.35, "pol": 0.4, "deplete": false, "icon": "tree",
		"desc": "Лесопилки. Нужен лес. Почти не загрязняют."},
	"farming": {"name": "Сельское хозяйство", "res": 1, "income": 1.3, "pol": 0.2, "deplete": false, "icon": "zone_a",
		"desc": "Фермы и теплицы. Нужна плодородная земля. Не загрязняют."},
	"ore": {"name": "Добыча руды", "res": 3, "income": 1.6, "pol": 1.5, "deplete": true, "icon": "zone_i",
		"desc": "Шахты. Нужна руда, которая со временем истощается. Сильно загрязняют."},
	"oil": {"name": "Нефтедобыча", "res": 4, "income": 1.8, "pol": 1.6, "deplete": true, "icon": "power",
		"desc": "Нефтяные качалки. Нужна нефть, которая истощается. Сильно загрязняют."},
}
const DISASTERS := {
	"tornado": {"name": "Торнадо", "icon": "dis_tornado", "desc": "Вихрь проносится через карту, разрушая здания."},
	"earthquake": {"name": "Землетрясение", "icon": "dis_quake", "desc": "Подземные толчки рушат здания вокруг эпицентра."},
	"meteor": {"name": "Метеорит", "icon": "dis_meteor", "desc": "Падение метеорита оставляет кратер и пожары."},
	"flood": {"name": "Наводнение", "icon": "dis_flood", "desc": "Вода выходит из берегов и затапливает низины."},
}

const CATEGORIES := [
	{"id": "roads",  "name": "Дороги",       "icon": "road"},
	{"id": "zones",  "name": "Зонирование",  "icon": "zone_r"},
	{"id": "transport", "name": "Транспорт", "icon": "bus"},
	{"id": "power",  "name": "Электричество","icon": "power"},
	{"id": "water",  "name": "Водоснабжение","icon": "water"},
	{"id": "safety", "name": "Безопасность", "icon": "police"},
	{"id": "health", "name": "Здоровье",     "icon": "health"},
	{"id": "edu",    "name": "Образование",  "icon": "edu"},
	{"id": "park",   "name": "Парки",        "icon": "park"},
	{"id": "landmark", "name": "Уникальные", "icon": "landmark"},
	{"id": "ugk", "name": "УГК", "icon": "space"},
	{"id": "districts", "name": "Районы", "icon": "district"},
	{"id": "tools",  "name": "Снос и ландшафт", "icon": "bulldoze"},
]

const MILESTONES := [
	{"pop": 0,     "name": "Пустошь", "reward": 0},
	{"pop": 120,   "name": "Деревушка", "reward": 10000},
	{"pop": 400,   "name": "Посёлок", "reward": 15000},
	{"pop": 1000,  "name": "Городок", "reward": 25000},
	{"pop": 2500,  "name": "Город", "reward": 40000},
	{"pop": 6000,  "name": "Крупный город", "reward": 70000},
	{"pop": 12000, "name": "Мегаполис", "reward": 120000},
]

const OVERLAYS := [
	{"id": "none",      "name": "Без слоя"},
	{"id": "power",     "name": "Электричество"},
	{"id": "water",     "name": "Вода"},
	{"id": "sewage",    "name": "Канализация"},
	{"id": "waterpol",  "name": "Загрязнение воды"},
	{"id": "flood",     "name": "Затопления"},
	{"id": "resources", "name": "Природные ресурсы"},
	{"id": "landvalue", "name": "Стоимость земли"},
	{"id": "pollution", "name": "Загрязнение"},
	{"id": "noise",     "name": "Шум"},
	{"id": "traffic",   "name": "Трафик"},
	{"id": "transit",   "name": "Общественный транспорт"},
	{"id": "happiness", "name": "Счастье"},
	{"id": "fire",      "name": "Пожарная охрана"},
	{"id": "police",    "name": "Полиция"},
	{"id": "health",    "name": "Здравоохранение"},
	{"id": "edu",       "name": "Образование"},
	{"id": "garbage",   "name": "Вывоз мусора"},
	{"id": "death",     "name": "Ритуальные услуги"},
]

const MAP_TYPES := {
	"river": {"name": "Речная долина", "desc": "Река, озеро и горы на горизонте."},
	"coast": {"name": "Морское побережье", "desc": "Город у моря: пляжи и порт."},
	"mountains": {"name": "Горный край", "desc": "Высокие горы и узкие долины. Сложнее строить."},
	"lakes": {"name": "Озёрный край", "desc": "Равнина с множеством озёр."},
}
const DIFFICULTY := [
	{"name": "Лёгкая", "money": 150000.0, "income": 1.2},
	{"name": "Обычная", "money": 70000.0, "income": 1.0},
	{"name": "Сложная", "money": 35000.0, "income": 0.85},
	{"name": "Песочница", "money": 9999999.0, "income": 1.0},
]
const CITY_NAMES := ["Новоградск", "Солнечногорск", "Светлоград", "Зеленодольск", "Приозёрск", "Северск", "Речной",
	"Каменск", "Ясногорск", "Лесной Бор", "Звёздный", "Белогорье", "Тихоречье", "Новая Заря", "Озёрск", "Вишнёвогорск"]

const MONTHS := ["Янв", "Фев", "Мар", "Апр", "Май", "Июн", "Июл", "Авг", "Сен", "Окт", "Ноя", "Дек"]


static func zone_kind(z: int) -> String:
	return ZONES[z]["kind"] if ZONES.has(z) else ""


static func date_string(day: int) -> String:
	var m := (day / DAYS_PER_MONTH) % 12
	var y := 2026 + day / (DAYS_PER_MONTH * 12)
	return "%d %s %d" % [day % DAYS_PER_MONTH + 1, MONTHS[m], y]


static func fmt_int(v: float) -> String:
	var neg := v < 0
	var s := str(int(abs(round(v))))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out
