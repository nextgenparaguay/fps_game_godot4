extends Node
## Headless check for the world-space hitmarker.
##   godot --headless --path . --scene res://tests/hitmarker_test.tscn

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _markers(root: Node) -> Array[Node]:
	return root.find_children("*", "Sprite3D", true, false).filter(func(n): return n is Hitmarker)


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
	_check(_markers(arena).is_empty(), "no hitmarker before a hit")

	var hit := Vector3(3.0, 1.5, -12.0)
	player.hitmarker_lifetime = 0.3
	player.show_hitmarker(false, hit)
	var found := _markers(arena)
	_check(found.size() == 1, "a hit spawns exactly one hitmarker")
	var m: Hitmarker = found[0]
	_check(m.global_position.is_equal_approx(hit), "spawned at the 3D collision point")
	_check(m.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "billboard enabled (always faces the camera)")
	_check(not m.get_parent() is Player, "world-space: not parented to the player")

	player.rotate_y(1.0)                     # the view moves; the marker must not
	player.global_position += Vector3(2, 0, 2)
	await get_tree().process_frame
	_check(m.global_position.is_equal_approx(hit), "stays fixed in the world while the player moves")

	player.show_hitmarker(true, hit + Vector3(1, 0, 0))
	var kill: Hitmarker = _markers(arena).filter(func(n): return n != m)[0]
	_check(kill.modulate.r > 0.9 and kill.modulate.g < 0.3, "kill marker is red")

	await get_tree().create_timer(0.6).timeout
	_check(not is_instance_valid(m) and not is_instance_valid(kill), "freed after hitmarker_lifetime")
	_check(_markers(arena).is_empty(), "no hitmarkers left over")

	arena.queue_free()
	await get_tree().process_frame
	print("== result: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
