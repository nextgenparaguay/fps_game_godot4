class_name Enemy
extends CharacterBody3D
## Cover-based ranged enemy (state machine).
##
## Instead of charging the player, the enemy plays the map:
##
##   ADVANCE   no cover yet: ask the CoverManager for a hidden, reachable spot and
##             hop cover-to-cover toward the player. With no cover available it
##             walks the navmesh and shoots from where it stands.
##   TO_COVER  walk to the claimed spot (re-plans if the player flanks it).
##   HOLD      hidden (crouched behind low cover), waits a random time.
##   PEEK      steps out (or stands up) to a spot with a line of sight, aims for
##             `reaction_time`, fires a burst, then goes back.
##
## After a few peeks, or when hurt while exposed, it relocates to new cover.
##
## Bullets are the same RifleProjectile the player uses (swept ray, finite speed,
## tracer). Accuracy is tunable with the exported variables in the "Accuracy"
## group; `spread_scale` is a single knob that scales all of them (difficulty).
##
## Every shot emits `shot_fired` so the arena can record it for the replay.

signal died
signal exploded_at(position: Vector3, intensity: float, shot_dir: Vector3)
signal shot_fired(muzzle: Vector3, target: Vector3, speed: float)

enum State { ADVANCE, TO_COVER, HOLD, PEEK }

const STAND_EYE := 1.55
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1

@export_group("Body")
@export var max_health := 100.0
@export var move_speed := 4.2
@export var gravity := 22.0

@export_group("Weapon")
@export var damage := 7.0
@export var bullet_speed := 85.0
@export var burst_min := 2
@export var burst_max := 4
@export var shot_interval := 0.14        ## seconds between shots inside a burst
@export var max_shoot_range := 70.0

@export_group("Accuracy")
@export var spread_scale := 1.0          ## difficulty knob: multiplies every spread value below
@export var aim_spread_deg := 1.6        ## base cone half-angle while standing still
@export var spread_per_shot_deg := 0.55  ## bloom added by each shot in a burst
@export var max_spread_deg := 6.0
@export var moving_spread_deg := 3.0     ## extra cone while the enemy itself is walking
@export var aim_error_deg := 1.4         ## per-burst systematic miss (random direction)
@export var reaction_time := 0.45        ## seconds to aim after stepping out before the first shot

@export_group("Cover behaviour")
@export var preferred_range_min := 12.0
@export var preferred_range_max := 34.0
@export var hold_time_min := 1.2
@export var hold_time_max := 3.0
@export var peeks_before_relocate := 3
@export var retreat_chance := 0.55       ## chance to relocate after taking damage while exposed

var health := 0.0
var state := State.ADVANCE

var _dying := false
var _dead := false
var _flash := 0.0
var _last_shot_dir := Vector3.ZERO
var _player: Player
var _cover_mgr: CoverManager
var _cover: CoverManager.CoverPoint
var _avoid_cover: CoverManager.CoverPoint
var _peek_pos := Vector3.ZERO

var _mat: StandardMaterial3D
var _agent: NavigationAgent3D
var _body: Node3D
var _shape: CapsuleShape3D
var _cs: CollisionShape3D
var _muzzle: Marker3D
var _flash_mesh: MeshInstance3D
var _flash_timer := 0.0
var _safe_velocity := Vector3.ZERO
var _desired := Vector3.ZERO
var _repath_timer := 0.0
var _crouched := false

var _state_time := 0.0
var _hold_for := 0.0
var _aim_timer := 0.0
var _burst_left := 0
var _shot_timer := 0.0
var _burst_shots := 0
var _burst_error := Vector2.ZERO
var _peeks_done := 0
var _los := false
var _los_timer := 0.0
var _cover_retry := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	collision_layer = 4          # layer 3 = enemies
	collision_mask = 1 | 2 | 4   # world + player + other enemies
	_repath_timer = randf() * 0.3
	_los_timer = randf() * 0.1
	_cover_retry = randf() * 0.4

	_shape = CapsuleShape3D.new()
	_shape.radius = 0.4
	_shape.height = STAND_HEIGHT
	_cs = CollisionShape3D.new()
	_cs.shape = _shape
	_cs.position.y = STAND_HEIGHT * 0.5
	add_child(_cs)

	# Visuals live under _body so crouching can squash them without scaling the
	# physics body (non-uniform scale on a CharacterBody3D is not supported).
	_body = Node3D.new()
	add_child(_body)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.72, 0.4, 0.36)
	_mat.emission_enabled = true
	_mat.emission = Color.BLACK

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.4
	body_mesh.height = 1.8
	body_mesh.material = _mat
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.position.y = 0.9
	_body.add_child(body)

	# "Visor" shows which way it faces (front = -Z)
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.5, 0.12, 0.2)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.05, 0.05, 0.05)
	visor_mesh.material = visor_mat
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.position = Vector3(0, 1.5, -0.32)
	_body.add_child(visor)

	_build_gun()

	_agent = NavigationAgent3D.new()
	_agent.radius = 0.6
	_agent.height = 1.8
	_agent.max_speed = move_speed
	_agent.path_desired_distance = 0.6
	_agent.path_max_distance = 2.2
	_agent.target_desired_distance = 0.5
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = 7.0
	_agent.max_neighbors = 12
	_agent.time_horizon_agents = 1.8
	_agent.time_horizon_obstacles = 1.0
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)


func _build_gun() -> void:
	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.08, 0.08, 0.09)
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.09, 0.12, 0.75)
	gun_mesh.material = gun_mat
	var gun := MeshInstance3D.new()
	gun.mesh = gun_mesh
	gun.position = Vector3(0.3, 1.15, -0.5)
	_body.add_child(gun)

	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0.3, 1.17, -0.92)
	_body.add_child(_muzzle)

	var fm := SphereMesh.new()
	fm.radius = 0.1
	fm.height = 0.2
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.8, 0.35)
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.7, 0.25)
	flash_mat.emission_energy_multiplier = 4.0
	fm.material = flash_mat
	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.mesh = fm
	_flash_mesh.visible = false
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_flash_mesh)


func _exit_tree() -> void:
	_release_cover()


# ----------------------------------------------------------------------------
# Tick
# ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _cover_mgr == null or not is_instance_valid(_cover_mgr):
		_cover_mgr = get_tree().get_first_node_in_group("cover_manager") as CoverManager

	_flash = move_toward(_flash, 0.0, delta * 8.0)
	_mat.emission = Color(1.0, 0.1, 0.05) * _flash
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_mesh.visible = false

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	_desired = Vector3.ZERO
	var face_player := false

	if _player != null and not _player.is_dead():
		_update_los(delta)
		_state_time += delta
		match state:
			State.ADVANCE:
				face_player = _tick_advance(delta)
			State.TO_COVER:
				_tick_to_cover(delta)
			State.HOLD:
				face_player = true
				_tick_hold()
			State.PEEK:
				face_player = true
				_tick_peek(delta)
	else:
		_set_crouch(false)

	_apply_movement(delta, face_player)


func _apply_movement(delta: float, face_player: bool) -> void:
	var nav_ready := NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0
	if nav_ready:
		_agent.velocity = _desired       # avoidance result arrives in _on_velocity_computed
	else:
		_safe_velocity = _desired

	velocity.x = _safe_velocity.x
	velocity.z = _safe_velocity.z
	if _desired.length_squared() > 0.01:
		var sep := _separation_velocity()
		velocity.x += sep.x
		velocity.z += sep.z

	var face := Vector3(velocity.x, 0.0, velocity.z)
	if _player != null and (face_player or face.length() < 0.5):
		face = _player.global_position - global_position
		face.y = 0.0
	if face.length() > 0.01:
		face = face.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-10.0 * delta))
	move_and_slide()

	# Stuck detection: if it is meant to move but is not getting anywhere,
	# drop the current plan and pick again.
	if _desired.length_squared() > 0.01:
		if global_position.distance_to(_last_pos) < move_speed * delta * 0.15:
			_stuck_timer += delta
		else:
			_stuck_timer = 0.0
		if _stuck_timer > 1.2:
			_stuck_timer = 0.0
			_go_advance(true)
	else:
		_stuck_timer = 0.0
	_last_pos = global_position


# ----------------------------------------------------------------------------
# States
# ----------------------------------------------------------------------------

## Returns true when the enemy should face the player (it is shooting).
func _tick_advance(delta: float) -> bool:
	_set_crouch(false)
	_cover_retry -= delta
	if _cover_mgr != null and _cover_retry <= 0.0:
		_cover_retry = 0.5
		var c := _cover_mgr.find_cover(self, _player_eye(), preferred_range_min,
				preferred_range_max, _avoid_cover)
		if c != null:
			_take_cover(c)
			return false

	# No cover available: close to a comfortable range over the navmesh and
	# shoot from the open as a fallback (never a melee rush).
	var dist := _flat_dist(_player.global_position)
	if dist > preferred_range_min:
		_move_toward(_player.global_position, move_speed, delta)
	if _los and dist < max_shoot_range:
		_open_fire(delta)
		return true
	return false


func _tick_to_cover(delta: float) -> void:
	_set_crouch(false)
	if _cover == null:
		_go_advance(false)
		return
	# Cover compromised (the player moved and can now see the spot): pick again.
	if _cover_mgr != null and _state_time > 0.4 and not _cover_mgr.is_hidden(_cover, _player_eye()):
		_go_advance(true)
		return
	if _flat_dist(_cover.pos) < 0.7:
		_enter_hold()
		return
	_move_toward(_cover.pos, move_speed, delta)
	if _state_time > 14.0:           # taking too long: give up
		_go_advance(true)


func _tick_hold() -> void:
	if _cover == null:
		_go_advance(false)
		return
	_set_crouch(_cover.low)
	if _state_time < _hold_for:
		return
	var dist := _flat_dist(_player.global_position)
	if dist > preferred_range_max * 1.25 or _peeks_done >= peeks_before_relocate:
		_go_advance(true)
		return
	var p: Variant = _cover_mgr.find_peek(_cover, _player_eye()) if _cover_mgr != null else null
	if p == null:
		_go_advance(true)
		return
	_peek_pos = p
	_enter_peek()


func _tick_peek(delta: float) -> void:
	# Burst finished: back behind cover.
	if _burst_shots > 0 and _burst_left <= 0 and _shot_timer <= 0.0:
		_peeks_done += 1
		_enter_hold()
		return

	_set_crouch(false)
	# Step out to the firing position (low cover: just stand up in place).
	if _cover != null and not _cover.low and _flat_dist(_peek_pos) > 0.35:
		_move_toward(_peek_pos, move_speed, delta)
		if _state_time > 4.0:
			_enter_hold()
		return

	if not _los:
		# The player moved out of sight: give up this peek after a moment.
		if _state_time > 1.5:
			_peeks_done += 1
			_enter_hold()
		return

	if _aim_timer > 0.0:
		_aim_timer -= delta
		return
	_shoot_burst(delta)
	if _state_time > 8.0:
		_enter_hold()


# ----------------------------------------------------------------------------
# State transitions
# ----------------------------------------------------------------------------

## Leave the current plan and look for cover again. With `avoid_current` the
## spot being left is excluded so the enemy actually moves somewhere new.
func _go_advance(avoid_current: bool) -> void:
	_avoid_cover = _cover if avoid_current else null
	_release_cover()
	state = State.ADVANCE
	_state_time = 0.0
	_cover_retry = 0.0
	_peeks_done = 0
	_burst_left = 0
	_burst_shots = 0
	_aim_timer = 0.0


func _take_cover(c: CoverManager.CoverPoint) -> void:
	_release_cover()
	_cover = c
	_cover_mgr.claim(c, self)
	state = State.TO_COVER
	_state_time = 0.0


func _enter_hold() -> void:
	state = State.HOLD
	_state_time = 0.0
	_hold_for = randf_range(hold_time_min, hold_time_max)
	_burst_left = 0
	_burst_shots = 0
	_shot_timer = 0.0


func _enter_peek() -> void:
	state = State.PEEK
	_state_time = 0.0
	_aim_timer = reaction_time * randf_range(0.8, 1.3)
	_burst_left = randi_range(burst_min, burst_max)
	_burst_shots = 0
	_shot_timer = 0.0
	_burst_error = _random_cone(aim_error_deg * spread_scale)


func _release_cover() -> void:
	if _cover != null and _cover_mgr != null and is_instance_valid(_cover_mgr):
		_cover_mgr.release(_cover, self)
	_cover = null


# ----------------------------------------------------------------------------
# Shooting
# ----------------------------------------------------------------------------

## Fire from the open (fallback when no cover exists): short bursts with pauses.
func _open_fire(delta: float) -> void:
	if _aim_timer > 0.0:
		_aim_timer -= delta
		return
	if _burst_left <= 0 and _shot_timer <= 0.0:
		_burst_left = randi_range(burst_min, burst_max)
		_burst_shots = 0
		_burst_error = _random_cone(aim_error_deg * spread_scale)
		_aim_timer = reaction_time * randf_range(1.0, 2.5)   # pause between bursts
		return
	_shoot_burst(delta)


func _shoot_burst(delta: float) -> void:
	_shot_timer -= delta
	if _burst_left > 0 and _shot_timer <= 0.0 and _los:
		_fire_one()
		_burst_left -= 1
		_burst_shots += 1
		_shot_timer = shot_interval
	elif _burst_left <= 0 and _shot_timer <= 0.0:
		_shot_timer = 0.0


func _fire_one() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var from := _muzzle.global_position
	var aim_point := _player.global_position + Vector3.UP * (0.8 if _player.crouching else 1.15)
	var dir := (aim_point - from).normalized()

	# Dispersion: base cone + bloom per shot in the burst, a penalty for the
	# enemy walking or the player sprinting, plus the per-burst systematic error.
	var spread := aim_spread_deg + spread_per_shot_deg * float(_burst_shots)
	if _player.velocity.length() > 4.0:
		spread += moving_spread_deg * 0.5
	if _desired.length_squared() > 0.01:
		spread += moving_spread_deg
	spread = minf(spread, max_spread_deg) * spread_scale
	var cone := _random_cone(spread) + _burst_error
	dir = _rotate_dir(dir, cone)

	var target := from + dir * max_shoot_range
	var bullet := RifleProjectile.new()
	bullet.hit_mask = RifleProjectile.ENEMY_HIT_MASK
	bullet.tracer_tint = RifleProjectile.ENEMY_TRACER
	parent.add_child(bullet)
	bullet.setup(from, target, bullet_speed, damage, self, null)

	_flash_mesh.visible = true
	_flash_timer = 0.05
	shot_fired.emit(from, target, bullet_speed)


## Random offset in degrees (x = yaw, y = pitch) inside a circle of `radius_deg`.
func _random_cone(radius_deg: float) -> Vector2:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius_deg
	return Vector2(cos(a), sin(a)) * r


func _rotate_dir(dir: Vector3, offset_deg: Vector2) -> Vector3:
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	var out := dir.rotated(up, deg_to_rad(offset_deg.x))
	out = out.rotated(right, deg_to_rad(offset_deg.y))
	return out.normalized()


# ----------------------------------------------------------------------------
# Perception, movement helpers
# ----------------------------------------------------------------------------

func _player_eye() -> Vector3:
	if _player.camera != null:
		return _player.camera.global_position
	return _player.global_position + Vector3.UP * 1.6


func _update_los(delta: float) -> void:
	_los_timer -= delta
	if _los_timer > 0.0:
		return
	_los_timer = 0.1
	var from := global_position + Vector3.UP * STAND_EYE
	var to := _player.global_position + Vector3.UP * 1.1
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	_los = from.distance_to(to) < max_shoot_range \
			and get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _set_crouch(on: bool) -> void:
	if on == _crouched:
		return
	_crouched = on
	var h := CROUCH_HEIGHT if on else STAND_HEIGHT
	_shape.height = h
	_cs.position.y = h * 0.5
	_body.scale.y = h / STAND_HEIGHT


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _move_toward(target: Vector3, speed: float, delta: float) -> void:
	var nav_ready := NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0
	if not nav_ready:
		return
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = 0.25 + randf() * 0.1
		_agent.target_position = target
	if _agent.is_navigation_finished():
		return
	var step := _agent.get_next_path_position() - global_position
	step.y = 0.0
	if step.length() > 0.05:
		_desired = step.normalized() * speed


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity


func _separation_velocity() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.001 and d < 1.7:
			push += away / d * (1.0 - d / 1.7)
	if push.length_squared() > 0.0001:
		push = push.normalized() * minf(push.length(), 1.0) * 1.6
	return push


# ----------------------------------------------------------------------------
# Damage / death
# ----------------------------------------------------------------------------

## Returns true if this hit was lethal (used for the kill hitmarker).
func take_damage(amount: float, hit_pos: Vector3, hit_normal: Vector3, shot_dir: Vector3) -> bool:
	if _dead:
		return false
	health -= amount
	_flash = 1.0
	_last_shot_dir = shot_dir
	Gore.blood_puff(hit_pos, hit_normal)

	# Hurt while out of cover: duck back, often to a different spot.
	if state == State.PEEK or (state == State.ADVANCE and _los):
		if randf() < retreat_chance:
			_go_advance(true)

	# Defer the explosion to the end of the frame so every projectile that
	# lands this frame counts toward the overkill amount.
	if health <= 0.0 and not _dying:
		_dying = true
		_explode.call_deferred()
	return health <= 0.0


func _explode() -> void:
	_dead = true
	_release_cover()
	var overkill := -health
	var intensity := clampf(1.0 + overkill / max_health, 1.0, 2.5)
	Gore.play_death_sound(global_position + Vector3.UP)
	exploded_at.emit(global_position + Vector3.UP, intensity, _last_shot_dir)
	Gore.explode(global_position + Vector3.UP * 1.0, intensity, _last_shot_dir)
	died.emit()
	queue_free()
