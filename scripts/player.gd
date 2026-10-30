class_name Player
extends CharacterBody3D
## Titanfall-2 style movement controller.
##
## Features: Source-style acceleration/air-strafing, auto-sprint, slide (with
## slope boost + slide-hop), crouch, double jump, wall-run, wall-jump.
## Collision shape, camera, weapon and HUD are created in code so the player
## works as an empty CharacterBody3D with just this script on it.

signal health_changed(new_health: float)
signal died

enum State { GROUND, AIR, SLIDE, WALLRUN }

const PITCH_LIMIT := 1.55
const ReticleScript := preload("res://scripts/reticle.gd")

@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var base_fov := 65.0
@export var ads_zoom := 3.5              ## FOV zoom factor while aiming down sights
@export var ads_move_mult := 0.6         ## movement speed multiplier while aiming

@export_group("Ground")
@export var walk_speed := 7.0
@export var sprint_speed := 9.5
@export var crouch_speed := 3.5
@export var ground_accel := 10.0
@export var ground_friction := 6.0
@export var stop_speed := 2.5

@export_group("Air")
@export var gravity := 22.0
@export var jump_velocity := 8.0
@export var double_jump_velocity := 7.5
@export var auto_hop := true            ## hold jump to keep hopping (keeps speed)
@export var coyote_time := 0.12
@export var air_accel := 10.0
## Lower = stricter air control. Higher = more air-strafing / speed gain.
@export var air_speed_cap := 3.0

@export_group("Slide")
@export var slide_start_speed := 8.0     ## min horizontal speed to start a slide
@export var slide_boost := 3.0
@export var slide_max_speed := 16.0      ## cap for the initial boost
@export var slide_slope_max_speed := 22.0
@export var slide_min_speed := 3.5       ## slide ends below this
@export var slide_decel := 5.0
@export var slide_steer := 2.5
@export var slide_slope_factor := 1.6    ## how strongly slopes accelerate you
@export var slide_cooldown := 0.4

@export_group("Wall")
@export var wall_check_distance := 0.6
@export var wallrun_min_speed := 5.0
@export var wallrun_speed := 9.5
@export var wallrun_max_time := 2.5
@export var wallrun_gravity_scale := 0.12
@export var wallrun_stick_speed := 2.0
@export var wallrun_tilt_deg := 14.0
@export var wall_jump_up := 8.5
@export var wall_jump_push := 7.0
@export var wall_jump_forward := 3.0
@export var air_wall_jumps := 3          ## wall jumps without wall-running, per airtime
@export var wall_cooldown := 0.35

@export_group("Body")
@export var stand_height := 1.8
@export var crouch_height := 0.9
@export var radius := 0.4
@export var stand_eye := 1.65
@export var crouch_eye := 0.85

@export_group("Health")
@export var max_health := 100.0

var state: State = State.GROUND
var health := 100.0

var head: Node3D
var camera: Camera3D
var weapon: Weapon
var shape: CapsuleShape3D
var collision_shape: CollisionShape3D

var crouching := false
var double_jump_ready := true
var wall_jumps_left := 3

var _coyote_timer := 0.0
var _slide_cd_timer := 0.0
var _wall_cd_timer := 0.0
var _wallrun_timer := 0.0
var _wallrun_side := 0.0
var _fall_speed := 0.0
var _jump_down_prev := false
var _slide_down_prev := false
var _sprint_down_prev := false
var _jump_edge := false          # edges are true for exactly one physics tick per key press
var _slide_edge := false
var _sprint_edge := false
var _sprint_toggle := false      # Shift toggles sprint (off by default)
var _crouch_toggle := false      # C / Ctrl toggles crouch (and slide when fast)
var _eye := 1.65
var _land_dip := 0.0
var _roll := 0.0
var _dead := false
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0

var _hud_label: Label
var _blood_overlay: ColorRect
var _reticle: Control
var _hitmarker: Hitmarker


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2          # layer 2 = player
	collision_mask = 1 | 4       # collides with world (1) and enemies (3)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)

	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		mouse_sensitivity *= float(cfg.get_value("input", "sensitivity_multiplier", 1.0))

	health = max_health
	wall_jumps_left = air_wall_jumps
	_eye = stand_eye

	_ensure_input_actions()
	_build_body()
	_build_hud()
	Gore.exploded.connect(_on_gore_exploded)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------

func _build_body() -> void:
	shape = CapsuleShape3D.new()
	shape.radius = radius
	shape.height = stand_height
	collision_shape = CollisionShape3D.new()
	collision_shape.shape = shape
	collision_shape.position.y = stand_height * 0.5   # origin = feet
	add_child(collision_shape)

	head = Node3D.new()
	head.position.y = stand_eye
	add_child(head)

	camera = Camera3D.new()
	camera.fov = base_fov
	camera.near = 0.05
	head.add_child(camera)
	camera.make_current()

	weapon = Weapon.new()
	weapon.player = self
	weapon.camera = camera
	camera.add_child(weapon)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_blood_overlay = ColorRect.new()
	_blood_overlay.color = Color(0.35, 0.0, 0.02, 0.0)
	_blood_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_blood_overlay)

	_hud_label = Label.new()
	_hud_label.position = Vector2(16, 12)
	layer.add_child(_hud_label)

	## Dynamic circular reticle driven by the weapon's current spread.
	_reticle = ReticleScript.new()
	layer.add_child(_reticle)
	_reticle.update_spread(weapon.current_spread_px(), weapon.ads_amount)

	_hitmarker = Hitmarker.new()
	layer.add_child(_hitmarker)

	var controls := Label.new()
	controls.text = "Shift: sprint toggle   C/Ctrl: slide/crouch toggle   RMB: ADS   LMB: fire"
	controls.add_theme_font_size_override("font_size", 13)
	controls.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT,
			Control.PRESET_MODE_MINSIZE, 10)
	layer.add_child(controls)


func _ensure_input_actions() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S],
		"move_left": [KEY_A], "move_right": [KEY_D],
		"jump": [KEY_SPACE], "slide": [KEY_C, KEY_CTRL],
		"sprint": [KEY_SHIFT],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k) as Key
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("ads"):
		InputMap.add_action("ads")
		var rb := InputEventMouseButton.new()
		rb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("ads", rb)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var sens := mouse_sensitivity * lerpf(1.0, 1.0 / ads_zoom, weapon.ads_amount)
		rotate_y(-m.relative.x * sens)
		head.rotation.x = clampf(head.rotation.x - m.relative.y * sens,
				-PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ----------------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		return

	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_slide_cd_timer = maxf(_slide_cd_timer - delta, 0.0)
	_wall_cd_timer = maxf(_wall_cd_timer - delta, 0.0)

	# Own edge detection: is_action_just_pressed can be true on 2 consecutive
	# physics ticks, which would eat the double jump on the same press as a jump.
	var jump_down := Input.is_action_pressed("jump")
	_jump_edge = jump_down and not _jump_down_prev
	_jump_down_prev = jump_down
	var slide_down := Input.is_action_pressed("slide")
	_slide_edge = slide_down and not _slide_down_prev
	_slide_down_prev = slide_down
	var sprint_down := Input.is_action_pressed("sprint")
	_sprint_edge = sprint_down and not _sprint_down_prev
	_sprint_down_prev = sprint_down

	# Toggles (edge-detected so a press can never toggle twice)
	if _slide_edge:
		_crouch_toggle = not _crouch_toggle
	if _sprint_edge:
		# If crouched/sliding, Shift always forces sprint on and drops the
		# crouch immediately. Otherwise it behaves as a normal on/off toggle.
		if _crouch_toggle or crouching or state == State.SLIDE:
			_sprint_toggle = true
			_cancel_crouch_for_sprint()
		else:
			_sprint_toggle = not _sprint_toggle
	if Input.is_action_pressed("ads"):
		_sprint_toggle = false         # aiming cancels sprint

	# Godot's forward is -Z, get_vector's "up" is negative Y => forward = input.y < 0
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Sprint is only a movement mode: releasing the movement keys ends it in the
	# same physics tick instead of letting the sprint pose linger while sliding
	# to a stop.
	if _sprint_toggle and input.length() < 0.1:
		_sprint_toggle = false
	var wish_dir := (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	match state:
		State.GROUND: _state_ground(delta, input, wish_dir)
		State.AIR: _state_air(delta, input, wish_dir)
		State.SLIDE: _state_slide(delta, wish_dir)
		State.WALLRUN: _state_wallrun(delta, input)

	_update_body_shape()
	_fall_speed = velocity.y
	move_and_slide()
	_after_move()
	_update_view(delta, input)
	_update_hud()


# ----------------------------------------------------------------------------
# States
# ----------------------------------------------------------------------------

func _state_ground(delta: float, input: Vector2, wish_dir: Vector3) -> void:
	var want_crouch := _crouch_toggle
	# Only stand back up if there's headroom
	crouching = want_crouch or (crouching and not _can_stand())

	# Slide: crouch key while moving fast (also triggers when landing with it held)
	if want_crouch and _horizontal_speed() >= slide_start_speed and _slide_cd_timer <= 0.0:
		_start_slide()
		return

	# Jump (holding = auto-hop, which also skips friction so speed is preserved)
	var jump_wanted := Input.is_action_pressed("jump") if auto_hop \
			else _jump_edge
	if jump_wanted:
		_jump(jump_velocity)
		return

	# Sprint is a true toggle (Shift on / Shift off); it is only cancelled by
	# aiming down sights, never automatically by standing still.
	var target := walk_speed
	if crouching:
		target = crouch_speed
	elif _sprint_toggle:
		target = sprint_speed
	target *= lerpf(1.0, ads_move_mult, weapon.ads_amount)

	_apply_friction(delta, ground_friction)
	if wish_dir != Vector3.ZERO:
		_accelerate(wish_dir, target * minf(input.length(), 1.0), ground_accel, delta)
	velocity.y = 0.0


func _state_air(delta: float, input: Vector2, wish_dir: Vector3) -> void:
	crouching = false
	velocity.y -= gravity * delta

	var wall := _scan_wall()

	# 1) Start a wall-run: airborne, beside a wall, holding forward, fast enough
	if not wall.is_empty() and _wall_cd_timer <= 0.0 and input.y < -0.5 \
			and absf(float(wall["side"])) > 0.5 and _horizontal_speed() >= wallrun_min_speed:
		_start_wallrun(wall)
		return

	# 2) Jump variants (priority: coyote jump > wall jump > double jump)
	if _jump_edge:
		if _coyote_timer > 0.0:
			_jump(jump_velocity)
			return
		if not wall.is_empty() and wall_jumps_left > 0 and _wall_cd_timer <= 0.0:
			wall_jumps_left -= 1
			_wall_jump(wall["normal"])
			return
		if double_jump_ready:
			double_jump_ready = false
			velocity.y = double_jump_velocity
			return

	# 3) Air control (Source-style: capped wish speed => air-strafing works)
	if wish_dir != Vector3.ZERO:
		_accelerate(wish_dir, sprint_speed, air_accel, delta, air_speed_cap)


func _state_slide(delta: float, wish_dir: Vector3) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horiz.length()

	if _jump_edge:
		_end_slide()
		_jump(jump_velocity)          # slide-hop: keeps all horizontal speed
		return
	if not _crouch_toggle or speed < slide_min_speed:
		_end_slide()
		return

	var dir := horiz / speed
	if wish_dir != Vector3.ZERO:       # gentle steering, doesn't add speed
		dir = dir.lerp(wish_dir, clampf(slide_steer * delta, 0.0, 1.0)).normalized()

	# Slopes: downhill adds speed, uphill bleeds it
	var slope := Vector3.ZERO
	if is_on_floor():
		var downhill := Vector3.DOWN.slide(get_floor_normal())
		slope = Vector3(downhill.x, 0.0, downhill.z) * gravity * slide_slope_factor

	speed = maxf(speed - slide_decel * delta, 0.0)
	var new_h := dir * speed + slope * delta
	if new_h.length() > slide_slope_max_speed:
		new_h = new_h.normalized() * slide_slope_max_speed
	velocity.x = new_h.x
	velocity.z = new_h.z
	velocity.y = 0.0


func _state_wallrun(delta: float, input: Vector2) -> void:
	_wallrun_timer += delta
	var wall := _scan_wall()
	var still_on_wall := not wall.is_empty() and absf(float(wall["side"])) > 0.35

	if not still_on_wall or _wallrun_timer > wallrun_max_time or input.y > -0.3 \
			or _horizontal_speed() < wallrun_min_speed * 0.6:
		_end_wallrun()
		return

	var normal: Vector3 = wall["normal"]
	_wallrun_side = wall["side"]

	if _jump_edge:
		_wall_jump(normal)
		return

	# Run along the wall in the direction we're already travelling
	var along := normal.cross(Vector3.UP).normalized()
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if along.dot(horiz) < 0.0:
		along = -along
	var cur := horiz.dot(along)        # along-wall component only (ignores the wall-stick push)
	var speed := cur if cur >= wallrun_speed else move_toward(cur, wallrun_speed, 25.0 * delta)

	velocity.x = along.x * speed - normal.x * wallrun_stick_speed
	velocity.z = along.z * speed - normal.z * wallrun_stick_speed
	velocity.y = maxf(velocity.y - gravity * wallrun_gravity_scale * delta, -3.0)


# ----------------------------------------------------------------------------
# Transitions / actions
# ----------------------------------------------------------------------------

## Shift toggled sprint on: immediately drop crouch/slide posture and stand up
## if there is headroom. The current slide velocity is kept, so this reads as a
## direct slide -> sprint transition rather than a stop.
func _cancel_crouch_for_sprint() -> void:
	_crouch_toggle = false
	if state == State.SLIDE:
		_end_slide()
	if state == State.GROUND:
		if _can_stand():
			crouching = false
			_eye = stand_eye
		else:
			# Low ceiling: sprint is impossible, stay crouched.
			_sprint_toggle = false
			crouching = true
	else:
		crouching = false


func _jump(strength: float) -> void:
	velocity.y = strength
	_coyote_timer = 0.0
	crouching = false
	_crouch_toggle = false         # jumping stands you up
	state = State.AIR


func _start_slide() -> void:
	var dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	var new_speed := minf(_horizontal_speed() + slide_boost, slide_max_speed)
	velocity.x = dir.x * new_speed
	velocity.z = dir.z * new_speed
	velocity.y = 0.0
	crouching = true
	state = State.SLIDE


func _end_slide() -> void:
	state = State.GROUND
	crouching = true               # ground state stands us up if there's headroom
	_slide_cd_timer = slide_cooldown


func _start_wallrun(wall: Dictionary) -> void:
	state = State.WALLRUN
	_wallrun_timer = 0.0
	_wallrun_side = wall["side"]
	velocity.y = maxf(velocity.y, 2.5)   # small upward pop like Titanfall
	double_jump_ready = true


func _end_wallrun() -> void:
	state = State.AIR
	_wall_cd_timer = wall_cooldown


func _wall_jump(normal: Vector3) -> void:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var into := fwd.dot(normal)
	if into < 0.0:
		fwd -= normal * into           # don't kick forward *into* the wall

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var h_into := horiz.dot(normal)
	if h_into < 0.0:
		horiz -= normal * h_into       # keep along-wall momentum, drop into-wall part

	velocity = horiz + normal * wall_jump_push + fwd * wall_jump_forward
	velocity.y = wall_jump_up
	double_jump_ready = true
	_wall_cd_timer = wall_cooldown
	_coyote_timer = 0.0
	state = State.AIR


func _after_move() -> void:
	var on_floor := is_on_floor()
	match state:
		State.GROUND, State.SLIDE:
			if not on_floor:
				state = State.AIR
				crouching = false
				_coyote_timer = coyote_time
		State.AIR, State.WALLRUN:
			if on_floor and velocity.y <= 0.1:
				_land()


func _land() -> void:
	state = State.GROUND
	double_jump_ready = true
	wall_jumps_left = air_wall_jumps
	_land_dip = clampf(-_fall_speed * 0.012, 0.0, 0.25)


# ----------------------------------------------------------------------------
# Movement helpers
# ----------------------------------------------------------------------------

func _horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Quake/Source style acceleration. cap_speed limits the *wish* speed only
## (used in the air), which is what makes air-strafing gain speed.
func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float,
		cap_speed := INF) -> void:
	var capped := minf(wish_speed, cap_speed)
	var add := capped - velocity.dot(wish_dir)
	if add <= 0.0:
		return
	velocity += wish_dir * minf(accel * wish_speed * delta, add)


func _apply_friction(delta: float, friction: float) -> void:
	var speed := _horizontal_speed()
	if speed < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var drop := maxf(speed, stop_speed) * friction * delta
	var k := maxf(speed - drop, 0.0) / speed
	velocity.x *= k
	velocity.z *= k


## Casts 8 horizontal rays around the player. Returns {} or
## {normal, side, position}; side > 0 means the wall is on our right.
func _scan_wall() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * (stand_height * 0.55)
	var right := global_transform.basis.x
	var best := {}
	var best_dist := INF
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := global_transform.basis * Vector3(sin(a), 0.0, cos(a))
		var query := PhysicsRayQueryParameters3D.create(
				origin, origin + dir * (radius + wall_check_distance), 1, [get_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.3:            # floors / ceilings / steep ramps aren't walls
			continue
		var d := origin.distance_to(hit["position"])
		if d < best_dist:
			best_dist = d
			best = {"normal": n, "side": -n.dot(right), "position": hit["position"]}
	return best


func _can_stand() -> bool:
	var extra := stand_height - shape.height
	if extra <= 0.01:
		return true
	return not test_move(global_transform, Vector3.UP * extra)


func _update_body_shape() -> void:
	var h := crouch_height if (state == State.SLIDE or crouching) else stand_height
	if not is_equal_approx(shape.height, h):
		shape.height = h
		collision_shape.position.y = h * 0.5


# ----------------------------------------------------------------------------
# Camera / HUD / damage
# ----------------------------------------------------------------------------

func _update_view(delta: float, input: Vector2) -> void:
	var low := state == State.SLIDE or crouching
	_eye = lerpf(_eye, crouch_eye if low else stand_eye, 1.0 - exp(-14.0 * delta))
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-10.0 * delta))
	head.position.y = _eye - _land_dip

	# Roll: lean away from the wall while wall-running, tiny lean when strafing.
	# (Flip the sign of wallrun_tilt_deg if you prefer leaning into the wall.)
	var target_roll := -input.x * deg_to_rad(1.2)
	if state == State.WALLRUN:
		target_roll = _wallrun_side * deg_to_rad(wallrun_tilt_deg)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-8.0 * delta))
	camera.rotation.z = _roll

	# ADS recoil lives on the camera (not the reticle) and springs back.
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, 1.0 - exp(-8.0 * delta))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, 1.0 - exp(-8.0 * delta))
	camera.rotation.x = _recoil_pitch
	camera.rotation.y = _recoil_yaw

	# FOV: widens with speed, narrows when aiming (zoom factor = ads_zoom)
	var ads := weapon.ads_amount
	var speed_fov := base_fov + clampf((_horizontal_speed() - walk_speed) * 1.2, 0.0, 14.0)
	var ads_fov := rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / ads_zoom))
	camera.fov = lerpf(camera.fov, lerpf(speed_fov, ads_fov, ads), 1.0 - exp(-14.0 * delta))

	# The reticle ring tracks the weapon's live angular spread in pixels.
	_reticle.update_spread(weapon.current_spread_px(), ads)

	_blood_overlay.color.a = move_toward(_blood_overlay.color.a, 0.0, delta * 0.35)


func _update_hud() -> void:
	var flags := ""
	if _sprint_toggle:
		flags += "  SPRINT"
	if _crouch_toggle:
		flags += "  CROUCH"
	if weapon.ads_amount > 0.45:
		flags += "  ADS"
	_hud_label.text = "Speed %.1f m/s   %s   HP %d   [%s]%s" % [
		_horizontal_speed(), State.find_key(state), int(health), weapon.current_name(), flags]


func is_sprinting() -> bool:
	return _sprint_toggle and state == State.GROUND and not crouching \
			and _horizontal_speed() > 1.2 \
			and Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1


func is_dead() -> bool:
	return _dead


## Screen-space centre of the reticle, including its UI recoil offset. The
## weapon projects this point into the world for proc-aim and bullet direction.
func get_reticle_screen_center() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var offset := Vector2.ZERO
	if _reticle:
		offset = _reticle.recoil_offset
	return viewport_size * 0.5 + offset


func show_hitmarker(kill: bool, world_pos: Vector3) -> void:
	var screen_pos := get_viewport().get_visible_rect().size * 0.5
	if not camera.is_position_behind(world_pos):
		screen_pos = camera.unproject_position(world_pos)
	_hitmarker.flash(kill, screen_pos)


## Hip-fire recoil is given to the reticle UI (up + horizontal jitter).
func add_reticle_recoil(up_px: float, jitter_px: float) -> void:
	if _reticle:
		_reticle.add_shot_recoil(up_px, jitter_px)


## ADS recoil is applied straight to the camera instead of the reticle.
func add_camera_recoil(pitch: float, yaw: float) -> void:
	_recoil_pitch = clampf(_recoil_pitch + pitch, -0.18, 0.18)
	_recoil_yaw = clampf(_recoil_yaw + yaw, -0.12, 0.12)


func kick_view(pitch: float, yaw: float) -> void:
	head.rotation.x = clampf(head.rotation.x + pitch, -PITCH_LIMIT, PITCH_LIMIT)
	rotate_y(yaw)


func take_damage(amount: float, _hit_pos := Vector3.ZERO, _hit_normal := Vector3.ZERO,
		_dir := Vector3.ZERO) -> void:
	if _dead:
		return
	health -= amount
	health_changed.emit(health)
	_blood_overlay.color.a = maxf(_blood_overlay.color.a, 0.25)
	if health <= 0.0:
		_dead = true
		died.emit()


func _on_gore_exploded(pos: Vector3, intensity: float) -> void:
	# Blood on the lens if an enemy pops close to you
	var dist := global_position.distance_to(pos)
	if dist < 6.0:
		var a := clampf((1.0 - dist / 6.0) * 0.55 * intensity, 0.0, 0.8)
		_blood_overlay.color.a = maxf(_blood_overlay.color.a, a)
