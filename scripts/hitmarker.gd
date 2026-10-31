class_name Hitmarker
extends Sprite3D
## World-space hitmarker: four small diagonal ticks that appear at the exact 3D
## impact point, stay fixed there for `lifetime` seconds while fading out, then
## free themselves. It is a billboard, so it always faces the camera, and it has
## a fixed on-screen size, so it stays legible at any distance. Normal hit = white,
## kill = larger and red. (The hit sound is played by the Player, not here, so a
## short lifetime can't cut the sound off.)

const DEFAULT_LIFETIME := 0.25
const TEX_SIZE := 64
const PIXEL_SIZE := 0.0009           # with fixed_size: roughly 0.75 screen px per texel
const KILL_SCALE := 1.35
const KILL_COLOR := Color(1.0, 0.15, 0.1)
const REFERENCE_FOV := 65.0          ## vertical FOV the marker size above was tuned at

var _base_scale := 1.0

static var _texture: ImageTexture


## Creates a hitmarker at `world_pos` under `parent` and returns it.
static func spawn(parent: Node, world_pos: Vector3, kill: bool,
		lifetime := DEFAULT_LIFETIME) -> Hitmarker:
	var m := Hitmarker.new()
	parent.add_child(m)
	m.global_position = world_pos
	m.start(kill, lifetime)
	return m


func start(kill: bool, lifetime: float) -> void:
	texture = _get_texture()
	pixel_size = PIXEL_SIZE
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	no_depth_test = true              # never hidden by (or clipped into) the surface it hit
	shaded = false
	double_sided = true
	render_priority = 10
	if kill:
		modulate = KILL_COLOR
		_base_scale = KILL_SCALE
	_apply_fov_scale()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, maxf(lifetime, 0.01))
	tween.tween_callback(queue_free)


func _process(_delta: float) -> void:
	_apply_fov_scale()


## `fixed_size` keeps the marker the same size at any distance, but it still
## magnifies when the FOV narrows (ADS, speed FOV). Scaling by tan(fov/2) cancels
## that, so the marker keeps the same on-screen size at every zoom level.
func _apply_fov_scale() -> void:
	var cam := get_viewport().get_camera_3d()
	var k := 1.0
	if cam:
		k = tan(deg_to_rad(cam.fov) * 0.5) / tan(deg_to_rad(REFERENCE_FOV) * 0.5)
	scale = Vector3.ONE * _base_scale * k


## Four soft-edged diagonal ticks around an empty centre, drawn once and shared.
static func _get_texture() -> ImageTexture:
	if _texture:
		return _texture
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (TEX_SIZE - 1) * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var ax := absf(x - c)
			var ay := absf(y - c)
			var along := (ax + ay) * 0.7071           # distance out along the diagonal
			var perp := absf(ax - ay) * 0.7071        # distance from the diagonal's centre line
			var a := clampf(2.2 - perp, 0.0, 1.0) \
					* clampf(along - 8.0, 0.0, 1.0) \
					* clampf(25.0 - along, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_texture = ImageTexture.create_from_image(img)
	return _texture
