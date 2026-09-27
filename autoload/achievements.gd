# achievements.gd - autoload singleton ("Achievements"). The checklist shown on the status window's
# achievements page (ui/achievements.tscn). pet.gd calls unlock() the moment each thing happens on
# screen; unlocks are saved straight away to user://achievements.json, kept apart from save.json
# and classification.json so resetting one never wipes another.
extends Node

signal unlocked(id: StringName)

const PATH := "user://achievements.json"
const VERSION := 1

# In display order.
const LIST := [
	{
		"id": &"summit",
		"name": "Around the World",
		"description": "Did you know Pandas love climbing?",
	},
	{
		"id": &"gamer",
		"name": "Touch Grass",
		"description": "Catch your panda stuck in losers queue, take a break from League panda!",
	},
	{
		"id": &"bamboo",
		"name": "Bamboo Brunch",
		"description": "Catch your panda munching bamboo. Everything tastes better when you're productive!",
	},
	{
		"id": &"pats",
		"name": "Belly Rub",
		"description": "I mean Pandas are just bigger, fluffier dogs right?",
	},
]

var _unlocked: Array[StringName] = []


func _ready() -> void:
	for id in SaveManager.load_json(PATH).get("unlocked", []):
		if not StringName(id) in _unlocked:
			_unlocked.append(StringName(id))


func is_unlocked(id: StringName) -> bool:
	return id in _unlocked


func unlock(id: StringName) -> void:
	if id in _unlocked:
		return
	_unlocked.append(id)
	SaveManager.save_json(PATH, {"version": VERSION, "unlocked": _unlocked})
	unlocked.emit(id)
