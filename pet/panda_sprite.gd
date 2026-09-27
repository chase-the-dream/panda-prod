# panda_sprite.gd - attach to the pet's Sprite2D. Owns everything visual about the panda: which
# animation plays (looping, or one-shot for scripted ones like the landing), which way it faces,
# and how it's turned when clinging to a surface.
# pet.gd decides *what* the panda is doing; this script only draws it.
# All sheets face right; facing left is a horizontal flip.
class_name PandaSprite
extends Sprite2D

signal finished(anim: StringName)  # a one-shot ("sequence") animation reached its end

enum Surface { FLOOR, LEFT_WALL, RIGHT_WALL }

const SCALE := 4  # integer, so art pixels stay even
const BOTTOM := 256.0  # the label sits below this line

# name -> {texture, frames (regions of the sheet), fps}. The sheets use different cell widths
# and gaps, so frames are explicit regions rather than hframes. Each region is chosen so that,
# centred, the body lines up with base_panda.png (the walk cells carry the head bob).
# An optional "sequence" of [frame index, seconds] steps replaces fps: it plays once, holds the
# last frame and emits `finished`. "loops": N does the same for an fps animation after N passes.
const ANIMS := {
	&"idle": {
		"texture": preload("res://art/base_panda.png"),
		"frames": [Rect2(0, 0, 32, 47)],
		"fps": 1.0,
	},
	&"sit": {
		# pandaSit.png is [sitting, standing]; standing is identical to base_panda.png.
		"texture": preload("res://art/pandaSit.png"),
		"frames": [Rect2(0, 0, 32, 47)],
		"fps": 1.0,
	},
	&"walk": {
		"texture": preload("res://art/pandaWalk.png"),
		"frames": [Rect2(0, 0, 34, 47), Rect2(34, 0, 34, 47), Rect2(68, 0, 34, 47), Rect2(102, 0, 34, 47)],
		"fps": 6.0,
	},
	&"sleep": {
		"texture": preload("res://art/pandaSleep.png"),
		"frames": [
			Rect2(0, 0, 63, 42), Rect2(63, 0, 63, 42), Rect2(126, 0, 63, 42), Rect2(189, 0, 63, 42),
			Rect2(252, 0, 63, 42), Rect2(315, 0, 63, 42), Rect2(378, 0, 63, 42), Rect2(441, 0, 63, 42),
			Rect2(504, 0, 63, 42), Rect2(567, 0, 63, 42),
		],
		"fps": 6.0,
	},
	# pandaEat.png is 33 cells of 32×43, lined up with the sitting frame. The timing is baked in
	# by repeated cells (chewing, blinks, a sparkly-eyed stretch), so it plays at a flat fps.
	# A whole meal is two passes (~12.7 s): "loops" plays that many, holds the last frame and
	# emits `finished`.
	&"eat": {
		"texture": preload("res://art/pandaEat.png"),
		"frames": [
			Rect2(0, 0, 32, 43), Rect2(32, 0, 32, 43), Rect2(64, 0, 32, 43), Rect2(96, 0, 32, 43),
			Rect2(128, 0, 32, 43), Rect2(160, 0, 32, 43), Rect2(192, 0, 32, 43), Rect2(224, 0, 32, 43),
			Rect2(256, 0, 32, 43), Rect2(288, 0, 32, 43), Rect2(320, 0, 32, 43), Rect2(352, 0, 32, 43),
			Rect2(384, 0, 32, 43), Rect2(416, 0, 32, 43), Rect2(448, 0, 32, 43), Rect2(480, 0, 32, 43),
			Rect2(512, 0, 32, 43), Rect2(544, 0, 32, 43), Rect2(576, 0, 32, 43), Rect2(608, 0, 32, 43),
			Rect2(640, 0, 32, 43), Rect2(672, 0, 32, 43), Rect2(704, 0, 32, 43), Rect2(736, 0, 32, 43),
			Rect2(768, 0, 32, 43), Rect2(800, 0, 32, 43), Rect2(832, 0, 32, 43), Rect2(864, 0, 32, 43),
			Rect2(896, 0, 32, 43), Rect2(928, 0, 32, 43), Rect2(960, 0, 32, 43), Rect2(992, 0, 32, 43),
			Rect2(1024, 0, 32, 43),
		],
		"fps": 5.2,
		"loops": 2,
	},
	# pandaFall.png is 5 cells of 60×34: [falling, impact, lying eyes shut, lying eyes open, getting up].
	# Full cells keep the frames aligned with each other, and getting-up with base_panda.png.
	&"fall": {
		"texture": preload("res://art/pandaFall.png"),
		"frames": [Rect2(0, 0, 60, 33)],  # its bottom row is empty; drop it so it lands flush
		"fps": 1.0,
	},
	&"land": {
		"texture": preload("res://art/pandaFall.png"),
		"frames": [Rect2(60, 0, 60, 34), Rect2(120, 0, 60, 34), Rect2(180, 0, 60, 34), Rect2(240, 0, 60, 34)],
		"sequence": [
			[0, 0.10],  # impact
			[1, 1.10],  # lying there, eyes shut
			[2, 0.90],  # eyes open
			[1, 0.12], [2, 0.25],  # blink
			[1, 0.12], [2, 0.65],  # blink, then a moment before getting up
			[3, 0.30],  # getting up
		],
	},
}

var facing_right := true:
	set(value):
		facing_right = value
		_orient()
var surface := Surface.FLOOR:
	set(value):
		surface = value
		_orient()

var anim := &""
var _frame := 0
var _time := 0.0
var _done := false  # a one-shot sequence has finished


func _ready() -> void:
	region_enabled = true
	scale = Vector2(SCALE, SCALE)


# Starts an animation from its first frame; replaying the current one is a no-op.
func play(anim_name: StringName) -> void:
	if anim_name == anim:
		return
	anim = anim_name
	texture = ANIMS[anim_name]["texture"]
	_time = 0.0
	_done = false
	var sequence: Array = ANIMS[anim_name].get("sequence", [])
	_show_frame(sequence[0][0] if sequence else 0)


func _process(delta: float) -> void:
	if not anim or _done:
		return
	if ANIMS[anim].has("sequence"):
		_step_sequence(delta)
		return
	var frames: Array = ANIMS[anim]["frames"]
	if frames.size() < 2:
		return
	_time += delta
	var f := int(_time * ANIMS[anim]["fps"])
	if f >= frames.size() * ANIMS[anim].get("loops", INF):  # played through: hold and report
		_done = true
		finished.emit(anim)
		return
	f %= frames.size()
	if f != _frame:
		_show_frame(f)


# One-shot: walk the [frame, seconds] steps, then hold the last frame and report it once.
func _step_sequence(delta: float) -> void:
	_time += delta
	var t := _time
	for step: Array in ANIMS[anim]["sequence"]:
		if t < step[1]:
			if step[0] != _frame:
				_show_frame(step[0])
			return
		t -= step[1]
	_done = true
	finished.emit(anim)


# Frames differ in size, so re-centre each time to keep the bottom edge (the floor the pet
# collides with) on BOTTOM. The sprite stays centred so the cling rotation turns it in place.
func _show_frame(f: int) -> void:
	_frame = f
	region_rect = ANIMS[anim]["frames"][f]
	position = Vector2(get_viewport().get_visible_rect().size.x / 2.0, BOTTOM - region_rect.size.y * SCALE / 2.0)


# Feet toward the surface. On walls the face points up, like climbing.
func _orient() -> void:
	match surface:
		Surface.LEFT_WALL:
			rotation_degrees = 90.0
			flip_h = true
		Surface.RIGHT_WALL:
			rotation_degrees = -90.0
			flip_h = false
		_:
			rotation_degrees = 0.0
			flip_h = not facing_right
