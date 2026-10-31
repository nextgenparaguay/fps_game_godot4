class_name Grenade
extends RigidBody3D
## Thrown frag grenade: a real physics body that arcs, bounces off the world and
## explodes when its fuse runs out.

var weapon: Weapon
var fuse := 2.5
var radius := 7.5
var damage := 140.0

var _blink := 0.0
var _mat: StandardMaterial3D
var _bounce_cd := 0.0


func _ready() -> void:
	collision_layer = 16           # layer 5: grenades (nothing listens for it)
	collision_mask = 1             # bounce off the world only
	mass = 0.4
	linear_damp = 0.08
	angular_damp = 0.6
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.38
	pm.friction = 0.75
	physics_material_override = pm
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.06
	shape.shape = sphere_shape
	add_child(shape)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.22, 0.30, 0.16)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.1, 0.05)
	_mat.emission_energy_multiplier = 0.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _physics_process(delta: float) -> void:
	_bounce_cd = maxf(_bounce_cd - delta, 0.0)
	fuse -= delta
	# Blink faster as the fuse burns down.
	_blink += delta * lerpf(4.0, 22.0, 1.0 - clampf(fuse / 2.5, 0.0, 1.0))
	_mat.emission_energy_multiplier = 3.0 if sin(_blink * TAU) > 0.6 else 0.0
	if fuse <= 0.0:
		var w := weapon if is_instance_valid(weapon) else null
		Explosion.blast(self, global_position, radius, damage, w)
		queue_free()


func _on_body_entered(_body: Node) -> void:
	if _bounce_cd > 0.0 or linear_velocity.length() < 2.0:
		return
	_bounce_cd = 0.15
	ProcAudio.play_at(get_tree().current_scene, "click", global_position, -4.0,
			randf_range(0.6, 0.8), 30.0)
