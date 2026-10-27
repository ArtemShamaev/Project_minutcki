class_name LanePath
## Converts a tile path into a smooth lane polyline (right-hand traffic).
## Turns are sampled as quadratic Bézier arcs instead of sharp corners.

static func _r(d: Vector2) -> Vector3:
	return Vector3(-d.y, 0, d.x)


static func _d(d: Vector2) -> Vector3:
	return Vector3(d.x, 0, d.y)


## Returns {"pts": PackedVector3Array, "tiles": PackedInt32Array (tile index per point),
##          "first": PackedInt32Array (first point index of each path tile)}
static func build(path: PackedVector2Array, off: float, n: int, start_back: float = 0.35, end_fwd: float = 0.3, loop: bool = false) -> Dictionary:
	var pts := PackedVector3Array()
	var tiles := PackedInt32Array()
	var first := PackedInt32Array()
	var cnt := path.size()
	for k in cnt:
		var t := path[k]
		var ti := int(t.y) * n + int(t.x)
		var center := Vector3(t.x + 0.5, 0.0, t.y + 0.5)
		var din: Vector2
		var dout: Vector2
		if k > 0:
			din = path[k] - path[k - 1]
		elif loop and cnt > 1:
			din = path[0] - path[cnt - 1]
		else:
			din = path[1] - path[0] if cnt > 1 else Vector2(1, 0)
		if k < cnt - 1:
			dout = path[k + 1] - path[k]
		elif loop and cnt > 1:
			dout = path[0] - path[k]
		else:
			dout = din
		if din == Vector2.ZERO or din.length() > 1.5: din = dout
		if dout == Vector2.ZERO or dout.length() > 1.5: dout = din
		first.append(pts.size())
		if k == 0 and not loop:
			pts.append(center + _r(din) * off - _d(din) * start_back)
			tiles.append(ti)
		if din == dout:
			pts.append(center + _r(din) * off)
			tiles.append(ti)
		elif din == -dout:
			# U-turn at a dead end
			pts.append(center + _r(din) * off + _d(din) * 0.2)
			pts.append(center + _d(din) * 0.3)
			pts.append(center + _r(dout) * off + _d(din) * 0.2)
			for i in 3:
				tiles.append(ti)
		else:
			var e := center - _d(din) * 0.5 + _r(din) * off
			var x := center + _d(dout) * 0.5 + _r(dout) * off
			var c := center + _r(din) * off + _r(dout) * off
			for s in [0.15, 0.4, 0.6, 0.85]:
				var a := e.lerp(c, s)
				var b := c.lerp(x, s)
				pts.append(a.lerp(b, s))
				tiles.append(ti)
		if k == cnt - 1 and not loop:
			pts.append(center + _r(dout) * off + _d(dout) * end_fwd)
			tiles.append(ti)
	return {"pts": pts, "tiles": tiles, "first": first}
