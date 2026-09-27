# info.gd - the information page inside the status window (ui/info.tscn), reached from its "?"
# tab: beginner help, one heading (Game Font) and body (Small-Font) per section, in a scrolling
# list over info.png's white box. Laid out in the art's native pixels, like status.gd.
# Every label wraps: a ScrollContainer grows to its content's minimum width, so a single line too
# wide for the box (a long heading) would stretch the whole list past the box's edge.
extends Control

signal back_to_status

const SmallFont := preload("res://ui/Small-Font.ttf")
# Same as the achievement descriptions: Small-Font is only crisp at multiples of 5 in this window.
const BODY_SIZE := 5
const BODY_LINE_SPACING := 1  # px between wrapped lines

const SECTIONS := [
	["Your Panda", "Your panda lives on your desktop and reacts to what you're doing. He walks, sits, snacks and naps along the bottom of your screen, and sometimes climbs its sides."],
	["Picking Him Up", "Hold left-click on him to lift him by the tail, move the mouse to swing him, and let go to toss him. Thrown at the edge of the screen, he'll cling on and climb. Right-click him to open this window. To close the app, click him and press Esc."],
	["Mood", "His mood runs from 1 to 100. It rises while you use productive apps, drops slowly on everything else and faster on distracting ones. Low is Chud, the middle is Content, high is Chad. A happy panda munches bamboo; a Chud one plays video games instead. Petting him and watching him finish a climb cheer him up."],
	["Petting", "Rub your cursor back and forth over him while he's standing on the ground. He needs a little while before he can be petted again."],
	["Sleep", "Stepping away? The moon button puts him to sleep and his mood stays frozen while he naps. The sun wakes him up. You can still carry him around while he sleeps."],
	["Config (the ! tab)", "The Distractions and Productives lists decide how an app counts. Both start empty, so add your own, like the name of your code editor or a site you lose time on. An entry matches any app or window title that contains it, and capitals don't matter. If both lists match, Distractions win. Type an entry and press the green arrow or Enter to add it; X removes one. Changes save right away."],
	["Achievements (the trophy tab)", "A checklist of things to catch your panda doing. Click one for a hint."],
	["This Window", "Drag it around by the pencil and close it with the X. Click the name tag to rename your panda."],
]

@onready var list: ScrollContainer = %List
@onready var sections: VBoxContainer = %Sections


func _ready() -> void:
	%BackButton.pressed.connect(back_to_status.emit)
	for section: Array in SECTIONS:
		var heading := Label.new()
		heading.text = section[0]
		heading.add_theme_font_size_override("font_size", 8)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var body := Label.new()
		body.text = section[1]
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_override("font", SmallFont)
		body.add_theme_font_size_override("font_size", BODY_SIZE)
		body.add_theme_constant_override("line_spacing", BODY_LINE_SPACING)
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 1)
		block.add_child(heading)
		block.add_child(body)
		sections.add_child(block)


# Back to the top, as if freshly opened.
func reset() -> void:
	list.scroll_vertical = 0
