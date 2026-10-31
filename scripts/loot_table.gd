class_name LootTable
extends RefCounted
## Randomized enemy drops.
##
## Each kill has a DROP_CHANCE of dropping something, with a small chance of a
## bonus second item. What drops is weighted by what the player needs:
##   - low on ammo      -> ammo is much more likely
##   - hurt             -> medkits are much more likely (and rare at full health)
##   - weapons not yet owned are favoured; once you own them all they turn into ammo
## All numbers are constants below so the economy is easy to tune.

const DROP_CHANCE := 0.8
const BONUS_DROP_CHANCE := 0.12
const MEDKIT_HEAL := 40.0

const BASE_WEIGHTS := {"ammo": 40.0, "medkit": 22.0, "weapon": 14.0, "frag": 14.0, "c4": 8.0}


## Returns a list of drop descriptions: {kind, payload, label, tint}.
static func roll(player: Player) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	if randf() > DROP_CHANCE:
		return drops
	drops.append(_pick(player))
	if randf() < BONUS_DROP_CHANCE:
		drops.append(_pick(player))
	return drops


static func weights_for(player: Player) -> Dictionary:
	var w := BASE_WEIGHTS.duplicate()
	var hp_frac := player.health / maxf(player.max_health, 1.0)
	if hp_frac < 0.5:
		w["medkit"] *= 2.5
	elif hp_frac >= 0.999:
		w["medkit"] *= 0.2
	if player.weapon.is_low_on_ammo():
		w["ammo"] *= 2.2
	if _unowned_weapons(player).is_empty():
		w["weapon"] = 3.0
	return w


static func _pick(player: Player) -> Dictionary:
	var w := weights_for(player)
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := randf() * total
	var kind := "ammo"
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			kind = k
			break

	match kind:
		"medkit":
			return {"kind": "medkit", "payload": {"heal": MEDKIT_HEAL},
					"label": "MEDKIT  +%d" % int(MEDKIT_HEAL), "tint": Color(0.3, 1.0, 0.45)}
		"weapon":
			var pool := _unowned_weapons(player)
			if pool.is_empty():
				return _ammo_drop(player)
			var id: String = pool.pick_random()
			return {"kind": "weapon", "payload": {"weapon": id},
					"label": str(WeaponDefs.get_def(id)["name"]).to_upper(), "tint": Color(0.35, 0.65, 1.0)}
		"frag":
			return {"kind": "ordnance", "payload": {"ordnance": "frag", "amount": 1},
					"label": "FRAG GRENADE", "tint": Color(0.7, 0.9, 0.35)}
		"c4":
			return {"kind": "ordnance", "payload": {"ordnance": "c4", "amount": 1},
					"label": "C4", "tint": Color(1.0, 0.45, 0.25)}
	return _ammo_drop(player)


## Ammo for a gun the player owns, weighted toward the pool that is running lowest.
static func _ammo_drop(player: Player) -> Dictionary:
	var weapon := player.weapon
	var types: Array = []
	for id in weapon.owned:
		if WeaponDefs.is_gun(id):
			var t := str(WeaponDefs.get_def(id)["ammo"])
			if not types.has(t):
				types.append(t)
	if types.is_empty():
		types = ["rifle"]
	var best_weight := -1.0
	var chosen: String = types[0]
	for t in types:
		var have := float(weapon.reserve.get(t, 0))
		var weight := randf() * (1.0 + 1.0 / (1.0 + have / 20.0))   # emptier pool => higher weight
		if weight > best_weight:
			best_weight = weight
			chosen = t
	var amount := 24
	for id in weapon.owned:
		if WeaponDefs.is_gun(id) and str(WeaponDefs.get_def(id)["ammo"]) == chosen:
			amount = int(WeaponDefs.get_def(id)["mag"])
			break
	return {"kind": "ammo", "payload": {"ammo": chosen, "amount": amount},
			"label": "%s  +%d" % [WeaponDefs.AMMO_NAMES[chosen], amount], "tint": Color(1.0, 0.82, 0.25)}


static func _unowned_weapons(player: Player) -> Array:
	var out: Array = []
	for id in WeaponDefs.droppable_weapons():
		if not player.weapon.owned.has(id):
			out.append(id)
	return out


## Spawns the rolled drops on the floor near `pos`.
static func spawn_drops(root: Node, pos: Vector3, player: Player) -> Array[Pickup]:
	var spawned: Array[Pickup] = []
	if player == null or root == null:
		return spawned
	var drops := roll(player)
	var space := (root as Node3D).get_world_3d().direct_space_state
	for i in drops.size():
		var d: Dictionary = drops[i]
		var p := Pickup.new()
		p.kind = d["kind"]
		p.payload = d["payload"]
		p.label_text = d["label"]
		p.tint = d["tint"]
		root.add_child(p)
		var spot := pos + Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7)) * float(i)
		# Snap down to the floor so drops never float where an enemy died mid-air.
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 6.0, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			spot = hit["position"]
		p.global_position = spot
		spawned.append(p)
	return spawned
