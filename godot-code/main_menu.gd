# =====================================================================================
# main_menu.gd  -  THE MAIN MENU (the first screen when the app opens)
# =====================================================================================
# What this file does:
#   Shows the main menu as soon as the game starts:
#     - your animated background (16 frames, or however many you put in the folder),
#     - a "Pet Selection" button    -> opens the pet grid (pet_picker.gd); choosing a
#                                      pet closes the menu and shows that pet,
#     - a "Wallpaper Selection" button -> opens the wallpaper setup on the phone,
#     - a "Dojo" button             -> the battle (battle/battle.tscn), in landscape,
#                                      with the pet that is chosen now.
#   Each button plays its own frames (3 by default) when it is tapped or clicked, and
#   then does its job.
#   While the menu or the pet grid is open, the pet (or its egg) is hidden and paused.
#   On the pet's screen a small "Menu" button (top left) brings the menu back. On the
#   phone, the Back button does the same: pet -> menu, pet grid -> menu, menu -> exit.
#
# Where it goes:
#   On a CanvasLayer node called "MainMenu", added as a child of "Main" (next to "Pet"
#   and "PetPicker"). If the scene has no "PetPicker" node, the menu makes one itself
#   from pet_picker.gd, so that file only has to be in the project.
#
# Your pictures (all optional; without them plain buttons and a plain colour are used):
#   res://menu/background/   bg_00.jpg ... bg_15.jpg         the animated background
#   res://menu/buttons/      pet_selection_00.png ... _02.png        Pet Selection
#                            wallpaper_selection_00.png ... _02.png  Wallpaper Selection
#                            menu_00.png ... _02.png          the small Menu button
#                            dojo_00.png ... _02.png          Dojo
#   res://menu/splash/       dragon.png, cat.png ...          see pet_picker.gd
#
# How to find things:
#   [EDIT]  = a setting you can safely change (folders, sizes, speeds, texts)
#   [LOGIC] = what leads to what
#   [FIX]   = places to look first if something goes wrong
#
# Sections in this file:
#   1. Settings                                      -> search "SECTION 1"
#   2. Start-up                                      -> search "SECTION 2"
#   3. Opening and closing the menu                  -> search "SECTION 3"
#   4. The animated background                       -> search "SECTION 4"
#   5. The buttons and their press animation         -> search "SECTION 5"
#   6. What the buttons do                           -> search "SECTION 6"
#   7. The phone's Back button                       -> search "SECTION 7"
#   8. Helpers                                       -> search "SECTION 8"
# =====================================================================================

extends CanvasLayer

# ===== SECTION 1: SETTINGS ===========================================================
# [FIX] Where the Pet and PetPicker nodes are, seen from this node.
@export var pet_path: NodePath = ^"../Pet"
@export var picker_path: NodePath = ^"../PetPicker"
# [EDIT] The pet grid's script. If the scene has no PetPicker node, the menu makes one
#        itself from this file, so the Pet Selection button always has a grid to open.
const PICKER_SCRIPT := "res://pet_picker.gd"

# --- Background ---
# [EDIT] The folder with the background frames. They are played in the order of their
#        names (bg_00, bg_01, ... bg_15). JPG, PNG or WebP. One picture = a still
#        background.
const BACKGROUND_FOLDER := "res://menu/background"
# [EDIT] Speed of the background, in frames per second. 16 frames at 8 = a 2-second loop.
@export var background_fps := 8.0
# [EDIT] Colour shown if there are no background pictures.
const BACKGROUND_COLOR := Color(0.95, 0.89, 0.81)

# --- Buttons ---
# [EDIT] The folder with the button pictures, and each button's file name. A button's
#        frames are <name>_00.png (how it looks at rest), <name>_01.png, <name>_02.png
#        (being pressed). More or fewer frames work too: _00 up to _09.
const BUTTON_FOLDER := "res://menu/buttons"
const PET_BUTTON := "pet_selection"
const WALLPAPER_BUTTON := "wallpaper_selection"
const MENU_BUTTON := "menu"
const DOJO_BUTTON := "dojo"
# [EDIT] The battle scene the Dojo button opens.
const BATTLE_SCENE := "res://battle/battle.tscn"
# [EDIT] How wide the two big buttons are drawn, in pixels of the 720-wide screen. The
#        height follows from your picture's shape.
@export var button_width := 440.0
# [EDIT] Space between the two buttons.
@export var button_gap := 28
# [EDIT] Where the pair of buttons sits: 0.5 = middle of the screen, 0.68 = lower part,
#        0.8 = near the bottom.
@export var buttons_center_y := 0.68
# [EDIT] Speed of the press animation, in frames per second. 3 frames at 12 = a quarter
#        of a second before the button does its job.
@export var press_fps := 12.0
# [EDIT] Width of the small "Menu" button on the pet's screen.
@export var menu_button_width := 150.0
# [EDIT] Text on the buttons when they have no pictures yet.
@export var pet_button_text := "Pet Selection"
@export var wallpaper_button_text := "Wallpaper Selection"
@export var menu_button_text := "Menu"
@export var dojo_button_text := "Dojo"
# [EDIT] Message shown when Wallpaper Selection is used on the computer.
@export var computer_notice := "The wallpaper setup opens on the phone."

# [EDIT] true = the menu's pictures are drawn smooth (right for painted art). Set to
#        false if your menu art is pixel art and should keep hard pixel edges.
const SMOOTH_PICTURES := true

# The part of the Android app that opens the wallpaper setup (WallpaperBridge.kt). It
# only exists in the app exported with the Project P Wallpaper add-on.
const WALLPAPER_PLUGIN := "ProjectPWallpaper"
# Kinds of picture files that are accepted.
const PICTURE_TYPES := ["png", "jpg", "jpeg", "webp"]

@onready var pet: Node2D = get_node_or_null(pet_path)
@onready var picker: Node = get_node_or_null(picker_path)

var _root: Control = null            # everything of the menu (background + buttons)
var _background: TextureRect = null  # shows the current background frame
var _buttons: Control = null         # holds the two big buttons
var _menu_button: BaseButton = null  # the small "Menu" button on the pet's screen
var _notice: Label = null            # the message for computer users
var _open := false                   # is the menu on screen?
var _bg_paths: Array = []            # the background frame files, in order
var _bg_frames: Array = []           # the frames loaded so far
var _bg_time := 0.0                  # seconds the background has been playing
var _button_busy := false            # a button's press animation is playing

# ===== SECTION 2: START-UP ===========================================================
func _ready() -> void:
	layer = 5                        # above the game, below the pet grid (layer 10)
	_bg_paths = _picture_files(BACKGROUND_FOLDER)
	_build_menu()
	# The pet grid belongs to the menu. No PetPicker node in the scene: make one.
	if picker == null:
		_make_picker()
	else:
		_connect_picker()
	# On the phone, the Back button is handled in SECTION 7 instead of closing the app.
	get_tree().quit_on_go_back = false
	open_menu()                      # the app starts on the menu
	print("Project P: main menu ready, %d background frames." % _bg_paths.size())

# Makes the PetPicker node (a CanvasLayer with pet_picker.gd) next to this node.
# It is added a moment later, because the scene is still being set up right now.
# [FIX] "pet_picker.gd not found": put pet_picker.gd in the project's top folder, next
#       to pet.gd, or change PICKER_SCRIPT (SECTION 1) to where it is.
func _make_picker() -> void:
	if not ResourceLoader.exists(PICKER_SCRIPT):
		push_warning("Project P: no PetPicker node, and %s not found." % PICKER_SCRIPT)
		return
	var made := CanvasLayer.new()
	made.name = "PetPicker"
	made.set_script(load(PICKER_SCRIPT))
	picker = made
	get_parent().add_child.call_deferred(made)
	_connect_picker.call_deferred()
	print("Project P: main menu made its own PetPicker node from %s." % PICKER_SCRIPT)

# Tells the pet grid that the menu is in charge, and listens to what the player does.
func _connect_picker() -> void:
	if picker.has_method("set_menu_mode"):
		picker.set_menu_mode(true)
	if picker.has_signal("pet_chosen") and not picker.pet_chosen.is_connected(_on_pet_chosen):
		picker.pet_chosen.connect(_on_pet_chosen)
	if picker.has_signal("cancelled") and not picker.cancelled.is_connected(_on_picker_cancelled):
		picker.cancelled.connect(_on_picker_cancelled)

# Builds the menu's parts once. They are shown and hidden later.
func _build_menu() -> void:
	# Covers the whole screen and stops taps from reaching the pet
	_root = ColorRect.new()
	_root.color = BACKGROUND_COLOR
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	if SMOOTH_PICTURES:
		_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # also for everything in it
	add_child(_root)

	# The background picture: fills the screen without stretching (edges that don't
	# fit are cut off evenly)
	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_background)

	# The two big buttons, one under the other, centred sideways
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", button_gap)
	column.add_child(_make_button(PET_BUTTON, pet_button_text, button_width,
		_open_pet_selection))
	column.add_child(_make_button(WALLPAPER_BUTTON, wallpaper_button_text, button_width,
		_open_wallpaper_selection))
	column.add_child(_make_button(DOJO_BUTTON, dojo_button_text, button_width, _open_dojo))
	# A thin strip across the screen at the chosen height; the buttons are centred on it
	var holder := CenterContainer.new()
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = buttons_center_y
	holder.anchor_bottom = buttons_center_y
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(column)
	_root.add_child(holder)
	_buttons = holder

	# The message for computer users (hidden until needed)
	_notice = Label.new()
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long messages wrap
	_notice.add_theme_font_size_override("font_size", 28)
	_notice.add_theme_color_override("font_outline_color", Color(0.2, 0.13, 0.09))
	_notice.add_theme_constant_override("outline_size", 10)
	_notice.anchor_left = 0.0
	_notice.anchor_right = 1.0
	_notice.anchor_top = 0.9
	_notice.anchor_bottom = 0.9
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.visible = false
	_root.add_child(_notice)

	# The small "Menu" button on the pet's screen (top left)
	# [EDIT] Change its position here (16 pixels in from the top-left corner).
	_menu_button = _make_button(MENU_BUTTON, menu_button_text, menu_button_width, open_menu)
	_menu_button.position = Vector2(16, 16)
	if SMOOTH_PICTURES:
		_menu_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_menu_button)

# ===== SECTION 3: OPENING AND CLOSING THE MENU =======================================
# Shows the menu and hides the pet. Other scripts can call it: $MainMenu.open_menu()
func open_menu() -> void:
	_open = true
	_root.visible = true
	_buttons.visible = true
	_menu_button.visible = false
	_set_pet_shown(false)            # the pet (or its egg) is never visible on the menu
	_start_background()

# Hides the menu and shows the pet.
func close_menu() -> void:
	_open = false
	_root.visible = false
	_menu_button.visible = true
	_set_pet_shown(true)
	# Give the background's memory back while the player is with the pet
	_bg_frames.clear()
	_background.texture = null

func is_open() -> bool:
	return _open

# Shows or hides the pet. A hidden pet is also paused, so it doesn't wander off or
# react to taps while the menu is in front of it.
func _set_pet_shown(shown: bool) -> void:
	if pet == null:
		return
	pet.visible = shown
	pet.process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED

# ===== SECTION 4: THE ANIMATED BACKGROUND ============================================
# [LOGIC] The first frame is shown at once. The others are loaded one per moment
#         while the menu is already on screen, so opening the menu never stalls. When
#         all are loaded, they play in a loop at background_fps.
# [FIX] Plain colour instead of your pictures: check they are in BACKGROUND_FOLDER
#       and read the "Project P: main menu ready" line in the Output panel.
func _start_background() -> void:
	_bg_time = 0.0
	if _bg_frames.is_empty() and not _bg_paths.is_empty():
		_bg_frames.append(load(_bg_paths[0]))
	if not _bg_frames.is_empty():
		_background.texture = _bg_frames[0]

func _process(delta: float) -> void:
	if not _root.visible or _bg_paths.is_empty():
		return
	if _bg_frames.size() < _bg_paths.size():
		_bg_frames.append(load(_bg_paths[_bg_frames.size()]))   # one more frame
		return
	if _bg_frames.size() > 1:
		_bg_time += delta
		var index := int(_bg_time * background_fps) % _bg_frames.size()
		_background.texture = _bg_frames[index]

# ===== SECTION 5: THE BUTTONS AND THEIR PRESS ANIMATION ==============================
# Makes one button. With pictures (<name>_00.png, _01, _02 in BUTTON_FOLDER) it is a
# picture button that plays its frames when pressed; without them it is a plain button
# with text, so the menu works before your art is ready.
# `action` is what the button does after its animation.
func _make_button(file_name: String, text: String, width: float,
		action: Callable) -> BaseButton:
	var frames := _button_frames(file_name)
	if frames.is_empty():
		var plain := Button.new()
		plain.text = text
		plain.add_theme_font_size_override("font_size", 30)
		plain.custom_minimum_size = Vector2(width, 0)
		plain.pressed.connect(action)
		return plain
	var b := TextureButton.new()
	b.texture_normal = frames[0]
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var picture_size: Vector2 = frames[0].get_size()
	b.custom_minimum_size = Vector2(width, width * picture_size.y / picture_size.x)
	b.size = b.custom_minimum_size
	b.pressed.connect(_play_button.bind(b, frames, action))
	return b

# [LOGIC] A tap or click plays the button's frames in order (_01, _02, ...), goes back
#         to _00, and then does the button's job. Other taps are ignored meanwhile.
func _play_button(b: TextureButton, frames: Array, action: Callable) -> void:
	if _button_busy:
		return
	_button_busy = true
	for i in range(1, frames.size()):
		b.texture_normal = frames[i]
		await get_tree().create_timer(1.0 / press_fps).timeout
	b.texture_normal = frames[0]
	_button_busy = false
	action.call()

# A button's frames: <name>_00, <name>_01, ... as far as they exist (empty if none).
func _button_frames(file_name: String) -> Array:
	var frames := []
	for i in range(10):
		var found := _find_picture(BUTTON_FOLDER.path_join("%s_%02d" % [file_name, i]))
		if found == "":
			break
		frames.append(load(found))
	return frames

# ===== SECTION 6: WHAT THE BUTTONS DO ================================================
# [LOGIC] Pet Selection: the buttons step aside and the pet grid opens on top of the
#         animated background. Choosing a pet -> the menu closes and that pet is shown.
#         "Back" in the grid -> the menu's buttons return.
# [FIX] The button shows a message instead of the grid: the message says what is
#       missing. The grid is the "PetPicker" node with pet_picker.gd on it; if the scene
#       has none, the menu makes it from PICKER_SCRIPT (SECTION 1).
func _open_pet_selection() -> void:
	if picker == null:
		_show_notice("Pet grid not found: put pet_picker.gd next to pet.gd (step A5).")
		return
	if not picker.has_method("open_picker") or not picker.has_signal("pet_chosen"):
		_show_notice("The PetPicker node needs the new pet_picker.gd on it (step A5).")
		return
	_buttons.visible = false
	picker.open_picker()

func _on_pet_chosen(_id: String) -> void:
	close_menu()                     # straight to the chosen pet

func _on_picker_cancelled() -> void:
	if _open:
		_buttons.visible = true      # back to the two buttons

# [LOGIC] Wallpaper Selection: opens the wallpaper setup screens on the phone (keep
#         your wallpaper or use the Project P wallpaper). The menu stays open behind.
# [FIX] Nothing happens on the phone: export with the Project P Wallpaper add-on
#       enabled and Use Gradle Build on (see the guide, Part C).
func _open_wallpaper_selection() -> void:
	if Engine.has_singleton(WALLPAPER_PLUGIN):
		Engine.get_singleton(WALLPAPER_PLUGIN).openWallpaperSetup()
	else:
		_show_notice(computer_notice)

# [LOGIC] Dojo: the chosen pet fights a random other pet (battle/battle_screen.gd).
#         The phone turns to landscape for the fight and back to portrait after.
# [FIX] "Battle scene not found": battle/battle.tscn must be in the project.
func _open_dojo() -> void:
	if not ResourceLoader.exists(BATTLE_SCENE):
		_show_notice("Battle scene not found: %s" % BATTLE_SCENE)
		return
	var current: String = pet.get("pet_id") if pet != null else ""
	var data := get_node_or_null("/root/GameData")
	if data != null:
		data.battle_request = {"player": current, "opponent": ""}
	get_tree().change_scene_to_file(BATTLE_SCENE)

# Shows a short message near the bottom of the menu for a few seconds.
func _show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = true
	await get_tree().create_timer(4.0).timeout
	if _notice.text == text:           # (not replaced by a newer message meanwhile)
		_notice.visible = false

# ===== SECTION 7: THE PHONE'S BACK BUTTON ============================================
# [LOGIC] Back on the pet grid -> the menu. Back on the pet's screen -> the menu.
#         Back on the menu -> closes the app.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if picker != null and picker.has_method("is_open") and picker.is_open():
		picker.close_picker()
	elif _open:
		get_tree().quit()
	else:
		open_menu()

# ===== SECTION 8: HELPERS ============================================================
# All picture files in a folder, in the order of their names (full paths).
# Works in the editor and in exported games, where Godot keeps only "<name>.import".
func _picture_files(folder: String) -> Array:
	var result := []
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	for f in dir.get_files():
		var fname := f.trim_suffix(".import").trim_suffix(".remap")
		if fname.get_extension().to_lower() in PICTURE_TYPES:
			var path := folder.path_join(fname)
			if not result.has(path) and ResourceLoader.exists(path):
				result.append(path)
	result.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	return result

# The picture file with this name, whatever its type ("" if there is none).
# `path_without_type` is e.g. "res://menu/buttons/menu_00".
func _find_picture(path_without_type: String) -> String:
	for type in PICTURE_TYPES:
		var path := "%s.%s" % [path_without_type, type]
		if ResourceLoader.exists(path):
			return path
	return ""
