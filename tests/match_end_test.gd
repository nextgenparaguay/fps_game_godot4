extends Node
## Headless test for the end-of-match sequences.
##
##   godot --headless --path . --fixed-fps 60 --scene res://tests/match_end_test.tscn
##
## Defeat: the player bursts into gibs, a death camera pulls out to look at the
## death spot, no loot drops, and the result panel appears ~5 s later.
## Victory: slow motion starts at the last kill, the result panel appears ~2 s
## later and the time scale is back to normal.
##
## Exits with code 0 when every check passes, 1 otherwise.

var _fails := 0
var _arena: Node
var _player: Player
var _elapsed := 0.0       ## real seconds (unscaled), accumulated in _process


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _process(delta: float) -> void:
	_elapsed += delta / maxf(Engine.time_scale, 0.001)


func _ready() -> void:
	_run.call_deferred()


func _wait_real(seconds: float) -> void:
	var until := _elapsed + seconds
	while _elapsed < until:
		await get_tree().process_frame


func _boot() -> void:
	_arena = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_arena)
	get_tree().current_scene = _arena
	await _wait_real(0.5)
	_player = get_tree().get_first_node_in_group("player") as Player


func _teardown() -> void:
	_arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	await _test_defeat()
	await _test_victory()
	print("== result: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _result_visible() -> bool:
	return _arena._result_layer.visible


func _gib_count() -> int:
	var n := 0
	for c in _arena.get_children():
		if c is Gib:
			n += 1
	return n


func _test_defeat() -> void:
	print("== defeat: death burst, death camera, 5 s delay")
	await _boot()
	var pickups_before := get_tree().get_nodes_in_group("pickup").size()
	var eye := _player.camera.global_position
	var focus := _player.global_position + Vector3.UP
	_player.take_damage(10000.0, Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1))
	await _wait_real(0.3)

	_check(_player.is_dead(), "player is dead")
	_check(_gib_count() > 10, "player bursts into gibs (%d)" % _gib_count())
	_check(not _player.weapon.visible and not _player.hud.visible, "first-person weapon and HUD are hidden")
	_check(get_tree().get_nodes_in_group("pickup").size() == pickups_before, "player death drops no loot")
	var cam := get_viewport().get_camera_3d()
	_check(cam != null and cam != _player.camera, "death camera is the active camera")
	var d_early := cam.global_position.distance_to(focus)

	await _wait_real(2.0)
	var d_mid := cam.global_position.distance_to(focus)
	_check(d_mid > d_early + 1.0, "camera keeps pulling away (%.1f -> %.1f m)" % [d_early, d_mid])

	await _wait_real(2.0)         # ~4.3 s since death
	_check(not _result_visible(), "result panel still hidden before ~5 s")
	var d_end := cam.global_position.distance_to(focus)
	var look := (focus - cam.global_position).normalized().dot(-cam.global_transform.basis.z)
	_check(d_end > 5.0 and cam.global_position.y > eye.y + 2.0,
			"camera ends behind/above the death spot (%.1f m away)" % d_end)
	_check(look > 0.99, "camera looks at the death spot (dot %.3f)" % look)

	await _wait_real(1.0)         # ~5.3 s since death
	_check(_result_visible(), "result panel visible after ~5 s")
	var events: Array = ReplayManager.current_replay.get("events", [])
	_check(events.any(func(e: Dictionary) -> bool: return e["type"] == "death"),
			"player burst is recorded as a replay death event")
	_check(ReplayManager.current_replay.get("outcome") == "defeat", "outcome is defeat")
	await _teardown()


func _test_victory() -> void:
	print("== victory: slow motion, 2 s delay")
	await _boot()
	for e in get_tree().get_nodes_in_group("enemy"):
		e.take_damage(10000.0, e.global_position, Vector3.UP, Vector3.RIGHT)
	await _wait_real(0.3)
	_check(is_equal_approx(Engine.time_scale, _arena.VICTORY_SLOWMO_SCALE),
			"slow motion starts at the last kill (x%.2f)" % Engine.time_scale)
	_player.toggle_bullet_time()
	_check(is_equal_approx(Engine.time_scale, _arena.VICTORY_SLOWMO_SCALE), "bullet time can't override it")
	var hp := _player.health
	_player.take_damage(10000.0)
	_check(not _player.is_dead() and _player.health == hp, "player is invulnerable during the win window")
	await _wait_real(0.7)         # ~1.0 s
	_check(not _result_visible(), "result panel still hidden before ~2 s")
	_check(Engine.time_scale < 0.5, "still in slow motion at ~1 s (x%.2f)" % Engine.time_scale)
	await _wait_real(1.2)         # ~2.2 s
	_check(_result_visible(), "result panel visible after ~2 s")
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale restored (x%.2f)" % Engine.time_scale)
	_check(ReplayManager.current_replay.get("outcome") == "victory", "outcome is victory")
	await _teardown()
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale is normal after leaving the arena")
