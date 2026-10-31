class_name Explosion
extends RefCounted
## Shared blast logic for frag grenades and C4: area damage with falloff and
## line-of-sight (walls shield you), plus the visual / audio effect.
##
## Enemies killed by a blast go through their normal death, so the existing
## gore (gibs, blood decals, loot drop) all triggers, with the gibs thrown away
## from the blast centre.

const WORLD_MASK := 1


## `weapon` is optional: when given, kills/hits are reported back to it so the
## hitmarker and replay events fire exactly like a bullet hit.
static func blast(source: Node, pos: Vector3, radius: float, max_damage: float,
		weapon: Weapon = null, self_damage_scale := 0.6) -> void:
	var tree := source.get_tree()
	var root := tree.current_scene
	if root == null:
		return
	_spawn_effect(root, pos, radius)
	ProcAudio.play_at(root, "explosion", pos, 4.0, randf_range(0.9, 1.1), 180.0)

	var space := source.get_viewport().world_3d.direct_space_state

	for e in tree.get_nodes_in_group("enemy"):
		var enemy := e as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		var centre := enemy.global_position + Vector3.UP * 0.9
		var d := centre.distance_to(pos)
		if d > radius or not _clear(space, pos, centre):
			continue
		var dmg := max_damage * clampf(1.0 - d / radius, 0.2, 1.0)
		var dir := (centre - pos).normalized()
		var lethal := enemy.take_damage(dmg, centre, -dir, dir)
		if weapon != null and is_instance_valid(weapon):
			weapon.notify_projectile_hit(enemy, lethal, centre)

	var player := tree.get_first_node_in_group("player") as Player
	if player != null and not player.is_dead():
		var pc := player.global_position + Vector3.UP * 0.9
		var pd := pc.distance_to(pos)
		if pd <= radius and _clear(space, pos, pc):
			var pdmg := max_damage * self_damage_scale * clampf(1.0 - pd / radius, 0.1, 1.0)
			player.take_damage(pdmg, pc, Vector3.UP, (pc - pos).normalized())
		# Screen punch scales with proximity, even if the walls shielded the damage.
		var punch := clampf(1.0 - pd / (radius * 2.2), 0.0, 1.0)
		if punch > 0.0:
			player.add_camera_recoil(randf_range(-0.05, 0.05) * punch, randf_range(-0.05, 0.05) * punch)


static func _clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.15, to, WORLD_MASK)
	var hit := space.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 0.6


static func _spawn_effect(root: Node, pos: Vector3, radius: float) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = pos

	# Fireball
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.62, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.material = mat
	var ball := MeshInstance3D.new()
	ball.mesh = sphere
	ball.scale = Vector3.ONE * 0.3
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ball)
	var tw := ball.create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 0.42, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)

	# Flash light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 10.0
	light.omni_range = radius * 1.6
	holder.add_child(light)
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.35)

	# Sparks + smoke
	holder.add_child(_particles(48, 0.7, 8.0, 18.0, 180.0, Vector3(0, -18, 0),
			Color(1.0, 0.8, 0.35), 0.03, true))
	holder.add_child(_particles(22, 1.6, 1.5, 4.5, 180.0, Vector3(0, 1.5, 0),
			Color(0.22, 0.22, 0.24, 0.8), 0.22, false))

	root.get_tree().create_timer(2.2).timeout.connect(holder.queue_free)


static func _particles(amount: int, life: float, v_min: float, v_max: float, spread: float,
		grav: Vector3, color: Color, size: float, emissive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = grav
	p.color = color
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = m
	p.mesh = mesh
	p.emitting = true
	return p
