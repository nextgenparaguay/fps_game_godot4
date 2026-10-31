class_name CoverManager
extends Node
## Knows where cover is and answers the enemy AI's questions about it.
##
## Cover spots come from arena_level.gd (`cover_points`). A spot is a place on
## the floor next to a solid object; `normal` points away from the object, so a
## spot protects you from threats on the *opposite* side of the object.
##
## Nothing here is trusted blindly: whether a spot actually hides you from the
## player right now is checked with a real ray-cast (is_hidden), and whether it
## can be walked to is checked against the navmesh. That keeps the AI correct
## even if the level changes.
##
##   find_cover()  best hidden, reachable, unclaimed spot for an enemy
##   is_hidden()   does this spot still protect from the threat? (cover compromised?)
##   find_peek()   where to stand to shoot from this spot (or null)
##   claim/release one enemy per spot, so they spread out instead of stacking

class CoverPoint:
	var pos := Vector3.ZERO
	var normal := Vector3.FORWARD
	var height := 2.0
	var low := false                  # low cover: enemy crouches behind it and stands to shoot
	var claimed_by := 0               # instance id of the enemy using it (0 = free)

	func hide_height() -> float:
		return CROUCH_HEAD if low else STAND_HEAD


const LOW_COVER_HEIGHT := 1.55        # below this an enemy hides crouched
const STAND_HEAD := 1.65
const CROUCH_HEAD := 0.95
const MIN_PLAYER_DISTANCE := 6.0      # never pick cover right on top of the player
const MAX_VALIDATE := 10              # ray-cast at most this many of the best candidates
const PEEK_OFFSETS := [1.2, 1.9, 2.7, 3.5]
const WORLD_MASK := 1

var points: Array[CoverPoint] = []


func _ready() -> void:
	add_to_group("cover_manager")


func setup(data: Array) -> void:
	points.clear()
	for d: Dictionary in data:
		var c := CoverPoint.new()
		c.pos = d["pos"]
		c.normal = (d["normal"] as Vector3).normalized()
		c.height = float(d["height"])
		c.low = c.height < LOW_COVER_HEIGHT
		points.append(c)


## Best cover for `enemy` against a threat at `threat_eye`.
## Prefers spots inside [range_min, range_max] of the threat and close to the
## enemy. An enemy that is too far away prefers spots *nearer the threat than
## itself*, so groups advance cover-to-cover instead of walking in the open.
func find_cover(enemy: Node3D, threat_eye: Vector3, range_min: float, range_max: float,
		avoid: CoverPoint = null) -> CoverPoint:
	var me := enemy.global_position
	var me_id := enemy.get_instance_id()
	var my_dist := Vector2(me.x - threat_eye.x, me.z - threat_eye.z).length()

	var scored: Array = []
	for c in points:
		if c.claimed_by != 0 and c.claimed_by != me_id:
			continue
		if avoid != null and c.pos.distance_to(avoid.pos) < 3.0:
			continue
		var to_t := Vector3(threat_eye.x - c.pos.x, 0.0, threat_eye.z - c.pos.z)
		var d := to_t.length()
		if d < MIN_PLAYER_DISTANCE:
			continue
		var dir := to_t / d
		if c.normal.dot(dir) > -0.15:      # the exposed side faces the player: useless
			continue
		var penalty := 0.0
		if d < range_min:
			penalty = range_min - d
		elif d > range_max:
			penalty = d - range_max
		var advance := 0.0
		if my_dist > range_max and d > my_dist - 2.0:
			advance = d - (my_dist - 2.0)
		var directness := (1.0 + c.normal.dot(dir)) * 2.0        # square-on to the player is best
		var score := penalty * 2.0 + me.distance_to(c.pos) * 0.35 + advance + directness + randf() * 2.0
		scored.append([score, c])

	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var tries := 0
	for entry: Array in scored:
		tries += 1
		if tries > MAX_VALIDATE:
			break
		var c: CoverPoint = entry[1]
		if is_hidden(c, threat_eye) and _reachable(me, c.pos):
			return c
	return null


## True if the spot still hides someone from `threat_eye`.
func is_hidden(c: CoverPoint, threat_eye: Vector3) -> bool:
	var target := c.pos + Vector3.UP * c.hide_height()
	var hit := _space().intersect_ray(PhysicsRayQueryParameters3D.create(threat_eye, target, WORLD_MASK))
	return not hit.is_empty() and (hit["position"] as Vector3).distance_to(target) > 0.15


## Where to stand to shoot at the threat from this cover. Low cover: stand up in
## place. Tall cover: the nearest sidestep with a clear line of sight. Returns
## a Vector3, or null if no firing position exists.
func find_peek(c: CoverPoint, threat_eye: Vector3) -> Variant:
	if c.low:
		return c.pos if _clear(c.pos + Vector3.UP * STAND_HEAD, threat_eye) else null
	var tangent := c.normal.cross(Vector3.UP).normalized()
	for off: float in PEEK_OFFSETS:
		var options: Array[Vector3] = []
		for sgn in [1.0, -1.0]:
			var p := c.pos + tangent * float(sgn) * off
			if _on_nav(p) and _clear(p + Vector3.UP * 1.55, threat_eye):
				options.append(p)
		if not options.is_empty():
			return options.pick_random()
	return null


func claim(c: CoverPoint, enemy: Node) -> void:
	c.claimed_by = enemy.get_instance_id()


func release(c: CoverPoint, enemy: Node) -> void:
	if c != null and c.claimed_by == enemy.get_instance_id():
		c.claimed_by = 0


# ----------------------------------------------------------------------------

func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state


func _clear(from: Vector3, to: Vector3) -> bool:
	return _space().intersect_ray(PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)).is_empty()


func _nav_map() -> RID:
	return get_viewport().world_3d.navigation_map


func _on_nav(p: Vector3) -> bool:
	var snapped_pos := NavigationServer3D.map_get_closest_point(_nav_map(), p)
	return Vector2(snapped_pos.x - p.x, snapped_pos.z - p.z).length() < 0.6


func _reachable(from: Vector3, to: Vector3) -> bool:
	if not _on_nav(to):
		return false
	var path := NavigationServer3D.map_get_path(_nav_map(), from, to, true)
	return path.size() > 0 and Vector2(path[path.size() - 1].x - to.x, path[path.size() - 1].z - to.z).length() < 1.2
