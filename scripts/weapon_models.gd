class_name WeaponModels
extends RefCounted
## Placeholder first-person models built from primitives.
##
## Every builder returns a Dictionary with:
##   root     Node3D parent of the whole model (shown/hidden on equip)
##   muzzle   Marker3D where projectiles leave the barrel
##   flash    Node3D muzzle flash (hidden until a shot)
##   grip_r   Marker3D the right hand IK target
##   grip_l   Marker3D the left hand IK target
##   mag      MeshInstance3D magazine that is animated while reloading (or null)
##   mag_rest Vector3 the magazine's resting local position
##   sight_y  float   height of the sight line (used to centre it on screen in ADS)
## Bores point down local -Z. Swap these for real meshes later; as long as the
## same markers exist nothing else needs to change.


static func build(id: String, parent: Node3D) -> Dictionary:
	match id:
		"pistol": return _build_pistol(parent)
		"smg": return _build_smg(parent)
		"sniper": return _build_sniper(parent)
		"frag": return _build_frag(parent)
		"c4": return _build_c4(parent)
	return _build_rifle(parent)


# ----------------------------------------------------------------------------
# Guns
# ----------------------------------------------------------------------------

static func _build_rifle(parent: Node3D) -> Dictionary:
	var root := _root("Rifle", parent)
	var dark := _mat(Color(0.10, 0.105, 0.12), 0.7, 0.35)
	var grey := _mat(Color(0.26, 0.27, 0.30), 0.55, 0.5)
	var accent := _mat(Color(0.92, 0.42, 0.08), 0.25, 0.55)
	var steel := _mat(Color(0.17, 0.18, 0.20), 0.85, 0.28)

	_box(root, Vector3(0.072, 0.105, 0.48), Vector3(0, 0, 0), dark)                     # receiver
	_box(root, Vector3(0.064, 0.062, 0.36), Vector3(0, 0.010, -0.42), grey)             # handguard
	_cyl(root, 0.012, 0.36, Vector3(0, 0.012, -0.77), steel)                            # barrel
	_cyl(root, 0.022, 0.085, Vector3(0, 0.012, -0.96), dark)                            # muzzle brake
	_box(root, Vector3(0.048, 0.020, 0.20), Vector3(0, 0.064, -0.44), dark)              # top rail
	_box(root, Vector3(0.012, 0.032, 0.012), Vector3(0, 0.085, -0.62), steel)            # front sight post
	_box(root, Vector3(0.008, 0.014, 0.012), Vector3(-0.022, 0.083, -0.06), dark)        # rear sight left
	_box(root, Vector3(0.008, 0.014, 0.012), Vector3(0.022, 0.083, -0.06), dark)         # rear sight right
	_box(root, Vector3(0.05, 0.12, 0.24), Vector3(0, -0.032, 0.34), grey, Vector3(-6, 0, 0))     # stock
	_box(root, Vector3(0.042, 0.13, 0.055), Vector3(0, -0.105, 0.13), accent, Vector3(15, 0, 0)) # grip
	var mag := _box(root, Vector3(0.034, 0.15, 0.055), Vector3(0, -0.125, -0.12), grey, Vector3(8, 0, 0))
	_box(root, Vector3(0.05, 0.024, 0.16), Vector3(0, 0.012, -0.64), accent)             # handguard accent
	_glow_dot(root, Vector3(0, 0.085, -0.628))

	return _finish(root, Vector3(0, 0.012, -1.01), Vector3(0, 0.012, -1.02),
			Vector3(0, -0.10, 0.13), Vector3(0, -0.035, -0.38), mag, 0.085)


static func _build_pistol(parent: Node3D) -> Dictionary:
	var root := _root("Pistol", parent)
	var dark := _mat(Color(0.10, 0.105, 0.12), 0.7, 0.35)
	var grey := _mat(Color(0.30, 0.31, 0.34), 0.6, 0.45)
	var accent := _mat(Color(0.92, 0.42, 0.08), 0.25, 0.55)

	_box(root, Vector3(0.040, 0.070, 0.16), Vector3(0, 0, 0.02), grey)                   # frame
	_box(root, Vector3(0.042, 0.045, 0.23), Vector3(0, 0.047, -0.02), dark)              # slide
	_cyl(root, 0.010, 0.05, Vector3(0, 0.047, -0.155), dark)                             # barrel tip
	_box(root, Vector3(0.038, 0.11, 0.052), Vector3(0, -0.085, 0.075), grey, Vector3(12, 0, 0))  # grip
	_box(root, Vector3(0.030, 0.012, 0.06), Vector3(0, -0.040, -0.04), dark)             # trigger guard
	_box(root, Vector3(0.008, 0.016, 0.008), Vector3(0, 0.0845, -0.125), dark)           # front sight
	_box(root, Vector3(0.008, 0.016, 0.010), Vector3(-0.013, 0.0845, 0.085), dark)       # rear sight L
	_box(root, Vector3(0.008, 0.016, 0.010), Vector3(0.013, 0.0845, 0.085), dark)        # rear sight R
	var mag := _box(root, Vector3(0.030, 0.07, 0.044), Vector3(0, -0.150, 0.082), accent, Vector3(12, 0, 0))
	_glow_dot(root, Vector3(0, 0.0845, -0.125))

	return _finish(root, Vector3(0, 0.047, -0.18), Vector3(0, 0.047, -0.19),
			Vector3(0, -0.08, 0.075), Vector3(-0.03, -0.115, 0.065), mag, 0.0845)


static func _build_smg(parent: Node3D) -> Dictionary:
	var root := _root("SMG", parent)
	var dark := _mat(Color(0.10, 0.105, 0.12), 0.7, 0.35)
	var grey := _mat(Color(0.26, 0.27, 0.30), 0.55, 0.5)
	var accent := _mat(Color(0.92, 0.42, 0.08), 0.25, 0.55)
	var steel := _mat(Color(0.17, 0.18, 0.20), 0.85, 0.28)

	_box(root, Vector3(0.052, 0.090, 0.34), Vector3(0, 0, 0), dark)                      # body
	_box(root, Vector3(0.046, 0.052, 0.18), Vector3(0, 0.010, -0.26), grey)              # shroud
	_cyl(root, 0.011, 0.14, Vector3(0, 0.012, -0.43), steel)                             # barrel
	_cyl(root, 0.020, 0.15, Vector3(0, 0.012, -0.52), dark)                              # suppressor
	_box(root, Vector3(0.030, 0.09, 0.036), Vector3(0, -0.075, -0.23), accent, Vector3(-8, 0, 0)) # foregrip
	_box(root, Vector3(0.040, 0.11, 0.050), Vector3(0, -0.095, 0.10), grey, Vector3(15, 0, 0))    # grip
	_box(root, Vector3(0.030, 0.050, 0.20), Vector3(0, -0.012, 0.28), grey)              # stock
	_box(root, Vector3(0.010, 0.030, 0.010), Vector3(0, 0.0725, -0.34), steel)           # front sight
	_box(root, Vector3(0.026, 0.020, 0.014), Vector3(0, 0.0625, 0.10), dark)             # rear sight
	var mag := _box(root, Vector3(0.030, 0.17, 0.046), Vector3(0, -0.125, 0.0), grey, Vector3(-4, 0, 0))
	_glow_dot(root, Vector3(0, 0.0725, -0.34))

	return _finish(root, Vector3(0, 0.012, -0.60), Vector3(0, 0.012, -0.61),
			Vector3(0, -0.095, 0.10), Vector3(0, -0.075, -0.23), mag, 0.0725)


static func _build_sniper(parent: Node3D) -> Dictionary:
	var root := _root("Sniper", parent)
	var dark := _mat(Color(0.10, 0.105, 0.12), 0.7, 0.35)
	var grey := _mat(Color(0.24, 0.25, 0.27), 0.55, 0.5)
	var steel := _mat(Color(0.17, 0.18, 0.20), 0.85, 0.28)
	var accent := _mat(Color(0.92, 0.42, 0.08), 0.25, 0.55)
	var glass := _mat(Color(0.2, 0.45, 0.9), 0.9, 0.05)

	_box(root, Vector3(0.065, 0.10, 0.50), Vector3(0, 0, 0), dark)                       # receiver
	_cyl(root, 0.014, 0.74, Vector3(0, 0.015, -0.62), steel)                             # barrel
	_cyl(root, 0.022, 0.09, Vector3(0, 0.015, -1.02), dark)                              # muzzle brake
	_box(root, Vector3(0.055, 0.13, 0.30), Vector3(0, -0.03, 0.38), grey, Vector3(-5, 0, 0)) # stock
	_box(root, Vector3(0.040, 0.12, 0.055), Vector3(0, -0.105, 0.17), grey, Vector3(15, 0, 0)) # grip
	var mag := _box(root, Vector3(0.032, 0.085, 0.06), Vector3(0, -0.085, -0.05), accent)
	_cyl(root, 0.030, 0.32, Vector3(0, 0.098, -0.05), dark)                              # scope tube
	_cyl(root, 0.038, 0.05, Vector3(0, 0.098, -0.22), dark)                              # objective bell
	_cyl(root, 0.030, 0.04, Vector3(0, 0.098, -0.2), glass)                              # lens
	_box(root, Vector3(0.024, 0.04, 0.03), Vector3(0, 0.065, -0.14), steel)              # front mount
	_box(root, Vector3(0.024, 0.04, 0.03), Vector3(0, 0.065, 0.04), steel)               # rear mount
	_cyl(root, 0.010, 0.06, Vector3(0.055, 0.03, 0.07), steel)                           # bolt handle
	_box(root, Vector3(0.012, 0.012, 0.05), Vector3(0.082, 0.03, 0.07), steel)
	_box(root, Vector3(0.010, 0.09, 0.010), Vector3(-0.035, -0.07, -0.55), steel, Vector3(0, 0, 15)) # bipod L
	_box(root, Vector3(0.010, 0.09, 0.010), Vector3(0.035, -0.07, -0.55), steel, Vector3(0, 0, -15)) # bipod R

	return _finish(root, Vector3(0, 0.015, -1.08), Vector3(0, 0.015, -1.09),
			Vector3(0, -0.10, 0.17), Vector3(0, -0.03, -0.40), mag, 0.098)


# ----------------------------------------------------------------------------
# Ordnance
# ----------------------------------------------------------------------------

static func _build_frag(parent: Node3D) -> Dictionary:
	var root := _root("Frag", parent)
	var olive := _mat(Color(0.22, 0.30, 0.16), 0.3, 0.6)
	var steel := _mat(Color(0.55, 0.56, 0.6), 0.9, 0.3)

	var body := SphereMesh.new()
	body.radius = 0.042
	body.height = 0.084
	body.material = olive
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_cyl(root, 0.014, 0.03, Vector3(0, 0.048, 0), steel).rotation_degrees = Vector3.ZERO     # fuse cap
	_box(root, Vector3(0.012, 0.075, 0.022), Vector3(0.040, 0.012, 0), steel)                # safety lever
	var ring := TorusMesh.new()
	ring.inner_radius = 0.010
	ring.outer_radius = 0.016
	ring.material = steel
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.position = Vector3(0.05, 0.06, 0)
	ring_mi.rotation_degrees = Vector3(0, 0, 90)
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring_mi)

	return _finish(root, Vector3(0, 0, 0), Vector3(0, 0, 0),
			Vector3(0, -0.02, 0.0), Vector3(-0.08, -0.05, 0.03), null, 0.0)


static func _build_c4(parent: Node3D) -> Dictionary:
	var root := _root("C4", parent)
	var olive := _mat(Color(0.28, 0.30, 0.20), 0.2, 0.7)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.5, 0.4)

	_box(root, Vector3(0.15, 0.045, 0.095), Vector3.ZERO, olive)                             # block
	_box(root, Vector3(0.06, 0.02, 0.045), Vector3(0.035, 0.032, 0), dark)                   # detonator pack
	var led := _mat(Color(1.0, 0.1, 0.05), 0.0, 0.3)
	led.emission_enabled = true
	led.emission = Color(1.0, 0.1, 0.05)
	led.emission_energy_multiplier = 2.5
	_box(root, Vector3(0.022, 0.006, 0.012), Vector3(-0.045, 0.026, 0), led)                 # red display
	_cyl(root, 0.004, 0.08, Vector3(0.0, 0.03, 0.04), dark).rotation_degrees = Vector3(0, 0, 90)  # wire

	return _finish(root, Vector3.ZERO, Vector3.ZERO,
			Vector3(0, -0.01, 0.0), Vector3(-0.10, -0.04, 0.05), null, 0.0)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

static func _root(node_name: String, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	return root


static func _finish(root: Node3D, muzzle_pos: Vector3, flash_pos: Vector3, grip_r_pos: Vector3,
		grip_l_pos: Vector3, mag: MeshInstance3D, sight_y: float) -> Dictionary:
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = muzzle_pos
	root.add_child(muzzle)

	var grip_r := Marker3D.new()
	grip_r.name = "GripRight"
	grip_r.position = grip_r_pos
	root.add_child(grip_r)

	var grip_l := Marker3D.new()
	grip_l.name = "GripLeft"
	grip_l.position = grip_l_pos
	root.add_child(grip_l)

	return {
		"root": root, "muzzle": muzzle, "flash": _make_flash(root, flash_pos),
		"grip_r": grip_r, "grip_l": grip_l, "mag": mag,
		"mag_rest": mag.position if mag else Vector3.ZERO, "sight_y": sight_y,
	}


static func _glow_dot(parent: Node3D, pos: Vector3) -> void:
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.008
	dot_mesh.height = 0.016
	var dot_mat := _mat(Color(1.0, 0.55, 0.12), 0.0, 0.4)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1.0, 0.35, 0.04)
	dot_mat.emission_energy_multiplier = 3.0
	dot_mesh.material = dot_mat
	var dot := MeshInstance3D.new()
	dot.mesh = dot_mesh
	dot.position = pos
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(dot)


static func _make_flash(parent: Node3D, pos: Vector3) -> Node3D:
	var f := Node3D.new()
	f.name = "MuzzleFlash"
	f.position = pos
	f.visible = false
	parent.add_child(f)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.78, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.12)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.22)
	light.light_energy = 2.0
	light.omni_range = 4.0
	light.shadow_enabled = false
	f.add_child(light)
	return f


static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, radius: float, length: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
