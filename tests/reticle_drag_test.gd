extends Node
## Headless check for firing-induced reticle aim lag.
##   godot --headless --path . --scene res://tests/reticle_drag_test.tscn

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _turn(player: Player, dx: float, dy: float) -> void:
	player._look(Vector2(dx, dy))


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
	var centre := get_viewport().get_visible_rect().size * 0.5

	_check(reticle.drag_offset == Vector2.ZERO, "no drag at rest")

	_turn(player, 120.0, 0.0)            # turning without firing: reticle stays centred
	_check(reticle.drag_offset == Vector2.ZERO, "no drag when turning without firing")

	player.mark_firing()                 # a shot (auto or semi) arms the drag
	_turn(player, 120.0, 60.0)           # turn right and down
	var d := reticle.drag_offset
	_check(d.x < 0.0 and d.y < 0.0, "reticle trails opposite to the turn (%s)" % d)
	_check(player.get_reticle_screen_center().is_equal_approx(centre + reticle.recoil_offset + d),
			"aim point includes the lag")

	player.reticle_firing_drag = 0.0
	var before := reticle.drag_offset
	_turn(player, 120.0, 0.0)
	_check(reticle.drag_offset == before, "reticle_firing_drag = 0 disables the lag")
	player.reticle_firing_drag = 0.6

	for i in 120:                        # firing has stopped: it must re-centre
		await get_tree().process_frame
	_check(reticle.drag_offset.length() < 1.0, "re-centres after firing stops (%s)" % reticle.drag_offset)

	arena.queue_free()
	await get_tree().process_frame
	print("== result: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
