class_name Hitmarker
extends Control
## Four small diagonal ticks at the exact screen position of the impact.
## Normal hit = white + short tick sound; kill = slightly bigger, red, lower
## "thunk". The sounds are synthesized at startup (no audio files needed).

var _t := 0.0
var _duration := 0.18
var _kill := false
var _screen_pos := Vector2.ZERO
var _player: AudioStreamPlayer
var _snd_hit: AudioStreamWAV
var _snd_kill: AudioStreamWAV


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_full_rect()

	_snd_hit = _make_blip(1900.0, 0.05, 0.30, 0.0)
	_snd_kill = _make_blip(620.0, 0.22, 0.45, 0.5)
	_player = AudioStreamPlayer.new()
	add_child(_player)


func _update_full_rect() -> void:
	var vp := get_viewport()
	if vp:
		var target_size := vp.get_visible_rect().size
		if size != target_size:
			size = target_size


func flash(kill: bool, screen_pos: Vector2) -> void:
	_kill = kill
	_screen_pos = screen_pos
	_duration = 0.34 if kill else 0.18
	_t = 1.0
	_player.stream = _snd_kill if kill else _snd_hit
	_player.play()
	queue_redraw()


func _process(delta: float) -> void:
	_update_full_rect()
	if _t > 0.0:
		_t = maxf(_t - delta / _duration, 0.0)
		queue_redraw()


func _draw() -> void:
	if _t <= 0.0:
		return
	var c := _screen_pos
	var k := 1.0 - _t                                   # 0 -> 1 over the animation
	var inner := lerpf(7.0, 3.5, minf(k * 5.0, 1.0)) if not _kill else lerpf(9.0, 5.0, minf(k * 4.0, 1.0))
	var length := 6.0 if not _kill else 8.5
	var width := 1.6 if not _kill else 2.3
	var col := Color(1, 1, 1, _t) if not _kill else Color(1.0, 0.15, 0.1, minf(_t * 1.6, 1.0))
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var dir: Vector2 = d.normalized()
		draw_line(c + dir * inner, c + dir * (inner + length), col, width, true)


## Short decaying sine blip (optionally with a fifth-ish overtone) as 16-bit mono PCM.
func _make_blip(freq: float, length: float, volume: float, overtone: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 6.0 / length)
		var s := sin(TAU * freq * t) + overtone * sin(TAU * freq * 1.5 * t)
		var v := clampf(s * env * volume, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
