extends Node
## Autoload: match recording, replay persistence and replay hand-off.
##
## The arena records lightweight snapshots at 20 Hz. At match end the finished
## dictionary is kept here so the post-match "Replay Match" button can open the
## viewer without writing a file, while "Save Replay" serializes it under
## user://replays/. The replay browser reads the same directory.

const REPLAY_DIR := "user://replays"
const FORMAT_VERSION := 1

var current_replay: Dictionary = {}
var pending_replay: Dictionary = {}
var selected_replay_path := ""

var _recording := false
var _frames: Array = []
var _started_ms := 0
var _start_date := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)


func start_recording() -> void:
	_recording = true
	_frames.clear()
	_started_ms = Time.get_ticks_msec()
	_start_date = Time.get_datetime_string_from_system(false, true)
	current_replay = {}


func is_recording() -> bool:
	return _recording


func record_frame(t: float, player: Dictionary, enemies: Array) -> void:
	if not _recording:
		return
	_frames.append({"t": t, "player": player, "enemies": enemies})


func finish_recording(outcome: String) -> Dictionary:
	if not _recording and not current_replay.is_empty():
		return current_replay
	_recording = false
	var duration := 0.0
	if not _frames.is_empty():
		duration = float(_frames[_frames.size() - 1].get("t", 0.0))
	current_replay = {
		"version": FORMAT_VERSION,
		"date": _start_date,
		"outcome": outcome,
		"duration": duration,
		"frames": _frames,
	}
	return current_replay


func has_current_replay() -> bool:
	return not current_replay.is_empty()


func set_pending_replay(data: Dictionary) -> void:
	pending_replay = data.duplicate(true)


func get_pending_replay() -> Dictionary:
	return pending_replay


## Returns the parsed replay and marks it as the replay the viewer should open.
func load_replay_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("ReplayManager: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_warning("ReplayManager: invalid replay JSON %s" % path)
		return {}
	pending_replay = parsed
	selected_replay_path = path
	return pending_replay


func load_pending_from_file(path: String) -> bool:
	return not load_replay_file(path).is_empty()


func save_current_replay() -> String:
	if current_replay.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace(":", "-").replace(" ", "_").replace("T", "_")
	var outcome := str(current_replay.get("outcome", "match"))
	var path := "%s/match_%s_%s.json" % [REPLAY_DIR, outcome, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ReplayManager: cannot write %s" % path)
		return ""
	f.store_string(JSON.stringify(current_replay, "\t"))
	f.close()
	return path


func get_replay_directory() -> String:
	return REPLAY_DIR


## Lightweight browser entries sorted newest-first. Full JSON is parsed so the
## list can show outcome and duration; matches are short enough for this.
func list_saved_replays() -> Array:
	var entries: Array = []
	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return entries
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var path := "%s/%s" % [REPLAY_DIR, file]
		var item := {
			"file": file,
			"path": path,
			"outcome": "match",
			"duration": 0.0,
			"date": "",
		}
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				item["outcome"] = str(parsed.get("outcome", "match"))
				item["duration"] = float(parsed.get("duration", 0.0))
				item["date"] = str(parsed.get("date", ""))
		entries.append(item)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["file"]) > str(b["file"]))
	return entries


func format_duration(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%02d:%02d" % [int(total / 60.0), total % 60]
