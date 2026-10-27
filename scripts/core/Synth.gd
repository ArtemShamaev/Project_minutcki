class_name Synth
## Procedural audio: generative music tracks and ambient/effect sounds.

const RATE := 22050

const TRACKS := [
	{"name": "Утро в городе", "bpm": 84, "key": 60, "prog": [[0, 4, 7], [9, 12, 16], [5, 9, 12], [7, 11, 14]], "seed": 11},
	{"name": "Вечерний проспект", "bpm": 72, "key": 57, "prog": [[0, 3, 7], [8, 12, 15], [3, 7, 10], [10, 14, 17]], "seed": 23},
	{"name": "Набережная", "bpm": 92, "key": 62, "prog": [[0, 4, 7, 11], [5, 9, 12, 16], [2, 5, 9, 12], [7, 11, 14, 17]], "seed": 37},
	{"name": "Тихий район", "bpm": 66, "key": 55, "prog": [[0, 4, 7], [7, 11, 14], [9, 12, 16], [5, 9, 12]], "seed": 41},
]


static func midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


static func to_stream(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(clamp(buf[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s


static func _add_tone(buf: PackedFloat32Array, start: int, dur: float, hz: float, amp: float, attack: float, decay: float, kind: int) -> void:
	## kind 0: soft sine pluck, 1: pad (detuned, slow), 2: bass
	var n := int(dur * RATE)
	var w := TAU * hz / RATE
	var w2 := TAU * hz * 1.006 / RATE
	var ph := 0.0
	var ph2 := 0.0
	var a_n: int = maxi(1, int(attack * RATE))
	var end := mini(buf.size(), start + n)
	for i in range(start, end):
		var t := i - start
		var env: float
		if t < a_n:
			env = float(t) / a_n
		else:
			env = exp(-(t - a_n) / (decay * RATE))
		var rel := end - i
		if rel < 400:
			env *= rel / 400.0
		var v: float
		match kind:
			0: v = sin(ph) + 0.25 * sin(ph * 2.0) + 0.08 * sin(ph * 3.0)
			1: v = (sin(ph) + sin(ph2)) * 0.5 + 0.15 * sin(ph * 2.0)
			_: v = sin(ph) + 0.3 * sin(ph * 2.0)
		buf[i] += v * env * amp
		ph += w
		ph2 += w2


static func render_track(idx: int) -> AudioStreamWAV:
	var tr: Dictionary = TRACKS[idx % TRACKS.size()]
	var rng := RandomNumberGenerator.new()
	rng.seed = tr.seed
	var beat: float = 60.0 / tr.bpm
	var bars_per_chord := 2
	var prog: Array = tr.prog
	var rounds := 2
	var total_beats := prog.size() * bars_per_chord * 4 * rounds
	var buf := PackedFloat32Array()
	buf.resize(int(total_beats * beat * RATE) + RATE)
	var key: int = tr.key
	var pent := [0, 2, 4, 7, 9, 12, 14, 16]
	var b := 0
	for r in rounds:
		for c in prog.size():
			var chord: Array = prog[c]
			var cs := int(b * beat * RATE)
			var cdur: float = bars_per_chord * 4 * beat
			# pad
			for nt in chord:
				_add_tone(buf, cs, cdur + 0.3, midi_hz(key + nt - 12), 0.06, 1.2, 4.0, 1)
			# bass
			for k in bars_per_chord * 2:
				_add_tone(buf, cs + int(k * 2 * beat * RATE), beat * 1.8, midi_hz(key + chord[0] - 24), 0.16, 0.01, 0.6, 2)
			# arpeggio (8ths)
			var pattern := [0, 1, 2, 1, 2, 3 % chord.size(), 1, 2]
			for k in bars_per_chord * 8:
				if r == 0 and c == 0 and k < 4:
					continue
				var nt: int = chord[pattern[k % 8] % chord.size()]
				_add_tone(buf, cs + int(k * beat * 0.5 * RATE), beat * 1.5, midi_hz(key + nt + 12), 0.055, 0.005, 0.35, 0)
			# melody on second round
			if r == 1:
				var k := 0
				while k < bars_per_chord * 4:
					if rng.randf() < 0.55:
						var m: int = key + 12 + pent[rng.randi() % pent.size()]
						var ln: float = beat * (1.0 if rng.randf() < 0.6 else 2.0)
						_add_tone(buf, cs + int(k * beat * RATE), ln * 1.4, midi_hz(m), 0.07, 0.01, 0.7, 0)
					k += 1 if rng.randf() < 0.6 else 2
			b += bars_per_chord * 4
	# simple reverb (two feedback delays)
	var d1 := int(0.21 * RATE)
	var d2 := int(0.37 * RATE)
	for i in buf.size():
		if i >= d1:
			buf[i] += buf[i - d1] * 0.28
		if i >= d2:
			buf[i] += buf[i - d2] * 0.18
	# normalize gently
	var mx := 0.001
	for v in buf:
		mx = max(mx, abs(v))
	var g: float = 0.7 / mx
	for i in buf.size():
		buf[i] *= g
	return to_stream(buf, false)


static func noise_loop(seconds: float, smooth: float, amp: float) -> AudioStreamWAV:
	## Brown-ish noise loop (city hum / wind).
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var v := 0.0
	var lp := 0.0
	for i in n:
		v = v * 0.995 + rng.randf_range(-1.0, 1.0) * 0.05
		lp = lerp(lp, v, smooth)
		buf[i] = lp * amp
	# crossfade ends for seamless loop
	var f := int(0.3 * RATE)
	for i in f:
		var k := float(i) / f
		buf[i] = buf[i] * k + buf[n - f + i] * (1.0 - k)
	buf.resize(n - f)
	return to_stream(buf, true)


static func bird() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var buf := PackedFloat32Array()
	buf.resize(int(0.9 * RATE))
	var t0 := 0
	for k in rng.randi_range(2, 5):
		var dur := rng.randf_range(0.06, 0.14)
		var f0 := rng.randf_range(2600, 4200)
		var f1 := f0 + rng.randf_range(-1200, 1200)
		var n := int(dur * RATE)
		var ph := 0.0
		for i in n:
			var t := float(i) / n
			var hz: float = lerp(f0, f1, t)
			ph += TAU * hz / RATE
			if t0 + i < buf.size():
				buf[t0 + i] += sin(ph) * sin(PI * t) * 0.35
		t0 += n + int(rng.randf_range(0.02, 0.08) * RATE)
	return to_stream(buf, false)


static func siren() -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	buf.resize(int(1.2 * RATE))
	var ph := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var hz := 760.0 if fmod(t, 1.2) < 0.6 else 1020.0
		ph += TAU * hz / RATE
		var v := sin(ph) * 0.6 + sin(ph * 3.0) * 0.12
		buf[i] = v * 0.4
	return to_stream(buf, true)


static func horn() -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	buf.resize(int(0.35 * RATE))
	var p1 := 0.0
	var p2 := 0.0
	for i in buf.size():
		p1 += TAU * 392.0 / RATE
		p2 += TAU * 494.0 / RATE
		var env: float = min(1.0, i / 300.0) * min(1.0, (buf.size() - i) / 600.0)
		buf[i] = (sign(sin(p1)) * 0.5 + sign(sin(p2)) * 0.4) * 0.18 * env
	return to_stream(buf, false)
