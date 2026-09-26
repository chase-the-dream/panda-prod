# classifier.gd - autoload singleton ("Classifier"). Sorts the focused app into a category.
# Keywords ({"productive": [...], "distracting": [...]}) come from the user's custom lists in
# user://classification.json if present, else the shipped defaults in data/classification.json.
# They match as case-insensitive substrings of the process name or window title. No match = neutral.
extends Node

signal lists_changed

enum Category { NEUTRAL, PRODUCTIVE, DISTRACTING }

const DEFAULT_PATH := "res://data/classification.json"
const USER_PATH := "user://classification.json"
const LISTS_VERSION := 1

var productive: PackedStringArray = []
var distracting: PackedStringArray = []


func _ready() -> void:
	_load()


func classify(app: String, title: String) -> Category:
	# Distracting wins on overlap, e.g. "LeetCode walkthrough - YouTube".
	if _matches(distracting, app, title):
		return Category.DISTRACTING
	if _matches(productive, app, title):
		return Category.PRODUCTIVE
	return Category.NEUTRAL


static func category_name(category: Category) -> String:
	return Category.find_key(category).to_lower()


# For the settings UI: replace the lists and save them as the user's custom lists.
func set_lists(new_productive: PackedStringArray, new_distracting: PackedStringArray) -> void:
	productive = new_productive
	distracting = new_distracting
	SaveManager.save_json(USER_PATH, {
		"version": LISTS_VERSION, "productive": productive, "distracting": distracting,
	})
	lists_changed.emit()


# Drop the user's custom lists and go back to the shipped defaults.
func reset_to_defaults() -> void:
	if FileAccess.file_exists(USER_PATH):
		DirAccess.remove_absolute(USER_PATH)
	_load()
	lists_changed.emit()


func _load() -> void:
	var data := SaveManager.load_json(USER_PATH)
	if not data.has("productive") and not data.has("distracting"):
		data = SaveManager.load_json(DEFAULT_PATH)
	if data.is_empty():
		push_error("Classifier: could not load %s — everything will count as neutral" % DEFAULT_PATH)
	productive = PackedStringArray(data.get("productive", []))
	distracting = PackedStringArray(data.get("distracting", []))


func _matches(keywords: PackedStringArray, app: String, title: String) -> bool:
	for kw in keywords:
		if kw != "" and (app.containsn(kw) or title.containsn(kw)):
			return true
	return false
