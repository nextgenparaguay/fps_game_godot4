class_name Hitmarker
extends Control
## Four small diagonal ticks at the exact screen position of the impact.
## Normal hit = white ticks + the hitmarker WAV; kill = larger red ticks but no
## hitmarker audio, so the spatial blood-impact sound stays clear.

const HIT_SOUND := preload("res://assets/sounds/hitmarker-sound-effect.wav")

var _t := 0.0
var _duration := 0.18
var _kill := false
var _screen_pos := Vector2.ZERO
var _player: AudioStreamPlayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_full_rect()

	_player = AudioStreamPlayer.new()
	_player.stream = HIT_SOUND
	_player.volume_db = -4.0
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
	if kill:
		# The enemy's blood-impact sound owns the kill audio.
		_player.stop()
	else:
		_player.pitch_scale = randf_range(0.97, 1.03)
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
