extends Control
## Minimal functional options screen. Settings are stored in user://settings.cfg
## and consumed by Player (sensitivity) and the audio bus (master volume).

const SETTINGS_PATH := "user://settings.cfg"

var _sens: HSlider
var _volume: HSlider


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_settings()


func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.size = vp
	bg.color = Color(0.055, 0.07, 0.09)
	add_child(bg)

	var center := CenterContainer.new()
	center.size = vp
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sens_label := Label.new()
	sens_label.text = "Mouse sensitivity"
	box.add_child(sens_label)
	_sens = HSlider.new()
	_sens.min_value = 0.5
	_sens.max_value = 3.0
	_sens.step = 0.05
	_sens.value = 1.0
	_sens.custom_minimum_size = Vector2(0, 28)
	box.add_child(_sens)

	var vol_label := Label.new()
	vol_label.text = "Master volume"
	box.add_child(vol_label)
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01
	_volume.value = 0.85
	_volume.custom_minimum_size = Vector2(0, 28)
	box.add_child(_volume)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)

	var save := Button.new()
	save.text = "Save & Back"
	save.custom_minimum_size = Vector2(0, 48)
	save.pressed.connect(_save_and_back)
	box.add_child(save)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_back)
	box.add_child(back)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_sens.value = float(cfg.get_value("input", "sensitivity_multiplier", 1.0))
	_volume.value = float(cfg.get_value("audio", "master_volume", 0.85))


func _save_and_back() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "sensitivity_multiplier", _sens.value)
	cfg.set_value("audio", "master_volume", _volume.value)
	cfg.save(SETTINGS_PATH)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_volume.value, 0.0001)))
	_back()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
