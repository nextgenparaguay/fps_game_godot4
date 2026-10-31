class_name Reticle
extends Control
## Dynamic circular reticle.
##
## The ring radius is driven by the weapon's *current* spread, so movement,
## sprinting, jumping and consecutive shots visibly open it up.  Every shot
## adds a small upward kick (plus random horizontal jitter) to the whole ring.
## While aiming down sights the UI kick is disabled; the weapon sends that
## recoil to the camera instead.

const MIN_RADIUS := 5.0
const MAX_RECOIL := Vector2(46.0, 46.0)
const MAX_DRAG := 70.0              # px: furthest the reticle can trail the view centre
const FIRING_CATCHUP := 0.25        # while firing, recovery runs at this fraction

var spread_radius := 10.0
var recoil_offset := Vector2.ZERO
var ads := 0.0
## Aim lag: how far the reticle trails the camera centre while firing. It is part
## of the aim point, so bullets follow the lagging reticle.
var drag_offset := Vector2.ZERO
var _firing := false
var _recovery_speed := 8.0

var _target_radius := 10.0
var _shot_heat := 0.0
var _reticle_color := Color(0.94, 0.97, 1.0, 0.92)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_NONE
	_update_full_rect()
	queue_redraw()


func _update_full_rect() -> void:
	var vp := get_viewport()
	if vp:
		var target_size := vp.get_visible_rect().size
		if size != target_size:
			size = target_size


## Called every frame by the player.
func update_spread(radius_px: float, ads_amount: float) -> void:
	_target_radius = maxf(radius_px, MIN_RADIUS)
	ads = clampf(ads_amount, 0.0, 1.0)


## Called by the player every frame with the current firing state and tuning.
func update_drag(firing: bool, recovery_speed: float) -> void:
	_firing = firing
	_recovery_speed = recovery_speed


## Called by the player when the view turns while firing. `px` is the screen-space
## amount the reticle should fall behind (opposite to the turn). Ignored in ADS.
func add_look_drag(px: Vector2) -> void:
	if ads > 0.45:
		return
	drag_offset = (drag_offset + px).limit_length(MAX_DRAG)


## Called by the weapon for hip-fire recoil. ADS ignores this by design.
func add_shot_recoil(up_px: float, jitter_px: float) -> void:
	if ads > 0.45:
		return
	recoil_offset.y -= up_px
	recoil_offset.x += randf_range(-jitter_px, jitter_px)
	recoil_offset = recoil_offset.clamp(-MAX_RECOIL, MAX_RECOIL)
	_shot_heat = minf(_shot_heat + 0.35, 1.0)


func _process(delta: float) -> void:
	_update_full_rect()
	var rate := 1.0 - exp(-22.0 * delta)
	spread_radius = lerpf(spread_radius, _target_radius, rate)
	_shot_heat = maxf(_shot_heat - delta * 2.4, 0.0)

	# The ring springs back toward the true aim point after each shot.  In ADS
	# this is forced to zero because that recoil lives on the camera instead.
	var recoil_rate := 1.0 - exp(-16.0 * delta)
	if ads > 0.45:
		recoil_offset = recoil_offset.lerp(Vector2.ZERO, 1.0 - exp(-28.0 * delta))
	else:
		recoil_offset = recoil_offset.lerp(Vector2.ZERO, recoil_rate * 0.55)

	# Aim lag re-centres smoothly: slowly while firing (the reticle keeps trailing),
	# at full recovery speed once firing stops, and fast in ADS.
	var drag_speed := _recovery_speed * (FIRING_CATCHUP if _firing else 1.0)
	if ads > 0.45:
		drag_speed = 28.0
	drag_offset = drag_offset.lerp(Vector2.ZERO, 1.0 - exp(-drag_speed * delta))

	var heat := clampf((spread_radius - MIN_RADIUS) / 42.0, 0.0, 1.0)
	_reticle_color = Color(0.94, 0.97, 1.0, 0.94).lerp(
			Color(1.0, 0.48, 0.16, 0.98), maxf(heat, _shot_heat * 0.7))
	# Fade the whole reticle out as the weapon settles into ADS; the hitmarker
	# stays fully visible because it is a separate Control.
	modulate.a = 1.0 - smoothstep(0.0, 0.85, ads)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5 + recoil_offset + drag_offset
	var radius := spread_radius

	# Low-alpha outer bloom ring makes the spread readable even against bright
	# backgrounds without turning into a solid blob.
	draw_arc(center, radius, 0.0, TAU, 48,
			Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, 0.10),
			6.0, true)

	# Four gaps: a circle, but an FPS-readable one.
	var gap := deg_to_rad(26.0)
	var arc := TAU / 4.0 - gap
	for i in 4:
		var start := float(i) * TAU / 4.0 + gap * 0.5
		draw_arc(center, radius, start, start + arc, 20,
				_reticle_color, 2.2, true)

	# Center dot stays put (the ring moves with recoil, the dot is the true
	# screen-center aim reference).
	draw_circle(center, 1.8, Color(1, 1, 1, 0.00))

	# Small ticks on the vertical/horizontal axes help judge the gap.
	var tick := Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, 0.75)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var dir: Vector2 = d
		var inner := radius + 4.0
		var outer := radius + 9.0
		draw_line(center + dir * inner, center + dir * outer, tick, 1.4, true)
