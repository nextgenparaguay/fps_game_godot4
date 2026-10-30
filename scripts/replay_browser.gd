extends Control
## Browse saved replay JSON files from user://replays/ and open one in the
## replay viewer.

var _list: VBoxContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_populate()


func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.size = vp
	bg.color = Color(0.045, 0.06, 0.08)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.size = vp
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_bottom", 38)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "REPLAYS"
	title.add_theme_font_size_override("font_size", 42)
	box.add_child(title)

	var path_label := Label.new()
	path_label.text = "Saved matches: %s" % ReplayManager.get_replay_directory()
	path_label.add_theme_font_size_override("font_size", 14)
	path_label.add_theme_color_override("font_color", Color(0.56, 0.65, 0.73))
	box.add_child(path_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	box.add_child(spacer)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.custom_minimum_size = Vector2(0, 44)
	refresh.pressed.connect(_populate)
	box.add_child(refresh)

	var back := Button.new()
	back.text = "Back to Main Menu"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_back)
	box.add_child(back)


func _populate() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var entries := ReplayManager.list_saved_replays()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No saved replays yet.\nFinish a match and press Save Replay."
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.62, 0.68, 0.72))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
		return

	for entry in entries:
		var button := Button.new()
		var outcome := str(entry["outcome"]).to_upper()
		var duration := ReplayManager.format_duration(float(entry["duration"]))
		button.text = "%s    %s    %s" % [outcome, duration, str(entry["date"])]
		button.custom_minimum_size = Vector2(0, 52)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_open_replay.bind(str(entry["path"])))
		_list.add_child(button)


func _open_replay(path: String) -> void:
	if ReplayManager.load_pending_from_file(path):
		get_tree().change_scene_to_file("res://scenes/replay_viewer.tscn")


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
