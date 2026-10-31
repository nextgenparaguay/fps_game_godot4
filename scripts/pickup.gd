class_name Pickup
extends Node3D
## A collectible dropped by enemies: ammo, medkits, weapons and ordnance.
##
## Walking within `PICKUP_RADIUS` collects it (if the player can actually use
## it: a medkit at full health stays on the ground). Pickups the player could
## use are gently pulled in once close. Unclaimed pickups blink and vanish.
##
## `payload` per kind:
##   ammo     {"ammo": "rifle", "amount": 30}
##   medkit   {"heal": 40.0}
##   weapon   {"weapon": "smg"}
##   ordnance {"ordnance": "frag", "amount": 1}

const PICKUP_RADIUS := 1.4
const MAGNET_RADIUS := 4.5
const LIFETIME := 45.0

var kind := "ammo"
var payload: Dictionary = {}
var label_text := ""
var tint := Color(1.0, 0.8, 0.2)

var _age := 0.0
var _bob := randf() * TAU
var _visual: Node3D
var _player: Player


func _ready() -> void:
	add_to_group("pickup")
	_visual = Node3D.new()
	_visual.position.y = 0.6
	add_child(_visual)
	match kind:
		"medkit": _build_medkit()
		"weapon": _build_weapon()
		"ordnance": _build_ordnance()
		_: _build_ammo()

	# Ground glow ring + coloured light so drops read from across the arena.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.45)
	ring_mat.emission_enabled = true
	ring_mat.emission = tint
	ring_mat.emission_energy_multiplier = 1.5
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ring := CylinderMesh.new()
	ring.top_radius = 0.5
	ring.bottom_radius = 0.5
	ring.height = 0.02
	ring.material = ring_mat
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.position.y = 0.04
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_mi)

	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 0.8
	light.omni_range = 3.5
	light.position.y = 0.7
	add_child(light)

	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.0045
	label.outline_size = 10
	label.modulate = tint.lightened(0.35)
	label.position.y = 1.15
	add_child(label)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	_bob += delta * 2.6
	_visual.position.y = 0.6 + sin(_bob) * 0.07
	_visual.rotation.y += delta * 1.7
	visible = _age < LIFETIME - 8.0 or int(_age * 5.0) % 2 == 0     # blink before despawn

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	if _player.is_dead():
		return

	var target := _player.global_position + Vector3.UP * 0.9
	var d := global_position.distance_to(target)
	var weapon := _player.weapon
	if d > MAGNET_RADIUS or not weapon.apply_pickup(kind, payload, true):
		return                                   # out of range, or the player can't use it
	if d <= PICKUP_RADIUS:
		if weapon.apply_pickup(kind, payload):
			ProcAudio.play_ui(_player, "medkit" if kind == "medkit" else "pickup", -4.0)
			queue_free()
		return
	# Magnet: ease toward the player once close and useful.
	var pull := (target - global_position).normalized() * lerpf(2.0, 9.0, 1.0 - d / MAGNET_RADIUS)
	global_position += Vector3(pull.x, 0.0, pull.z) * delta


# ----------------------------------------------------------------------------
# Placeholder visuals
# ----------------------------------------------------------------------------

func _build_ammo() -> void:
	_part(Vector3(0.30, 0.18, 0.20), Vector3.ZERO, Color(0.55, 0.42, 0.16))
	_part(Vector3(0.31, 0.04, 0.21), Vector3(0, 0.05, 0), Color(0.15, 0.13, 0.08))
	for i in 3:                                                       # bullet tips
		_part(Vector3(0.045, 0.07, 0.045), Vector3(-0.09 + i * 0.09, 0.13, 0), Color(0.9, 0.72, 0.25))


func _build_medkit() -> void:
	_part(Vector3(0.36, 0.24, 0.20), Vector3.ZERO, Color(0.92, 0.94, 0.94))
	_part(Vector3(0.20, 0.06, 0.205), Vector3.ZERO, Color(0.85, 0.12, 0.12))
	_part(Vector3(0.06, 0.20, 0.205), Vector3.ZERO, Color(0.85, 0.12, 0.12))


func _build_weapon() -> void:
	var id := str(payload.get("weapon", "smg"))
	_part(Vector3(0.50, 0.10, 0.07), Vector3.ZERO, Color(0.12, 0.13, 0.16))
	_part(Vector3(0.32, 0.035, 0.05), Vector3(-0.30, 0.02, 0), Color(0.2, 0.21, 0.25))
	_part(Vector3(0.06, 0.17, 0.06), Vector3(0.10, -0.12, 0), Color(0.92, 0.42, 0.08))
	if id == "sniper":
		_part(Vector3(0.22, 0.05, 0.05), Vector3(0.02, 0.09, 0), Color(0.1, 0.35, 0.8))


func _build_ordnance() -> void:
	if str(payload.get("ordnance", "frag")) == "c4":
		_part(Vector3(0.30, 0.09, 0.20), Vector3.ZERO, Color(0.28, 0.30, 0.20))
		_part(Vector3(0.05, 0.02, 0.03), Vector3(-0.08, 0.055, 0), Color(1.0, 0.1, 0.05))
	else:
		var mesh := SphereMesh.new()
		mesh.radius = 0.12
		mesh.height = 0.24
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.22, 0.30, 0.16)
		mesh.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(mi)
		_part(Vector3(0.05, 0.08, 0.05), Vector3(0, 0.14, 0), Color(0.6, 0.6, 0.65))


func _part(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mi)
