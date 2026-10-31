class_name AimAssist
extends RefCounted
## Lightweight magnetic aim assist. Picks the enemy closest to the view centre
## (a plain screen-space distance check over the few enemies in the "enemy" group)
## and returns how far, in pixels, the reticle should be pulled toward it.
##
## The pull is measured from the *view centre* only, never from the reticle's
## current position, so it cannot react to the reticle's recoil or aim-lag offsets:
## the reticle simply sits at  centre + recoil + lag + assist.  The assist fades out
## toward the edge of its radius, so a target entering or leaving range never pops.
## The only physics call is one world-only line-of-sight ray, for the chosen target.
##
## Lead aiming: the reticle is pulled toward where the enemy will be when the bullet
## arrives, by plain linear extrapolation:  future = pos + velocity * lead_time,
## with lead_time = distance / bullet_speed.  Target selection and the fade weight
## still use the enemy's *current* screen position, so which enemy is chosen (and how
## strongly) never flickers with its velocity; only the point pulled toward leads.

const MAX_RANGE := 80.0         ## m: enemies further than this are ignored
const RADIUS_FRAC := 0.2        ## capture radius as a fraction of the viewport height
const CHEST := Vector3(0.0, 1.1, 0.0)
const WORLD_MASK := 1
const MAX_LEAD_TIME := 1.0      ## s: cap so very slow bullets don't lead absurdly far


## Screen-space pull (px) toward the best enemy, or ZERO if there is none.
## `strength` 0..1 is the fraction of the centre-to-enemy distance to pull.
## `lead_factor` scales how far ahead of a moving enemy to aim (0 = aim at it where
## it is now, 1 = full lead); `bullet_speed` is the equipped gun's projectile speed.
static func pull(cam: Camera3D, strength: float, lead_factor := 0.0,
		bullet_speed := 0.0) -> Vector2:
	if strength <= 0.0:
		return Vector2.ZERO
	var vp := cam.get_viewport().get_visible_rect().size
	var centre := vp * 0.5
	var radius := vp.y * RADIUS_FRAC
	var best_dist := radius
	var best_screen := Vector2.ZERO
	var best_world := Vector3.ZERO
	var best_enemy: Enemy
	var found := false
	for n in cam.get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e == null or e.health <= 0.0:
			continue
		var p := e.global_position + CHEST
		if cam.is_position_behind(p) or p.distance_to(cam.global_position) > MAX_RANGE:
			continue
		var s := cam.unproject_position(p)
		var d := s.distance_to(centre)
		if d < best_dist:
			best_dist = d
			best_screen = s
			best_world = p
			best_enemy = e
			found = true
	if not found:
		return Vector2.ZERO
	# No pulling toward enemies behind walls (one ray, chosen target only).
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, best_world, WORLD_MASK)
	if not cam.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return Vector2.ZERO
	var weight := 1.0 - smoothstep(radius * 0.6, radius, best_dist)

	# Linear lead: where will the enemy be when the bullet arrives?
	var aim_screen := best_screen
	if lead_factor > 0.0 and bullet_speed > 0.0:
		var flat := Vector3(best_enemy.velocity.x, 0.0, best_enemy.velocity.z)
		var lead_time := minf(best_world.distance_to(cam.global_position) / bullet_speed, MAX_LEAD_TIME)
		var future := best_world + flat * lead_time * lead_factor
		if not cam.is_position_behind(future):
			aim_screen = cam.unproject_position(future)
	return (aim_screen - centre) * strength * weight
