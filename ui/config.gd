# config.gd - the config pages inside the status window (ui/config.tscn), reached from its red "!"
# tab. The menu (config.png) picks one of the two keyword lists; the entries page
# (config_entries.png) lists that list's keywords with an X to delete each, and adds new ones from
# the "New Entry:" field (green arrow or Enter). Every change goes straight to Classifier, which
# saves it to user://classification.json. Laid out in the art's native pixels, like status.gd.
extends Control

signal back_to_status

const MenuTexture := preload("res://ui/config.png")
const EntriesTexture := preload("res://ui/config_entries.png")
const DOTS_WIDTH := 4.0  # px: the ".." a keyword too long for its row ends in (see _fit())

@onready var background: TextureRect = %Background
@onready var title: Label = %Title
@onready var menu: Control = %Menu
@onready var entries: Control = %Entries
@onready var list: ScrollContainer = %List
@onready var rows: VBoxContainer = %Rows
@onready var new_entry: LineEdit = %NewEntry

var _category := Classifier.Category.DISTRACTING  # the list the entries page shows


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	%DistractionsButton.pressed.connect(show_entries.bind(Classifier.Category.DISTRACTING))
	%ProductivesButton.pressed.connect(show_entries.bind(Classifier.Category.PRODUCTIVE))
	%AddButton.pressed.connect(_add_entry)
	new_entry.text_submitted.connect(_add_entry.unbind(1))
	new_entry.gui_input.connect(_on_new_entry_input)
	Classifier.lists_changed.connect(_rebuild)
	show_menu()


func show_menu() -> void:
	background.texture = MenuTexture
	title.text = "Configuration"
	entries.hide()
	menu.show()
	new_entry.release_focus()


func show_entries(category: Classifier.Category) -> void:
	_category = category
	background.texture = EntriesTexture
	title.text = "Productives" if category == Classifier.Category.PRODUCTIVE else "Distractions"
	menu.hide()
	entries.show()
	new_entry.clear()
	_rebuild()
	list.scroll_vertical = 0


# Entries back to the menu; the menu back to the status page.
func _on_back_pressed() -> void:
	if entries.visible:
		show_menu()
	else:
		back_to_status.emit()


# Blanks and duplicates are ignored. Adding rebuilds the list (lists_changed), then it scrolls to
# the new keyword once the rows have been laid out.
func _add_entry() -> void:
	new_entry.edit()  # clicking the arrow shouldn't end typing either
	if not Classifier.add_keyword(_category, new_entry.text):
		return
	new_entry.clear()
	await get_tree().process_frame
	if rows.get_child_count() > 0:
		list.ensure_control_visible(rows.get_child(-1))


func _on_new_entry_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		new_entry.clear()
		new_entry.release_focus()
		new_entry.accept_event()


# One row per keyword: the name on the left (cut short with ".." if it doesn't fit), an X on the
# right that deletes it.
func _rebuild() -> void:
	for row in rows.get_children():
		rows.remove_child(row)
		row.queue_free()
	for keyword in Classifier.get_keywords(_category):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = keyword
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true  # so a long keyword doesn't widen the row
		label.add_theme_font_size_override("font_size", 8)
		label.resized.connect(_fit.bind(label, keyword))
		label.draw.connect(_draw_dots.bind(label))
		var remove := Button.new()
		remove.text = "X"
		remove.focus_mode = Control.FOCUS_NONE
		remove.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		remove.pressed.connect(Classifier.remove_keyword.bind(_category, keyword))
		row.add_child(label)
		row.add_child(remove)
		rows.add_child(row)


# A keyword that doesn't fit its row is cut short, letter by letter, until it fits with "..". The
# dots are drawn by hand (_draw_dots()): Label's own ellipsis only takes a single character, and
# this font's "." has no spacing, so ".." as text runs together into one bar.
func _fit(label: Label, keyword: String) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var text := keyword
	var cut := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x
	if cut:
		while text.length() > 1 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x + DOTS_WIDTH > label.size.x:
			text = text.left(-1)
	label.text = text
	label.set_meta(&"cut", cut)
	label.queue_redraw()


# Two 1 px dots on the baseline, a pixel apart, straight after the cut text.
func _draw_dots(label: Label) -> void:
	if not label.get_meta(&"cut", false):
		return
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var x := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var y := font.get_ascent(font_size) - 1.0
	var color := label.get_theme_color("font_color")
	for i in 2:
		label.draw_rect(Rect2(x + i * 2.0, y, 1.0, 1.0), color)
