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


func get_keywords(category: Category) -> PackedStringArray:
	return productive if category == Category.PRODUCTIVE else distracting


# For the config UI: add one keyword to the productive or distracting list, and save. Blanks and
# case-insensitive duplicates are ignored (returns false).
func add_keyword(category: Category, keyword: String) -> bool:
	keyword = keyword.strip_edges()
	var list := get_keywords(category)
	if keyword.is_empty():
		return false
	for kw in list:
		if kw.nocasecmp_to(keyword) == 0:
			return false
	list.append(keyword)
	_set_keywords(category, list)
	return true


func remove_keyword(category: Category, keyword: String) -> void:
	var list := get_keywords(category)
	var i := list.find(keyword)
	if i == -1:
		return
	list.remove_at(i)
	_set_keywords(category, list)


func _set_keywords(category: Category, list: PackedStringArray) -> void:
	if category == Category.PRODUCTIVE:
		set_lists(list, distracting)
	else:
		set_lists(productive, list)


# Drop the user's custom lists and go back to the shipped defaults.
func reset_to_defaults() -> void:
	for path in [USER_PATH, USER_PATH + ".tmp"]:  # a leftover .tmp would be loaded in its place
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_load()
	lists_changed.emit()


func _load() -> void:
	var data := SaveManager.load_json(USER_PATH)
	if not data.has("productive") and not data.has("distracting"):
		data = SaveManager.load_json(DEFAULT_PATH)
	if data.is_empty():
		push_error("Classifier: could not load %s — everything will count as neutral" % DEFAULT_PATH)
	productive = _strings(data.get("productive"))
	distracting = _strings(data.get("distracting"))


# The strings in a loaded list; anything else (a hand-edited or damaged file) is skipped.
func _strings(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for item in value:
			if item is String:
				out.append(item)
	return out


func _matches(keywords: PackedStringArray, app: String, title: String) -> bool:
	for kw in keywords:
		if kw != "" and (app.containsn(kw) or title.containsn(kw)):
			return true
	return false
