extends Node3D
## Replay viewer.
##
## Rebuilds lightweight ghost actors from a recorded match and plays their
## transforms back with interpolation. Five camera modes are available:
##   1 first-person (recorded head), 2 SpringArm third-person, 3 smooth drone,
##   4 free spectator, 5 fixed area cameras that look_at() the player.

const MODE_LABELS := [
	"First-Person",
	"Third-Person (SpringArm)",
	"Drone",
	"Free Camera",
	"Static Area",
]

var _replay: Dictionary = {}
var _frames: Array = []
var _player_track: Array = []
var _enemy_tracks: Dictionary = {}
var _duration := 1.0
var _time := 0.0
var _playing := true
var _mode := 0

var _ghost: Node3D
var _ghost_head: Node3D
var _enemy_ghosts: Dictionary = {}

var _cameras: Array[Camera3D] = []
var _cam_fp: Camera3D
var _cam_third: Camera3D
var _cam_drone: Camera3D
var _cam_free: Camera3D
var _static_cams: Array[Camera3D] = []
var _spring: SpringArm3D
var _static_index := 0
var _free_pos := Vector3.ZERO
var _free_yaw := 0.0
var _free_pitch := -0.2

var _ui_root: Control
var _mode_label: Label
var _time_label: Label
var _pause_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_replay = ReplayManager.get_pending_replay()
	_build_environment()
	_build_cameras()
	if _replay.is_empty() or not _replay.has("frames"):
		_build_ui()
		_show_error("No replay selected.")
		return
	_frames = _replay.get("frames", [])
	if _frames.is_empty():
		_build_ui()
		_show_error("This replay contains no frames.")
		return
	_preprocess_tracks()
	_build_player_ghost()
	_build_enemy_ghosts()
	_build_ui()
	_set_mode(0)
	_apply_replay_time(0.0)


# ----------------------------------------------------------------------------
# Replay data
# ----------------------------------------------------------------------------

func _preprocess_tracks() -> void:
	_enemy_tracks.clear()
	_player_track.clear()
	for frame in _frames:
		var t := float(frame.get("t", 0.0))
		var pd: Dictionary = frame.get("player", {})
		if not pd.is_empty():
			_player_track.append({
				"t": t,
				"p": _to_vec(pd.get("p", [])),
				"yaw": float(pd.get("yaw", 0.0)),
				"pitch": float(pd.get("pitch", 0.0)),
			})
		for ed in frame.get("enemies", []):
			var id := int(ed.get("id", 0))
			if not _enemy_tracks.has(id):
				_enemy_tracks[id] = []
			_enemy_tracks[id].append({
				"t": t,
				"p": _to_vec(ed.get("p", [])),
				"yaw": float(ed.get("yaw", 0.0)),
			})
	_duration = maxf(0.1, float(_replay.get("duration", 0.0)))
	if _player_track.is_empty():
		_duration = 0.1


func _sample_player(t: float) -> Dictionary:
	if _player_track.is_empty():
		return {"p": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0}
	var i := _find_track_index(_player_track, t)
	var a: Dictionary = _player_track[i]
	var b: Dictionary = _player_track[mini(i + 1, _player_track.size() - 1)]
	var span := float(b["t"]) - float(a["t"])
	var u := 0.0 if span <= 0.0001 else clampf((t - float(a["t"])) / span, 0.0, 1.0)
	return {
		"p": (a["p"] as Vector3).lerp(b["p"], u),
		"yaw": lerp_angle(float(a["yaw"]), float(b["yaw"]), u),
		"pitch": lerpf(float(a["pitch"]), float(b["pitch"]), u),
	}


func _sample_enemy(track: Array, t: float) -> Dictionary:
	var i := _find_track_index(track, t)
	var a: Dictionary = track[i]
	var b: Dictionary = track[mini(i + 1, track.size() - 1)]
	var span := float(b["t"]) - float(a["t"])
	var u := 0.0 if span <= 0.0001 else clampf((t - float(a["t"])) / span, 0.0, 1.0)
	return {
		"p": (a["p"] as Vector3).lerp(b["p"], u),
		"yaw": lerp_angle(float(a["yaw"]), float(b["yaw"]), u),
	}


func _find_track_index(track: Array, t: float) -> int:
	var lo := 0
	var hi := track.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(track[mid]["t"]) <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _track_active(track: Array, t: float) -> bool:
	if track.is_empty():
		return false
	return t >= float(track[0]["t"]) - 0.05 and t <= float(track[track.size() - 1]["t"]) + 0.08


func _to_vec(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


# ----------------------------------------------------------------------------
# Ghost actors
# ----------------------------------------------------------------------------

func _build_player_ghost() -> void:
	_ghost = Node3D.new()
	_ghost.name = "ReplayPlayerGhost"
	add_child(_ghost)

	var body := CapsuleMesh.new()
	body.radius = 0.4
	body.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.58, 0.86)
	mat.roughness = 0.55
	body.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.position.y = 0.9
	_ghost.add_child(mi)

	_ghost_head = Node3D.new()
	_ghost_head.position.y = 1.65
	_ghost.add_child(_ghost_head)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.67, 0.43, 0.3)
	head_mesh.material = head_mat
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head_mesh
	_ghost_head.add_child(head_mi)

	_cam_fp = Camera3D.new()
	_cam_fp.name = "FirstPersonCam"
	_cam_fp.fov = 75.0
	_ghost_head.add_child(_cam_fp)
	_cameras.append(_cam_fp)


func _build_enemy_ghosts() -> void:
	for id in _enemy_tracks.keys():
		var track: Array = _enemy_tracks[id]
		if track.is_empty():
			continue
		var ghost := Node3D.new()
		ghost.name = "EnemyGhost_%s" % id
		add_child(ghost)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.68, 0.28, 0.3)
		mat.roughness = 0.5
		var body := CapsuleMesh.new()
		body.radius = 0.4
		body.height = 1.8
		body.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = body
		mi.position.y = 0.9
		ghost.add_child(mi)
		var visor := BoxMesh.new()
		visor.size = Vector3(0.5, 0.12, 0.2)
		var vmat := StandardMaterial3D.new()
		vmat.albedo_color = Color(0.05, 0.05, 0.06)
		visor.material = vmat
		var vmi := MeshInstance3D.new()
		vmi.mesh = visor
		vmi.position = Vector3(0, 1.5, -0.32)
		ghost.add_child(vmi)
		ghost.visible = false
		_enemy_ghosts[id] = ghost


# ----------------------------------------------------------------------------
# Cameras
# ----------------------------------------------------------------------------

func _build_cameras() -> void:
	_cameras.clear()

	# Third person: SpringArm3D with the camera behind the tracked player.
	_spring = SpringArm3D.new()
	_spring.name = "ThirdPersonSpringArm"
	_spring.spring_length = 4.2
	_spring.margin = 0.25
	_spring.collision_mask = 0
	add_child(_spring)
	_cam_third = Camera3D.new()
	_cam_third.name = "ThirdPersonCam"
	_cam_third.position = Vector3(0, 0, 4.2)
	_cam_third.fov = 72.0
	_spring.add_child(_cam_third)
	_cameras.append(_cam_third)

	_cam_drone = Camera3D.new()
	_cam_drone.name = "DroneCam"
	_cam_drone.fov = 70.0
	add_child(_cam_drone)
	_cameras.append(_cam_drone)

	_cam_free = Camera3D.new()
	_cam_free.name = "FreeCam"
	_cam_free.fov = 72.0
	add_child(_cam_free)
	_cameras.append(_cam_free)

	var static_positions := [
		Vector3(0, 13, 38),
		Vector3(-38, 9, -2),
		Vector3(36, 11, -34),
	]
	for i in static_positions.size():
		var cam := Camera3D.new()
		cam.name = "StaticCam%d" % (i + 1)
		cam.fov = 62.0
		add_child(cam)
		cam.global_position = static_positions[i]
		_static_cams.append(cam)
		_cameras.append(cam)

	# First-person camera is created with the player ghost and appended later.
	if _cam_fp:
		_cameras.append(_cam_fp)


func _set_mode(index: int) -> void:
	if index < 0 or index > 4:
		return
	if index == 4 and _mode == 4:
		_static_index = (_static_index + 1) % _static_cams.size()
	_mode = index

	for cam in _cameras:
		cam.current = false

	var ps := _sample_player(_time)
	match index:
		0:
			_cam_fp.current = true
		1:
			_cam_third.current = true
			_spring.global_position = ps["p"] + Vector3.UP * 1.35
			_spring.rotation = Vector3(-0.12, float(ps["yaw"]), 0)
		2:
			_cam_drone.current = true
			_cam_drone.global_position = _drone_desired(ps)
			_cam_drone.look_at(ps["p"] + Vector3.UP * 1.1, Vector3.UP)
		3:
			_cam_free.current = true
			_free_pos = ps["p"] + Vector3(7, 6, 9)
			_free_yaw = float(ps["yaw"])
			_free_pitch = -0.25
			_cam_free.global_position = _free_pos
			_cam_free.rotation = Vector3(_free_pitch, _free_yaw, 0)
		4:
			_cam_static_current().current = true
	_update_mode_ui()


func _cam_static_current() -> Camera3D:
	return _static_cams[_static_index]


func _drone_desired(ps: Dictionary) -> Vector3:
	var behind := Basis(Vector3.UP, float(ps["yaw"])) * Vector3(0, 7.0, 10.0)
	return ps["p"] + behind


func _process(delta: float) -> void:
	if _frames.is_empty():
		return
	if _playing:
		_time += delta
		if _time >= _duration:
			_time = fmod(_time, _duration) if _duration > 0.001 else 0.0
		_apply_replay_time(_time)
	else:
		_apply_replay_time(_time)

	if _mode == 3:
		_update_free_camera(delta)
	if _time_label:
		var outcome := str(_replay.get("outcome", "match")).to_upper()
		_time_label.text = "%s / %s   •   %s" % [
			_format_time(_time), _format_time(_duration), outcome]


func _apply_replay_time(t: float) -> void:
	if _player_track.is_empty():
		return
	var ps := _sample_player(t)
	_ghost.global_position = ps["p"]
	_ghost.rotation.y = float(ps["yaw"])
	_ghost_head.rotation.x = float(ps["pitch"])

	for id in _enemy_tracks.keys():
		var ghost: Node3D = _enemy_ghosts.get(id)
		if ghost == null:
			continue
		var track: Array = _enemy_tracks[id]
		var active := _track_active(track, t)
		ghost.visible = active
		if active:
			var sample := _sample_enemy(track, t)
			ghost.global_position = sample["p"]
			ghost.rotation.y = float(sample["yaw"])

	match _mode:
		1:
			_spring.global_position = ps["p"] + Vector3.UP * 1.35
			_spring.rotation = Vector3(-0.12, float(ps["yaw"]), 0)
		2:
			var target := _drone_desired(ps)
			_cam_drone.global_position = _cam_drone.global_position.lerp(
					target, 1.0 - exp(-4.0 * get_process_delta_time()))
			if _cam_drone.global_position.distance_to(ps["p"]) > 0.01:
				_cam_drone.look_at(ps["p"] + Vector3.UP * 1.1, Vector3.UP)
		4:
			_cam_static_current().look_at(ps["p"] + Vector3.UP * 1.1, Vector3.UP)


func _update_free_camera(delta: float) -> void:
	var look := 1.8 * delta
	if Input.is_key_pressed(KEY_LEFT):
		_free_yaw += look
	if Input.is_key_pressed(KEY_RIGHT):
		_free_yaw -= look
	if Input.is_key_pressed(KEY_UP):
		_free_pitch = minf(_free_pitch + look, 1.4)
	if Input.is_key_pressed(KEY_DOWN):
		_free_pitch = maxf(_free_pitch - look, -1.4)

	var cam_basis := Basis.from_euler(Vector3(_free_pitch, _free_yaw, 0.0))
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move -= cam_basis.z
	if Input.is_key_pressed(KEY_S):
		move += cam_basis.z
	if Input.is_key_pressed(KEY_A):
		move -= cam_basis.x
	if Input.is_key_pressed(KEY_D):
		move += cam_basis.x
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	var speed := 30.0 if Input.is_key_pressed(KEY_SHIFT) else 12.0
	if move.length_squared() > 0.001:
		_free_pos += move.normalized() * speed * delta
	_cam_free.global_position = _free_pos
	_cam_free.rotation = Vector3(_free_pitch, _free_yaw, 0)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_set_mode(0)
		KEY_2:
			_set_mode(1)
		KEY_3:
			_set_mode(2)
		KEY_4:
			_set_mode(3)
		KEY_5:
			_set_mode(4)
		KEY_SPACE:
			_toggle_pause()
		KEY_R:
			_time = 0.0
			_apply_replay_time(0.0)
		KEY_ESCAPE:
			_exit_to_menu()


# ----------------------------------------------------------------------------
# UI / environment
# ----------------------------------------------------------------------------

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_ui_root = Control.new()
	_ui_root.size = vp
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui_root)

	var panel := PanelContainer.new()
	panel.position = Vector2(24, 22)
	_ui_root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := Label.new()
	title.text = "MATCH REPLAY"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.84, 0.6))
	box.add_child(title)

	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 17)
	box.add_child(_mode_label)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 14)
	_time_label.add_theme_color_override("font_color", Color(0.65, 0.76, 0.83))
	box.add_child(_time_label)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	box.add_child(modes)
	for i in 5:
		var b := Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(34, 32)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_mode.bind(i))
		modes.add_child(b)

	var pause := Button.new()
	pause.text = "Pause"
	pause.focus_mode = Control.FOCUS_NONE
	pause.pressed.connect(_toggle_pause)
	modes.add_child(pause)
	_pause_button = pause

	var hint := Label.new()
	hint.text = "1-5 cameras   •   Space pause   •   R restart   •   WASD/QE/Arrows free camera"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68))
	box.add_child(hint)

	var exit_btn := Button.new()
	exit_btn.text = "Exit to Main Menu"
	exit_btn.custom_minimum_size = Vector2(0, 38)
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.pressed.connect(_exit_to_menu)
	box.add_child(exit_btn)

	_update_mode_ui()


func _update_mode_ui() -> void:
	if _mode_label == null:
		return
	var label: String = str(MODE_LABELS[_mode])
	if _mode == 4:
		_mode_label.text = "Camera 5/5: Static Area %d" % (_static_index + 1)
		return
	_mode_label.text = "Camera %d/5: %s" % [_mode + 1, label]


func _toggle_pause() -> void:
	_playing = not _playing
	if _pause_button:
		_pause_button.text = "Pause" if _playing else "Resume"


func _format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%02d:%02d" % [int(total / 60.0), total % 60]


func _show_error(message: String) -> void:
	var vp := get_viewport().get_visible_rect().size
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var root := Control.new()
	root.size = vp
	layer.add_child(root)
	var center := CenterContainer.new()
	center.size = vp
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var back := Button.new()
	back.text = "Back to Main Menu"
	back.custom_minimum_size = Vector2(320, 48)
	back.pressed.connect(_exit_to_menu)
	box.add_child(back)


func _exit_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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

	var mat := _grid_material()
	var ground := CSGBox3D.new()
	ground.size = Vector3(160, 1, 160)
	ground.position = Vector3(0, -0.5, 0)
	ground.material = mat
	ground.use_collision = false
	add_child(ground)

	# A few landmarks from the playable arena so replay camera movement reads.
	_box(Vector3(-3, 4, -25), Vector3(1, 8, 60), mat)
	_box(Vector3(3, 4, -25), Vector3(1, 8, 60), mat)
	for i in 4:
		var top := 1.2 * (i + 1)
		_box(Vector3(-20, top * 0.5, 10 - i * 8), Vector3(6, top, 6), mat)
	for i in 6:
		_box(Vector3(50 + (i % 2) * 6, 5, -10 + i * 7), Vector3(2, 10, 2), mat)
	_box(Vector3(-45, 4, -40), Vector3(1, 8, 40), mat)


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	b.use_collision = false
	add_child(b)


func _grid_material() -> StandardMaterial3D:
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
	return m
