# pet.gd - attach to the root Node2D ("Pet") with children Sprite2D (panda_sprite.gd) and Label.
# The whole OS window is the pet: dragging, throwing, gravity and clinging to the screen
# edges all move the window itself. Collisions use the sprite's rect against the usable
# (taskbar-excluded) rect of the monitor it's on. On the floor, a small activity AI has the
# panda idle, sit, walk and, in a good mood, eat. Picked up, it dangles by its tail from the
# cursor and swings like a pendulum (the window grows to fit the swing). On a wall
# it climbs up in stretches with breaks, along the roof to the far wall and head-first down that,
# hopping off near the floor, proud of itself (+mood); any break may end in a fall. Once it's really
# falling it shows the fall frame, and landing like that plays a one-shot flop, blink and
# get-up before the AI takes over again. Rubbing the mouse over a settled panda interrupts it
# to be petted (hearts, +mood, on a cooldown). In a Chud mood idle, sit, walk and climb use the
# glum-faced variants. Sleep mode (PetBrain.sleeping) overrides all of it with
# the sleep animation and freezes the AI; it's independent of the pose, so a sleeping pet can
# still be carried and thrown.
extends Node2D

# CLING_CEILING is only reached by climbing onto the roof; a throw never sticks to it.
enum Pose { HELD, AIRBORNE, GROUNDED, CLING_LEFT, CLING_RIGHT, CLING_CEILING }
enum Activity { IDLE, SIT, WALK, EAT, PET, PROUD }

signal pose_changed(pose: Pose)

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
# px/s of sideways throw needed to turn the panda that way; low, so even a gentle drift faces
# where it's going (below it's just release jitter).
const THROW_FACE_MIN := 15.0

# Held by the tail: the body's mass centre swings below the cursor (a damped Verlet pendulum), so
# moving the mouse swings it, up to SWING_MAX_ANGLE either way. The throw is the mass centre's
# speed, so letting go mid-swing flings it off. The swing needs more room than the pet window, so
# the window grows to HELD_SIZE (the tail at its centre) until it's let go. A tap (a plain click,
# or the first of a double-click) puts it back exactly where it was.
const HELD_SIZE := Vector2i(448, 448)  # px; the farthest pixel swings ~203 px from the grip
# A stronger pull back to hanging means the same mouse movement swings it less, and the damping
# settles it sooner.
const SWING_GRAVITY := 3200.0  # px/s²; ~1 s swing period
const SWING_DAMPING := 1.4  # exponential swing decay per second
const SWING_MAX_ANGLE := deg_to_rad(45.0)  # either side of hanging straight down
const TAP_TIME := 0.15  # s
const TAP_MOVE := 8.0  # px of mouse travel

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
const CHUD_STATE := "Chud"  # the PetBrain.get_state() name that swaps in the glum animations
const WALK_SPEED := 55.0  # px/s
const MIN_WALK_ROOM := 150.0  # px; less room than this ahead and it walks the other way

# Petting: rubbing the mouse over a settled panda fills a meter (px of mouse travel over the body)
# that drains on its own, so a pass over it or hovering never counts, but a brisk back-and-forth
# fills it in about half a second. It interrupts whatever the panda was doing, in any mood.
const RUB_AMOUNT := 500.0  # px
const RUB_DECAY := 400.0  # px/s
const PET_COOLDOWN := 30.0  # s, from the start of one petting to the next
const PET_MOOD := 5.0  # mood gained per petting

# Climbing. Durations are [min, max] seconds. A wall takes roughly 30–40 s and about 8 breaks, so
# it lets go somewhere along the way about half the time.
const CLING_WAIT := Vector2(2.0, 4.0)  # first rest after grabbing a wall
const CLIMB_TIME := Vector2(3.0, 6.0)
const CLIMB_BREAK_TIME := Vector2(1.5, 3.0)
const CLIMB_SPEED := 40.0  # px/s
const CLIMB_FALL_CHANCE := 0.1  # per break
const CLIMB_FALL_PUSH := 150.0  # px/s toward the middle of the screen when it lets go
const CLIMB_DROP_HEIGHT := 40.0  # px above the floor where a head-first climb hops off
# Hopping off after the whole route (up, over the roof, down the far wall) without falling, it
# strikes a proud pose for a moment and cheers up.
const PROUD_TIME := Vector2(2.5, 3.5)
const PROUD_MOOD := 10.0

const StatusScene := preload("res://ui/status.tscn")

@onready var sprite: PandaSprite = $Sprite2D
@onready var label: Label = $Label

var pose := Pose.AIRBORNE
var activity := Activity.IDLE

var _pos := Vector2.ZERO  # window position, kept as floats between ticks
var _vel := Vector2.ZERO
var _samples: Array = []  # [time_sec, mass centre] while held
var _swing_com := Vector2.ZERO  # held: the body's mass centre on screen
var _swing_prev := Vector2.ZERO  # ...on the previous tick (Verlet keeps velocity as the difference)
var _grab_pos := Vector2.ZERO  # window position when picked up, restored after a tap
var _grab_mouse := Vector2.ZERO
var _grab_time := 0.0
var _normal_content := Vector2i.ZERO  # the pet window's content size, restored on letting go
var _dpi_ratio := Vector2.ONE  # window px per content px
var _app := ""
var _status: Window  # created on first double-click, then reused
var _activity_left := 0.0  # s until the AI picks the next activity
var _walk_dir := 1.0
var _falling := false  # showing the fall frame; latched until the pose changes (so through bounces)
var _recovering := false  # the landing animation is playing; the AI waits for it
var _rub := 0.0  # the petting meter, px
var _pet_cooldown := 0.0  # s until it can be petted again
var _last_mouse := Vector2.ZERO
var _climbing := false  # moving along the wall or roof, rather than resting
var _climb_down := false  # on a wall, head-first toward the floor
var _soft_drop := false  # hopped off at the bottom of a climb: lands on its feet, no flop


func _ready() -> void:
	get_viewport().transparent_bg = true  # belt and braces with project settings
	# PetBrain connected to Tracker first (autoloads are ready before this scene), so its
	# category is already up to date when _on_active_app_changed runs.
	Tracker.active_app_changed.connect(_on_active_app_changed)
	PetBrain.mood_changed.connect(_on_mood_changed)
	PetBrain.sleep_changed.connect(_on_sleep_changed)
	sprite.finished.connect(_on_sprite_finished)
	sprite.chud = PetBrain.get_state() == CHUD_STATE
	_update_anim()
	_refresh_label()

	_pos = Vector2(get_window().position)  # start airborne: drop onto the taskbar
	_last_mouse = _mouse()
	_normal_content = get_window().content_scale_size
	_dpi_ratio = Vector2(get_window().size) / Vector2(_normal_content)

	# Optional click-through: only the area inside this polygon receives clicks;
	# everything else passes to the desktop. Enable once dragging works.
	# var r := Rect2(sprite.global_position - sprite.get_rect().size / 2, sprite.get_rect().size)
	# DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
	# 	r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)
	# ]))


func _input(event: InputEvent) -> void:
	# Pick up by the tail with the left mouse button; releasing throws with the recent swing
	# velocity.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click:
			_open_status()  # the pair's first click already did a normal pick-up and drop
		elif event.pressed:
			_grab_pos = _pos
			_grab_mouse = _mouse()
			_grab_time = Time.get_ticks_usec() / 1e6
			_samples.clear()
			_vel = Vector2.ZERO
			_set_window_size(true)
			# It dangles facing the way it looked: on a wall, toward the wall.
			match pose:
				Pose.CLING_LEFT:
					sprite.facing_right = false
				Pose.CLING_RIGHT:
					sprite.facing_right = true
			# Teleport the tail to the cursor, hanging at rest straight below it.
			_swing_com = _grab_mouse + Vector2(0.0, sprite.hang_arm().length() * _dpi_ratio.x)
			_swing_prev = _swing_com
			_set_pose(Pose.HELD)
			_swing_step(0.0)
			get_window().position = Vector2i(_pos.round())
		elif pose == Pose.HELD:
			var tap := (Time.get_ticks_usec() / 1e6 - _grab_time < TAP_TIME
					and _mouse().distance_to(_grab_mouse) < TAP_MOVE)
			_vel = Vector2.ZERO if tap else _throw_velocity()
			if absf(_vel.x) > THROW_FACE_MIN:
				sprite.facing_right = _vel.x > 0.0
			_set_window_size(false)
			_set_pose(Pose.AIRBORNE)
			# Upright again, its body centred where the dangling body was.
			_pos = _grab_pos if tap else _swing_com - _body_rect().get_center()
			get_window().position = Vector2i(_pos.round())

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _physics_process(delta: float) -> void:
	_update_rub(delta)
	match pose:
		Pose.HELD:
			_swing_step(delta)
		Pose.AIRBORNE:
			_vel.y += GRAVITY * delta
			_pos += _vel * delta
			_collide()
			# After the collision, so the pick-up-and-drop of a plain click (landed on this same
			# first tick) never shows the fall frame or plays the landing. Nor does the short hop
			# off the bottom of a climb.
			if pose == Pose.AIRBORNE and not _falling and not _soft_drop and not PetBrain.sleeping:
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
			if not PetBrain.sleeping:
				_run_climb(delta)
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


# Polls the mouse rather than using motion events, so it works while the window isn't focused.
# Only a panda standing settled on the floor (slide over, not getting up, awake) can be petted.
func _update_rub(delta: float) -> void:
	var mouse := _mouse()
	var moved := mouse.distance_to(_last_mouse)
	_last_mouse = mouse
	_pet_cooldown = maxf(_pet_cooldown - delta, 0.0)
	_rub = maxf(_rub - RUB_DECAY * delta, 0.0)
	if (pose != Pose.GROUNDED or _vel.x != 0.0 or PetBrain.sleeping or _recovering
			or activity == Activity.PET or _pet_cooldown > 0.0):
		_rub = 0.0
		return
	var local := _body_rect()
	if Rect2(_pos + local.position, local.size).has_point(mouse):
		_rub += moved
		if _rub >= RUB_AMOUNT:
			_start_pet()


# Like a meal, it ends when the sprite reports the animation finished.
func _start_pet() -> void:
	activity = Activity.PET
	_activity_left = INF
	_rub = 0.0
	_pet_cooldown = PET_COOLDOWN
	PetBrain.change_mood(PET_MOOD)
	_update_anim()


# Climbing AI, in stretches and breaks on the same timer as the floor AI. Up a wall, along the
# roof away from it, head-first down the far wall, and a hop off near the floor. Each break may
# end in a fall instead (not the first rest after grabbing on).
func _run_climb(delta: float) -> void:
	if _climbing:
		match pose:
			Pose.CLING_CEILING:
				_pos.x += (1.0 if sprite.facing_right else -1.0) * CLIMB_SPEED * delta
			_:
				_pos.y += (1.0 if _climb_down else -1.0) * CLIMB_SPEED * delta
		var local := _body_rect()
		var body := Rect2(_pos + local.position, local.size)
		var bounds := _screen_bounds(body)
		match pose:
			Pose.CLING_CEILING:
				if sprite.facing_right and body.end.x >= bounds.end.x:
					_turn_corner(Pose.CLING_RIGHT, true)
				elif not sprite.facing_right and body.position.x <= bounds.position.x:
					_turn_corner(Pose.CLING_LEFT, true)
			_:
				if _climb_down and body.end.y >= bounds.end.y - CLIMB_DROP_HEIGHT:
					_drop(0.0, true)
					return
				if not _climb_down and body.position.y <= bounds.position.y:
					sprite.facing_right = pose == Pose.CLING_LEFT  # head away from this wall
					_turn_corner(Pose.CLING_CEILING, false)
	_activity_left -= delta
	if _activity_left > 0.0:
		return
	if _climbing:
		_climbing = false
		if randf() < CLIMB_FALL_CHANCE:
			_drop(CLIMB_FALL_PUSH, false)
			return
		_activity_left = randf_range(CLIMB_BREAK_TIME.x, CLIMB_BREAK_TIME.y)
	else:
		_climbing = true
		_activity_left = randf_range(CLIMB_TIME.x, CLIMB_TIME.y)
	_update_anim()


# Round a corner mid-stretch: the new surface keeps the climb going rather than starting a rest.
func _turn_corner(to: Pose, down: bool) -> void:
	var left := _activity_left
	_cling(to, down)
	_climbing = true
	_activity_left = left
	_update_anim()


# Let go, drifting toward the middle of the screen. A soft drop is the planned hop off the bottom
# of a climb: it lands on its feet instead of flopping.
func _drop(push: float, soft: bool) -> void:
	var local := _body_rect()
	var body := Rect2(_pos + local.position, local.size)
	var dir := signf(_screen_bounds(body).get_center().x - body.get_center().x)
	if dir != 0.0:
		sprite.facing_right = dir > 0.0
	_vel = Vector2(dir * push, 0.0)
	_set_pose(Pose.AIRBORNE)
	_soft_drop = soft


# Held by the tail beats everything (even sleep: it's still dangling), then sleep, then falling
# and landing; on the floor the activity picks the animation, on a wall or the roof the
# climbing; otherwise idle.
func _update_anim() -> void:
	if pose == Pose.HELD:
		sprite.play(&"drag")
	elif PetBrain.sleeping:
		sprite.play(&"sleep")
	elif pose == Pose.AIRBORNE and _falling:
		sprite.play(&"fall")
	elif pose == Pose.GROUNDED and _recovering:
		sprite.play(&"land")
	elif pose == Pose.AIRBORNE:
		sprite.play(&"idle")
	elif pose != Pose.GROUNDED:
		sprite.play(&"climb" if _climbing else &"cling")
	else:
		match activity:
			Activity.SIT:
				sprite.play(&"sit")
			Activity.WALK:
				sprite.play(&"walk")
			Activity.EAT:
				sprite.play(&"eat")
			Activity.PET:
				sprite.play(&"pet")
			Activity.PROUD:
				sprite.play(&"proud")
			_:
				sprite.play(&"idle")


func _open_status() -> void:
	if _status == null:
		_status = StatusScene.instantiate()
		add_child(_status)
	_status.open_centered(get_window().current_screen)


func _mouse() -> Vector2:
	return Vector2(DisplayServer.mouse_get_position())


# Held: one tick of the tail pendulum. The tail follows the cursor exactly, and the mass centre
# keeps its own momentum (Verlet), falls, and is pulled back to arm's length from the tail, so
# moving the tail swings it. The sprite turns to point from the tail to the mass centre.
func _swing_step(delta: float) -> void:
	var tail := _mouse()
	var arm := sprite.hang_arm() * _dpi_ratio.x
	var swing := (_swing_com - _swing_prev) * exp(-SWING_DAMPING * delta)
	_swing_prev = _swing_com
	_swing_com += swing + Vector2(0.0, SWING_GRAVITY) * delta * delta
	var dir := _swing_com - tail
	if dir.is_zero_approx():
		dir = Vector2.DOWN
	# A free pendulum flips and spins in ways that look wrong on a panda, so the swing stops dead
	# at SWING_MAX_ANGLE either side of hanging straight down.
	var angle := Vector2.DOWN.angle_to(dir)
	var hit_stop := absf(angle) > SWING_MAX_ANGLE
	if hit_stop:
		dir = Vector2.DOWN.rotated(clampf(angle, -SWING_MAX_ANGLE, SWING_MAX_ANGLE))
	_swing_com = tail + dir.normalized() * arm.length()
	if hit_stop:
		_swing_prev = _swing_com
	sprite.rotation = dir.angle() - arm.angle()
	_pos = tail - Vector2(get_window().size) / 2.0  # the tail sits at the window's centre
	var now := Time.get_ticks_usec() / 1e6
	_samples.append([now, _swing_com])
	while _samples.size() > 2 and now - _samples[0][0] > THROW_SAMPLE_TIME:
		_samples.pop_front()


# Held, the window grows to fit the swing; the content size follows it so nothing is scaled.
func _set_window_size(held: bool) -> void:
	var window := get_window()
	window.content_scale_size = HELD_SIZE if held else _normal_content
	window.size = Vector2i((Vector2(window.content_scale_size) * _dpi_ratio).round())


func _throw_velocity() -> Vector2:
	if _samples.size() < 2:
		return Vector2.ZERO
	var first: Array = _samples[0]
	var last: Array = _samples[-1]
	var dt: float = last[0] - first[0]
	if dt <= 0.0:
		return Vector2.ZERO
	return ((last[1] - first[1]) / dt).limit_length(MAX_THROW_SPEED)


# Sprite rect in window pixels (window size may differ from the viewport size on hi-DPI). Through
# the sprite's transform, so it's the right way round when turned sideways on the roof.
func _body_rect() -> Rect2:
	var local := sprite.get_transform() * sprite.get_rect()
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


# Clinging swaps the frame (the wide fall frame for climb, or turning a corner), so it snaps to
# the surface after the swap, using the new body rect; snapping first would leave a gap. Coming
# down off the roof the upright frame is taller, so a wall also keeps it below the roof.
func _cling(to: Pose, down := false) -> void:
	_vel = Vector2.ZERO
	_climb_down = down
	_set_pose(to)
	var local := _body_rect()
	var body := Rect2(_pos + local.position, local.size)
	var bounds := _screen_bounds(body)
	match to:
		Pose.CLING_LEFT:
			_pos.x += bounds.position.x - body.position.x
		Pose.CLING_RIGHT:
			_pos.x -= body.end.x - bounds.end.x
		Pose.CLING_CEILING:
			_pos.y += bounds.position.y - body.position.y
			_clamp_to_side_walls(false)  # flush into the corner it came up
	if to != Pose.CLING_CEILING and body.position.y < bounds.position.y:
		_pos.y += bounds.position.y - body.position.y


func _set_pose(p: Pose) -> void:
	if p == pose:
		return
	pose = p
	match p:
		Pose.CLING_LEFT:
			sprite.surface = PandaSprite.Surface.LEFT_WALL
		Pose.CLING_RIGHT:
			sprite.surface = PandaSprite.Surface.RIGHT_WALL
		Pose.CLING_CEILING:
			sprite.surface = PandaSprite.Surface.CEILING
		_:
			sprite.surface = PandaSprite.Surface.FLOOR
	sprite.climbing_down = _climb_down
	label.visible = p != Pose.HELD  # it would sit off to one side of the grown window
	# Only a real fall ends in the landing animation; any other pose change cancels it. The hop
	# off the bottom of a climb only happens after the whole route, so landing it is a win.
	var proud := p == Pose.GROUNDED and _soft_drop
	_recovering = p == Pose.GROUNDED and _falling
	_falling = false
	_soft_drop = false
	_climbing = false
	# Every return to the floor (landing, or the drop at the end of a grab) settles briefly first,
	# and a fresh grip on a wall rests a little longer before climbing.
	activity = Activity.IDLE
	var wait: Vector2 = SETTLE_TIME if p == Pose.GROUNDED else CLING_WAIT
	_activity_left = randf_range(wait.x, wait.y)
	if proud:
		activity = Activity.PROUD
		_activity_left = randf_range(PROUD_TIME.x, PROUD_TIME.y)
		PetBrain.change_mood(PROUD_MOOD)
	_update_anim()
	pose_changed.emit(p)


func _on_active_app_changed(app: String, _title: String) -> void:
	_app = app
	_refresh_label()


func _on_mood_changed(_mood: float, state: String) -> void:
	sprite.chud = state == CHUD_STATE  # swaps the current animation's sheet in place
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
		&"pet":
			if activity == Activity.PET:
				_start_activity(Activity.IDLE, IDLE_TIME)


func _on_sleep_changed(_sleeping: bool) -> void:
	# Waking resumes the AI with a short idle, wherever it was when it fell asleep. Sleep hides a
	# fall or landing in progress (so `finished` never comes); drop them rather than get stuck.
	# A climber rests first, then carries on the way it was going.
	_falling = false
	_recovering = false
	_climbing = false
	activity = Activity.IDLE
	_activity_left = randf_range(SETTLE_TIME.x, SETTLE_TIME.y)
	_update_anim()
	_refresh_label()


func _refresh_label() -> void:
	label.text = "%s (%d)\n%s · %s" % [
		"Sleeping" if PetBrain.sleeping else PetBrain.get_state(), int(PetBrain.mood),
		"(nothing)" if _app == "" else _app, Classifier.category_name(PetBrain.category),
	]
