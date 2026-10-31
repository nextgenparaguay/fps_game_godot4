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

	# The _look() calls above really turned the view; put the enemy back in front of it.
	fwd = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	right = cam.global_transform.basis.x
	target.global_position = player.global_position + fwd * 10.0 + right * 1.0
	await _settle(0.3)

	# Lead aiming: a moving enemy is aimed at where it will be, not where it is.
	var speed := float(player.weapon.current_def.get("speed", 0.0))
	_check(speed > 0.0, "equipped gun has a bullet speed (%.0f)" % speed)
	var still := AimAssist.pull(cam, 0.5, 1.0, speed)
	target.velocity = right * 20.0
	var ahead := AimAssist.pull(cam, 0.5, 1.0, speed)
	target.velocity = -right * 20.0
	var behind := AimAssist.pull(cam, 0.5, 1.0, speed)
	target.velocity = right * 20.0
	var no_lead := AimAssist.pull(cam, 0.5, 0.0, speed)
	_check(ahead.x > still.x + 0.5, "pull leads an enemy moving right (%.2f > %.2f)" % [ahead.x, still.x])
	_check(behind.x < still.x - 0.5, "pull leads an enemy moving left (%.2f < %.2f)" % [behind.x, still.x])
	_check(no_lead.is_equal_approx(still), "lead_prediction_factor = 0 disables the lead")
	target.velocity = Vector3(0, 30.0, 0)
	_check(AimAssist.pull(cam, 0.5, 1.0, speed).is_equal_approx(still), "vertical velocity (gravity) is ignored")
	target.velocity = right * 20.0
	var half := AimAssist.pull(cam, 0.5, 0.5, speed)
	_check(half.x > still.x and half.x < ahead.x, "factor scales the lead (0.5 lies between none and full)")

	# Through the player: the reticle settles on the led point, steadily, alongside the lag.
	player.enable_aim_assist = true
	player.lead_prediction_factor = 1.0
	await _settle(1.0)
	var settled_led := reticle.assist_offset
	_check(settled_led.x > still.x + 0.5, "reticle follows the led point (%s)" % settled_led)
	var lo := 1e9
	var hi := -1e9
	for i in 40:
		await get_tree().process_frame
		lo = minf(lo, reticle.assist_offset.x)
		hi = maxf(hi, reticle.assist_offset.x)
	_check(hi - lo < 0.05, "no jitter while tracking a moving enemy (range %.4f px)" % (hi - lo))
	player.mark_firing()
	player._look(Vector2(120.0, 0.0))
	_check(reticle.drag_offset.distance_to(drag_with_assist) < 0.05, "lag offset unchanged with lead active")
	_check(player.get_reticle_screen_center().is_equal_approx(get_viewport().get_visible_rect().size * 0.5
			+ reticle.recoil_offset + reticle.drag_offset + reticle.assist_offset), "aim point still = centre + recoil + lag + assist")
	player.lead_prediction_factor = 0.0
	await _settle(1.0)
	_check(reticle.assist_offset.x < settled_led.x - 0.5, "lead off: reticle settles back toward the enemy's current position")
	target.velocity = Vector3.ZERO

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
