class_name Weapon
extends Node3D
## Automatic rifle with physical projectiles, ADS zoom, bloom and procedural aim.
##
## The rifle is a placeholder built from primitives.  Two things make it feel
## alive:
##   1. The whole weapon pivot is rotated every frame so the barrel points at
##      the world point under the projected reticle.
##   2. Both arms are solved with analytic two-bone IK to the pistol grip and
##      handguard, so the hands stay on the gun while it is aimed/sprinted.
##
## Recoil routing follows the requested rules:
##   hip-fire  -> reticle UI kick (up + horizontal jitter), no camera kick
##   ADS       -> camera kick, reticle recoil disabled
##
## Shots are real projectiles spawned at the muzzle; see projectile.gd.

const MAX_RANGE := 400.0
const HIT_MASK := 1 | 4              # world + enemies
const ProjectileScript := preload("res://scripts/projectile.gd")

const HIP_POS := Vector3(0.22, -0.24, -0.56)
const ADS_POS := Vector3(0.0, -0.069, -0.68)
const ADS_SPEED := 12.0
const SPRINT_POS_OFFSET := Vector3(0.02, -0.045, 0.05)
const SPRINT_POSE_DEG := Vector3(-17.0, 27.0, -8.0)
const SPRINT_FIRE_OVERRIDE_SPEED := 26.0
const FIRE_OVERRIDE_SPEED := 20.0

@export_group("Rifle")
@export var fire_rate := 10.5
@export var damage := 16.0
@export var projectile_speed := 165.0
@export var hip_spread_deg := 0.45
@export var ads_spread_deg := 0.05
@export var bloom_per_shot_deg := 0.86
@export var max_bloom_deg := 4.8
@export var bloom_recovery_deg := 5.0
@export var movement_spread_deg := 1.35
@export var air_spread_deg := 2.2
@export var sprint_spread_deg := 2.1

@export_group("Recoil")
@export var hip_reticle_kick_px := 26.0
@export var hip_reticle_jitter_px := 8.6
@export var ads_camera_pitch := 0.0105
@export var ads_camera_yaw := 0.0020

var player: Player
var camera: Camera3D
var ads_amount := 0.0

var _cooldown := 0.0
var _ads_t := 0.0
var _sprint_t := 0.0
var _fire_override := 0.0
var _kick := 0.0
var _bob_t := 0.0
var _bloom := 0.0
var _flash_timer := 0.0
var _firing := false
var _sprint_fire_timer := 0.0

var _pivot: Node3D
var _pose: Node3D
var _rifle: Node3D
var _muzzle: Marker3D
var _flash: Node3D
var _grip_right: Marker3D
var _grip_left: Marker3D

var _arms: Node3D
var _upper_r: MeshInstance3D
var _fore_r: MeshInstance3D
var _hand_r: MeshInstance3D
var _upper_l: MeshInstance3D
var _fore_l: MeshInstance3D
var _hand_l: MeshInstance3D
var _skin_mat: StandardMaterial3D
var _sleeve_mat: StandardMaterial3D


func current_name() -> String:
	return "Rifle"


func _ready() -> void:
	_build_weapon()
	_build_arms()


# ----------------------------------------------------------------------------
# Tick
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or player.is_dead():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	if captured:
		if Input.is_action_pressed("fire") and _cooldown <= 0.0:
			fire()

	var sprinting := player.is_sprinting()
	var want_ads := captured and Input.is_action_pressed("ads") and not sprinting
	_ads_t = move_toward(_ads_t, 1.0 if want_ads else 0.0, delta * ADS_SPEED)
	ads_amount = smoothstep(0.0, 1.0, _ads_t)

	_firing = captured and Input.is_action_pressed("fire")
	_sprint_fire_timer = maxf(_sprint_fire_timer - delta, 0.0)
	_sprint_t = lerpf(_sprint_t, 1.0 if sprinting else 0.0, 1.0 - exp(-10.0 * delta))

	var firing_from_sprint := (_firing or _sprint_fire_timer > 0.0) \
			and _sprint_t > 0.18 and ads_amount < 0.35
	var override_target := 1.0 if firing_from_sprint else 0.0
	_fire_override = move_toward(_fire_override, override_target,
			delta * (SPRINT_FIRE_OVERRIDE_SPEED if override_target > 0.5 else FIRE_OVERRIDE_SPEED))

	_bloom = maxf(_bloom - bloom_recovery_deg * delta, 0.0)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-12.0 * delta))

	_update_viewmodel(delta)

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash.visible = false


# ----------------------------------------------------------------------------
# Shooting
# ----------------------------------------------------------------------------

func fire() -> void:
	_cooldown = 1.0 / maxf(fire_rate, 0.1)

	# A shot taken from the sprint pose snaps the rifle forward immediately and
	# holds it forward for a moment so even a quick tap fully overrides sprint.
	if _sprint_t > 0.18:
		_fire_override = 1.0
		_sprint_fire_timer = 0.30
		_pose.rotation_degrees = Vector3.ZERO
		_pivot.position = HIP_POS
	# Re-align just before reading the muzzle so the projectile leaves the
	# barrel as it is rendered this frame, not last frame's pose.
	_align_to_aim()

	var spread_px := current_spread_px()
	var cam_origin := camera.global_position
	var screen_center := player.get_reticle_screen_center()

	# Sample a uniformly random point inside the reticle's circular spread. This
	# is the same radius the player sees, so the bullet pattern and the ring can
	# never disagree.
	var spread_angle := randf() * TAU
	var spread_radius := spread_px * sqrt(randf())
	var shot_screen := screen_center + Vector2(cos(spread_angle), sin(spread_angle)) * spread_radius
	var aim_dir := camera.project_ray_normal(shot_screen).normalized()

	# The world point under the (centre) projected reticle / spread sample.
	var hit := _ray(cam_origin, cam_origin + aim_dir * MAX_RANGE)
	var target := cam_origin + aim_dir * MAX_RANGE
	var aim_distance := MAX_RANGE
	if not hit.is_empty():
		target = hit["position"]
		aim_distance = cam_origin.distance_to(target)

	var muzzle_pos := _muzzle.global_position
	# If a wall is closer than the visible muzzle, don't spawn the bullet behind
	# the wall: start just in front of the camera along the shot direction.
	var spawn := muzzle_pos
	if aim_distance < cam_origin.distance_to(muzzle_pos) + 0.10:
		spawn = cam_origin + aim_dir * 0.30

	var projectile = ProjectileScript.new()
	get_tree().current_scene.add_child(projectile)
	projectile.setup(spawn, target, projectile_speed, damage, player, self)

	# Consecutive shots open the reticle up to a hard cap.
	_bloom = minf(_bloom + bloom_per_shot_deg, max_bloom_deg)
	_kick = minf(_kick + 0.55, 1.0)
	_flash.visible = true
	_flash_timer = 0.045

	# Hip-fire recoil is UI-only; ADS recoil is applied to the camera.
	if ads_amount > 0.45:
		var pitch := ads_camera_pitch * randf_range(0.85, 1.15)
		var yaw := randf_range(-ads_camera_yaw, ads_camera_yaw)
		player.add_camera_recoil(pitch, yaw)
	else:
		player.add_reticle_recoil(hip_reticle_kick_px, hip_reticle_jitter_px)


func notify_projectile_hit(collider: Object, lethal: bool, hit_pos: Vector3) -> void:
	if collider is Enemy:
		player.show_hitmarker(lethal, hit_pos)


func notify_environment_hit(_pos: Vector3, _normal: Vector3) -> void:
	pass


## Current cone half-angle in degrees, including movement/air/sprint and bloom.
func current_spread_deg() -> float:
	var base := lerpf(hip_spread_deg, ads_spread_deg, ads_amount)
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	var motion := clampf(hspeed / maxf(player.sprint_speed, 0.1), 0.0, 1.0) * movement_spread_deg
	if not player.is_on_floor():
		motion += air_spread_deg
	if player.is_sprinting():
		motion += sprint_spread_deg
	motion *= lerpf(1.0, 0.22, ads_amount)
	var bloom := _bloom * lerpf(1.0, 0.55, ads_amount)
	return base + motion + bloom


## Converts the current angular spread to a pixel radius at the reticle.
func current_spread_px() -> float:
	var h := get_viewport().get_visible_rect().size.y
	if h <= 1.0:
		h = 720.0
	var fov := maxf(camera.fov, 1.0) if camera else 90.0
	var half_tan := tan(deg_to_rad(fov) * 0.5)
	if half_tan <= 0.0001:
		return 7.0
	return tan(deg_to_rad(current_spread_deg())) / half_tan * h * 0.5


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if is_instance_valid(player):
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, exclude)
	return space.intersect_ray(query)


## The point the reticle projects to in the 3D world (includes UI recoil).
func get_aim_point() -> Vector3:
	if player == null:
		return camera.global_position - camera.global_transform.basis.z * MAX_RANGE
	var screen := player.get_reticle_screen_center()
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen).normalized()
	var hit := _ray(from, from + dir * MAX_RANGE)
	if hit.is_empty():
		return from + dir * MAX_RANGE
	return hit["position"]


# ----------------------------------------------------------------------------
# Viewmodel
# ----------------------------------------------------------------------------

func _update_viewmodel(delta: float) -> void:
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	_bob_t += delta * (5.0 + hspeed * 0.8)
	var bob_amount := clampf(hspeed / 11.0, 0.0, 1.0) * (1.0 - ads_amount * 0.92)
	var bob := Vector3(sin(_bob_t) * 0.006, -absf(cos(_bob_t)) * 0.006, 0.0) * bob_amount

	var pos := HIP_POS.lerp(ADS_POS, ads_amount)
	var sprint_pose_weight := _sprint_t * (1.0 - _fire_override)
	pos += SPRINT_POS_OFFSET * sprint_pose_weight
	pos += bob
	pos.z += _kick * 0.035 * (1.0 - ads_amount * 0.55)
	_pivot.position = pos

	# The sprint pose points the muzzle across the body. While firing we blend
	# it out quickly so the rifle points straight at the reticle aim point.
	var pose := SPRINT_POSE_DEG * sprint_pose_weight
	pose.z += sin(_bob_t * 0.5) * 1.1 * sprint_pose_weight
	_pose.rotation_degrees = pose

	# Rotate the pivot so local -Z (the bore) points precisely at the projected
	# reticle point.  Called after the pose so the visible muzzle is where the
	# projectile will actually spawn.
	_align_to_aim()

	_update_arms()


func _align_to_aim() -> void:
	var target := get_aim_point()
	# Very close walls can place the hit point behind the viewmodel pivot; use
	# a safe forward fallback so look_at never flips the rifle around.
	if camera.global_position.distance_squared_to(target) < 1.0:
		target = camera.global_position - camera.global_transform.basis.z * 2.0
	var up := camera.global_transform.basis.y
	_pivot.look_at(target, up)


func _update_arms() -> void:
	if _pivot == null:
		return
	var grip_r := _arms.to_local(_grip_right.global_position)
	var grip_l := _arms.to_local(_grip_left.global_position)

	var shoulder_r := Vector3(0.30, -0.55, -0.18)
	var shoulder_l := Vector3(-0.18, -0.58, -0.50)
	var pole_r := shoulder_r + Vector3(0.55, -0.45, -0.05)
	var pole_l := shoulder_l + Vector3(-0.50, -0.50, 0.15)

	var r := _solve_two_bone(shoulder_r, grip_r, 0.27, 0.30, pole_r)
	var l := _solve_two_bone(shoulder_l, grip_l, 0.40, 0.43, pole_l)

	_place_bone(_upper_r, shoulder_r, r["elbow"])
	_place_bone(_fore_r, r["elbow"], r["hand"])
	_place_bone(_upper_l, shoulder_l, l["elbow"])
	_place_bone(_fore_l, l["elbow"], l["hand"])
	_place_hand(_hand_r, r["hand"])
	_place_hand(_hand_l, l["hand"])


## Analytic two-bone IK. Returns elbow/hand points in the arms-local space.
func _solve_two_bone(shoulder: Vector3, target: Vector3, l1: float, l2: float,
		pole: Vector3) -> Dictionary:
	var to := target - shoulder
	var dist := clampf(to.length(), 0.01, l1 + l2 - 0.001)
	var dir := to.normalized()
	var cos_angle := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)
	cos_angle = clampf(cos_angle, -1.0, 1.0)
	var angle := acos(cos_angle)

	var bend := pole - shoulder
	bend -= dir * bend.dot(dir)
	if bend.length_squared() < 0.0001:
		bend = Vector3.DOWN
	bend = bend.normalized()

	var elbow := shoulder + dir * (cos(angle) * l1) + bend * (sin(angle) * l1)
	var hand := shoulder + dir * dist
	return {"elbow": elbow, "hand": hand}


func _place_bone(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		return
	var y := d / length
	var ref := Vector3.UP
	if absf(y.dot(ref)) > 0.95:
		ref = Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	mi.scale = Vector3(1.0, length, 1.0)


func _place_hand(hand: MeshInstance3D, pos: Vector3) -> void:
	hand.position = pos
	hand.rotation = Vector3.ZERO


# ----------------------------------------------------------------------------
# Placeholder model
# ----------------------------------------------------------------------------

func _build_weapon() -> void:
	_pivot = Node3D.new()
	_pivot.name = "AimPivot"
	_pivot.position = HIP_POS
	add_child(_pivot)

	_pose = Node3D.new()
	_pose.name = "SprintPose"
	_pose.scale = Vector3(0.82, 0.82, 0.82)
	_pivot.add_child(_pose)

	_rifle = Node3D.new()
	_rifle.name = "Rifle"
	_pose.add_child(_rifle)

	var dark := _mat(Color(0.10, 0.105, 0.12), 0.7, 0.35)
	var grey := _mat(Color(0.26, 0.27, 0.30), 0.55, 0.5)
	var accent := _mat(Color(0.92, 0.42, 0.08), 0.25, 0.55)
	var steel := _mat(Color(0.17, 0.18, 0.20), 0.85, 0.28)

	_box(_rifle, Vector3(0.072, 0.105, 0.48), Vector3(0, 0, 0), dark)                     # receiver
	_box(_rifle, Vector3(0.064, 0.062, 0.36), Vector3(0, 0.010, -0.42), grey)             # handguard
	_cyl(_rifle, 0.012, 0.36, Vector3(0, 0.012, -0.77), steel)                            # barrel
	_cyl(_rifle, 0.022, 0.085, Vector3(0, 0.012, -0.96), dark)                            # muzzle brake
	_box(_rifle, Vector3(0.048, 0.020, 0.20), Vector3(0, 0.064, -0.44), dark)              # top rail
	_box(_rifle, Vector3(0.012, 0.032, 0.012), Vector3(0, 0.085, -0.62), steel)            # front sight post
	_box(_rifle, Vector3(0.008, 0.014, 0.012), Vector3(-0.022, 0.083, -0.06), dark)        # rear sight left
	_box(_rifle, Vector3(0.008, 0.014, 0.012), Vector3(0.022, 0.083, -0.06), dark)         # rear sight right
	_box(_rifle, Vector3(0.05, 0.12, 0.24), Vector3(0, -0.032, 0.34), grey, Vector3(-6, 0, 0)) # stock
	_box(_rifle, Vector3(0.042, 0.13, 0.055), Vector3(0, -0.105, 0.13), accent, Vector3(15, 0, 0)) # grip
	_box(_rifle, Vector3(0.034, 0.15, 0.055), Vector3(0, -0.125, -0.12), grey, Vector3(8, 0, 0))    # magazine
	_box(_rifle, Vector3(0.05, 0.024, 0.16), Vector3(0, 0.012, -0.64), accent)             # handguard accent

	# Tiny emissive front dot, visible when the iron sights are lined up.
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.008
	dot_mesh.height = 0.016
	var dot_mat := _mat(Color(1.0, 0.55, 0.12), 0.0, 0.4)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1.0, 0.35, 0.04)
	dot_mat.emission_energy_multiplier = 3.0
	dot_mesh.material = dot_mat
	var dot := MeshInstance3D.new()
	dot.mesh = dot_mesh
	dot.position = Vector3(0, 0.085, -0.628)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rifle.add_child(dot)

	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0.012, -1.01)
	_rifle.add_child(_muzzle)

	_flash = _make_flash(_rifle, Vector3(0, 0.012, -1.02))

	_grip_right = Marker3D.new()
	_grip_right.name = "GripRight"
	_grip_right.position = Vector3(0, -0.10, 0.13)
	_rifle.add_child(_grip_right)

	_grip_left = Marker3D.new()
	_grip_left.name = "GripLeft"
	_grip_left.position = Vector3(0, -0.035, -0.38)
	_rifle.add_child(_grip_left)


func _build_arms() -> void:
	_arms = Node3D.new()
	_arms.name = "ArmIK"
	add_child(_arms)

	_skin_mat = _mat(Color(0.52, 0.34, 0.25), 0.0, 0.76)
	_sleeve_mat = _mat(Color(0.11, 0.12, 0.14), 0.1, 0.8)

	_upper_r = _arm_mesh(0.045, _sleeve_mat)
	_fore_r = _arm_mesh(0.038, _skin_mat)
	_hand_r = _hand_mesh(0.045, _skin_mat)
	_upper_l = _arm_mesh(0.048, _sleeve_mat)
	_fore_l = _arm_mesh(0.040, _skin_mat)
	_hand_l = _hand_mesh(0.047, _skin_mat)


func _arm_mesh(radius: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.16
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arms.add_child(mi)
	return mi


func _hand_mesh(radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.2
	mesh.radial_segments = 8
	mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arms.add_child(mi)
	return mi


func _make_flash(parent: Node3D, pos: Vector3) -> Node3D:
	var f := Node3D.new()
	f.name = "MuzzleFlash"
	f.position = pos
	f.visible = false
	parent.add_child(f)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.78, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.12)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.22)
	light.light_energy = 2.0
	light.omni_range = 4.0
	light.shadow_enabled = false
	f.add_child(light)
	return f


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, radius: float, length: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
