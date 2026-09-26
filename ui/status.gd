# status.gd - the status window (ui/status.tscn), opened by double-clicking the pet.
# A separate native OS window (embed_subwindows is off in project.godot). Everything inside is
# laid out in status.png's native pixels; content scaling blows it up by UI_SCALE so the art
# stays crisp and the text renders at full resolution. Purely informational: nothing pauses.
extends Window

const UI_SCALE := 5
const ART_SIZE := Vector2i(144, 142)  # status.png

@onready var state_label: Label = %StateLabel
@onready var value_label: Label = %ValueLabel
@onready var name_label: Label = %NameLabel
@onready var name_edit: LineEdit = %NameEdit

var _dragging := false
var _drag_offset := Vector2i.ZERO
var _cancel_edit := false


func _ready() -> void:
	content_scale_size = ART_SIZE
	size = Vector2i((Vector2(ART_SIZE) * UI_SCALE).round())
	transparent_bg = true  # the rounded pixel corners show the desktop
	# A Window gets its own viewport, which defaults to linear filtering (only the root
	# viewport follows the project setting), so force nearest or the pixel art goes fuzzy.
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	close_requested.connect(hide)
	%CloseButton.pressed.connect(hide)
	%DragHandle.gui_input.connect(_on_drag_handle_input)
	PetBrain.mood_changed.connect(_on_mood_changed)
	PetBrain.name_changed.connect(_on_name_changed)
	name_label.gui_input.connect(_on_name_label_input)
	name_edit.gui_input.connect(_on_name_edit_input)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_finish_name_edit)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func open_centered(screen: int) -> void:
	var usable := DisplayServer.screen_get_usable_rect(screen)
	position = usable.get_center() - size / 2
	show()
	grab_focus()


# Drag the window by the pencil, same approach as the pet: screen mouse minus a grab offset.
func _on_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = DisplayServer.mouse_get_position() - position
	elif event is InputEventMouseMotion and _dragging:
		position = DisplayServer.mouse_get_position() - _drag_offset


func _on_mood_changed(_mood: float, _state: String) -> void:
	_refresh()


func _on_name_changed(_pet_name: String) -> void:
	_refresh()


# Double-clicking the name swaps the label for a LineEdit in the same spot.
func _on_name_label_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and event.double_click:
		name_label.hide()
		name_edit.text = PetBrain.pet_name
		name_edit.show()
		name_edit.grab_focus()
		name_edit.select_all()
		name_label.accept_event()


func _on_name_edit_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_edit = true
		name_edit.accept_event()
		name_edit.release_focus()


# Enter drops focus, and focus_exited does the commit, so it only runs once.
func _on_name_submitted(_text: String) -> void:
	name_edit.release_focus()


func _on_visibility_changed() -> void:
	if not visible:
		_finish_name_edit()


# Commits on Enter, focus loss or the window closing, and reverts on Esc.
func _finish_name_edit() -> void:
	if not name_edit.visible:
		return
	name_edit.hide()  # before committing: hiding drops focus, which re-enters here
	if not _cancel_edit:
		PetBrain.set_pet_name(name_edit.text)
	_cancel_edit = false
	name_label.show()
	_refresh()


func _refresh() -> void:
	name_label.text = PetBrain.pet_name
	state_label.text = PetBrain.get_state()
	value_label.text = "Mood: %d / 100" % int(PetBrain.mood)
