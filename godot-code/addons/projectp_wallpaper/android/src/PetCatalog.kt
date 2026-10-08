// =====================================================================================
// PetCatalog.kt  -  THE LIST OF ALL PETS (the one place to add a new pet)
// =====================================================================================
// What this file does:
//   Lists every pet the wallpaper can show, the animations every pet's frames are split
//   into, and the things a pet does by itself (ACTIONS). PetWallpaperService.kt draws
//   the chosen pet; SetWallpaperActivity.kt lets the user pick which one. It also reads
//   the Godot game's save file when the wallpaper is packaged in the same app as the
//   game (see GameSave at the bottom).
//
// Where the pets, their frames, animations and actions come from:
//   - One app with the Godot game (Part C): AUTOMATIC, all from pet.gd. On every export
//     the Godot add-on reads PETS, ANIMS and ACTIONS from pet.gd, sorts every pet's PNGs
//     into animations exactly like the game does, and packs them into
//     assets/wallpaper_frames/. Nothing to edit here; the PETS, ANIMS and ACTIONS lists
//     below are only the stand-ins used when that information is missing.
//   - Wallpaper-only app (Part B): the PETS, ANIMS and ACTIONS lists below, with the
//     frames copied by hand into app/src/main/assets/pets/<name>/.
//
// >>> HOW TO ADD A NEW PET <<<
//   One app with the game: add it to PETS in pet.gd (search "ADD PET" there). Done.
//   Wallpaper-only app:
//   1. Export its frames as separate PNGs, named like the dragon's (see ANIMS below):
//      egg_idle_00.png, egg_hatch_00.png, cat_emerge_00.png, idle_a_00.png, walk_a_00.png
//   2. Put them in their own folder: assets/pets/<name>/, e.g. pets/cat/
//   3. Add one line to PETS below, e.g.  PetType("cat", "Cat", "pets/cat"),
//   The setup screen shows a "Which pet?" question as soon as there is more than one.
//
// How to find things:
//   [ADD PET]    = where new pets go
//   [ADD ACTION] = where new movements the pet does by itself go
//   [EDIT]       = a setting you can safely change
// =====================================================================================

package com.yourname.projectp.wallpaper

import java.io.File

/**
 * One pet.
 *   id     = short name used in saved data, e.g. "dragon". Never change it after release,
 *            or users lose their saved progress for that pet. Use the same id as in pet.gd.
 *   name   = name shown to the user on the "Which pet?" screen.
 *   folder = its frame folder inside the app's assets, e.g. "pets/dragon".
 */
data class PetType(val id: String, val name: String, val folder: String)

/**
 * One action.
 *   frames = how many frame files it uses when files are only numbered
 *   fps    = frames per second (higher = faster)
 *   loop   = true repeats forever, false plays once and then calls onAnimationFinished()
 *   names  = what its files are called, without the frame number. The pet's name in
 *            front is allowed: "idle" also matches dragon_idle_00.png, cat_idle_00.png...
 */
data class Anim(val frames: Int, val fps: Int, val loop: Boolean, val names: List<String>)

/**
 * One thing the pet may do by itself between blinks.
 *   kind   = "blink"  : nothing new, it keeps resting and blinking (a longer idle)
 *            "travel" : goes to a random spot on the left or right with this animation
 *            "hop"    : jumps up on the spot with this animation, then plays "landing"
 *            "play"   : plays this animation once where it stands
 *   anim   = the animation it uses (a name from ANIMS; empty for "blink")
 *   weight = how often it is picked compared with the others (4 = four times as often
 *            as 1; 0 = switched off)
 */
data class Action(val kind: String, val anim: String, val weight: Float)

/**
 * Everything about how the pets animate and behave, in one bundle. Comes from pet.gd
 * (one app with the game) or from the lists in PetCatalog below.
 */
class PetTable(
    val anims: Map<String, Anim>,       // the animations
    val actions: List<Action>,          // what the pet does by itself
    val waitMin: Float,                 // seconds of blinking between two actions
    val waitMax: Float,
    val blinkFrames: Int,               // frames in one blink
    val fromGame: Boolean,              // true = read from the Godot game's export
    // Movements with several versions: animation -> frames per version. Playing such an
    // animation plays ONE version, picked at random ("trick#1", "trick#2", ...).
    val sets: Map<String, Int> = PetCatalog.ANIM_SETS,
    // Low energy: at or below this battery percent (and not charging) the pet picks from
    // lowActions instead of actions.
    val lowBatteryPercent: Int = PetCatalog.LOW_BATTERY_PERCENT,
    val lowActions: List<Action> = PetCatalog.LOW_ENERGY_ACTIONS,
    // Sleep: between these hours (24-hour clock) the pet plays "sleep" instead of
    // pet_idle; a tap or a shake wakes it for awakeMinutes.
    val sleepFrom: Int = PetCatalog.SLEEP_FROM_HOUR,
    val sleepUntil: Int = PetCatalog.SLEEP_UNTIL_HOUR,
    val awakeMinutes: Float = PetCatalog.AWAKE_MINUTES,
    // The game's screen as set in Godot (Project Settings > Display > Window): its width
    // and height in the game's own units, whether Stretch is on, and the Stretch Scale.
    // With these the wallpaper shows the pet at the same size on screen as the game does.
    val gameWidth: Float = 720f,
    val gameHeight: Float = 1280f,
    val gameStretches: Boolean = true,
    val gameScale: Float = 1f,
    // pet_size in pet.gd: the pet's size in the game until the player resizes it (0 =
    // not known, the wallpaper's own drawScale is used).
    val defaultSize: Float = 0f
) {
    /**
     * How many screen pixels one unit of the game's screen is on a screen of this size.
     * (Godot fits the game's screen into the phone's screen: the smaller of the two
     * ratios, the same for every Stretch Aspect except "ignore", which is close to it.)
     */
    fun gamePixel(screenW: Float, screenH: Float): Float {
        val fit = if (gameStretches) minOf(screenW / gameWidth, screenH / gameHeight) else 1f
        return fit * gameScale
    }
}

object PetCatalog {

    // [ADD PET] Used by the wallpaper-only app (Part B). Inside the Godot game's app the
    //           list comes from pet.gd instead (see fromGameList below).
    //           One line per pet: PetType(id, name shown to the user, assets folder).
    //           The FIRST pet is the default.
    val PETS = listOf(
        PetType("dragon", "Dragon", "pets/dragon"),
        // PetType("cat", "Cat", "pets/cat"),
        // PetType("fox", "Fox", "pets/fox"),
    )

    // [EDIT] The animations: Anim(frames, fps, loop, file names it accepts).
    //        Files are matched by name first (egg_idle_03.png -> egg_idle,
    //        idle_b_03.png -> pet_idle, fly_a_00.png -> move). If no names match, files
    //        are taken in number order: the first 8 -> egg_idle, the next 8 -> egg_hatch...
    //        The second number is the speed. Keep in sync with ANIMS in pet.gd (Godot).
    //        "move" is played while the pet travels sideways (by itself, sent by a tap,
    //        or the phone tilted on the lock screen). fly_ frames make it bob in the air.
    //        "move_left" / "move_right": if a pet has these, they are used when it travels
    //        that way (no mirroring). With only "move", one set serves both ways.
    //        "trick" holds the pet's tricks, 8 frames each; one is played at a time.
    //        "low_energy" is played on a low battery, "sleep" is its resting animation
    //        at night (see the settings below ACTIONS).
    //        "greet" is optional: frames named greet_00.png, hello_00.png or wave_00.png
    //        are played when the lock screen appears. Without them the pet hops instead.
    val ANIMS = linkedMapOf(
        "egg_idle" to Anim(8, 6, true, listOf("egg_idle")),
        "egg_hatch" to Anim(8, 10, false, listOf("egg_hatch", "egg_hatch_emerge")),
        "pet_emerge" to Anim(8, 10, false, listOf("pet_emerge", "emerge")),
        "pet_idle" to Anim(8, 8, true, listOf("pet_idle", "idle")),
        "jump" to Anim(8, 12, false, listOf("jump", "jump_land_a", "jump_landing_a")),
        "landing" to Anim(8, 12, false, listOf("landing", "jump_land_b", "jump_landing_b")),
        "ticklish" to Anim(8, 12, false, listOf("ticklish", "ticklish_recovery_a")),
        "recovery" to Anim(8, 10, false, listOf("recovery", "ticklish_recovery_b")),
        "move" to Anim(32, 12, true, listOf("move", "fly", "walk", "run", "hop")),
        "move_left" to Anim(8, 12, true,
            listOf("move_left", "fly_left", "walk_left", "run_left")),
        "move_right" to Anim(8, 12, true,
            listOf("move_right", "fly_right", "walk_right", "run_right")),
        "trick" to Anim(16, 10, false, listOf("trick", "extra", "special", "dance")),
        "low_energy" to Anim(8, 8, false, listOf("low_energy", "low_battery", "tired")),
        "sleep" to Anim(8, 6, true, listOf("sleep", "sleeping", "asleep")),
        "greet" to Anim(8, 10, false, listOf("greet", "hello", "wave")),
    )

    // [EDIT] WHAT THE PET DOES BY ITSELF (wallpaper-only app; inside the Godot game's app
    //        this comes from ACTIONS in pet.gd). Most of the time the hatched pet rests
    //        and blinks (pet_idle). After ACTION_WAIT_MIN..ACTION_WAIT_MAX seconds it
    //        picks one line below at random, does it, and goes back to resting.
    //        Action(what it does, animation, weight) - see "Action" above.
    //        An action whose animation has no frames for the pet is skipped.
    // [ADD ACTION] Add the animation to ANIMS above (loop = false), then a line here,
    //        e.g.  Action("play", "spin", 2f),
    val ACTIONS = listOf(
        Action("blink", "", 4f),           // keep blinking a while longer
        Action("travel", "move", 3f),      // fly / walk / run to the left or right
        Action("hop", "jump", 2f),         // jump on the spot (jump, then landing)
        Action("play", "trick", 2f),       // one of its tricks (see ANIM_SETS)
    )
    // [EDIT] Seconds of resting and blinking between two actions (a random time in this
    //        range), and how many frames one blink has (an action starts between blinks).
    const val ACTION_WAIT_MIN = 3f
    const val ACTION_WAIT_MAX = 7f
    const val BLINK_FRAMES = 8

    // The settings below are the stand-ins for the wallpaper-only app. Inside the Godot
    // game's app they all come from pet.gd (SECTION 0), where they have the same names.

    // [EDIT] MOVEMENTS WITH SEVERAL VERSIONS: animation -> frames per version. With
    //        "trick" to 8, trick_a_00..07 is one trick and trick_b_00..07 another; when
    //        the pet plays "trick" it picks ONE of them at random.
    val ANIM_SETS = mapOf("trick" to 8, "low_energy" to 8)

    // [EDIT] LOW ENERGY: at or below this battery percent, and not charging, the pet
    //        picks from this list instead of ACTIONS.
    const val LOW_BATTERY_PERCENT = 15
    val LOW_ENERGY_ACTIONS = listOf(
        Action("blink", "", 3f),           // keep blinking a while longer
        Action("play", "low_energy", 4f),  // one of its low-energy movements
    )

    // [EDIT] SLEEP: between these hours of the phone's clock (24-hour: 23 = 11 PM) the
    //        pet sleeps; a tap or a shake wakes it for AWAKE_MINUTES.
    const val SLEEP_FROM_HOUR = 23
    const val SLEEP_UNTIL_HOUR = 6
    const val AWAKE_MINUTES = 5f

    /** The lists above as one bundle (used when pet.gd's lists aren't in the app). */
    fun defaultTable() =
        PetTable(ANIMS, ACTIONS, ACTION_WAIT_MIN, ACTION_WAIT_MAX, BLINK_FRAMES, false)

    /**
     * Which animation a frame file belongs to, from its name (null if none).
     *   "egg_idle_03.png"    -> "egg_idle"  (exact name)
     *   "dragon_idle_03.png" -> "pet_idle"  (pet name in front + "idle")
     *   "idle_b_03.png"      -> "pet_idle"  (extra rows a, b, c, d from the slicer)
     * [EDIT] If a file isn't recognised, add its name (without the number) to ANIMS.
     */
    fun animForFile(fileName: String): String? {
        val label = fileName.substringBeforeLast('.').lowercase()
            .replace(Regex("[ _-]*\\d+$"), "")           // remove the frame number
        return animForLabel(label)
    }

    private fun animForLabel(label: String): String? {
        // 1) exact match, e.g. "egg_idle", "jump_land_a"
        ANIMS.entries.firstOrNull { label in it.value.names }?.let { return it.key }
        // 2) pet name in front, e.g. "dragon_idle" ends with "_idle"
        ANIMS.entries.firstOrNull { e -> e.value.names.any { label.endsWith("_$it") } }
            ?.let { return it.key }
        // 3) extra rows from the slicer, e.g. "idle_b" -> try "idle"
        if (Regex("_[a-z]$").containsMatchIn(label)) return animForLabel(label.dropLast(2))
        return null
    }

    /**
     * Sorts a pet's frame file names into animations: by name if they match ANIMS,
     * otherwise by number order. Returns e.g. { "egg_idle": [file names...], ... }.
     */
    fun groupFrames(fileNames: List<String>): Map<String, List<String>> {
        val sorted = fileNames.sortedWith(FRAME_ORDER)
        val byName = LinkedHashMap<String, MutableList<String>>()
        for (name in sorted) {
            val anim = animForFile(name) ?: continue
            byName.getOrPut(anim) { mutableListOf() }.add(name)
        }
        if (byName.isNotEmpty()) return byName
        val result = LinkedHashMap<String, List<String>>()
        var next = 0
        for ((name, anim) in ANIMS) {
            result[name] = sorted.drop(next).take(anim.frames)
            next += anim.frames
        }
        return result
    }

    // Saved settings shared by the setup screen and the wallpaper.
    const val PREFS = "pet_wallpaper"     // name of the saved-settings file
    const val KEY_PET = "pet_id"          // which pet the user chose

    // Where the Godot add-on puts things inside the app's assets (one app with the game).
    const val GAME_FRAMES = "wallpaper_frames"                 // + "/<pet id>/<frame>.png"
    const val GAME_PET_LIST = "wallpaper_frames/pets.txt"      // one pet id per line
    // ANIMS and ACTIONS from pet.gd, written by the add-on (see tableFromGame below).
    const val GAME_TABLE = "wallpaper_frames/anims.txt"
    // In each pet's folder: which frame files belong to which animation, sorted by the
    // add-on with pet.gd's own rules (see framesFromList below).
    const val FRAME_LIST = "frames.txt"

    // The animated Project P wallpaper: the assets folder with its frames, and the kinds
    // of picture files it accepts. With the Godot add-on the frames are packed there from
    // addons/projectp_wallpaper/default_wallpaper_frames/ on every export. In the
    // wallpaper-only app, copy them into app/src/main/assets/wallpaper_bg_frames/.
    // No frames = the still picture (pet_default_bg.png) is used.
    const val DEFAULT_BG_FRAMES = "wallpaper_bg_frames"
    val PICTURE_TYPES = setOf("png", "jpg", "jpeg", "webp")

    /**
     * Turns the add-on's pet list (one id per line, same order as PETS in pet.gd) into
     * pets. The name shown to the user is the id with capitals: "ice_dragon" -> "Ice Dragon".
     */
    fun fromGameList(text: String): List<PetType> =
        text.lines().map { it.trim() }.filter { it.isNotEmpty() }.map { id ->
            val name = id.split('_', '-', ' ').filter { it.isNotEmpty() }
                .joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
            PetType(id, name, "$GAME_FRAMES/$id")
        }

    /**
     * Reads the animations and actions the add-on copied from pet.gd. One entry per line:
     *   anim|pet_idle|8.0|true          name, frames per second, loops?
     *   actions|1                       pet.gd has an ACTIONS list (the lines below)
     *   action|travel|move|3            what it does, animation, weight
     *   wait|3.0|7.0                    seconds between actions (min, max)
     *   blink|8                         frames per blink
     *   sets|1  and  set|trick|8        movements with several versions: frames each
     *   lowbattery|15                   low energy at or below this battery percent
     *   lowactions|1  and  lowaction|play|low_energy|4   what it does then
     *   sleep|23|6|5.0                  asleep from, until (hours), minutes awake after a tap
     *   gamescreen|720|1280|canvas_items|1.0   the game's screen: width, height,
     *                                   Stretch Mode, Stretch Scale
     *   petsize|2.0                     pet_size in pet.gd (the size before any resizing)
     * Animations pet.gd doesn't list (e.g. "greet") keep their values from ANIMS above.
     * Anything missing or unreadable falls back to the lists above.
     */
    fun tableFromGame(text: String): PetTable {
        val anims = LinkedHashMap(ANIMS)
        val actions = ArrayList<Action>()
        var waitMin = ACTION_WAIT_MIN
        var waitMax = ACTION_WAIT_MAX
        var blink = BLINK_FRAMES
        var listsActions = false         // pet.gd has an ACTIONS list (even an empty one)
        val sets = LinkedHashMap<String, Int>()
        var listsSets = false            // pet.gd has ANIM_SETS (even an empty one)
        val lowActions = ArrayList<Action>()
        var listsLowActions = false
        var lowBattery = LOW_BATTERY_PERCENT
        var sleepFrom = SLEEP_FROM_HOUR
        var sleepUntil = SLEEP_UNTIL_HOUR
        var awakeMinutes = AWAKE_MINUTES
        var gameWidth = 720f
        var gameHeight = 1280f
        var gameStretches = true
        var gameScale = 1f
        var defaultSize = 0f
        for (raw in text.lines()) {
            val part = raw.trim().split('|').map { it.trim() }
            try {
                when (part[0]) {
                    "anim" -> {
                        val fps = part[2].toFloat().toInt().coerceIn(1, 60)
                        val old = anims[part[1]]
                        anims[part[1]] = Anim(
                            old?.frames ?: 8, fps, part[3] == "true", old?.names ?: emptyList())
                    }
                    "actions" -> listsActions = true
                    "action" -> actions += Action(part[1], part[2], part[3].toFloat())
                    "wait" -> {
                        waitMin = part[1].toFloat()
                        waitMax = part[2].toFloat()
                    }
                    "blink" -> blink = part[1].toFloat().toInt().coerceAtLeast(1)
                    "sets" -> listsSets = true
                    "set" -> {
                        val per = part[2].toFloat().toInt()
                        if (per > 0) sets[part[1]] = per
                    }
                    "lowbattery" -> lowBattery = part[1].toFloat().toInt()
                    "lowactions" -> listsLowActions = true
                    "lowaction" -> lowActions += Action(part[1], part[2], part[3].toFloat())
                    "sleep" -> {
                        sleepFrom = part[1].toFloat().toInt()
                        sleepUntil = part[2].toFloat().toInt()
                        awakeMinutes = part[3].toFloat().coerceAtLeast(0f)
                    }
                    "gamescreen" -> {
                        gameWidth = part[1].toFloat().coerceAtLeast(1f)
                        gameHeight = part[2].toFloat().coerceAtLeast(1f)
                        gameStretches = part[3] != "disabled"
                        gameScale = part[4].toFloat().takeIf { it > 0f } ?: 1f
                    }
                    "petsize" -> defaultSize = part[1].toFloat().coerceAtLeast(0f)
                }
            } catch (e: Exception) {
                // a line that can't be read is skipped
            }
        }
        if (waitMax < waitMin) waitMax = waitMin
        // No ACTIONS in pet.gd (an older pet.gd): the list above. An empty ACTIONS list
        // in pet.gd is respected: the pet then only rests and blinks.
        val chosen = if (listsActions) actions else actions.ifEmpty { ACTIONS }
        return PetTable(
            anims, chosen, waitMin, waitMax, blink, true,
            sets = if (listsSets) sets else ANIM_SETS,
            lowBatteryPercent = lowBattery,
            lowActions = if (listsLowActions) lowActions else LOW_ENERGY_ACTIONS,
            sleepFrom = sleepFrom, sleepUntil = sleepUntil, awakeMinutes = awakeMinutes,
            gameWidth = gameWidth, gameHeight = gameHeight,
            gameStretches = gameStretches, gameScale = gameScale, defaultSize = defaultSize
        )
    }

    /**
     * Reads a pet's frame list written by the add-on. One line per animation:
     *   pet_idle=idle_a_00.png/idle_a_01.png/...
     * Returns { "pet_idle": [file names in playing order], ... }.
     */
    fun framesFromList(text: String): Map<String, List<String>> {
        val result = LinkedHashMap<String, List<String>>()
        for (raw in text.lines()) {
            val line = raw.trim()
            if (!line.contains('=')) continue
            val files = line.substringAfter('=').split('/').map { it.trim() }
                .filter { it.isNotEmpty() }
            if (files.isNotEmpty()) result[line.substringBefore('=').trim()] = files
        }
        return result
    }

    /** Finds a pet by id in a list; falls back to the first pet if the id is unknown. */
    fun byId(pets: List<PetType>, id: String?): PetType =
        pets.firstOrNull { it.id == id } ?: pets.first()

    /**
     * Sorts frame file names by their numbers, so "frame_2.png" comes before
     * "frame_10.png". Works with names like 01.png, frame_1.png or idle_b_03.png.
     */
    val FRAME_ORDER = Comparator<String> { a, b ->
        val chunksA = Regex("\\d+|\\D+").findAll(a.lowercase()).map { it.value }.toList()
        val chunksB = Regex("\\d+|\\D+").findAll(b.lowercase()).map { it.value }.toList()
        for (i in 0 until minOf(chunksA.size, chunksB.size)) {
            val x = chunksA[i]
            val y = chunksB[i]
            val cmp = if (x[0].isDigit() && y[0].isDigit()) {
                x.toBigInteger().compareTo(y.toBigInteger())   // compare as numbers
            } else {
                x.compareTo(y)                                 // compare as text
            }
            if (cmp != 0) return@Comparator cmp
        }
        chunksA.size - chunksB.size
    }
}

// =====================================================================================
// GameSave  -  READS THE GODOT GAME'S SAVE FILE (only when both are in one app)
// =====================================================================================
// When the wallpaper is packaged inside the Godot game's APK, both share the same
// private storage. The game saves to "user://pet.cfg", which is the file "pet.cfg" in
// that storage, so the wallpaper can read it to follow the game:
//   - which pet the player chose      ->  [game]   chosen_pet="dragon"
//   - whether that pet has hatched    ->  [dragon] hatched=true
//   - how big the player made it      ->  [dragon] size=2.0
// In the wallpaper-only app this file doesn't exist, and everything here returns
// "nothing", so the wallpaper uses its own settings instead.
// The wallpaper only READS this file; it never changes the game's save.
// [FIX] If the wallpaper doesn't follow the game, check the names above still match
//       what pet.gd and pet_picker.gd save (SAVE_PATH, "hatched", "chosen_pet").
//       The pet is chosen on the pet grid, opened from the main menu (main_menu.gd).
object GameSave {

    const val FILE_NAME = "pet.cfg"

    /** The save file as { section -> { key -> value } }. Empty if there is no file. */
    fun read(filesDir: File): Map<String, Map<String, String>> {
        val file = File(filesDir, FILE_NAME)
        if (!file.exists()) return emptyMap()
        val result = LinkedHashMap<String, MutableMap<String, String>>()
        var section = ""
        try {
            for (raw in file.readLines()) {
                val line = raw.trim()
                if (line.startsWith("[") && line.endsWith("]")) {
                    section = line.substring(1, line.length - 1)
                } else if (line.contains("=") && !line.startsWith(";")) {
                    val key = line.substringBefore("=").trim()
                    val value = line.substringAfter("=").trim().removeSurrounding("\"")
                    result.getOrPut(section) { LinkedHashMap() }[key] = value
                }
            }
        } catch (e: Exception) {
            return emptyMap()
        }
        return result
    }

    /** The pet chosen in the game, or null if the game hasn't saved one. */
    fun chosenPet(filesDir: File): String? =
        read(filesDir)["game"]?.get("chosen_pet")?.takeIf { it.isNotEmpty() }

    /** Has this pet hatched in the game? */
    fun isHatched(filesDir: File, petId: String): Boolean =
        read(filesDir)[petId]?.get("hatched") == "true"

    /**
     * The size the player gave this pet in the game ([dragon] size=2.0): 1 = the frame's
     * own size on the game's screen, 2 = twice that. null if the game hasn't saved one.
     */
    fun size(filesDir: File, petId: String): Float? =
        read(filesDir)[petId]?.get("size")?.toFloatOrNull()?.takeIf { it > 0f }
}
