extends Control
## Main menu: scene transitions live here so every entry works even though the
## buttons are wired in the .tscn.

@onready var _play_button: Button = $Center/VBox/Play


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var volume := float(cfg.get_value("audio", "master_volume", 0.85))
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	_play_button.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_replays_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/replay_browser.tscn")


func _on_options_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/options.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
