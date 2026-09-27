# panda_sprite.gd - attach to the pet's Sprite2D. Owns everything visual about the panda: which
# animation plays (looping, or one-shot for scripted ones like the landing), which way it faces,
# and how it's flipped and turned when climbing a wall or the roof.
# pet.gd decides *what* the panda is doing; this script only draws it.
# All sheets face right; facing left is a horizontal flip.
class_name PandaSprite
extends Sprite2D

signal finished(anim: StringName)  # a one-shot ("sequence") animation reached its end

enum Surface { FLOOR, LEFT_WALL, RIGHT_WALL, CEILING }

const SCALE := 4  # integer, so art pixels stay even
const BOTTOM := 256.0  # the floor line the frames stand on

# name -> {texture, frames (regions of the sheet), fps}. The sheets use different cell widths
# and gaps, so frames are explicit regions rather than hframes. Each region is chosen so that,
# centred, the body lines up with base_panda.png (the walk cells carry the head bob).
# An optional "sequence" of [frame index, seconds] steps replaces fps: it plays once, holds the
# last frame and emits `finished`. "loops": N does the same for an fps animation after N passes.
# A "<name>_chud" entry is drawn instead of "<name>" while `chud` is set (the Chud mood); each has
# the same frame layout and timing as its default, just a glummer face.
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
	# pandaPet.png is 24 cells of 39×47: the body is at x 0–32 of each cell, lined up with
	# base_panda.png, and the hearts float in the extra columns to its right. Timing is baked in by
	# repeated cells, like eat; it plays once and emits `finished`. The cells aren't centred on the
	# body, so "anchor_x" (the body's centre x in the region) keeps it from jumping sideways.
	&"pet": {
		"texture": preload("res://art/pandaPet.png"),
		"frames": [
			Rect2(0, 0, 39, 47), Rect2(39, 0, 39, 47), Rect2(78, 0, 39, 47), Rect2(117, 0, 39, 47),
			Rect2(156, 0, 39, 47), Rect2(195, 0, 39, 47), Rect2(234, 0, 39, 47), Rect2(273, 0, 39, 47),
			Rect2(312, 0, 39, 47), Rect2(351, 0, 39, 47), Rect2(390, 0, 39, 47), Rect2(429, 0, 39, 47),
			Rect2(468, 0, 39, 47), Rect2(507, 0, 39, 47), Rect2(546, 0, 39, 47), Rect2(585, 0, 39, 47),
			Rect2(624, 0, 39, 47), Rect2(663, 0, 39, 47), Rect2(702, 0, 39, 47), Rect2(741, 0, 39, 47),
			Rect2(780, 0, 39, 47), Rect2(819, 0, 39, 47), Rect2(858, 0, 39, 47), Rect2(897, 0, 39, 47),
		],
		"fps": 6.0,
		"loops": 1,
		"anchor_x": 16.0,
	},
	# pandaClimb.png is 6 cells of 33×48, drawn upright on a wall to the panda's right, paws on the
	# cell's right edge. Timing is baked in by repeated cells; cell 0 is the resting grip.
	&"cling": {
		"texture": preload("res://art/pandaClimb.png"),
		"frames": [Rect2(0, 0, 33, 48)],
		"fps": 1.0,
	},
	&"climb": {
		"texture": preload("res://art/pandaClimb.png"),
		"frames": [
			Rect2(0, 0, 33, 48), Rect2(33, 0, 33, 48), Rect2(66, 0, 33, 48),
			Rect2(99, 0, 33, 48), Rect2(132, 0, 33, 48), Rect2(165, 0, 33, 48),
		],
		"fps": 6.0,
	},
	# pandaDrag.png is one 52×35 frame of the panda on its side, head right, tail at the far left.
	# It dangles by the tail: "pivot" is the grip, just in from the tail toward the butt (the node's
	# origin, which rotation turns round), and "mass" the body's centre, which pet.gd swings below
	# it like a pendulum.
	# pandaProud.png is one frame the size of base_panda.png: hands on hips, after a full climb.
	&"proud": {
		"texture": preload("res://art/pandaProud.png"),
		"frames": [Rect2(0, 0, 32, 47)],
		"fps": 1.0,
	},
	# Chud variants. pandaWalkChud.png has pandaWalk.png's 4×34 cells; its first cell, cropped 1 px
	# in, lines up with base_panda.png, so it doubles as the chud idle. pandaSitChud.png is the
	# sitting frame without its 4 empty top rows (bottom-aligned, so it lands on the same pixels),
	# and pandaClimbChud.png has pandaClimb.png's 6×33 cells.
	&"idle_chud": {
		"texture": preload("res://art/pandaWalkChud.png"),
		"frames": [Rect2(1, 0, 32, 47)],
		"fps": 1.0,
	},
	&"sit_chud": {
		"texture": preload("res://art/pandaSitChud.png"),
		"frames": [Rect2(0, 0, 32, 43)],
		"fps": 1.0,
	},
	&"walk_chud": {
		"texture": preload("res://art/pandaWalkChud.png"),
		"frames": [Rect2(0, 0, 34, 47), Rect2(34, 0, 34, 47), Rect2(68, 0, 34, 47), Rect2(102, 0, 34, 47)],
		"fps": 6.0,
	},
	&"cling_chud": {
		"texture": preload("res://art/pandaClimbChud.png"),
		"frames": [Rect2(0, 0, 33, 48)],
		"fps": 1.0,
	},
	&"climb_chud": {
		"texture": preload("res://art/pandaClimbChud.png"),
		"frames": [
			Rect2(0, 0, 33, 48), Rect2(33, 0, 33, 48), Rect2(66, 0, 33, 48),
			Rect2(99, 0, 33, 48), Rect2(132, 0, 33, 48), Rect2(165, 0, 33, 48),
		],
		"fps": 6.0,
	},
	# pandaGamingChud.png is 8 cells of 60×47: the panda (pandaSitChud.png, 5 px in) in a gaming
	# chair at a desk, typing. Only a Chud panda games, so it's glum already and has no plain
	# version. It's drawn centred like the wide sleep frame; the scene is too wide to keep the body
	# on its standing spot without clipping the desk. A session is 9 passes (~12 s, about a meal).
	&"game": {
		"texture": preload("res://art/pandaGamingChud.png"),
		"frames": [
			Rect2(0, 0, 60, 47), Rect2(60, 0, 60, 47), Rect2(120, 0, 60, 47), Rect2(180, 0, 60, 47),
			Rect2(240, 0, 60, 47), Rect2(300, 0, 60, 47), Rect2(360, 0, 60, 47), Rect2(420, 0, 60, 47),
		],
		"fps": 6.0,
		"loops": 9,
	},
	&"drag": {
		"texture": preload("res://art/pandaDrag.png"),
		"frames": [Rect2(0, 0, 52, 35)],
		"fps": 1.0,
		"pivot": Vector2(5, 16),
		"mass": Vector2(26, 18),
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
var climbing_down := false:  # on a wall: head-first, heading for the floor
	set(value):
		climbing_down = value
		_orient()

# The Chud mood: draw the "_chud" variant of the current animation where there is one. Switching
# mid-animation swaps the sheet in place (same frames and timing), so nothing restarts.
var chud := false:
	set(value):
		if value == chud:
			return
		chud = value
		if anim:
			_sheet = _resolve(anim)
			texture = ANIMS[_sheet]["texture"]
			_show_frame(mini(_frame, ANIMS[_sheet]["frames"].size() - 1))

var anim := &""  # what pet.gd asked for
var _sheet := &""  # the ANIMS entry actually drawn: anim, or its chud variant
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
	_sheet = _resolve(anim_name)
	texture = ANIMS[_sheet]["texture"]
	_time = 0.0
	_done = false
	var sequence: Array = ANIMS[_sheet].get("sequence", [])
	_frame = sequence[0][0] if sequence else 0
	region_rect = ANIMS[_sheet]["frames"][_frame]
	_orient()  # the flip depends on the animation (a pivot one never uses it), so redo it


func _resolve(anim_name: StringName) -> StringName:
	if chud:
		var variant := StringName(String(anim_name) + "_chud")
		if ANIMS.has(variant):
			return variant
	return anim_name


# Pivot (the grip by the tail) to mass centre of the held frame, in viewport px, before
# rotation; mirrored when facing left, like the frame.
func hang_arm() -> Vector2:
	var drag: Dictionary = ANIMS[&"drag"]
	var arm: Vector2 = (drag["mass"] - drag["pivot"]) * SCALE
	if not facing_right:
		arm.x = -arm.x
	return arm


func _process(delta: float) -> void:
	if not anim or _done:
		return
	if ANIMS[_sheet].has("sequence"):
		_step_sequence(delta)
		return
	var frames: Array = ANIMS[_sheet]["frames"]
	if frames.size() < 2:
		return
	_time += delta
	var f := int(_time * ANIMS[_sheet]["fps"])
	if f >= frames.size() * ANIMS[_sheet].get("loops", INF):  # played through: hold and report
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
	for step: Array in ANIMS[_sheet]["sequence"]:
		if t < step[1]:
			if step[0] != _frame:
				_show_frame(step[0])
			return
		t -= step[1]
	_done = true
	finished.emit(anim)


func _show_frame(f: int) -> void:
	_frame = f
	region_rect = ANIMS[_sheet]["frames"][f]
	_place()


# Frames differ in size, so re-centre each time to keep the bottom edge (the floor the pet
# collides with) on BOTTOM. The sprite stays centred so the roof rotation turns it in place.
# An "anchor_x" off the region's centre shifts it so the body is centred instead, mirrored
# with the flip (only floor animations use one, so rotation doesn't come into it).
#
# A "pivot" animation instead hangs from the viewport centre: the offset puts the pivot on the
# node's origin so rotation turns round it. Facing left mirrors it with a negative x scale rather
# than flip_h, since that mirrors round the origin and so keeps the pivot in place.
func _place() -> void:
	if not _sheet:
		return
	var pivot = ANIMS[_sheet].get("pivot")
	if pivot != null:
		offset = region_rect.size / 2.0 - pivot
		scale = Vector2(SCALE if facing_right else -SCALE, SCALE)
		position = get_viewport().get_visible_rect().size / 2.0
		return
	offset = Vector2.ZERO
	scale = Vector2(SCALE, SCALE)
	position = Vector2(get_viewport().get_visible_rect().size.x / 2.0, BOTTOM - region_rect.size.y * SCALE / 2.0)
	var anchor: float = ANIMS[_sheet].get("anchor_x", region_rect.size.x / 2.0)
	position.x += (region_rect.size.x / 2.0 - anchor) * SCALE * (-1.0 if flip_h else 1.0)


# The climb art grips a wall on the panda's right and heads up. On walls it's flipped toward the
# wall (and upside down, head-first, climbing down); on the roof it's turned so the grip is up
# and the head leads the way it's facing. A pivot (held) animation is mirrored by _place() with
# its scale instead, so it's never flipped.
func _orient() -> void:
	flip_v = false
	match surface:
		Surface.LEFT_WALL, Surface.RIGHT_WALL:
			rotation_degrees = 0.0
			flip_h = surface == Surface.LEFT_WALL
			flip_v = climbing_down
		Surface.CEILING:
			rotation_degrees = 90.0 if facing_right else -90.0
			flip_h = facing_right
		_:
			rotation_degrees = 0.0
			flip_h = not facing_right and not (_sheet and ANIMS[_sheet].has("pivot"))
	_place()
