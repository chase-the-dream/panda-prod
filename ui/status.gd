# status.gd - the status window (ui/status.tscn), opened by right-clicking the pet.
# A separate native OS window (embed_subwindows is off in project.godot). Everything inside is
# laid out in the status art's native pixels; content scaling blows it up by UI_SCALE so the art
# stays crisp and the text renders at full resolution. The moon/sun button toggles sleep mode
# (statusDay.png / statusNight.png); nothing else pauses while it's open. The "?" tab swaps the
# status page for the information page (ui/info.tscn), the red "!" tab for the config pages
# (ui/config.tscn) and the green trophy tab for the achievements page (ui/achievements.tscn);
# their back arrows swap it back. The window always reopens on the status page.
extends Window

const UI_SCALE := 5
const ART_SIZE := Vector2i(144, 142)  # statusDay.png / statusNight.png
const DayTexture := preload("res://ui/statusDay.png")
const NightTexture := preload("res://ui/statusNight.png")  # sleeping panda baked into the field
# The sleep toggle's two looks, each a sheet of two 15×15 frames: [as baked into the background,
# with a hover ring]. Awake it's the moon (buttonNight.png, go to sleep); asleep, the sun
# (buttonDay.png, wake up). Frame 1 matches the background exactly, so only hovering shows.
const MoonSheet := preload("res://ui/buttonNight.png")
const SunSheet := preload("res://ui/buttonDay.png")
const TOGGLE_FRAME := Vector2(15, 15)

@onready var state_label: Label = %StateLabel
@onready var value_label: Label = %ValueLabel
@onready var name_label: Label = %NameLabel
@onready var name_edit: LineEdit = %NameEdit
@onready var background: TextureRect = %Background
@onready var field_panda: TextureRect = %FieldPanda
@onready var sleep_button: TextureButton = %SleepButton
@onready var status_page: Control = %StatusPage
@onready var config_page: Control = %ConfigPage
@onready var achievements_page: Control = %AchievementsPage
@onready var info_page: Control = %InfoPage

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
	sleep_button.pressed.connect(_on_sleep_pressed)
	%ConfigTab.pressed.connect(_show_config)
	%AchievementsTab.pressed.connect(_show_achievements)
	%InfoTab.pressed.connect(_show_info)
	info_page.back_to_status.connect(_show_status)
	config_page.back_to_status.connect(_show_status)
	achievements_page.back_to_status.connect(_show_status)
	%DragHandle.gui_input.connect(_on_drag_handle_input)
	PetBrain.mood_changed.connect(_on_mood_changed)
	PetBrain.name_changed.connect(_on_name_changed)
	PetBrain.sleep_changed.connect(_on_sleep_changed)
	name_edit.max_length = PetBrain.NAME_MAX_LENGTH
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


func _on_sleep_changed(_sleeping: bool) -> void:
	_refresh()


# The moon (day) puts the pet to sleep; the sun (night) wakes it up.
func _on_sleep_pressed() -> void:
	PetBrain.set_sleeping(not PetBrain.sleeping)


# Clicking the name tag swaps the label for a LineEdit in the same spot.
func _on_name_label_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
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
		_show_status()


func _show_config() -> void:
	config_page.show_menu()
	_show_page(config_page)


func _show_achievements() -> void:
	achievements_page.reset()
	_show_page(achievements_page)


func _show_info() -> void:
	info_page.reset()
	_show_page(info_page)


func _show_status() -> void:
	_show_page(status_page)


# One page at a time over the shared close button and drag handle.
func _show_page(page: Control) -> void:
	_finish_name_edit()
	for p: Control in [status_page, config_page, achievements_page, info_page]:
		p.visible = p == page


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


func _toggle_frame(sheet: Texture2D, frame: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(Vector2(TOGGLE_FRAME.x * frame, 0), TOGGLE_FRAME)
	return atlas


func _refresh() -> void:
	name_label.text = PetBrain.pet_name
	state_label.text = PetBrain.get_state()
	value_label.text = "Mood: %d / 100" % int(PetBrain.mood)
	background.texture = NightTexture if PetBrain.sleeping else DayTexture
	var sheet := SunSheet if PetBrain.sleeping else MoonSheet
	sleep_button.texture_normal = _toggle_frame(sheet, 0)
	sleep_button.texture_hover = _toggle_frame(sheet, 1)
	sleep_button.texture_pressed = sleep_button.texture_hover
	field_panda.visible = not PetBrain.sleeping
