extends Node3D
## Shared static arena geometry. Both the live match and the replay viewer
## instantiate this scene so the map, lighting, ramp and colliders are identical.

var nav_source := NavigationMeshSourceGeometryData3D.new()
## Cover positions for the enemy AI (see cover_manager.gd). Each entry is
## {pos, normal, height}: `pos` is a spot on the floor 0.9 m out from a solid
## object's face, `normal` points away from that object, `height` is how tall
## the object is (low cover is < LOW_COVER_HEIGHT and is used crouching).
var cover_points: Array[Dictionary] = []
var _mat: StandardMaterial3D

const COVER_OFFSET := 0.9            # how far from the face a cover spot sits
const COVER_SPACING := 3.0           # one spot per this much face length
const COVER_TYPES := {
	# type: [size, colour] - tinted so cover reads at a glance in the greybox
	"slab": [Vector3(4.0, 2.6, 0.8), Color(0.72, 0.74, 0.80)],
	"container": [Vector3(6.0, 2.6, 2.6), Color(0.55, 0.78, 0.62)],
	"crate": [Vector3(1.4, 1.4, 1.4), Color(0.95, 0.72, 0.42)],
	"barrier": [Vector3(3.0, 1.1, 0.7), Color(1.0, 0.86, 0.32)],
}
## [type, x, z, yaw_degrees]
const COVER_PROPS := [
	# around the player's start
	["slab", -8, 6, 0], ["crate", 7, 8, 30], ["barrier", 10, 16, 90], ["barrier", -10, 18, 70],
	# south field
	["container", -14, 34, 10], ["slab", 8, 30, -15], ["crate", 0, 26, 0], ["crate", 1.8, 26.4, 20],
	["slab", 22, 40, 0], ["barrier", -26, 24, 40], ["container", 14, 50, 80], ["slab", -30, 44, 0],
	["barrier", -6, 46, 0],
	# west
	["slab", -34, 5, 90], ["barrier", -32, -8, 90], ["crate", -30, 12, 0],
	# east
	["slab", 40, 12, 90], ["container", 42, -6, 0], ["barrier", 38, 28, 90], ["crate", 44, 36, 45],
	# north of the corridor
	["slab", -8, -62, 0], ["container", 12, -64, 0], ["barrier", 0, -58, 0],
	# mid-field
	["slab", 15, -30, 90], ["slab", -14, -34, 90], ["crate", 12, -18, 0], ["barrier", 18, -45, 90],
]


func _ready() -> void:
	_mat = _make_grid_material()
	_build_environment()
	_build_level()


func _build_level() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(160, 1, 160))                    # ground

	# Wall-run corridor (inner faces at x = +-2.5)
	_box(Vector3(-3, 4, -25), Vector3(1, 8, 60))
	_box(Vector3(3, 4, -25), Vector3(1, 8, 60))
	_register_cover(Vector3(-3, 4, -25), Vector3(1, 8, 60), 0.0, 5)
	_register_cover(Vector3(3, 4, -25), Vector3(1, 8, 60), 0.0, 5)

	# Slide ramp (solid wedge, ~14 deg): walk up from the south end, slide down.
	_add_solid(_wedge_faces(14.0, 30.0, 7.5), Vector3(28, 0, 0))

	# Stepped platforms
	for i in 4:
		var top := 1.2 * (i + 1)
		_box(Vector3(-20, top * 0.5, 10 - i * 8), Vector3(6, top, 6))
		_register_cover(Vector3(-20, top * 0.5, 10 - i * 8), Vector3(6, top, 6), 0.0, 2)

	# Pillar field
	for i in 6:
		_box(Vector3(50 + (i % 2) * 6, 5, -10 + i * 7), Vector3(2, 10, 2))
		_register_cover(Vector3(50 + (i % 2) * 6, 5, -10 + i * 7), Vector3(2, 10, 2), 0.0, 1)

	# One long single wall for plain wall-running
	_box(Vector3(-45, 4, -40), Vector3(1, 8, 40))
	_register_cover(Vector3(-45, 4, -40), Vector3(1, 8, 40), 0.0, 5)

	_build_cover()


## Builds the free-standing cover props from COVER_PROPS. They are ordinary
## boxes (so they collide, cast shadows, and carve the navmesh) that are also
## registered as cover spots for the enemy AI.
func _build_cover() -> void:
	var tinted: Dictionary = {}
	for prop: Array in COVER_PROPS:
		var type := str(prop[0])
		var def: Array = COVER_TYPES[type]
		var size: Vector3 = def[0]
		if not tinted.has(type):
			var m := _mat.duplicate() as StandardMaterial3D
			m.albedo_color = def[1]
			tinted[type] = m
		var centre := Vector3(float(prop[1]), size.y * 0.5, float(prop[2]))
		var yaw := float(prop[3])
		_box(centre, size, Vector3(0.0, yaw, 0.0), tinted[type])
		_register_cover(centre, size, yaw, 4)


## Adds cover spots around the four sides of a (yaw-rotated) box.
func _register_cover(centre: Vector3, size: Vector3, yaw_deg: float, max_per_side: int) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	# [outward normal (local), face length, half depth along the normal]
	var sides := [
		[Vector3.RIGHT, size.z, size.x * 0.5],
		[Vector3.LEFT, size.z, size.x * 0.5],
		[Vector3.BACK, size.x, size.z * 0.5],
		[Vector3.FORWARD, size.x, size.z * 0.5],
	]
	for s: Array in sides:
		var n_local: Vector3 = s[0]
		var length: float = s[1]
		var half_depth: float = s[2]
		var count := clampi(roundi(length / COVER_SPACING), 1, max_per_side)
		var tangent := n_local.cross(Vector3.UP)
		for i in count:
			var along := ((i + 0.5) / float(count) - 0.5) * maxf(length - 1.0, 0.0)
			var local := n_local * (half_depth + COVER_OFFSET) + tangent * along
			var world := centre + basis * local
			world.y = 0.0
			cover_points.append({"pos": world, "normal": basis * n_local, "height": size.y})


func _box(pos: Vector3, size: Vector3, rot_deg := Vector3.ZERO, material: Material = null) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.rotation_degrees = rot_deg
	b.use_collision = true
	b.collision_layer = 1
	b.material = material if material != null else _mat
	add_child(b)

	var rot_rad := Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	nav_source.add_faces(_box_faces(size), Transform3D(Basis.from_euler(rot_rad), pos))


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
		if n.dot(mid - centre) > 0.0:
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
	mi.name = "SlideRamp"
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

	nav_source.add_faces(faces, Transform3D(Basis.IDENTITY, pos))


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
