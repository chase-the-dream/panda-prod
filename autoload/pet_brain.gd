# pet_brain.gd - autoload singleton ("PetBrain"). Tracks the pet's 1–100 mood, which drifts
# based on the Classifier category of the focused app: up when productive, down slowly when
# neutral, down fast when distracted. While sleeping (the user is away) the mood is frozen.
extends Node

signal mood_changed(mood: float, state: String)
signal name_changed(pet_name: String)
signal sleep_changed(sleeping: bool)

# Mood points per minute.
const PRODUCTIVE_RATE := 3.0
const NEUTRAL_RATE := -1.0
const DISTRACTING_RATE := -4.0
const RATE_SCALE := 1.0  # debug speed-up; e.g. 30 to see state changes within seconds
const AUTOSAVE_INTERVAL := 30.0  # s; also saved on exit

const MOOD_MIN := 1.0
const MOOD_MAX := 100.0
# [upper bound (inclusive), name], ascending. Add rows here for more states.
const STATES := [[33, "Chud"], [66, "Content"], [100, "Chad"]]

const DEFAULT_NAME := "Click Me!"
const NAME_MAX_LENGTH := 12  # fits the status window's 51 px name tag at font size 8

var mood := 50.0
var pet_name := DEFAULT_NAME  # not "name", which would shadow Node.name
var category := Classifier.Category.NEUTRAL
var sleeping := false

var _last_int := -1
var _last_state := ""


func _ready() -> void:
	# Resume exactly where the last run left off; time spent closed doesn't count.
	# Values of the wrong type (a hand-edited or damaged file) are ignored, not fatal.
	var data := SaveManager.load_json(SaveManager.SAVE_PATH)
	var saved_mood = data.get("mood")
	if saved_mood is float or saved_mood is int:
		mood = clampf(float(saved_mood), MOOD_MIN, MOOD_MAX)
	var saved_name = data.get("name")
	if saved_name is String:
		pet_name = _clean_name(saved_name, DEFAULT_NAME)
	var saved_sleeping = data.get("sleeping")
	if saved_sleeping is bool:
		sleeping = saved_sleeping

	Tracker.active_app_changed.connect(_on_active_app_changed)
	Classifier.lists_changed.connect(_reclassify)

	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(save)
	add_child(timer)


func _exit_tree() -> void:
	if not Tracker.another_instance:  # a second copy quitting mustn't overwrite the running one's save
		save()


func save() -> void:
	SaveManager.save_json(SaveManager.SAVE_PATH, {
		"version": SaveManager.SAVE_VERSION,
		"mood": mood,
		"name": pet_name,
		"sleeping": sleeping,
	})


# Blank names are ignored. Saves right away so a rename isn't lost before the next autosave.
func set_pet_name(new_name: String) -> void:
	var cleaned := _clean_name(new_name, pet_name)
	if cleaned == pet_name:
		return
	pet_name = cleaned
	name_changed.emit(pet_name)
	save()


# Sleep mode: the user is away, so mood neither rises nor falls until they wake the pet.
func set_sleeping(value: bool) -> void:
	if value == sleeping:
		return
	sleeping = value
	sleep_changed.emit(sleeping)
	save()


func _clean_name(raw: String, fallback: String) -> String:
	# One line: the name tag has room for one.
	var cleaned := raw.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(NAME_MAX_LENGTH)
	return cleaned if not cleaned.is_empty() else fallback


func get_state() -> String:
	for entry in STATES:
		if int(mood) <= entry[0]:  # by the displayed value, so "Chud (33)" never reads "Content"
			return entry[1]
	return STATES[-1][1]


func _on_active_app_changed(app: String, title: String) -> void:
	category = Classifier.classify(app, title)
	print("[PetBrain] %s" % Classifier.category_name(category))


# The lists changed under the current app, so re-check it without waiting for a focus change.
func _reclassify() -> void:
	_on_active_app_changed(Tracker.current_app, Tracker.current_title)


func _process(delta: float) -> void:
	if sleeping:
		return
	var rate: float
	match category:
		Classifier.Category.PRODUCTIVE:
			rate = PRODUCTIVE_RATE
		Classifier.Category.DISTRACTING:
			rate = DISTRACTING_RATE
		_:
			rate = NEUTRAL_RATE
	mood = clampf(mood + rate / 60.0 * RATE_SCALE * delta, MOOD_MIN, MOOD_MAX)
	_notify_mood()


# One-off boosts (or hits) on top of the drift, e.g. petting.
func change_mood(amount: float) -> void:
	mood = clampf(mood + amount, MOOD_MIN, MOOD_MAX)
	_notify_mood()


# Only notify when the displayed value or state changes, not every frame.
func _notify_mood() -> void:
	var state := get_state()
	if int(mood) != _last_int or state != _last_state:
		_last_int = int(mood)
		_last_state = state
		mood_changed.emit(mood, state)
