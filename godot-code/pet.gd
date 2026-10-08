# =====================================================================================
# pet.gd  -  THE PET IN THE GODOT GAME
# =====================================================================================
# What this file does:
#   Controls the pet inside the game: plays its animations, hatches the egg after a
#   few taps, plays the tickle animation when the hatched pet is tapped, lets the
#   player drag it around and resize it (pinch or mouse wheel), and remembers its
#   position, size and whether it has hatched. By itself the pet mostly rests and
#   blinks, and now and then does one thing picked at random from ACTIONS (SECTION 0):
#   travels left or right, hops, plays one of its tricks, or just keeps blinking.
#   On a low battery it does its low-energy movements instead, and at night it sleeps
#   until it is tapped (LOW ENERGY and SLEEP in SECTION 0).
#
# Where it goes:
#   Attached to the "Pet" node (Node2D), with a child AnimatedSprite2D.
#   The script builds the animations from the pet's frame folder by itself when the
#   game starts, so the AnimatedSprite2D's Sprite Frames slot can stay empty.
#   In the editor it shows the first egg frame as a preview, so you can see the pet
#   while building the scene.
#
# IMPORTANT: add this file to Godot as a file (drag pet.gd into the FileSystem panel).
#   Don't copy the code out of the PDF guide: PDFs lose the tab indentation that
#   GDScript needs, and the script then fails without showing the pet.
#
# >>> HOW TO ADD A NEW PET (Godot) <<<
#   1. Export its frames as separate PNGs (see "Frame file names" in SECTION 0).
#   2. Put them in their own folder in the project, e.g. res://pets/cat/
#      (subfolders inside it are fine, e.g. res://pets/cat/frames/).
#   3. Add one line to PETS below, e.g.  "cat": "res://pets/cat",
#   4. To show it, set the Pet node's "Pet Id" in the Inspector to "cat"
#      (or call set_pet("cat") from another script).
#   Also add the pet to PetCatalog.kt in the Android wallpaper app.
#
# How to find things:
#   [EDIT]  = a setting you can safely change
#   [LOGIC] = rules for how the pet behaves (what plays after what)
#   [FIX]   = places to look first if something goes wrong
#   [ADD PET] = where new pets go
#   [ADD ACTION] = where new movements the pet does by itself go
#
# Sections in this file:
#   0. Pets and animations ([ADD PET] is here)       -> search "SECTION 0"
#   1. Settings                                      -> search "SECTION 1"
#   2. Pet state                                     -> search "SECTION 2"
#   3. Start-up                                      -> search "SECTION 3"
#   4. Touch: tap and drag                           -> search "SECTION 4"
#   4b. Resizing: pinch / mouse wheel                -> search "SECTION 4b"
#   4c. What the pet does by itself (ACTIONS)        -> search "SECTION 4c"
#   5. Animation rules (hatch, tickle, jump/landing) -> search "SECTION 5"
#   6. Helpers (screen position, keep on screen)     -> search "SECTION 6"
#   7. Saving and loading                            -> search "SECTION 7"
#   8. Building animations from a frame folder       -> search "SECTION 8"
#   9. Editor preview                                -> search "SECTION 9"
#
# Animation names: egg_idle, egg_hatch, pet_emerge, pet_idle, jump, landing, ticklish,
#   recovery, move, move_left, move_right, trick, low_energy, sleep. Inside the game's
#   app the Android wallpaper gets ANIMS, ACTIONS and the low-energy and sleep settings
#   from this file on every export, so the two always match.
# =====================================================================================

@tool   # lets the script draw a preview of the pet in the editor (SECTION 9)
extends Node2D

# ===== SECTION 0: PETS AND ANIMATIONS ================================================
# [ADD PET] One line per pet: "id": "folder with its frame PNGs".
#           The id is used in saved data, so don't change it after release.
#           Keep this list in sync with PETS in PetCatalog.kt (Android).
#           If the folder isn't found, the script also searches the project for a
#           folder named like the id (e.g. any folder called "dragon") and says so.
const PETS := {
	"dragon": "res://pets/dragon",
	# "cat": "res://pets/cat",
	# "fox": "res://pets/fox",
}

# [EDIT] The animations: [name, frames, fps, loop, file names it accepts].
#   frames = how many frames it has when files are only numbered (see below)
#   file names = what this animation's files are called, without the frame number.
#                The pet's name in front is allowed: "idle" also matches dragon_idle_00,
#                owl_idle_00, cat_idle_00... Add your own names here if yours differ.
#   The order of this list is also the order of numbered files (1-8 egg_idle, ...).
#   pet_idle: 4 sets of 8 frames (idle_a .. idle_d), one blink each, played in a loop.
#   The wallpaper inside the game's app reads this list on every export.
const ANIMS := [
	["egg_idle", 8, 6.0, true, ["egg_idle"]],                   # egg_idle_00..07
	["egg_hatch", 8, 10.0, false, ["egg_hatch", "egg_hatch_emerge"]],   # egg_hatch_emerge_..
	["pet_emerge", 8, 10.0, false, ["pet_emerge", "emerge"]],   # dragon_emerge_00..07
	["pet_idle", 8, 8.0, true, ["pet_idle", "idle"]],           # idle_a_00..idle_d_07
	["jump", 8, 12.0, false, ["jump", "jump_land_a", "jump_landing_a"]],        # jump_land_a_..
	["landing", 8, 12.0, false, ["landing", "jump_land_b", "jump_landing_b"]],  # jump_land_b_..
	["ticklish", 8, 12.0, false, ["ticklish", "ticklish_recovery_a"]],      # ticklish_recovery_a_..
	["recovery", 8, 10.0, false, ["recovery", "ticklish_recovery_b"]],      # ticklish_recovery_b_..
	["move", 32, 12.0, true, ["move", "fly", "walk", "run", "hop"]],    # fly_a_.. / walk_a_..
	["move_left", 8, 12.0, true, ["move_left", "fly_left", "walk_left", "run_left"]],
	["move_right", 8, 12.0, true, ["move_right", "fly_right", "walk_right", "run_right"]],
	["trick", 16, 10.0, false, ["trick", "extra", "special", "dance"]],     # trick_a_.. trick_b_..
	["low_energy", 8, 8.0, false, ["low_energy", "low_battery", "tired"]],    # low_energy_..
	["sleep", 8, 6.0, true, ["sleep", "sleeping", "asleep"]],                 # sleep_00..
]

# [EDIT] WHAT THE PET DOES BY ITSELF. Most of the time the hatched pet rests and blinks
#        (pet_idle: 4 sets of 8 frames, one blink each). After a random wait it picks ONE
#        line below at random, does it, and goes back to resting and blinking.
#        One line per action: [what it does, animation, weight]
#          "blink"  = nothing new: it keeps resting and blinking (makes the idle longer)
#          "travel" = goes to a random spot on the left or right with this animation,
#                     facing the way it goes (fly_ frames bob in the air)
#          "hop"    = jumps up on the spot with this animation, then plays "landing"
#          "play"   = plays this animation once where it stands
#        weight = how often it is picked compared with the others: 4 is picked four
#                 times as often as 1. Use 0 to switch a line off.
#        An action whose animation has no frames for this pet is skipped.
# [ADD ACTION] To add your own movement:
#        1. Add its animation to ANIMS above, with loop = false, e.g.
#             ["spin", 8, 12.0, false, ["spin"]],        # spin_00..07
#        2. Add a line here, e.g.
#             ["play", "spin", 2],
#        The wallpaper picks both up from this file on the next export.
const ACTIONS := [
	["blink", "", 4],          # keep blinking a while longer
	["travel", "move", 3],     # fly / walk / run to the left or right
	["hop", "jump", 2],        # jump on the spot (jump, then landing)
	["play", "trick", 2],      # one of its tricks (see ANIM_SETS below)
]
# [EDIT] Seconds of resting and blinking between two actions (a random time in this range).
const ACTION_WAIT_MIN := 3.0
const ACTION_WAIT_MAX := 7.0
# [EDIT] How many frames one blink has. An action starts between two blinks, never in the
#        middle of one.
const BLINK_FRAMES := 8
# [EDIT] The hop on the spot: how high (as a share of the pet's height) and how long.
const HOP_HEIGHT := 0.5
const HOP_SECONDS := 0.7

# [EDIT] MOVEMENTS WITH SEVERAL VERSIONS. An animation listed here is not one long
#        movement but several separate ones in a row, each this many frames long: with
#        "trick": 8, trick_a_00..07 is one trick and trick_b_00..07 another. When the
#        pet plays it, it picks ONE version at random, plays just that one, and goes
#        back to resting. Add more rows of frames (trick_c_.., trick_d_..) and they
#        join the choice by themselves.
#        Remove a line to play that animation from its first to its last frame again.
const ANIM_SETS := {
	"trick": 8,
	"low_energy": 8,
}

# [EDIT] LOW ENERGY. When the phone's battery is at or below LOW_BATTERY_PERCENT and
#        the phone is not charging, the pet picks from this list instead of ACTIONS:
#        it does its low-energy movements instead of travelling, hopping and tricks.
#        Same kind of lines as ACTIONS. A pet without low_energy frames keeps ACTIONS.
const LOW_BATTERY_PERCENT := 15
const LOW_ENERGY_ACTIONS := [
	["blink", "", 3],              # keep blinking a while longer
	["play", "low_energy", 4],     # one of its low-energy movements
]

# [EDIT] SLEEP. Between these hours of the phone's clock (24-hour clock: 23 = 11 PM,
#        6 = 6 AM) the hatched pet sleeps: it plays "sleep" instead of pet_idle and
#        does nothing by itself. Tapping it wakes it up for AWAKE_MINUTES; every
#        further tap keeps it awake that long again. Then it goes back to sleep.
#        A pet without sleep frames never sleeps.
const SLEEP_FROM_HOUR := 23
const SLEEP_UNTIL_HOUR := 6
const AWAKE_MINUTES := 5.0

# Frame file names - any of these styles works:
#   A) Named by animation (what the sprite-sheet-slicer skill exports), e.g. the dragon:
#        egg_idle_00.png ... egg_idle_07.png       -> egg_idle
#        egg_hatch_emerge_00.png ... _07.png       -> egg_hatch (hatching and the pet
#                                                     coming out, as one animation)
#        Older sets with two animations also work: egg_hatch_00.. -> egg_hatch and
#        dragon_emerge_00.. -> pet_emerge, played one after the other.
#        idle_a_00.png ... idle_d_07.png           -> pet_idle (rows a, b, c, d in order)
#        jump_land_a_00.png ... _07.png            -> jump
#        jump_land_b_00.png ... _07.png            -> landing
#        ticklish_recovery_a_00.png ... _07.png    -> ticklish
#        ticklish_recovery_b_00.png ... _07.png    -> recovery
#        move_left_00.png ... / move_right_00.png ... -> move_left / move_right: used
#                                                     when the pet travels that way
#        fly_a_00.png ... fly_d_07.png             -> move (or walk_, run_, hop_): one set
#                                                     for both ways, mirrored as needed
#        trick_a_00.png ... trick_b_07.png         -> trick: each row is one trick, and
#                                                     one is picked at a time (ANIM_SETS)
#        low_energy_a_00.png ...                   -> low_energy: played on a low battery
#        sleep_00.png ...                          -> sleep: its resting animation at night
#      Each file goes to the animation whose name it matches (see ANIMS above).
#   B) Only numbered, in the order of ANIMS: 01.png ... 64.png, frame_1 ... frame_64.
#      The first 8 files go to egg_idle, the next 8 to egg_hatch, and so on.
# Numbers are compared as numbers, so frame_2 comes before frame_10.
# The Output panel says which style was found and how many frames each animation got.

# ===== SECTION 1: SETTINGS ===========================================================
# [EDIT] Which pet this node shows (an id from PETS). Change it in the Inspector.
@export var pet_id: String = "dragon":
	set(value):
		pet_id = value
		if Engine.is_editor_hint():
			queue_redraw()        # update the editor preview (SECTION 9)
# [EDIT] How close to the pet's centre a touch must land to grab it (in pixels).
#        Make it bigger if the pet is hard to grab.
# [EDIT] PET SIZE: 1 = the PNG's own size, 2 = twice as big. Starting size;
#        players can resize it by pinching (phone) or mouse wheel (PC), see SECTION 4b.
@export var pet_size: float = 2.0:
	set(value):
		pet_size = value
		scale = Vector2.ONE * pet_size
# [EDIT] Smallest and biggest size players can resize the pet to.
@export var min_size: float = 1.0
@export var max_size: float = 5.0
# [EDIT] How much one mouse-wheel step changes the size on PC.
const WHEEL_STEP := 0.25
# [EDIT] TRAVELLING: moving speed in pixels per second, and how high flying pets bob in
#        the air. Pets travel with their fly_, walk_, run_ or hop_ frames (whichever they
#        have); only pets with fly_ frames bob up and down.
#        How often the pet does something by itself is ACTION_WAIT_MIN / MAX in SECTION 0.
@export var move_speed := 180.0
@export var move_bob := 12.0
# [EDIT] Which way the pet faces in its moving frames. If it moves backwards, untick
#        this in the Inspector (or set it to false).
@export var move_frames_face_right := true
# [EDIT] Grab area at size 1 (multiplied by pet_size).
@export var grab_radius: float = 56.0
# [EDIT] How many taps on the egg before it hatches.
@export var taps_to_hatch: int = 3
# [EDIT] FOR TESTING: pretend the battery is at this percent (e.g. 10 to see the low-
#        energy movements) and pretend it is this hour (e.g. 23 to see the pet sleep).
#        -1 = use the real battery and the real clock. Set them in the Inspector and
#        put them back to -1 before you export.
@export var test_battery_percent: int = -1
@export var test_hour: int = -1
# [EDIT] How far a finger can move and still count as a tap instead of a drag.
const TAP_SLOP := 12.0
# Where the save file lives (Godot's private user folder).
# [FIX] To see the egg again while testing: Project > Open User Data Folder,
#       then delete pet.cfg.
const SAVE_PATH := "user://pet.cfg"

# The pet's AnimatedSprite2D child node.
# [FIX] If you get "node not found", check the child is named exactly AnimatedSprite2D.
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# ===== SECTION 2: PET STATE ==========================================================
var hatched := false        # has the egg hatched? (saved per pet, so it stays hatched)
var _busy := false          # a one-shot animation (hatching, tickle) is playing
var _egg_taps := 0          # taps counted on the egg so far
var _dragging := false      # a finger went down on the pet
var _moved := false         # the finger moved far enough to count as a drag
var _finger := -1           # which finger is holding the pet (for multi-touch)
var _offset := Vector2.ZERO # where on the pet the finger grabbed it
var _press_pos := Vector2.ZERO  # where the finger first touched
var _touches := {}              # every finger on the screen: finger index -> position
var _pinching := false          # two fingers are resizing the pet
var _pinch_start_dist := 0.0    # distance between the fingers when the pinch began
var _pinch_start_size := 1.0    # pet_size when the pinch began
var _moving := false            # the pet is travelling across the screen
var _move_target_x := 0.0       # where it's going to (x position)
var _move_base_y := 0.0         # its height before setting off (flyers bob around this)
var _move_time := 0.0           # seconds since setting off (for the bob)
var _next_move := 0.0           # seconds until the next trip
var _move_bobs := false         # true if this pet's moving frames are fly_ frames
var _hopping := false           # the pet is in the air, hopping on the spot
var _hop_time := 0.0            # seconds since it took off
var _hop_base_y := 0.0          # its height before the hop
var _awake_until := 0.0         # woken up at night: stays awake until this time
var _no_battery_info := false   # the phone side can't tell the battery level (old add-on)
var _frame_size := 128      # size of one frame, measured from the first PNG in _build_frames()

# ===== SECTION 3: START-UP ===========================================================
# Runs once when the scene starts.
func _ready() -> void:
	scale = Vector2.ONE * pet_size   # apply PET SIZE
	if Engine.is_editor_hint():
		queue_redraw()   # in the editor: only draw the preview (SECTION 9)
		return
	# Call _on_animation_finished() whenever a play-once animation ends.
	sprite.animation_finished.connect(_on_animation_finished)
	set_pet(pet_id)

# Switches this node to another pet: loads its frames and its saved progress.
# Other scripts can call it, e.g. $Pet.set_pet("cat")
# [FIX] If the pet doesn't appear, check the id is in PETS and the folder path is right.
func set_pet(id: String) -> void:
	if not PETS.has(id):
		push_warning("Unknown pet id '%s', using the first pet instead" % id)
		id = PETS.keys()[0]
	pet_id = id
	var frames := _build_frames(PETS[id])
	if frames == null:
		return           # folder not found: the error message is in the Output panel
	sprite.sprite_frames = frames
	_egg_taps = 0
	_moving = false      # the new pet doesn't finish the old pet's trip or hop
	_hopping = false
	sprite.flip_h = false
	_load()          # restore this pet's position and hatched state
	_play_idle()     # start resting: egg_idle or pet_idle
	_reset_move_timer()
	print("Project P: showing pet '%s' from %s (%dpx frames)" % [id, PETS[id], _frame_size])

# ===== SECTION 4: TOUCH (TAP AND DRAG) ===============================================
# [LOGIC] Finger down on the pet -> up without moving = tap (_on_tap).
#         Finger down and moving  = drag: pet plays "jump", then "landing" on release.
# Works with the mouse on PC because "Emulate Touch From Mouse" is on in Project Settings.
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return           # no tapping or dragging inside the editor
	if _handle_resize(event):
		return           # the event was a pinch or mouse-wheel resize (SECTION 4b)
	# --- Finger touches or lifts ---
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var p := _to_world(touch.position)
		# Finger goes down on the pet: start tracking it
		if touch.pressed and not _dragging \
				and p.distance_to(global_position) <= grab_radius * pet_size:
			if _busy and not hatched:
				return   # leave the egg alone while it hatches
			if _moving:
				_stop_moving()   # grabbing the pet mid-trip makes it stop
			_dragging = true
			_moved = false
			_finger = touch.index
			_press_pos = p
			_offset = global_position - p
			get_viewport().set_input_as_handled()
		# Finger lifts: finish the drag (land + save) or count it as a tap
		elif not touch.pressed and touch.index == _finger:
			_dragging = false
			_finger = -1
			if _moved:
				if hatched:
					sprite.play("landing")
				_save()
			else:
				_on_tap()
			get_viewport().set_input_as_handled()
	# --- Finger moves while holding the pet ---
	elif event is InputEventScreenDrag and _dragging:
		var drag := event as InputEventScreenDrag
		if drag.index != _finger:
			return
		var q := _to_world(drag.position)
		# Moved past TAP_SLOP: this is a drag, not a tap
		if not _moved and q.distance_to(_press_pos) > TAP_SLOP:
			_moved = true
			if hatched:
				_busy = false
				sprite.play("jump")   # holds its last frame while the finger is down
		# Move the pet with the finger, kept inside the screen
		if _moved:
			global_position = _clamp_to_screen(q + _offset)
		get_viewport().set_input_as_handled()

# ===== SECTION 4b: RESIZING (pinch on phones, mouse wheel on PC) =====================
# One finger on the pet + a second finger: spread = bigger, pinch = smaller.
# On PC: scroll the mouse wheel over the pet. Size is saved with the pet.
func _handle_resize(event: InputEvent) -> bool:
	# Keep track of every finger on the screen
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = _to_world(t.position)
		else:
			_touches.erase(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = _to_world(d.position)

	# A second finger arrives while the first one holds the pet: start pinching
	if not _pinching and _dragging and _touches.size() == 2:
		_pinching = true
		_dragging = false
		_finger = -1
		if sprite.animation == "jump":
			_play_idle()
		_pinch_start_dist = _finger_distance()
		_pinch_start_size = pet_size
		get_viewport().set_input_as_handled()
		return true

	if _pinching:
		if _touches.size() < 2:          # a finger lifted: the pinch is over
			_pinching = false
			_save()
		elif event is InputEventScreenDrag and _pinch_start_dist > 0.0:
			_set_size(_pinch_start_size * _finger_distance() / _pinch_start_dist)
		get_viewport().set_input_as_handled()
		return true

	# Mouse wheel over the pet (PC)
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
		var down := mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if (up or down) and _to_world(mb.position).distance_to(global_position) \
				<= grab_radius * pet_size:
			_set_size(pet_size + (WHEEL_STEP if up else -WHEEL_STEP))
			_save()
			get_viewport().set_input_as_handled()
			return true
	return false

# Changes the size within min_size..max_size and keeps the pet on screen.
func _set_size(new_size: float) -> void:
	pet_size = clampf(new_size, min_size, max_size)
	global_position = _clamp_to_screen(global_position)

# Distance between the first two fingers on the screen.
func _finger_distance() -> float:
	var points := _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)

# ===== SECTION 4c: WHAT THE PET DOES BY ITSELF =======================================
# [LOGIC] While the hatched pet rests (pet_idle, blinking) and nobody is touching it, a
#         timer runs down (ACTION_WAIT_MIN..ACTION_WAIT_MAX seconds). Then, between two
#         blinks, it picks one action from ACTIONS (SECTION 0) at random, does it, and
#         goes back to resting. The timer starts again.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _moving:
		_move_step(delta)
		return
	if _hopping:
		if _dragging:                  # grabbed in the air: put it down, the drag takes over
			_hopping = false
			global_position.y = _hop_base_y
			_play_idle()
		else:
			_hop_step(delta)
		return
	if not hatched or _busy or _dragging or _pinching or sprite.sprite_frames == null:
		return
	# Falling asleep or waking up: the resting animation it should have now is another
	# one than it is playing (the clock passed SLEEP_FROM_HOUR, or its time awake is over)
	var playing := String(sprite.animation)
	var rest := _rest_anim()
	if (playing == "pet_idle" or playing == "sleep") and playing != rest:
		if playing == "sleep" or sprite.frame % BLINK_FRAMES == 0:
			_play_idle()               # (an awake pet finishes its blink first)
		return
	if playing != "pet_idle":
		return                         # asleep: it does nothing by itself
	_next_move -= delta
	if _next_move > 0.0:
		return
	if sprite.frame % BLINK_FRAMES != 0:
		return                         # let the current blink finish first
	_do_random_action()

# Picks a new random wait before the next action.
func _reset_move_timer() -> void:
	_next_move = randf_range(ACTION_WAIT_MIN, ACTION_WAIT_MAX)

# [LOGIC] Picks one action from ACTIONS at random (by weight) and starts it.
#         Actions this pet has no frames for are left out.
func _do_random_action() -> void:
	_reset_move_timer()
	var choices := []
	var total := 0.0
	for a in _actions_now():           # ACTIONS, or LOW_ENERGY_ACTIONS on a low battery
		if float(a[2]) > 0.0 and (a[0] == "blink" or _can_do(a[0], a[1])):
			choices.append(a)
			total += float(a[2])
	var pick := randf() * total
	for a in choices:
		pick -= float(a[2])
		if pick <= 0.0:
			_do_action(a[0], a[1])
			return

# Starts one action. `kind` is the first word of its line in ACTIONS.
# [FIX] An action never happens: read the "frames per animation" line in the Output
#       panel. Its animation must have more than 0 frames.
func _do_action(kind: String, anim: String) -> void:
	match kind:
		"travel":
			_start_moving(anim)
		"hop":
			_start_hop(anim)
		"play":
			if sprite.sprite_frames.get_animation_loop(anim):
				return                     # a looping animation would never end
			_busy = true                   # no tickling until it has finished
			sprite.play(_one_version(anim))    # e.g. "trick#2"; when it ends -> resting
		_:
			pass                           # "blink": it simply keeps resting

# [LOGIC] An animation listed in ANIM_SETS has several versions, built when the pet is
#         loaded: "trick#1", "trick#2", ... This picks one of them at random. For any
#         other animation it returns the animation itself.
func _one_version(anim: String) -> String:
	var count := 0
	while sprite.sprite_frames.has_animation("%s#%d" % [anim, count + 1]):
		count += 1
	if count == 0:
		return anim
	return "%s#%d" % [anim, randi_range(1, count)]

# [LOGIC] The list the pet picks its next action from: LOW_ENERGY_ACTIONS while the
#         battery is low and the pet has frames for something in it, otherwise ACTIONS.
func _actions_now() -> Array:
	if _is_low_energy():
		for a in LOW_ENERGY_ACTIONS:
			if a[0] != "blink" and float(a[2]) > 0.0 and _can_do(a[0], a[1]):
				return LOW_ENERGY_ACTIONS
	return ACTIONS

# Is the phone's battery low (and not charging)? Always false on the computer, unless
# test_battery_percent is set in the Inspector.
# On the phone the battery is read through the wallpaper add-on (WallpaperBridge.kt).
func _is_low_energy() -> bool:
	if test_battery_percent >= 0:
		return test_battery_percent <= LOW_BATTERY_PERCENT
	if _no_battery_info or not Engine.has_singleton("ProjectPWallpaper"):
		return false
	var phone = Engine.get_singleton("ProjectPWallpaper")
	var percent = phone.call("batteryPercent")
	if not (percent is int):
		_no_battery_info = true        # an older add-on without battery info: stop asking
		return false
	if percent < 0 or phone.call("isCharging") == true:
		return false
	return percent <= LOW_BATTERY_PERCENT

# [LOGIC] Is it the pet's bedtime right now? True between SLEEP_FROM_HOUR and
#         SLEEP_UNTIL_HOUR by the phone's clock, unless a tap woke it up a moment ago.
func _is_sleep_time() -> bool:
	if Time.get_unix_time_from_system() < _awake_until:
		return false                   # woken up: awake for a while
	var hour: int = test_hour if test_hour >= 0 else Time.get_time_dict_from_system()["hour"]
	if SLEEP_FROM_HOUR <= SLEEP_UNTIL_HOUR:
		return hour >= SLEEP_FROM_HOUR and hour < SLEEP_UNTIL_HOUR
	return hour >= SLEEP_FROM_HOUR or hour < SLEEP_UNTIL_HOUR     # (through midnight)

# The animation the pet rests with right now: the egg's idle before hatching, "sleep"
# at night (if it has sleep frames), otherwise pet_idle (blinking).
func _rest_anim() -> String:
	if not hatched:
		return "egg_idle"
	if _is_sleep_time() and _has_frames("sleep"):
		return "sleep"
	return "pet_idle"

# Does this pet have frames for an animation?
func _has_frames(anim: String) -> bool:
	return sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim) \
		and sprite.sprite_frames.get_frame_count(anim) > 0

# Can this pet do an action? "travel" needs frames for its animation or for the
# _left / _right versions of it; everything else needs frames for its animation.
func _can_do(kind: String, anim: String) -> bool:
	if kind == "travel":
		return not _travel_anim(anim, true).is_empty()
	return _has_frames(anim)

# [LOGIC] Which animation the pet travels with, and whether it is drawn mirrored.
#         `base` is the animation named in ACTIONS, normally "move".
#           going left  -> "move_left" frames, if the pet has them
#           going right -> "move_right" frames, if the pet has them
#           only one of the two -> that one, mirrored for the other direction
#           neither -> "move" itself (fly_ / walk_ / run_ frames), mirrored when it
#                      goes the other way than the frames face (move_frames_face_right)
#         Returns [animation, mirrored], or [] if the pet has no frames to travel with.
func _travel_anim(base: String, going_left: bool) -> Array:
	var own := base + ("_left" if going_left else "_right")
	var other := base + ("_right" if going_left else "_left")
	if _has_frames(own):
		return [own, false]
	if _has_frames(other):
		return [other, true]
	if _has_frames(base):
		return [base, going_left == move_frames_face_right]
	return []

# "travel": sets off towards a random spot on the left or right.
func _start_moving(anim: String = "move") -> void:
	var view := get_viewport_rect().size
	var half := _frame_size * 0.5 * scale.x
	var target := randf_range(half, view.x - half)
	if absf(target - global_position.x) < view.x * 0.25:
		# Too short a trip: go towards the farther side of the screen instead
		target = half if global_position.x > view.x / 2.0 else view.x - half
	var going_left := target < global_position.x
	var travel := _travel_anim(anim, going_left)     # e.g. ["move_left", false]
	if travel.is_empty():
		return                         # this pet has no frames to travel with
	_move_target_x = target
	_move_base_y = global_position.y
	_move_time = 0.0
	_moving = true
	_busy = true                       # no tickling while it's on the move
	# Only pets whose travelling frames are named fly_ bob in the air
	var first := sprite.sprite_frames.get_frame_texture(travel[0], 0)
	_move_bobs = first.resource_path.get_file().to_lower().begins_with("fly")
	sprite.flip_h = travel[1]          # mirrored only when it has no frames for this side
	sprite.play(travel[0])

# Moves the pet a little each frame until it reaches its spot.
func _move_step(delta: float) -> void:
	_move_time += delta
	var step := move_speed * delta
	var gap := _move_target_x - global_position.x
	if absf(gap) <= step:
		global_position = Vector2(_move_target_x, _move_base_y)
		_stop_moving()
		return
	global_position.x += signf(gap) * step
	if _move_bobs:
		global_position.y = _move_base_y - absf(sin(_move_time * 3.0)) * move_bob * scale.y

# Stops: back to resting, facing forward, position saved, next action scheduled.
func _stop_moving() -> void:
	_moving = false
	global_position.y = _move_base_y
	sprite.flip_h = false
	_play_idle()
	_save()
	_reset_move_timer()

# "hop": jumps up on the spot. The animation (jump) plays while it is in the air; when
# it comes down, "landing" plays and then it rests (see _on_animation_finished).
func _start_hop(anim: String = "jump") -> void:
	_hopping = true
	_hop_time = 0.0
	_hop_base_y = global_position.y
	_busy = true                       # no tickling while it's in the air
	sprite.play(anim)

# Moves the hopping pet up and back down in an arc.
func _hop_step(delta: float) -> void:
	_hop_time += delta
	var t := _hop_time / HOP_SECONDS       # 0 at take-off, 1 at touchdown
	if t >= 1.0:
		_hopping = false
		global_position.y = _hop_base_y
		if _has_frames("landing"):
			sprite.play("landing")         # -> resting when it ends
		else:
			_play_idle()
		return
	global_position.y = _hop_base_y - sin(t * PI) * HOP_HEIGHT * _frame_size * scale.y

# [LOGIC] What a tap on the pet does.
#         Egg: count taps, hatch after taps_to_hatch (SECTION 1).
#         Pet: play ticklish (then recovery, see _on_animation_finished).
func _on_tap() -> void:
	if _busy:
		return       # ignore taps while hatching or being tickled
	if not hatched:
		_egg_taps += 1
		if _egg_taps >= taps_to_hatch:
			_busy = true
			if _has_frames("egg_hatch"):
				sprite.play("egg_hatch")       # the egg hatches (and the pet emerges)
			elif _has_frames("pet_emerge"):
				sprite.play("pet_emerge")      # only emerge frames: play those
			else:
				hatched = true                 # no hatching frames at all: hatch at once
				_save()
				_play_idle()
	else:
		# Any tap keeps the pet awake for AWAKE_MINUTES (this only matters at night)
		var was_asleep := String(sprite.animation) == "sleep"
		_awake_until = Time.get_unix_time_from_system() + AWAKE_MINUTES * 60.0
		if was_asleep:
			_play_idle()               # it wakes up: back to blinking
			_reset_move_timer()
			return
		_busy = true
		sprite.play("ticklish")

# ===== SECTION 5: ANIMATION RULES ====================================================
# [LOGIC] What plays after each play-once animation ends.
#         Change these lines to change the order of animations.
# [FIX] If an animation never moves on, make sure its loop is false in ANIMS
#       (only egg_idle and pet_idle should loop), otherwise it never "finishes".
func _on_animation_finished() -> void:
	match String(sprite.animation):
		"egg_hatch":
			if _has_frames("pet_emerge"):
				sprite.play("pet_emerge")  # egg cracks -> pet comes out
			else:
				hatched = true             # hatching and emerging are one animation:
				_save()                    # the pet is out -> remember it
				_play_idle()
		"pet_emerge":
			hatched = true                 # pet is out -> remember it
			_save()
			_play_idle()
		"ticklish":
			sprite.play("recovery")        # tickled -> calms down
		"recovery", "landing":
			_play_idle()                   # -> back to resting
		"jump":
			# In the air or in the hand it holds its last frame; otherwise -> resting
			if not _hopping and not _moving and not _dragging:
				_play_idle()
		_:
			# Any other play-once animation (e.g. "trick") -> back to resting. While
			# the pet travels or hops with it, it holds the last frame until it arrives.
			if not _moving and not _hopping:
				_play_idle()

# Go back to resting: egg_idle before hatching; after it pet_idle (blinking), or
# "sleep" at night (see _rest_anim in SECTION 4c).
func _play_idle() -> void:
	_busy = false
	sprite.play(_rest_anim())

# ===== SECTION 6: HELPERS ============================================================
# Converts a touch position on the screen into a position in the game world.
func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos

# Keeps the pet fully inside the screen.
func _clamp_to_screen(p: Vector2) -> Vector2:
	var view := get_viewport_rect().size
	var half := Vector2(_frame_size, _frame_size) * 0.5 * scale   # half of one frame
	return p.clamp(half, view - half)

# ===== SECTION 7: SAVING AND LOADING =================================================
# Saves the pet's position and whether it has hatched to user://pet.cfg.
# Each pet has its own section in the file (named after its id), so every pet keeps
# its own progress.
# [EDIT] Add more cfg.set_value(...) lines here to save more things (e.g. stats).
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)              # keep the other pets' data already in the file
	cfg.set_value(pet_id, "position", global_position)
	cfg.set_value(pet_id, "hatched", hatched)
	cfg.set_value(pet_id, "size", pet_size)
	cfg.save(SAVE_PATH)

# Loads this pet's data back. If there's no save yet, it starts as an egg where the
# Pet node was placed in the editor.
func _load() -> void:
	hatched = false
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		global_position = cfg.get_value(pet_id, "position", global_position)
		hatched = cfg.get_value(pet_id, "hatched", false)
		pet_size = cfg.get_value(pet_id, "size", pet_size)

# ===== SECTION 8: BUILDING ANIMATIONS FROM A FRAME FOLDER ============================
# Finds the pet's PNG frames, sorts them into animations (by name or by number, see
# SECTION 0) and returns them as SpriteFrames, ready for the AnimatedSprite2D.
# [FIX] Read the "Project P:" lines in the Output panel: they list the folder used,
#       how the files were matched, and how many frames each animation got.
func _build_frames(folder: String) -> SpriteFrames:
	var groups := _frame_groups(folder)
	if groups.is_empty():
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation("default")       # SpriteFrames starts with an empty one
	var summary := PackedStringArray()
	for a in ANIMS:
		var anim_name: String = a[0]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, a[2])
		frames.set_animation_loop(anim_name, a[3])
		var paths: Array = groups.get(anim_name, [])
		for path in paths:
			frames.add_frame(anim_name, load(path))
		summary.append("%s %d" % [anim_name, paths.size()])
		if paths.is_empty():
			push_warning("Project P: no frames found for '%s'." % anim_name)
	# Movements with several versions (ANIM_SETS, SECTION 0): besides the whole animation,
	# one extra animation per version is made, named "trick#1", "trick#2", ...
	for set_name in ANIM_SETS:
		var per_version: int = ANIM_SETS[set_name]
		var set_paths: Array = groups.get(set_name, [])
		if per_version <= 0 or not frames.has_animation(set_name):
			continue
		@warning_ignore("integer_division")
		var versions: int = set_paths.size() / per_version
		for v in versions:
			var version_name := "%s#%d" % [set_name, v + 1]
			frames.add_animation(version_name)
			frames.set_animation_speed(version_name, frames.get_animation_speed(set_name))
			frames.set_animation_loop(version_name, frames.get_animation_loop(set_name))
			for path in set_paths.slice(v * per_version, (v + 1) * per_version):
				frames.add_frame(version_name, load(path))
		if versions > 0:
			summary.append("(%s: %d versions)" % [set_name, versions])
	print("Project P: frames per animation: " + ", ".join(summary))
	for a in ANIMS:                          # measure the frame size from the first frame
		var first: Array = groups.get(a[0], [])
		if not first.is_empty():
			_frame_size = (load(first[0]) as Texture2D).get_width()
			break
	return frames

# Sorts a pet's PNG files into animations. Returns { "egg_idle": [paths...], ... }.
func _frame_groups(folder: String) -> Dictionary:
	var files := _png_files(folder)
	if files.is_empty():
		# Not found where PETS says: look for a folder named like the pet anywhere
		var found := _find_folder("res://", folder.get_file().to_lower())
		if found != "":
			push_warning("Project P: no frames in %s, using %s instead. Update PETS in "
				% [folder, found] + "pet.gd (SECTION 0) to this path.")
			files = _png_files(found)
	if files.is_empty():
		push_error("Project P: no PNG frames found in %s (or its subfolders). Check the "
			% folder + "folder name and place match PETS in pet.gd (SECTION 0).")
		return {}
	files.sort_custom(func(x, y): return x.naturalnocasecmp_to(y) < 0)
	print("Project P: found %d PNG frames in %s, e.g. %s" % [files.size(), folder,
		files[0].get_file()])

	# Style A: files named by animation (egg_idle_00.png ...)
	var groups := {}
	var unmatched := 0
	for path in files:
		var anim := _anim_for_file(path.get_file())
		if anim == "":
			unmatched += 1
		else:
			if not groups.has(anim):
				groups[anim] = []
			groups[anim].append(path)
	if not groups.is_empty():
		print("Project P: matched frames by animation name.")
		if unmatched > 0:
			push_warning("Project P: %d files didn't match any animation name in ANIMS "
				% unmatched + "(SECTION 0) and were skipped.")
		return groups

	# Style B: files only numbered -> hand them out in ANIMS order
	print("Project P: matched frames by number (first %d -> %s, ...)." % [ANIMS[0][1],
		ANIMS[0][0]])
	var next := 0
	for a in ANIMS:
		var count: int = a[1]
		groups[a[0]] = files.slice(next, next + count)
		next += count
	if files.size() != next:
		push_warning("Project P: found %d frames, ANIMS expects %d." % [files.size(), next])
	return groups

# Which animation a file belongs to, from its name ("" if none).
#   "egg_idle_03.png"    -> "egg_idle"   (exact name in ANIMS)
#   "dragon_idle_03.png" -> "pet_idle"   (pet name in front + "idle")
#   "jump_land_a_05.png" -> "jump"       (exact name in ANIMS)
# [EDIT] If a file isn't recognised, add its name (without the number) to ANIMS.
func _anim_for_file(file_name: String) -> String:
	var label := file_name.get_basename().to_lower()
	var re := RegEx.new()
	re.compile("[ _-]*\\d+$")               # remove the frame number at the end
	label = re.sub(label, "")
	# 1) exact match, e.g. "egg_idle", "jump_land_a"
	for a in ANIMS:
		if label in a[4]:
			return a[0]
	# 2) pet name in front, e.g. "dragon_idle" ends with "_idle"
	for a in ANIMS:
		for n in a[4]:
			if label.ends_with("_" + n):
				return a[0]
	# 3) extra rows from the slicer, e.g. "idle_b" -> try "idle"
	var row := RegEx.new()
	row.compile("_[a-z]$")
	if row.search(label) != null:
		return _anim_for_file(row.sub(label, "") + "_00.png")
	return ""

# All PNG files in a folder and its subfolders (full paths).
# Works in the editor and in exported games, where Godot keeps only "<name>.png.import".
func _png_files(folder: String) -> Array:
	var result := []
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	for f in dir.get_files():
		var fname := f.trim_suffix(".import").trim_suffix(".remap")
		if fname.get_extension().to_lower() == "png":
			var path := folder.path_join(fname)
			if not result.has(path):
				result.append(path)
	for d in dir.get_directories():
		if not d.begins_with("."):
			result.append_array(_png_files(folder.path_join(d)))
	return result

# Searches the project for a folder called `wanted` that contains PNGs ("" if none).
func _find_folder(start: String, wanted: String) -> String:
	var dir := DirAccess.open(start)
	if dir == null:
		return ""
	for d in dir.get_directories():
		if d.begins_with(".") or d == "addons":
			continue
		var path := start.path_join(d)
		if d.to_lower() == wanted and not _png_files(path).is_empty():
			return path
		var deeper := _find_folder(path, wanted)
		if deeper != "":
			return deeper
	return ""

# ===== SECTION 9: EDITOR PREVIEW =====================================================
# Only runs inside the Godot editor: draws the pet's first egg frame where the pet will
# be, so you can see and place the pet while building the scene. Nothing here runs in
# the game itself (the AnimatedSprite2D shows the real animations there).
# [FIX] No preview? Check the folder path in PETS, then use Scene > Reload Saved Scene.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var folder: String = PETS.get(pet_id, PETS.values()[0])
	var groups := _frame_groups(folder)
	for a in ANIMS:
		var paths: Array = groups.get(a[0], [])
		if not paths.is_empty():
			var tex: Texture2D = load(paths[0])
			draw_texture(tex, -tex.get_size() / 2.0)   # centred like the AnimatedSprite2D
			return
