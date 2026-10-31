extends Node
## Records a short match, checks enemy shots land in the replay data, then plays
## that replay in the real replay viewer.
##
##   godot --headless --path . --fixed-fps 60 --scene res://tests/replay_test.tscn

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	var player := get_tree().get_first_node_in_group("player") as Player
	for i in 60 * 30:
		await get_tree().process_frame
		if i % 20 == 0:
			player.heal(20.0)
	var data: Dictionary = ReplayManager.finish_recording("test")
	var events: Array = data.get("events", [])
	var enemy_shots := 0
	var player_shots := 0
	for e in events:
		if str(e.get("type", "")) == "shot":
			if str((e.get("data", {}) as Dictionary).get("src", "player")) == "enemy":
				enemy_shots += 1
			else:
				player_shots += 1
	print("  frames: %d  events: %d  enemy shots: %d" % [(data.get("frames", []) as Array).size(), events.size(), enemy_shots])
	var ok := enemy_shots > 0
	print("  %s  enemy shots recorded for replay" % ("PASS" if ok else "FAIL"))

	ReplayManager.set_pending_replay(data)
	arena.queue_free()
	await get_tree().process_frame
	var viewer: Node = (load("res://scenes/replay_viewer.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(viewer)
	get_tree().current_scene = viewer
	for i in 60 * 20:
		await get_tree().process_frame
	print("  PASS  replay viewer ran 20s of playback without crashing")
	get_tree().quit(0 if ok else 1)
