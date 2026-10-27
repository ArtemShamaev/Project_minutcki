extends Node
## Music (generated in a background thread) and city ambience.

signal track_changed(name: String)

static var siren_stream: AudioStreamWAV
static var horn_stream: AudioStreamWAV
static var sfx_volume := 0.8

var main
var music: AudioStreamPlayer
var hum: AudioStreamPlayer
var wind: AudioStreamPlayer
var birds: Array = []
var bird_player: AudioStreamPlayer
var tracks: Array = []          # rendered AudioStreamWAV (null until ready)
var current := -1
var music_volume := 0.6
var music_on := true
var _thread: Thread
var _mutex := Mutex.new()
var _ready_tracks := {}
var _bird_t := 3.0
var rng := RandomNumberGenerator.new()


func setup(m) -> void:
	main = m
	rng.randomize()
	music = AudioStreamPlayer.new()
	music.finished.connect(_next_track)
	add_child(music)
	hum = AudioStreamPlayer.new()
	hum.stream = Synth.noise_loop(4.0, 0.06, 4.0)
	hum.volume_db = -80
	add_child(hum)
	hum.play()
	wind = AudioStreamPlayer.new()
	wind.stream = Synth.noise_loop(3.0, 0.25, 2.5)
	wind.volume_db = -80
	add_child(wind)
	wind.play()
	bird_player = AudioStreamPlayer.new()
	add_child(bird_player)
	for i in 4:
		birds.append(Synth.bird())
	siren_stream = Synth.siren()
	horn_stream = Synth.horn()
	tracks.resize(Synth.TRACKS.size())
	_load_settings()
	_thread = Thread.new()
	_thread.start(_render_all)


func _render_all() -> void:
	var order := range(Synth.TRACKS.size())
	for i in order:
		var s := Synth.render_track(i)
		_mutex.lock()
		_ready_tracks[i] = s
		_mutex.unlock()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		music_volume = float(cf.get_value("audio", "music", 0.6))
		sfx_volume = float(cf.get_value("audio", "sfx", 0.8))
		music_on = bool(cf.get_value("audio", "music_on", true))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("audio", "music_on", music_on)
	cf.save("user://settings.cfg")


func set_music_volume(v: float) -> void:
	music_volume = v
	music.volume_db = linear_to_db(max(v, 0.001)) - 4.0
	save_settings()


func current_name() -> String:
	return Synth.TRACKS[current].name if current >= 0 else "…"


func _next_track() -> void:
	var avail: Array = []
	for i in tracks.size():
		if tracks[i] != null and i != current:
			avail.append(i)
	if avail.is_empty():
		if current >= 0 and tracks[current] != null:
			avail.append(current)
		else:
			return
	current = avail[rng.randi() % avail.size()]
	music.stream = tracks[current]
	music.volume_db = linear_to_db(max(music_volume, 0.001)) - 4.0
	if music_on:
		music.play()
	track_changed.emit(current_name())


func skip() -> void:
	_next_track()


func _process(delta: float) -> void:
	Prof.b("audio")
	_process_inner(delta)
	Prof.e("audio")


func _process_inner(delta: float) -> void:
	# pick up rendered tracks
	_mutex.lock()
	for i in _ready_tracks:
		tracks[i] = _ready_tracks[i]
	_ready_tracks.clear()
	_mutex.unlock()
	if music_on and not music.playing and current < 0:
		_next_track()
	if not music_on and music.playing:
		music.stop()
	var city: City = main.city
	if city == null or main.rig == null:
		return
	var rig = main.rig
	var near: float = clamp(1.0 - (rig.dist - 4.0) / 40.0, 0.0, 1.0)
	# city hum follows traffic around the camera focus
	var fx := int(rig.focus.x)
	var fz := int(rig.focus.z)
	var tr := 0.0
	var built := 0
	for dz in range(-6, 7, 2):
		for dx in range(-6, 7, 2):
			var x := fx + dx
			var z := fz + dz
			if city.inb(x, z):
				var i := city.idx(x, z)
				tr += city.traffic[i]
				if city.bld[i] != -1 or city.road[i] > 0:
					built += 1
	var activity: float = clamp(tr / 60.0 + built / 49.0 * 0.5, 0.0, 1.0)
	var hv: float = (0.15 + near * 0.85) * activity * sfx_volume
	hum.volume_db = lerp(hum.volume_db, linear_to_db(max(hv * 0.5, 0.0001)), clamp(delta * 2.0, 0.0, 1.0))
	# tornado wind
	var windy := 0.0
	if main.disasters:
		for d in main.disasters.active:
			if d.kind == "tornado":
				windy = 1.0
	wind.volume_db = lerp(wind.volume_db, linear_to_db(max(windy * sfx_volume * 0.9, 0.0001)), clamp(delta, 0.0, 1.0))
	# birds during the day near trees/parks
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = rng.randf_range(2.5, 7.0)
		var night: float = main.night
		var green := 0
		for dz in range(-4, 5, 2):
			for dx in range(-4, 5, 2):
				if city.inb(fx + dx, fz + dz) and city.tree[city.idx(fx + dx, fz + dz)] == 1:
					green += 1
		if night < 0.5 and near > 0.3 and (green > 2 or city.avg_happiness > 60) and Sfx.enabled:
			bird_player.stream = birds[rng.randi() % birds.size()]
			bird_player.volume_db = linear_to_db(near * sfx_volume * 0.5 + 0.001)
			bird_player.pitch_scale = rng.randf_range(0.9, 1.15)
			bird_player.play()
