extends Node
## Gore manager (registered as the autoload "Gore").
##
## Gore.explode(pos, intensity, shot_dir)  - bloody enemy explosion
## Gore.blood_puff(pos, normal)            - small hit spray
## Gore.splat_toward(origin, dir, size)    - blood decal on whatever is in that direction
##
## Everything is procedural (no assets): flesh chunks are boxes/spheres, blood
## droplets are particles, and blood splats are generated into textures at
## startup. Swap these for real meshes/textures later.

signal exploded(position: Vector3, intensity: float)

const WORLD_MASK := 1

var max_gibs := 160
var max_decals := 150
var gib_count := 22          # at intensity 1.0
var decal_rays := 28         # at intensity 1.0
var decal_range := 6.0

var drop_mesh: SphereMesh

var _gibs: Array = []
var _decals: Array = []
var _splat_textures: Array[Texture2D] = []
var _gib_materials: Array[StandardMaterial3D] = []
var _gib_physics: PhysicsMaterial
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()

	for i in 4:
		_splat_textures.append(_make_splat_texture(96))

	for c in [Color(0.55, 0.02, 0.04), Color(0.38, 0.02, 0.03), Color(0.78, 0.28, 0.30)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.3              # glossy / wet
		_gib_materials.append(m)

	var blood_mat := StandardMaterial3D.new()
	blood_mat.albedo_color = Color(0.5, 0.0, 0.02)
	blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mesh = SphereMesh.new()
	drop_mesh.radius = 0.05
	drop_mesh.height = 0.1
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	drop_mesh.material = blood_mat

	_gib_physics = PhysicsMaterial.new()
	_gib_physics.friction = 0.9
	_gib_physics.bounce = 0.15


# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

func explode(pos: Vector3, intensity: float, shot_dir: Vector3) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	exploded.emit(pos, intensity)

	_spawn_gibs(root, pos, intensity, shot_dir)

	# Directed spray (follows the bullet) + omni mist
	var spray_dir := Vector3.UP
	if shot_dir != Vector3.ZERO:
		spray_dir = (shot_dir + Vector3.UP * 0.6).normalized()
	_emit_blood(root, pos, spray_dir, int(90 * intensity), 1.4, 4.0, 11.0, 55.0)
	_emit_blood(root, pos, Vector3.UP, int(120 * intensity), 1.0, 1.5, 6.0, 180.0)

	_splatter(pos, intensity)


func blood_puff(pos: Vector3, normal: Vector3) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var dir := normal if normal != Vector3.ZERO else Vector3.UP
	_emit_blood(root, pos, dir, 14, 0.5, 2.0, 6.0, 50.0)


func splat_toward(origin: Vector3, dir: Vector3, size: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 0.7, WORLD_MASK)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		_spawn_decal(hit["position"], hit["normal"], size)


# ----------------------------------------------------------------------------
# Internals
# ----------------------------------------------------------------------------

func _spawn_gibs(root: Node, pos: Vector3, intensity: float, shot_dir: Vector3) -> void:
	var count := int(gib_count * intensity)
	for i in count:
		var gib := Gib.new()
		# First few are big "torso/head" chunks, the rest are small bits
		var size := _rng.randf_range(0.34, 0.5) if i < 3 else _rng.randf_range(0.1, 0.28)
		gib.setup(size, _gib_materials.pick_random(), _rng.randf_range(8.0, 14.0), _gib_physics)
		root.add_child(gib)
		gib.global_position = pos + Vector3(
				_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.3, 0.3))
		gib.global_rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)

		var burst := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.2),
				_rng.randf_range(-1, 1)).normalized()
		gib.linear_velocity = burst * _rng.randf_range(4.0, 11.0) * sqrt(intensity) \
				+ shot_dir * _rng.randf_range(2.0, 7.0)
		gib.angular_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1),
				_rng.randf_range(-1, 1)) * 10.0
		_gibs.append(gib)
	_trim(_gibs, max_gibs)


func _emit_blood(root: Node, pos: Vector3, dir: Vector3, amount: int, life: float,
		v_min: float, v_max: float, spread_deg: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.mesh = drop_mesh
	p.direction = dir
	p.spread = spread_deg
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, -16, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## Fire rays in random directions from the explosion; every wall/floor they hit
## gets a blood splat.
func _splatter(pos: Vector3, intensity: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	for i in int(decal_rays * intensity):
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1.0, 0.6),
				_rng.randf_range(-1, 1)).normalized()
		var query := PhysicsRayQueryParameters3D.create(pos, pos + dir * decal_range, WORLD_MASK)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var dist := pos.distance_to(hit["position"])
		var size := _rng.randf_range(0.8, 1.7) * lerpf(1.2, 0.6, dist / decal_range) * sqrt(intensity)
		_spawn_decal(hit["position"], hit["normal"], size)


func _spawn_decal(pos: Vector3, normal: Vector3, size: float) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var d := Decal.new()
	d.texture_albedo = _splat_textures.pick_random()
	d.modulate = Color(0.45, 0.0, 0.02).lerp(Color(0.25, 0.0, 0.01), _rng.randf())
	d.size = Vector3(size, 0.6, size)
	root.add_child(d)

	# Decals project along their local -Y, so make local Y the surface normal
	var up := normal.normalized()
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var b := Basis(x, up, z).rotated(up, _rng.randf() * TAU)
	d.global_transform = Transform3D(b, pos)

	_decals.append(d)
	_trim(_decals, max_decals)


## Removes freed entries, then frees the oldest ones beyond `limit`.
func _trim(list: Array, limit: int) -> void:
	var i := 0
	while i < list.size():
		if is_instance_valid(list[i]):
			i += 1
		else:
			list.remove_at(i)
	while list.size() > limit:
		var old: Node = list.pop_front()
		old.queue_free()


## Procedural blood splat: a noisy blob with jagged edges plus flung droplets.
func _make_splat_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.12
	noise.fractal_octaves = 3

	var c := Vector2(size, size) * 0.5
	var base_r := size * 0.17
	for y in size:
		for x in size:
			var v := Vector2(x, y) - c
			var ang := v.angle()
			var n := noise.get_noise_2d(cos(ang) * 14.0, sin(ang) * 14.0)
			var edge := base_r * clampf(1.0 + 1.1 * n, 0.35, 2.4)
			var a := clampf((edge - v.length()) / 2.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))

	for i in 18:                         # satellite droplets
		var p := c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(size * 0.22, size * 0.44)
		var r := _rng.randf_range(1.0, size * 0.035)
		for yy in range(int(p.y - r), int(p.y + r) + 1):
			for xx in range(int(p.x - r), int(p.x + r) + 1):
				if xx < 0 or yy < 0 or xx >= size or yy >= size:
					continue
				if Vector2(xx, yy).distance_to(p) <= r:
					img.set_pixel(xx, yy, Color(1, 1, 1, 1))

	return ImageTexture.create_from_image(img)
