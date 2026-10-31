class_name Weapon
extends Node3D
## Player weapon system: slots, ammo, reloads, guns, grenades and C4.
##
## Weapon stats live in weapon_defs.gd and the placeholder models in
## weapon_models.gd; this node owns the inventory and drives the viewmodel.
##
##   slot 1 [key 1]  pistol / smg            slot 2 [key 3]  rifle / sniper
##   slot 3 [key 4]  frag grenade / C4       (press a slot key again to cycle it)
##
## What makes the viewmodel feel alive (unchanged from the single-rifle version):
##   1. The whole weapon pivot is rotated every frame so the barrel points at
##      the world point under the projected reticle.
##   2. Both arms are solved with analytic two-bone IK to the weapon's grips, so
##      the hands stay on the gun while it is aimed / sprinted / reloaded.
##
## Recoil routing:  hip-fire -> reticle UI kick (up + jitter), no camera kick
##                  ADS      -> camera kick, reticle recoil disabled
##
## Shots are real projectiles spawned at the muzzle; see projectile.gd.

const MAX_RANGE := 400.0
const HIT_MASK := 1 | 4              # world + enemies
const WORLD_MASK := 1
const ProjectileScript := preload("res://scripts/projectile.gd")
const GrenadeScript := preload("res://scripts/grenade.gd")
const C4Script := preload("res://scripts/c4_charge.gd")
const SHOT_SOUND := preload("res://assets/sounds/semiautorifleshot.wav")

signal shot_fired(muzzle: Vector3, target: Vector3, speed: float)
signal projectile_hit(hit_pos: Vector3, lethal: bool)
signal message(text: String, color: Color)

const POSE_SCALE := 0.82
const ADS_SPEED := 12.0
const SPRINT_POS_OFFSET := Vector3(0.02, -0.045, 0.05)
const SPRINT_POSE_DEG := Vector3(-17.0, 27.0, -8.0)
const SPRINT_FIRE_OVERRIDE_SPEED := 26.0
const FIRE_OVERRIDE_SPEED := 20.0
const SWITCH_DOWN_TIME := 0.12
const SWITCH_UP_TIME := 0.20
const THROW_TIME := 0.62
const THROW_RELEASE := 0.36
const PLACE_TIME := 0.48
const PLACE_RELEASE := 0.34
const DETONATE_TIME := 0.40
const DETONATE_RELEASE := 0.45

var player: Player
var camera: Camera3D
var ads_amount := 0.0

# --- Inventory ---------------------------------------------------------------
var owned: Dictionary = {}           # gun id -> true
var mags: Dictionary = {}            # gun id -> rounds in the magazine
var reserve: Dictionary = {}         # ammo type -> spare rounds
var ordnance: Dictionary = {}        # "frag"/"c4" -> carried count
var slot_last: Dictionary = {1: "pistol", 2: "rifle", 3: "frag"}
var current_id := "rifle"
var current_def: Dictionary = {}

# --- Gun state ---------------------------------------------------------------
var _cooldown := 0.0
var _ads_t := 0.0
var _sprint_t := 0.0
var _fire_override := 0.0
var _kick := 0.0
var _bob_t := 0.0
var _bloom := 0.0
var _flash_timer := 0.0
var _firing := false
var _sprint_fire_timer := 0.0
var _auto_reload_timer := 0.0

# Reload
var _reload_left := 0.0
var _reload_total := 1.0
var _reload_stage := 0
var _reload_pos := Vector3.ZERO      # this frame's reload animation offsets
var _reload_rot := Vector3.ZERO
var _reload_hand := Vector3.ZERO     # left-hand offset in pivot space

# Weapon switching: lower the old weapon, swap the model, raise the new one.
var _switching := false
var _switch_phase := 0               # 0 = lowering, 1 = raising
var _switch_timer := 0.0
var _pending_id := ""

# Throw / place / detonate animation
var _action_kind := ""               # "throw" | "place" | "detonate" | ""
var _action_t := 0.0
var _action_dur := 0.5
var _action_release_at := 0.4
var _action_released := false
var _pending_c4_pos := Vector3.ZERO
var _pending_c4_normal := Vector3.UP
var _placed_c4: Array = []

# --- Nodes -------------------------------------------------------------------
var _pivot: Node3D
var _pose: Node3D
var _models: Dictionary = {}         # id -> model dictionary from WeaponModels
var _model: Dictionary = {}
var _arms: Node3D
var _upper_r: MeshInstance3D
var _fore_r: MeshInstance3D
var _hand_r: MeshInstance3D
var _upper_l: MeshInstance3D
var _fore_l: MeshInstance3D
var _hand_l: MeshInstance3D
var _skin_mat: StandardMaterial3D
var _sleeve_mat: StandardMaterial3D
var _shot_players: Array[AudioStreamPlayer] = []
var _shot_voice := 0


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "AimPivot"
	add_child(_pivot)
	_pose = Node3D.new()
	_pose.name = "SprintPose"
	_pose.scale = Vector3.ONE * POSE_SCALE
	_pivot.add_child(_pose)

	for id in WeaponDefs.DEFS:
		var m := WeaponModels.build(id, _pose)
		(m["root"] as Node3D).visible = false
		_models[id] = m

	_build_arms()
	_build_audio()
	_init_inventory()
	_apply_equip(WeaponDefs.START_WEAPON, false)
	ProcAudio.warm()


func _init_inventory() -> void:
	owned.clear()
	mags.clear()
	for id in WeaponDefs.START_OWNED:
		owned[id] = true
		mags[id] = int(WeaponDefs.get_def(id)["mag"])
	reserve = WeaponDefs.START_RESERVE.duplicate()
	ordnance = WeaponDefs.START_ORDNANCE.duplicate()


# ----------------------------------------------------------------------------
# Public queries (HUD, player, loot, tests)
# ----------------------------------------------------------------------------

func current_name() -> String:
	return str(current_def.get("name", "Weapon"))


func current_kind() -> String:
	return str(current_def.get("kind", "gun"))


func is_gun() -> bool:
	return current_kind() == "gun"


func can_ads() -> bool:
	return is_gun()


func current_zoom() -> float:
	return float(current_def.get("zoom", 1.0)) if is_gun() else 1.0


func is_scoped() -> bool:
	return bool(current_def.get("scope", false)) and ads_amount > 0.9


func has_item(id: String) -> bool:
	var d := WeaponDefs.get_def(id)
	match str(d.get("kind", "")):
		"gun": return owned.has(id)
		"grenade": return int(ordnance.get(id, 0)) > 0
		"c4": return int(ordnance.get("c4", 0)) > 0 or placed_c4_count() > 0
	return false


func ammo_in_mag() -> int:
	if is_gun():
		return int(mags.get(current_id, 0))
	return int(ordnance.get(current_id, 0))


func ammo_reserve() -> int:
	if is_gun():
		return int(reserve.get(str(current_def["ammo"]), 0))
	return 0


func is_reloading() -> bool:
	return _reload_left > 0.0


func reload_progress() -> float:
	return 1.0 - clampf(_reload_left / maxf(_reload_total, 0.01), 0.0, 1.0) if is_reloading() else 0.0


func placed_c4_count() -> int:
	var n := 0
	for c in _placed_c4:
		if is_instance_valid(c):
			n += 1
	return n


## True when the player is nearly out of ammo for everything they own (loot weighting).
func is_low_on_ammo() -> bool:
	for id in owned:
		if not WeaponDefs.is_gun(id):
			continue
		var d := WeaponDefs.get_def(id)
		var total := int(mags.get(id, 0)) + int(reserve.get(str(d["ammo"]), 0))
		if total > int(d["mag"]):
			return false
	return true


func hint_text() -> String:
	match current_kind():
		"grenade": return "LMB: throw"
		"c4": return "LMB: place   RMB: detonate (%d placed)" % placed_c4_count()
	if is_reloading():
		return "RELOADING"
	if ammo_in_mag() <= 0:
		return "NO AMMO" if ammo_reserve() <= 0 else "PRESS R TO RELOAD"
	if ammo_in_mag() <= maxi(int(int(current_def["mag"]) * 0.25), 1) and ammo_reserve() > 0:
		return "LOW AMMO - R"
	return ""


## One entry per owned item, for the HUD slot list.
func slot_entries() -> Array:
	var out: Array = []
	for slot in [1, 2, 3]:
		for id in WeaponDefs.ids_in_slot(slot):
			if not has_item(id):
				continue
			var d := WeaponDefs.get_def(id)
			var count := ""
			match str(d["kind"]):
				"grenade": count = "x%d" % int(ordnance.get(id, 0))
				"c4": count = "x%d" % int(ordnance.get(id, 0))
			out.append({
				"slot": slot, "key": str(WeaponDefs.SLOT_LABELS[slot]), "id": id,
				"name": str(d["name"]), "count": count,
				"selected": id == (_pending_id if _switching and _pending_id != "" else current_id),
			})
	return out


# ----------------------------------------------------------------------------
# Equip / switching
# ----------------------------------------------------------------------------

func select_slot(slot: int) -> void:
	var ids: Array = []
	for id in WeaponDefs.ids_in_slot(slot):
		if has_item(id):
			ids.append(id)
	if ids.is_empty():
		return
	var shown := _pending_id if _switching and _pending_id != "" else current_id
	var target: String
	if int(WeaponDefs.get_def(shown)["slot"]) == slot:
		if ids.size() < 2:
			return
		target = ids[(ids.find(shown) + 1) % ids.size()]      # cycle within the slot
	else:
		target = slot_last[slot] if ids.has(slot_last[slot]) else ids[0]
	request_equip(target)


func request_equip(id: String) -> void:
	if not has_item(id):
		return
	var shown := _pending_id if _switching and _pending_id != "" else current_id
	if id == shown:
		return
	if _action_kind != "":
		return                                   # mid throw / place: finish first
	_cancel_reload()
	_pending_id = id
	if not _switching:
		_switching = true
		_switch_phase = 0
		_switch_timer = SWITCH_DOWN_TIME


func _update_switch(delta: float) -> void:
	if not _switching:
		return
	_switch_timer -= delta
	if _switch_timer > 0.0:
		return
	if _switch_phase == 0:
		_apply_equip(_pending_id, true)
		_switch_phase = 1
		_switch_timer = SWITCH_UP_TIME
	else:
		_switching = false
		_pending_id = ""


## 0 = weapon fully up, 1 = fully lowered.
func _switch_amount() -> float:
	if not _switching:
		return 0.0
	if _switch_phase == 0:
		return smoothstep(0.0, 1.0, 1.0 - _switch_timer / SWITCH_DOWN_TIME)
	return smoothstep(0.0, 1.0, clampf(_switch_timer / SWITCH_UP_TIME, 0.0, 1.0))


func _apply_equip(id: String, play_sound := true) -> void:
	for k in _models:
		(_models[k]["root"] as Node3D).visible = false
	current_id = id
	current_def = WeaponDefs.get_def(id)
	_model = _models[id]
	(_model["root"] as Node3D).visible = true
	slot_last[int(current_def["slot"])] = id
	_bloom = 0.0
	_kick = 0.0
	_cooldown = 0.15
	if play_sound and is_inside_tree():
		ProcAudio.play_ui(self, "equip", -8.0)


func _switch_to_fallback() -> void:
	for id in [slot_last[2], slot_last[1], "rifle", "pistol"]:
		if has_item(id):
			request_equip(id)
			return


# ----------------------------------------------------------------------------
# Audio
# ----------------------------------------------------------------------------

## A tiny voice pool lets rapid automatic fire overlap without cutting the
## previous shot off. Each shot gets a slight random pitch shift.
func _build_audio() -> void:
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.stream = SHOT_SOUND
		p.volume_db = -5.0
		add_child(p)
		_shot_players.append(p)


func _play_shot_sound() -> void:
	if _shot_players.is_empty():
		return
	var p := _shot_players[_shot_voice]
	_shot_voice = (_shot_voice + 1) % _shot_players.size()
	p.pitch_scale = float(current_def.get("sound_pitch", 1.0)) * randf_range(0.96, 1.04)
	p.volume_db = float(current_def.get("sound_db", -5.0)) + randf_range(-1.0, 1.0)
	p.play()


# ----------------------------------------------------------------------------
# Tick
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or player.is_dead():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	_update_switch(delta)
	_update_reload(delta)
	_update_action(delta)

	if _auto_reload_timer > 0.0:
		_auto_reload_timer -= delta
		if _auto_reload_timer <= 0.0:
			start_reload()

	if captured:
		_handle_slot_input()
		if Input.is_action_just_pressed("reload"):
			start_reload()
		if not _switching and _action_kind == "":
			_handle_fire_input()

	var sprinting := player.is_sprinting()
	var busy := _switching or is_reloading() or _action_kind != ""
	var want_ads := captured and Input.is_action_pressed("ads") and not sprinting \
			and can_ads() and not busy
	_ads_t = move_toward(_ads_t, 1.0 if want_ads else 0.0, delta * ADS_SPEED)
	ads_amount = smoothstep(0.0, 1.0, _ads_t)

	_firing = captured and is_gun() and not _switching and Input.is_action_pressed("fire")
	_sprint_fire_timer = maxf(_sprint_fire_timer - delta, 0.0)
	# Sprint pose drops instantly when movement stops; it still ramps in when
	# sprint begins so entering sprint does not pop the viewmodel.
	if sprinting:
		_sprint_t = lerpf(_sprint_t, 1.0, 1.0 - exp(-10.0 * delta))
	else:
		_sprint_t = 0.0

	var firing_from_sprint := (_firing or _sprint_fire_timer > 0.0) \
			and _sprint_t > 0.18 and ads_amount < 0.35
	var override_target := 1.0 if firing_from_sprint else 0.0
	_fire_override = move_toward(_fire_override, override_target,
			delta * (SPRINT_FIRE_OVERRIDE_SPEED if override_target > 0.5 else FIRE_OVERRIDE_SPEED))

	_bloom = maxf(_bloom - float(current_def.get("bloom_recovery", 5.0)) * delta, 0.0)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-12.0 * delta))

	_update_viewmodel(delta)

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			(_model["flash"] as Node3D).visible = false


func _handle_slot_input() -> void:
	for slot in [1, 2, 3]:
		if Input.is_action_just_pressed(str(WeaponDefs.SLOT_KEYS[slot])):
			select_slot(slot)


func _handle_fire_input() -> void:
	match current_kind():
		"gun":
			var wants: bool = Input.is_action_pressed("fire") if bool(current_def["auto"]) \
					else Input.is_action_just_pressed("fire")
			if wants:
				try_fire()
		"grenade":
			if Input.is_action_just_pressed("fire") and int(ordnance.get(current_id, 0)) > 0:
				_start_throw()
		"c4":
			if Input.is_action_just_pressed("fire") and int(ordnance.get("c4", 0)) > 0:
				_start_place()
			elif Input.is_action_just_pressed("ads") and placed_c4_count() > 0:
				_start_detonate()


# ----------------------------------------------------------------------------
# Shooting
# ----------------------------------------------------------------------------

## Fires if the weapon is ready (cooldown, ammo, not reloading). Returns true if a shot left.
func try_fire() -> bool:
	if not is_gun() or _switching or _cooldown > 0.0 or is_reloading():
		return false
	if int(mags.get(current_id, 0)) <= 0:
		_dry_fire()
		return false
	fire()
	return true


func _dry_fire() -> void:
	_cooldown = 0.3
	ProcAudio.play_ui(self, "click", -8.0)
	if ammo_reserve() > 0:
		start_reload()
	else:
		message.emit("NO AMMO", Color(1.0, 0.4, 0.3))


func fire() -> void:
	var d := current_def
	_cooldown = 1.0 / maxf(float(d["rate"]), 0.1)
	mags[current_id] = int(mags[current_id]) - 1

	# A shot taken from the sprint pose snaps the weapon forward immediately and
	# holds it forward for a moment so even a quick tap fully overrides sprint.
	if _sprint_t > 0.18:
		_fire_override = 1.0
		_sprint_fire_timer = 0.30
		_pose.rotation_degrees = Vector3.ZERO
		_pivot.position = d["hip_pos"]
	# Re-align just before reading the muzzle so the projectile leaves the
	# barrel as it is rendered this frame, not last frame's pose.
	_align_to_aim()

	var spread_px := current_spread_px()
	var cam_origin := camera.global_position
	var screen_center := player.get_reticle_screen_center()

	# Sample a uniformly random point inside the reticle's circular spread. This
	# is the same radius the player sees, so the bullet pattern and the ring can
	# never disagree.
	var spread_angle := randf() * TAU
	var spread_radius := spread_px * sqrt(randf())
	var shot_screen := screen_center + Vector2(cos(spread_angle), sin(spread_angle)) * spread_radius
	var aim_dir := camera.project_ray_normal(shot_screen).normalized()

	# The world point under the (centre) projected reticle / spread sample.
	var hit := _ray(cam_origin, cam_origin + aim_dir * MAX_RANGE)
	var target := cam_origin + aim_dir * MAX_RANGE
	var aim_distance := MAX_RANGE
	if not hit.is_empty():
		target = hit["position"]
		aim_distance = cam_origin.distance_to(target)

	var muzzle_pos := (_model["muzzle"] as Marker3D).global_position
	# If a wall is closer than the visible muzzle, don't spawn the bullet behind
	# the wall: start just in front of the camera along the shot direction.
	var spawn := muzzle_pos
	if aim_distance < cam_origin.distance_to(muzzle_pos) + 0.10:
		spawn = cam_origin + aim_dir * 0.30

	var speed := float(d["speed"])
	var projectile = ProjectileScript.new()
	get_tree().current_scene.add_child(projectile)
	projectile.setup(spawn, target, speed, float(d["damage"]), player, self)
	shot_fired.emit(spawn, target, speed)

	# Consecutive shots open the reticle up to a hard cap.
	_bloom = minf(_bloom + float(d["bloom_per_shot"]), float(d["max_bloom"]))
	_kick = minf(_kick + 0.55, 1.0)
	(_model["flash"] as Node3D).visible = true
	_flash_timer = 0.045
	_play_shot_sound()

	# Hip-fire recoil is UI-only; ADS recoil is applied to the camera.
	if ads_amount > 0.45:
		var pitch := float(d["ads_pitch"]) * randf_range(0.85, 1.15)
		var yaw := randf_range(-float(d["ads_yaw"]), float(d["ads_yaw"]))
		player.add_camera_recoil(pitch, yaw)
	else:
		player.add_reticle_recoil(float(d["kick_px"]), float(d["jitter_px"]))

	# Empty magazine: reload automatically after a beat.
	if int(mags[current_id]) <= 0 and ammo_reserve() > 0:
		_auto_reload_timer = 0.35


func notify_projectile_hit(collider: Object, lethal: bool, hit_pos: Vector3) -> void:
	if collider is Enemy:
		projectile_hit.emit(hit_pos, lethal)
		player.show_hitmarker(lethal, hit_pos)


func notify_environment_hit(_pos: Vector3, _normal: Vector3) -> void:
	pass


## Current cone half-angle in degrees, including movement/air/sprint and bloom.
func current_spread_deg() -> float:
	if not is_gun():
		return 0.3
	var d := current_def
	var base := lerpf(float(d["hip_spread"]), float(d["ads_spread"]), ads_amount)
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	var motion := clampf(hspeed / maxf(player.sprint_speed, 0.1), 0.0, 1.0) * float(d["move_spread"])
	if not player.is_on_floor():
		motion += float(d["air_spread"])
	if player.is_sprinting():
		motion += float(d["sprint_spread"])
	motion *= lerpf(1.0, 0.22, ads_amount)
	var bloom := _bloom * lerpf(1.0, 0.55, ads_amount)
	return base + motion + bloom


## Converts the current angular spread to a pixel radius at the reticle.
func current_spread_px() -> float:
	var h := get_viewport().get_visible_rect().size.y
	if h <= 1.0:
		h = 720.0
	var fov := maxf(camera.fov, 1.0) if camera else 90.0
	var half_tan := tan(deg_to_rad(fov) * 0.5)
	if half_tan <= 0.0001:
		return 7.0
	return tan(deg_to_rad(current_spread_deg())) / half_tan * h * 0.5


func _ray(from: Vector3, to: Vector3, mask := HIT_MASK) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if is_instance_valid(player):
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return space.intersect_ray(query)


## The point the reticle projects to in the 3D world (includes UI recoil).
func get_aim_point() -> Vector3:
	if player == null:
		return camera.global_position - camera.global_transform.basis.z * MAX_RANGE
	var screen := player.get_reticle_screen_center()
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen).normalized()
	var hit := _ray(from, from + dir * MAX_RANGE)
	if hit.is_empty():
		return from + dir * MAX_RANGE
	return hit["position"]


# ----------------------------------------------------------------------------
# Reloading
# ----------------------------------------------------------------------------

func start_reload() -> bool:
	if not is_gun() or is_reloading() or _switching or _action_kind != "":
		return false
	if int(mags.get(current_id, 0)) >= int(current_def["mag"]):
		return false
	if ammo_reserve() <= 0:
		return false
	_reload_total = float(current_def["reload"])
	_reload_left = _reload_total
	_reload_stage = 0
	_auto_reload_timer = 0.0
	return true


func _cancel_reload() -> void:
	_reload_left = 0.0
	_auto_reload_timer = 0.0
	_reset_mag_node()


func _update_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		return
	_reload_left -= delta
	var r := reload_progress()
	# Three foley beats: magazine out, magazine in, charge.
	if _reload_stage == 0 and r >= 0.22:
		_reload_stage = 1
		ProcAudio.play_ui(self, "mag_out", -8.0)
	elif _reload_stage == 1 and r >= 0.58:
		_reload_stage = 2
		ProcAudio.play_ui(self, "mag_in", -7.0)
	elif _reload_stage == 2 and r >= 0.86:
		_reload_stage = 3
		ProcAudio.play_ui(self, "bolt", -8.0)
	if _reload_left <= 0.0:
		_reload_left = 0.0
		var ammo_type := str(current_def["ammo"])
		var need := int(current_def["mag"]) - int(mags[current_id])
		var take := mini(need, int(reserve.get(ammo_type, 0)))
		mags[current_id] = int(mags[current_id]) + take
		reserve[ammo_type] = int(reserve.get(ammo_type, 0)) - take
		_reset_mag_node()


func _reset_mag_node() -> void:
	if _model.has("mag") and _model["mag"] != null:
		(_model["mag"] as MeshInstance3D).position = _model["mag_rest"]
		(_model["root"] as Node3D).position = Vector3.ZERO


# ----------------------------------------------------------------------------
# Ordnance: throw / place / detonate
# ----------------------------------------------------------------------------

func _begin_action(kind: String, duration: float, release_at: float) -> void:
	_action_kind = kind
	_action_t = 0.0
	_action_dur = duration
	_action_release_at = release_at
	_action_released = false


func _start_throw() -> void:
	_begin_action("throw", THROW_TIME, THROW_RELEASE)
	ProcAudio.play_ui(self, "throw", -10.0)


func _start_place() -> void:
	if placed_c4_count() >= int(current_def["max_placed"]):
		message.emit("MAX CHARGES PLACED", Color(1.0, 0.6, 0.3))
		return
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var range_m := float(current_def["place_range"])
	var hit := _ray(origin, origin + fwd * range_m, WORLD_MASK)
	if hit.is_empty():
		# Nothing in reach: try the floor a short way ahead.
		var p := origin + fwd * minf(range_m, 2.0)
		hit = _ray(p, p + Vector3.DOWN * 3.0, WORLD_MASK)
	if hit.is_empty():
		message.emit("NOTHING TO ATTACH TO", Color(1.0, 0.6, 0.3))
		return
	_pending_c4_pos = hit["position"]
	_pending_c4_normal = hit["normal"]
	_begin_action("place", PLACE_TIME, PLACE_RELEASE)


func _start_detonate() -> void:
	_begin_action("detonate", DETONATE_TIME, DETONATE_RELEASE)
	ProcAudio.play_ui(self, "beep", -6.0, 1.4)


func _update_action(delta: float) -> void:
	if _action_kind == "":
		return
	_action_t += delta / _action_dur
	if not _action_released and _action_t >= _action_release_at:
		_action_released = true
		_release_action()
	if _action_t >= 1.0:
		_action_kind = ""
		# Out of grenades / C4 (and nothing left to detonate): go back to a gun.
		if not has_item(current_id):
			_switch_to_fallback()


func _release_action() -> void:
	match _action_kind:
		"throw": _release_throw()
		"place": _release_place()
		"detonate": _release_detonate()


func _release_throw() -> void:
	var d := current_def
	ordnance[current_id] = int(ordnance[current_id]) - 1
	var basis := camera.global_transform.basis
	var fwd := -basis.z
	var start := camera.global_position + fwd * 0.6 + basis.x * 0.18 - basis.y * 0.12
	# Don't spawn the grenade on the far side of a wall we're standing against.
	if not _ray(camera.global_position, start, WORLD_MASK).is_empty():
		start = camera.global_position + fwd * 0.12

	var g = GrenadeScript.new()
	g.weapon = self
	g.fuse = float(d["fuse"])
	g.radius = float(d["radius"])
	g.damage = float(d["damage"])
	get_tree().current_scene.add_child(g)
	g.global_position = start
	g.linear_velocity = fwd * float(d["throw_speed"]) + basis.y * 3.0 + player.velocity * 0.6
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))


func _release_place() -> void:
	var d := current_def
	ordnance["c4"] = int(ordnance["c4"]) - 1
	var charge = C4Script.new()
	charge.weapon = self
	charge.radius = float(d["radius"])
	charge.damage = float(d["damage"])
	get_tree().current_scene.add_child(charge)
	# Orient so the brick's up-axis is the surface normal.
	var up := _pending_c4_normal.normalized()
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	charge.global_transform = Transform3D(Basis(x, up, z).rotated(up, randf() * TAU), _pending_c4_pos)
	_placed_c4.append(charge)
	ProcAudio.play_ui(self, "mag_in", -6.0, 0.7)
	message.emit("C4 PLACED  (%d)" % placed_c4_count(), Color(1.0, 0.7, 0.3))


func _release_detonate() -> void:
	var charges := _placed_c4.duplicate()
	_placed_c4.clear()
	for c in charges:
		if is_instance_valid(c):
			(c as C4Charge).detonate()


# ----------------------------------------------------------------------------
# Pickups
# ----------------------------------------------------------------------------

## Applies (or with dry_run, just tests) a pickup. Returns true if it was/would be used.
func apply_pickup(kind: String, payload: Dictionary, dry_run := false) -> bool:
	match kind:
		"ammo":
			return _pickup_ammo(str(payload["ammo"]), int(payload["amount"]), dry_run)
		"medkit":
			if player.health >= player.max_health - 0.01:
				return false
			if not dry_run:
				var healed := player.heal(float(payload["heal"]))
				message.emit("+%d HEALTH" % int(round(healed)), Color(0.4, 1.0, 0.55))
			return true
		"weapon":
			var id := str(payload["weapon"])
			var d := WeaponDefs.get_def(id)
			if owned.has(id):               # duplicate weapon => it turns into ammo
				return _pickup_ammo(str(d["ammo"]), int(d["mag"]), dry_run)
			if not dry_run:
				owned[id] = true
				mags[id] = int(d["mag"])
				var t := str(d["ammo"])
				reserve[t] = mini(int(reserve.get(t, 0)) + int(d["mag"]) * 2, int(WeaponDefs.AMMO_MAX[t]))
				slot_last[int(d["slot"])] = id
				message.emit("%s ACQUIRED  [%s]" % [str(d["name"]).to_upper(),
						WeaponDefs.SLOT_LABELS[int(d["slot"])]], Color(0.5, 0.75, 1.0))
			return true
		"ordnance":
			var oid := str(payload["ordnance"])
			var cap := int(WeaponDefs.get_def(oid)["max_carry"])
			if int(ordnance.get(oid, 0)) >= cap:
				return false
			if not dry_run:
				ordnance[oid] = mini(int(ordnance.get(oid, 0)) + int(payload.get("amount", 1)), cap)
				message.emit("+%s  [4]" % str(WeaponDefs.get_def(oid)["name"]).to_upper(),
						Color(0.8, 0.95, 0.4))
			return true
	return false


func _pickup_ammo(ammo_type: String, amount: int, dry_run: bool) -> bool:
	var room := int(WeaponDefs.AMMO_MAX[ammo_type]) - int(reserve.get(ammo_type, 0))
	if room <= 0:
		return false
	if not dry_run:
		var add := mini(room, amount)
		reserve[ammo_type] = int(reserve.get(ammo_type, 0)) + add
		message.emit("+%d %s" % [add, WeaponDefs.AMMO_NAMES[ammo_type]], Color(1.0, 0.85, 0.3))
	return true


# ----------------------------------------------------------------------------
# Viewmodel
# ----------------------------------------------------------------------------

func _update_viewmodel(delta: float) -> void:
	var d := current_def
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	_bob_t += delta * (5.0 + hspeed * 0.8)
	var bob_amount := clampf(hspeed / 11.0, 0.0, 1.0) * (1.0 - ads_amount * 0.92)
	var bob := Vector3(sin(_bob_t) * 0.006, -absf(cos(_bob_t)) * 0.006, 0.0) * bob_amount

	var hip: Vector3 = d["hip_pos"]
	var ads_pos := Vector3(0.0, -float(_model["sight_y"]) * POSE_SCALE, float(d.get("ads_z", hip.z)))
	var pos := hip.lerp(ads_pos, ads_amount)
	var sprint_pose_weight := _sprint_t * (1.0 - _fire_override)
	pos += SPRINT_POS_OFFSET * sprint_pose_weight
	pos += bob
	pos.z += _kick * 0.035 * (1.0 - ads_amount * 0.55)

	# The sprint pose points the muzzle across the body. While firing we blend
	# it out quickly so the weapon points straight at the reticle aim point.
	var pose := SPRINT_POSE_DEG * sprint_pose_weight
	pose.z += sin(_bob_t * 0.5) * 1.1 * sprint_pose_weight

	# Weapon switch: dip the weapon out of view and bring the new one up.
	var sw := _switch_amount()
	pos.y -= 0.24 * sw
	pose.x -= 34.0 * sw

	_update_reload_pose()
	pos += _reload_pos
	pose += _reload_rot
	var action := _action_pose()
	pos += action["pos"]
	pose += action["rot"]

	_pivot.position = pos
	_pose.rotation_degrees = pose

	# Rotate the pivot so local -Z (the bore) points precisely at the projected
	# reticle point. Called after the pose so the visible muzzle is where the
	# projectile will actually spawn.
	_align_to_aim()

	# Hide the viewmodel behind the scope overlay when fully scoped.
	var scoped := is_scoped()
	_pivot.visible = not scoped
	_arms.visible = not scoped

	# Grenade / C4 models vanish once thrown until the next one is readied.
	var hide_held := _action_kind != "" and _action_released and _action_t < 0.72 \
			and _action_kind != "detonate"
	(_model["root"] as Node3D).visible = not hide_held

	_update_arms(_reload_hand)


## Computes the reload animation for this frame: the weapon dips and rolls
## toward the player, the magazine drops out and slides back in while the left
## hand follows it, then the weapon is charged and brought back up.
## Results are stored in _reload_pos/_reload_rot/_reload_hand (and the magazine node).
func _update_reload_pose() -> void:
	_reload_pos = Vector3.ZERO
	_reload_rot = Vector3.ZERO
	_reload_hand = Vector3.ZERO
	if not is_reloading():
		return
	var r := reload_progress()
	var dip := smoothstep(0.0, 0.18, r) * (1.0 - smoothstep(0.84, 1.0, r))
	_reload_pos = Vector3(-0.03, -0.07, 0.04) * dip
	_reload_rot = Vector3(-14.0, -8.0, 20.0) * dip

	# Magazine: out (0.2-0.4), held down, back in (0.5-0.72)
	var mag_drop := smoothstep(0.20, 0.40, r) * (1.0 - smoothstep(0.50, 0.72, r))
	var mag_node = _model.get("mag")
	if mag_node != null:
		(mag_node as MeshInstance3D).position = (_model["mag_rest"] as Vector3) + Vector3(0, -0.30, 0.02) * mag_drop

	# Left hand: goes to the magazine, rides it down and back up.
	var to_mag := smoothstep(0.12, 0.26, r) * (1.0 - smoothstep(0.74, 0.88, r))
	_reload_hand = Vector3(0.0, -0.12, 0.30) * to_mag + Vector3(0, -0.28, 0.0) * mag_drop

	# Charge: a short pull-and-release of the whole weapon at the end.
	var charge := sin(clampf((r - 0.84) / 0.16, 0.0, 1.0) * PI)
	(_model["root"] as Node3D).position = Vector3(0, 0, 0.03 * charge)


## Throw / place / detonate offsets (position, rotation degrees).
func _action_pose() -> Dictionary:
	var p := Vector3.ZERO
	var r := Vector3.ZERO
	if _action_kind == "throw":
		if _action_t < _action_release_at:
			var u := smoothstep(0.0, 1.0, _action_t / _action_release_at)       # wind up
			p = Vector3(0.05, 0.04, 0.14) * u
			r = Vector3(26.0, 8.0, 0.0) * u
		else:
			var u2 := (_action_t - _action_release_at) / (1.0 - _action_release_at)
			var swing := sin(clampf(u2 * 1.6, 0.0, 1.0) * PI * 0.5)
			var back := smoothstep(0.55, 1.0, u2)
			p = Vector3(0.05, 0.04, 0.14).lerp(Vector3(-0.02, -0.05, -0.24), swing) * (1.0 - back)
			r = Vector3(26.0, 8.0, 0.0).lerp(Vector3(-38.0, 0.0, 0.0), swing) * (1.0 - back)
	elif _action_kind == "place":
		var u3 := sin(clampf(_action_t, 0.0, 1.0) * PI)
		p = Vector3(0.0, -0.02, -0.20) * u3
		r = Vector3(-20.0, 0.0, 0.0) * u3
	elif _action_kind == "detonate":
		var u4 := sin(clampf(_action_t, 0.0, 1.0) * PI)
		p = Vector3(-0.04, 0.03, 0.05) * u4
		r = Vector3(10.0, 0.0, -10.0) * u4
	return {"pos": p, "rot": r}


func _align_to_aim() -> void:
	var target := get_aim_point()
	# Very close walls can place the hit point behind the viewmodel pivot; use
	# a safe forward fallback so look_at never flips the weapon around.
	if camera.global_position.distance_squared_to(target) < 1.0:
		target = camera.global_position - camera.global_transform.basis.z * 2.0
	var up := camera.global_transform.basis.y
	_pivot.look_at(target, up)


func _update_arms(left_hand_offset := Vector3.ZERO) -> void:
	if _pivot == null or _model.is_empty():
		return
	var grip_r := _arms.to_local((_model["grip_r"] as Marker3D).global_position)
	var left_world := (_model["grip_l"] as Marker3D).global_position \
			+ _pivot.global_transform.basis * left_hand_offset
	var grip_l := _arms.to_local(left_world)

	var shoulder_r := Vector3(0.30, -0.55, -0.18)
	var shoulder_l := Vector3(-0.18, -0.58, -0.50)
	var pole_r := shoulder_r + Vector3(0.55, -0.45, -0.05)
	var pole_l := shoulder_l + Vector3(-0.50, -0.50, 0.15)

	var r := _solve_two_bone(shoulder_r, grip_r, 0.27, 0.30, pole_r)
	var l := _solve_two_bone(shoulder_l, grip_l, 0.40, 0.43, pole_l)

	_place_bone(_upper_r, shoulder_r, r["elbow"])
	_place_bone(_fore_r, r["elbow"], r["hand"])
	_place_bone(_upper_l, shoulder_l, l["elbow"])
	_place_bone(_fore_l, l["elbow"], l["hand"])
	_place_hand(_hand_r, r["hand"])
	_place_hand(_hand_l, l["hand"])


## Analytic two-bone IK. Returns elbow/hand points in the arms-local space.
func _solve_two_bone(shoulder: Vector3, target: Vector3, l1: float, l2: float,
		pole: Vector3) -> Dictionary:
	var to := target - shoulder
	var dist := clampf(to.length(), 0.01, l1 + l2 - 0.001)
	var dir := to.normalized()
	var cos_angle := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)
	cos_angle = clampf(cos_angle, -1.0, 1.0)
	var angle := acos(cos_angle)

	var bend := pole - shoulder
	bend -= dir * bend.dot(dir)
	if bend.length_squared() < 0.0001:
		bend = Vector3.DOWN
	bend = bend.normalized()

	var elbow := shoulder + dir * (cos(angle) * l1) + bend * (sin(angle) * l1)
	var hand := shoulder + dir * dist
	return {"elbow": elbow, "hand": hand}


func _place_bone(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		return
	var y := d / length
	var ref := Vector3.UP
	if absf(y.dot(ref)) > 0.95:
		ref = Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	mi.scale = Vector3(1.0, length, 1.0)


func _place_hand(hand: MeshInstance3D, pos: Vector3) -> void:
	hand.position = pos
	hand.rotation = Vector3.ZERO


func _build_arms() -> void:
	_arms = Node3D.new()
	_arms.name = "ArmIK"
	add_child(_arms)

	_skin_mat = _mat(Color(0.52, 0.34, 0.25), 0.0, 0.76)
	_sleeve_mat = _mat(Color(0.11, 0.12, 0.14), 0.1, 0.8)

	_upper_r = _arm_mesh(0.045, _sleeve_mat)
	_fore_r = _arm_mesh(0.038, _skin_mat)
	_hand_r = _hand_mesh(0.045, _skin_mat)
	_upper_l = _arm_mesh(0.048, _sleeve_mat)
	_fore_l = _arm_mesh(0.040, _skin_mat)
	_hand_l = _hand_mesh(0.047, _skin_mat)


func _arm_mesh(radius: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.16
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arms.add_child(mi)
	return mi


func _hand_mesh(radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.2
	mesh.radial_segments = 8
	mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arms.add_child(mi)
	return mi


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m
