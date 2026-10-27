class_name Prof
## Tiny profiler: accumulates microseconds per section.
static var acc := {}
static var enabled := false
static var _t := {}

static func b(name: String) -> void:
	if enabled:
		_t[name] = Time.get_ticks_usec()

static func e(name: String) -> void:
	if enabled and _t.has(name):
		acc[name] = acc.get(name, 0) + Time.get_ticks_usec() - _t[name]

static func report(frames: int) -> String:
	var out := ""
	for k in acc:
		out += "%s=%.2fms " % [k, acc[k] / 1000.0 / max(1, frames)]
	return out
