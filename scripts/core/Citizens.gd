class_name Citizens
## Procedural citizen personas and "Chirper" post generation.

const FIRST_M := ["Алексей", "Иван", "Дмитрий", "Сергей", "Андрей", "Михаил", "Николай", "Павел", "Артём", "Егор",
	"Максим", "Владимир", "Олег", "Тимур", "Роман", "Кирилл", "Григорий", "Фёдор", "Степан", "Лев"]
const FIRST_F := ["Анна", "Мария", "Елена", "Ольга", "Наталья", "Татьяна", "Ирина", "Светлана", "Дарья", "Ксения",
	"Полина", "Алина", "Вера", "Юлия", "Екатерина", "Софья", "Варвара", "Милана", "Ева", "Надежда"]
const LAST := ["Иванов", "Петров", "Смирнов", "Кузнецов", "Соколов", "Попов", "Лебедев", "Козлов", "Новиков", "Морозов",
	"Волков", "Соловьёв", "Васильев", "Зайцев", "Павлов", "Семёнов", "Голубев", "Виноградов", "Богданов", "Воробьёв",
	"Фролов", "Комаров", "Орлов", "Белов", "Медведев", "Ершов", "Никитин", "Сорокин", "Гусев", "Тихонов"]
const HOBBIES := ["рыбалку", "шахматы", "велосипед", "садоводство", "фотографию", "бег по утрам", "настольные игры",
	"кулинарию", "театр", "футбол", "вязание", "походы в горы", "джаз", "старые фильмы", "йогу"]
const AVATAR_COLORS := [Color("ef5350"), Color("ab47bc"), Color("5c6bc0"), Color("29b6f6"), Color("26a69a"), Color("9ccc65"),
	Color("ffca28"), Color("ff7043"), Color("8d6e63"), Color("78909c")]


static func persona(sd: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = sd
	var female := r.randf() < 0.5
	var first: String = (FIRST_F if female else FIRST_M)[r.randi() % 20]
	var last: String = LAST[r.randi() % LAST.size()]
	if female:
		last += "а"
	var age := r.randi_range(18, 82)
	return {
		"name": "%s %s" % [first, last], "first": first, "female": female, "age": age,
		"hobby": HOBBIES[r.randi() % HOBBIES.size()],
		"handle": "@" + _translit(first).to_lower() + "_" + str(r.randi_range(1, 99)),
		"color": AVATAR_COLORS[r.randi() % AVATAR_COLORS.size()],
		"initials": first.substr(0, 1) + last.substr(0, 1),
	}


static func age_word(a: int) -> String:
	var d := a % 10
	var h := a % 100
	if h >= 11 and h <= 14:
		return "%d лет" % a
	if d == 1:
		return "%d год" % a
	if d >= 2 and d <= 4:
		return "%d года" % a
	return "%d лет" % a


static func _translit(s: String) -> String:
	var m := {"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh", "з": "z", "и": "i", "й": "y",
		"к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
		"х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"}
	var out := ""
	for ch in s.to_lower():
		out += m.get(ch, ch)
	return out


## A thought for a citizen living in building b.
static func thought(city: City, home: Building, sd: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = sd + city.day / 10
	var opts: Array = []
	if home:
		if "power" in home.problems: opts.append("Опять нет света. Сколько можно сидеть при свечах?")
		if "water" in home.problems: opts.append("Из крана ничего не течёт… Где вода?!")
		if "garbage" in home.problems: opts.append("Мусор во дворе не вывозят уже неделю.")
		if "sick" in home.problems: opts.append("Кашляю из-за завода по соседству.")
		if "crime" in home.problems: opts.append("Вечером страшно выходить из дома.")
		if "sewage" in home.problems: opts.append("Канализация опять засорилась. Во дворе такой запах…")
		if "dirtywater" in home.problems: opts.append("Вода из крана мутная и пахнет. Пью только из бутылок.")
		if "dead" in home.problems: opts.append("Дедушку до сих пор не забрали… Где катафалк?!")
		if city.avg_cover(home, "death") > 0.3 and home.seed % 5 == 0: opts.append("Рядом кладбище. Тихо, хоть и немного жутковато.")
		if home.happiness > 75: opts.append("Мне очень нравится мой район!")
		if city.avg_cover(home, "park") > 0.3: opts.append("Люблю гулять в парке рядом с домом.")
		if city.avg_cover(home, "transit") > 0.3: opts.append("Хорошо, что рядом остановка — до работы быстро.")
		if city.avg_field(home, city.noise) > 0.4: opts.append("Под окнами такой шум, что не уснуть.")
	if city.unemployment > 0.15: opts.append("Ищу работу уже месяц. Вакансий нет…")
	if city.taxes.r > 12: opts.append("Налоги в этом городе слишком высокие.")
	if city.taxes.r < 7: opts.append("С такими низкими налогами жить можно!")
	opts.append_array(["Думаю, чем заняться в выходные.", "Хочется сходить в новое кафе.", "Пора бы в отпуск.",
		"Какая сегодня погода!", "Надо не забыть купить хлеба."])
	return opts[r.randi() % opts.size()]


## Generates a post about the current city state (or null).
static func city_chirp(city: City, rng: RandomNumberGenerator) -> String:
	var opts: Array = []
	var total_tr := 0.0
	var cnt := 0
	for i in city.n * city.n:
		if city.road[i] > 0:
			total_tr += city.traffic[i]
			cnt += 1
	var avg_tr: float = total_tr / max(1, cnt)
	if avg_tr > 6.0: opts.append("Опять пробки! Полчаса стою на одном перекрёстке 🚗🚗🚗 #пробки")
	if city.power_demand > city.power_supply: opts.append("Электричества не хватает на весь город. Мэр, где новая станция? ⚡")
	if city.water_demand > city.water_supply: opts.append("Воду дают по часам. Это нормально вообще? 💧")
	if city.taxes.r > 12: opts.append("Налоги опять подняли. Скоро на еду не останется 💸")
	if city.taxes.r < 8: opts.append("Мэр снизил налоги — респект! 👍")
	if city.unemployment > 0.12: opts.append("Кто знает, где сейчас нужны работники? Хоть кем пойду…")
	if city.demand.r > 70: opts.append("Хотим переехать в этот город, но жилья не найти! 🏠")
	if city.demand.c > 70: opts.append("В нашем районе даже продуктового магазина нет 🛒")
	if city.transit_riders > 50: opts.append("Езжу на работу на автобусе — быстро и удобно 🚌")
	if city.avg_happiness > 75: opts.append("Лучший город на свете ❤ #люблюсвойгород")
	if city.avg_happiness < 40: opts.append("Всё плохо. Подумываю переехать отсюда… 😞")
	if city.lines.size() == 0 and city.population > 800: opts.append("Когда у нас появится общественный транспорт?")
	opts.append_array(["Отличная погода для прогулки ☀", "Кто-нибудь видел мою кошку? Рыжая, откликается на «Пончик» 🐈",
		"Открыл для себя новую пекарню. Круассаны — огонь 🥐", "Субботник в эту субботу, присоединяйтесь! 🧹",
		"Кто идёт на футбол в выходные? ⚽", "Вчера был такой красивый закат над рекой 🌅"])
	if city.districts.size() > 0:
		var d: Dictionary = city.districts.values()[rng.randi() % city.districts.size()]
		opts.append("В районе «%s» стало так уютно ✨" % d.name)
	return opts[rng.randi() % opts.size()]
