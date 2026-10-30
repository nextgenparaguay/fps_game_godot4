class_name RifleProjectile
extends Node3D
## A real travelling rifle bullet.
##
## Unlike a hitscan shot, this leaves the muzzle with a finite velocity, is
## advanced every physics tick, and resolves its impact against the world with
## a swept ray so fast bullets cannot tunnel through thin geometry.  The shot
## is still aimed at the point under the reticle, but the damage only happens
## when the projectile actually gets there, so moving targets can be missed.
##
## No gravity is applied by default: the projectile flies flat from the muzzle
## to the reticle's projected world point. Set `gravity` to a positive value if
## you want visible bullet drop later (then add the matching aim compensation).

const HIT_MASK := 1 | 4              # world (1) + enemies (4)
const TRACER_MATERIAL := Color(1.0, 0.62, 0.18)
const CORE_MATERIAL := Color(1.0, 0.92, 0.62)

var speed := 160.0
var damage := 15.0
var gravity := 0.0
var max_lifetime := 3.0

var _velocity := Vector3.ZERO
var _shooter: Node3D
var _weapon: Weapon
var _age := 0.0
var _dead := false
var _trail: MeshInstance3D
var _trail_particles: CPUParticles3D


func setup(from: Vector3, to: Vector3, shot_speed: float, shot_damage: float,
		shooter: Node3D, weapon: Weapon) -> void:
	speed = shot_speed
	damage = shot_damage
	_shooter = shooter
	_weapon = weapon

	global_position = from
	var dir := to - from
	if dir.length_squared() < 0.0001:
		dir = -shooter.global_transform.basis.z
	dir = dir.normalized()
	_velocity = dir * speed
	_build_tracer(dir)
	# The projectile is a swept query, not a physics body: no collision layer
	# is needed, so enemies/players/world ignore it entirely.
	set_physics_process(true)


func _build_tracer(dir: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TRACER_MATERIAL
	mat.emission_enabled = true
	mat.emission = TRACER_MATERIAL
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.75

	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(0.022, 0.022, 2.0)
	_trail = MeshInstance3D.new()
	_trail.mesh = trail_mesh
	_trail.material_override = mat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stretch the tracer back behind the nose so it reads as a streak.
	_trail.position = Vector3(0.0, 0.0, 1.0)
	add_child(_trail)

	# A short world-space particle wake makes the projectile read as a moving
	# tracer instead of a one-frame line, even at high velocity.
	_trail_particles = CPUParticles3D.new()
	_trail_particles.amount = 12
	_trail_particles.lifetime = 0.16
	_trail_particles.local_coords = false
	_trail_particles.direction = Vector3.ZERO
	_trail_particles.spread = 0.0
	_trail_particles.gravity = Vector3.ZERO
	_trail_particles.initial_velocity_min = 0.0
	_trail_particles.initial_velocity_max = 0.0
	_trail_particles.scale_amount_min = 0.3
	_trail_particles.scale_amount_max = 0.8
	_trail_particles.color = TRACER_MATERIAL
	var wake_mesh := SphereMesh.new()
	wake_mesh.radius = 0.018
	wake_mesh.height = 0.036
	wake_mesh.radial_segments = 4
	wake_mesh.rings = 2
	var wake_mat := StandardMaterial3D.new()
	wake_mat.albedo_color = TRACER_MATERIAL
	wake_mat.emission_enabled = true
	wake_mat.emission = TRACER_MATERIAL
	wake_mat.emission_energy_multiplier = 2.0
	wake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wake_mesh.material = wake_mat
	_trail_particles.mesh = wake_mesh
	_trail_particles.emitting = true
	add_child(_trail_particles)

	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = CORE_MATERIAL
	core_mat.emission_enabled = true
	core_mat.emission = CORE_MATERIAL
	core_mat.emission_energy_multiplier = 5.0
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.045
	core_mesh.height = 0.09
	core_mesh.radial_segments = 6
	core_mesh.rings = 3
	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	# Projectile local -Z is the direction of travel.
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.RIGHT
	look_at(global_position + dir, up)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	if _age > max_lifetime:
		queue_free()
		return

	if gravity != 0.0:
		_velocity.y -= gravity * delta

	var from := global_position
	var to := from + _velocity * delta
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if is_instance_valid(_shooter) and _shooter is CollisionObject3D:
		exclude.append((_shooter as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, exclude)
	query.hit_from_inside = false
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit)
		return

	global_position = to
	# Keep the streak aligned if gravity bends the path.
	if _velocity.length_squared() > 0.001:
		var dir := _velocity.normalized()
		var up := Vector3.UP
		if absf(dir.dot(up)) > 0.98:
			up = Vector3.RIGHT
		look_at(global_position + dir, up)


func _impact(hit: Dictionary) -> void:
	_dead = true
	var hit_pos: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]
	var dir := _velocity.normalized()

	if collider and collider.has_method("take_damage"):
		var lethal: bool = collider.take_damage(damage, hit_pos, hit_normal, dir)
		if is_instance_valid(_weapon):
			_weapon.notify_projectile_hit(collider, lethal, hit_pos)
		_spawn_impact(hit_pos, hit_normal, true)
	else:
		_spawn_impact(hit_pos, hit_normal, false)
		if is_instance_valid(_weapon):
			_weapon.notify_environment_hit(hit_pos, hit_normal)

	queue_free()


func _spawn_impact(pos: Vector3, normal: Vector3, flesh: bool) -> void:
	var root := get_tree().current_scene
	if root == null:
		return

	var p := CPUParticles3D.new()
	p.amount = 7 if flesh else 4
	p.lifetime = 0.28
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 55.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -10, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	var col := Color(0.45, 0.0, 0.02) if flesh else Color(1.0, 0.55, 0.12)
	p.color = col
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	mesh.radial_segments = 4
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.5 if flesh else 3.0
	mesh.material = mat
	p.mesh = mesh
	root.add_child(p)
	p.global_position = pos + normal * 0.01
	p.emitting = true
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)
