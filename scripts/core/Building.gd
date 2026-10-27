class_name Building
extends RefCounted
## A building occupying a rectangular lot. Either a zoned (growable) building
## or a player-placed service building.

var id := 0
var type := "zone"            # "zone" or a key of Defs.SERVICES
var zone := 0
var level := 1
var x := 0                    # lot min corner
var y := 0
var sx := 1                   # lot size along X / Z (world axes)
var sy := 1
var w := 1                    # lot width (along road) / depth (away from road)
var d := 1
var dir := 0                  # facing direction (index into Defs.DIRS), towards the road
var access := Vector2i(-1, -1)  # road tile in front of the building
var seed := 0
var base_y := 0.0              # ground height of the (flattened) lot

var cap := 0                  # residents or jobs capacity
var occ := 0                  # current residents / workers
var happiness := 60.0
var powered := false
var watered := false
var has_road := true
var abandoned := false
var collapsed := false
var fire := 0                 # days of fire remaining (>0 = burning)
var fire_dispatched := false
var build_days := 0           # construction remaining
var no_power_days := 0
var no_water_days := 0
var unhappy_days := 0
var abandoned_days := 0
var garbage := 0.0
var sewered := false
var no_sewage_days := 0
var dead := 0.0               # deceased waiting for a hearse
var dead_days := 0
var stored := 0.0             # landfill garbage / cemetery graves used
var emptying := false         # landfill / cemetery is being emptied
var flooded := false          # standing in flood water
var flooded_days := 0
var eff := 1.0                # pumps: share of the wanted water available; hydro: flow factor
var sew_in := 0.0             # outlets: sewage received through the pipes
var sew_pass := 1.0           # zoned: share of its sewage the pipes can take
var style := "modern"         # architecture style the building was built in
var stage := 0                # megaprojects: finished construction stages
var stage_days := 0.0
var funded := false           # current stage paid for
var ministries: Array = []    # city hall: department wings built
var style_lock := false       # style chosen by the player for this building (kept on upgrades)
var problems: Array = []      # list of problem keys for icons/info


## Megaprojects work only when every construction stage is finished.
func done() -> bool:
	return type == "zone" or stage >= int(Defs.SERVICES[type].get("stages", 0))


func is_service() -> bool:
	return type != "zone"


func kind() -> String:
	return Defs.zone_kind(zone) if type == "zone" else "s"


func center() -> Vector3:
	return Vector3(x + sx * 0.5, 0.0, y + sy * 0.5)


func rect() -> Rect2i:
	return Rect2i(x, y, sx, sy)


func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for j in sy:
		for i in sx:
			out.append(Vector2i(x + i, y + j))
	return out


func store_cap() -> float:
	return float(Defs.SERVICES[type].get("store", 0)) if type != "zone" else 0.0


func is_full() -> bool:
	var c := store_cap()
	return c > 0.0 and stored >= c


func area() -> int:
	return sx * sy


func display_name() -> String:
	if collapsed:
		return "Руины"
	if type == "cityhall":
		return Defs.HALL_LEVELS[clampi(level, 1, 3) - 1].name
	if type != "zone":
		return Defs.SERVICES[type]["name"]
	var names := {
		Defs.R_LOW: ["Частный дом", "Коттедж", "Особняк"],
		Defs.R_HIGH: ["Жилой дом", "Многоэтажка", "Жилой комплекс"],
		Defs.C_LOW: ["Лавка", "Магазин", "Торговый центр"],
		Defs.C_HIGH: ["Торговое здание", "Бизнес-центр", "Небоскрёб"],
		Defs.IND: ["Мастерская", "Фабрика", "Завод"],
		Defs.OFFICE: ["Контора", "Офисное здание", "Офисная башня"],
		Defs.AGRI: ["Ферма", "Агрохозяйство", "Агрокомплекс"],
	}
	return names[zone][clampi(level - 1, 0, 2)]


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "zone": zone, "level": level, "x": x, "y": y, "sx": sx, "sy": sy,
		"w": w, "d": d, "dir": dir, "ax": access.x, "ay": access.y, "seed": seed, "cap": cap, "occ": occ,
		"happiness": happiness, "abandoned": abandoned, "fire": fire, "build_days": build_days,
		"no_power_days": no_power_days, "no_water_days": no_water_days, "unhappy_days": unhappy_days,
		"abandoned_days": abandoned_days, "garbage": garbage, "base_y": base_y, "collapsed": collapsed,
		"dead": dead, "dead_days": dead_days, "no_sewage_days": no_sewage_days, "stored": stored, "emptying": emptying, "style": style, "style_lock": style_lock, "stage": stage, "stage_days": stage_days, "funded": funded, "ministries": ministries,
	}


static func from_dict(dd: Dictionary) -> Building:
	var b := Building.new()
	b.id = int(dd.id); b.type = dd.type; b.zone = int(dd.zone); b.level = int(dd.level)
	b.x = int(dd.x); b.y = int(dd.y); b.sx = int(dd.sx); b.sy = int(dd.sy)
	b.w = int(dd.w); b.d = int(dd.d); b.dir = int(dd.dir); b.access = Vector2i(int(dd.ax), int(dd.ay))
	b.seed = int(dd.seed); b.cap = int(dd.cap); b.occ = int(dd.occ); b.happiness = float(dd.happiness)
	b.abandoned = bool(dd.abandoned); b.fire = int(dd.fire); b.build_days = int(dd.build_days)
	b.no_power_days = int(dd.no_power_days); b.no_water_days = int(dd.no_water_days)
	b.unhappy_days = int(dd.unhappy_days); b.abandoned_days = int(dd.abandoned_days)
	b.garbage = float(dd.get("garbage", 0.0))
	b.base_y = float(dd.get("base_y", 0.0))
	b.collapsed = bool(dd.get("collapsed", false))
	b.dead = float(dd.get("dead", 0.0))
	b.dead_days = int(dd.get("dead_days", 0))
	b.no_sewage_days = int(dd.get("no_sewage_days", 0))
	b.stored = float(dd.get("stored", 0.0))
	b.emptying = bool(dd.get("emptying", false))
	b.style = dd.get("style", "modern")
	b.style_lock = bool(dd.get("style_lock", false))
	b.stage = int(dd.get("stage", 0))
	b.stage_days = float(dd.get("stage_days", 0.0))
	b.funded = bool(dd.get("funded", false))
	b.ministries = dd.get("ministries", [])
	return b
