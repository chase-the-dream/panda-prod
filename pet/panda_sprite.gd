# panda_sprite.gd - attach to the pet's Sprite2D. Owns everything visual about the panda: which
# looping animation plays, which way it faces, and how it's turned when clinging to a surface.
# pet.gd decides *what* the panda is doing; this script only draws it.
# All sheets face right; facing left is a horizontal flip.
class_name PandaSprite
extends Sprite2D

enum Surface { FLOOR, LEFT_WALL, RIGHT_WALL, CEILING }

const SCALE := 4  # integer, so art pixels stay even
const BOTTOM := 256.0  # the label sits below this line

# name -> {texture, frames (regions of the sheet), fps}. The sheets use different cell widths
# and gaps, so frames are explicit regions rather than hframes. Each region is chosen so that,
# centred, the body lines up with base_panda.png (the walk cells carry the head bob).
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


func _ready() -> void:
	region_enabled = true
	scale = Vector2(SCALE, SCALE)


# Starts a looping animation from its first frame; replaying the current one is a no-op.
func play(anim_name: StringName) -> void:
	if anim_name == anim:
		return
	anim = anim_name
	texture = ANIMS[anim_name]["texture"]
	_time = 0.0
	_show_frame(0)


func _process(delta: float) -> void:
	var frames: Array = ANIMS[anim]["frames"] if anim else []
	if frames.size() < 2:
		return
	_time += delta
	var f := int(_time * ANIMS[anim]["fps"]) % frames.size()
	if f != _frame:
		_show_frame(f)


# Frames differ in size, so re-centre each time to keep the bottom edge (the floor the pet
# collides with) on BOTTOM. The sprite stays centred so the cling rotation turns it in place.
func _show_frame(f: int) -> void:
	_frame = f
	region_rect = ANIMS[anim]["frames"][f]
	position = Vector2(get_viewport().get_visible_rect().size.x / 2.0, BOTTOM - region_rect.size.y * SCALE / 2.0)


# Feet toward the surface. On walls the face points up, like climbing. The 180° ceiling turn
# mirrors the image, so the flip is inverted there to keep the left/right facing.
func _orient() -> void:
	match surface:
		Surface.LEFT_WALL:
			rotation_degrees = 90.0
			flip_h = true
		Surface.RIGHT_WALL:
			rotation_degrees = -90.0
			flip_h = false
		Surface.CEILING:
			rotation_degrees = 180.0
			flip_h = facing_right
		_:
			rotation_degrees = 0.0
			flip_h = not facing_right
