# achievements.gd - the achievements page inside the status window (ui/achievements.tscn), reached
# from its green trophy tab. A checklist of Achievements.LIST: each entry is a header row (a hand-
# drawn checkbox, the name and a caret) that drops its description down, in the smaller font, when
# clicked. Ticks follow Achievements.unlocked live. Laid out in the art's native pixels, like
# status.gd.
extends Control

signal back_to_status

const SmallFont := preload("res://ui/Small-Font.ttf")
# Small-Font is a dot-matrix font on a 1/25 em grid, so with the window's 5x scale its dots only
# land on whole screen pixels at multiples of 5; 5 is the small one.
const DESCRIPTION_SIZE := 5
const DESCRIPTION_LINE_SPACING := 1  # px between wrapped lines (Label's default 3 is airy here)
const INK := Color(0.22352941, 0.2901961, 0.3137255)  # the status page's dark slate
const LOCKED_INK := Color(0.56, 0.6, 0.61)  # a not-yet-earned name
const TICK := Color(0.27450982, 0.50980395, 0.19607843)  # the art's dark green
const BOX := 7  # px, the checkbox
const INDENT := 10  # px, descriptions line up under the names

@onready var rows: VBoxContainer = %Rows

var _entries := {}  # id -> {box, name, caret, description}


func _ready() -> void:
	%BackButton.pressed.connect(back_to_status.emit)
	for achievement: Dictionary in Achievements.LIST:
		_add_entry(achievement)
	Achievements.unlocked.connect(_on_unlocked)


# Every description closed, as if freshly opened.
func reset() -> void:
	for id in _entries:
		_entries[id]["description"].hide()
		_entries[id]["caret"].queue_redraw()
	%List.scroll_vertical = 0


func _add_entry(achievement: Dictionary) -> void:
	var id: StringName = achievement["id"]
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 1)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 3)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := Control.new()
	box.custom_minimum_size = Vector2(BOX, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.draw.connect(_draw_box.bind(box, id))
	var title := Label.new()
	title.text = achievement["name"]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long name wraps, never widens the list
	title.add_theme_font_size_override("font_size", 8)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caret := Control.new()
	caret.custom_minimum_size = Vector2(5, 0)
	caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(box)
	header.add_child(title)
	header.add_child(caret)

	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", INDENT)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var description := Label.new()
	description.text = achievement["description"]
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_override("font", SmallFont)
	description.add_theme_font_size_override("font_size", DESCRIPTION_SIZE)
	description.add_theme_constant_override("line_spacing", DESCRIPTION_LINE_SPACING)
	description.hide()
	indent.add_child(description)

	caret.draw.connect(_draw_caret.bind(caret, description))
	header.gui_input.connect(_on_header_input.bind(description, caret))
	entry.add_child(header)
	entry.add_child(indent)
	rows.add_child(entry)
	_entries[id] = {"box": box, "name": title, "caret": caret, "description": description}
	_show_state(id)


func _on_header_input(event: InputEvent, description: Label, caret: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		description.visible = not description.visible
		caret.queue_redraw()
		caret.accept_event()


func _on_unlocked(id: StringName) -> void:
	if _entries.has(id):
		_show_state(id)


func _show_state(id: StringName) -> void:
	var entry: Dictionary = _entries[id]
	entry["name"].add_theme_color_override("font_color",
			INK if Achievements.is_unlocked(id) else LOCKED_INK)
	entry["box"].queue_redraw()


# A 7×7 outline, vertically centred on the name, with a pixel tick inside once it's earned.
func _draw_box(box: Control, id: StringName) -> void:
	var top := floorf((box.size.y - BOX) / 2.0)
	var ink := INK if Achievements.is_unlocked(id) else LOCKED_INK
	box.draw_rect(Rect2(0, top, BOX, 1), ink)
	box.draw_rect(Rect2(0, top + BOX - 1, BOX, 1), ink)
	box.draw_rect(Rect2(0, top, 1, BOX), ink)
	box.draw_rect(Rect2(BOX - 1, top, 1, BOX), ink)
	if Achievements.is_unlocked(id):
		for p: Vector2 in [Vector2(1, 3), Vector2(2, 4), Vector2(3, 3), Vector2(4, 2), Vector2(5, 1)]:
			box.draw_rect(Rect2(p + Vector2(0, top), Vector2.ONE), TICK)
		box.draw_rect(Rect2(Vector2(2, 3 + top), Vector2.ONE), TICK)  # thicker at the elbow


# A pixel triangle: pointing right while the description is closed, down while it's open.
func _draw_caret(caret: Control, description: Label) -> void:
	var top := floorf((caret.size.y - 5) / 2.0)
	if description.visible:
		for row in 3:
			caret.draw_rect(Rect2(row, top + 1 + row, 5 - row * 2, 1), INK)
	else:
		for column in 3:
			caret.draw_rect(Rect2(1 + column, top + column, 1, 5 - column * 2), INK)
