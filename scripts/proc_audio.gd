class_name ProcAudio
extends RefCounted
## Tiny procedural sound effects (reload clicks, pickups, explosions...).
##
## The project only ships a handful of WAV files, so the new gameplay systems
## synthesize their own placeholder sounds at runtime. Replace any of them by
## pointing the caller at a real asset; nothing else depends on these.

const RATE := 22050

static var _cache: Dictionary = {}


## Generate every sound once up front so the first explosion doesn't hitch.
static func warm() -> void:
	for n in ["click", "mag_out", "mag_in", "bolt", "equip", "pickup", "medkit",
			"explosion", "beep", "throw"]:
		get_sound(n)


static func get_sound(sound_name: String) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var s := _make(sound_name)
	_cache[sound_name] = s
	return s


## Non-positional one-shot (UI / viewmodel sounds). `owner` just hosts the player node.
static func play_ui(owner: Node, sound_name: String, volume_db := -6.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = get_sound(sound_name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	owner.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Positional one-shot in the world.
static func play_at(root: Node, sound_name: String, pos: Vector3, volume_db := 0.0,
		pitch := 1.0, max_dist := 80.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_sound(sound_name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 8.0
	p.max_distance = max_dist
	root.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


static func _make(n: String) -> AudioStreamWAV:
	match n:
		"click":
			return _synth(0.05, func(t: float, _l: float) -> float:
				return sin(TAU * 1800.0 * t) * exp(-t * 90.0) * 0.5 + _noise() * 0.3 * exp(-t * 200.0))
		"mag_out":
			return _synth(0.12, func(t: float, _l: float) -> float:
				return sin(TAU * 160.0 * t) * exp(-t * 30.0) * 0.8 + _noise() * 0.35 * exp(-t * 70.0))
		"mag_in":
			return _synth(0.15, func(t: float, _l: float) -> float:
				var thud := sin(TAU * 240.0 * t) * exp(-t * 28.0) * 0.7
				var snap := _noise() * 0.4 * exp(-maxf(t - 0.06, 0.0) * 90.0) * (1.0 if t > 0.06 else 0.2)
				return thud + snap)
		"bolt":
			return _synth(0.1, func(t: float, _l: float) -> float:
				return sin(TAU * 700.0 * t) * exp(-t * 40.0) * 0.5 + _noise() * 0.5 * exp(-t * 55.0))
		"equip":
			return _synth(0.08, func(t: float, _l: float) -> float:
				return sin(TAU * 420.0 * t) * exp(-t * 35.0) * 0.5 + _noise() * 0.2 * exp(-t * 80.0))
		"pickup":
			return _synth(0.2, func(t: float, _l: float) -> float:
				return sin(TAU * (660.0 * t + 1500.0 * t * t)) * exp(-t * 10.0) * 0.5)
		"medkit":
			return _synth(0.34, func(t: float, _l: float) -> float:
				var v := 0.0
				var notes := [523.0, 659.0, 784.0]
				for i in 3:
					var tt := t - 0.09 * i
					if tt >= 0.0:
						v += sin(TAU * float(notes[i]) * tt) * exp(-tt * 9.0) * 0.35
				return v)
		"beep":
			return _synth(0.09, func(t: float, _l: float) -> float:
				return sin(TAU * 1500.0 * t) * exp(-t * 18.0) * 0.5)
		"throw":
			return _synth(0.25, func(t: float, l: float) -> float:
				return _noise() * sin(PI * t / l) * 0.3)
		"explosion":
			var lp := [0.0]
			return _synth(1.1, func(t: float, _l: float) -> float:
				var nz := _noise()
				lp[0] += (nz - lp[0]) * 0.12         # one-pole low-pass => rumble
				return lp[0] * 3.0 * exp(-t * 3.2) + sin(TAU * 48.0 * t) * exp(-t * 5.0) * 0.9 \
						+ nz * 0.25 * exp(-t * 18.0))
	return _synth(0.05, func(_t: float, _l: float) -> float: return 0.0)


static func _noise() -> float:
	return randf() * 2.0 - 1.0


static func _synth(length: float, fn: Callable) -> AudioStreamWAV:
	var count := int(RATE * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var v := clampf(float(fn.call(float(i) / RATE, length)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
