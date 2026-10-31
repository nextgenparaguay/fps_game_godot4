extends Node
## Headless check for the incoming-bullet SFX.
##   godot --headless --path . --scene res://tests/incoming_sound_test.tscn

func _ready() -> void:
	_run.call_deferred()


func _count_sfx() -> Array:
	var out := []
	for c in get_children():
		if c is AudioStreamPlayer and RifleProjectile.INCOMING_SOUNDS.has(c.stream):
			out.append(c)
	return out


func _run() -> void:
	get_tree().current_scene = self
	var target := Node3D.new()
	target.add_to_group("player")
	add_child(target)
	target.global_position = Vector3(0, 0, -100)

	# Bullet aimed at the target: should trigger exactly once.
	var hit := RifleProjectile.new()
	hit.hit_mask = RifleProjectile.ENEMY_HIT_MASK
	add_child(hit)
	hit.setup(Vector3(0, 1, 0), Vector3(0, 1, -100), 160.0, 10.0, null)
	# Bullet fired well wide of the target: must stay silent.
	var miss := RifleProjectile.new()
	miss.hit_mask = RifleProjectile.ENEMY_HIT_MASK
	add_child(miss)
	miss.setup(Vector3(30, 1, 0), Vector3(30, 1, -100), 160.0, 10.0, null)

	# Clips free themselves when finished, so record them as they appear.
	var seen := {}
	for i in 200:
		await get_tree().physics_frame
		for c in _count_sfx():
			if not seen.has(c.get_instance_id()):
				seen[c.get_instance_id()] = c.pitch_scale
	var ok := seen.size() == 1
	for pitch in seen.values():
		ok = ok and pitch >= 0.9 and pitch <= 1.1
		print("  incoming sfx: count=%d pitch=%.3f" % [seen.size(), pitch])
	print(("  PASS" if ok else "  FAIL") + "  incoming bullet sfx plays once for a bullet on target, not for a miss")
	get_tree().quit(0 if ok else 1)
