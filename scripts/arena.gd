extends Node3D
## Greybox test arena, built entirely in code so main.tscn stays trivial.
##
##  - Corridor north of spawn (two parallel walls)  -> wall-run / wall-jump zigzag
##  - Ramp to the east                              -> run up, slide down (speed boost)
##  - Stepped platforms to the west                 -> double-jump / wall-jump practice
##  - Pillar field far east                         -> wall-jump chains
##  - Enemies spawn around the map                  -> test the gore
##
## A navigation mesh is baked at startup from the same boxes the level is
## built from, so enemies path-find around walls, pillars and platforms.

const MAX_ENEMIES := 8
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-40, 1, 40), Vector3(40, 1, 40), Vector3(0, 1, 60), Vector3(-60, 1, -20),
	Vector3(15, 1, -70), Vector3(-10, 1, -70), Vector3(60, 1, 60), Vector3(-55, 1, 20),
]

var _mat: StandardMaterial3D
var _spawn_timer := 2.0
var _nav_source := NavigationMeshSourceGeometryData3D.new()


func _ready() -> void:
	randomize()
	_mat = _make_grid_material()
	_build_environment()
	_build_level()
	_bake_navigation()

	var player := Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.5, 14)

	for i in 3:
		_spawn_enemy()


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 3.0
		if get_tree().get_nodes_in_group("enemy").size() < MAX_ENEMIES:
			_spawn_enemy()


func _spawn_enemy() -> void:
	var e := Enemy.new()
	add_child(e)
	e.global_position = SPAWN_POINTS.pick_random()


# ----------------------------------------------------------------------------

func _build_level() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(160, 1, 160))                    # ground

	# Wall-run corridor (inner faces at x = +-2.5)
	_box(Vector3(-3, 4, -25), Vector3(1, 8, 60))
	_box(Vector3(3, 4, -25), Vector3(1, 8, 60))

	# Slide ramp (solid wedge, ~14 deg): walk up from the south end, slide down.
	_add_solid(_wedge_faces(14.0, 30.0, 7.5), Vector3(28, 0, 0))

	# Stepped platforms
	for i in 4:
		var top := 1.2 * (i + 1)
		_box(Vector3(-20, top * 0.5, 10 - i * 8), Vector3(6, top, 6))

	# Pillar field
	for i in 6:
		_box(Vector3(50 + (i % 2) * 6, 5, -10 + i * 7), Vector3(2, 10, 2))

	# One long single wall for plain wall-running
	_box(Vector3(-45, 4, -40), Vector3(1, 8, 40))


func _box(pos: Vector3, size: Vector3, rot_deg := Vector3.ZERO) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.rotation_degrees = rot_deg
	b.use_collision = true
	b.collision_layer = 1
	b.material = _mat
	add_child(b)

	# Feed the same box to the navmesh baker (raw triangles, so it doesn't
	# depend on meshes being available to the renderer)
	var rot_rad := Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	_nav_source.add_faces(_box_faces(size), Transform3D(Basis.from_euler(rot_rad), pos))


## Solid triangular prism: x in [-w/2, w/2], low end at +Z (y=0), high end at -Z (y=h).
func _wedge_faces(w: float, length: float, h: float) -> PackedVector3Array:
	var hx := w * 0.5
	var hz := length * 0.5
	var lo_l := Vector3(-hx, 0, hz)
	var lo_r := Vector3(hx, 0, hz)
	var bk_l := Vector3(-hx, 0, -hz)
	var bk_r := Vector3(hx, 0, -hz)
	var hi_l := Vector3(-hx, h, -hz)
	var hi_r := Vector3(hx, h, -hz)
	var tris: Array = [
		[bk_l, bk_r, lo_r], [bk_l, lo_r, lo_l],      # bottom
		[lo_l, lo_r, hi_r], [lo_l, hi_r, hi_l],      # sloped top
		[bk_l, hi_l, hi_r], [bk_l, hi_r, bk_r],      # back wall
		[bk_l, lo_l, hi_l],                          # left cap
		[bk_r, hi_r, lo_r],                          # right cap
	]
	var centre := Vector3(0, h * 0.33, 0)
	var faces := PackedVector3Array()
	for t: Array in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var n := (b - a).cross(c - a)
		var mid := (a + b + c) / 3.0
		if n.dot(mid - centre) > 0.0:       # want clockwise-from-outside => normal points inward
			var tmp := b
			b = c
			c = tmp
		faces.append_array(PackedVector3Array([a, b, c]))
	return faces


## Visual mesh + trimesh collision + navmesh geometry from one triangle list.
func _add_solid(faces: PackedVector3Array, pos: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_mat)
	for v in faces:
		st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = pos
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)

	_nav_source.add_faces(faces, Transform3D(Basis.IDENTITY, pos))


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25              # must match the navigation map's cell size (default 0.25)
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5         # can't step up onto the 1.2m+ platforms
	nm.agent_max_slope = 45.0
	NavigationServer3D.bake_from_source_geometry_data(nm, _nav_source)

	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	add_child(region)


## 12 triangles for an axis-aligned box centred on the origin, wound the way
## Godot's navmesh baker expects (clockwise when seen from outside).
func _box_faces(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var faces := PackedVector3Array()
	for n: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var ref := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var u := n.cross(ref).normalized()
		var v := n.cross(u).normalized()
		var c := Vector3(n.x * h.x, n.y * h.y, n.z * h.z)
		var eu := u * u.abs().dot(h)
		var ev := v * v.abs().dot(h)
		var q: Array[Vector3] = [c - eu - ev, c + eu - ev, c + eu + ev, c - eu + ev]
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			var a := q[tri[0]]
			var b := q[tri[1]]
			var d := q[tri[2]]
			if (b - a).cross(d - a).dot(n) > 0.0:
				var t := b
				b = d
				d = t
			faces.append_array(PackedVector3Array([a, b, d]))
	return faces


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## Grey grid texture (world-space triplanar, one cell = 2m) so you can *see* speed.
func _make_grid_material() -> StandardMaterial3D:
	var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.62, 0.64, 0.68))
	for i in 64:
		for k in 2:
			img.set_pixel(i, k, Color(0.22, 0.24, 0.28))
			img.set_pixel(k, i, Color(0.22, 0.24, 0.28))
	img.generate_mipmaps()

	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
