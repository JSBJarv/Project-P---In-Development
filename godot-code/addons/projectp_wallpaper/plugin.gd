# =====================================================================================
# plugin.gd  -  PUTS THE LIVE WALLPAPER INTO THE GAME'S ANDROID APP (one APK)
# =====================================================================================
# What this file does:
#   When you export the game for Android with "Use Gradle Build" turned on, this add-on
#   automatically:
#     1. copies the wallpaper's Kotlin code and resources (android/ folder next to this
#        file) into Godot's Android build folder, so they're compiled into the same app,
#     2. copies the Project P wallpaper picture (default_wallpaper.png next to this
#        file) into the app, for the wallpaper and its setup screens,
#     3. registers the wallpaper, its setup screens and the bridge to the game in the
#        app's manifest,
#     4. reads the pet list (PETS) from pet.gd and adds every pet's frame PNGs to the
#        app as plain files, so the wallpaper shows the same pets with the same frames.
#        The frames can be in any folder or subfolder; whatever PETS points to is used.
#        It sorts the frames into animations with pet.gd's own rules, and also hands
#        the wallpaper pet.gd's animation list (ANIMS) and the list of things the pet
#        does by itself (ACTIONS), together with the settings for tricks with several
#        versions, low energy and sleep. So the wallpaper pet always has the same
#        animations, speeds and behaviour as the pet in the game, with nothing to keep
#        in sync.
#        The Output panel lists how many frames each animation got, per pet.
#     5. adds the animation frames of the Project P wallpaper, if you put any in the
#        default_wallpaper_frames/ folder next to this file (an animated default
#        wallpaper). With no frames there, the still picture is used.
#   It runs again on every export, so it also repairs itself after a Godot update
#   resets the build folder.
#
# One app, one icon: the phone shows only the game's icon. The wallpaper setup is
# opened from the "Wallpaper Selection" button in the game's main menu (main_menu.gd).
#
# The wallpaper runs in its own process (":wallpaper"), separate from the game. Godot
# shuts its process down when the game closes; kept separate, that can't take the
# wallpaper down with it.
#
# You normally don't need to change anything here. To change the wallpaper itself, edit
# the files in  addons/projectp_wallpaper/android/src/  and export again.
#
# How to find things:
#   [EDIT]  = a setting you can safely change
#   [FIX]   = places to look first if something goes wrong
#
# Works with both Android build layouts: Godot 4.5 and older (files directly in
# android/build) and Godot 4.6 and newer (files in android/build/src/main).
# =====================================================================================

@tool
extends EditorPlugin

var _export_plugin: WallpaperExportPlugin

func _enter_tree() -> void:
	_export_plugin = WallpaperExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class WallpaperExportPlugin extends EditorExportPlugin:

	# ===== SECTION 1: SETTINGS ===================================================
	# The wallpaper's files that come with this add-on.
	const ADDON_ANDROID := "res://addons/projectp_wallpaper/android"
	# [EDIT] Where your pet script is. The add-on reads its PETS list (pet id -> folder).
	const PET_SCRIPT := "res://pet.gd"
	# Where the frames go inside the app (must match GAME_FRAMES in PetCatalog.kt).
	const APP_FRAMES := "res://wallpaper_frames"
	# [EDIT] The Kotlin package of the wallpaper code. If you change the "package ..."
	#        line at the top of the .kt files, change these two to match.
	const KOTLIN_PACKAGE := "com.yourname.projectp.wallpaper"
	const KOTLIN_PACKAGE_DIR := "com/yourname/projectp/wallpaper"
	# [EDIT] The Project P wallpaper picture: the default wallpaper, the picture behind
	#        the wallpaper setup screens and behind the game's "Choose your pet" screen.
	#        To change it, replace this PNG with your own (same name, portrait, PNG).
	const DEFAULT_PICTURE := "res://addons/projectp_wallpaper/default_wallpaper.png"
	# [EDIT] The folder with the animation frames of the Project P wallpaper (optional).
	#        Put pictures there named in playing order: frame_00.jpg, frame_01.jpg, ...
	#        (JPG, PNG or WebP, all the same size, portrait). Godot doesn't show this
	#        folder (it has a .gdignore file so the frames aren't imported into the
	#        game); use your computer's file explorer. Empty folder = still picture.
	const DEFAULT_FRAMES := "res://addons/projectp_wallpaper/default_wallpaper_frames"
	# [EDIT] true = if the folder above is empty, the main menu's background frames
	#        (MENU_BACKGROUND) are used as the animated Project P wallpaper too, so one
	#        set of frames serves both. Leave it false if your menu background has a
	#        title or logo painted into it.
	const USE_MENU_BACKGROUND_AS_WALLPAPER := false
	const MENU_BACKGROUND := "res://menu/background"
	# Where those frames go inside the app (must match DEFAULT_BG_FRAMES in
	# PetCatalog.kt), and the kinds of picture files that are accepted.
	const APP_BG_FRAMES := "res://wallpaper_bg_frames"
	const PICTURE_TYPES := ["png", "jpg", "jpeg", "webp"]
	# [EDIT] Animations only the wallpaper uses, so pet.gd doesn't list them:
	#        animation -> the file names it accepts (without the frame number).
	#        "greet" is played when the lock screen appears (greet_00.png ...); a pet
	#        without such frames greets with a hop instead.
	const WALLPAPER_ONLY_ANIMS := {"greet": ["greet", "hello", "wave"]}
	# [EDIT] Names shown on the phone: the title of the wallpaper setup screens, and the
	#        wallpaper's name in Android's wallpaper list.
	const SETUP_ICON_LABEL := "Project P Wallpaper"
	const WALLPAPER_LABEL := "Project P Pet"
	# [EDIT] false = one app icon (the game); the wallpaper setup opens from the main
	#        menu's "Wallpaper Selection" button. true = a second icon "Project P
	#        Wallpaper" that opens the setup directly (use it only if the button doesn't
	#        work on some phone).
	const SHOW_SETUP_ICON := false
	# The name the game uses to reach the wallpaper code. Must match getPluginName() in
	# WallpaperBridge.kt and WALLPAPER_PLUGIN in main_menu.gd and pet_picker.gd.
	const PLUGIN_NAME := "ProjectPWallpaper"
	# The wallpaper's own process (see the top of this file). Leave as it is.
	const WALLPAPER_PROCESS := ":wallpaper"

	func _get_name() -> String:
		return "ProjectPWallpaper"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	# ===== SECTION 2: THE APP'S MANIFEST =========================================
	# Added at the top level of the manifest: says the app can use live wallpapers.
	# required="false" keeps the game installable on devices without live wallpapers.
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return '    <uses-feature android:name="android.software.live_wallpaper" ' \
			+ 'android:required="false" />\n'

	# Added inside <application>: the bridge to the game, the setup screens and the
	# wallpaper service.
	# [FIX] Two app icons on the phone: SHOW_SETUP_ICON (SECTION 1) must be false.
	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		# The second app icon, only if asked for in SECTION 1
		var launcher := ""
		if SHOW_SETUP_ICON:
			launcher = """
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>"""
		return """
        <meta-data
            android:name="org.godotengine.plugin.v2.%s"
            android:value="%s.WallpaperBridge" />

        <activity
            android:name="%s.SetWallpaperActivity"
            android:exported="%s"
            android:label="%s"
            android:process="%s"
            android:screenOrientation="portrait"
            android:theme="@android:style/Theme.DeviceDefault.Light.NoActionBar">%s
        </activity>

        <service
            android:name="%s.PetWallpaperService"
            android:exported="true"
            android:label="%s"
            android:process="%s"
            android:permission="android.permission.BIND_WALLPAPER">
            <intent-filter>
                <action android:name="android.service.wallpaper.WallpaperService" />
            </intent-filter>
            <meta-data
                android:name="android.service.wallpaper"
                android:resource="@xml/pet_wallpaper" />
        </service>
""" % [PLUGIN_NAME, KOTLIN_PACKAGE,
			KOTLIN_PACKAGE, "true" if SHOW_SETUP_ICON else "false", SETUP_ICON_LABEL,
			WALLPAPER_PROCESS, launcher,
			KOTLIN_PACKAGE, WALLPAPER_LABEL, WALLPAPER_PROCESS]

	# ===== SECTION 3: WHAT HAPPENS WHEN AN EXPORT STARTS =========================
	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String,
			_flags: int) -> void:
		if not features.has("android"):
			return                       # only for Android exports
		if not get_option("gradle_build/use_gradle_build"):
			push_warning("Project P Wallpaper: 'Use Gradle Build' is off in the Android "
				+ "export, so the wallpaper is NOT included. Turn it on in Project > "
				+ "Export > Android > Gradle Build.")
			return
		if install_wallpaper_code(_build_dir()):
			var pets := read_pets()
			var count := add_pet_frames(pets)
			print("Project P Wallpaper: wallpaper code installed, %d frame PNGs added for pets: %s"
				% [count, ", ".join(PackedStringArray(pets.keys()))])
			var bg_count := add_background_frames()
			if bg_count > 0:
				print("Project P Wallpaper: animated default wallpaper, "
					+ "%d background frames added." % bg_count)
			else:
				print("Project P Wallpaper: no background frames in %s, " % DEFAULT_FRAMES
					+ "so the default wallpaper is the still picture.")

	# Godot's Android build folder (normally res://android/build).
	func _build_dir() -> String:
		var base := "res://android"
		var custom = get_option("gradle_build/gradle_build_directory")
		if custom is String and custom != "":
			base = custom
		return base.path_join("build")

	# ===== SECTION 4: COPYING THE WALLPAPER CODE INTO THE BUILD FOLDER ===========
	# Returns true if the files were copied.
	# [FIX] "Android build template not found": install it first. Older Godot versions:
	#       Project > Install Android Build Template. Newer versions install it when you
	#       export with Use Gradle Build on; export once, then export again.
	func install_wallpaper_code(build_dir: String) -> bool:
		var new_layout := FileAccess.file_exists(
			build_dir.path_join("src/main/AndroidManifest.xml"))
		var old_layout := FileAccess.file_exists(build_dir.path_join("AndroidManifest.xml"))
		if not new_layout and not old_layout:
			push_error("Project P Wallpaper: Android build template not found in %s. "
				% build_dir + "Install the Android build template, then export again.")
			return false
		# Godot 4.6+: code in src/main/java, resources in src/main/res.
		# Godot 4.5 and older: code in src, resources in res.
		var code_dir := build_dir.path_join("src/main/java" if new_layout else "src")
		var res_dir := build_dir.path_join("src/main/res" if new_layout else "res")
		var copied := _copy_tree(ADDON_ANDROID.path_join("src"),
			code_dir.path_join(KOTLIN_PACKAGE_DIR))
		copied += _copy_tree(ADDON_ANDROID.path_join("res"), res_dir)
		if copied == 0:
			push_error("Project P Wallpaper: no files found in %s." % ADDON_ANDROID)
			return false
		_copy_default_picture(res_dir)
		return true

	# Copies the Project P wallpaper picture into the app as pet_default_bg.png, the
	# name the wallpaper code looks for.
	# [FIX] Plain colour instead of the picture on the phone: check DEFAULT_PICTURE
	#       (SECTION 1) exists and is a real PNG file.
	func _copy_default_picture(res_dir: String) -> void:
		var target := res_dir.path_join("drawable-nodpi/pet_default_bg.png")
		if not FileAccess.file_exists(DEFAULT_PICTURE):
			push_warning("Project P Wallpaper: %s not found; " % DEFAULT_PICTURE
				+ "the wallpaper will use a plain colour as its default background.")
			return
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.copy_absolute(DEFAULT_PICTURE, target) != OK:
			push_error("Project P Wallpaper: could not copy %s" % DEFAULT_PICTURE)

	# Copies a folder and everything in it. Returns how many files were copied.
	func _copy_tree(from: String, to: String) -> int:
		var dir := DirAccess.open(from)
		if dir == null:
			return 0
		DirAccess.make_dir_recursive_absolute(to)
		var count := 0
		for f in dir.get_files():
			if f.ends_with(".import") or f.ends_with(".uid") or f.begins_with("."):
				continue                 # skip Godot's own helper files
			if DirAccess.copy_absolute(from.path_join(f), to.path_join(f)) == OK:
				count += 1
			else:
				push_error("Project P Wallpaper: could not copy %s" % from.path_join(f))
		for d in dir.get_directories():
			count += _copy_tree(from.path_join(d), to.path_join(d))
		return count

	# ===== SECTION 5: ADDING THE PETS' FRAMES AS PLAIN FILES =====================
	# Godot normally packs images in its own format, which the wallpaper can't read.
	# So for every pet in PETS (pet.gd), this adds the original PNGs to the app as
	#   assets/wallpaper_frames/<pet id>/<file>.png
	# and a list of the pet ids (wallpaper_frames/pets.txt). The wallpaper reads both.
	# The frames are sorted into animations here, with pet.gd's own code, and the
	# result is handed to the wallpaper, so game and wallpaper can never disagree
	# about which file belongs to which animation.

	# The pets from pet.gd: { "dragon": "res://pets/dragon", ... }
	# [FIX] "could not read PETS": check PET_SCRIPT (SECTION 1) points to your pet.gd.
	func read_pets() -> Dictionary:
		var script = load(PET_SCRIPT) if ResourceLoader.exists(PET_SCRIPT) else null
		var pets = script.get_script_constant_map().get("PETS") if script is Script else null
		if not (pets is Dictionary) or pets.is_empty():
			push_error("Project P Wallpaper: could not read PETS from %s. The wallpaper "
				% PET_SCRIPT + "will have no pets. Check PET_SCRIPT in the add-on's plugin.gd.")
			return {}
		return pets

	# Adds every pet's PNGs, the pet list, and what the wallpaper needs to know about
	# the animations. Returns how many PNGs were added. Files written into the app:
	#   wallpaper_frames/pets.txt             the pet ids, one per line
	#   wallpaper_frames/anims.txt            ANIMS and ACTIONS from pet.gd
	#   wallpaper_frames/<id>/<file>.png      the frames
	#   wallpaper_frames/<id>/frames.txt      which files belong to which animation
	# [FIX] An animation is missing on the wallpaper: read the per-pet line this prints
	#       in the Output panel, e.g. "dragon: egg_idle 8, ... move 32, trick 16". An
	#       animation with 0 has no files whose names match its list in ANIMS (pet.gd).
	func add_pet_frames(pets: Dictionary) -> int:
		var script = load(PET_SCRIPT) if ResourceLoader.exists(PET_SCRIPT) else null
		var constants: Dictionary = script.get_script_constant_map() if script is Script else {}
		# A stand-in pet made from pet.gd, used only to sort the files the way the game does
		var sorter = script.new() if script is Script and script.can_instantiate() else null
		if sorter != null and not sorter.has_method("_frame_groups"):
			sorter.free()
			sorter = null
		if sorter == null:
			push_warning("Project P Wallpaper: %s can't sort the frames (it needs '@tool' "
				% PET_SCRIPT + "at the top and a _frame_groups function), so the wallpaper "
				+ "sorts them by file name itself. Animations you added may be missing.")
		var total := 0
		var ids := PackedStringArray()
		for id in pets:
			var groups := {}                 # animation -> [file paths in playing order]
			if sorter != null:
				groups = sorter._frame_groups(String(pets[id]))
			if groups.is_empty():
				groups = {"": _all_pngs(String(id), String(pets[id]))}   # unsorted
			else:
				_add_wallpaper_only(groups, _all_pngs(String(id), String(pets[id])))
			var seen := {}
			var listing := PackedStringArray()
			var summary := PackedStringArray()
			var count := 0
			for anim in groups:
				var names := PackedStringArray()
				for path in groups[anim]:
					var file_name: String = path.get_file()
					if seen.has(file_name.to_lower()):
						push_warning("Project P Wallpaper: two files named %s for pet '%s'; "
							% [file_name, id] + "only the first is used.")
						continue
					seen[file_name.to_lower()] = true
					add_file(APP_FRAMES.path_join(String(id)).path_join(file_name),
						FileAccess.get_file_as_bytes(path), false)
					names.append(file_name)
					count += 1
				if anim != "" and not names.is_empty():
					listing.append("%s=%s" % [anim, "/".join(names)])
					summary.append("%s %d" % [anim, names.size()])
			if count == 0:
				push_warning("Project P Wallpaper: no PNG frames found for pet '%s' in %s."
					% [id, pets[id]])
				continue
			if not listing.is_empty():
				add_file(APP_FRAMES.path_join(String(id)).path_join("frames.txt"),
					"\n".join(listing).to_utf8_buffer(), false)
				print("Project P Wallpaper: %s: %s" % [id, ", ".join(summary)])
				_warn_missing(String(id), groups, constants)
			total += count
			ids.append(String(id))
		# pet_size in pet.gd: the pet's size in the game before the player resizes it
		var default_size := 0.0
		if sorter != null:
			var size_in_script = sorter.get("pet_size")
			if size_in_script is float or size_in_script is int:
				default_size = float(size_in_script)
			sorter.free()
		add_file(APP_FRAMES.path_join("pets.txt"), "\n".join(ids).to_utf8_buffer(), false)
		var table := _anim_table(constants, default_size)
		if table != "":
			add_file(APP_FRAMES.path_join("anims.txt"), table.to_utf8_buffer(), false)
		return total

	# Every PNG of a pet, unsorted (used only if pet.gd can't sort them).
	func _all_pngs(id: String, folder: String) -> Array:
		var files := _png_files(folder)
		if files.is_empty():
			# Not where PETS says (e.g. different capitals): look for a folder named
			# like the pet anywhere in the project, like pet.gd does.
			var found := _find_folder("res://", id.to_lower())
			if found != "":
				files = _png_files(found)
		return files

	# Adds the frames of animations only the wallpaper knows (WALLPAPER_ONLY_ANIMS) to a
	# pet's groups, by file name: greet_00.png, dragon_greet_00.png, greet_a_00.png ...
	# An animation pet.gd already sorted itself (it is in ANIMS there) is left alone.
	func _add_wallpaper_only(groups: Dictionary, files: Array) -> void:
		var wanted := {}                        # animation -> names, still to be filled
		for anim in WALLPAPER_ONLY_ANIMS:
			if (groups.get(anim, []) as Array).is_empty():
				wanted[anim] = WALLPAPER_ONLY_ANIMS[anim]
		if wanted.is_empty():
			return
		var number := RegEx.new()
		number.compile("[ _-]*\\d+$")           # the frame number at the end
		var row := RegEx.new()
		row.compile("_[a-z]$")                  # a row letter from the slicer
		files.sort_custom(func(x, y): return x.naturalnocasecmp_to(y) < 0)
		for path in files:
			var label: String = number.sub(str(path).get_file().get_basename().to_lower(), "")
			var plain: String = row.sub(label, "")
			for anim in wanted:
				for n in wanted[anim]:
					if label == n or label.ends_with("_" + n) or plain == n \
							or plain.ends_with("_" + n):
						if not groups.has(anim):
							groups[anim] = []
						groups[anim].append(path)
						break

	# Says so in the Output panel when a pet lacks frames for something it should do.
	func _warn_missing(id: String, groups: Dictionary, constants: Dictionary) -> void:
		var needed := {"pet_idle": "rest", "move": "travel (also when tapped or tilted)",
			"jump": "jump (also when tapped or greeting)"}
		for action in constants.get("ACTIONS", []):
			if action is Array and action.size() >= 3 and str(action[0]) != "blink" \
					and _number(action[2]) > 0.0:
				needed[str(action[1])] = "do its '%s' action" % str(action[0])
		for anim in needed:
			var found: bool = not (groups.get(anim, []) as Array).is_empty()
			# Travelling also works with the _left / _right frames of its animation
			if not found and (anim == "move" or String(needed[anim]).contains("'travel'")):
				found = not (groups.get(anim + "_left", []) as Array).is_empty() \
					or not (groups.get(anim + "_right", []) as Array).is_empty()
			if not found:
				push_warning("Project P Wallpaper: pet '%s' has no frames for '%s', "
					% [id, anim] + "so on the wallpaper it will not %s. " % needed[anim]
					+ "Check the file names against ANIMS in pet.gd.")

	# pet.gd's ANIMS and ACTIONS as text for the wallpaper (see tableFromGame in
	# PetCatalog.kt): one entry per line.
	func _anim_table(constants: Dictionary, default_size := 0.0) -> String:
		var lines := PackedStringArray()
		for a in constants.get("ANIMS", []):
			if a is Array and a.size() >= 4:
				lines.append("anim|%s|%s|%s" % [str(a[0]), _number(a[2]),
					"true" if a[3] else "false"])
		if constants.get("ACTIONS") is Array:
			lines.append("actions|1")           # pet.gd has an ACTIONS list (even if empty)
			for a in constants["ACTIONS"]:
				if a is Array and a.size() >= 3:
					lines.append("action|%s|%s|%s" % [str(a[0]), str(a[1]), _number(a[2])])
				else:
					push_warning("Project P Wallpaper: a line in ACTIONS (pet.gd) isn't "
						+ "[what, animation, weight] and was skipped: %s" % str(a))
		if constants.has("ACTION_WAIT_MIN") and constants.has("ACTION_WAIT_MAX"):
			lines.append("wait|%s|%s" % [_number(constants["ACTION_WAIT_MIN"]),
				_number(constants["ACTION_WAIT_MAX"])])
		if constants.has("BLINK_FRAMES"):
			lines.append("blink|%s" % int(_number(constants["BLINK_FRAMES"])))
		# Movements with several versions (one is played at a time)
		if constants.get("ANIM_SETS") is Dictionary:
			lines.append("sets|1")
			for anim in constants["ANIM_SETS"]:
				lines.append("set|%s|%s" % [str(anim), int(_number(constants["ANIM_SETS"][anim]))])
		# Low energy: what the pet does on a low battery
		if constants.has("LOW_BATTERY_PERCENT"):
			lines.append("lowbattery|%s" % int(_number(constants["LOW_BATTERY_PERCENT"])))
		if constants.get("LOW_ENERGY_ACTIONS") is Array:
			lines.append("lowactions|1")
			for a in constants["LOW_ENERGY_ACTIONS"]:
				if a is Array and a.size() >= 3:
					lines.append("lowaction|%s|%s|%s" % [str(a[0]), str(a[1]), _number(a[2])])
		# Sleep: from which hour until which hour, and minutes awake after a tap
		if constants.has("SLEEP_FROM_HOUR") and constants.has("SLEEP_UNTIL_HOUR"):
			lines.append("sleep|%s|%s|%s" % [int(_number(constants["SLEEP_FROM_HOUR"])),
				int(_number(constants["SLEEP_UNTIL_HOUR"])),
				_number(constants.get("AWAKE_MINUTES", 5.0))])
		# The game's screen (Project Settings > Display > Window), so the wallpaper can
		# show the pet at the same size on screen as the game does. The size the player
		# gave the pet is read from the save file; pet_size is used until there is one.
		lines.append("gamescreen|%s|%s|%s|%s" % [
			int(ProjectSettings.get_setting("display/window/size/viewport_width", 720)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", 1280)),
			str(ProjectSettings.get_setting("display/window/stretch/mode", "disabled")),
			_number(ProjectSettings.get_setting("display/window/stretch/scale", 1.0))])
		if default_size > 0.0:
			lines.append("petsize|%s" % default_size)
		return "\n".join(lines)

	# A value from pet.gd as a number (0 if it isn't one).
	func _number(value) -> float:
		return float(value) if (value is float or value is int) else 0.0

	# ===== SECTION 6: THE ANIMATED PROJECT P WALLPAPER (optional) =================
	# Adds the pictures in DEFAULT_FRAMES to the app as plain files:
	#   assets/wallpaper_bg_frames/<file>
	# The wallpaper plays them in the order of their names. Returns how many were added.
	# [FIX] "0 background frames": the pictures must be directly in that folder (not in
	#       a subfolder) and be JPG, PNG or WebP files.
	func add_background_frames() -> int:
		var total := _add_frames_from(DEFAULT_FRAMES)
		if total == 0 and USE_MENU_BACKGROUND_AS_WALLPAPER:
			total = _add_frames_from(MENU_BACKGROUND)   # share the main menu's frames
		return total

	# Adds every picture in `folder` to the app's wallpaper_bg_frames. Returns how many.
	func _add_frames_from(folder: String) -> int:
		var dir := DirAccess.open(folder)
		if dir == null:
			return 0
		var total := 0
		for f in dir.get_files():
			if f.get_extension().to_lower() in PICTURE_TYPES:
				add_file(APP_BG_FRAMES.path_join(f),
					FileAccess.get_file_as_bytes(folder.path_join(f)), false)
				total += 1
		return total

	# ===== SECTION 7: HELPERS ====================================================
	# All PNG files in a folder and its subfolders (full paths).
	func _png_files(folder: String) -> Array:
		var result := []
		var dir := DirAccess.open(folder)
		if dir == null:
			return result
		for f in dir.get_files():
			if f.get_extension().to_lower() == "png":
				result.append(folder.path_join(f))
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
			if d.begins_with(".") or d == "addons" or d == "android":
				continue
			var path := start.path_join(d)
			if d.to_lower() == wanted and not _png_files(path).is_empty():
				return path
			var deeper := _find_folder(path, wanted)
			if deeper != "":
				return deeper
		return ""
