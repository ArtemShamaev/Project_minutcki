extends Node3D
## City-builder camera: WASD/arrows pan, Q/E rotate, wheel zoom,
## middle mouse rotate/tilt, right mouse drag pan, edge scrolling optional.

var cam: Camera3D
var focus := Vector3(20, 0, 60)
var yaw := deg_to_rad(-35.0)
var pitch := deg_to_rad(52.0)
var dist := 22.0
var t_focus := focus
var t_yaw := yaw
var t_pitch := pitch
var t_dist := dist
var bounds := Rect2(0, 0, 120, 120)
var orbit := false   # menu background mode
var city: City
var shake := 0.0
var follow: Node3D = null
var street := false          # street-level view (eyes of a citizen or a free walk)
var look_pitch := 0.0        # street view: looking up / down
var tilt_shift := true
var attrs: CameraAttributesPractical
var _rot_drag := false
var _pan_drag := false
var _last_mouse := Vector2.ZERO

const MIN_DIST := 3.0
const MAX_DIST := 110.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 50
	cam.near = 0.05
	cam.far = 600
	attrs = CameraAttributesPractical.new()
	cam.attributes = attrs
	add_child(cam)
	_apply()


func set_focus(p: Vector3, d: float = -1.0) -> void:
	t_focus = p
	focus = p
	if d > 0:
		t_dist = d
		dist = d
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if orbit:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			t_dist = max(MIN_DIST, t_dist * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			t_dist = min(MAX_DIST, t_dist * 1.13)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rot_drag = mb.pressed
			_last_mouse = mb.position
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_pan_drag = mb.pressed
			_last_mouse = mb.position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if street and (_rot_drag or _pan_drag):
			t_yaw -= mm.relative.x * 0.005
			look_pitch = clamp(look_pitch - mm.relative.y * 0.004, -0.9, 0.7)
			return
		if _rot_drag:
			t_yaw -= mm.relative.x * 0.006
			t_pitch = clamp(t_pitch + mm.relative.y * 0.004, deg_to_rad(18), deg_to_rad(88))
		elif _pan_drag:
			follow = null
			var k := t_dist * 0.0022
			var right := Vector3(cos(t_yaw), 0, -sin(t_yaw))
			var fwd := Vector3(-sin(t_yaw), 0, -cos(t_yaw))
			t_focus -= right * mm.relative.x * k
			t_focus -= fwd * -mm.relative.y * k


func _process(delta: float) -> void:
	Prof.b("rig")
	_process_inner(delta)
	Prof.e("rig")


func _process_inner(delta: float) -> void:
	if orbit:
		t_yaw += delta * 0.05
	else:
		var mv := Vector2.ZERO
		if not _ui_focus():
			if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.y -= 1
			if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.y += 1
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x -= 1
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x += 1
			if Input.is_key_pressed(KEY_Q): t_yaw += delta * 1.6
			if Input.is_key_pressed(KEY_E): t_yaw -= delta * 1.6
			if Input.is_key_pressed(KEY_R) and Input.is_key_pressed(KEY_SHIFT): t_pitch = clamp(t_pitch - delta, deg_to_rad(18), deg_to_rad(88))
			if Input.is_key_pressed(KEY_F) and Input.is_key_pressed(KEY_SHIFT): t_pitch = clamp(t_pitch + delta, deg_to_rad(18), deg_to_rad(88))
		if mv != Vector2.ZERO and follow:
			follow = null
		if mv != Vector2.ZERO:
			var speed := t_dist * 1.1 * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
			if street:
				speed = 0.6 * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
			var right := Vector3(cos(t_yaw), 0, -sin(t_yaw))
			var fwd := Vector3(-sin(t_yaw), 0, -cos(t_yaw))
			t_focus += (right * mv.x - fwd * mv.y).normalized() * speed * delta
	if follow:
		if is_instance_valid(follow) and follow.is_inside_tree():
			t_focus = follow.global_position
		else:
			follow = null
	t_focus.x = clamp(t_focus.x, bounds.position.x - 5, bounds.end.x + 5)
	t_focus.z = clamp(t_focus.z, bounds.position.y - 5, bounds.end.y + 5)
	var k: float = clamp(delta * 10.0, 0.0, 1.0)
	focus = focus.lerp(t_focus, k)
	yaw = lerp_angle(yaw, t_yaw, k)
	pitch = lerp(pitch, t_pitch, k)
	dist = lerp(dist, t_dist, k)
	if tilt_shift and not street:
		_update_dof()
	_apply()


func _ui_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Street view: the camera rides behind the followed citizen / vehicle, or walks freely.
func set_street(on: bool) -> void:
	street = on
	look_pitch = -0.08
	if on and follow:
		t_yaw = follow.global_rotation.y + PI
		yaw = t_yaw
	_update_dof()


func _apply_street() -> void:
	var p := focus
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	if follow and is_instance_valid(follow):
		var fy: float = follow.global_rotation.y
		fwd = Vector3(sin(fy), 0, cos(fy))
		t_yaw = atan2(-fwd.x, -fwd.z)
		p = follow.global_position - fwd * 0.42
		p.y = follow.global_position.y + 0.16
	elif city:
		p.y = city.height_at(p.x, p.z) + 0.11
	position = p
	if city:
		position.y = maxf(position.y, city.height_at(position.x, position.z) + 0.06)
	var dir := fwd.rotated(fwd.cross(Vector3.UP).normalized(), look_pitch) if fwd.cross(Vector3.UP).length() > 0.01 else fwd
	look_at(position + dir, Vector3.UP)
	if cam:
		cam.position = Vector3.ZERO


func _update_dof() -> void:
	if attrs == null:
		return
	var on := tilt_shift and not street
	attrs.dof_blur_far_enabled = on
	attrs.dof_blur_near_enabled = on
	attrs.dof_blur_amount = 0.05
	if on:
		attrs.dof_blur_far_distance = dist * 1.25
		attrs.dof_blur_far_transition = dist * 1.6
		attrs.dof_blur_near_distance = dist * 0.55
		attrs.dof_blur_near_transition = dist * 0.4


func _apply() -> void:
	if street:
		_apply_street()
		return
	if city:
		var gh: float = max(city.height_at(focus.x, focus.z), 0.0)
		focus.y = lerp(focus.y, gh, 0.15)
	# lower pitch when zoomed in for a more cinematic street view
	var p: float = pitch - clamp((12.0 - dist) / 12.0, 0.0, 1.0) * deg_to_rad(18)
	var off := Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist
	position = focus + off
	if city:
		var minh: float = max(city.height_at(position.x, position.z), 0.0) + 0.6
		if position.y < minh:
			position.y = minh
	look_at(focus, Vector3.UP)
	if cam:
		cam.position = Vector3.ZERO
		if shake > 0.001:
			cam.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * clamp(dist / 20.0, 0.3, 2.0)
			shake = max(0.0, shake - get_process_delta_time() * 0.08)


## Mouse ray -> ground plane (y = 0) intersection.
func ground_point(screen: Vector2) -> Variant:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if abs(d.y) < 1e-5:
		return null
	if city == null:
		var t0 := -o.y / d.y
		return null if t0 < 0 else o + d * t0
	# march along the ray against the heightfield
	var step := 0.25
	var t := 0.0
	for i in 2400:
		var p := o + d * t
		var inside := p.x >= 0 and p.z >= 0 and p.x <= city.n and p.z <= city.n
		var gh: float = city.height_at(p.x, p.z) if inside else 0.0
		if p.y <= gh:
			var lo := t - step
			var hi := t
			for k in 8:
				var mid := (lo + hi) * 0.5
				var q := o + d * mid
				if q.y <= city.height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return o + d * hi
		t += step
		if p.y < -2.0:
			break
	var tt := -o.y / d.y
	return null if tt < 0 else o + d * tt


func ray(screen: Vector2) -> Array:
	return [cam.project_ray_origin(screen), cam.project_ray_normal(screen)]
