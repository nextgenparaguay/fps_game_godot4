class_name Gib
extends RigidBody3D
## A single flesh chunk. Leaves a short blood trail while flying, smears blood
## decals where it hits the world, then shrinks away.

var _mesh_node: MeshInstance3D
var _trail: CPUParticles3D
var _life := 10.0
var _size := 0.2
var _splats_left := 2
var _last_splat_ms := 0
var _prev_speed := 0.0
var _pending_splat_dir := Vector3.ZERO


func setup(size: float, material: Material, life: float, phys: PhysicsMaterial) -> void:
	_size = size
	_life = life
	collision_layer = 8          # layer 4 = gibs
	collision_mask = 1           # only collide with the world (not each other / actors)
	physics_material_override = phys
	mass = maxf(size * 5.0, 0.1)
	linear_damp = 0.15
	angular_damp = 0.4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 1

	_mesh_node = MeshInstance3D.new()
	var col := CollisionShape3D.new()
	if randf() < 0.5:
		var box := BoxMesh.new()
		box.size = Vector3(size, size * randf_range(0.5, 1.4), size * randf_range(0.6, 1.6))
		_mesh_node.mesh = box
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size
		col.shape = box_shape
	else:
		var sph := SphereMesh.new()
		sph.radius = size * 0.5
		sph.height = size
		_mesh_node.mesh = sph
		var sph_shape := SphereShape3D.new()
		sph_shape.radius = size * 0.5
		col.shape = sph_shape
	_mesh_node.material_override = material
	add_child(col)
	add_child(_mesh_node)


func _ready() -> void:
	# Blood drips behind the chunk for a moment (particles live in world space)
	_trail = CPUParticles3D.new()
	_trail.amount = 10
	_trail.lifetime = 0.5
	_trail.mesh = Gore.drop_mesh
	_trail.direction = Vector3.DOWN
	_trail.spread = 35.0
	_trail.initial_velocity_min = 0.2
	_trail.initial_velocity_max = 1.2
	_trail.gravity = Vector3(0, -12, 0)
	_trail.scale_amount_min = 0.4
	_trail.scale_amount_max = 1.0
	add_child(_trail)

	get_tree().create_timer(1.3).timeout.connect(_stop_trail)
	get_tree().create_timer(_life).timeout.connect(_fade_out)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Physics space is locked in here, so only *record* the contact; the decal
	# ray-cast happens in _physics_process.
	if _splats_left > 0 and state.get_contact_count() > 0 and _prev_speed > 2.5:
		var now := Time.get_ticks_msec()
		if now - _last_splat_ms > 150:
			var contact := state.get_contact_local_position(0)
			var to_contact := contact - state.transform.origin
			if to_contact.length() > 0.001:
				_pending_splat_dir = to_contact.normalized()
				_last_splat_ms = now
	_prev_speed = state.linear_velocity.length()


func _physics_process(_delta: float) -> void:
	if _pending_splat_dir != Vector3.ZERO:
		Gore.splat_toward(global_position, _pending_splat_dir, randf_range(0.45, 1.0) + _size)
		_pending_splat_dir = Vector3.ZERO
		_splats_left -= 1


func _stop_trail() -> void:
	if is_instance_valid(_trail):
		_trail.emitting = false


func _fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(_mesh_node, "scale", Vector3.ZERO, 0.6)
	tw.tween_callback(queue_free)
