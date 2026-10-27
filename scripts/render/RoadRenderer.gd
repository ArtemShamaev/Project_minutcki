extends Node3D
## Auto-tiles road models based on neighbour connections.

var city: City
var nodes := {}   # tile index -> Node3D

# base model connection masks (bit0 N, bit1 E, bit2 S, bit3 W) at rotation 0
const BASE := {
	"roads/road-straight": 10,      # E + W
	"roads/road-bend": 12,          # S + W
	"roads/road-intersection": 14,  # E + S + W
	"roads/road-crossroad": 15,
	"roads/road-end": 2,            # open to E
}


func setup(c: City) -> void:
	city = c
	city.roads_changed.connect(_on_changed)


func rebuild_all() -> void:
	for nd in nodes.values():
		nd.queue_free()
	nodes.clear()
	for y in city.n:
		for x in city.n:
			if city.road[city.idx(x, y)] > 0:
				_update_tile(Vector2i(x, y))


func _on_changed(cells: Array) -> void:
	var todo := {}
	for c in cells:
		todo[c] = true
		for d in Defs.DIRS:
			todo[c + d] = true
	for c in todo.keys():
		if city.inb(c.x, c.y):
			_update_tile(c)


static func _lod(n: Node, r: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = r
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_lod(ch, r)


static var _sig_pole: CylinderMesh
static var _sig_box: BoxMesh
static var _sig_lamp: SphereMesh


## Traffic signals at a junction: a pole at two opposite corners, each with heads for both directions.
func _signals(root: Node3D, mask: int, cx: float, cz: float) -> void:
	if _sig_pole == null:
		_sig_pole = CylinderMesh.new(); _sig_pole.top_radius = 0.008; _sig_pole.bottom_radius = 0.01; _sig_pole.height = 0.26
		_sig_box = BoxMesh.new(); _sig_box.size = Vector3(0.028, 0.06, 0.02)
		_sig_lamp = SphereMesh.new(); _sig_lamp.radius = 0.009; _sig_lamp.height = 0.018; _sig_lamp.radial_segments = 6; _sig_lamp.rings = 3
	var dark := Models.mat(Color("2b2f33"), 0.6)
	for corner in [Vector2(0.43, 0.43), Vector2(-0.43, -0.43)]:
		var pole := MeshInstance3D.new()
		pole.mesh = _sig_pole
		pole.material_override = dark
		var gy := city.height_at(cx + corner.x, cz + corner.y)
		pole.position = Vector3(corner.x, gy + 0.13, corner.y)
		root.add_child(pole)
		# head facing traffic coming along Z (axis 0) and along X (axis 1)
		for axis in 2:
			var head := Node3D.new()
			head.position = Vector3(corner.x, gy + 0.22, corner.y)
			head.rotation.y = (0.0 if axis == 0 else PI * 0.5) + (PI if corner.x < 0 else 0.0)
			root.add_child(head)
			var bx := MeshInstance3D.new()
			bx.mesh = _sig_box
			bx.material_override = dark
			bx.position = Vector3(0, 0, -0.014)
			head.add_child(bx)
			for k in 2:
				var lamp := MeshInstance3D.new()
				lamp.mesh = _sig_lamp
				lamp.material_override = Models.signal_mat(axis, k == 1)
				lamp.position = Vector3(0, 0.015 - k * 0.03, -0.026)
				lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				head.add_child(lamp)


static var _bulb: BoxMesh


static func _bulb_mesh() -> BoxMesh:
	if _bulb == null:
		_bulb = BoxMesh.new()
		_bulb.size = Vector3(0.05, 0.02, 0.07)
	return _bulb


static var _bar_mat: ShaderMaterial
static var _bar_mesh: BoxMesh
static var _med_mesh: BoxMesh


func _highway_barriers(root: Node3D, mask: int, straight: bool) -> void:
	if _bar_mat == null:
		_bar_mat = ShaderMaterial.new()
		_bar_mat.shader = load("res://shaders/drape_color.gdshader")
		_bar_mat.set_shader_parameter("color", Color(0.86, 0.86, 0.84))
		_bar_mesh = BoxMesh.new()
		_bar_mesh.size = Vector3(1.0, 0.06, 0.035)
		_bar_mesh.subdivide_width = 4
		_med_mesh = BoxMesh.new()
		_med_mesh.size = Vector3(1.0, 0.045, 0.03)
		_med_mesh.subdivide_width = 4
	for d in 4:
		if mask & (1 << d):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _bar_mesh
		mi.material_override = _bar_mat
		var dir: Vector2i = Defs.DIRS[d]
		mi.position = Vector3(dir.x * 0.47, 0.05, dir.y * 0.47)
		mi.rotation.y = PI * 0.5 if dir.x != 0 else 0.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	if straight:
		var md := MeshInstance3D.new()
		md.mesh = _med_mesh
		md.material_override = _bar_mat
		md.position = Vector3(0, 0.04, 0)
		md.rotation.y = 0.0 if mask == 10 else PI * 0.5
		md.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(md)


static func _rot_mask(m: int, k: int) -> int:
	# rotating by k*90deg maps direction d -> (d - k) mod 4
	var r := 0
	for d in 4:
		if m & (1 << d):
			r |= 1 << ((d - k + 4) % 4)
	return r


func _choose(mask: int, rtype: int = 1) -> Array:
	return _choose_base(mask)


func _choose_base(mask: int) -> Array:
	var count := 0
	for d in 4:
		if mask & (1 << d):
			count += 1
	var model := "roads/road-crossroad"
	match count:
		0: return ["roads/road-end", 0]  # isolated tile
		1: model = "roads/road-end"
		2:
			model = "roads/road-straight" if (mask == 5 or mask == 10) else "roads/road-bend"
		3: model = "roads/road-intersection"
	for k in 4:
		if _rot_mask(BASE[model], k) == mask:
			return [model, k]
	return [model, 0]


func _update_tile(c: Vector2i) -> void:
	var i := city.idx(c.x, c.y)
	if nodes.has(i):
		nodes[i].queue_free()
		nodes.erase(i)
	if city.road[i] == 0:
		return
	var mask := city.road_mask(c)
	var root := Node3D.new()
	root.position = Vector3(c.x + 0.5, 0, c.y + 0.5)
	var cx := c.x + 0.5
	var cz := c.y + 0.5
	add_child(root)
	nodes[i] = root
	if city.terrain[i] == 1:
		# bridge
		var k := 0 if (mask & 10) else 1
		var br: Node3D = Models.scene("roads/road-bridge").instantiate()
		br.rotation.y = k * PI * 0.5
		br.position.y = -0.5
		root.add_child(br)
		return
	var rtype: int = city.road[i]
	var ch := _choose(mask, rtype)
	var m: Node3D = Models.scene(ch[0]).instantiate()
	m.rotation.y = ch[1] * PI * 0.5
	root.add_child(m)
	Models.set_cast_shadows(m, false)
	Models.set_material(m, Models.drape_mats[rtype])
	# decorations
	if rtype == 2 and ch[0] == "roads/road-straight":
		for side in [-1, 1]:
			var t := Models.fit("suburban/tree-small", Vector2(0.2, 0.2), 0, 1.3)
			var off := Vector3(0, 0, side * 0.45) if mask == 10 else Vector3(side * 0.45, 0, 0)
			t.position = off + Vector3(0, city.height_at(cx + off.x, cz + off.z), 0)
			root.add_child(t)
		if (c.x + c.y) % 2 == 0:
			var dl: Node3D = Models.scene("roads/light-square-double").instantiate()
			dl.position = Vector3(0, city.height_at(cx, cz), 0)
			dl.rotation.y = 0.0 if mask == 10 else PI * 0.5
			dl.scale = Vector3(1, 1, 1)
			root.add_child(dl)
	if rtype == 3:
		_highway_barriers(root, mask, ch[0] == "roads/road-straight")
	if rtype == 3 and ch[0] == "roads/road-straight" and (c.x * 3 + c.y * 5) % 9 == 0 and c != city.outside:
		var sg: Node3D = Models.scene("roads/sign-highway-wide").instantiate()
		sg.position = Vector3(0, city.height_at(cx, cz), 0)
		sg.rotation.y = PI * 0.5 if mask == 10 else 0.0
		sg.scale = Vector3.ONE * 0.8
		root.add_child(sg)
	elif rtype == 1 and ch[0] == "roads/road-straight" and (c.x * 7 + c.y * 13) % 4 == 0:
		var lamp: Node3D = Models.scene("roads/light-square").instantiate()
		var side := 1 if (c.x + c.y) % 2 == 0 else -1
		if mask == 10:
			lamp.position = Vector3(0, 0, side * 0.44)
			lamp.rotation.y = PI * 0.5 if side > 0 else -PI * 0.5
		else:
			lamp.position = Vector3(side * 0.44, 0, 0)
			lamp.rotation.y = 0.0 if side > 0 else PI
		lamp.position.y = city.height_at(cx + lamp.position.x, cz + lamp.position.z)
		root.add_child(lamp)
		var bulb := MeshInstance3D.new()
		bulb.mesh = _bulb_mesh()
		bulb.material_override = Models.lamp_mat
		bulb.position = Vector3(0.0, 0.565, -0.15)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(bulb)
	elif ch[0] in ["roads/road-crossroad", "roads/road-intersection"] and rtype < 3 and preload("res://scripts/render/Traffic.gd").signalised(city, c):
		_signals(root, mask, cx, cz)
	for dn in root.get_children():
		if dn != m:
			_lod(dn, 40.0)
	if c == city.outside:
		var s: Node3D = Models.scene("roads/sign-highway").instantiate()
		s.position = Vector3(0.0, city.height_at(cx, cz - 0.45), -0.45)
		s.scale = Vector3.ONE * 0.7
		root.add_child(s)
