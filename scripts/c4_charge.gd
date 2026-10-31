class_name C4Charge
extends Node3D
## A planted C4 brick. It sits where it was placed, blinks, and detonates when
## the player triggers it (right mouse button while holding C4).

var weapon: Weapon
var radius := 9.0
var damage := 240.0

var _t := 0.0
var _led_mat: StandardMaterial3D
var _light: OmniLight3D
var _beep_phase := -1


func _ready() -> void:
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.28, 0.30, 0.20)
	olive.roughness = 0.7
	var block := BoxMesh.new()
	block.size = Vector3(0.15, 0.045, 0.095)
	block.material = olive
	var mi := MeshInstance3D.new()
	mi.mesh = block
	mi.position.y = 0.0225
	add_child(mi)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	var pack := BoxMesh.new()
	pack.size = Vector3(0.06, 0.02, 0.045)
	pack.material = dark
	var pack_mi := MeshInstance3D.new()
	pack_mi.mesh = pack
	pack_mi.position = Vector3(0.035, 0.055, 0)
	add_child(pack_mi)

	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(1.0, 0.1, 0.05)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1.0, 0.1, 0.05)
	_led_mat.emission_energy_multiplier = 0.2
	var led := BoxMesh.new()
	led.size = Vector3(0.022, 0.008, 0.012)
	led.material = _led_mat
	var led_mi := MeshInstance3D.new()
	led_mi.mesh = led
	led_mi.position = Vector3(-0.045, 0.049, 0)
	add_child(led_mi)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.1, 0.05)
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	_light.position.y = 0.12
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	var phase := int(_t / 0.6)
	var on := fmod(_t, 0.6) < 0.12
	_led_mat.emission_energy_multiplier = 4.0 if on else 0.2
	_light.light_energy = 1.2 if on else 0.0
	if phase != _beep_phase:
		_beep_phase = phase
		ProcAudio.play_at(get_tree().current_scene, "beep", global_position, -14.0, 0.9, 25.0)


func detonate() -> void:
	var w := weapon if is_instance_valid(weapon) else null
	Explosion.blast(self, global_position + Vector3.UP * 0.1, radius, damage, w)
	queue_free()
