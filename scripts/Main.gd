extends Node3D
## Entry point: environment, world creation, game loop, save/load, menus.

const TerrainR := preload("res://scripts/render/Terrain.gd")
const RoadR := preload("res://scripts/render/RoadRenderer.gd")
const BuildingR := preload("res://scripts/render/BuildingRenderer.gd")
const OverlaysR := preload("res://scripts/render/Overlays.gd")
const TrafficR := preload("res://scripts/render/Traffic.gd")
const TransitR := preload("res://scripts/render/TransitRenderer.gd")
const DisastersR := preload("res://scripts/render/Disasters.gd")
const PedsR := preload("res://scripts/render/Pedestrians.gd")
const PathsR := preload("res://scripts/render/PathRenderer.gd")
const RailR := preload("res://scripts/render/RailRenderer.gd")
const TrainsR := preload("res://scripts/render/Trains.gd")
const AudioM := preload("res://scripts/render/AudioManager.gd")
const ToolsC := preload("res://scripts/world/ToolController.gd")
const RigC := preload("res://scripts/world/CameraRig.gd")
const UIC := preload("res://scripts/ui/UI.gd")
const LoadingC := preload("res://scripts/ui/Loading.gd")

const SPEEDS := [0.0, 1.0, 2.5, 6.0]
const SAVE_PATH := "user://city_save.dat"
const AUTOSAVE_PATH := "user://autosave.dat"

var city: City
var world: Node3D
var terrain
var roads
var brender
var overlays
var traffic
var transit
var disasters
var peds
var paths
var rails
var trains
var audio
var tools
var rig
var ui
var sun: DirectionalLight3D
var _tilt_pref := true
var _street_icons := false
var env: Environment
var sky_mat: ShaderMaterial
var loading
var _loading_world := false
var _shadow_cap := 0.0                # debug: fixed shadow distance     # world is being rebuilt: skip the simulation and the UI
var _wet := 0.0
var _cloud_off := Vector2.ZERO
var speed := 1
var _prev_speed := 1
var _acc := 0.0
var in_game := false
var menu_pause := false
var quality := 1
var night := 0.0
var _sky_k := -1.0
var _sky_t := 0.0
var _sky_e := 0.0
var precip: GPUParticles3D
var _rain_k := 0.0
var _snow_vis := 0.0


func _ready() -> void:
	Models.init()
	Sfx.init(self)
	_setup_env()
	rig = RigC.new()
	add_child(rig)
	ui = UIC.new()
	add_child(ui)
	audio = AudioM.new()
	add_child(audio)
	audio.setup(self)
	ui.setup(self)
	ui.new_game_requested.connect(new_game)
	ui.continue_requested.connect(func(): load_game(latest_save()))
	ui.save_requested.connect(save_game)
	ui.load_requested.connect(func(): load_game())
	ui.menu_requested.connect(_to_menu)
	ui.speed_requested.connect(set_speed)
	loading = LoadingC.new()
	add_child(loading)
	loading.active = OS.get_environment("BS_SHOT") == "" or OS.get_environment("BS_LOADING") != ""
	if OS.get_environment("BS_LOADSHOT") != "":
		# debug: picture of the loading screen at start-up
		get_tree().create_timer(float(OS.get_environment("BS_LOADSHOT"))).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(OS.get_environment("BS_LOADPNG"))
			get_tree().quit())
	_to_menu()
	if OS.get_environment("BS_SHOT") != "":
		_debug_run()


## Debug helper: BS_SHOT=<png path>, BS_SCENE=menu|game|night, BS_WAIT=<sec>.
func _debug_run() -> void:
	while city == null or _loading_world:
		await get_tree().process_frame
	var scene := OS.get_environment("BS_SCENE")
	var wait := float(OS.get_environment("BS_WAIT")) if OS.get_environment("BS_WAIT") != "" else 3.0
	if scene == "game" or scene == "night":
		in_game = true
		ui.show_menu(false)
		rig.orbit = false
		rig.set_focus(Vector3(28, 0, city.n / 2), 22.0)
		rig.t_yaw = deg_to_rad(-35)
		rig.t_pitch = deg_to_rad(48)
		set_speed(1)
		if scene == "night":
			city.day = int(Defs.DAY_CYCLE * 0.62)
	var cmd := OS.get_environment("BS_CMD")
	if cmd != "":
		await get_tree().create_timer(0.5).timeout
		_debug_cmd(cmd)
	await get_tree().create_timer(wait).timeout
	if OS.get_environment("BS_END") != "":
		_debug_cmd(OS.get_environment("BS_END"))
	Prof.enabled = true
	Prof.acc.clear()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	if OS.get_environment("BS_NOFPS") == "":
		await get_tree().create_timer(3.0).timeout
	else:
		await get_tree().process_frame
	var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
	get_viewport().get_texture().get_image().save_png(OS.get_environment("BS_SHOT"))
	print("PROF ", Prof.report(Engine.get_frames_drawn() - f0))
	var vrid := get_viewport().get_viewport_rid()
	print("GPU ms: ", RenderingServer.viewport_get_measured_render_time_gpu(vrid), " CPU render ms: ", RenderingServer.viewport_get_measured_render_time_cpu(vrid))
	print("process ms: ", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, " prims: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("FPS: ", fps, " draw calls: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " objects: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), " cars: ", traffic.cars.size(), " buildings: ", city.buildings.size(), " pop: ", city.population, " peds: ", peds.peds.size(), " walk: ", city.walk_share)
	get_tree().quit()


func _focus_crossing() -> void:
	await get_tree().create_timer(1.0).timeout
	for i in rails.crossings:
		rig.set_focus(Vector3(i % city.n + 0.5, 0, i / city.n + 0.5), rig.t_dist)
		rig.focus = Vector3(i % city.n + 0.5, 0, i / city.n + 0.5)
		return


func _follow_train(kind: String) -> void:
	for k in 80:
		for tr in trains.trains:
			if tr.cars[0].visible and tr.v > 0.5 and (kind == "" or tr.kind == kind):
				rig.follow = tr.cars[0]
				print("train ", tr.kind, " cars ", tr.cars.size())
				return
		await get_tree().create_timer(0.25).timeout


func _debug_cmd(cmd: String) -> void:
	for part in cmd.split(";"):
		var a := part.strip_edges().split(" ")
		match a[0]:
			"cat": ui._select_category(a[1])
			"overlay": ui.set_overlay(a[1]); ui.overlay_panel.visible = true
			"budget": ui._toggle(ui.budget_panel)
			"advisors": ui._toggle(ui.advisor_panel)
			"paper":
				ui._publish_paper()
				ui._toggle(ui.paper_panel)
			"policies": ui._toggle(ui.policy_panel)
			"stats": ui._toggle(ui.stats_panel)
			"zoom": rig.t_dist = float(a[1])
			"hideui": ui.root.visible = false
			"yaw": rig.t_yaw = deg_to_rad(float(a[1]))
			"pitch": rig.t_pitch = deg_to_rad(float(a[1]))
			"followtrain":
				_follow_train(a[1] if a.size() > 1 else "")
			"crossing": _focus_crossing()
			"tod": city.day = int(Defs.DAY_CYCLE) * (city.day / int(Defs.DAY_CYCLE) + 1) + int(Defs.DAY_CYCLE * float(a[1]))
			"pause": set_speed(0)
			"fx":
				match a[1]:
					"ssao": env.ssao_enabled = a[2] == "1"
					"glow": env.glow_enabled = a[2] == "1"
					"fog": env.fog_enabled = a[2] == "1"
					"shadow": _shadow_cap = float(a[2])
					"wet": _wet = 1.0; _rain_k = 1.0
			"newgame": new_game({"name": "Тестоград"})
			"noon": city.day = int(Defs.DAY_CYCLE) * (city.day / int(Defs.DAY_CYCLE) + 1) + int(Defs.DAY_CYCLE * 0.2)
			"focus": rig.set_focus(Vector3(float(a[1]), 0, float(a[2])), rig.t_dist)
			"yaw": rig.t_yaw = deg_to_rad(float(a[1]))
			"pitch": rig.t_pitch = deg_to_rad(float(a[1]))
			"select":
				for b: Building in city.buildings.values():
					if b.type == a[1] or (a[1] == "zone" and b.type == "zone" and b.build_days == 0):
						tools.select(b)
						break
			"tool":
				if a[1] == "service": tools.set_tool({"type": "service", "id": a[2]})
				elif a[1] == "zone": tools.set_tool({"type": "zone", "zone": int(a[2])})
				else: tools.set_tool({"type": a[1]})
			"newgame": new_game()
			"newgame2": new_game({"name": "Тестоград", "map": a[1], "difficulty": 1, "seed": int(a[2])})
			"newgametut": new_game({"name": "Тестоград", "tutorial": true})
			"ngpanel": ui._toggle(ui.newgame_panel)
			"road":
				ui._on_road(Vector2i(int(a[1]), int(a[2])))
			"drag":
				# drag <tool> x1 y1 x2 y2  (simulates mouse drag through the tool controller)
				tools.hover = Vector2i(int(a[2]), int(a[3]))
				tools._press()
				tools.hover = Vector2i(int(a[4]), int(a[5]))
				if tools.tool.type == "road":
					var rr: Dictionary = city.check_roads(city.road_path(tools.drag_start, tools.hover), tools.tool.get("rtype", 1))
					if not rr.ok:
						print("road failed: ", rr.reason)
				tools._release()
			"place":
				tools.set_tool({"type": "service", "id": a[1]})
				tools.hover = Vector2i(int(a[2]), int(a[3]))
				var pr: Dictionary = city.service_placement(a[1], tools.hover, -1)
				if not pr.ok:
					print("place ", a[1], " failed: ", pr.reason)
				tools._press()
				tools.set_tool({"type": "select"})
			"money": city.money = float(a[1])
			"spec": city.set_district_spec(int(a[1]), a[2] if a.size() > 2 else "")
			"budget_set": city.budget[a[1]] = int(a[2])
			"noui": ui.root.visible = false
			"zonerect": city.paint_zone(Rect2i(int(a[1]), int(a[2]), int(a[3]), int(a[4])), int(a[5]))
			"gallery":
				# gallery x y path1,path2,...  — models in a row, 1.5 tiles apart, front facing -Z
				var gx := float(a[1])
				var gz := float(a[2])
				var k := 0
				for path in a[3].split(","):
					var m: Node3D = Models.fit(path, Vector2(1.2, 1.2), 0, 99.0)
					m.position = Vector3(gx + (k % 6) * 1.6, city.height_at(gx, gz) + 0.02, gz + (k / 6) * 1.8)
					world.add_child(m)
					print(k, " ", path, " h ", m.get_meta("height"), " aabb ", Models.aabb(path).size)
					k += 1
			"trstat":
				var vals: Array = []
				for i in city.n * city.n:
					if city.road[i] > 0:
						vals.append(city.traffic[i])
				vals.sort()
				print("TRAFFIC n=", vals.size(), " p50=", vals[vals.size() / 2], " p90=", vals[int(vals.size() * 0.9)], " max=", vals[-1])
			"hide":
				match a[1]:
					"shadows": sun.shadow_enabled = false
					"trees": terrain.trees_root.visible = false
					"forest":
						for ch in terrain.get_children():
							if ch is MultiMeshInstance3D:
								ch.visible = false
					"particles":
						for p in get_tree().root.find_children("*", "GPUParticles3D", true, false):
							p.visible = false
					"buildings": brender.visible = false
					"roads": roads.visible = false
					"cars": traffic.visible = false
					"glow": env.glow_enabled = false
			"noproc":
				var nodes := {"traffic": traffic, "tools": tools, "rig": rig, "ui": ui, "audio": audio, "brender": brender, "peds": peds, "transit": transit, "terrain": terrain, "disasters": disasters, "sim": self}
				if a[1] == "sim":
					menu_pause = true
				else:
					nodes[a[1]].set_process(false)
			"milestone": city.milestone = int(a[1])
			"hover": tools.set_meta("debug_hover", Vector2i(int(a[1]), int(a[2])))
			"pickcar":
				if traffic.cars.size() > 0:
					tools.selected_agent = traffic.cars[0]
					tools.agent_selected.emit(traffic.cars[0])
					rig.follow = traffic.cars[0].node
			"chirp":
				for k in int(a[1]):
					ui.add_chirp()
				ui._toggle_chirper()
			"focusbus":
				var bi := clampi(int(a[1]) if a.size() > 1 else 0, 0, max(0, transit.buses.size() - 1))
				if transit.buses.size() > 0:
					var bp: Vector3 = transit.buses[bi].pos
					rig.set_focus(bp, rig.t_dist)
					rig.focus = bp
					print("bus at ", bp, " buses ", transit.buses.size())
			"focusped":
				var bi := clampi(int(a[1]) if a.size() > 1 else 0, 0, max(0, peds.peds.size() - 1))
				if peds.peds.size() > 0:
					var pp: Vector3 = peds.peds[bi].node.position
					rig.set_focus(pp, rig.t_dist)
					rig.focus = pp
					rig.follow = peds.peds[bi].node
					print("ped at ", pp, " ", peds.peds[bi].purpose)
			"style": city.set_style(int(a[1]), a[2], true)
			"street": rig.set_street(true)
			"land": ui._toggle(ui.land_panel)
			"region": ui._toggle(ui.region_panel)
			"spacesetup":
				# quick space program for screenshots: agency, pad, control centre, some research
				city.milestone = 6
				city.money = 1e8
				var hh: Building = city.hall()
				if hh:
					hh.ministries.append("science")
				for t in ["dsa_hq", "launchpad", "mission_control", "rocket_factory", "astro_center", "observatory"]:
					var done := false
					for r in 40:
						for dy in range(-r, r + 1):
							for dx in range(-r, r + 1):
								var sp2 := Vector2i(int(rig.focus.x) + dx, int(rig.focus.z) + dy)
								if not done and city.service_placement(t, sp2, -1).ok:
									city.place_service(t, sp2, -1)
									done = true
				city.space.researched["manned"] = true
				city.space.done["test"] = 2
				city.space.supplies = 5000.0
				city.space.astronauts = 3
				city.space.done["weather"] = 1
				city.space.done["comsat"] = 2
				city.space.target = "station"
				city.space.progress = 50.0
			"space": ui._toggle(ui.space_panel)
			"ach": ui._toggle(ui.ach_panel)
			"subsidy": ui._toggle(ui.subsidy_panel)
			"gov":
				# gov <level> <ministries...>: set up the city hall for testing
				var hb: Building = city.hall()
				if hb == null:
					city.money = 1e8
					for r in 30:
						for dy in range(-r, r + 1):
							for dx in range(-r, r + 1):
								var gp := Vector2i(int(rig.focus.x) + dx, int(rig.focus.z) + dy)
								if hb == null and city.service_placement("cityhall", gp, -1).ok:
									hb = city.place_service("cityhall", gp, -1)
				if hb:
					hb.level = int(a[1])
					for k2 in range(2, a.size()):
						if not a[k2] in hb.ministries:
							hb.ministries.append(a[k2])
					city.building_updated.emit(hb)
					rig.set_focus(hb.center(), rig.t_dist)
			"deal": city.region.deals[a[1]] = true
			"colony":
				# colony <moon|mars> [tab]: open a colony with a few buildings for screenshots
				city.money = 1e8
				city.space.done["moonbase"] = 1
				city.space.open_colony(city, a[1])
				var col: Dictionary = city.space.colonies[a[1]]
				var plan := {2: "mine", 3: "ice", 0: "solar"}
				var placed := {"mine": 0, "ice": 0, "solar": 0, "hab": 0}
				for i in col.tiles.size():
					var t: int = col.tiles[i]
					if plan.has(t) and placed[plan[t]] < (2 if t > 0 else 3) and city.space.colony_build(city, a[1], i, plan[t]):
						placed[plan[t]] += 1
				for i in col.tiles.size():
					if placed.hab < 3 and city.space.colony_build(city, a[1], i, "hab"):
						placed.hab += 1
				for bid in ["port", "lab"]:
					for i in range(col.tiles.size() - 1, -1, -1):
						if city.space.colony_build(city, a[1], i, bid):
							break
				ui.space_tab = "moon" if a[1] == "moon" else "mars"
				ui._toggle(ui.space_panel)
			"govwin": ui._toggle(ui.gov_panel)
			"railsetup":
				# a straight line from the west edge with a station and a cargo station, plus a branch for screenshots
				city.milestone = 6
				city.money = 1e8
				var built := false
				for dy in 40:
					for sgn in [1, -1]:
						var ry: int = int(rig.focus.z) + dy * sgn
						if built or ry < 2 or ry > city.n - 3:
							continue
						var cells := city.road_path(Vector2i(0, ry), Vector2i(int(rig.focus.x) + 14, ry), 0)
						if city.check_rails(cells).ok:
							city.build_rails(cells)
							built = true
							rig.set_focus(Vector3(rig.focus.x, 0, ry), rig.t_dist)
							rig.focus = Vector3(rig.focus.x, 0, ry)
							for cx in range(int(rig.focus.x) - 14, int(rig.focus.x) + 12):
								var rc := city.road_path(Vector2i(cx, ry - 3), Vector2i(cx, ry + 3), 1)
								if city.build_roads(rc, 1):
									print("crossing road at ", cx)
									break
				for t in ["train_station", "cargo_station"]:
					var ok := false
					for r in 30:
						for dx in range(-r, r + 1):
							for dy2 in [-2, 2, -3, 3]:
								var sp3 := Vector2i(int(rig.focus.x) + dx, int(rig.focus.z) + dy2)
								if not ok and city.service_placement(t, sp3, -1).ok:
									city.place_service(t, sp3, -1)
									ok = true
					print("rail ", built, " ", t, " ", ok)
			"mega":
				# mega <type> <stage>: place a megaproject near the camera focus at a given stage
				city.milestone = 6
				city.money = 1e8
				var mb: Building = null
				for r in 30:
					for dy in range(-r, r + 1):
						for dx in range(-r, r + 1):
							var mp := Vector2i(int(rig.focus.x) + dx, int(rig.focus.z) + dy)
							if mb == null and city.service_placement(a[1], mp, -1).ok:
								mb = city.place_service(a[1], mp, -1)
				if mb:
					mb.stage = int(a[2])
					city.building_updated.emit(mb)
					rig.set_focus(mb.center(), rig.t_dist)
					print("mega at ", mb.x, ",", mb.y)
			"disaster": disasters.trigger(a[1])
			"focusdis":
				for d in disasters.active:
					if d.has("pos"):
						var dp: Vector2 = d.pos
						rig.set_focus(Vector3(dp.x, 0, dp.y), rig.t_dist)
						break
			"weather":
				city.weather = a[1]
				city.weather_days = 30
				if a[1] == "snow":
					city.snow_cover = 1.0
					_snow_vis = 1.0
					_rain_k = 1.0
			"save": save_game()
			"load": load_game()
			"pause": ui.toggle_pause_menu()
			"speed": set_speed(int(a[1]))
			"days":
				for i in int(a[1]): city.tick_day()
			"fire":
				for b: Building in city.buildings.values():
					if b.type == "zone" and b.build_days == 0:
						city._ignite(b)
						break


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var nt := NoiseTexture2D.new()
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	nt.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.012
	fn.fractal_octaves = 4
	nt.noise = fn
	sky_mat.set_shader_parameter("noise_tex", nt)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.08
	env.fog_aerial_perspective = 0.55
	env.fog_sun_scatter = 0.15
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.0
	sun.light_energy = 1.35
	sun.light_angular_distance = 0.6
	sun.rotation_degrees = Vector3(-50, -40, 0)
	add_child(sun)
	var q := OS.get_environment("BS_Q")
	apply_quality(int(q) if q != "" else _load_quality())


func _load_quality() -> int:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		Sfx.enabled = bool(cf.get_value("audio", "enabled", true))
		return int(cf.get_value("video", "quality", 1))
	return 1


func set_sound(on: bool) -> void:
	Sfx.enabled = on
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("audio", "enabled", on)
	cf.save("user://settings.cfg")


## 0 = low, 1 = medium, 2 = high, 3 = ultra
func apply_quality(q: int) -> void:
	quality = q
	var vp := get_viewport()
	# ambient occlusion: half resolution on high, full + indirect light on ultra
	env.ssao_enabled = q >= 2
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW if q <= 2 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, q <= 2, 0.5, 2, 50, 300)
	env.ssil_enabled = q >= 3
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.8
	# glow: on medium only the wide, cheap levels (city lights at night still bloom)
	env.glow_enabled = q >= 1
	for lv in 7:
		env.set_glow_level(lv, (lv >= 2 and lv <= 4) if q == 1 else (lv >= 1 and lv <= 4))
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 48 if q >= 3 else 32
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	# light shafts through the haze on ultra
	env.volumetric_fog_enabled = q >= 3
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_sky_affect = 0.0
	if rig:
		rig.tilt_shift = q >= 2 and _tilt_pref
		rig._update_dof()
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [45.0, 55.0, 80.0, 110.0][q]
	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 8192][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if q >= 2 else Viewport.SCREEN_SPACE_AA_FXAA
	# low: render at 75% and upscale with FSR (sharper than plain stretching)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q == 0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.75 if q == 0 else 1.0
	vp.fsr_sharpness = 0.4
	if ui and ui.vignette:
		ui.vignette.visible = q >= 1
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("video", "quality", q)
	cf.save("user://settings.cfg")


# ------------------------------------------------------------------ world
## Loading screen step: show what is being built and let a frame be drawn.
func _ls(p: float, text: String) -> void:
	if loading == null or not loading.busy():
		return
	loading.set_progress(p, text)
	await get_tree().process_frame
	await get_tree().process_frame


func _create_world(c: City, p0: float = 0.2) -> void:
	_loading_world = true
	var span := 0.95 - p0
	if world:
		world.free()
	if traffic:
		traffic = null
	city = c
	world = Node3D.new()
	world.name = "World"
	# renderers start working only when everything is set up
	world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(world)
	terrain = TerrainR.new()
	roads = RoadR.new()
	brender = BuildingR.new()
	overlays = OverlaysR.new()
	traffic = TrafficR.new()
	transit = TransitR.new()
	disasters = DisastersR.new()
	peds = PedsR.new()
	paths = PathsR.new()
	rails = RailR.new()
	trains = TrainsR.new()
	tools = ToolsC.new()
	for n in [terrain, roads, paths, rails, trains, brender, overlays, traffic, transit, disasters, peds, tools]:
		world.add_child(n)
	await _ls(p0 + span * 0.05, "Укладываем землю, реки и леса…")
	terrain.setup(c)
	terrain.rebuild_all()
	await _ls(p0 + span * 0.3, "Прокладываем дороги, дорожки и рельсы…")
	roads.setup(c)
	roads.rebuild_all()
	paths.setup(c)
	paths.rebuild_all()
	rails.setup(c)
	rails.rebuild_all()
	trains.setup(c, rails)
	traffic.trains = trains
	await _ls(p0 + span * 0.5, "Строим дома, заводы и %d зданий…" % c.buildings.size())
	brender.setup(c)
	brender.rebuild_all()
	await _ls(p0 + span * 0.8, "Выпускаем машины, автобусы и поезда…")
	overlays.setup(c)
	overlays.refresh_zones()
	overlays.refresh_districts()
	traffic.setup(c)
	transit.setup(c)
	transit.rebuild_all()
	disasters.setup(c, rig, terrain)
	await _ls(p0 + span * 0.9, "Будим горожан…")
	peds.setup(c)
	peds.traffic = traffic
	traffic.peds = peds
	peds.transit = transit
	c.space.launched.connect(func(pad_id, _ok): brender.launch_from(pad_id))
	c.space.exploded.connect(func(pad_id): brender.explode_at(pad_id))
	c.space.orbit_changed.connect(func(): brender.update_orbiters(c.space.orbiters()))
	brender.update_orbiters(c.space.orbiters())
	rig.follow = null
	disasters.happened.connect(_on_disaster)
	tools.setup(c, rig, overlays, terrain, brender)
	tools.action_done.connect(_on_action)
	tools.traffic = traffic
	tools.peds = peds
	ui.rebind(c, tools)
	c.day_passed.connect(func():
		if c.day % Defs.DAYS_PER_MONTH == 0:
			ui.on_month()
			if in_game and (c.day / Defs.DAYS_PER_MONTH) % 3 == 0:
				save_game(AUTOSAVE_PATH))
	rig.bounds = Rect2(0, 0, c.n, c.n)
	rig.city = c
	rig.tilt_shift = quality >= 2 and _tilt_pref
	rig.street = false
	_acc = 0.0
	_loading_world = false
	world.process_mode = Node.PROCESS_MODE_INHERIT


func _on_action(kind: String) -> void:
	match kind:
		"place": Sfx.play("place")
		"road": Sfx.play("road")
		"zone": Sfx.play("zone", -8.0)
		"bulldoze": Sfx.play("bulldoze")
		"error": Sfx.play("error", -6.0)
		"terraform": Sfx.play("bulldoze", -10.0)


func _screenshot() -> void:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = OS.get_user_data_dir()
	dir = dir.path_join("BS Cities")
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var path := dir.path_join("city_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	get_viewport().get_texture().get_image().save_png(path)
	Sfx.play("click", 0.0)
	if ui.root.visible:
		ui.add_notification("📷 Скриншот сохранён: " + path, "good")


func _on_disaster(kind: String, text: String) -> void:
	if not in_game:
		return
	ui.add_notification(text, "info" if kind.ends_with("_end") else "bad")
	if not kind.ends_with("_end"):
		city.log_event("disaster", "%s обрушилось на город" % Defs.DISASTERS[kind].name if kind == "earthquake" else "%s обрушился на город" % Defs.DISASTERS[kind].name if kind in ["tornado", "meteor"] else "%s в городе" % Defs.DISASTERS[kind].name,
			"Спасатели работают на месте. Всего пострадавших: %d." % city.casualties)
	if not kind.ends_with("_end"):
		Sfx.play("error", 0.0)
		ui.show_banner(text)


func new_game(params: Dictionary = {}) -> void:
	var nm: String = params.get("name", Defs.CITY_NAMES[randi() % Defs.CITY_NAMES.size()])
	loading.show_screen("Новый город «%s»" % nm)
	ui.show_menu(false)
	await _ls(0.05, "Поднимаем горы и наполняем реки…")
	var c := City.new()
	c.generate(int(params.get("seed", randi())), params.get("map", "river"))
	c.day = Defs.DAYS_PER_MONTH * 2   # start in spring
	c.city_name = nm
	c.difficulty = int(params.get("difficulty", 1))
	c.city_style = params.get("style", "modern")
	c.money = Defs.DIFFICULTY[c.difficulty].money
	if c.difficulty == 3:
		c.sandbox = true
		c.milestone = Defs.MILESTONES.size() - 1
	await _create_world(c)
	in_game = true
	menu_pause = false
	rig.orbit = false
	rig.set_focus(Vector3(10, 0, c.n / 2), 24.0)
	rig.t_yaw = deg_to_rad(-60)
	rig.t_pitch = deg_to_rad(50)
	ui.show_menu(false)
	set_speed(1)
	if params.get("tutorial", false):
		ui.start_tutorial()
	ui.add_notification("👋 Добро пожаловать в %s, мэр! Город соединён с шоссе на западе." % c.city_name, "good")
	ui.add_notification("🛣 Начните с дорог: «Дороги» внизу, затем тяните мышью от шоссе.", "info")
	ui.add_notification("🗺 Город стоит на двух участках земли. Новые участки покупаются по мере роста: «Снос и ландшафт» → «Участки» или клавиша L.", "info")
	ui.add_notification("🤝 Рядом три соседних города: торгуйте с ними электричеством и водой в окне «Регион» (G).", "info")
	ui.add_notification("🏘 Разметьте зоны вдоль дорог и обеспечьте электричество, воду и канализацию (сток ставится у воды).", "info")
	await _finish_loading()


## Let the deferred builders and shaders settle, then fade the loading screen out.
func _finish_loading() -> void:
	await _ls(0.97, "Последние штрихи…")
	await _ls(1.0, "Готово!")
	if loading.busy():
		await get_tree().create_timer(0.25).timeout
	loading.hide_screen()


func _to_menu() -> void:
	in_game = false
	menu_pause = false
	loading.show_screen("Главное меню" if city else "Запуск игры")
	await _ls(0.05, "Готовим демонстрационный город…")
	var c := City.new()
	c.generate(12345)
	_build_demo(c)
	await _create_world(c, 0.3)
	rig.orbit = true
	rig.set_focus(Vector3(26, 0, c.n / 2 + 2), 30.0)
	rig.t_pitch = deg_to_rad(38)
	rig.pitch = rig.t_pitch
	ui.show_menu(true, latest_save() != "")
	speed = 1
	await _finish_loading()


func _build_demo(c: City) -> void:
	Demo.build(c)
	c.day = int(Defs.DAY_CYCLE) * 4 + 10   # daytime


func set_speed(s: int) -> void:
	if s > 0:
		_prev_speed = s
	speed = s
	ui.set_speed(s)


func set_menu_pause(on: bool) -> void:
	menu_pause = on


# ------------------------------------------------------------------ save / load
func save_game(path: String = SAVE_PATH) -> void:
	if not in_game:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		ui.add_notification("Не удалось сохранить игру", "bad")
		return
	var d := city.to_dict()
	d["camera"] = [rig.t_focus, rig.t_yaw, rig.t_pitch, rig.t_dist]
	f.store_var(d)
	f.close()
	ui.add_notification("💾 Автосохранение" if path == AUTOSAVE_PATH else "💾 Игра сохранена", "info" if path == AUTOSAVE_PATH else "good")


func latest_save() -> String:
	var a := FileAccess.get_modified_time(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else -1
	var b := FileAccess.get_modified_time(AUTOSAVE_PATH) if FileAccess.file_exists(AUTOSAVE_PATH) else -1
	if a < 0 and b < 0:
		return ""
	return SAVE_PATH if a >= b else AUTOSAVE_PATH


func load_game(path: String = SAVE_PATH) -> void:
	if not FileAccess.file_exists(path):
		ui.add_notification("Нет сохранённой игры", "bad")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var d = f.get_var()
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		ui.add_notification("Файл сохранения повреждён", "bad")
		return
	loading.show_screen("Загрузка «%s»" % d.get("city_name", "города"))
	ui.show_menu(false)
	await _ls(0.1, "Читаем сохранение…")
	var c := City.new()
	c.from_dict(d)
	await _create_world(c)
	in_game = true
	menu_pause = false
	rig.orbit = false
	if d.has("camera"):
		var cm: Array = d.camera
		rig.set_focus(cm[0], cm[3])
		rig.t_yaw = cm[1]
		rig.t_pitch = cm[2]
	ui.show_menu(false)
	set_speed(1)
	ui.add_notification("📂 Игра загружена", "good")
	await _finish_loading()


# ------------------------------------------------------------------ input & loop
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	if _loading_world or (loading and loading.busy()):
		return
	if ui.in_menu() and k != KEY_F11:
		return
	if k == KEY_F12:
		_screenshot()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_H and in_game and not ui.pause_layer.visible:
		ui.root.visible = not ui.root.visible
		tools.visible = ui.root.visible
		get_viewport().set_input_as_handled()
		return
	if k == KEY_K and in_game:
		ui._toggle(ui.space_panel)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_U and in_game:
		ui._toggle(ui.gov_panel)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_J and in_game:
		ui._toggle(ui.ach_panel)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_G and in_game:
		ui._toggle(ui.region_panel)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_L and in_game:
		ui._toggle(ui.land_panel)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_V and in_game:
		rig.set_street(not rig.street)
		ui.add_notification("👀 Вид с улицы: WASD — идти, мышь с зажатой правой кнопкой — оглядеться, V — назад." if rig.street else "🏙 Обычный вид.", "info")
		get_viewport().set_input_as_handled()
		return
	if k == KEY_M and in_game:
		ui.minimap.visible = not ui.minimap.visible
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
		return
	match k:
		KEY_ESCAPE:
			if ui.pause_layer.visible:
				ui.toggle_pause_menu()
			elif not ui.cancel_tool():
				ui.toggle_pause_menu()
		KEY_SPACE:
			set_speed(0 if speed > 0 else _prev_speed)
		KEY_1: set_speed(1)
		KEY_2: set_speed(2)
		KEY_3: set_speed(3)
		KEY_B: tools.set_tool({"type": "bulldoze"})
		KEY_F5: save_game()
		KEY_F9: load_game()
		_: return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	Prof.b("main")
	_process_inner(delta)
	Prof.e("main")


func _process_inner(delta: float) -> void:
	if city == null or _loading_world:
		return
	var sim: float = 0.0 if menu_pause else (SPEEDS[speed] if in_game else 1.0)
	_acc += delta * sim
	var ticks := 0
	while _acc >= 1.0 and ticks < 4:
		_acc -= 1.0
		Prof.b("tick")
		city.tick_day()
		Prof.e("tick")
		ticks += 1
	if _acc > 1.0:
		_acc = 0.0
	traffic.time_scale = min(sim, 3.0)
	transit.time_scale = min(sim, 3.0)
	disasters.time_scale = sim
	peds.time_scale = min(sim, 3.0)
	trains.time_scale = min(sim, 3.0)
	terrain.water_speed = min(sim, 3.0)
	# street view: hide floating status icons (they would show through walls)
	if rig.street != _street_icons:
		_street_icons = rig.street
		for sp in brender.icons.values():
			if is_instance_valid(sp):
				sp.visible = not rig.street
	if OS.get_environment("BS_NODN") == "":
		_update_daynight()
	_update_weather_fx(delta)


func _make_precip() -> void:
	precip = GPUParticles3D.new()
	precip.amount = 1400
	precip.lifetime = 1.6
	precip.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 4.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3(0, -4, 0)
	precip.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.85, 0.95, 0.45)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	precip.draw_pass_1 = q
	precip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	precip.emitting = false
	add_child(precip)


func _update_weather_fx(delta: float) -> void:
	if precip == null:
		_make_precip()
	var w := city.weather
	var target_rain := 1.0 if w != "clear" else 0.0
	_rain_k = move_toward(_rain_k, target_rain, delta * 0.3)
	_snow_vis = move_toward(_snow_vis, city.snow_cover, delta * 0.2)
	RenderingServer.global_shader_parameter_set("snow", _snow_vis)
	RenderingServer.global_shader_parameter_set("clouds", 0.45 + 0.55 * _rain_k)
	# streets get wet in the rain and dry slowly afterwards
	_wet = move_toward(_wet, 1.0 if w == "rain" else 0.0, delta * (0.25 if w == "rain" else 0.02))
	RenderingServer.global_shader_parameter_set("wet", _wet)
	RenderingServer.global_shader_parameter_set("wind", 0.3 + 0.7 * _rain_k)
	var show: bool = w != "clear" and rig.dist < 60.0 and quality >= 1
	precip.emitting = show
	if show:
		precip.global_position = rig.focus + Vector3(0, 14, 0)
		var pm := precip.process_material as ParticleProcessMaterial
		var mat := (precip.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		if w == "snow":
			pm.initial_velocity_min = 1.2
			pm.initial_velocity_max = 2.0
			pm.gravity = Vector3(0.3, -0.6, 0)
			pm.spread = 25.0
			(precip.draw_pass_1 as QuadMesh).size = Vector2(0.09, 0.09)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.albedo_color = Color(1, 1, 1, 0.85)
			precip.lifetime = 8.0
		else:
			pm.initial_velocity_min = 9.0
			pm.initial_velocity_max = 12.0
			pm.gravity = Vector3(0, -4, 0)
			pm.spread = 4.0
			(precip.draw_pass_1 as QuadMesh).size = Vector2(0.025, 0.4)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			mat.albedo_color = Color(0.8, 0.85, 0.95, 0.45)
			precip.lifetime = 1.6


func _update_daynight() -> void:
	var t := fmod((city.day + _acc) / Defs.DAY_CYCLE + 0.3, 1.0)
	var a := (t - 0.25) * TAU
	var elev := sin(a) + 0.3                         # > 0 most of the cycle
	var day_k := smoothstep(-0.15, 0.35, elev)
	var sun_elev := deg_to_rad(lerp(35.0, 14.0 + 40.0 * clamp(elev, 0.0, 1.0), day_k))
	# shadows reach as far as the camera sees: farther when zoomed out
	var want_sd: float = clampf(rig.dist * 2.4, 40.0, [60.0, 90.0, 170.0, 220.0][quality]) if _shadow_cap <= 0.0 else _shadow_cap
	if absf(want_sd - sun.directional_shadow_max_distance) > want_sd * 0.12:
		sun.directional_shadow_max_distance = want_sd
	var az := a * 0.5 + deg_to_rad(-40)
	sun.rotation = Vector3(-sun_elev, az, 0)
	var warm := Color(1.0, 0.72, 0.48)
	var white := Color(1.0, 0.97, 0.92)
	var moon := Color(0.55, 0.65, 1.0)
	var dc := warm.lerp(white, smoothstep(0.15, 0.6, elev))
	sun.light_color = moon.lerp(dc, day_k)
	sun.light_energy = lerp(0.35, 1.35, day_k) * (1.0 - _rain_k * 0.45)
	night = clamp(1.0 - day_k * 1.15, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("night", night)
	# sky changes are expensive (radiance update): throttle them
	_sky_t -= get_process_delta_time()
	# clouds drift slowly; the sky (and its radiance) is refreshed at most every 0.5 s
	_cloud_off += Vector2(0.0006, 0.0003) * get_process_delta_time() * (1.0 + _rain_k)
	if _sky_t > 0.0:
		return
	_sky_t = 0.5
	_sky_k = day_k
	_sky_e = elev
	env.ambient_light_energy = lerp(0.35, 0.6, day_k)
	var golden := (1.0 - smoothstep(0.1, 0.5, elev)) * day_k
	var top := Color(0.03, 0.05, 0.13).lerp(Color(0.24, 0.46, 0.8), day_k)
	var hor := Color(0.1, 0.13, 0.24).lerp(Color(0.98, 0.66, 0.42).lerp(Color(0.72, 0.83, 0.95), smoothstep(0.1, 0.5, elev)), day_k)
	top = top.lerp(Color(0.42, 0.46, 0.52) * lerp(0.25, 1.0, day_k), _rain_k * 0.8)
	hor = hor.lerp(Color(0.55, 0.58, 0.62) * lerp(0.25, 1.0, day_k), _rain_k * 0.8)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(0.45))
	sky_mat.set_shader_parameter("day_k", day_k)
	sky_mat.set_shader_parameter("rain", _rain_k)
	sky_mat.set_shader_parameter("cover", 0.38 + 0.5 * _rain_k)
	sky_mat.set_shader_parameter("cloud_offset", _cloud_off)
	env.fog_light_color = hor.lerp(top, 0.3)
	env.fog_density = 0.0016 + _rain_k * 0.003
	# warm grading at sunrise / sunset, cooler and calmer at night
	env.adjustment_saturation = lerp(0.85, 1.08, day_k) + golden * 0.1 - _rain_k * 0.15
	env.adjustment_brightness = 1.0
	env.glow_hdr_threshold = lerp(0.8, 1.25, day_k)
	# on medium the glow only runs when there are lights to glow (evening and night)
	env.glow_enabled = quality >= 2 or (quality == 1 and day_k < 0.7)
	env.glow_intensity = lerp(0.9, 0.45, day_k)
