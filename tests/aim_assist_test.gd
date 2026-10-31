extends Node
## Headless check for aim assist and its compatibility with the reticle lag.
##   godot --headless --path . --scene res://tests/aim_assist_test.tscn

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _settle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	for i in 20:
		await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player") as Player
	player.heal(1000.0)
	var reticle: Reticle = player._reticle
	var cam := player.camera

	# Freeze every enemy, then park one in clear view, a little right of centre.
	var enemies := get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.global_position = Vector3(0, -200, 0)
	var target: Enemy = enemies[0]
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	target.global_position = Vector3(player.global_position.x, player.global_position.y, player.global_position.z) \
			+ fwd * 10.0 + right * 1.0
	await _settle(0.3)

	player.enable_aim_assist = true
	player.aim_assist_strength = 0.5
	var expected := AimAssist.pull(cam, 0.5)
	_check(expected.x > 1.0, "enemy right of centre produces a rightward pull (%s)" % expected)
	await _settle(1.0)
	_check(reticle.assist_offset.distance_to(expected) < 1.0, "reticle eases onto the pull (%s)" % reticle.assist_offset)

	player.aim_assist_strength = 0.0
	await _settle(1.0)
	_check(reticle.assist_offset.length() < 0.5, "strength 0 = no pull")
	player.aim_assist_strength = 0.5
	await _settle(1.0)

	# Compatibility: lag and assist are independent and simply add.
	player.mark_firing()
	player._look(Vector2(120.0, 0.0))
	var drag_with_assist := reticle.drag_offset
	_check(drag_with_assist.x < 0.0 and reticle.assist_offset.x > 0.0, "lag and assist act at the same time")
	_check(player.get_reticle_screen_center().is_equal_approx(get_viewport().get_visible_rect().size * 0.5
			+ reticle.recoil_offset + reticle.drag_offset + reticle.assist_offset), "aim point = centre + recoil + lag + assist")
	await _settle(1.5)

	player.enable_aim_assist = false
	await _settle(1.0)
	_check(reticle.assist_offset.length() < 0.5, "disabled = no pull")
	player.mark_firing()
	player._look(Vector2(120.0, 0.0))
	_check(reticle.drag_offset.distance_to(drag_with_assist) < 0.05, "lag offset is identical with assist on or off")
	player.enable_aim_assist = true
	await _settle(1.5)

	# No pulling toward an enemy hidden behind a wall.
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 8, 0.5)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = player.global_position + fwd * 5.0 + Vector3.UP * 1.5
	wall.look_at(wall.global_position + fwd)
	await _settle(0.5)
	_check(AimAssist.pull(cam, 0.5) == Vector2.ZERO, "no pull toward an enemy behind a wall")

	arena.queue_free()
	await get_tree().process_frame
	print("== result: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
