# pet.gd - attach to the root Node2D ("Pet") with children Sprite2D and Label.
# The whole OS window is the pet: dragging, throwing, gravity and clinging to the screen
# edges all move the window itself. Collisions use the sprite's rect against the usable
# (taskbar-excluded) rect of the monitor it's on.
extends Node2D

enum Pose { HELD, AIRBORNE, GROUNDED, CLING_LEFT, CLING_RIGHT, CLING_TOP }

signal pose_changed(pose: Pose)  # hook for the future climbing animations

const GRAVITY := 2400.0  # px/s²
const MAX_THROW_SPEED := 3000.0  # px/s
const GROUND_FRICTION := 6.0  # exponential slide decay per second
const BOUNCE := 0.25  # fraction of vertical speed kept on a floor bounce
const MIN_BOUNCE_SPEED := 300.0  # slower landings just stop
const THROW_SAMPLE_TIME := 0.08  # s of drag history used to estimate the throw

const StatusScene := preload("res://ui/status.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label

var pose := Pose.AIRBORNE

var _pos := Vector2.ZERO  # window position, kept as floats between ticks
var _vel := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _samples: Array = []  # [time_sec, mouse_pos] while held
var _app := ""
var _status: Window  # created on first double-click, then reused


func _ready() -> void:
	get_viewport().transparent_bg = true  # belt and braces with project settings
	# PetBrain connected to Tracker first (autoloads are ready before this scene), so its
	# category is already up to date when _on_active_app_changed runs.
	Tracker.active_app_changed.connect(_on_active_app_changed)
	PetBrain.mood_changed.connect(_on_mood_changed)
	_refresh_label()

	_pos = Vector2(get_window().position)  # start airborne: drop onto the taskbar

	# Optional click-through: only the area inside this polygon receives clicks;
	# everything else passes to the desktop. Enable once dragging works.
	# var r := Rect2(sprite.global_position - sprite.get_rect().size / 2, sprite.get_rect().size)
	# DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
	# 	r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)
	# ]))


func _input(event: InputEvent) -> void:
	# Pick up with the left mouse button; releasing throws with the recent drag velocity.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click:
			_open_status()  # the pair's first click already did a normal pick-up and drop
		elif event.pressed:
			_drag_offset = _mouse() - Vector2(get_window().position)
			_samples.clear()
			_vel = Vector2.ZERO
			_set_pose(Pose.HELD)
		elif pose == Pose.HELD:
			_vel = _throw_velocity()
			_set_pose(Pose.AIRBORNE)

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _physics_process(delta: float) -> void:
	match pose:
		Pose.HELD:
			var mouse := _mouse()
			_pos = mouse - _drag_offset
			var now := Time.get_ticks_usec() / 1e6
			_samples.append([now, mouse])
			while _samples.size() > 2 and now - _samples[0][0] > THROW_SAMPLE_TIME:
				_samples.pop_front()
		Pose.AIRBORNE:
			_vel.y += GRAVITY * delta
			_pos += _vel * delta
			_collide()
		Pose.GROUNDED:
			if _vel.x != 0.0:
				_vel.x *= exp(-GROUND_FRICTION * delta)
				if absf(_vel.x) < 5.0:
					_vel.x = 0.0
				_pos.x += _vel.x * delta
				_clamp_to_side_walls()
		_:
			pass  # clinging: stay put until picked up
	get_window().position = Vector2i(_pos.round())


func _open_status() -> void:
	if _status == null:
		_status = StatusScene.instantiate()
		add_child(_status)
	_status.open_centered(get_window().current_screen)


func _mouse() -> Vector2:
	return Vector2(DisplayServer.mouse_get_position())


func _throw_velocity() -> Vector2:
	if _samples.size() < 2:
		return Vector2.ZERO
	var first: Array = _samples[0]
	var last: Array = _samples[-1]
	var dt: float = last[0] - first[0]
	if dt <= 0.0:
		return Vector2.ZERO
	return ((last[1] - first[1]) / dt).limit_length(MAX_THROW_SPEED)


# Sprite rect in window pixels (window size may differ from the viewport size on hi-DPI).
func _body_rect() -> Rect2:
	var r := sprite.get_rect()
	var local := Rect2(sprite.position + r.position * sprite.scale, r.size * sprite.scale)
	var ratio := Vector2(get_window().size) / get_viewport().get_visible_rect().size
	return Rect2(local.position * ratio, local.size * ratio)


# Usable rect (taskbar excluded) of the monitor under the body's centre.
func _screen_bounds(body: Rect2) -> Rect2:
	var centre := body.get_center()
	var screen := get_window().current_screen
	for i in DisplayServer.get_screen_count():
		if Rect2(Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))).has_point(centre):
			screen = i
			break
	return Rect2(DisplayServer.screen_get_usable_rect(screen))


func _collide() -> void:
	var local := _body_rect()
	var body := Rect2(_pos + local.position, local.size)
	var bounds := _screen_bounds(body)

	# Walls first, so a throw into a lower corner clings rather than lands.
	if body.position.x < bounds.position.x:
		_pos.x += bounds.position.x - body.position.x
		_cling(Pose.CLING_LEFT)
	elif body.end.x > bounds.end.x:
		_pos.x -= body.end.x - bounds.end.x
		_cling(Pose.CLING_RIGHT)
	elif body.position.y < bounds.position.y:
		_pos.y += bounds.position.y - body.position.y
		_cling(Pose.CLING_TOP)
	elif body.end.y > bounds.end.y:
		_pos.y -= body.end.y - bounds.end.y
		if _vel.y > MIN_BOUNCE_SPEED:
			_vel.y *= -BOUNCE
		else:
			_vel.y = 0.0
			_set_pose(Pose.GROUNDED)


func _clamp_to_side_walls() -> void:
	var local := _body_rect()
	var body := Rect2(_pos + local.position, local.size)
	var bounds := _screen_bounds(body)
	if body.position.x < bounds.position.x:
		_pos.x += bounds.position.x - body.position.x
		_vel.x = 0.0
	elif body.end.x > bounds.end.x:
		_pos.x -= body.end.x - bounds.end.x
		_vel.x = 0.0


func _cling(to: Pose) -> void:
	_vel = Vector2.ZERO
	_set_pose(to)


func _set_pose(p: Pose) -> void:
	if p == pose:
		return
	pose = p
	# Placeholder until the climbing art exists: rotate the sprite toward the surface it holds.
	match p:
		Pose.CLING_LEFT:
			sprite.rotation_degrees = 90.0
		Pose.CLING_RIGHT:
			sprite.rotation_degrees = -90.0
		Pose.CLING_TOP:
			sprite.rotation_degrees = 180.0
		_:
			sprite.rotation_degrees = 0.0
	pose_changed.emit(p)


func _on_active_app_changed(app: String, _title: String) -> void:
	_app = app
	_refresh_label()


func _on_mood_changed(_mood: float, _state: String) -> void:
	_refresh_label()


func _refresh_label() -> void:
	label.text = "%s (%d)\n%s · %s" % [
		PetBrain.get_state(), int(PetBrain.mood),
		"(nothing)" if _app == "" else _app, Classifier.category_name(PetBrain.category),
	]
