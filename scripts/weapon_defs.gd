class_name WeaponDefs
extends RefCounted
## Data for every weapon. Tune the game here; weapon.gd just reads these.
##
## Slots (CS 1.6 style):
##   slot 1  [key 1]  sidearms / light weapons   (pistol, smg)
##   slot 2  [key 3]  primary / heavy weapons    (rifle, sniper)
##   slot 3  [key 4]  ordnance / utility         (frag grenade, C4)
## Pressing a slot key again cycles through the owned weapons in that slot.
##
## Gun keys
##   rate           shots per second            auto   hold-to-fire vs click-per-shot
##   mag            magazine size               ammo   ammo pool it draws from
##   *_spread       cone half-angle in degrees  bloom_* extra spread per consecutive shot
##   kick_px/jitter hip-fire reticle recoil     ads_pitch/yaw  ADS camera recoil
##   zoom           ADS field-of-view divisor   scope  true = full-screen scope overlay
##   hip_pos        viewmodel offset at the hip ads_z  viewmodel depth while aiming
##   sound_pitch/db placeholder gunshot tuning  drop_weight  loot-table weight

const SLOT_KEYS := {1: "slot_1", 2: "slot_2", 3: "slot_3"}
const SLOT_LABELS := {1: "1", 2: "3", 3: "4"}        # key shown in the HUD

const AMMO_MAX := {"light": 180, "rifle": 150, "sniper": 25}
const AMMO_NAMES := {"light": "LIGHT AMMO", "rifle": "RIFLE AMMO", "sniper": "SNIPER AMMO"}
const START_RESERVE := {"light": 48, "rifle": 90, "sniper": 0}
const START_OWNED := ["pistol", "rifle"]
const START_ORDNANCE := {"frag": 2, "c4": 0}
const START_WEAPON := "rifle"

const DEFS := {
	"pistol": {
		"name": "Pistol", "slot": 1, "kind": "gun", "ammo": "light",
		"mag": 12, "auto": false, "rate": 6.0, "damage": 24.0, "speed": 150.0,
		"hip_spread": 0.8, "ads_spread": 0.08, "bloom_per_shot": 1.0, "max_bloom": 2.5,
		"bloom_recovery": 6.0, "move_spread": 1.2, "air_spread": 2.0, "sprint_spread": 1.8,
		"kick_px": 22.0, "jitter_px": 8.0, "ads_pitch": 0.016, "ads_yaw": 0.003,
		"zoom": 1.8, "reload": 1.3, "scope": false,
		"hip_pos": Vector3(0.17, -0.20, -0.46), "ads_z": -0.52,
		"sound_pitch": 1.28, "sound_db": -7.0, "drop_weight": 0,
	},
	"smg": {
		"name": "SMG", "slot": 1, "kind": "gun", "ammo": "light",
		"mag": 30, "auto": true, "rate": 14.0, "damage": 10.0, "speed": 140.0,
		"hip_spread": 0.9, "ads_spread": 0.15, "bloom_per_shot": 0.55, "max_bloom": 3.0,
		"bloom_recovery": 5.0, "move_spread": 1.5, "air_spread": 2.4, "sprint_spread": 2.2,
		"kick_px": 20.0, "jitter_px": 10.0, "ads_pitch": 0.012, "ads_yaw": 0.005,
		"zoom": 2.2, "reload": 1.9, "scope": false,
		"hip_pos": Vector3(0.20, -0.22, -0.52), "ads_z": -0.58,
		"sound_pitch": 1.15, "sound_db": -6.0, "drop_weight": 3,
	},
	"rifle": {
		"name": "Rifle", "slot": 2, "kind": "gun", "ammo": "rifle",
		"mag": 30, "auto": true, "rate": 10.5, "damage": 16.0, "speed": 165.0,
		"hip_spread": 0.45, "ads_spread": 0.05, "bloom_per_shot": 0.86, "max_bloom": 2.8,
		"bloom_recovery": 5.0, "move_spread": 1.35, "air_spread": 2.2, "sprint_spread": 2.1,
		"kick_px": 32.0, "jitter_px": 12.6, "ads_pitch": 0.0205, "ads_yaw": 0.004,
		"zoom": 3.5, "reload": 2.1, "scope": false,
		"hip_pos": Vector3(0.22, -0.24, -0.56), "ads_z": -0.68,
		"sound_pitch": 1.0, "sound_db": -5.0, "drop_weight": 0,
	},
	"sniper": {
		"name": "Sniper", "slot": 2, "kind": "gun", "ammo": "sniper",
		"mag": 5, "auto": false, "rate": 0.85, "damage": 110.0, "speed": 330.0,
		"hip_spread": 3.5, "ads_spread": 0.01, "bloom_per_shot": 3.0, "max_bloom": 3.0,
		"bloom_recovery": 3.0, "move_spread": 4.0, "air_spread": 5.0, "sprint_spread": 5.0,
		"kick_px": 50.0, "jitter_px": 8.0, "ads_pitch": 0.05, "ads_yaw": 0.006,
		"zoom": 6.0, "reload": 2.9, "scope": true,
		"hip_pos": Vector3(0.22, -0.25, -0.60), "ads_z": -0.62,
		"sound_pitch": 0.72, "sound_db": -2.0, "drop_weight": 2,
	},
	"frag": {
		"name": "Frag Grenade", "slot": 3, "kind": "grenade", "max_carry": 4,
		"fuse": 2.5, "radius": 7.5, "damage": 140.0, "throw_speed": 17.0,
		"hip_pos": Vector3(0.20, -0.20, -0.40),
	},
	"c4": {
		"name": "C4", "slot": 3, "kind": "c4", "max_carry": 3, "max_placed": 3,
		"radius": 9.0, "damage": 240.0, "place_range": 4.0,
		"hip_pos": Vector3(0.20, -0.20, -0.40),
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func is_gun(id: String) -> bool:
	return str(DEFS.get(id, {}).get("kind", "")) == "gun"


## Weapon ids in a slot, in definition order.
static func ids_in_slot(slot: int) -> Array:
	var out: Array = []
	for id in DEFS:
		if int(DEFS[id]["slot"]) == slot:
			out.append(id)
	return out


## Weapons that can show up as loot (drop_weight > 0).
static func droppable_weapons() -> Array:
	var out: Array = []
	for id in DEFS:
		if int(DEFS[id].get("drop_weight", 0)) > 0:
			out.append(id)
	return out
