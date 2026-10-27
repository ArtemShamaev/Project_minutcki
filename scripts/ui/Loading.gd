extends CanvasLayer
## Loading screen: a picture of a city with a slow camera drift, the game title,
## what is being built right now, a progress bar and tips that change every few seconds.

const BACKS := ["res://assets/loading/bg1.jpg", "res://assets/loading/bg2.jpg", "res://assets/loading/bg3.jpg",
	"res://assets/loading/bg4.jpg", "res://assets/loading/bg5.jpg"]
const TIPS := [
	"Тяните дороги от шоссе на западе — по нему в город приезжают новые жители.",
	"Канализационный сток ставится у воды и загрязняет её ниже по течению. Насосы держите выше.",
	"Пути, выведенные за край карты, связывают вокзал с внешним миром: приедут туристы.",
	"В окне «Правительство» [U] открываются министерства: каждое даёт бонус и открывает здания раньше.",
	"УГК [K]: снабжение на стартовые столы везут грузовики с заводов. Сначала — испытательные пуски!",
	"Клавиша V — вид с улицы. H прячет интерфейс, F12 сохраняет скриншот.",
	"Пробки? Проспект пропускает вдвое больше машин, а метро и трамвай разгружают улицы.",
	"Высокие налоги отпугивают жителей. Следите за спросом RCI в верхней панели.",
	"Деревья снижают загрязнение и шум и повышают стоимость земли.",
	"Купить новые участки земли можно в меню «Участки» (клавиша L).",
	"После дождя асфальт блестит, а на дорогах стоят лужи.",
	"Министерство туризма и знаменитые здания мира привлекают туристов со всего региона.",
	"Соседние города продают электричество и воду: окно «Регион» (G).",
	"Чем образованнее жители, тем охотнее растут офисы и тем выше уровень домов.",
	"На Луне добывают гелий-3. Гелиевая электростанция даёт 6 000 МВт без дыма.",
]

var active := true            # off in screenshot runs: everything loads at once
var root: Control
var back: TextureRect
var title: Label
var sub: Label
var stage: Label
var tip: Label
var bar: ProgressBar
var spinner: Control
var _tip_t := 0.0
var _shown := false
var _t := 0.0
var _target := 0.0
var _fade: Tween


func _ready() -> void:
	layer = 100
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	back = TextureRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)
	# darken towards the bottom so the text reads well
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.15))
	gr.set_color(1, Color(0.02, 0.03, 0.06, 0.92))
	gr.add_point(0.45, Color(0, 0, 0, 0.1))
	gt.gradient = gr
	gt.width = 4
	gt.height = 256
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 60
	box.offset_right = -60
	box.offset_bottom = -48
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	title = _lbl("BS: Cities", 54, Color(1, 1, 1))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	box.add_child(title)
	sub = _lbl("", 22, Color(0.8, 0.88, 1.0))
	box.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	spinner = Control.new()
	spinner.custom_minimum_size = Vector2(22, 22)
	spinner.draw.connect(_draw_spinner)
	row.add_child(spinner)
	stage = _lbl("", 17, Color(0.95, 0.95, 0.95))
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stage)
	box.add_child(row)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.show_percentage = false
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(1, 1, 1, 0.12)
	bgs.set_corner_radius_all(5)
	var fgs := StyleBoxFlat.new()
	fgs.bg_color = Color(0.36, 0.66, 1.0)
	fgs.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bgs)
	bar.add_theme_stylebox_override("fill", fgs)
	box.add_child(bar)
	tip = _lbl("", 15, Color(0.75, 0.8, 0.88))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	root.visible = false


func _lbl(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	return l


func _draw_spinner() -> void:
	var c := spinner.size * 0.5
	for k in 8:
		var a := _t * 6.0 + k * TAU / 8.0
		var al := 0.15 + 0.85 * float(k) / 8.0
		spinner.draw_circle(c + Vector2(cos(a), sin(a)) * 8.0, 2.4, Color(1, 1, 1, al))


func show_screen(subtitle: String) -> void:
	if not active:
		return
	_shown = true
	_t = 0.0
	if _fade:
		_fade.kill()
	back.texture = load(BACKS[randi() % BACKS.size()])
	back.scale = Vector2.ONE
	back.pivot_offset = root.get_viewport_rect().size * 0.5
	sub.text = subtitle
	stage.text = ""
	bar.value = 0.0
	_target = 0.0
	_next_tip()
	root.modulate.a = 1.0
	root.visible = true


func set_progress(p: float, text: String) -> void:
	_target = clampf(p, 0.0, 1.0) * 100.0
	stage.text = text


func busy() -> bool:
	return _shown


func hide_screen() -> void:
	if not _shown:
		return
	_shown = false
	_target = 100.0
	_fade = create_tween()
	_fade.tween_property(root, "modulate:a", 0.0, 0.6).set_delay(0.15)
	_fade.tween_callback(func(): root.visible = false)


func _next_tip() -> void:
	tip.text = "💡 " + TIPS[randi() % TIPS.size()]
	_tip_t = 5.0


func _process(delta: float) -> void:
	if not root.visible:
		return
	_t += delta
	# the bar never jumps: it eases towards the reported progress
	bar.value = move_toward(bar.value, _target, maxf(delta * 160.0, absf(_target - bar.value) * delta * 6.0))
	back.scale = Vector2.ONE * (1.0 + minf(_t * 0.004, 0.08))
	spinner.queue_redraw()
	_tip_t -= delta
	if _tip_t <= 0.0:
		_next_tip()
