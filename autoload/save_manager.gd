# save_manager.gd - autoload singleton ("SaveManager"). JSON file IO for everything persisted
# under user:// (on Windows: %APPDATA%\Godot\app_userdata\PandaProd\).
#   save.json            - pet state (mood, name, sleeping), written by PetBrain
#   classification.json  - the user's custom app lists, written by Classifier (absent = defaults)
#   achievements.json    - unlocked achievements, written by Achievements
extends Node

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1


# Missing or corrupt file -> {}. A missing file with a .tmp beside it was cut off mid-save (see
# save_json()), so the .tmp, the newer copy, is read instead.
func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".tmp"):
			return _read(path + ".tmp")
		return {}
	return _read(path)


func _read(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("SaveManager: %s is corrupt, ignoring it" % path)
		return {}
	return data


# Writes to a temp file and renames it over the target, so a crash mid-write can't corrupt it.
# On Windows the rename deletes the target first; a crash in that gap is what load_json()'s .tmp
# fallback covers.
func save_json(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("SaveManager: could not replace %s (error %d)" % [path, err])
		return false
	return true
