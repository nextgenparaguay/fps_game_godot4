extends Node3D
## Greybox test arena + match flow + replay recording.
##
##  - Fixed-roster match: six enemies spawn at the start, then the spawner is
##    stopped. Clearing all six triggers victory; player death triggers defeat.
##  - On match end a CanvasLayer result panel offers Replay Match / Save Replay
##    / Exit to Main Menu.
##  - The arena records player/enemy transforms at 20 Hz into ReplayManager.
##  - A navigation mesh is baked at startup from the same boxes the level is
##    built from, so enemies path-find around walls, pillars and platforms.

signal victory
signal defeat
signal match_ended(result: String)

const MAX_ENEMIES := 8
const MATCH_ENEMY_TOTAL := 6
const SPAWN_INTERVAL := 3.0
const RECORD_INTERVAL := 0.05
const ArenaLevelScript := preload("res://scripts/arena_level.gd")
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-40, 1, 40), Vector3(40, 1, 40), Vector3(0, 1, 60), Vector3(-60, 1, -20),
	Vector3(15, 1, -70), Vector3(-10, 1, -70), Vector3(60, 1, 60), Vector3(-55, 1, 20),
]

var _nav_source := NavigationMeshSourceGeometryData3D.new()
var _spawn_timer: Timer
var _player: Player
var _kills := 0
var _spawned := 0
var _next_enemy_id := 1
var _match_over := false
var _match_time := 0.0
var _record_accum := 0.0

var _match_layer: CanvasLayer
var _objective_label: Label
var _result_layer: CanvasLayer
var _result_title: Label
var _result_sub: Label
var _save_button: Button
var _save_status: Label


func _ready() -> void:
	randomize()
	var level = ArenaLevelScript.new()
	add_child(level)
	_nav_source = level.nav_source
	_bake_navigation()

	_player = Player.new()
	add_child(_player)
	_player.global_position = Vector3(0, 0.5, 14)
	_player.died.connect(_on_player_died)
	_player.weapon.shot_fired.connect(_on_weapon_shot_fired)
	_player.weapon.projectile_hit.connect(_on_weapon_projectile_hit)

	_build_spawn_timer()
	_build_match_ui()

	# Fixed roster: populate once, then permanently disable the spawner for this
	# match. No enemies are added while the player is fighting the roster.
	for i in MATCH_ENEMY_TOTAL:
		_spawn_enemy()
	_spawn_timer.stop()
	_update_objective_label()

	ReplayManager.start_recording()


func _physics_process(delta: float) -> void:
	if _match_over or _player == null:
		return
	_match_time += delta
	_record_accum += delta
	if _record_accum >= RECORD_INTERVAL:
		_record_accum = 0.0
		_record_match_frame()


# ----------------------------------------------------------------------------
# Match flow
# ----------------------------------------------------------------------------

func _build_spawn_timer() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = SPAWN_INTERVAL
	_spawn_timer.autostart = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)


func _on_spawn_timer_timeout() -> void:
	# Safety net only. Normal matches call stop() in _ready; if this ever fires,
	# it can never exceed the fixed roster.
	if _match_over or _spawned >= MATCH_ENEMY_TOTAL:
		_spawn_timer.stop()
		return
	if get_tree().get_nodes_in_group("enemy").size() < MAX_ENEMIES:
		_spawn_enemy()


func _spawn_enemy() -> void:
	if _spawned >= MATCH_ENEMY_TOTAL:
		return
	_spawned += 1
	var e := Enemy.new()
	e.set_meta("replay_id", _next_enemy_id)
	_next_enemy_id += 1
	add_child(e)
	e.global_position = SPAWN_POINTS.pick_random()
	e.died.connect(_on_enemy_died)
	e.exploded_at.connect(_on_enemy_exploded)


func _on_enemy_exploded(pos: Vector3, intensity: float, shot_dir: Vector3) -> void:
	ReplayManager.record_event(_match_time, "death", {
		"pos": _vec(pos),
		"intensity": intensity,
		"dir": _vec(shot_dir),
	})


func _on_weapon_shot_fired(muzzle: Vector3, target: Vector3, speed: float) -> void:
	ReplayManager.record_event(_match_time, "shot", {
		"muzzle": _vec(muzzle),
		"target": _vec(target),
		"speed": speed,
	})


func _on_weapon_projectile_hit(hit_pos: Vector3, lethal: bool) -> void:
	ReplayManager.record_event(_match_time, "hit", {
		"pos": _vec(hit_pos),
		"kill": lethal,
	})


func _on_enemy_died() -> void:
	if _match_over:
		return
	_kills += 1
	_update_objective_label()
	_spawn_timer.stop()
	call_deferred("_check_victory")


func _check_victory() -> void:
	if _match_over or _spawned < MATCH_ENEMY_TOTAL:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			return
	_end_match("victory")


func _on_player_died() -> void:
	_end_match("defeat")


func _end_match(result: String) -> void:
	if _match_over:
		return
	_match_over = true
	if _spawn_timer:
		_spawn_timer.stop()
	_record_match_frame()
	ReplayManager.finish_recording(result)

	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.set_physics_process(false)
	if _player:
		_player.set_physics_process(false)
		if _player.weapon:
			_player.weapon.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_result_ui(result)

	if result == "victory":
		victory.emit()
	else:
		defeat.emit()
	match_ended.emit(result)


func _update_objective_label() -> void:
	if _objective_label == null:
		return
	_objective_label.text = "ELIMINATE  %d / %d" % [_kills, MATCH_ENEMY_TOTAL]


# ----------------------------------------------------------------------------
# Replay recording
# ----------------------------------------------------------------------------

func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 45.0
	NavigationServer3D.bake_from_source_geometry_data(nm, _nav_source)

	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	add_child(region)


func _record_match_frame() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var enemies: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var t: Transform3D = (e as Node3D).global_transform
		enemies.append({
			"id": int(e.get_meta("replay_id", 0)),
			"p": _vec(t.origin),
			"bx": _vec(t.basis.x),
			"by": _vec(t.basis.y),
			"bz": _vec(t.basis.z),
			"yaw": (e as Node3D).rotation.y,
		})
	var pt: Transform3D = _player.global_transform
	ReplayManager.record_frame(_match_time, {
		"p": _vec(pt.origin),
		"bx": _vec(pt.basis.x),
		"by": _vec(pt.basis.y),
		"bz": _vec(pt.basis.z),
		"yaw": _player.rotation.y,
		"pitch": _player.head.rotation.x,
		"ads": _player.weapon.ads_amount,
		"sprint": 1.0 if _player.is_sprinting() else 0.0,
		"fov": _player.camera.fov,
		"health": _player.health,
		"dead": _player.is_dead(),
	}, enemies)


func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


# ----------------------------------------------------------------------------
# Match UI
# ----------------------------------------------------------------------------

func _build_match_ui() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	_match_layer = CanvasLayer.new()
	_match_layer.layer = 10
	add_child(_match_layer)

	var hud_root := Control.new()
	hud_root.size = vp_size
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match_layer.add_child(hud_root)

	_objective_label = Label.new()
	_objective_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_objective_label.offset_left = -460
	_objective_label.offset_right = -24
	_objective_label.offset_top = 18
	_objective_label.offset_bottom = 56
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_objective_label.add_theme_font_size_override("font_size", 20)
	_objective_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.55))
	hud_root.add_child(_objective_label)

	_result_layer = CanvasLayer.new()
	_result_layer.layer = 20
	_result_layer.visible = false
	add_child(_result_layer)

	var root := Control.new()
	root.size = vp_size
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_layer.add_child(root)

	var dim := ColorRect.new()
	dim.size = vp_size
	dim.color = Color(0.015, 0.02, 0.03, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.size = vp_size
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", 46)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)

	_result_sub = Label.new()
	_result_sub.add_theme_font_size_override("font_size", 18)
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	box.add_child(spacer)

	var replay_button := Button.new()
	replay_button.text = "Replay Match"
	replay_button.custom_minimum_size = Vector2(360, 52)
	replay_button.pressed.connect(_on_replay_match_pressed)
	box.add_child(replay_button)

	_save_button = Button.new()
	_save_button.text = "Save Replay"
	_save_button.custom_minimum_size = Vector2(360, 52)
	_save_button.pressed.connect(_on_save_replay_pressed)
	box.add_child(_save_button)

	var menu_button := Button.new()
	menu_button.text = "Exit to Main Menu"
	menu_button.custom_minimum_size = Vector2(360, 52)
	menu_button.pressed.connect(_on_exit_to_menu_pressed)
	box.add_child(menu_button)

	_save_status = Label.new()
	_save_status.add_theme_font_size_override("font_size", 14)
	_save_status.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	_save_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_save_status)


func _show_result_ui(result: String) -> void:
	_result_layer.visible = true
	if result == "victory":
		_result_title.text = "VICTORY"
		_result_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	else:
		_result_title.text = "DEFEAT"
		_result_title.add_theme_color_override("font_color", Color(0.95, 0.25, 0.22))
	_result_sub.text = "Eliminations: %d   â€¢   Match time: %s" % [
		_kills, ReplayManager.format_duration(_match_time)]
	_save_status.text = "Replays are written to %s" % ReplayManager.get_replay_directory()
	if _objective_label:
		_objective_label.visible = false


func _on_save_replay_pressed() -> void:
	var path := ReplayManager.save_current_replay()
	if path == "":
		_save_status.text = "Save failed: no replay data."
		return
	_save_status.text = "Saved: %s" % path
	_save_button.disabled = true


func _on_replay_match_pressed() -> void:
	if not ReplayManager.has_current_replay():
		_save_status.text = "No replay data recorded."
		return
	ReplayManager.set_pending_replay(ReplayManager.current_replay)
	get_tree().change_scene_to_file("res://scenes/replay_viewer.tscn")


func _on_exit_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
