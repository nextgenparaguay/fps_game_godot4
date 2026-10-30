class_name Enemy
extends CharacterBody3D
## Placeholder melee rusher.
##  - Paths to the player over the baked navmesh (NavigationAgent3D), so it
##    walks around walls instead of straight into them.
##  - Uses RVO avoidance so enemies steer around each other instead of stacking.
##  - Far away it heads for a random point on a ring around the player
##    ("flanking"), so groups arrive from different directions, then closes in.
##  - Explodes into gibs when killed; more overkill damage => bigger explosion.

signal died

const BLOOD_SOUND := preload("res://assets/sounds/blood_impact_.wav")

@export var max_health := 100.0
@export var move_speed := 4.5
@export var attack_damage := 12.0
@export var attack_range := 1.8
@export var attack_interval := 0.9
@export var gravity := 22.0
@export var flank_distance := 14.0   ## farther than this from the player => take a flanking route
@export var flank_radius := 8.0

var health := 0.0

var _dying := false
var _dead := false
var _attack_timer := 0.0
var _flash := 0.0
var _last_shot_dir := Vector3.ZERO
var _player: Player
var _mat: StandardMaterial3D
var _agent: NavigationAgent3D
var _safe_velocity := Vector3.ZERO
var _repath_timer := 0.0
var _flank_angle := NAN             # NAN = pick one on the next _pick_target()
var _flanking := true


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	collision_layer = 4          # layer 3 = enemies
	collision_mask = 1 | 2 | 4   # world + player + other enemies (hard backstop for avoidance)
	_repath_timer = randf() * 0.3

	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.55, 0.6, 0.72)
	_mat.emission_enabled = true
	_mat.emission = Color.BLACK

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.4
	body_mesh.height = 1.8
	body_mesh.material = _mat
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.position.y = 0.9
	add_child(body)

	# "Visor" so you can see which way it's facing (front = -Z)
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.5, 0.12, 0.2)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.05, 0.05, 0.05)
	visor_mesh.material = visor_mat
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.position = Vector3(0, 1.5, -0.32)
	add_child(visor)

	_agent = NavigationAgent3D.new()
	_agent.radius = 0.6
	_agent.height = 1.8
	_agent.max_speed = move_speed
	_agent.path_desired_distance = 0.8
	_agent.path_max_distance = 2.2
	_agent.target_desired_distance = 0.8
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = 7.0
	_agent.max_neighbors = 12
	_agent.time_horizon_agents = 1.8
	_agent.time_horizon_obstacles = 1.0
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player

	_flash = move_toward(_flash, 0.0, delta * 8.0)
	_mat.emission = Color(1.0, 0.1, 0.05) * _flash

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var to_player := Vector3.ZERO
	if _player:
		to_player = _player.global_position - global_position
	var vertical := to_player.y
	to_player.y = 0.0
	var dist := to_player.length()

	# --- Navigation: pick a target, follow the path, let avoidance adjust velocity
	var desired := Vector3.ZERO
	var nav_ready := NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0
	if _player and nav_ready:
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = 0.25 + randf() * 0.1
			_agent.target_position = _pick_target(dist)
		if dist > attack_range * 0.7 and not _agent.is_navigation_finished():
			var step := _agent.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.05:
				desired = step.normalized() * move_speed
		_agent.velocity = desired            # feeds avoidance; result arrives in _on_velocity_computed
	else:
		_safe_velocity = Vector3.ZERO

	velocity.x = _safe_velocity.x
	velocity.z = _safe_velocity.z
	# RVO is the primary separation solver; this small extra push guarantees
	# that two rushers converging on the same point cannot settle on top of
	# each other when they get cornered against the player or a wall.
	var separation := _separation_velocity()
	velocity.x += separation.x
	velocity.z += separation.z

	# Face where we're going, or at the player when close
	var face := Vector3(velocity.x, 0.0, velocity.z)
	if dist < attack_range * 1.5 or face.length() < 0.5:
		face = to_player
	if face.length() > 0.01:
		face = face.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-10.0 * delta))
	move_and_slide()

	_attack_timer -= delta
	if _player and dist <= attack_range and absf(vertical) < 2.0 and _attack_timer <= 0.0:
		_attack_timer = attack_interval
		_player.take_damage(attack_damage)


## Returns true if this hit was lethal (used for the kill hitmarker).
func take_damage(amount: float, hit_pos: Vector3, hit_normal: Vector3, shot_dir: Vector3) -> bool:
	if _dead:
		return false
	health -= amount
	_flash = 1.0
	_last_shot_dir = shot_dir
	Gore.blood_puff(hit_pos, hit_normal)

	# Defer the explosion to the end of the frame so every shotgun pellet that
	# lands this frame counts toward the overkill amount.
	if health <= 0.0 and not _dying:
		_dying = true
		_explode.call_deferred()
	return health <= 0.0


## Far away: head for a point on a ring around the player (so a group spreads
## out and arrives from different sides). Close in: go straight for the player.
## The ring point is chosen on *this enemy's side* of the player (+/- ~60 deg)
## so enemies fan out instead of all circling to the far side. Hysteresis
## (leave at flank_distance, only re-enter at 4x) stops the target flip-flopping
## when a wall makes the walking route much longer than the straight line.
func _pick_target(dist_to_player: float) -> Vector3:
	var p := _player.global_position
	if _flanking and dist_to_player < flank_distance:
		_flanking = false
	elif not _flanking and dist_to_player > flank_distance * 4.0:
		_flanking = true
		_flank_angle = NAN
	if _flanking:
		if is_nan(_flank_angle):
			var base := atan2(global_position.z - p.z, global_position.x - p.x)
			_flank_angle = base + randf_range(-1.05, 1.05)
		return p + Vector3(cos(_flank_angle), 0.0, sin(_flank_angle)) * flank_radius
	return p


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity


func _separation_velocity() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.001 and d < 1.7:
			push += away / d * (1.0 - d / 1.7)
	if push.length_squared() > 0.0001:
		push = push.normalized() * minf(push.length(), 1.0) * 1.6
	return push


func _explode() -> void:
	_dead = true
	var overkill := -health
	var intensity := clampf(1.0 + overkill / max_health, 1.0, 2.5)
	_play_death_sound()
	Gore.explode(global_position + Vector3.UP * 1.0, intensity, _last_shot_dir)
	died.emit()
	queue_free()


## Spatial death squelch. A small random pitch shift keeps repeated kills from
## sounding identical.
func _play_death_sound() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = BLOOD_SOUND
	p.pitch_scale = randf_range(0.92, 1.08)
	p.volume_db = randf_range(-4.0, -2.0)
	p.unit_size = 7.0
	p.max_distance = 70.0
	root.add_child(p)
	p.global_position = global_position + Vector3.UP * 1.0
	p.finished.connect(p.queue_free)
	p.play()
