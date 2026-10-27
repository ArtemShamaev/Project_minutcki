extends CanvasLayer
## Game HUD, built entirely in code.

signal new_game_requested(params: Dictionary)
signal continue_requested
signal save_requested
signal load_requested
signal menu_requested
signal speed_requested(s: int)

var main
var city: City
var tools

var root: Control
var vignette: TextureRect
var loading: CanvasLayer
var top_bar: PanelContainer
var lbl_money: Label
var lbl_delta: Label
var lbl_pop: Label
var lbl_happy: Label
var lbl_date: Label
var lbl_milestone: Label
var rci: Control
var speed_btns: Array = []
var toolbar: PanelContainer
var subpanel: PanelContainer
var sub_box: HFlowContainer
var cat_btns := {}
var cur_cat := ""
var info_panel: PanelContainer
var info_box: VBoxContainer
var overlay_panel: PanelContainer
var overlay_btns := {}
var budget_panel: PanelContainer
var budget_box: VBoxContainer
var tax_labels := {}
var bud_labels := {}
var auto_demolish_cb: CheckButton
var stats_panel: PanelContainer
var stats_graph: Control
var stats_box: VBoxContainer
var help_panel: PanelContainer
var lines_panel: PanelContainer
var policy_panel: PanelContainer
var disaster_panel: PanelContainer
var advisor_panel: PanelContainer
var advisor_box: VBoxContainer
var paper_panel: PanelContainer
var paper_box: VBoxContainer
var paper_btn: Button
var issues: Array = []
var _prev_snapshot := {}
var ticker: PanelContainer
var ticker_clip: Control
var ticker_label: Label
var _ticker_x := 0.0
var road_panel: PanelContainer
var road_box: VBoxContainer
var road_tile := Vector2i(-1, -1)
var quest_panel: PanelContainer
var quest_box: VBoxContainer
var minimap: Control
var newgame_panel: PanelContainer
var tut_panel: PanelContainer
var tut_label: Label
var tut_step := -1
var tut_base_roads := 0
var _tut_t := 0.0
var _tut_tw: Tween
var _tut_btn: Control
const TUT := [
	{"text": "Шаг 1/6. Постройте дорогу: откройте «Дороги», выберите «Улица» и протяните её мышью от шоссе на западе.", "cat": "roads"},
	{"text": "Шаг 2/6. Откройте «Зонирование», выберите «Жилая» и закрасьте клетки вдоль новой улицы (тяните мышью).", "cat": "zones"},
	{"text": "Шаг 3/6. Жителям нужна работа и магазины: разметьте немного «Торговли» и «Промзоны» (лучше подальше от домов).", "cat": "zones"},
	{"text": "Шаг 4/6. Дома без света пустеют. Откройте «Электричество» и поставьте ветрогенератор или ТЭЦ у дороги.", "cat": "power"},
	{"text": "Шаг 5/6. Теперь вода: «Водоснабжение» → водонапорная башня у дороги (насосную ставят на берегу). Стокам нужен канализационный сток у воды — подальше от насосов!", "cat": "water"},
	{"text": "Шаг 6/6. Запустите время (Пробел или ▶) и дождитесь первых жителей. Следите за столбиками спроса Ж/Т/П!", "cat": ""},
]
var agent_panel: PanelContainer
var land_panel: PanelContainer
var region_panel: PanelContainer
var subsidy_panel: PanelContainer
var subsidy_box: VBoxContainer
var space_panel: PanelContainer
var space_box: VBoxContainer
var space_tab := "overview"
var colony_pick := ""                 # colony building chosen in the УГК window ("demolish" to remove)
var colony_view: SubViewportContainer
var gov_panel: PanelContainer
var gov_box: VBoxContainer
var ach_panel: PanelContainer
var ach_box: GridContainer
var region_box: VBoxContainer
var land_grid: GridContainer
var land_info_box: VBoxContainer
var land_sel := -1
var agent_box: VBoxContainer
var chirp_panel: PanelContainer
var chirp_box: VBoxContainer
var chirp_btn: Button
var chirps: Array = []
var unread := 0
var _chirp_rng := RandomNumberGenerator.new()
var policy_box: VBoxContainer
var policy_target: OptionButton
var lines_box: VBoxContainer
var notif_box: VBoxContainer
var tip_panel: PanelContainer
var tip_label: Label
var banner: PanelContainer
var banner_label: Label
var menu_layer: Control
var pause_layer: Control
var btn_continue: Button
var toast: Label
var _refresh_t := 0.0
var font: Font

const BG := Color(0.08, 0.1, 0.14, 0.92)
const BG2 := Color(0.13, 0.16, 0.22, 0.95)
const ACCENT := Color(0.25, 0.55, 0.95)
const TXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.62, 0.67, 0.75)
const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.45, 0.4)

const SERVICE_ICONS := {"wind": "power", "coal": "power", "solar": "sun", "tower": "water", "pump": "water",
	"fire": "fire", "police": "police", "clinic": "health", "hospital": "health", "landfill": "garbage",
	"cityhall": "landmark", "tvtower": "landmark", "cathedral": "landmark", "museum": "landmark", "stadium": "landmark", "pagoda": "landmark", "heaven": "landmark", "spaceport": "space", "arcology": "landmark", "fusion": "power", "dsa_hq": "space", "launchpad": "space", "mission_control": "dish", "rocket_factory": "factory", "astro_center": "astro", "observatory": "observatory", "rectenna": "dish", "space_museum": "landmark", "he3_plant": "power", "port": "landmark", "airport": "landmark",
	"nuclear": "power", "watertreat": "water", "recycling": "recycle", "incinerator": "garbage", "library": "edu", "college": "edu",
	"playground": "park", "sports": "park", "zoo": "landmark",
	"rescue": "rescue", "school": "edu", "university": "edu", "park": "park", "bigpark": "park", "plaza": "park", "busdepot": "bus", "tramdepot": "tram", "metro": "metro",
	"outlet": "sewage", "sewtreat": "sewtreat", "hydro": "hydro", "cemetery": "cemetery", "crematorium": "crematorium", "cargo": "cargo", "train_station": "train", "cargo_station": "cargo"}


func setup(m) -> void:
	main = m
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	# soft vignette under the interface (a texture, no screen read: free on weak GPUs)
	var vl := CanvasLayer.new()
	vl.layer = 1
	add_child.call_deferred(vl)
	vignette = TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0))
	gr.set_color(1, Color(0, 0, 0, 0.42))
	gr.add_point(0.55, Color(0, 0, 0, 0.0))
	gt.gradient = gr
	gt.width = 256
	gt.height = 256
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.visible = main.quality >= 1
	vl.add_child(vignette)
	add_child(root)
	_build_top_bar()
	_build_toolbar()
	_build_info()
	_build_overlay_panel()
	_build_budget()
	_build_stats()
	_build_help()
	_build_lines()
	_build_policies()
	_build_land()
	_build_region()
	_build_subsidies()
	_build_space()
	_build_gov()
	_build_achievements()
	_build_disasters()
	_build_agent_panel()
	_build_road_panel()
	_build_quests()
	_build_minimap()
	_build_newgame()
	_build_tutorial()
	_build_advisors()
	_build_paper()
	_build_ticker()
	_build_chirper()
	_build_notifs()
	_build_tooltip()
	_build_banner()
	_build_pause()
	_build_menu()


func rebind(c: City, t) -> void:
	city = c
	tools = t
	city.notify.connect(add_notification)
	city.milestone_reached.connect(_on_milestone)
	tools.tooltip.connect(_on_tooltip)
	tools.selected.connect(_on_selected)
	tools.tool_changed.connect(_on_tool_changed)
	tools.agent_selected.connect(_on_agent)
	tools.road_selected.connect(_on_road)
	city.quest_done.connect(_on_quest)
	minimap.set("city", city)
	minimap.set("rig", main.rig)
	_refresh_quests()
	city.day_passed.connect(_on_day_chirp)
	city.month_ended.connect(_publish_paper)
	issues.clear()
	_prev_snapshot = {"pop": city.population}
	_rebuild_ticker()
	city.milestone_reached.connect(func(i): _chirp_event("Ура! Наш город теперь «%s»! 🎉" % Defs.MILESTONES[i].name))
	chirps.clear()
	unread = 0
	_refresh_chirps()
	cur_cat = ""
	for ch in sub_box.get_children():
		ch.queue_free()
	subpanel.visible = false
	info_panel.visible = false
	for ch in notif_box.get_children():
		ch.queue_free()
	set_overlay("none")
	tut_step = -1
	if tut_panel:
		tut_panel.visible = false
		_highlight("")


# ================================================================== theme
func _sb(col: Color, radius: int = 8, margin: int = 8, border: Color = Color(1, 1, 1, 0.07)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	s.border_color = border
	s.set_border_width_all(1)
	return s


func _make_theme() -> Theme:
	var th := Theme.new()
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Inter", "Noto Sans", "Ubuntu", "Cantarell", "DejaVu Sans", "Sans-Serif"])
	sf.font_weight = 500
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font = sf
	th.default_font = sf
	th.default_font_size = 15
	var panel := _sb(BG, 10, 10)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 8
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("normal", "Button", _sb(BG2, 7, 8))
	th.set_stylebox("hover", "Button", _sb(Color(0.2, 0.25, 0.34), 7, 8, Color(1, 1, 1, 0.18)))
	th.set_stylebox("pressed", "Button", _sb(Color(0.18, 0.4, 0.72), 7, 8, Color(0.5, 0.75, 1, 0.6)))
	th.set_stylebox("hover_pressed", "Button", _sb(Color(0.22, 0.47, 0.82), 7, 8, Color(0.5, 0.75, 1, 0.7)))
	th.set_stylebox("disabled", "Button", _sb(Color(0.1, 0.11, 0.14, 0.9), 7, 8))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.48, 0.53))
	th.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.3))
	th.set_color("font_color", "Label", TXT)
	th.set_stylebox("panel", "TooltipPanel", _sb(Color(0.05, 0.06, 0.09, 0.96), 6, 8))
	th.set_color("font_color", "TooltipLabel", TXT)
	th.set_stylebox("slider", "HSlider", _sb(Color(0.2, 0.23, 0.3), 4, 2))
	th.set_stylebox("grabber_area", "HSlider", _sb(ACCENT, 4, 2))
	th.set_stylebox("grabber_area_highlight", "HSlider", _sb(ACCENT.lightened(0.2), 4, 2))
	th.set_stylebox("normal", "LineEdit", _sb(Color(0.05, 0.06, 0.09), 6, 8))
	th.set_stylebox("background", "ProgressBar", _sb(Color(0.18, 0.2, 0.26), 4, 0))
	th.set_stylebox("fill", "ProgressBar", _sb(GOOD.darkened(0.2), 4, 0))
	th.set_color("font_color", "ProgressBar", Color.WHITE)
	return th


func _label(text: String, size: int = 15, col: Color = TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _icon(name: String, size: int = 22) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.get_tex(name, 64)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	return t


func _button(text: String, icon: String = "", cb: Callable = Callable(), icon_size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	if icon != "":
		b.icon = Icons.get_tex(icon, 64)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", icon_size)
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(func(): Sfx.play("click", -10.0))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _window(title: String, size: Vector2) -> Array:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	p.visible = false
	root.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := _label(title, 19)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var x := _button("", "close", func(): p.visible = false, 14)
	hb.add_child(x)
	vb.add_child(HSeparator.new())
	return [p, vb]


# ================================================================== top bar
func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 10
	top_bar.offset_right = -10
	top_bar.offset_top = 8
	root.add_child(top_bar)
	var hb := HFlowContainer.new()
	hb.add_theme_constant_override("h_separation", 14)
	hb.add_theme_constant_override("v_separation", 6)
	top_bar.add_child(hb)
	hb.add_child(_button("", "menu", func(): toggle_pause_menu(), 20))
	var title := _label("BS: Cities", 18, Color(0.75, 0.85, 1.0))
	hb.add_child(title)
	lbl_milestone = _label("", 13, DIM)
	hb.add_child(lbl_milestone)
	hb.add_child(VSeparator.new())
	hb.add_child(_icon("coin"))
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", -4)
	lbl_money = _label("₽0", 17)
	lbl_delta = _label("", 12, GOOD)
	mv.add_child(lbl_money)
	mv.add_child(lbl_delta)
	hb.add_child(mv)
	hb.add_child(VSeparator.new())
	hb.add_child(_icon("people"))
	lbl_pop = _label("0", 17)
	lbl_pop.tooltip_text = "Население"
	lbl_pop.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(lbl_pop)
	hb.add_child(_icon("smile"))
	lbl_happy = _label("0%", 17)
	lbl_happy.tooltip_text = "Среднее счастье жителей"
	lbl_happy.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(lbl_happy)
	hb.add_child(VSeparator.new())
	rci = RCIWidget.new()
	rci.custom_minimum_size = Vector2(66, 40)
	rci.tooltip_text = "Спрос: жильё (Ж), торговля (Т), рабочие места (П)"
	hb.add_child(rci)
	lbl_date = _label("", 16)
	lbl_date.custom_minimum_size.x = 120
	lbl_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(lbl_date)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 2)
	for i in 4:
		var b := _button("", ["pause", "play1", "play2", "play3"][i], func(): speed_requested.emit(i), 18)
		b.toggle_mode = true
		b.tooltip_text = ["Пауза [Пробел]", "Скорость 1 [1]", "Скорость 2 [2]", "Скорость 3 [3]"][i]
		speeds.add_child(b)
		speed_btns.append(b)
	hb.add_child(speeds)
	hb.add_child(VSeparator.new())
	var bb := _button("", "budget", func(): _toggle(budget_panel), 20)
	bb.tooltip_text = "Бюджет и налоги"
	hb.add_child(bb)
	var stb := _button("", "stats", func(): _toggle(stats_panel), 20)
	stb.tooltip_text = "Статистика"
	hb.add_child(stb)
	var rgb := _button("", "region", func(): _toggle(region_panel), 20)
	rgb.tooltip_text = "Регион и соседние города [G]"
	hb.add_child(rgb)
	var gvb := _button("", "gov", func(): _toggle(gov_panel), 20)
	gvb.tooltip_text = "Правительство: ратуша, министерства, субсидии [U]"
	hb.add_child(gvb)
	var spb := _button("", "space", func(): _toggle(space_panel), 20)
	spb.tooltip_text = "УГК — космическая программа [K]"
	hb.add_child(spb)

	var advb := _button("", "advisor", func(): _toggle(advisor_panel), 20)
	advb.tooltip_text = "Советники"
	hb.add_child(advb)
	paper_btn = _button("", "paper", func(): _toggle(paper_panel), 20)
	paper_btn.tooltip_text = "Газета «Вестник»"
	hb.add_child(paper_btn)
	var lawb := _button("", "law", func(): _toggle(policy_panel), 20)
	lawb.tooltip_text = "Законы"
	hb.add_child(lawb)
	var disb := _button("", "dis_tornado", func(): _toggle(disaster_panel), 20)
	disb.tooltip_text = "Катастрофы"
	hb.add_child(disb)
	chirp_btn = _button("", "bird", func(): _toggle_chirper(), 20)
	chirp_btn.tooltip_text = "Чирпер: что пишут горожане"
	hb.add_child(chirp_btn)
	var layb := _button("", "layers", func(): overlay_panel.visible = not overlay_panel.visible, 20)
	layb.tooltip_text = "Информационные слои"
	hb.add_child(layb)
	hb.add_child(_button("?", "", func(): _toggle(help_panel)))


func _toggle(p: Control) -> void:
	p.visible = not p.visible
	if p.visible:
		p.move_to_front()
		_refresh_windows()
		_center.call_deferred(p)


func _center(p: Control) -> void:
	if p.has_meta("scroll"):
		# fit scrollable windows into the screen
		var sc: Control = p.get_meta("scroll")
		var extra := p.get_combined_minimum_size().y - sc.custom_minimum_size.y
		sc.custom_minimum_size.y = clamp(root.size.y - extra - 24.0, 180.0, 520.0)
	p.reset_size()
	p.position = ((root.size - p.size) * 0.5).floor()



func set_speed(s: int) -> void:
	for i in speed_btns.size():
		speed_btns[i].button_pressed = i == s


class RCIWidget extends Control:
	var vals := [0.0, 0.0, 0.0]
	func _draw() -> void:
		var cols := [Color("5fd35f"), Color("4fa3ff"), Color("f2c230")]
		var letters := ["Ж", "Т", "П"]
		var bw := 16.0
		var h := size.y - 14
		for i in 3:
			var x := 4 + i * (bw + 6)
			draw_rect(Rect2(x, 0, bw, h), Color(1, 1, 1, 0.08))
			var v: float = clamp(vals[i] / 100.0, 0.0, 1.0)
			draw_rect(Rect2(x, h * (1.0 - v), bw, h * v), cols[i])
			draw_string(get_theme_default_font(), Vector2(x + 3, size.y), letters[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9))


# ================================================================== toolbar
func _build_toolbar() -> void:
	toolbar = PanelContainer.new()
	toolbar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toolbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toolbar.offset_bottom = -10
	toolbar.offset_left = 10
	toolbar.offset_right = -10
	root.add_child(toolbar)
	var hb := HFlowContainer.new()
	hb.alignment = FlowContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("h_separation", 6)
	hb.add_theme_constant_override("v_separation", 6)
	toolbar.add_child(hb)
	var sel := _cat_button("Выбор", "select")
	sel.pressed.connect(func(): _select_category(""); tools.set_tool({"type": "select"}))
	sel.tooltip_text = "Просмотр зданий [Esc]"
	hb.add_child(sel)
	cat_btns["select"] = sel
	hb.add_child(VSeparator.new())
	for c in Defs.CATEGORIES:
		var b := _cat_button(c.name, c.icon)
		var id: String = c.id
		b.pressed.connect(func(): _select_category(id))
		hb.add_child(b)
		cat_btns[id] = b
	subpanel = PanelContainer.new()
	subpanel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	subpanel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subpanel.offset_bottom = -100
	subpanel.offset_left = 60
	subpanel.offset_right = -60
	subpanel.visible = false
	root.add_child(subpanel)
	sub_box = HFlowContainer.new()
	sub_box.alignment = FlowContainer.ALIGNMENT_CENTER
	sub_box.add_theme_constant_override("h_separation", 6)
	sub_box.add_theme_constant_override("v_separation", 6)
	subpanel.add_child(sub_box)


func _cat_button(text: String, icon: String) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = Icons.get_tex(icon, 64)
	b.add_theme_constant_override("icon_max_width", 34)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(84, 66)
	b.add_theme_font_size_override("font_size", 12)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Sfx.play("click", -10.0))
	return b


func _select_category(id: String) -> void:
	if cur_cat == id and id != "":
		id = ""
		tools.set_tool({"type": "select"})
	cur_cat = id
	for k in cat_btns:
		cat_btns[k].button_pressed = (k == id) or (k == "select" and id == "" and tools.tool.type == "select")
	for ch in sub_box.get_children():
		ch.queue_free()
	subpanel.visible = id != ""
	if id == "":
		return
	match id:
		"roads":
			for rt in Defs.ROAD_TYPES:
				var rd: Dictionary = Defs.ROAD_TYPES[rt]
				_item(rd.name, rd.icon, "₽%d/клетка" % rd.cost, rd.unlock, {"type": "road", "rtype": rt},
					"%s\nСодержание ₽%s/мес за клетку. Над водой строится мост." % [rd.desc, Defs.fmt_int(rd.upkeep)])
			_item("Пешеходная дорожка", "path", "₽%d/клетка" % City.PATH_COST, 0, {"type": "path"},
				"Мощёная дорожка с фонарями и скамейками. Жители ходят по ней пешком: меньше машин, выше счастье и стоимость земли. Пересекает дороги по зебре, над водой строится мостик.")
		"transport":
			_item("Ж/д путь", "rail", "₽%d/клетка" % City.RAIL_COST, City.RAIL_UNLOCK, {"type": "rail"},
				"Железная дорога: тяните мышью. Поперёк прямой дороги получается переезд со шлагбаумом, над водой — мост. Пути, выходящие за край карты, связывают город с внешним миром.")
			for sid in ["train_station", "cargo_station", "busdepot", "tramdepot", "metro", "cargo"]:
				var s: Dictionary = Defs.SERVICES[sid]
				_item(s.name, SERVICE_ICONS.get(sid, "bus"), "₽" + Defs.fmt_int(s.cost), s.unlock, {"type": "service", "id": sid},
					"%s\nСтоимость: ₽%s, содержание ₽%s/мес" % [s.desc, Defs.fmt_int(s.cost), Defs.fmt_int(s.upkeep)])
			_item("Автобусный маршрут", "line_bus", "₽250/мес", 400, {"type": "line", "kind": "bus"}, "Кликайте по дорогам, чтобы расставить остановки. Нужен автобусный парк.")
			_item("Трамвайный маршрут", "line_tram", "₽500/мес", 1000, {"type": "line", "kind": "tram"}, "Как автобус, но втрое вместительнее. Рельсы прокладываются по дорогам. Нужно трамвайное депо.")
			_item("Линия метро", "line_metro", "₽900/мес", 1000, {"type": "line", "kind": "metro"}, "Кликайте по станциям метро по порядку.")
			var lb := _button("Маршруты", "stats", func(): _toggle(lines_panel), 26)
			lb.custom_minimum_size = Vector2(118, 82)
			lb.add_theme_font_size_override("font_size", 12)
			sub_box.add_child(lb)
		"zones":
			for z in [Defs.R_LOW, Defs.R_HIGH, Defs.C_LOW, Defs.C_HIGH, Defs.IND, Defs.OFFICE, Defs.AGRI]:
				var zd: Dictionary = Defs.ZONES[z]
				_item(zd.short, zd.icon, "бесплатно", zd.unlock, {"type": "zone", "zone": z}, zd.name)
			_item("Снять зону", "dezone", "", 0, {"type": "dezone"}, "Убирает зонирование (здания на участке будут снесены).")
		"districts":
			_item("Новый район", "district", "", 0, {"type": "district", "mode": "new"}, "Создаёт новый район: нажмите и рисуйте кистью.")
			_item("Кисть района", "district_paint", "", 0, {"type": "district", "mode": "paint"}, "Расширяет текущий район. Ctrl+клик — выбрать район.")
			_item("Стереть", "dezone", "", 0, {"type": "district", "mode": "erase"}, "Убирает клетки из районов.")
			var pb := _button("Законы", "law", func(): _toggle(policy_panel), 26)
			pb.custom_minimum_size = Vector2(118, 82)
			pb.add_theme_font_size_override("font_size", 12)
			sub_box.add_child(pb)
		"tools":
			var lb := _button("Участки", "land", func(): _toggle(land_panel), 26)
			lb.custom_minimum_size = Vector2(118, 82)
			lb.add_theme_font_size_override("font_size", 12)
			sub_box.add_child(lb)
			_item("Бульдозер", "bulldoze", "возврат 50%", 0, {"type": "bulldoze"}, "Сносит здания, дороги и деревья. Тяните мышью для области.")
			_item("Деревья", "tree", "₽%d" % Defs.TREE_COST, 0, {"type": "tree"}, "Деревья снижают загрязнение и украшают город.")
			_item("Поднять", "tf_raise", "", 0, {"type": "terraform", "mode": "raise"}, "Поднимает землю. [ и ] — размер кисти.")
			_item("Опустить", "tf_lower", "", 0, {"type": "terraform", "mode": "lower"}, "Опускает землю. Ниже уровня воды образуется водоём.")
			_item("Выровнять", "tf_level", "", 0, {"type": "terraform", "mode": "level"}, "Выравнивает землю до высоты в точке клика.")
			_item("Сгладить", "tf_smooth", "", 0, {"type": "terraform", "mode": "smooth"}, "Сглаживает неровности.")
		_:
			for sid in Defs.SERVICES:
				var s: Dictionary = Defs.SERVICES[sid]
				if s.cat == id:
					var extra := ""
					if s.has("power"): extra = "\nМощность: %d МВт" % s.power
					if s.has("water"): extra = "\nВода: %d тыс. м³" % s.water
					if s.has("sewage"): extra = "\nСтоки: %d тыс. м³" % s.sewage
					if s.has("radius"): extra = "\nРадиус: %d клеток" % s.radius
					if s.has("store"): extra += "\nВместимость: %s" % Defs.fmt_int(s.store)
					_item(s.name, SERVICE_ICONS.get(sid, "select"), "₽" + Defs.fmt_int(s.cost) if s.cost > 0 else "награда", city.service_unlock(sid), {"type": "service", "id": sid},
						"%s\nСтоимость: ₽%s, содержание ₽%s/мес%s" % [s.desc, Defs.fmt_int(s.cost), Defs.fmt_int(s.upkeep), extra], city.space.unlock_reason(sid))
			if id == "ugk":
				var kb := _button("Окно УГК [K]", "space", func(): _toggle(space_panel), 26)
				kb.custom_minimum_size = Vector2(118, 82)
				kb.add_theme_font_size_override("font_size", 12)
				sub_box.add_child(kb)


func _item(name: String, icon: String, price: String, unlock: int, t: Dictionary, tip: String, lock: String = "") -> void:
	var b := Button.new()
	b.text = name + ("\n" + price if price != "" else "")
	b.icon = Icons.get_tex(icon, 64)
	b.add_theme_constant_override("icon_max_width", 30)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(118, 82)
	b.add_theme_font_size_override("font_size", 12)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_meta("tool", t)
	var locked := not city.is_unlocked(unlock)
	b.disabled = locked
	b.tooltip_text = tip + (("\n\n🔒 Нужно Министерство науки и космоса" if unlock >= 999999 else "\n\n🔒 Откроется при населении %s" % Defs.fmt_int(unlock)) if locked else "")
	if locked:
		b.text = name + ("\n🔒 мин. науки" if unlock >= 999999 else "\n🔒 " + Defs.fmt_int(unlock))
	b.pressed.connect(func(): tools.set_tool(t); Sfx.play("toggle", -8.0))
	if lock != "" and not locked:
		b.disabled = true
		b.text = name + "\n🔒"
		b.tooltip_text = tip + "\n\n🔒 " + lock
	b.button_pressed = _same_tool(tools.tool, t)
	sub_box.add_child(b)


func _same_tool(a: Dictionary, b: Dictionary) -> bool:
	return a.get("type") == b.get("type") and a.get("rtype", 1) == b.get("rtype", 1) and a.get("kind", "") == b.get("kind", "") and a.get("zone", -1) == b.get("zone", -1) and a.get("id", "") == b.get("id", "") and a.get("mode", "") == b.get("mode", "")


func _on_tool_changed(t: Dictionary) -> void:
	for ch in sub_box.get_children():
		if ch.has_meta("tool"):
			ch.button_pressed = _same_tool(t, ch.get_meta("tool"))
	if t.type == "select":
		cat_btns["select"].button_pressed = cur_cat == ""


func cancel_tool() -> bool:
	## Returns true if something was cancelled.
	if tools.tool.type != "select":
		tools.set_tool({"type": "select"})
		_select_category("")
		cat_btns["select"].button_pressed = true
		return true
	if cur_cat != "":
		_select_category("")
		return true
	if tools.selected_b:
		tools.select(null)
		return true
	for p in [budget_panel, stats_panel, help_panel]:
		if p.visible:
			p.visible = false
			return true
	return false


# ================================================================== info panel
func _build_info() -> void:
	info_panel = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.offset_right = -12
	info_panel.offset_top = 78
	info_panel.custom_minimum_size = Vector2(300, 0)
	info_panel.visible = false
	root.add_child(info_panel)
	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 5)
	info_panel.add_child(info_box)


func _on_selected(b: Building) -> void:
	info_panel.visible = b != null
	if b != null:
		agent_panel.visible = false
		road_panel.visible = false
	_refresh_info()


func _row(parent: Control, k: String, v: String, col: Color = TXT) -> void:
	var hb := HBoxContainer.new()
	var a := _label(k, 14, DIM)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(a)
	hb.add_child(_label(v, 14, col))
	parent.add_child(hb)


func _refresh_info() -> void:
	var b: Building = tools.selected_b
	if b == null or not city.buildings.has(b.id):
		info_panel.visible = false
		return
	for ch in info_box.get_children():
		ch.queue_free()
	var hb := HBoxContainer.new()
	var title := _label(b.display_name(), 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(title)
	hb.add_child(_button("", "close", func(): tools.select(null), 14))
	info_box.add_child(hb)
	if b.is_service():
		var def: Dictionary = Defs.SERVICES[b.type]
		info_box.add_child(_label(def.desc, 13, DIM))
		info_box.add_child(HSeparator.new())
		var bk: float = 1.0 if def.cat == "landmark" else city.bud(def.cat)
		_row(info_box, "Содержание", "₽%s/мес" % Defs.fmt_int(def.upkeep * bk))
		if def.cat != "landmark":
			_row(info_box, "Бюджет службы", "%d%%" % int(bk * 100), GOOD if bk >= 1.0 else Color(1, 0.8, 0.4))
		if def.has("power"):
			_row(info_box, "Мощность", "%d из %d МВт" % [int(city.svc_output(b, "power")), def.power])
			if b.type == "wind": _row(info_box, "Ветер", "%d%% (выше на холмах)" % int(city.env_factor(b) * 100), DIM)
			if b.type == "solar": _row(info_box, "Солнце", "%d%% (%s)" % [int(city.env_factor(b) * 100), city.season_name().to_lower()], DIM)
			if b.type == "hydro": _row(info_box, "Течение реки", "%d%% (быстрее — больше энергии)" % int(city.env_factor(b) * 100), GOOD if city.env_factor(b) > 0.8 else Color(1, 0.8, 0.4))
		if def.has("water"): _row(info_box, "Подача воды", "%d тыс. м³" % int(city.svc_output(b, "water")))
		if b.type == "pump" or b.type == "tower":
			var dp := city.pump_dirty(b)
			_row(info_box, "Качество воды", "загрязнена!" if dp > 0.25 else ("есть примеси" if dp > 0.08 else "чистая"), BAD if dp > 0.25 else (Color(1, 0.8, 0.4) if dp > 0.08 else GOOD))
		if b.type == "cityhall":
			var lv := clampi(b.level, 1, 3)
			_row(info_box, "Уровень", "%s (%d/3)" % [Defs.HALL_LEVELS[lv - 1].name, lv], Color(1, 0.85, 0.5))
			if lv < 3:
				var nx: Dictionary = Defs.HALL_LEVELS[lv]
				var us := city.upgrade_hall_state()
				var ub := _button("Улучшить до «%s» — ₽%s" % [nx.name, Defs.fmt_int(nx.cost)], "landmark", func():
					if city.upgrade_hall():
						Sfx.play("milestone", -8.0)
					_refresh_info(), 18)
				ub.disabled = not us.ok
				ub.tooltip_text = us.reason if not us.ok else "Больше мест для министерств: %d" % nx.slots
				info_box.add_child(ub)
				if not us.ok:
					info_box.add_child(_label(us.reason, 12, DIM))
			var mn: Array = []
			for mid in b.ministries:
				mn.append(Defs.MINISTRIES[mid].name.replace("Министерство ", ""))
			_row(info_box, "Министерства", "%d из %d" % [b.ministries.size(), city.hall_slots()], Color(0.75, 0.85, 1.0))
			if mn.size() > 0:
				var ml := _label(", ".join(mn), 12, DIM)
				ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				ml.custom_minimum_size.x = 280
				info_box.add_child(ml)
			info_box.add_child(_button("Министерства и субсидии…", "gov", func(): _toggle(gov_panel), 18))
		if b.type in ["train_station", "cargo_station"]:
			var lk := city.station_link(b)
			_row(info_box, "Пути у платформы", "есть" if lk.platform.x >= 0 else "нет — проложите рельсы вплотную", GOOD if lk.platform.x >= 0 else BAD)
			_row(info_box, "Связь с внешним миром", "есть" if lk.out else "нет (выведите пути за край карты)", GOOD if lk.out else Color(1, 0.8, 0.4))
			_row(info_box, "Других станций в сети", str(lk.peers))
			if not lk.out and lk.peers == 0:
				info_box.add_child(_label("Поезда не ходят: нужна вторая станция или выход за край карты.", 12, BAD))
			elif b.type == "train_station":
				_row(info_box, "Пассажиров ж/д в месяц", Defs.fmt_int(city.rail_stats.riders), GOOD)
			elif not lk.out:
				info_box.add_child(_label("Экспорт по железной дороге работает только с выходом за край карты.", 12, Color(1, 0.8, 0.4)))
		if def.has("stages"):
			var st: int = def.stages
			if b.stage < st:
				_row(info_box, "Мегапроект", "этап %d из %d" % [b.stage + 1, st], Color(1, 0.8, 0.4))
				var pb2 := ProgressBar.new()
				pb2.value = (b.stage + b.stage_days / Defs.DAYS_PER_MONTH) / st * 100.0
				pb2.custom_minimum_size = Vector2(0, 14)
				info_box.add_child(pb2)
				if not b.funded:
					_row(info_box, "Нужно на этап", "₽" + Defs.fmt_int(def.stage_cost[b.stage]), BAD if city.money < def.stage_cost[b.stage] else TXT)
				else:
					_row(info_box, "Идёт стройка", "ещё ~%d дн." % int(Defs.DAYS_PER_MONTH - b.stage_days), GOOD)
			else:
				_row(info_box, "Мегапроект", "завершён", GOOD)
		if def.get("need_water", false) and def.has("water"):
			_row(info_box, "Уровень воды у насоса", "%d%%" % int(b.eff * 100), GOOD if b.eff > 0.9 else (Color(1, 0.8, 0.4) if b.eff > 0.4 else BAD))
		if def.has("sewage"):
			_row(info_box, "Приём стоков", "%d тыс. м³" % int(city.svc_output(b, "sewage")))
			_row(info_box, "Поступает по трубам", "%d тыс. м³" % int(b.sew_in), BAD if b.sew_in > city.svc_output(b, "sewage") * 0.98 else TXT)
		if b.flooded: _row(info_box, "Состояние", "ЗАТОПЛЕНО — не работает", BAD)
		if def.has("radius"): _row(info_box, "Радиус покрытия", "%d клеток" % int(city.svc_radius(b)))
		if def.has("export_cap"): _row(info_box, "Экспорт", "до %s ед. товаров" % Defs.fmt_int(def.export_cap))
		if b.store_cap() > 0.0:
			var fill: float = clamp(b.stored / b.store_cap(), 0.0, 1.0)
			_row(info_box, "Заполнено", "%s / %s (%d%%)" % [Defs.fmt_int(b.stored), Defs.fmt_int(b.store_cap()), int(fill * 100)], BAD if fill > 0.9 else TXT)
			var fb := ProgressBar.new()
			fb.value = fill * 100
			fb.custom_minimum_size = Vector2(0, 14)
			fb.show_percentage = false
			fb.add_theme_stylebox_override("fill", _sb(Overlays_heat(100 - fill * 100), 4, 0))
			info_box.add_child(fb)
			var proc_name := "мусоросжигательный завод или центр переработки" if def.cover == "garbage" else "крематорий"
			var eb := _button("Остановить опустошение" if b.emptying else "Опустошить", "rotate", func():
				city.set_emptying(b, not b.emptying)
				_refresh_info(), 16)
			eb.tooltip_text = "Содержимое вывозится на %s. Пока идёт опустошение, объект не принимает новые поступления." % proc_name
			info_box.add_child(eb)
			if b.emptying:
				info_box.add_child(_label("⏳ Идёт опустошение…", 13, Color(1, 0.8, 0.4)))
		elif def.get("process", false):
			info_box.add_child(_label("♻ Перерабатывает без заполнения", 13, GOOD))
		_row(info_box, "Подключение к дороге", "есть" if b.has_road else "нет", GOOD if b.has_road else BAD)
	else:
		var zd: Dictionary = Defs.ZONES[b.zone]
		var stars := "★".repeat(b.level) + "☆".repeat(3 - b.level)
		var sub := _label("%s  %s" % [zd.short, stars], 14, zd.color.lightened(0.2))
		info_box.add_child(sub)
		info_box.add_child(HSeparator.new())
		if b.build_days > 0:
			info_box.add_child(_label("🏗 Идёт строительство: %d дн." % b.build_days, 14, Color(1, 0.8, 0.4)))
		if b.kind() == "r":
			_row(info_box, "Жители", "%d / %d" % [b.occ, b.cap])
		else:
			_row(info_box, "Работники", "%d / %d" % [b.occ, b.cap])
		var hp := ProgressBar.new()
		hp.value = b.happiness
		hp.custom_minimum_size = Vector2(0, 16)
		hp.show_percentage = false
		var fill := _sb(Overlays_heat(b.happiness), 4, 0)
		hp.add_theme_stylebox_override("fill", fill)
		_row(info_box, "Счастье", "%d%%" % int(b.happiness))
		info_box.add_child(hp)
		_row(info_box, "Электричество", "есть" if b.powered else "нет", GOOD if b.powered else BAD)
		_row(info_box, "Водоснабжение", "есть" if b.watered else "нет", GOOD if b.watered else BAD)
		_row(info_box, "Канализация", "есть" if b.sewered else "нет", GOOD if b.sewered else BAD)
		# the people living / working here
		var ids: Array = city.people.residents(b) if b.kind() == "r" else city.people.workers(b)
		if ids.size() > 0:
			info_box.add_child(_label(("Жители" if b.kind() == "r" else "Работники") + " (%d)" % ids.size(), 13, DIM))
			var shown := 0
			for pid in ids:
				if shown >= 5:
					break
				var pp = city.people.get_person(pid)
				var occ: String = city.people.occupation(pp) if b.kind() == "r" else People.EDU_NAMES[pp.edu]
				var id2: int = pid
				var rb2 := _button("%s, %d — %s" % [city.people.full_name(pp), pp.age, occ], "", func(): show_person(id2), 0)
				rb2.add_theme_font_size_override("font_size", 12)
				rb2.alignment = HORIZONTAL_ALIGNMENT_LEFT
				rb2.clip_text = true
				rb2.custom_minimum_size.x = 300
				info_box.add_child(rb2)
				shown += 1
			if ids.size() > 5:
				info_box.add_child(_label("…и ещё %d" % (ids.size() - 5), 12, DIM))
		var sp := city.ind_spec(b)
		if sp != "":
			var sr := city.spec_resource(b, sp)
			_row(info_box, "Специализация", Defs.SPECS[sp].name, Color(0.8, 0.75, 1.0))
			_row(info_box, Defs.RESOURCES[Defs.SPECS[sp].res].name, "%d%%" % int(sr * 100) if sr >= 0.05 else ("истощено" if Defs.SPECS[sp].deplete else "нет на участке"), GOOD if sr > 0.3 else BAD)
		if b.type == "zone" and not b.abandoned and b.zone != Defs.IND and b.zone != Defs.AGRI:
			# architecture of this building
			var sr2 := HBoxContainer.new()
			var sl2 := _label("Архитектура", 14, DIM)
			sl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sr2.add_child(sl2)
			var so2 := OptionButton.new()
			so2.focus_mode = Control.FOCUS_NONE
			so2.add_theme_font_size_override("font_size", 13)
			var area_style: String = city.style_at(Vector2i(b.x, b.y))
			so2.add_item("Как в районе (%s)" % Defs.STYLES[area_style].name, 0)
			var bkeys: Array = Defs.STYLES.keys()
			for i in bkeys.size():
				so2.add_item(Defs.STYLES[bkeys[i]].name, i + 1)
			so2.select(so2.get_item_index(bkeys.find(b.style) + 1) if b.style_lock else 0)
			so2.tooltip_text = "Перестроить это здание в другом стиле — ₽%d. Выбранный стиль сохраняется при улучшении." % City.RESTYLE_COST
			var tb := b
			so2.item_selected.connect(func(ix):
				var id: int = so2.get_item_id(ix)
				if city.set_building_style(tb, "" if id == 0 else bkeys[id - 1]):
					Sfx.play("place", -6.0)
				else:
					add_notification("Недостаточно денег для перестройки (₽%d)." % City.RESTYLE_COST, "bad")
				_refresh_info.call_deferred())
			sr2.add_child(so2)
			info_box.add_child(sr2)
		_row(info_box, "Стоимость земли", "%d" % int(city.avg_field(b, city.land_value)))
		_row(info_box, "Загрязнение", "%d%%" % int(city.avg_field(b, city.pollution) * 100))
		_row(info_box, "Шум", "%d%%" % int(city.avg_field(b, city.noise) * 100))
		var cov_names := {"fire": "Пожарная охрана", "police": "Полиция", "health": "Медицина", "edu": "Образование", "garbage": "Вывоз мусора", "death": "Ритуальные услуги"}
		for k in cov_names:
			var v := city.avg_cover(b, k)
			_row(info_box, cov_names[k], "%d%%" % int(v * 100), GOOD if v > 0.3 else (Color(1, 0.8, 0.4) if v > 0.05 else BAD))
		var probs := {"traffic": "Пробки у дома", "power": "Нет электричества", "water": "Нет воды", "noroad": "Нет дороги", "garbage": "Мусор не вывозится",
			"sick": "Жители болеют", "crime": "Высокая преступность", "abandoned": "Здание заброшено", "fire": "ПОЖАР!",
			"sewage": "Канализация не работает", "dead": "Умерших некому забрать", "dirtywater": "Из крана течёт грязная вода",
			"nobuyers": "Некому продавать товары", "flood": "Здание затоплено!", "depleted": "Месторождение истощено", "nores": "На участке нет нужного ресурса"}
		if b.problems.size() > 0:
			info_box.add_child(HSeparator.new())
			for p in b.problems:
				var hb2 := HBoxContainer.new()
				hb2.add_child(_icon("st_" + p, 18))
				hb2.add_child(_label(probs.get(p, p), 14, BAD))
				info_box.add_child(hb2)
		if b.level < 3 and b.build_days == 0 and not b.abandoned:
			info_box.add_child(_label(_level_hint(b), 12, DIM))
	info_box.add_child(HSeparator.new())
	var del := _button("Снести", "bulldoze", func():
		if b.is_service():
			city.money += Defs.SERVICES[b.type].cost * 0.5
		city.remove_building(b, "bulldoze")
		tools.select(null), 20)
	info_box.add_child(del)


func _level_hint(b: Building) -> String:
	match b.kind():
		"r": return "Для роста уровня нужны высокая стоимость земли и образование."
		"c": return "Для роста уровня нужна высокая стоимость земли."
	return "Для роста уровня нужны образованные работники."


static func Overlays_heat(h: float) -> Color:
	if h > 66: return Color(0.35, 0.8, 0.4)
	if h > 40: return Color(0.95, 0.75, 0.2)
	return Color(0.9, 0.3, 0.25)


# ================================================================== overlays
func _build_overlay_panel() -> void:
	overlay_panel = PanelContainer.new()
	overlay_panel.position = Vector2(12, 78)
	overlay_panel.visible = false
	root.add_child(overlay_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	overlay_panel.add_child(outer)
	outer.add_child(_label("Информационные слои", 15))
	var vb := GridContainer.new()
	vb.columns = 3
	vb.add_theme_constant_override("h_separation", 4)
	vb.add_theme_constant_override("v_separation", 3)
	outer.add_child(vb)
	for o in Defs.OVERLAYS:
		var b := _button(o.name)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size.x = 140
		var id: String = o.id
		b.pressed.connect(func(): set_overlay(id))
		vb.add_child(b)
		overlay_btns[id] = b
	overlay_btns["none"].button_pressed = true


func set_overlay(id: String) -> void:
	main.overlays.set_mode(id)
	main.transit.set_show_metro(id == "transit")
	for k in overlay_btns:
		overlay_btns[k].button_pressed = k == id


# ================================================================== budget
func _build_budget() -> void:
	var w := _window("Бюджет города", Vector2(880, 0))
	budget_panel = w[0]
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	w[1].add_child(cols)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size.x = 430
	vb.add_theme_constant_override("separation", 6)
	cols.add_child(vb)
	cols.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 400
	cols.add_child(right)
	vb.add_child(_label("Налоговые ставки", 16, Color(0.75, 0.85, 1.0)))
	for k in [["r", "Жилые зоны"], ["c", "Коммерция"], ["i", "Промышленность"], ["o", "Офисы"]]:
		var key: String = k[0]
		tax_labels[key] = _slider_row(vb, k[1], 1, 29, 1, 9, "%d%%", func(v): city.taxes[key] = int(v))
	vb.add_child(_label("Высокие налоги снижают счастье и спрос.", 12, DIM))
	vb.add_child(HSeparator.new())
	vb.add_child(_label("Бюджет служб", 16, Color(0.75, 0.85, 1.0)))
	for bc in Defs.BUDGET_CATS:
		var key: String = bc[0]
		bud_labels[key] = _slider_row(vb, bc[1], 50, 150, 5, 100, "%d%%", func(v):
			city.budget[key] = int(v)
			city._cov_dirty = true)
	var bl := _label("Больше денег — шире радиус и мощность служб, больше машин на маршрутах. Меньше — экономия, но хуже обслуживание.", 12, DIM)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size.x = 420
	vb.add_child(bl)
	vb.add_child(HSeparator.new())
	vb.add_child(_label("Кредиты (на 2 года, 15%)", 16, Color(0.75, 0.85, 1.0)))
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 6)
	for amt in [25000, 60000, 120000]:
		var a: int = amt
		lh.add_child(_button("₽" + Defs.fmt_int(a), "coin", func():
			if city.take_loan(a):
				add_notification("🏦 Получен кредит ₽%s" % Defs.fmt_int(a), "good")
			else:
				add_notification("Нельзя взять больше 3 кредитов", "bad")
			_refresh_budget(), 18))
	vb.add_child(lh)
	vb.add_child(_button("Субсидии отраслям…", "coin", func(): _toggle(subsidy_panel), 18))
	budget_box = VBoxContainer.new()
	right.add_child(budget_box)


func _slider_row(parent: Control, title: String, mn: float, mx: float, step: float, val: float, fmt: String, cb: Callable) -> Array:
	var hb := HBoxContainer.new()
	var l := _label(title, 14)
	l.custom_minimum_size.x = 200
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size.y = 22
	sl.value = val
	sl.focus_mode = Control.FOCUS_NONE
	var vl := _label(fmt % int(val), 14)
	vl.custom_minimum_size.x = 48
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.value_changed.connect(func(v):
		vl.text = fmt % int(v)
		cb.call(v))
	hb.add_child(sl)
	hb.add_child(vl)
	parent.add_child(hb)
	return [sl, vl]


func _refresh_budget() -> void:
	for k in tax_labels:
		tax_labels[k][0].set_value_no_signal(city.taxes[k])
		tax_labels[k][1].text = "%d%%" % city.taxes[k]
	for k in bud_labels:
		bud_labels[k][0].set_value_no_signal(city.budget.get(k, 100))
		bud_labels[k][1].text = "%d%%" % city.budget.get(k, 100)
	for ch in budget_box.get_children():
		ch.queue_free()
	var pr: Dictionary = city.projected
	budget_box.add_child(_label("Доходы (в месяц)", 15, GOOD))
	var inc: Dictionary = pr.get("inc", {})
	for k in inc:
		_row(budget_box, "   " + k, "₽" + Defs.fmt_int(inc[k]), GOOD)
	budget_box.add_child(_label("Расходы (в месяц)", 15, BAD))
	var exp: Dictionary = pr.get("exp", {})
	for k in exp:
		_row(budget_box, "   " + k, "₽" + Defs.fmt_int(exp[k]), BAD)
	budget_box.add_child(HSeparator.new())
	var bal: float = pr.get("income", 0.0) - pr.get("expense", 0.0)
	_row(budget_box, "Итого за месяц", ("+" if bal >= 0 else "") + "₽" + Defs.fmt_int(bal), GOOD if bal >= 0 else BAD)
	for l in city.loans:
		_row(budget_box, "   Кредит ₽%s" % Defs.fmt_int(l.amount), "₽%s/мес · ещё %d мес." % [Defs.fmt_int(l.pay), l.left], DIM)


# ================================================================== stats
func _build_stats() -> void:
	var w := _window("Статистика города", Vector2(560, 0))
	stats_panel = w[0]
	var vb: VBoxContainer = w[1]
	stats_graph = GraphWidget.new()
	stats_graph.custom_minimum_size = Vector2(520, 180)
	vb.add_child(stats_graph)
	stats_box = VBoxContainer.new()
	vb.add_child(stats_box)
	vb.add_child(_button("Достижения [J]", "trophy", func(): _toggle(ach_panel), 18))


func _refresh_stats() -> void:
	stats_graph.city = city
	stats_graph.queue_redraw()
	for ch in stats_box.get_children():
		ch.queue_free()
	var counts := {}
	for b: Building in city.buildings.values():
		var k: String = b.kind()
		counts[k] = counts.get(k, 0) + 1
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	stats_box.add_child(grid)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	left.custom_minimum_size.x = 245
	right.custom_minimum_size.x = 245
	grid.add_child(left)
	grid.add_child(right)
	_row(left, "Население", Defs.fmt_int(city.population))
	_row(left, "Трудоспособные", Defs.fmt_int(city.working_pop))
	_row(left, "Рабочие места", Defs.fmt_int(city.jobs))
	_row(left, "Безработица", "%d%%" % int(city.unemployment * 100), BAD if city.unemployment > 0.15 else GOOD)
	_row(left, "Счастье", "%d%%" % int(city.avg_happiness))
	_row(left, "Образованность", "%d%%" % int(city.edu_level * 100))
	_row(left, "Умерло за месяц", str(city.deaths_last))
	var g: Dictionary = city.goods
	_row(left, "Товары: выпуск / спрос", "%s / %s" % [Defs.fmt_int(g.prod), Defs.fmt_int(g.need)])
	_row(left, "Импорт товаров", "%d%%" % int(g.import * 100), BAD if g.import > 0.4 else TXT)
	_row(left, "Сбыт продукции", "%d%%" % int(g.sell * 100), BAD if g.sell < 0.85 else GOOD)
	_row(left, "Сырьё: добыча / нужно", "%s / %s" % [Defs.fmt_int(g.raw_prod), Defs.fmt_int(g.raw_need)])
	_row(right, "Электричество", "%d / %d МВт" % [int(city.power_demand), int(city.power_supply)], BAD if city.power_demand > city.power_supply else GOOD)
	_row(right, "Вода", "%d / %d тыс. м³" % [int(city.water_demand), int(city.water_supply)], BAD if city.water_demand > city.water_supply else GOOD)
	_row(right, "Стоки", "%d / %d тыс. м³" % [int(city.sewage_demand), int(city.sewage_supply)], BAD if city.sewage_demand > city.sewage_supply else GOOD)
	_row(right, "Жилых зданий", str(counts.get("r", 0)))
	_row(right, "Коммерческих", str(counts.get("c", 0)))
	_row(right, "Предприятий", str(counts.get("i", 0)))
	_row(right, "Служебных", str(counts.get("s", 0)))
	_row(right, "Дорог (клеток)", str(city.road_count))
	# citizens: age groups and education (bars)
	stats_box.add_child(HSeparator.new())
	var pc := HBoxContainer.new()
	pc.add_theme_constant_override("separation", 30)
	stats_box.add_child(pc)
	var ag: Array = city.people.age_groups()
	var eg: Array = city.people.edu_groups()
	pc.add_child(_bars("Возраст жителей", ["Дети", "Подростки", "Молодёжь", "Взрослые", "Пенсионеры"], ag, Color(0.45, 0.8, 0.55)))
	pc.add_child(_bars("Образование взрослых", ["Без образования", "Школа", "Колледж", "Университет"], eg, Color(0.45, 0.65, 1.0)))
	_row(stats_box, "Родилось / выпускников за месяц", "%d / %d" % [city.people.births_month, city.people.graduates_month])


func _bars(title: String, names: Array, vals: Array, col: Color) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size.x = 245
	vb.add_theme_constant_override("separation", 2)
	vb.add_child(_label(title, 14, Color(0.75, 0.85, 1.0)))
	var tot := 0
	for v in vals:
		tot += v
	for i in names.size():
		var hb := HBoxContainer.new()
		var l := _label(names[i], 12, DIM)
		l.custom_minimum_size.x = 110
		hb.add_child(l)
		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.value = 100.0 * vals[i] / max(1, tot)
		pb.custom_minimum_size = Vector2(90, 12)
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		pb.add_theme_stylebox_override("fill", fill)
		hb.add_child(pb)
		hb.add_child(_label(" %d%%" % int(pb.value), 12, TXT))
		vb.add_child(hb)
	return vb


class GraphWidget extends Control:
	var city: City
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
		var f := get_theme_default_font()
		if city == null or city.history.size() < 2:
			draw_string(f, Vector2(12, size.y * 0.5), "График появится через пару месяцев", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.75))
			return
		var h: Array = city.history
		var series := [["pop", Color(0.4, 0.85, 0.5), "Население"], ["money", Color(1.0, 0.8, 0.3), "Казна"], ["jobs", Color(0.4, 0.7, 1.0), "Рабочие места"]]
		var li := 0
		for s in series:
			var mx := 1.0
			var mn := 0.0
			for e in h:
				mx = max(mx, float(e.get(s[0], 0)))
				mn = min(mn, float(e.get(s[0], 0)))
			var pts := PackedVector2Array()
			for i in h.size():
				var v := float(h[i].get(s[0], 0))
				pts.append(Vector2(8 + (size.x - 16) * i / (h.size() - 1), size.y - 8 - (size.y - 30) * (v - mn) / (mx - mn)))
			draw_polyline(pts, s[1], 2.0, true)
			draw_string(f, Vector2(10 + li * 150, 16), "● " + s[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, s[1])
			li += 1


# ================================================================== transit lines
func _build_lines() -> void:
	var w := _window("Маршруты общественного транспорта", Vector2(480, 0))
	lines_panel = w[0]
	lines_box = VBoxContainer.new()
	lines_box.add_theme_constant_override("separation", 6)
	w[1].add_child(lines_box)


func _refresh_lines() -> void:
	for ch in lines_box.get_children():
		ch.queue_free()
	if city.lines.is_empty():
		var l := _label("Маршрутов пока нет. Постройте автобусный парк и проложите маршрут, или соедините станции метро.", 13, DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 440
		lines_box.add_child(l)
	for ln in city.lines:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		var sw := ColorRect.new()
		sw.color = ln.color
		sw.custom_minimum_size = Vector2(16, 16)
		hb.add_child(sw)
		var name := _label(ln.name, 15)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name)
		hb.add_child(_label("остановок %d · %s %d · пасс. %s/день" % [ln.stops.size(), {"bus": "автобусов", "tram": "вагонов", "metro": "поездов"}[ln.kind], city.line_vehicles(ln), Defs.fmt_int(ln.riders)], 13, DIM))
		var id: int = ln.id
		hb.add_child(_button("", "close", func(): city.remove_line(id); _refresh_lines(), 12))
		lines_box.add_child(hb)
	lines_box.add_child(HSeparator.new())
	_row(lines_box, "Пассажиров в день", Defs.fmt_int(city.transit_riders))
	_row(lines_box, "Доля поездок на транспорте", "%d%%" % int(city.transit_share * 100))


# ================================================================== policies
# ================================================================== subsidies
func _build_subsidies() -> void:
	var w := _window("Субсидии", Vector2(560, 0))
	subsidy_panel = w[0]
	subsidy_box = VBoxContainer.new()
	subsidy_box.add_theme_constant_override("separation", 6)
	w[1].add_child(subsidy_box)


func _refresh_subsidies() -> void:
	for ch in subsidy_box.get_children():
		ch.queue_free()
	var intro := _label("Город доплачивает отраслям из бюджета (как в SimCity). Стоимость — доля от налогов этой отрасли в месяц.", 12, DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 530
	subsidy_box.add_child(intro)
	for sid in Defs.SUBSIDIES:
		var sd: Dictionary = Defs.SUBSIDIES[sid]
		var row := HBoxContainer.new()
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(_label(sd.name, 14))
		tv.add_child(_label("%s · %d%% налогов отрасли за уровень" % [sd.desc, int(sd.pct * 100)], 11, DIM))
		row.add_child(tv)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		for k in Defs.SUBSIDY_LEVELS.size():
			ob.add_item(Defs.SUBSIDY_LEVELS[k], k)
		ob.select(city.subsidy(sid))
		var s_id: String = sid
		ob.item_selected.connect(func(ix):
			city.subsidies[s_id] = ix
			Sfx.play("toggle", -6.0)
			_refresh_subsidies.call_deferred())
		row.add_child(ob)
		subsidy_box.add_child(row)
	var e: Dictionary = city._upkeep_month()
	_row(subsidy_box, "Субсидии стоят в месяц", "₽" + Defs.fmt_int(e.get("Субсидии", 0.0)), TXT)


# ================================================================== government (city hall, ministries)
func _build_gov() -> void:
	var w := _window("Правительство: ратуша и министерства", Vector2(600, 0))
	gov_panel = w[0]
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(580, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gov_panel.set_meta("scroll", sc)
	w[1].add_child(sc)
	gov_box = VBoxContainer.new()
	gov_box.add_theme_constant_override("separation", 6)
	gov_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(gov_box)


func _pick_service(sid: String) -> void:
	var cat: String = Defs.SERVICES[sid].cat
	if cur_cat != cat:
		_select_category(cat)
	tools.set_tool({"type": "service", "id": sid})


func _refresh_gov() -> void:
	for ch in gov_box.get_children():
		ch.queue_free()
	var h: Building = city.hall()
	if h == null:
		var t := _label("Ратуши пока нет. Министерства пристраиваются к ней, поэтому сначала постройте ратушу (категория «Уникальные», ₽8 000). Её можно улучшить до Мэрии (2 500 жителей) и Капитолия (12 000).", 14)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 550
		gov_box.add_child(t)
		gov_box.add_child(_button("Построить ратушу", "landmark", func(): _pick_service("cityhall"); gov_panel.visible = false, 22))
		return
	var lv := clampi(h.level, 1, 3)
	_row(gov_box, "Здание", "%s (уровень %d из 3)" % [Defs.HALL_LEVELS[lv - 1].name, lv], Color(1, 0.85, 0.5))
	if lv < 3:
		var nx: Dictionary = Defs.HALL_LEVELS[lv]
		var us := city.upgrade_hall_state()
		var ub := _button("Улучшить до «%s» — ₽%s (мест для министерств: %d)" % [nx.name, Defs.fmt_int(nx.cost), nx.slots], "landmark", func():
			if city.upgrade_hall():
				Sfx.play("milestone", -8.0)
			_refresh_gov(), 18)
		ub.disabled = not us.ok
		gov_box.add_child(ub)
		if not us.ok:
			gov_box.add_child(_label("Пока нельзя: " + us.reason, 12, DIM))
	var free := city.hall_slots() - h.ministries.size()
	gov_box.add_child(_label("Министерства: %d из %d мест" % [h.ministries.size(), city.hall_slots()], 16, Color(0.75, 0.85, 1.0)))
	if free <= 0 and lv < 3:
		gov_box.add_child(_label("Все места заняты — улучшите ратушу, чтобы открыть новые.", 12, Color(1, 0.8, 0.4)))
	for mid in Defs.MINISTRIES:
		var md: Dictionary = Defs.MINISTRIES[mid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var sw := ColorRect.new()
		sw.color = md.color
		sw.custom_minimum_size = Vector2(8, 40)
		row.add_child(sw)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var built: bool = mid in h.ministries
		tv.add_child(_label(md.name, 14, GOOD if built else TXT))
		var dl := _label("%s Содержание ₽%s/мес." % [md.desc, Defs.fmt_int(md.upkeep)], 11, DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size.x = 380
		tv.add_child(dl)
		row.add_child(tv)
		if built:
			row.add_child(_label("✓ открыто", 13, GOOD))
		else:
			var m_id: String = mid
			var mb := _button("Открыть ₽%s" % Defs.fmt_int(md.cost), "", func():
				if city.build_ministry(m_id):
					Sfx.play("place", -6.0)
				_refresh_gov(), 0)
			mb.custom_minimum_size.x = 120
			mb.disabled = free <= 0 or city.money < md.cost
			mb.tooltip_text = "Нет свободных мест — улучшите ратушу" if free <= 0 else ("Недостаточно денег" if city.money < md.cost else "Пристроить крыло к ратуше")
			row.add_child(mb)
		gov_box.add_child(row)
	gov_box.add_child(HSeparator.new())
	var sb := _button("Субсидии отраслям", "budget", func(): _toggle(subsidy_panel), 18)
	gov_box.add_child(sb)


# ================================================================== УГК — space program (like the DSA in TheoTown)
const SPACE_TABS := [["overview", "Обзор"], ["research", "Исследования"], ["missions", "Миссии"], ["moon", "Луна"], ["mars", "Марс"], ["log", "Журнал"]]
const MISSION_GROUPS := [["Испытания и орбита", ["test", "weather", "comsat", "gps", "telescope", "solarsat", "shield"]],
	["Пилотируемая программа", ["crew", "module"]],
	["Лунная программа (4 миссии)", ["lunar_probe", "lunar_orbit", "moon", "moonbase"]],
	["Марс", ["mars_probe", "mars", "colony"]]]
const UGK_BUILDINGS := ["dsa_hq", "launchpad", "rocket_factory", "astro_center", "mission_control", "observatory", "rectenna", "space_museum", "he3_plant", "spaceport"]


func _build_space() -> void:
	var w := _window("УГК — Управление городской космонавтики", Vector2(820, 0))
	space_panel = w[0]
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	w[1].add_child(tabs)
	for t in SPACE_TABS:
		var tid: String = t[0]
		var b := _button(t[1], "", func(): space_tab = tid; colony_pick = ""; _refresh_space())
		b.toggle_mode = true
		b.set_meta("tab", tid)
		tabs.add_child(b)
	space_panel.set_meta("tabs", tabs)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(800, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	space_panel.set_meta("scroll", sc)
	w[1].add_child(sc)
	space_box = VBoxContainer.new()
	space_box.add_theme_constant_override("separation", 5)
	space_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(space_box)
	_build_colony_view()


func _h(t: String) -> void:
	space_box.add_child(_label(t, 16, Color(0.75, 0.85, 1.0)))


func _wrap(t: String, size: int = 13, col: Color = TXT, wdt: float = 760) -> Label:
	var l := _label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = wdt
	return l


func _bar(v: float, wdt: float = 200, col: Color = Color(0.3, 0.6, 1.0)) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.value = clampf(v, 0.0, 1.0) * 100.0
	pb.custom_minimum_size = Vector2(wdt, 16)
	pb.show_percentage = false
	pb.add_theme_stylebox_override("fill", _sb(col, 4, 0))
	return pb


func _refresh_space() -> void:
	if colony_view.get_parent():
		colony_view.get_parent().remove_child(colony_view)
	for ch in space_box.get_children():
		ch.queue_free()
	for b in (space_panel.get_meta("tabs") as HBoxContainer).get_children():
		b.button_pressed = b.get_meta("tab") == space_tab
	match space_tab:
		"research": _space_research()
		"missions": _space_missions()
		"moon", "mars": _space_colony(space_tab)
		"log": _space_log()
		_: _space_overview()


func _space_overview() -> void:
	var sp: Space = city.space
	# progress strip: tests -> orbit -> crew -> station -> Moon -> colony -> Mars
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 12)
	for st in [["🧪 Испытания", sp.has("test")], ["🛰 Орбита", sp.has("weather") or sp.has("comsat")], ["👨‍🚀 Космонавты", sp.has("crew")], ["🏗 Станция", sp.station_ready()],
			["🌕 Луна", sp.has("moon")], ["🏠 Лунная колония", sp.colony_open("moon")], ["🔴 Марс", sp.has("mars")], ["🏙 Колония на Марсе", sp.colony_open("mars")]]:
		strip.add_child(_label(st[0], 14, GOOD if st[1] else DIM))
	space_box.add_child(strip)
	space_box.add_child(HSeparator.new())
	if not sp.has_agency(city):
		_h("С чего начать")
		var steps := [
			["1. Постройте штаб УГК (от %s жителей; с Министерством науки — раньше)." % Defs.fmt_int(city.service_unlock("dsa_hq")), "dsa_hq"],
			["2. Стартовый стол — сюда грузовики везут снабжение с заводов.", "launchpad"],
			["3. Ракетный завод рядом с промышленностью — главный источник снабжения.", "rocket_factory"],
			["4. Центр подготовки космонавтов — для пилотируемых полётов.", "astro_center"],
			["5. ЦУП и обсерватория повышают надёжность и дают очки исследований.", "mission_control"],
		]
		for s in steps:
			var row := HBoxContainer.new()
			var l := _wrap(s[0], 14, TXT, 560)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var sid: String = s[1]
			var b := _button("Построить", SERVICE_ICONS.get(sid, "space"), func(): _pick_service(sid); space_panel.visible = false, 18)
			b.disabled = not city.is_unlocked(city.service_unlock(sid))
			row.add_child(b)
			space_box.add_child(row)
		space_box.add_child(_wrap("Дальше — как в DSA из TheoTown: испытательные пуски, спутники, космонавты, орбитальная станция, четыре миссии лунной программы, колония на Луне с добычей гелия-3 и полёт на Марс.", 12, DIM))
		return
	_h("Ресурсы программы")
	var cap := sp.supply_cap(city)
	var row1 := HBoxContainer.new()
	var l1 := _label("Снабжение: %s / %s  (+%d в день)" % [Defs.fmt_int(sp.supplies), Defs.fmt_int(cap), int(sp.supply_rate(city))], 14)
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(l1)
	row1.add_child(_bar(sp.supplies / maxf(cap, 1.0), 260, Color(0.95, 0.65, 0.2)))
	space_box.add_child(row1)
	if cap <= 0.0:
		space_box.add_child(_label("Нет стартового стола — снабжение некуда везти.", 12, BAD))
	elif sp.supply_rate(city) < 30.0:
		space_box.add_child(_label("Мало снабжения: постройте ракетный завод и промышленность рядом со стартовым столом.", 12, Color(1, 0.8, 0.4)))
	var ccap := sp.crew_capacity(city)
	var row2 := HBoxContainer.new()
	var l2 := _label("Космонавты: готовы %d, в полёте %d, мест %d%s" % [sp.astronauts, sp.crew_flying(), ccap, ("  · погибло %d" % sp.lost) if sp.lost > 0 else ""], 14)
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(l2)
	if ccap > 0 and sp.astronauts + sp.crew_flying() < ccap:
		row2.add_child(_label("подготовка", 11, DIM))
		row2.add_child(_bar(sp.train / Space.TRAIN_DAYS, 140, Color(0.4, 0.8, 0.5)))
	space_box.add_child(row2)
	if ccap == 0:
		space_box.add_child(_label("Нет центра подготовки космонавтов: пилотируемые миссии недоступны.", 12, DIM))
	_row(space_box, "Очки исследований", "+%d в месяц" % int(sp.rp_month(city)))
	_row(space_box, "Надёжность ракет", "+%d%% за испытания (%d/3), стартовых столов: %d" % [sp.tests_ok() * 5, sp.tests_ok(), sp.pads(city).size()])
	if sp.he3 > 0.0 or sp.colony_open("moon"):
		_row(space_box, "Гелий-3 на складе", "%d т" % int(sp.he3), TXT)
	if sp.income() > 0.0:
		_row(space_box, "Доход колоний", "₽%s/мес" % Defs.fmt_int(sp.income()), GOOD)
	if sp.target != "":
		var rr := HBoxContainer.new()
		var rl := _label("Исследуется: %s" % Defs.RESEARCH[sp.target].name, 14)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(rl)
		rr.add_child(_bar(sp.progress / maxf(Defs.RESEARCH[sp.target].rp, 1.0), 260))
		space_box.add_child(rr)
	else:
		space_box.add_child(_label("Исследование не выбрано — откройте вкладку «Исследования».", 12, Color(1, 0.8, 0.4)))
	if sp.active.size() > 0:
		_h("В полёте")
		for a in sp.active:
			var fr := HBoxContainer.new()
			var fl := _label("🚀 %s%s — ещё %d дн." % [Defs.MISSIONS[a.id].name, (" (экипаж %d)" % a.crew) if a.crew > 0 else "", a.left], 13)
			fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fr.add_child(fl)
			fr.add_child(_bar(1.0 - float(a.left) / maxf(a.days, 1), 220, Color(0.6, 0.5, 1.0)))
			space_box.add_child(fr)
	var orb := sp.orbiters()
	if orb.size() > 0:
		var names := {"weather": "метеоспутник", "gps": "навигация", "telescope": "телескоп", "solarsat": "орбитальная электростанция", "shield": "щит SDI", "comsat": "спутник связи", "station": "станция (%d/3 модулей)" % sp.done.get("module", 0)}
		var arr: Array = []
		for o in orb:
			arr.append(names[o])
		_row(space_box, "На орбите", ", ".join(arr))
	_h("Здания УГК")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	for sid in UGK_BUILDINGS:
		var s: Dictionary = Defs.SERVICES[sid]
		var n: int = city._count_building(sid)
		var cell := HBoxContainer.new()
		cell.custom_minimum_size.x = 385
		var lb := _label("%s: %d%s" % [s.name, n, (" / %d" % int(s.max)) if s.has("max") else (" / 1" if s.get("unique", false) else "")], 13, GOOD if n > 0 else TXT)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(lb)
		var lock := sp.unlock_reason(sid)
		var s_id: String = sid
		var bb := _button("+", SERVICE_ICONS.get(sid, "space"), func(): _pick_service(s_id); space_panel.visible = false, 16)
		var full: bool = (s.has("max") and n >= int(s.max)) or (s.get("unique", false) and n > 0)
		bb.disabled = full or lock != "" or not city.is_unlocked(city.service_unlock(sid))
		bb.tooltip_text = lock if lock != "" else s.desc
		cell.add_child(bb)
		grid.add_child(cell)
	space_box.add_child(grid)


func _space_research() -> void:
	var sp: Space = city.space
	_row(space_box, "Очки исследований", "+%d в месяц" % int(sp.rp_month(city)))
	if not sp.has_agency(city):
		space_box.add_child(_label("Исследования ведёт штаб УГК — постройте его.", 13, BAD))
	for rid in Defs.RESEARCH:
		var rd: Dictionary = Defs.RESEARCH[rid]
		var row := HBoxContainer.new()
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ok: bool = sp.researched.has(rid)
		tv.add_child(_label(rd.name + ("  ✓" if ok else ""), 14, GOOD if ok else TXT))
		var need := ""
		if not ok and not sp.can_research(rid):
			var parts: Array = []
			for k in ["need", "need2"]:
				if rd.has(k) and not sp.researched.has(rd[k]):
					parts.append("«%s»" % Defs.RESEARCH[rd[k]].name)
			need = "  · сначала " + ", ".join(parts)
		tv.add_child(_wrap(rd.desc + ("" if ok else "  (%d очков)" % rd.rp) + need, 11, DIM, 560))
		row.add_child(tv)
		if sp.target == rid:
			row.add_child(_bar(sp.progress / maxf(rd.rp, 1.0), 160))
		elif sp.can_research(rid):
			var r_id: String = rid
			row.add_child(_button("Изучать", "edu", func(): sp.target = r_id; sp.progress = 0.0; _refresh_space(), 18))
		space_box.add_child(row)


func _space_missions() -> void:
	var sp: Space = city.space
	_row(space_box, "Снабжение / космонавты", "%s ед. · %d готовы" % [Defs.fmt_int(sp.supplies), sp.astronauts])
	for g in MISSION_GROUPS:
		_h(g[0])
		for mid in g[1]:
			var md: Dictionary = Defs.MISSIONS[mid]
			var row := HBoxContainer.new()
			var tv := VBoxContainer.new()
			tv.add_theme_constant_override("separation", -2)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cnt: int = sp.done.get(mid, 0)
			tv.add_child(_label(md.name + (" ×%d" % cnt if cnt > 0 else ""), 14, GOOD if cnt > 0 else TXT))
			var req := "₽%s · снабжение %s · %d дн.%s · успех %d%%" % [Defs.fmt_int(sp.cost(mid)), Defs.fmt_int(sp.supplies_need(mid)), md.days,
				(" · экипаж %d" % md.crew) if md.has("crew") else "", int(sp.chance(city, mid) * 100)]
			tv.add_child(_wrap(md.desc, 11, DIM, 560))
			tv.add_child(_label(req, 11, Color(0.75, 0.8, 0.9)))
			row.add_child(tv)
			var st := sp.mission_state(city, mid)
			if st == "":
				var m_id: String = mid
				row.add_child(_button("Запуск", "space", func():
					if sp.launch(city, m_id):
						Sfx.play("milestone", -8.0)
					_refresh_space(), 18))
			else:
				var sl := _wrap(st, 11, GOOD if st.begins_with("Выполнено") else DIM, 170)
				row.add_child(sl)
			space_box.add_child(row)


func _space_log() -> void:
	var sp: Space = city.space
	_h("Журнал полётов")
	if sp.log.is_empty():
		space_box.add_child(_label("Пока пусто.", 13, DIM))
	for e in sp.log:
		space_box.add_child(_label("• " + e, 12, DIM))
	_h("Статистика")
	var ok := 0
	var bad := 0
	for k in sp.done: ok += int(sp.done[k])
	for k in sp.fails: bad += int(sp.fails[k])
	_row(space_box, "Успешных запусков", str(ok), GOOD)
	_row(space_box, "Аварий", str(bad), BAD if bad > 0 else TXT)
	if sp.lost > 0:
		_row(space_box, "Погибших космонавтов", str(sp.lost), BAD)
		space_box.add_child(_label("Вечная память героям космоса.", 12, DIM))
	for cid in sp.colonies:
		_row(space_box, "Вывезено с колонии «%s»" % Defs.COLONIES[cid].name, "%d т" % int(sp.exported(cid)))


# ---------------------------------------------------------------- colonies: tile map + small 3D view
func _space_colony(cid: String) -> void:
	var sp: Space = city.space
	var cd: Dictionary = Defs.COLONIES[cid]
	if not sp.colony_open(cid):
		var m: Dictionary = Defs.MISSIONS[cd.mission]
		space_box.add_child(_wrap("Колонии «%s» пока нет. Её основывает миссия «%s» — как в TheoTown, Луна открывается после всей лунной программы:" % [cd.name, m.name], 14))
		var chain: Array = ["lunar_probe", "lunar_orbit", "moon", "moonbase"] if cid == "moon" else ["mars_probe", "mars", "colony"]
		for mid in chain:
			space_box.add_child(_label(("✓ " if sp.has(mid) else "○ ") + Defs.MISSIONS[mid].name, 14, GOOD if sp.has(mid) else DIM))
		space_box.add_child(_wrap("На колонии: жилые модули, солнечные фермы, добывающие станции на месторождениях, ледяные шахты, лаборатории и космопорт, который отправляет добычу на Землю.", 12, DIM))
		return
	var st := sp.colony_stats(cid)
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 16)
	top.add_child(_label("👥 %d колонистов" % st.pop, 14))
	top.add_child(_label("⚡ %d / %d" % [int(st.power_prod), int(st.power_use)], 14, GOOD if st.power_prod >= st.power_use else BAD))
	top.add_child(_label("💧 модулей с водой %d/%d" % [st.habs_ok, st.habs], 14, GOOD if st.habs_ok >= st.habs else BAD))
	top.add_child(_label("👷 рабочих %d/%d" % [mini(st.pop, st.workers), st.workers], 14, GOOD if st.pop >= st.workers else Color(1, 0.8, 0.4)))
	top.add_child(_label("⛏ %d т %s/мес" % [int(st.prod), cd.res], 14))
	top.add_child(_label("₽%s/мес" % Defs.fmt_int(st.income) if st.income > 0.0 else "нет космопорта — добыча копится (%d т)" % int(sp.colonies[cid].get("stock", 0.0)), 14, GOOD if st.income > 0.0 else Color(1, 0.8, 0.4)))
	space_box.add_child(top)
	# build palette
	var pal := HFlowContainer.new()
	pal.add_theme_constant_override("h_separation", 4)
	for bid in Defs.COLONY_BUILD:
		var bd: Dictionary = Defs.COLONY_BUILD[bid]
		var b_id: String = bid
		var b := _button("%s ₽%s" % [bd.name, Defs.fmt_int(bd.cost / 1000.0) + "к"], bd.icon, func(): colony_pick = "" if colony_pick == b_id else b_id; _refresh_space(), 16)
		b.toggle_mode = true
		b.button_pressed = colony_pick == bid
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = bd.desc
		pal.add_child(b)
	var db := _button("Снести", "bulldoze", func(): colony_pick = "" if colony_pick == "demolish" else "demolish"; _refresh_space(), 16)
	db.toggle_mode = true
	db.button_pressed = colony_pick == "demolish"
	db.add_theme_font_size_override("font_size", 12)
	pal.add_child(db)
	space_box.add_child(pal)
	space_box.add_child(_label(Defs.COLONY_BUILD[colony_pick].desc if Defs.COLONY_BUILD.has(colony_pick) else ("Кликните по зданию, чтобы снести его." if colony_pick == "demolish" else "Выберите здание и кликните по клетке карты."), 12, DIM))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = Defs.COLONY_SIZE.x
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	var col: Dictionary = sp.colonies[cid]
	var tnames := ["грунт", "кратер", "месторождение (%s)" % cd.res, "лёд"]
	for i in col.tiles.size():
		var t: int = col.tiles[i]
		var bid: String = col.build[i]
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(34, 34)
		cell.focus_mode = Control.FOCUS_NONE
		var c: Color = [cd.ground, cd.crater, cd.ore, cd.ice][t]
		for stn in ["normal", "hover", "pressed", "disabled"]:
			cell.add_theme_stylebox_override(stn, _sb(c.lightened(0.15) if stn == "hover" else c, 3, 0, Color(0, 0, 0, 0.3)))
		if bid != "":
			cell.icon = Icons.get_tex(Defs.COLONY_BUILD[bid].icon, 64)
			cell.expand_icon = true
		var tip: String = tnames[t] + ((" · " + Defs.COLONY_BUILD[bid].name) if bid != "" else "")
		if Defs.COLONY_BUILD.has(colony_pick):
			var why := sp.build_state(city, cid, i, colony_pick)
			if why != "":
				tip += "\n" + why
		cell.tooltip_text = tip
		var idx: int = i
		cell.pressed.connect(func():
			if colony_pick == "demolish":
				if sp.colony_demolish(cid, idx):
					Sfx.play("bulldoze", -8.0)
			elif colony_pick != "":
				if sp.colony_build(city, cid, idx, colony_pick):
					Sfx.play("place", -6.0)
				else:
					add_notification(sp.build_state(city, cid, idx, colony_pick), "bad")
			_refresh_space())
		grid.add_child(cell)
	hb.add_child(grid)
	hb.add_child(colony_view)
	space_box.add_child(hb)
	_update_colony_view(cid)


func _build_colony_view() -> void:
	colony_view = SubViewportContainer.new()
	colony_view.custom_minimum_size = Vector2(280, 320)
	colony_view.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(280, 320)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	colony_view.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 6.5, 8.0)
	cam.fov = 48
	pivot.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO)
	var scene := Node3D.new()
	vp.add_child(scene)
	colony_view.set_meta("env", env.environment)
	colony_view.set_meta("pivot", pivot)
	colony_view.set_meta("scene", scene)


func _update_colony_view(cid: String) -> void:
	var key := "%s_%d" % [cid, city.space.version]
	if colony_view.get_meta("key", "") == key:
		return
	colony_view.set_meta("key", key)
	var cd: Dictionary = Defs.COLONIES[cid]
	(colony_view.get_meta("env") as Environment).background_color = Color(0.01, 0.01, 0.03) if cid == "moon" else Color(0.62, 0.42, 0.3)
	var scene: Node3D = colony_view.get_meta("scene")
	for ch in scene.get_children():
		ch.queue_free()
	var col: Dictionary = city.space.colonies[cid]
	var sz := Defs.COLONY_SIZE
	var off := Vector3(-sz.x * 0.5 + 0.5, 0, -sz.y * 0.5 + 0.5)
	Models.plane(Vector2(sz.x + 4, sz.y + 4), cd.ground, Vector3.ZERO, scene)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cid)
	for i in col.tiles.size():
		var p := Vector3(i % sz.x, 0, i / sz.x) + off
		var t: int = col.tiles[i]
		if t == 1:
			Models.cylinder(0.45, 0.03, cd.crater, p, scene, 14)
			Models.cylinder(0.5, 0.06, cd.ground.darkened(0.1), p + Vector3(0, -0.04, 0), scene, 14)
		elif t >= 2 and col.build[i] == "":
			for k in 3:
				var r := Models.box(Vector3(0.26, 0.32, 0.26), cd.ore if t == 2 else cd.ice, p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)), scene)
				r.rotation = Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)
				r.material_override = Models.mat(cd.ore if t == 2 else cd.ice, 0.3, 0.6)
		var bid: String = col.build[i]
		if bid != "":
			var m := Models.fit(Defs.COLONY_BUILD[bid].model, Vector2(0.95, 0.95), 0, 5.0)
			var mh: float = m.get_meta("height")
			if mh > 1.6:
				m.scale = Vector3.ONE * (1.6 / mh)
			m.position = p
			scene.add_child(m)
	# a rover on patrol and the Earth (or Phobos) in the sky
	var rover := Models.fit("poly/curiosity", Vector2(0.6, 0.6), 0, 5.0)
	rover.position = Vector3(sz.x * 0.5 + 0.8, 0, 0)
	scene.add_child(rover)
	colony_view.set_meta("rover", rover)
	var planet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.6 if cid == "moon" else 0.6
	sm.height = sm.radius * 2.0
	planet.mesh = sm
	planet.material_override = Models.mat(Color(0.25, 0.5, 0.95) if cid == "moon" else Color(0.55, 0.5, 0.45), 0.6, 0.6 if cid == "moon" else 0.0)
	planet.position = Vector3(-5, 5, -9)
	scene.add_child(planet)


func _animate_colony_view(delta: float) -> void:
	if colony_view == null or not colony_view.is_visible_in_tree():
		return
	var pv: Node3D = colony_view.get_meta("pivot")
	pv.rotation.y += delta * 0.12
	var rv = colony_view.get_meta("rover", null)
	if rv != null and is_instance_valid(rv):
		var a: float = Time.get_ticks_msec() * 0.0002
		rv.position = Vector3(cos(a) * (Defs.COLONY_SIZE.x * 0.5 + 0.9), 0, sin(a) * (Defs.COLONY_SIZE.y * 0.5 + 0.9))
		rv.rotation.y = -a


# ================================================================== achievements
func _build_achievements() -> void:
	var w := _window("Достижения", Vector2(640, 0))
	ach_panel = w[0]
	ach_box = GridContainer.new()
	ach_box.columns = 2
	ach_box.add_theme_constant_override("h_separation", 12)
	w[1].add_child(ach_box)


func _refresh_achievements() -> void:
	for ch in ach_box.get_children():
		ch.queue_free()
	for id in Achievements.LIST:
		var a: Dictionary = Achievements.LIST[id]
		var got: bool = city.achievements.has(id)
		var row := HBoxContainer.new()
		row.custom_minimum_size.x = 300
		row.modulate = Color(1, 1, 1, 1.0 if got else 0.45)
		row.add_child(_icon(a.icon, 26))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -3)
		tv.add_child(_label(("🏆 " if got else "") + a.name, 14, Color(1, 0.85, 0.4) if got else TXT))
		tv.add_child(_label(a.desc, 11, DIM))
		row.add_child(tv)
		ach_box.add_child(row)


# ================================================================== region
func _build_region() -> void:
	var w := _window("Регион", Vector2(620, 0))
	region_panel = w[0]
	region_box = VBoxContainer.new()
	region_box.add_theme_constant_override("separation", 6)
	w[1].add_child(region_box)


func _refresh_region() -> void:
	for ch in region_box.get_children():
		ch.queue_free()
	var rg: Region = city.region
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	region_box.add_child(cards)
	for nb in rg.neighbors:
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.05)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
		pc.add_theme_stylebox_override("panel", sb)
		pc.custom_minimum_size.x = 190
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		pc.add_child(vb)
		vb.add_child(_label(nb.name, 16))
		vb.add_child(_label("%s · %s" % [Region.SPECS[nb.spec].name, nb.dir], 11, DIM))
		vb.add_child(_label("👥 %s жителей" % Defs.fmt_int(nb.pop), 13))
		var mood: float = nb.mood
		vb.add_child(_label(("😊 Дружелюбны" if mood > 65 else ("😐 Нейтральны" if mood > 40 else "😠 Недовольны")) + " (%d)" % int(mood), 12, GOOD if mood > 65 else (TXT if mood > 40 else BAD)))
		cards.add_child(pc)
	region_box.add_child(_label("Сделки с соседями", 15, Color(0.75, 0.85, 1.0)))
	var u: Dictionary = rg.used
	var amounts := {"sell_power": "сейчас продаётся %d МВт" % int(u.power_out), "buy_power": "сейчас покупается %d МВт" % int(u.power_in),
		"sell_water": "сейчас продаётся %d тыс. м³" % int(u.water_out), "buy_water": "сейчас покупается %d тыс. м³" % int(u.water_in),
		"garbage": "≈%d т в месяц" % int(u.garbage), "workers": "приезжает %d человек" % int(u.workers)}
	for d in Region.DEALS:
		var row := HBoxContainer.new()
		var txt := VBoxContainer.new()
		txt.add_theme_constant_override("separation", -2)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_child(_label(Region.DEALS[d].name, 14))
		var dl := _label(rg.deal_desc(d) + ("  —  " + amounts[d] if rg.deals.get(d, false) else ""), 11, DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size.x = 500
		txt.add_child(dl)
		row.add_child(txt)
		var cb := CheckButton.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = rg.deals.get(d, false)
		var did: String = d
		cb.toggled.connect(func(on):
			rg.deals[did] = on
			Sfx.play("toggle", -6.0)
			city._compute_utilities()
			_refresh_region.call_deferred())
		row.add_child(cb)
		region_box.add_child(row)
	var mm := rg.monthly_money()
	_row(region_box, "Доход от соседей / расходы", "+₽%s / −₽%s в месяц" % [Defs.fmt_int(mm.x), Defs.fmt_int(mm.y)], GOOD if mm.x >= mm.y else BAD)
	if rg.news.size() > 0:
		region_box.add_child(HSeparator.new())
		region_box.add_child(_label("Новости региона", 14, Color(0.75, 0.85, 1.0)))
		for nw in rg.news:
			var l := _label("• " + nw, 12, DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 580
			region_box.add_child(l)


# ================================================================== land plots
func _build_land() -> void:
	var w := _window("Участки земли", Vector2(640, 0))
	land_panel = w[0]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	w[1].add_child(hb)
	land_grid = GridContainer.new()
	land_grid.columns = City.LAND_N
	land_grid.add_theme_constant_override("h_separation", 3)
	land_grid.add_theme_constant_override("v_separation", 3)
	hb.add_child(land_grid)
	land_info_box = VBoxContainer.new()
	land_info_box.custom_minimum_size.x = 230
	hb.add_child(land_info_box)
	land_panel.visibility_changed.connect(func():
		if main and main.overlays:
			main.overlays.set_land_view(land_panel.visible))


func _refresh_land() -> void:
	for ch in land_grid.get_children():
		ch.queue_free()
	for t in City.LAND_N * City.LAND_N:
		var b := Button.new()
		b.custom_minimum_size = Vector2(68, 60)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		var cb := city.can_buy_land(t)
		var info := city.land_info(t)
		var has_road := t == city.land_of(city.outside.x, city.outside.y)
		if city.owned[t] == 1:
			sb.bg_color = Color(0.25, 0.55, 0.3)
			b.text = "Ваш" + ("\n🛣 въезд" if has_road else "")
		elif cb.ok or cb.reason == "Недостаточно денег":
			sb.bg_color = Color(0.55, 0.45, 0.15)
			b.text = "₽%s" % Defs.fmt_int(city.land_price(t))
		else:
			sb.bg_color = Color(0.18, 0.2, 0.24)
			b.text = "🔒"
		if info.water > 25:
			b.text += "\n💧"
		if t == land_sel:
			sb.border_color = Color(1, 1, 1)
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		var tt := t
		b.pressed.connect(func():
			land_sel = tt
			main.rig.set_focus(Vector3((tt % City.LAND_N + 0.5) * City.LAND, 0, (tt / City.LAND_N + 0.5) * City.LAND), 45.0)
			_refresh_land())
		land_grid.add_child(b)
	for ch in land_info_box.get_children():
		ch.queue_free()
	land_info_box.add_child(_label("Ваших участков: %d из %d возможных" % [city.owned_count(), city.land_limit()], 13, DIM))
	if land_sel < 0:
		var tip := _label("Выберите участок на схеме (север сверху). Новые участки открываются по мере роста города.", 13, DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		land_info_box.add_child(tip)
		return
	var inf := city.land_info(land_sel)
	land_info_box.add_child(_label("Участок %d-%d" % [land_sel % City.LAND_N + 1, land_sel / City.LAND_N + 1], 16))
	for k in [["water", "Вода"], ["forest", "Лес"], ["fertile", "Плодородная земля"], ["ore", "Руда"], ["oil", "Нефть"], ["hills", "Холмы и склоны"]]:
		_row(land_info_box, k[1], "%d%%" % inf[k[0]], DIM if inf[k[0]] == 0 else TXT)
	if city.owned[land_sel] == 1:
		land_info_box.add_child(_label("Участок принадлежит городу.", 13, GOOD))
	else:
		var cb := city.can_buy_land(land_sel)
		var sel := land_sel
		var buy := _button("Купить за ₽%s" % Defs.fmt_int(city.land_price(land_sel)), "land", func():
			if city.buy_land(sel):
				Sfx.play("milestone", -8.0)
				add_notification("🗺 Новый участок куплен! Можно строить дальше.", "good")
			_refresh_land(), 20)
		buy.disabled = not cb.ok
		land_info_box.add_child(buy)
		if not cb.ok:
			var r := _label(cb.reason, 12, BAD)
			r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			land_info_box.add_child(r)


func _build_policies() -> void:
	var w := _window("Законы и постановления", Vector2(520, 0))
	policy_panel = w[0]
	var vb: VBoxContainer = w[1]
	var hb := HBoxContainer.new()
	var l := _label("Действуют для:", 14, DIM)
	hb.add_child(l)
	policy_target = OptionButton.new()
	policy_target.focus_mode = Control.FOCUS_NONE
	policy_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	policy_target.item_selected.connect(func(_i): _refresh_policies())
	hb.add_child(policy_target)
	vb.add_child(hb)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 500)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	policy_panel.set_meta("scroll", sc)
	vb.add_child(sc)
	policy_box = VBoxContainer.new()
	policy_box.add_theme_constant_override("separation", 4)
	policy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(policy_box)


func _refresh_policies() -> void:
	var sel := policy_target.get_selected_id() if policy_target.item_count > 0 else 0
	policy_target.clear()
	policy_target.add_item("Весь город", 0)
	for d in city.districts:
		policy_target.add_item("Район «%s»" % city.districts[d].name, d)
	var idx := policy_target.get_item_index(sel)
	policy_target.select(idx if idx >= 0 else 0)
	var target := policy_target.get_selected_id()
	for ch in policy_box.get_children():
		ch.queue_free()
	var active: Array = city.city_policies if target == 0 else city.districts[target].policies
	if target == 0:
		var ad := CheckButton.new()
		ad.text = "Автоснос заброшенных зданий"
		ad.tooltip_text = "Заброшенные дома сносятся через пару дней, освобождая место для новых."
		ad.focus_mode = Control.FOCUS_NONE
		ad.button_pressed = city.auto_demolish
		ad.toggled.connect(func(on): city.auto_demolish = on; Sfx.play("toggle", -6.0))
		policy_box.add_child(ad)
	else:
		var sr := HBoxContainer.new()
		sr.add_theme_constant_override("separation", 10)
		sr.add_child(_icon("spec", 26))
		var sl := _label("Специализация промышленности", 15)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sr.add_child(sl)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.add_item("Обычная", 0)
		var keys := Defs.SPECS.keys()
		var cur: String = city.districts[target].get("spec", "")
		for i in keys.size():
			ob.add_item(Defs.SPECS[keys[i]].name, i + 1)
			if keys[i] == cur:
				ob.select(i + 1)
		var tid := target
		ob.item_selected.connect(func(ix):
			city.set_district_spec(tid, "" if ix == 0 else keys[ix - 1])
			Sfx.play("toggle", -6.0)
			_refresh_policies.call_deferred())
		sr.add_child(ob)
		policy_box.add_child(sr)
		# what the district soil holds
		var cnt := {}
		var tot := 0
		for i in city.n * city.n:
			if city.district[i] == target:
				tot += 1
				var r := city.resource[i]
				if r > 0:
					cnt[r] = cnt.get(r, 0.0) + (city.res_amt[i] if r >= 3 else 1.0)
		var parts: Array = []
		for r in Defs.RESOURCES:
			if cnt.has(r):
				parts.append("%s %d%%" % [Defs.RESOURCES[r].name.to_lower(), int(cnt[r] * 100.0 / max(1, tot))])
		var info := _label(("Ресурсы района: " + ", ".join(parts) if parts.size() > 0 else "В районе нет природных ресурсов.") + ("\n" + Defs.SPECS[cur].desc if cur != "" else "\nСлой «Природные ресурсы» покажет, где что лежит."), 12, DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 460
		policy_box.add_child(info)
	# architecture style
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 10)
	ar.add_child(_icon("style", 26))
	var al := _label("Архитектурный стиль", 15)
	al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.add_child(al)
	var so := OptionButton.new()
	so.focus_mode = Control.FOCUS_NONE
	var skeys: Array = Defs.STYLES.keys()
	var scur: String = city.city_style if target == 0 else city.districts[target].get("style", "")
	if target != 0:
		so.add_item("Как во всём городе", 0)
	for i in skeys.size():
		so.add_item(Defs.STYLES[skeys[i]].name, i + 1)
		if skeys[i] == scur:
			so.select(so.get_item_index(i + 1))
	if target != 0 and scur == "":
		so.select(0)
	var st_tid := target
	so.item_selected.connect(func(ix):
		var id: int = so.get_item_id(ix)
		city.set_style(st_tid, "" if id == 0 else skeys[id - 1])
		Sfx.play("toggle", -6.0)
		_refresh_policies.call_deferred())
	ar.add_child(so)
	policy_box.add_child(ar)
	var eff_style: String = city.style_at(Vector2i(-1, -1)) if target == 0 else (scur if scur != "" else city.city_style)
	var cnt_old := 0
	for b: Building in city.buildings.values():
		if b.type == "zone" and not b.abandoned and not b.style_lock and b.style != eff_style and (target == 0 or city.district[city.idx(b.x, b.y)] == target) \
				and (target != 0 or city.districts.get(city.district[city.idx(b.x, b.y)], {}).get("style", "") == ""):
			cnt_old += 1
	var sd := _label(Defs.STYLES[eff_style].desc + " Дома перестраиваются в новом стиле постепенно, при улучшении.", 12, DIM)
	sd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sd.custom_minimum_size.x = 460
	policy_box.add_child(sd)
	if cnt_old > 0:
		var price := cnt_old * 250
		var rb := _button("Перестроить сразу %d зд. — ₽%s" % [cnt_old, Defs.fmt_int(price)], "bulldoze", func():
			if city.money < price:
				add_notification("Недостаточно денег для перестройки.", "bad")
				return
			city.money -= price
			city.set_style(st_tid, city.city_style if st_tid == 0 else city.districts[st_tid].get("style", ""), true)
			Sfx.play("place", -4.0)
			_refresh_policies.call_deferred(), 13)
		policy_box.add_child(rb)
	policy_box.add_child(HSeparator.new())
	for pid in Defs.POLICIES:
		var pd: Dictionary = Defs.POLICIES[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_icon(pd.icon, 26))
		var txt := VBoxContainer.new()
		txt.add_theme_constant_override("separation", -2)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_child(_label(pd.name, 15))
		var dl := _label(pd.desc + ("  ₽%s/мес за здание" % str(pd.cost) if pd.cost > 0.0 else ""), 12, DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size.x = 360
		txt.add_child(dl)
		row.add_child(txt)
		var cb := CheckButton.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = pid in active
		if target != 0 and pid in city.city_policies:
			cb.disabled = true
			cb.tooltip_text = "Уже действует во всём городе"
		var p_id: String = pid
		cb.toggled.connect(func(_on): city.toggle_policy(p_id, target); Sfx.play("toggle", -6.0))
		row.add_child(cb)
		policy_box.add_child(row)


# ================================================================== disasters
func _build_disasters() -> void:
	var w := _window("Катастрофы", Vector2(420, 0))
	disaster_panel = w[0]
	var vb: VBoxContainer = w[1]
	var hb := HBoxContainer.new()
	var l := _label("Случайные катастрофы", 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var ob := OptionButton.new()
	for t in ["Выключены", "Редко", "Часто"]:
		ob.add_item(t)
	ob.focus_mode = Control.FOCUS_NONE
	ob.item_selected.connect(func(i): city.random_disasters = i)
	ob.set_meta("is_freq", true)
	hb.add_child(ob)
	vb.add_child(hb)
	disaster_panel.set_meta("freq", ob)
	vb.add_child(_label("Вызвать вручную:", 13, DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for k in Defs.DISASTERS:
		var dd: Dictionary = Defs.DISASTERS[k]
		var kind: String = k
		var b := _button(dd.name, dd.icon, func(): main.disasters.trigger(kind); disaster_panel.visible = false, 26)
		b.tooltip_text = dd.desc
		b.custom_minimum_size = Vector2(190, 44)
		grid.add_child(b)
	vb.add_child(grid)
	var tip := _label("Служба спасения (раздел «Безопасность») быстро разбирает руины и снижает число пострадавших.", 12, DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 390
	vb.add_child(tip)


# ================================================================== advisors & news
func _build_advisors() -> void:
	var w := _window("Советники мэра", Vector2(560, 0))
	advisor_panel = w[0]
	advisor_box = VBoxContainer.new()
	advisor_box.add_theme_constant_override("separation", 10)
	w[1].add_child(advisor_box)


func _refresh_advisors() -> void:
	for ch in advisor_box.get_children():
		ch.queue_free()
	for a in News.ADVISORS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var av := _avatar({"color": a.color, "initials": a.name.substr(0, 1) + a.name.get_slice(" ", 1).substr(0, 1)}, 46)
		av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(av)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		var hh := HBoxContainer.new()
		hh.add_child(_label(a.name, 15))
		hh.add_child(_label("  " + a.role, 12, DIM))
		v.add_child(hh)
		for adv in News.advice(city, a.id).slice(0, 3):
			var col: Color = [GOOD, Color(1, 0.8, 0.35), BAD][adv.level]
			var l := _label(["✔ ", "⚠ ", "‼ "][adv.level] + adv.text, 13, col)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 460
			v.add_child(l)
		row.add_child(v)
		advisor_box.add_child(row)


func _build_paper() -> void:
	paper_panel = PanelContainer.new()
	paper_panel.visible = false
	paper_panel.custom_minimum_size = Vector2(620, 0)
	var sb := _sb(Color("f3ecd9"), 4, 22, Color("b8a988"))
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	paper_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(paper_panel)
	paper_box = VBoxContainer.new()
	paper_box.add_theme_constant_override("separation", 6)
	paper_panel.add_child(paper_box)


func _publish_paper() -> void:
	if in_menu():
		return
	var issue := News.newspaper(city, city.events, _prev_snapshot)
	issues.push_front(issue)
	if issues.size() > 12:
		issues.pop_back()
	city.events.clear()
	_prev_snapshot = {"pop": city.population}
	if paper_panel.visible:
		_refresh_paper()
	else:
		paper_btn.text = " 1"
	_rebuild_ticker()


func _refresh_paper() -> void:
	for ch in paper_box.get_children():
		ch.queue_free()
	var ink := Color("2b2418")
	var sub := Color("6b5d45")
	var hb := HBoxContainer.new()
	var t := _label("ВЕСТНИК BS: CITIES", 34, ink)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.add_theme_color_override("font_color", ink)
	x.pressed.connect(func(): paper_panel.visible = false)
	hb.add_child(x)
	paper_box.add_child(hb)
	if issues.is_empty():
		paper_box.add_child(_label("Первый номер выйдет в конце месяца.", 15, sub))
		return
	var iss: Dictionary = issues[0]
	paper_box.add_child(_label("№ %d · %s · %s" % [iss.issue, iss.date, iss.weather], 13, sub))
	var line := ColorRect.new()
	line.color = ink
	line.custom_minimum_size.y = 2
	paper_box.add_child(line)
	var arts: Array = iss.articles
	for k in arts.size():
		var a: Dictionary = arts[k]
		var ttl := _label(a.title, 24 if k == 0 else 17, ink)
		ttl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ttl.custom_minimum_size.x = 570
		paper_box.add_child(ttl)
		var bd := _label(a.body, 14 if k == 0 else 13, sub)
		bd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bd.custom_minimum_size.x = 570
		paper_box.add_child(bd)
		if k < arts.size() - 1:
			var ln := ColorRect.new()
			ln.color = Color(ink, 0.25)
			ln.custom_minimum_size.y = 1
			paper_box.add_child(ln)
	var line2 := ColorRect.new()
	line2.color = ink
	line2.custom_minimum_size.y = 2
	paper_box.add_child(line2)
	paper_box.add_child(_label(iss.stats, 13, sub))


func _build_ticker() -> void:
	ticker = PanelContainer.new()
	var sb := _sb(Color(0.05, 0.07, 0.1, 0.75), 0, 4)
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	ticker.add_theme_stylebox_override("panel", sb)
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ticker)
	ticker_clip = Control.new()
	ticker_clip.clip_contents = true
	ticker_clip.custom_minimum_size = Vector2(0, 20)
	ticker_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker.add_child(ticker_clip)
	ticker_label = _label("", 13, Color(0.85, 0.9, 1.0))
	ticker_clip.add_child(ticker_label)


func _rebuild_ticker() -> void:
	if city == null or ticker_label == null:
		return
	var items: Array = []
	if not issues.is_empty():
		for a in issues[0].articles:
			items.append("📰 " + a.title)
	for a in News.ADVISORS:
		for adv in News.advice(city, a.id):
			if adv.level >= 1:
				items.append("%s: %s" % [a.role, adv.text])
				break
	items.append("Население: %s" % Defs.fmt_int(city.population))
	items.append("Курс городских облигаций стабилен")
	items.append("%s. Погода: %s" % [city.season_name(), {"clear": "ясно", "rain": "дождь", "snow": "снегопад"}.get(city.weather, "ясно")])
	ticker_label.text = "      •      ".join(items)
	ticker_label.reset_size()


# ================================================================== roads info
func _build_road_panel() -> void:
	road_panel = PanelContainer.new()
	road_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	road_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	road_panel.offset_right = -12
	road_panel.offset_top = 78
	road_panel.custom_minimum_size = Vector2(290, 0)
	road_panel.visible = false
	root.add_child(road_panel)
	road_box = VBoxContainer.new()
	road_box.add_theme_constant_override("separation", 5)
	road_panel.add_child(road_box)


func _on_road(t: Vector2i) -> void:
	road_tile = t
	road_panel.visible = true
	info_panel.visible = false
	agent_panel.visible = false
	_refresh_road()


func _refresh_road() -> void:
	for ch in road_box.get_children():
		ch.queue_free()
	if not city.is_road(road_tile):
		road_panel.visible = false
		return
	var i := city.idx(road_tile.x, road_tile.y)
	var rt: int = city.road[i]
	var hb := HBoxContainer.new()
	var t := _label(Defs.ROAD_TYPES[rt].name + (" (мост)" if city.terrain[i] == 1 else ""), 19)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	hb.add_child(_button("", "close", func(): road_panel.visible = false, 14))
	road_box.add_child(hb)
	var d := city.district[i]
	if city.districts.has(d):
		road_box.add_child(_label("Район «%s»" % city.districts[d].name, 13, DIM))
	road_box.add_child(HSeparator.new())
	var cg := city.congestion(i)
	_row(road_box, "Загрузка", "%d%%" % int(cg * 100), GOOD if cg < 0.7 else (Color(1, 0.8, 0.35) if cg < 1.0 else BAD))
	var bar := ProgressBar.new()
	bar.max_value = 1.5
	bar.value = min(cg, 1.5)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 12
	bar.add_theme_stylebox_override("fill", _sb(Overlays_heat(100.0 - cg * 66.0), 4, 0))
	road_box.add_child(bar)
	_row(road_box, "Скорость", "×%.1f" % Defs.ROAD_TYPES[rt].speed)
	_row(road_box, "Пропускная способность", str(int(Defs.ROAD_TYPES[rt].cap)))
	_row(road_box, "Содержание", "₽%s/мес" % Defs.fmt_int(Defs.ROAD_TYPES[rt].upkeep))
	if cg > 1.0:
		var w := _label("Пробка! Замените на проспект или шоссе, пустите автобус.", 12, BAD)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size.x = 270
		road_box.add_child(w)
	road_box.add_child(HSeparator.new())
	road_box.add_child(_label("Заменить участок на:", 13, DIM))
	var seg := city.road_segment(road_tile)
	for nt in Defs.ROAD_TYPES:
		if nt == rt:
			continue
		var rd: Dictionary = Defs.ROAD_TYPES[nt]
		var cost: int = rd.cost * seg.size()
		var ntt: int = nt
		var b := _button("%s — %d кл., ₽%s" % [rd.name, seg.size(), Defs.fmt_int(cost)], rd.icon, func():
			if city.build_roads(seg, ntt):
				Sfx.play("road")
				_refresh_road()
			else:
				Sfx.play("error")
				add_notification("Нельзя заменить дорогу: %s" % city.check_roads(seg, ntt).reason, "bad"), 20)
		b.disabled = not city.is_unlocked(rd.unlock)
		road_box.add_child(b)


# ================================================================== quests
func _build_quests() -> void:
	quest_panel = PanelContainer.new()
	quest_panel.position = Vector2(12, 110)
	quest_panel.custom_minimum_size = Vector2(250, 0)
	quest_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(quest_panel)
	quest_box = VBoxContainer.new()
	quest_box.add_theme_constant_override("separation", 3)
	quest_panel.add_child(quest_box)


func _refresh_quests() -> void:
	if city == null:
		return
	for ch in quest_box.get_children():
		ch.queue_free()
	var hb := HBoxContainer.new()
	var t := _label("🎯 Задания  %d/%d" % [city.quests_done.size(), Quests.LIST.size()], 14, Color(0.75, 0.85, 1.0))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	quest_box.add_child(hb)
	for q in city.active_quests(3):
		var p: float = clamp(Quests.progress(city, q.id), 0.0, 1.0)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var h2 := HBoxContainer.new()
		var nl := _label(q.name, 13)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h2.add_child(nl)
		h2.add_child(_label("₽" + Defs.fmt_int(q.reward), 11, GOOD))
		row.add_child(h2)
		row.add_child(_label(q.desc, 11, DIM))
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = p
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		row.add_child(bar)
		quest_box.add_child(row)


func _on_quest(q: Dictionary) -> void:
	if in_menu():
		return
	show_banner("🎯 Задание выполнено: %s\nНаграда: ₽%s" % [q.name, Defs.fmt_int(q.reward)])
	Sfx.play("milestone", -4.0)
	add_notification("🎯 Выполнено «%s» (+₽%s)" % [q.name, Defs.fmt_int(q.reward)], "good")
	_refresh_quests()


# ================================================================== minimap
class Minimap extends Control:
	var city: City
	var rig
	var img: Image
	var tex: ImageTexture
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		_t -= delta
		if city and _t <= 0.0:
			_t = 1.5
			_rebuild()
		queue_redraw()

	func _rebuild() -> void:
		var n := city.n
		if img == null:
			img = Image.create(n, n, false, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var i := city.idx(x, y)
				var c := Color("5e9e48")
				var h := city.tile_h(x, y)
				if h > 2.5: c = Color("4d7a3c")
				if h > 7.0: c = Color("8f8a80")
				if city.tree[i] == 1: c = Color("3d6e32")
				if city.terrain[i] == 1: c = Color("3f7fbf")
				if city.road[i] > 0: c = Color("cfd3da") if city.road[i] < 3 else Color("f2f2f2")
				elif city.bld[i] != -1:
					var b: Building = city.buildings[city.bld[i]]
					if b.is_service(): c = Color("ef6c00")
					elif b.collapsed or b.abandoned: c = Color("555555")
					else: c = Defs.ZONES[b.zone].color.darkened(0.15)
				elif city.zone[i] != 0:
					c = c.lerp(Defs.ZONES[city.zone[i]].color, 0.35)
				img.set_pixel(x, y, c)
		if tex == null:
			tex = ImageTexture.create_from_image(img)
		else:
			tex.update(img)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.1, 0.9))
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(4, 4), size - Vector2(8, 8)), false)
		if rig and city:
			var k := (size.x - 8) / city.n
			var vp := get_viewport().get_visible_rect().size
			var pts := PackedVector2Array()
			for c in [Vector2(0, 0), Vector2(vp.x, 0), vp, Vector2(0, vp.y)]:
				var o: Vector3 = rig.cam.project_ray_origin(c)
				var d: Vector3 = rig.cam.project_ray_normal(c)
				var t: float = (rig.focus.y - o.y) / d.y if d.y < -0.01 else 300.0
				t = min(t, 300.0)
				var p: Vector3 = o + d * t
				pts.append(Vector2(4 + p.x * k, 4 + p.z * k).clamp(Vector2(4, 4), size - Vector2(4, 4)))
			pts.append(pts[0])
			draw_polyline(pts, Color(1, 1, 1, 0.9), 1.5)
			draw_circle(Vector2(4 + rig.focus.x * k, 4 + rig.focus.z * k), 2.5, Color(1, 0.85, 0.3))

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			var k := (size.x - 8) / city.n
			var p: Vector2 = (e.position - Vector2(4, 4)) / k
			rig.follow = null
			rig.t_focus = Vector3(p.x, 0, p.y)
			accept_event()


func _build_minimap() -> void:
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(190, 190)
	minimap.size = Vector2(190, 190)
	minimap.tooltip_text = "Мини-карта: клик — переместить камеру [M — скрыть]"
	root.add_child(minimap)


# ================================================================== tutorial
func _build_tutorial() -> void:
	tut_panel = PanelContainer.new()
	var sb := _sb(Color(0.1, 0.22, 0.4, 0.95), 10, 14, Color(0.5, 0.75, 1, 0.9))
	sb.set_border_width_all(2)
	tut_panel.add_theme_stylebox_override("panel", sb)
	tut_panel.visible = false
	root.add_child(tut_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	tut_panel.add_child(hb)
	hb.add_child(_icon("advisor", 40))
	tut_label = _label("", 15)
	tut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_label.custom_minimum_size.x = 460
	hb.add_child(tut_label)
	hb.add_child(_button("Пропустить", "close", func(): end_tutorial(), 14))


func start_tutorial() -> void:
	tut_step = 0
	tut_base_roads = city.road_count
	_show_tut_step()


func end_tutorial() -> void:
	tut_step = -1
	tut_panel.visible = false
	_highlight("")
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("game", "tutorial_done", true)
	cf.save("user://settings.cfg")


static func tutorial_done() -> bool:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		return bool(cf.get_value("game", "tutorial_done", false))
	return false


func _show_tut_step() -> void:
	tut_panel.visible = true
	tut_label.text = TUT[tut_step].text
	_highlight(TUT[tut_step].cat)
	tut_panel.reset_size()


func _highlight(cat: String) -> void:
	if _tut_tw:
		_tut_tw.kill()
	if _tut_btn and is_instance_valid(_tut_btn):
		_tut_btn.modulate = Color.WHITE
	_tut_btn = cat_btns.get(cat) if cat != "" else null
	if _tut_btn:
		_tut_tw = create_tween().set_loops()
		_tut_tw.tween_property(_tut_btn, "modulate", Color(1.6, 1.4, 0.6), 0.5)
		_tut_tw.tween_property(_tut_btn, "modulate", Color.WHITE, 0.5)


func _zone_count(kinds: Array) -> int:
	var c := 0
	for z in city.zone:
		if z != 0 and Defs.zone_kind(z) in kinds:
			c += 1
	return c


func _tutorial_check() -> void:
	tut_panel.position = Vector2((root.size.x - tut_panel.size.x) * 0.5, top_bar.size.y + 40)
	var done := false
	match tut_step:
		0: done = city.road_count >= tut_base_roads + 4
		1: done = _zone_count(["r"]) >= 8
		2: done = _zone_count(["c"]) >= 4 and _zone_count(["i"]) >= 4
		3: done = city.power_supply > 0
		4: done = city.water_supply > 0
		5: done = city.population >= 10
	if done:
		Sfx.play("milestone", -6.0)
		tut_step += 1
		if tut_step >= TUT.size():
			end_tutorial()
			show_banner("🎓 Обучение пройдено!\nДальше вас поведут задания слева. Удачи, мэр!")
		else:
			_show_tut_step()


# ================================================================== new game
func _build_newgame() -> void:
	var w := _window("Новый город", Vector2(460, 0))
	newgame_panel = w[0]
	var vb: VBoxContainer = w[1]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var name_h := HBoxContainer.new()
	var nl := _label("Название", 14, DIM)
	nl.custom_minimum_size.x = 120
	name_h.add_child(nl)
	var name_e := LineEdit.new()
	name_e.text = Defs.CITY_NAMES[rng.randi() % Defs.CITY_NAMES.size()]
	name_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_e.max_length = 24
	name_h.add_child(name_e)
	vb.add_child(name_h)
	var map_h := HBoxContainer.new()
	var ml := _label("Карта", 14, DIM)
	ml.custom_minimum_size.x = 120
	map_h.add_child(ml)
	var map_o := OptionButton.new()
	var keys := Defs.MAP_TYPES.keys()
	for k in keys:
		map_o.add_item(Defs.MAP_TYPES[k].name)
	map_o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_o.focus_mode = Control.FOCUS_NONE
	map_h.add_child(map_o)
	vb.add_child(map_h)
	var mdesc := _label(Defs.MAP_TYPES[keys[0]].desc, 12, DIM)
	map_o.item_selected.connect(func(i): mdesc.text = Defs.MAP_TYPES[keys[i]].desc)
	vb.add_child(mdesc)
	var dif_h := HBoxContainer.new()
	var dl := _label("Сложность", 14, DIM)
	dl.custom_minimum_size.x = 120
	dif_h.add_child(dl)
	var dif_o := OptionButton.new()
	for d in Defs.DIFFICULTY:
		dif_o.add_item(d.name)
	dif_o.select(1)
	dif_o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dif_o.focus_mode = Control.FOCUS_NONE
	dif_h.add_child(dif_o)
	vb.add_child(dif_h)
	var ddesc := _label("Стартовый капитал ₽70 000.", 12, DIM)
	dif_o.item_selected.connect(func(i):
		ddesc.text = "Бесконечные деньги, всё открыто." if i == 3 else "Стартовый капитал ₽%s, доходы ×%.2f." % [Defs.fmt_int(Defs.DIFFICULTY[i].money), Defs.DIFFICULTY[i].income])
	vb.add_child(ddesc)
	var sty_h := HBoxContainer.new()
	var styl := _label("Архитектура", 14, DIM)
	styl.custom_minimum_size.x = 120
	sty_h.add_child(styl)
	var sty_o := OptionButton.new()
	var skeys: Array = Defs.STYLES.keys()
	for k in skeys:
		sty_o.add_item(Defs.STYLES[k].name)
	sty_o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sty_o.focus_mode = Control.FOCUS_NONE
	sty_h.add_child(sty_o)
	vb.add_child(sty_h)
	var sdesc := _label(Defs.STYLES[skeys[0]].desc + " Районам можно задать свой стиль.", 12, DIM)
	sdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sdesc.custom_minimum_size.x = 380
	sty_o.item_selected.connect(func(i): sdesc.text = Defs.STYLES[skeys[i]].desc + " Районам можно задать свой стиль.")
	vb.add_child(sdesc)
	var seed_h := HBoxContainer.new()
	var sl := _label("Сид карты", 14, DIM)
	sl.custom_minimum_size.x = 120
	seed_h.add_child(sl)
	var seed_e := LineEdit.new()
	seed_e.text = str(rng.randi() % 1000000)
	seed_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_h.add_child(seed_e)
	seed_h.add_child(_button("", "rotate", func(): seed_e.text = str(randi() % 1000000), 16))
	vb.add_child(seed_h)
	var tut_cb := CheckButton.new()
	tut_cb.text = "Обучение для новичков"
	tut_cb.button_pressed = not tutorial_done()
	tut_cb.focus_mode = Control.FOCUS_NONE
	vb.add_child(tut_cb)
	vb.add_child(HSeparator.new())
	var go := _button("Основать город", "play1", func():
		newgame_panel.visible = false
		new_game_requested.emit({"name": name_e.text.strip_edges() if name_e.text.strip_edges() != "" else "Новоградск",
			"map": keys[map_o.selected], "difficulty": dif_o.selected, "seed": int(seed_e.text) if seed_e.text.is_valid_int() else randi(), "tutorial": tut_cb.button_pressed,
			"style": skeys[sty_o.selected]}), 20)
	go.custom_minimum_size.y = 44
	vb.add_child(go)


# ================================================================== citizens
func _complain(text: String) -> String:
	var t := text
	for pre in ["Горожане ", "Жители "]:
		t = t.replace(pre, "")
	var tails := [" Мэр, сделайте что-нибудь!", " #безобразие", " Ну сколько можно?", " 😠"]
	return t + tails[_chirp_rng.randi() % tails.size()]


func _build_agent_panel() -> void:
	agent_panel = PanelContainer.new()
	agent_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	agent_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	agent_panel.offset_right = -12
	agent_panel.offset_top = 78
	agent_panel.custom_minimum_size = Vector2(300, 0)
	agent_panel.visible = false
	root.add_child(agent_panel)
	agent_box = VBoxContainer.new()
	agent_box.add_theme_constant_override("separation", 5)
	agent_panel.add_child(agent_box)


func _on_agent(ag) -> void:
	agent_panel.visible = ag != null
	info_panel.visible = false
	_refresh_agent()


func _avatar(p: Dictionary, size: int) -> Control:
	var c := Panel.new()
	c.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = p.color
	sb.set_corner_radius_all(size / 2)
	c.add_theme_stylebox_override("panel", sb)
	var l := _label(p.initials, int(size * 0.4), Color.WHITE)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c


func _refresh_agent() -> void:
	var ag = tools.selected_agent
	for ch in agent_box.get_children():
		ch.queue_free()
	var person = null
	if ag != null and is_instance_valid(ag.node) and ag.citizen >= 0:
		person = city.people.get_person(ag.citizen)
	elif ag == null and view_person >= 0:
		person = city.people.get_person(view_person)
	if (ag == null or not is_instance_valid(ag.node)) and person == null:
		agent_panel.visible = false
		if main.rig.follow != null and ag != null:
			main.rig.follow = null
			add_notification("📍 Горожанин добрался до места назначения.", "info")
		tools.selected_agent = null
		view_person = -1
		return
	agent_panel.visible = true
	var sd: int = person.seed if person else ag.seed
	var p := Citizens.persona(sd)
	if person:
		p.name = city.people.full_name(person)
		p.initials = person.first.substr(0, 1) + person.last.substr(0, 1)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(_avatar(p, 44))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(_label(p.name, 17))
	nv.add_child(_label("%s · %s" % [Citizens.age_word(person.age if person else p.age), p.handle], 12, DIM))
	hb.add_child(nv)
	hb.add_child(_button("", "close", func(): tools.selected_agent = null; view_person = -1; main.rig.follow = null; agent_panel.visible = false, 14))
	agent_box.add_child(hb)
	agent_box.add_child(HSeparator.new())
	if ag != null and is_instance_valid(ag.node):
		_row(agent_box, "Сейчас", ag.purpose if ag.purpose != "" else "в пути")
	var home: Building = null
	if person:
		home = city.buildings.get(person.home)
		_row(agent_box, "Занятие", city.people.occupation(person))
		_row(agent_box, "Образование", People.EDU_NAMES[person.edu])
	else:
		home = ag.get("home") if "home" in ag else ag.get("from_b")
	if home and city.buildings.has(home.id):
		var dn := ""
		var d := city.district[city.idx(home.x, home.y)]
		if city.districts.has(d):
			dn = " (%s)" % city.districts[d].name
		_row(agent_box, "Живёт", home.display_name() + dn)
		_row(agent_box, "Настроение", "%d%%" % int(home.happiness), GOOD if home.happiness > 60 else (BAD if home.happiness < 35 else TXT))
	if ag != null and is_instance_valid(ag.node):
		var dest: Building = ag.get("dest") if "dest" in ag else ag.get("to_b")
		if dest and city.buildings.has(dest.id):
			_row(agent_box, "Направляется", dest.display_name())
	if person:
		var fam: Array = city.people.family_of(person)
		if fam.size() > 0:
			agent_box.add_child(_label("Семья", 13, DIM))
			for o in fam:
				var rel := "супруг" if o.id == person.partner and not o.female else ("супруга" if o.id == person.partner else (("сын" if not o.female else "дочь") if person.id in o.parents else (("отец" if not o.female else "мать") if o.id in person.parents else "родственник")))
				var oid: int = o.id
				var fb2 := _button("%s — %s, %s" % [city.people.full_name(o), rel, Citizens.age_word(o.age)], "", func(): show_person(oid), 0)
				fb2.add_theme_font_size_override("font_size", 12)
				fb2.alignment = HORIZONTAL_ALIGNMENT_LEFT
				agent_box.add_child(fb2)
	_row(agent_box, "Увлечение", p.hobby)
	var th := _label("💭 «%s»" % Citizens.thought(city, home, sd), 13, Color(0.85, 0.9, 1.0))
	th.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	th.custom_minimum_size.x = 280
	agent_box.add_child(th)
	if ag != null and is_instance_valid(ag.node):
		var following: bool = main.rig.follow == ag.node
		var fb := _button("Перестать следить" if following else "Следить", "select", func():
			main.rig.follow = null if main.rig.follow == ag.node else ag.node
			if main.rig.follow:
				main.rig.t_dist = 6.0
			elif main.rig.street:
				main.rig.set_street(false)
			_refresh_agent(), 18)
		agent_box.add_child(fb)
		var eyes := _button("Вернуть обычный вид" if main.rig.street else "Вид с улицы (V)", "select", func():
			main.rig.follow = ag.node
			main.rig.set_street(not main.rig.street)
			_refresh_agent(), 18)
		agent_box.add_child(eyes)
	elif person:
		var found = _agent_of(person.id)
		if found:
			agent_box.add_child(_button("Найти на улице", "select", func():
				tools.selected_agent = found
				view_person = -1
				main.rig.follow = found.node
				main.rig.t_dist = 6.0
				_refresh_agent(), 18))
		elif home:
			agent_box.add_child(_button("Показать дом", "select", func(): main.rig.set_focus(home.center(), 10.0), 18))


var view_person := -1


## Opens the card of a citizen (from a building's resident list or a family member).
func show_person(id: int) -> void:
	tools.selected_agent = null
	view_person = id
	info_panel.visible = false
	_refresh_agent()


func _agent_of(pid: int):
	for l in [main.peds.peds, main.traffic.cars]:
		for a in l:
			if a.citizen == pid and is_instance_valid(a.node):
				return a
	return null

func _build_chirper() -> void:
	chirp_panel = PanelContainer.new()
	chirp_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	chirp_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chirp_panel.offset_right = -12
	chirp_panel.offset_left = -332
	chirp_panel.offset_top = 78
	chirp_panel.offset_bottom = -110
	chirp_panel.visible = false
	root.add_child(chirp_panel)
	var vb := VBoxContainer.new()
	chirp_panel.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_child(_icon("bird", 22))
	var t := _label("Чирпер", 18, Color(0.55, 0.8, 1.0))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	hb.add_child(_button("", "close", func(): chirp_panel.visible = false, 14))
	vb.add_child(hb)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	chirp_box = VBoxContainer.new()
	chirp_box.add_theme_constant_override("separation", 8)
	chirp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(chirp_box)
	_chirp_rng.randomize()


func _toggle_chirper() -> void:
	chirp_panel.visible = not chirp_panel.visible
	if chirp_panel.visible:
		unread = 0
		_refresh_chirps()
	_update_chirp_badge()


func _update_chirp_badge() -> void:
	if chirp_btn:
		chirp_btn.text = (" %d" % unread) if unread > 0 else ""


func _on_day_chirp() -> void:
	if in_menu() or city.population < 20:
		return
	if _chirp_rng.randf() < 0.12:
		add_chirp()


func _chirp_event(text: String) -> void:
	if in_menu():
		return
	_push_chirp(Citizens.persona(_chirp_rng.randi()), text)


func add_chirp() -> void:
	var recent: Array = []
	for c in chirps.slice(0, 6):
		recent.append(c.text)
	var text := Citizens.city_chirp(city, _chirp_rng)
	for k in 8:
		if not text in recent:
			break
		text = Citizens.city_chirp(city, _chirp_rng)
	if text in recent:
		return
	_push_chirp(Citizens.persona(_chirp_rng.randi()), text)


func _push_chirp(p: Dictionary, text: String) -> void:
	chirps.push_front({"p": p, "text": text, "day": city.day})
	if chirps.size() > 40:
		chirps.pop_back()
	if chirp_panel.visible:
		_refresh_chirps()
	else:
		unread += 1
		_update_chirp_badge()


func _refresh_chirps() -> void:
	for ch in chirp_box.get_children():
		ch.queue_free()
	if chirps.is_empty():
		chirp_box.add_child(_label("Пока тихо…", 13, DIM))
	for c in chirps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var av := _avatar(c.p, 34)
		av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(av)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_label("%s  %s · %s" % [c.p.name, c.p.handle, Defs.date_string(c.day)], 11, DIM))
		var tl := _label(c.text, 13)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size.x = 250
		v.add_child(tl)
		row.add_child(v)
		chirp_box.add_child(row)


# ================================================================== help
func _build_help() -> void:
	var w := _window("Управление", Vector2(440, 0))
	help_panel = w[0]
	var vb: VBoxContainer = w[1]
	var lines := [
		["WASD / стрелки", "перемещение камеры"], ["Q / E", "поворот камеры"], ["Колесо мыши", "приближение"],
		["Средняя кнопка", "вращение и наклон"], ["Правая кнопка", "перетаскивание карты"], ["ЛКМ (тянуть)", "строить дороги / зоны / сносить"],
		["R", "повернуть здание"], ["Tab", "перевернуть угол дороги"], ["[ / ]", "размер кисти ландшафта"], ["ПКМ / Enter", "завершить маршрут"], ["Пробел", "пауза"], ["1 / 2 / 3", "скорость игры"], ["B", "бульдозер"],
		["F5 / F9", "быстрое сохранение / загрузка"], ["F11", "полный экран"], ["F12", "скриншот"], ["H", "скрыть интерфейс (фоторежим)"], ["M", "мини-карта"], ["Esc", "отмена / меню"],
		["Клик по машине/прохожему", "карточка горожанина, слежение"], ["Ctrl+клик (районы)", "выбрать район"],
	]
	for l in lines:
		_row(vb, l[0], l[1])
	vb.add_child(HSeparator.new())
	var tips := _label("Советы: начните с дорог от шоссе на западе, разметьте жилые (зелёные), коммерческие (синие) и промышленные (жёлтые) зоны. Постройте электростанцию и водокачку рядом с дорогой — сети идут вдоль дорог. Следите за спросом (столбики Ж/Т/П) и бюджетом.", 13, DIM)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.custom_minimum_size.x = 420
	vb.add_child(tips)


# ================================================================== notifications
func _build_notifs() -> void:
	notif_box = VBoxContainer.new()
	notif_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	notif_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	notif_box.offset_left = 12
	notif_box.offset_bottom = -110
	notif_box.custom_minimum_size = Vector2(380, 0)
	notif_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notif_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(notif_box)


func add_notification(text: String, kind: String = "info") -> void:
	if in_menu():
		return
	if kind == "bad":
		Sfx.play("bad", -12.0)
		if _chirp_rng.randf() < 0.5 and city:
			_chirp_event(_complain(text))
	var p := PanelContainer.new()
	var col := BG
	var sb := _sb(Color(0.08, 0.1, 0.14, 0.9), 8, 8, (BAD if kind == "bad" else (GOOD if kind == "good" else ACCENT)) * Color(1, 1, 1, 0.7))
	sb.border_width_left = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	p.add_child(l)
	notif_box.add_child(p)
	while notif_box.get_child_count() > 5:
		notif_box.get_child(0).free()
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.tween_interval(9.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


# ================================================================== tooltip
func _build_tooltip() -> void:
	tip_panel = PanelContainer.new()
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.06, 0.09, 0.9), 6, 7))
	tip_label = _label("", 13)
	tip_panel.add_child(tip_label)
	tip_panel.visible = false
	root.add_child(tip_panel)


func _on_tooltip(text: String, ok: bool) -> void:
	tip_panel.visible = text != ""
	tip_label.text = text
	tip_label.add_theme_color_override("font_color", TXT if ok else BAD)


# ================================================================== banner
func _build_banner() -> void:
	banner = PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.offset_top = 90
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _sb(Color(0.1, 0.2, 0.35, 0.95), 12, 18, Color(0.5, 0.75, 1, 0.8))
	sb.set_border_width_all(2)
	banner.add_theme_stylebox_override("panel", sb)
	banner_label = _label("", 22)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_label)
	banner.visible = false
	root.add_child(banner)


func show_banner(text: String) -> void:
	if in_menu():
		return
	banner_label.text = text
	banner.visible = true
	banner.modulate.a = 0
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.4)
	tw.tween_interval(5.0)
	tw.tween_property(banner, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): banner.visible = false)


func _on_milestone(i: int) -> void:
	var m: Dictionary = Defs.MILESTONES[i]
	var unl: Array = []
	for z in Defs.ZONES:
		if Defs.ZONES[z].unlock == m.pop:
			unl.append(Defs.ZONES[z].short)
	for s in Defs.SERVICES:
		if Defs.SERVICES[s].unlock == m.pop:
			unl.append(Defs.SERVICES[s].name)
	var t := "🏆 Новый статус: %s!\nНаграда: ₽%s" % [m.name, Defs.fmt_int(m.reward)]
	if unl.size() > 0:
		t += "\nОткрыто: " + ", ".join(unl)
	show_banner(t)
	Sfx.play("milestone", -2.0)
	add_notification("🏆 Город достиг статуса «%s»" % m.name, "good")
	if cur_cat != "":
		var c := cur_cat
		cur_cat = ""
		_select_category(c)


# ================================================================== menus
func _fullscreen_layer(dim: float) -> Control:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.03, 0.05, dim)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(c)
	return c


func _build_pause() -> void:
	pause_layer = _fullscreen_layer(0.55)
	pause_layer.visible = false
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(300, 0)
	pause_layer.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var t := _label("Пауза", 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for e in [["Продолжить", func(): toggle_pause_menu()], ["Сохранить", func(): save_requested.emit(); toggle_pause_menu()],
			["Загрузить", func(): load_requested.emit(); toggle_pause_menu()], ["Управление", func(): toggle_pause_menu(); _toggle(help_panel)],
			["Главное меню", func(): toggle_pause_menu(); menu_requested.emit()], ["Выход из игры", func(): get_tree().quit()]]:
		var b := _button(e[0], "", e[1])
		b.custom_minimum_size.y = 40
		vb.add_child(b)
	vb.add_child(HSeparator.new())
	var qh := HBoxContainer.new()
	var ql := _label("Графика", 14, DIM)
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qh.add_child(ql)
	var qo := OptionButton.new()
	for q in ["Низкая", "Средняя", "Высокая", "Ультра"]:
		qo.add_item(q)
	qo.focus_mode = Control.FOCUS_NONE
	qo.item_selected.connect(func(i): main.apply_quality(i))
	qh.add_child(qo)
	vb.add_child(qh)
	var tsc := CheckButton.new()
	tsc.text = "Эффект миниатюры (размытие вдали)"
	tsc.button_pressed = true
	tsc.focus_mode = Control.FOCUS_NONE
	tsc.toggled.connect(func(on):
		main._tilt_pref = on
		main.rig.tilt_shift = on and main.quality >= 2
		main.rig._update_dof())
	vb.add_child(tsc)
	var mh := HBoxContainer.new()
	var ml := _label("Музыка", 14, DIM)
	ml.custom_minimum_size.x = 90
	mh.add_child(ml)
	var ms := HSlider.new()
	ms.min_value = 0
	ms.max_value = 1
	ms.step = 0.05
	ms.value = main.audio.music_volume
	ms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ms.custom_minimum_size.y = 22
	ms.value_changed.connect(func(v): main.audio.set_music_volume(v))
	mh.add_child(ms)
	vb.add_child(mh)
	var sh := HBoxContainer.new()
	var sl := _label("Эффекты", 14, DIM)
	sl.custom_minimum_size.x = 90
	sh.add_child(sl)
	var ss := HSlider.new()
	ss.min_value = 0
	ss.max_value = 1
	ss.step = 0.05
	ss.value = main.audio.sfx_volume
	ss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ss.custom_minimum_size.y = 22
	ss.value_changed.connect(func(v): main.audio.sfx_volume = v; main.audio.save_settings())
	sh.add_child(ss)
	vb.add_child(sh)
	var th := HBoxContainer.new()
	var tl := _label("♪ …", 13, Color(0.7, 0.8, 1.0))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	main.audio.track_changed.connect(func(n): tl.text = "♪ " + n)
	var mcb := CheckButton.new()
	mcb.text = "Музыка"
	mcb.button_pressed = main.audio.music_on
	mcb.focus_mode = Control.FOCUS_NONE
	mcb.toggled.connect(func(on): main.audio.music_on = on; main.audio.save_settings(); if on: main.audio.skip())
	th.add_child(mcb)
	th.add_child(_button("", "play2", func(): main.audio.skip(), 14))
	vb.add_child(th)
	var sc := CheckButton.new()
	sc.text = "Звуки"
	sc.button_pressed = Sfx.enabled
	sc.focus_mode = Control.FOCUS_NONE
	sc.toggled.connect(func(on): main.set_sound(on))
	vb.add_child(sc)
	pause_layer.set_meta("quality_opt", qo)
	pause_layer.set_meta("sound_chk", sc)


func toggle_pause_menu() -> void:
	pause_layer.visible = not pause_layer.visible
	(pause_layer.get_meta("quality_opt") as OptionButton).select(main.quality)
	(pause_layer.get_meta("sound_chk") as CheckButton).set_pressed_no_signal(Sfx.enabled)
	pause_layer.move_to_front()
	main.set_menu_pause(pause_layer.visible)


func _build_menu() -> void:
	menu_layer = Control.new()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu_layer)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.02, 0.04, 0.08, 0.92), Color(0.02, 0.04, 0.08, 0.0)])
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_layer.add_child(grad)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.offset_left = 90
	vb.add_theme_constant_override("separation", 12)
	menu_layer.add_child(vb)
	var t := _label("BS: CITIES", 64, Color(0.85, 0.92, 1.0))
	vb.add_child(t)
	vb.add_child(_label("Градостроительный симулятор", 22, Color(0.6, 0.72, 0.9)))
	var sp := Control.new()
	sp.custom_minimum_size.y = 30
	vb.add_child(sp)
	btn_continue = _menu_btn("Продолжить", func(): continue_requested.emit())
	vb.add_child(btn_continue)
	vb.add_child(_menu_btn("Новая игра", func(): _toggle(newgame_panel)))
	vb.add_child(_menu_btn("Управление", func(): _toggle(help_panel); help_panel.move_to_front()))
	vb.add_child(_menu_btn("Выход", func(): get_tree().quit()))
	var credits := _label("Модели: Kenney, KayKit, Quaternius (CC0) и авторы Poly Pizza (CC-BY), OpenGameArt: GGBotNet, Mixazzz (CC0) — см. CREDITS.md в assets/poly и assets/style · Движок: Godot 4", 12, Color(0.5, 0.55, 0.65))
	credits.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	credits.offset_left = 90
	credits.offset_top = -40
	menu_layer.add_child(credits)


func _menu_btn(text: String, cb: Callable) -> Button:
	var b := _button(text, "", cb)
	b.custom_minimum_size = Vector2(320, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


func show_menu(on: bool, has_save: bool = false) -> void:
	menu_layer.visible = on
	btn_continue.visible = has_save
	for c in [top_bar, toolbar, notif_box, ticker, quest_panel, minimap]:
		c.visible = not on
	if not on:
		newgame_panel.visible = false
	if on:
		subpanel.visible = false
		info_panel.visible = false
		overlay_panel.visible = false
		budget_panel.visible = false
		stats_panel.visible = false
		tip_panel.visible = false
		menu_layer.move_to_front()


func in_menu() -> bool:
	return menu_layer.visible


func toast_msg(text: String) -> void:
	add_notification(text, "info")


# ================================================================== refresh
func _process(delta: float) -> void:
	Prof.b("ui")
	_process_inner(delta)
	Prof.e("ui")


func _process_inner(delta: float) -> void:
	if main._loading_world:
		return
	_animate_colony_view(delta)
	if toolbar.visible:
		subpanel.offset_bottom = -(toolbar.size.y + 18)
		if subpanel.visible:
			var want := 24.0
			for ch in sub_box.get_children():
				if not ch.is_queued_for_deletion():
					want += ch.get_combined_minimum_size().x + 6
			var side: float = max(10.0, (root.size.x - want) * 0.5)
			subpanel.offset_left = side
			subpanel.offset_right = -side
		notif_box.offset_bottom = -(toolbar.size.y + 18 + (subpanel.size.y + 8 if subpanel.visible else 0))
	if ticker.visible:
		ticker.position = Vector2(top_bar.position.x + 10, top_bar.position.y + top_bar.size.y + 2)
		ticker.size.x = top_bar.size.x - 20
		_ticker_x -= delta * 70.0
		if _ticker_x < -ticker_label.size.x:
			_ticker_x = ticker_clip.size.x
			_rebuild_ticker()
		ticker_label.position.x = _ticker_x
	if top_bar.visible:
		info_panel.offset_top = top_bar.size.y + 18
		agent_panel.offset_top = top_bar.size.y + 18
		chirp_panel.offset_top = top_bar.size.y + 18
		chirp_panel.offset_bottom = -(toolbar.size.y + 20)
		var shift := -(chirp_panel.size.x + 24.0) if chirp_panel.visible else -12.0
		info_panel.offset_right = shift
		agent_panel.offset_right = shift
		road_panel.offset_right = shift
		road_panel.offset_top = top_bar.size.y + 18
		quest_panel.position = Vector2(12, top_bar.size.y + 34)
		overlay_panel.position.y = quest_panel.position.y + (quest_panel.size.y + 8 if quest_panel.visible else 0)
		if minimap.visible:
			chirp_panel.offset_bottom = -(toolbar.size.y + 20 + minimap.size.y + 8)
			minimap.position = Vector2(root.size.x - minimap.size.x - 12, root.size.y - toolbar.size.y - minimap.size.y - 22)
	if tip_panel.visible:
		var mp := root.get_viewport().get_mouse_position()
		tip_panel.position = mp + Vector2(18, 20)
		tip_panel.size = Vector2.ZERO
	_refresh_t -= delta
	_tut_t -= delta
	if tut_step >= 0 and _tut_t <= 0.0 and city and not in_menu():
		_tut_t = 0.5
		_tutorial_check()
	if _refresh_t <= 0.0 and city and not in_menu():
		_refresh_t = 0.25
		_refresh_bar()
		var mp2 := root.get_viewport().get_mouse_position()
		# don't rebuild a panel under the mouse: clicks on its buttons would get lost
		if info_panel.visible and not info_panel.get_global_rect().has_point(mp2):
			_refresh_info()
		if agent_panel.visible and not agent_panel.get_global_rect().has_point(mp2):
			_refresh_agent()
		if road_panel.visible and not road_panel.get_global_rect().has_point(mp2):
			_refresh_road()
		if city.day % 2 == 0:
			_refresh_quests()


func _refresh_bar() -> void:
	lbl_money.text = "₽" + Defs.fmt_int(city.money)
	lbl_money.add_theme_color_override("font_color", TXT if city.money >= 0 else BAD)
	var bal: float = city.projected.get("income", 0.0) - city.projected.get("expense", 0.0)
	lbl_delta.text = ("+" if bal >= 0 else "") + Defs.fmt_int(bal) + " / мес"
	lbl_delta.add_theme_color_override("font_color", GOOD if bal >= 0 else BAD)
	lbl_pop.text = Defs.fmt_int(city.population)
	lbl_happy.text = "%d%%" % int(city.avg_happiness)
	var wi := {"clear": ["☀", "🌱", "☀", "🍂"][city.season()], "rain": "🌧", "snow": "❄"}
	lbl_date.text = "%s %s" % [wi.get(city.weather, ""), Defs.date_string(city.day)]
	lbl_date.tooltip_text = "%s · %s" % [city.season_name(), {"clear": "ясно", "rain": "дождь", "snow": "снегопад"}.get(city.weather, "")]
	lbl_date.mouse_filter = Control.MOUSE_FILTER_PASS
	lbl_milestone.text = "%s · %s" % [city.city_name, Defs.MILESTONES[city.milestone].name]
	if city.milestone + 1 < Defs.MILESTONES.size():
		lbl_milestone.tooltip_text = "Следующий статус: %s (%s жителей)" % [Defs.MILESTONES[city.milestone + 1].name, Defs.fmt_int(Defs.MILESTONES[city.milestone + 1].pop)]
	lbl_milestone.mouse_filter = Control.MOUSE_FILTER_PASS
	rci.vals = [city.demand.r, city.demand.c, city.demand.i]
	rci.queue_redraw()


func _refresh_windows() -> void:
	if lines_panel.visible:
		_refresh_lines()
	if policy_panel.visible:
		_refresh_policies()
	if advisor_panel.visible:
		_refresh_advisors()
	if paper_panel.visible:
		_refresh_paper()
		paper_btn.text = ""
	if disaster_panel.visible:
		(disaster_panel.get_meta("freq") as OptionButton).select(city.random_disasters)
	if budget_panel.visible:
		_refresh_budget()
	if stats_panel.visible:
		_refresh_stats()
	if land_panel.visible:
		_refresh_land()
	if region_panel.visible:
		_refresh_region()
	if subsidy_panel.visible:
		_refresh_subsidies()
	if space_panel.visible:
		_refresh_space()
	if gov_panel.visible:
		_refresh_gov()
	if ach_panel.visible:
		_refresh_achievements()
	main.overlays.set_land_view(land_panel.visible)


func on_month() -> void:
	_refresh_windows()
