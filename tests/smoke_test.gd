extends Node
## Headless integration smoke test for the gameplay systems.
##
##   godot --headless --path . --fixed-fps 60 --scene res://tests/smoke_test.tscn
##
## Exits with code 0 when every check passes, 1 otherwise.

var _fails := 0
var _arena: Node
var _player: Player


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== boot arena")
	var scene := load("res://scenes/main.tscn") as PackedScene
	_arena = scene.instantiate()
	get_tree().root.add_child(_arena)
	get_tree().current_scene = _arena
	await _frames(30)
	_player = get_tree().get_first_node_in_group("player") as Player
	_check(_player != null, "player spawned")
	_check(_player.hud != null, "HUD created")
	_check(_player.max_health > 0.0 and _player.health == _player.max_health, "health starts full")
	_check(get_tree().get_first_node_in_group("cover_manager") != null, "cover manager present")
	_check((get_tree().get_first_node_in_group("cover_manager") as CoverManager).points.size() > 10, "cover points registered")

	await _test_slots()
	await _test_ammo_reload()
	await _test_heal_and_hud()
	await _test_enemy_ai()
	await _test_loot()
	await _test_pause()

	print("== result: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _test_slots() -> void:
	print("== weapon slots (1 / 3 / 4)")
	var w := _player.weapon
	w.select_slot(1)
	await _frames(70)
	_check(w.current_kind() != "" and w.current_id == w.slot_last[1], "slot 1 selects '%s'" % w.current_id)
	var slot1 := w.current_id
	w.select_slot(2)
	await _frames(70)
	_check(w.current_id == w.slot_last[2] and w.current_id != slot1, "slot 2 selects '%s'" % w.current_id)
	w.select_slot(3)
	await _frames(70)
	_check(w.current_id == w.slot_last[3], "slot 3 selects ordnance '%s'" % w.current_id)
	_check(w.slot_entries().size() >= 3, "slot_entries() feeds the HUD")
	w.select_slot(1)
	await _frames(70)


func _test_ammo_reload() -> void:
	print("== ammo and reload")
	var w := _player.weapon
	var mag_before := w.ammo_in_mag()
	var res_before := w.ammo_reserve()
	_check(mag_before > 0, "magazine has rounds (%d, reserve %d)" % [mag_before, res_before])
	var fired := 0
	for i in 400:
		if w.ammo_in_mag() <= 0:
			break
		if w.try_fire():
			fired += 1
		await _frames(12)
	_check(w.ammo_in_mag() == 0 and fired > 0, "firing drains the magazine (%d shots)" % fired)
	_check(not w.try_fire(), "dry magazine does not fire")
	w._auto_reload_timer = 0.0
	Input.action_press("reload")
	await _frames(2)
	Input.action_release("reload")
	await _frames(4)
	_check(w.is_reloading(), "reload starts")
	await _frames(8)
	_check(w.reload_progress() > 0.0, "reload progress animates (%.2f)" % w.reload_progress())
	await _frames(300)
	_check(not w.is_reloading() and w.ammo_in_mag() > 0, "reload completes (mag %d)" % w.ammo_in_mag())
	_check(w.ammo_reserve() < res_before, "reserve ammo consumed (%d -> %d)" % [res_before, w.ammo_reserve()])


func _test_heal_and_hud() -> void:
	print("== health + HUD")
	# Enemies may already have hit the player during earlier tests: use deltas.
	_player.heal(1000.0)
	var full := _player.health
	_player.take_damage(40.0)
	_check(is_equal_approx(_player.health, full - 40.0), "damage lowers health")
	var healed := _player.heal(25.0)
	_check(is_equal_approx(healed, 25.0), "heal restores health")
	_player.heal(1000.0)
	_check(is_equal_approx(_player.health, _player.max_health), "heal is capped at max")
	await _frames(5)


func _test_enemy_ai() -> void:
	print("== cover-based enemy AI")
	var shots := [0]
	var seen: Dictionary = {}
	var enemy_hits := [0]
	# Make sure the match has spawned enemies, then watch them for a while.
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.shot_fired.is_connected(_on_shot):
			e.shot_fired.connect(func(_m: Vector3, _t: Vector3, _s: float) -> void: shots[0] += 1)
	var start_hp := _player.health
	var charged := 0
	for tick in 60 * 40:
		await get_tree().process_frame
		# Keep the player alive and still so the AI has a steady target.
		if tick % 30 == 0:
			_player.heal(15.0)
			for e in get_tree().get_nodes_in_group("enemy"):
				if not e.has_meta("_watched"):
					e.set_meta("_watched", true)
					e.shot_fired.connect(func(_m: Vector3, _t: Vector3, _s: float) -> void: shots[0] += 1)
				seen[e.state] = int(seen.get(e.state, 0)) + 1
				if e.global_position.distance_to(_player.global_position) < 3.0:
					charged += 1
		if shots[0] >= 8 and seen.has(Enemy.State.HOLD) and seen.has(Enemy.State.PEEK):
			break
	var names := []
	for k in seen:
		names.append("%s:%d" % [Enemy.State.find_key(k), seen[k]])
	print("    observed states: ", ", ".join(names), "  shots: ", shots[0])
	_check(get_tree().get_nodes_in_group("enemy").size() > 0, "enemies alive")
	_check(seen.has(Enemy.State.TO_COVER) or seen.has(Enemy.State.HOLD), "enemies take cover")
	_check(seen.has(Enemy.State.HOLD), "enemies hold behind cover")
	_check(seen.has(Enemy.State.PEEK), "enemies peek out to fire")
	_check(shots[0] > 0, "enemies shoot with projectiles (%d shots)" % shots[0])
	_check(charged == 0, "no enemy rushed into melee range")
	print("    player hp %.0f -> %.0f (healed during test)" % [start_hp, _player.health])


func _on_shot(_m: Vector3, _t: Vector3, _s: float) -> void:
	pass


func _test_loot() -> void:
	print("== loot drops")
	var before := get_tree().get_nodes_in_group("pickup").size()
	for i in 12:
		LootTable.spawn_drops(_arena, _player.global_position + Vector3(3, 0, 0), _player)
	await _frames(5)
	var after := get_tree().get_nodes_in_group("pickup").size()
	_check(after > before, "kills drop pickups (%d -> %d)" % [before, after])
	# Walk onto them: they should be collected.
	var w := _player.weapon
	var reserve_before := w.ammo_reserve()
	_player.take_damage(50.0)
	var hp_before := _player.health
	for p in get_tree().get_nodes_in_group("pickup"):
		(p as Node3D).global_position = _player.global_position
	await _frames(90)
	_check(get_tree().get_nodes_in_group("pickup").size() < after, "pickups are collected on contact")
	_check(_player.health > hp_before or w.ammo_reserve() > reserve_before or w.ordnance.get("frag", 0) > 1 or w.owned.size() > 2,
			"pickups apply effects (hp %.0f->%.0f, reserve %d->%d)" % [hp_before, _player.health, reserve_before, w.ammo_reserve()])


func _test_pause() -> void:
	print("== pause menu")
	var pm: PauseMenu
	for c in _arena.get_children():
		if c is PauseMenu:
			pm = c
	_check(pm != null, "pause menu exists")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(4)
	_check(get_tree().paused, "Esc pauses the game")
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_ESCAPE
	ev2.keycode = KEY_ESCAPE
	ev2.pressed = true
	Input.parse_input_event(ev2)
	await _frames(4)
	_check(not get_tree().paused, "Esc resumes the game")
	pm.pause()
	await _frames(3)
	_check(get_tree().paused and pm.is_open(), "pause() opens the menu")
	pm.resume()
	await _frames(3)
	_check(not get_tree().paused, "resume() unpauses")
	# Restart reloads the arena scene.
	pm.pause()
	pm._on_restart()
	await _frames(40)
	_check(not get_tree().paused, "restart unpauses the tree")
	_check(get_tree().get_first_node_in_group("player") != null and get_tree().get_first_node_in_group("player") != _player,
			"restart builds a fresh arena")
