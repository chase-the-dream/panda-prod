# pet.gd - attach to the root Node2D ("Pet") with children Sprite2D (panda_sprite.gd) and Label.
# The whole OS window is the pet: dragging, throwing, gravity and clinging to the screen
# edges all move the window itself. Collisions use the sprite's rect against the usable
# (taskbar-excluded) rect of the monitor it's on. On the floor, a small activity AI has the
# panda idle, sit, walk and, in a good mood, eat; held and clinging it just shows the idle frame. Once it's really
# falling it shows the fall frame, and landing like that plays a one-shot flop, blink and
# get-up before the AI takes over again. Sleep mode (PetBrain.sleeping) overrides all of it with
# the sleep animation and freezes the AI; it's independent of the pose, so a sleeping pet can
# still be carried and thrown.
extends Node2D

enum Pose { HELD, AIRBORNE, GROUNDED, CLING_LEFT, CLING_RIGHT }
enum Activity { IDLE, SIT, WALK, EAT }

signal pose_changed(pose: Pose)  # hook for the future climbing animations

const GRAVITY := 2400.0  # px/s²
const MAX_THROW_SPEED := 3000.0  # px/s
const GROUND_FRICTION := 6.0  # exponential slide decay per second
const BOUNCE := 0.5  # fraction of vertical speed kept on a floor bounce
# px/s of impact; softer impacts thud down and stop. Plain drops from most heights don't bounce,
# and the weakest bounce is still a big ~170 px hop. Its rebound usually lands dead, but the
# hardest throws on a tall screen can get a smaller second bounce.
const MIN_BOUNCE_SPEED := 1800.0
# Too fast to catch a wall: it hits it and keeps falling down it instead of clinging. Falling
# counts from a lower speed (px/s downward, ~300 px of free fall) than a throw at any angle
# (px/s total), so only hard throws miss.
const WALL_GRAB_MAX_FALL_SPEED := 1200.0
const WALL_GRAB_MAX_SPEED := 2200.0
const WALL_BOUNCE := 0.4  # fraction of sideways speed kept rebounding off a wall it missed
const THROW_SAMPLE_TIME := 0.08  # s of drag history used to estimate the throw
const THROW_FACE_MIN := 60.0  # px/s of sideways throw needed to turn the panda that way

# Activity AI. Durations are [min, max] seconds; a meal is two passes of the eat animation
# (~12.7 s). Averaged out, a Content or Chad panda spends roughly 30% of its floor time idle, 26%
# walking, 22% sitting and 22% eating. A Chud one doesn't eat (a nudge to be productive) and sits instead:
# about 30% idle, 26% walking, 44% sitting.
const IDLE_TIME := Vector2(2.0, 5.0)
const SIT_TIME := Vector2(8.0, 18.0)
const WALK_TIME := Vector2(4.0, 8.0)
const SETTLE_TIME := Vector2(1.0, 3.0)  # first idle after landing, being put down or waking
const WALK_CHANCE := 0.5  # when an idle ends; the rest of the time it may sit...
const SIT_CHANCE := 0.2
const EAT_CHANCE := 0.2  # ...or eat (only in EAT_MOODS; otherwise it sits instead)...
# ...and otherwise idles again, turning around.
const EAT_MOODS := ["Content", "Chad"]  # PetBrain.get_state() names it's allowed to eat in
const WALK_SPEED := 55.0  # px/s
const MIN_WALK_ROOM := 150.0  # px; less room than this ahead and it walks the other way

const StatusScene := preload("res://ui/status.tscn")

@onready var sprite: PandaSprite = $Sprite2D
@onready var label: Label = $Label

var pose := Pose.AIRBORNE
var activity := Activity.IDLE

var _pos := Vector2.ZERO  # window position, kept as floats between ticks
var _vel := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _samples: Array = []  # [time_sec, mouse_pos] while held
var _app := ""
var _status: Window  # created on first double-click, then reused
var _activity_left := 0.0  # s until the AI picks the next activity
var _walk_dir := 1.0
var _falling := false  # showing the fall frame; latched until the pose changes (so through bounces)
var _recovering := false  # the landing animation is playing; the AI waits for it


func _ready() -> void:
	get_viewport().transparent_bg = true  # belt and braces with project settings
	# PetBrain connected to Tracker first (autoloads are ready before this scene), so its
	# category is already up to date when _on_active_app_changed runs.
	Tracker.active_app_changed.connect(_on_active_app_changed)
	PetBrain.mood_changed.connect(_on_mood_changed)
	PetBrain.sleep_changed.connect(_on_sleep_changed)
	sprite.finished.connect(_on_sprite_finished)
	_update_anim()
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
			if absf(_vel.x) > THROW_FACE_MIN:
				sprite.facing_right = _vel.x > 0.0
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
			# After the collision, so the pick-up-and-drop of a plain click (landed on this same
			# first tick) never shows the fall frame or plays the landing.
			if pose == Pose.AIRBORNE and not _falling and not PetBrain.sleeping:
				_falling = true
				_update_anim()
				# The fall frame is much wider than idle; widening beside a wall must push it
				# off the wall, not count as a hit. Keeping the speed lets a flick into the
				# wall still cling next tick.
				_clamp_to_side_walls(false)
		Pose.GROUNDED:
			if _vel.x != 0.0:
				_vel.x *= exp(-GROUND_FRICTION * delta)
				if absf(_vel.x) < 5.0:
					_vel.x = 0.0
				_pos.x += _vel.x * delta
			elif not PetBrain.sleeping and not _recovering:
				_run_activity(delta)
			# Every tick, not just while moving: frames differ in width (sleep is much wider),
			# so switching animation next to a wall could otherwise leave the body inside it.
			_clamp_to_side_walls()
		_:
			pass  # clinging: stay put until picked up
	get_window().position = Vector2i(_pos.round())


# The floor AI: count down the current activity, walk if walking, then pick what's next.
func _run_activity(delta: float) -> void:
	if activity == Activity.WALK:
		_pos.x += _walk_dir * WALK_SPEED * delta
		var before := _pos.x
		_clamp_to_side_walls()
		if _pos.x != before:  # pushed back: hit a wall or monitor edge
			_start_activity(Activity.IDLE, IDLE_TIME)
			return
	_activity_left -= delta
	if _activity_left > 0.0:
		return
	if activity != Activity.IDLE:
		_start_activity(Activity.IDLE, IDLE_TIME)
		return
	var eat := EAT_CHANCE if _can_eat() else 0.0
	var sit := SIT_CHANCE + EAT_CHANCE - eat  # no eating: that share goes to sitting
	var roll := randf()
	if roll < WALK_CHANCE:
		_start_walk()
	elif roll < WALK_CHANCE + sit:
		_start_activity(Activity.SIT, SIT_TIME)
	elif roll < WALK_CHANCE + sit + eat:
		_start_eat()
	else:
		sprite.facing_right = not sprite.facing_right  # look the other way for a bit
		_start_activity(Activity.IDLE, IDLE_TIME)


func _start_activity(a: Activity, duration: Vector2) -> void:
	activity = a
	_activity_left = randf_range(duration.x, duration.y)
	_update_anim()


# Random direction, unless that side is nearly at a wall; face the way it walks.
func _start_walk() -> void:
	var local := _body_rect()
	var body := Rect2(_pos + local.position, local.size)
	var bounds := _screen_bounds(body)
	_walk_dir = -1.0 if randf() < 0.5 else 1.0
	var room := bounds.end.x - body.end.x if _walk_dir > 0.0 else body.position.x - bounds.position.x
	if room < MIN_WALK_ROOM:
		_walk_dir = -_walk_dir
	sprite.facing_right = _walk_dir > 0.0
	_start_activity(Activity.WALK, WALK_TIME)


# A meal is two passes of the eat animation; it ends when the sprite reports it finished, not on
# the timer, so it never cuts off mid-chew or wraps back to the first frame.
func _start_eat() -> void:
	activity = Activity.EAT
	_activity_left = INF
	_update_anim()


func _can_eat() -> bool:
	return PetBrain.get_state() in EAT_MOODS


# Sleep beats everything, then falling and landing; on the floor the activity picks the
# animation; otherwise idle.
func _update_anim() -> void:
	if PetBrain.sleeping:
		sprite.play(&"sleep")
	elif pose == Pose.AIRBORNE and _falling:
		sprite.play(&"fall")
	elif pose == Pose.GROUNDED and _recovering:
		sprite.play(&"land")
	elif pose != Pose.GROUNDED:
		sprite.play(&"idle")
	else:
		match activity:
			Activity.SIT:
				sprite.play(&"sit")
			Activity.WALK:
				sprite.play(&"walk")
			Activity.EAT:
				sprite.play(&"eat")
			_:
				sprite.play(&"idle")


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


# Usable rect (taskbar excluded) of the monitor under the body's centre. Off every monitor (flown
# over the top, or dragged out), the nearest one, so it always falls back onto a real desktop.
func _screen_bounds(body: Rect2) -> Rect2:
	var centre := body.get_center()
	var screen := get_window().current_screen
	var best := INF
	for i in DisplayServer.get_screen_count():
		var r := Rect2(Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)))
		var dist := centre.distance_squared_to(centre.clamp(r.position, r.end))
		if dist < best:
			best = dist
			screen = i
			if dist == 0.0:
				break
	return Rect2(DisplayServer.screen_get_usable_rect(screen))


func _collide() -> void:
	var local := _body_rect()
	var body := Rect2(_pos + local.position, local.size)
	var bounds := _screen_bounds(body)

	# No ceiling: over the top edge it flies on and gravity brings it back. The side walls still
	# hold it in, but it only clings once fully back in view (keeping its sideways speed so it
	# does), so it can never get stuck out of sight.
	if body.position.y < bounds.position.y:
		_clamp_to_side_walls(false)
	# Walls first, so a throw into a lower corner clings rather than lands.
	elif body.position.x < bounds.position.x or body.end.x > bounds.end.x:
		var left := body.position.x < bounds.position.x
		if _vel.y > WALL_GRAB_MAX_FALL_SPEED or _vel.length() > WALL_GRAB_MAX_SPEED:
			# Too fast to grab on: rebound off it (always away from the wall) and fall on.
			_clamp_to_side_walls(false)
			_vel.x = absf(_vel.x) * WALL_BOUNCE * (1.0 if left else -1.0)
			if absf(_vel.x) > THROW_FACE_MIN:  # same rule as a throw: face the way it's going
				sprite.facing_right = _vel.x > 0.0
		else:
			_cling(Pose.CLING_LEFT if left else Pose.CLING_RIGHT)
	elif body.end.y > bounds.end.y:
		_pos.y -= body.end.y - bounds.end.y
		if _vel.y > MIN_BOUNCE_SPEED:
			_vel.y *= -BOUNCE
		else:
			_vel.y = 0.0
			_set_pose(Pose.GROUNDED)


func _clamp_to_side_walls(stop := true) -> void:
	var local := _body_rect()
	var body := Rect2(_pos + local.position, local.size)
	var bounds := _screen_bounds(body)
	if body.position.x < bounds.position.x:
		_pos.x += bounds.position.x - body.position.x
		if stop:
			_vel.x = 0.0
	elif body.end.x > bounds.end.x:
		_pos.x -= body.end.x - bounds.end.x
		if stop:
			_vel.x = 0.0


# Clinging swaps the frame (the wide fall frame for idle), so it snaps to the surface after the
# swap, using the new body rect; snapping first would leave a gap.
func _cling(to: Pose) -> void:
	_vel = Vector2.ZERO
	_set_pose(to)
	var local := _body_rect()
	var body := Rect2(_pos + local.position, local.size)
	var bounds := _screen_bounds(body)
	match to:
		Pose.CLING_LEFT:
			_pos.x += bounds.position.x - body.position.x
		Pose.CLING_RIGHT:
			_pos.x -= body.end.x - bounds.end.x


func _set_pose(p: Pose) -> void:
	if p == pose:
		return
	pose = p
	# Placeholder until the climbing art exists: the idle frame turned feet-first to the surface.
	match p:
		Pose.CLING_LEFT:
			sprite.surface = PandaSprite.Surface.LEFT_WALL
		Pose.CLING_RIGHT:
			sprite.surface = PandaSprite.Surface.RIGHT_WALL
		_:
			sprite.surface = PandaSprite.Surface.FLOOR
	# Only a real fall ends in the landing animation; any other pose change cancels it.
	_recovering = p == Pose.GROUNDED and _falling
	_falling = false
	# Every return to the floor (landing, or the drop at the end of a grab) settles briefly first.
	activity = Activity.IDLE
	_activity_left = randf_range(SETTLE_TIME.x, SETTLE_TIME.y)
	_update_anim()
	pose_changed.emit(p)


func _on_active_app_changed(app: String, _title: String) -> void:
	_app = app
	_refresh_label()


func _on_mood_changed(_mood: float, state: String) -> void:
	# Slipping out of a good mood takes the bamboo away mid-meal.
	if activity == Activity.EAT and state not in EAT_MOODS:
		_start_activity(Activity.IDLE, IDLE_TIME)
	_refresh_label()


func _on_sprite_finished(anim: StringName) -> void:
	match anim:
		&"land":
			# Back on its feet: resume the AI with a short idle.
			_recovering = false
			activity = Activity.IDLE
			_activity_left = randf_range(SETTLE_TIME.x, SETTLE_TIME.y)
			_update_anim()
		&"eat":
			if activity == Activity.EAT:
				_start_activity(Activity.IDLE, IDLE_TIME)


func _on_sleep_changed(_sleeping: bool) -> void:
	# Waking resumes the AI with a short idle, wherever it was when it fell asleep. Sleep hides a
	# fall or landing in progress (so `finished` never comes); drop them rather than get stuck.
	_falling = false
	_recovering = false
	activity = Activity.IDLE
	_activity_left = randf_range(SETTLE_TIME.x, SETTLE_TIME.y)
	_update_anim()
	_refresh_label()


func _refresh_label() -> void:
	label.text = "%s (%d)\n%s · %s" % [
		"Sleeping" if PetBrain.sleeping else PetBrain.get_state(), int(PetBrain.mood),
		"(nothing)" if _app == "" else _app, Classifier.category_name(PetBrain.category),
	]
