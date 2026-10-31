class_name PauseMenu
extends CanvasLayer
## Esc pause menu: Resume / Restart Game / Return to Main Menu / Quit Game.
##
## Pausing uses SceneTree.paused, so gameplay (player, enemies, projectiles,
## timers, audio) freezes while this layer keeps running (PROCESS_MODE_ALWAYS).
## Set `enabled = false` (the arena does this when the match ends) to stop Esc
## from opening it over the result screen.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var enabled := true

var _root: Control
var _first_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_ensure_pause_action()
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open():
		resume()
	else:
		pause()


func pause() -> void:
	if not enabled or is_open():
		return
	get_tree().paused = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first_button.grab_focus()


func resume() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_restart() -> void:
	# Unpause first: a paused tree would never finish swapping the scene.
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_quit() -> void:
	get_tree().quit()


func _ensure_pause_action() -> void:
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", ev)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.015, 0.02, 0.03, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	box.add_child(spacer)

	_first_button = _add_button(box, "Resume", resume)
	_add_button(box, "Restart Game", _on_restart)
	_add_button(box, "Return to Main Menu", _on_main_menu)
	_add_button(box, "Quit Game", _on_quit)

	var hint := Label.new()
	hint.text = "Esc: resume"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 50)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b
