# =====================================================================================
# pet_picker.gd  -  THE PET SELECTION GRID IN THE GODOT GAME
# =====================================================================================
# What this file does:
#   Shows the "Choose your pet" screen: a grid of pets, each shown with its own splash
#   art (2 per row by default, so 6 pets make 3 rows; it scrolls if there are more than
#   fit). Tapping a pet's splash art chooses that pet, saves the choice and goes
#   straight to the pet. While the grid is open the pet (or its egg) is hidden.
#
#   With the main menu (main_menu.gd on a "MainMenu" node): the grid is opened by the
#   menu's Pet Selection button, shows on top of the menu's animated background, and
#   its Back button returns to the menu.
#   Without a main menu: it adds its own "Change pet" and "Wallpaper" buttons in the
#   top-left corner and opens by itself on the very first start, as before.
#
# Where it goes:
#   On a CanvasLayer node called "PetPicker", added as a child of "Main" (next to "Pet").
#   It reads the list of pets from PETS in pet.gd, so new pets appear here by themselves.
#
# Splash art:
#   One picture per pet in res://menu/splash/, named after the pet's id in PETS:
#   dragon.png, cat.png, ... (PNG, JPG or WebP). A pet without splash art shows its
#   first idle frame instead, so the grid works before the art is ready.
#
# How to find things:
#   [EDIT]  = a setting you can safely change (text, sizes, positions)
#   [LOGIC] = what leads to what
#   [FIX]   = places to look first if something goes wrong
#
# Sections in this file:
#   1. Settings                                      -> search "SECTION 1"
#   2. Start-up                                      -> search "SECTION 2"
#   3. Its own buttons (only without a main menu)    -> search "SECTION 3"
#   4. The pet grid                                  -> search "SECTION 4"
#   5. One pet's tile (splash art)                   -> search "SECTION 5"
#   6. Helpers                                       -> search "SECTION 6"
# =====================================================================================

extends CanvasLayer

# The main menu listens to these to know what the player did.
signal pet_chosen(id: String)       # a pet was picked
signal cancelled                    # the grid was closed without picking

# ===== SECTION 1: SETTINGS ===========================================================
# [FIX] Where the Pet node is, seen from this node. "../Pet" = the Pet next to it.
@export var pet_path: NodePath = ^"../Pet"
# [EDIT] Without a main menu: open the grid by itself the first time the game starts
#        (only if there's more than one pet to choose from).
@export var ask_on_first_start := true
# [EDIT] Text on the screens and buttons.
@export var title_text := "Choose your pet"
@export var back_button_text := "Back"
@export var change_button_text := "Change pet"
@export var wallpaper_button_text := "Wallpaper"
# [EDIT] The folder with the pets' splash art: one picture per pet, named after the
#        pet's id in PETS (pet.gd), e.g. nocti.png for "nocti".
const SPLASH_FOLDER := "res://menu/splash"
# [EDIT] Grid layout: how many pets per row, and the size of each pet's tile (pixels of
#        the 720-wide screen). 3 x 210px with the 12 pets = 4 rows, no scrolling.
#        For 2 per row use columns 2 and TILE_SIZE Vector2(300, 330).
#        Splash art drawn in the tile's shape (here 210 x 240; draw it at 420 x 480 so
#        it stays sharp on phones) fills its tile exactly; other shapes are cut to fit,
#        never stretched.
@export var columns := 3
const TILE_SIZE := Vector2(210, 240)
const GAP := 16
const FONT_SIZE := 28
# [EDIT] Show each pet's name over the bottom of its splash art. Set to false if the
#        name is already part of your splash art.
@export var show_names := true
# [EDIT] The frame around every tile, and around the pet that is chosen now.
const TILE_EDGE_COLOR := Color(1, 1, 1, 0.55)
const CURRENT_EDGE_COLOR := Color(1.0, 0.78, 0.25)
const TILE_EDGE_WIDTH := 4
const CURRENT_EDGE_WIDTH := 8
# [EDIT] Without a main menu: the picture behind the grid. It is the picture the
#        wallpaper uses as the Project P wallpaper. With a main menu, the menu's own
#        animated background is behind the grid instead.
const BACKGROUND_PICTURE := "res://addons/projectp_wallpaper/default_wallpaper.png"
# [EDIT] How much the background is darkened so the pets and text stand out:
#        0 = not at all, 1 = black.
const BACKGROUND_DARKEN := 0.3
# [EDIT] Colour of the dark edge around the title and names, which keeps them readable.
const TITLE_EDGE_COLOR := Color(0.23, 0.15, 0.10)
# [EDIT] true = splash art and the background are drawn smooth (right for painted
#        art). Set to false if your splash art is pixel art.
const SMOOTH_PICTURES := true
# The part of the Android app that opens the wallpaper setup (WallpaperBridge.kt).
# It only exists in the app exported with the Project P Wallpaper add-on.
const WALLPAPER_PLUGIN := "ProjectPWallpaper"
# Kinds of picture files that are accepted as splash art.
const PICTURE_TYPES := ["png", "jpg", "jpeg", "webp"]
# Same save file as pet.gd; the chosen pet is stored under [game] chosen_pet.
const SAVE_PATH := "user://pet.cfg"

@onready var pet: Node2D = get_node(pet_path)
var _panel: Control = null          # the open grid (null = closed)
var _own_buttons: Control = null    # "Change pet" and "Wallpaper" (only without a menu)
var _menu_mode := false             # true when a main menu is in charge

# ===== SECTION 2: START-UP ===========================================================
func _ready() -> void:
	layer = 10                      # above the main menu (layer 5)
	_add_own_buttons()
	# Wait until every node is ready (so pet.gd has loaded its first pet and the main
	# menu, if there is one, has taken charge), then switch to the saved pet.
	_apply_saved_choice.call_deferred()

# Called by main_menu.gd: the menu takes charge, so this script's own buttons and its
# opening by itself on the first start are switched off.
func set_menu_mode(on: bool) -> void:
	_menu_mode = on
	if _own_buttons != null:
		_own_buttons.visible = not on

# Switches to the pet the player chose last time. Without a main menu it also opens
# the grid on the very first start.
func _apply_saved_choice() -> void:
	var chosen := ""
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		chosen = cfg.get_value("game", "chosen_pet", "")
	if chosen != "" and _pets().has(chosen):
		if chosen != pet.get("pet_id"):
			pet.set_pet(chosen)
	elif ask_on_first_start and not _menu_mode and _pets().size() > 1:
		open_picker()

# ===== SECTION 3: ITS OWN BUTTONS (ONLY WITHOUT A MAIN MENU) =========================
# [EDIT] Change position (top-left corner, 16px in), spacing or font size here.
func _add_own_buttons() -> void:
	var column := VBoxContainer.new()   # stacks the buttons under each other
	column.position = Vector2(16, 16)
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	_own_buttons = column

	var b := Button.new()
	b.text = change_button_text
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(open_picker)
	b.visible = _pets().size() > 1      # no point showing it with only one pet
	column.add_child(b)

	# "Wallpaper": opens the wallpaper setup. Only shown where it can work (the phone).
	var w := Button.new()
	w.text = wallpaper_button_text
	w.add_theme_font_size_override("font_size", 28)
	w.pressed.connect(open_wallpaper_setup)
	w.visible = Engine.has_singleton(WALLPAPER_PLUGIN)
	column.add_child(w)

# Opens the wallpaper setup screens (pet on the home screen and lock screen).
# Other scripts can call it too, e.g. $PetPicker.open_wallpaper_setup()
# [FIX] Nothing happens on the phone: export with the add-on enabled and Use Gradle
#       Build on (see the guide, Part C).
func open_wallpaper_setup() -> void:
	if Engine.has_singleton(WALLPAPER_PLUGIN):
		Engine.get_singleton(WALLPAPER_PLUGIN).openWallpaperSetup()

# ===== SECTION 4: THE PET GRID =======================================================
# Opens the grid: a title, one splash-art tile per pet, and a Back button.
# Other scripts can open it too, e.g. $PetPicker.open_picker()
func open_picker() -> void:
	if _panel != null:
		return                         # already open
	_set_pet_shown(false)              # the pet (or its egg) is hidden during selection
	# Overlay over the whole screen; it also stops taps reaching anything behind it.
	# With a main menu it only darkens the menu's background a little. Without one it
	# shows its own picture (or a dark screen if that picture is missing).
	var picture: Texture2D = null if _menu_mode else _background_picture()
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, BACKGROUND_DARKEN if _menu_mode else 0.85)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_panel = overlay
	if picture != null:
		# The picture fills the screen without stretching (edges that don't fit are cut)
		var bg := TextureRect.new()
		bg.texture = picture
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if SMOOTH_PICTURES:
			bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		overlay.add_child(bg)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, BACKGROUND_DARKEN)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	# A dark edge around the letters so the title reads on any background
	title.add_theme_color_override("font_outline_color", TITLE_EDGE_COLOR)
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)

	# The grid of pets: one tile per pet in PETS (pet.gd, SECTION 0), so it grows
	# by itself when pets are added.
	var pets := _pets()
	var cols := clampi(pets.size(), 1, columns)   # fewer pets than columns: stay centred
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	for id in pets:
		grid.add_child(_make_tile(String(id), String(pets[id])))
	if pets.is_empty():
		# Nothing to choose from: say why on the screen instead of an empty grid.
		# [FIX] This shows when pet.gd has an error (red lines in Godot's Output panel,
		#       the Pet node then has no working script) or its PETS list is empty.
		var problem := Label.new()
		problem.text = "No pets found.\npet.gd has an error or its PETS list is empty.\n" \
			+ "Look for red lines in Godot's Output panel."
		problem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		problem.add_theme_font_size_override("font_size", FONT_SIZE)
		problem.add_theme_color_override("font_outline_color", TITLE_EDGE_COLOR)
		problem.add_theme_constant_override("outline_size", 8)
		box.add_child(problem)

	# Put the grid in a scroll area. It's only as tall as the grid needs, up to the
	# screen height minus room for the title and Back; beyond that it scrolls.
	# [EDIT] 220 = space kept free for the title and the Back button.
	var rows := ceili(pets.size() / float(cols))
	var grid_height := rows * TILE_SIZE.y + maxi(rows - 1, 0) * GAP
	var max_height := get_viewport().get_visible_rect().size.y - 220
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(
		cols * TILE_SIZE.x + (cols - 1) * GAP, minf(grid_height, max_height))
	scroll.add_child(grid)
	box.add_child(scroll)

	var back := Button.new()
	back.text = back_button_text
	back.add_theme_font_size_override("font_size", FONT_SIZE)
	back.pressed.connect(close_picker)
	box.add_child(back)

# Closes the grid without changing the pet.
# [LOGIC] With a main menu: back to the menu (the pet stays hidden).
#         Without one: back to the pet.
func close_picker() -> void:
	if _panel == null:
		return
	_panel.queue_free()
	_panel = null
	if not _menu_mode:
		_set_pet_shown(true)
	cancelled.emit()

func is_open() -> bool:
	return _panel != null

# [LOGIC] The player tapped a pet's splash art: switch to that pet, remember the
#         choice, close the grid and go to the pet.
func _choose(id: String) -> void:
	pet.set_pet(id)
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)               # keep the pets' data already in the file
	cfg.set_value("game", "chosen_pet", id)
	cfg.save(SAVE_PATH)
	if _panel != null:
		_panel.queue_free()
		_panel = null
	_set_pet_shown(true)
	pet_chosen.emit(id)               # the main menu closes itself when it hears this

# ===== SECTION 5: ONE PET'S TILE =====================================================
# A tile is a button filled with the pet's splash art, a frame around it, and the
# pet's name over the bottom (if show_names is on). The pet chosen now gets a thicker
# frame in another colour.
# [FIX] A tile shows a small pet frame instead of your splash art: the picture isn't in
#       SPLASH_FOLDER, or its name isn't exactly the pet's id in PETS (dragon.png for
#       "nocti", same small letters).
func _make_tile(id: String, folder: String) -> Control:
	var tile := Button.new()
	tile.flat = true                                      # no grey button look
	tile.custom_minimum_size = TILE_SIZE
	tile.clip_contents = true
	tile.pressed.connect(_choose.bind(id))
	# Darken the tile a little while a finger is on it
	tile.button_down.connect(func(): tile.modulate = Color(0.75, 0.75, 0.75))
	tile.button_up.connect(func(): tile.modulate = Color.WHITE)

	var splash := _splash_for(id)
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if splash != null:
		art.texture = splash
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED   # fill the tile
		if SMOOTH_PICTURES:
			art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		# No splash art yet: a soft panel with the pet's first idle frame in the middle
		var plain := ColorRect.new()
		plain.color = Color(0, 0, 0, 0.35)
		plain.set_anchors_preset(Control.PRESET_FULL_RECT)
		plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(plain)
		art.texture = _picture_for(folder)
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tile.add_child(art)

	# The frame around the tile (thicker and coloured for the pet chosen now)
	var is_current: bool = (id == pet.get("pet_id"))
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color(0, 0, 0, 0)
	edge.border_color = CURRENT_EDGE_COLOR if is_current else TILE_EDGE_COLOR
	edge.set_border_width_all(CURRENT_EDGE_WIDTH if is_current else TILE_EDGE_WIDTH)
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", edge)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(frame)

	if show_names or splash == null:
		var name_label := Label.new()
		name_label.text = id.capitalize()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", FONT_SIZE)
		name_label.add_theme_color_override("font_outline_color", TITLE_EDGE_COLOR)
		name_label.add_theme_constant_override("outline_size", 8)
		name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		name_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		name_label.offset_bottom = -14
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(name_label)
	return tile

# ===== SECTION 6: HELPERS ============================================================
# The pet list (PETS) from pet.gd, so this script never needs its own copy.
# Empty if pet.gd isn't on the Pet node or has an error.
func _pets() -> Dictionary:
	var script = pet.get_script()
	if not (script is Script) or not pet.has_method("set_pet"):
		return {}
	var pets = script.get_script_constant_map().get("PETS", {})
	return pets if pets is Dictionary else {}

# Shows or hides the pet. A hidden pet is also paused, so it doesn't wander off or
# react to taps while the grid is in front of it.
func _set_pet_shown(shown: bool) -> void:
	pet.visible = shown
	pet.process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED

# A pet's splash art: SPLASH_FOLDER/<id>.png (or .jpg, .jpeg, .webp); null if none.
func _splash_for(id: String) -> Texture2D:
	for type in PICTURE_TYPES:
		var path := "%s/%s.%s" % [SPLASH_FOLDER, id, type]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

# The picture behind the grid when there is no main menu (null if the file isn't there).
func _background_picture() -> Texture2D:
	if ResourceLoader.exists(BACKGROUND_PICTURE):
		return load(BACKGROUND_PICTURE) as Texture2D
	return null

# The stand-in for missing splash art: the pet's first idle frame (or its egg).
# [FIX] No picture at all? Check that pet's frames load in the game (Output panel).
func _picture_for(folder: String) -> Texture2D:
	var groups: Dictionary = pet._frame_groups(folder)
	for anim in ["pet_idle", "egg_idle"]:
		var paths: Array = groups.get(anim, [])
		if not paths.is_empty():
			return load(paths[0])
	return null
