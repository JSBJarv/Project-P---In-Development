// =====================================================================================
// PetWallpaperService.kt  -  THE PET ON THE HOME SCREEN AND LOCK SCREEN
// =====================================================================================
// What this file does:
//   This is the live wallpaper. It draws the background (the Project P wallpaper, still
//   or animated, the user's own pictures, or their GIF) and the animated pet on top.
//   The user can have one picture for the home screen and another for the lock screen.
//   - Home screen: tap the pet to tickle it (it glows softly while it listens); then
//     tap any spot and it goes there (sideways it flies or walks, up or down it jumps).
//     No finger drag is needed, so the home screen's own swipes (app list, pages) don't
//     get mixed up with moving the pet.
//   - By itself, on both screens: the pet mostly rests and blinks. Now and then it
//     does one thing picked at random from the ACTIONS list (travels left or right,
//     hops, plays ONE of its tricks, or just keeps blinking), then rests again.
//   - Low battery (15% or less, not charging): it picks from the low-energy list
//     instead. At night (11 PM to 6 AM by the phone's clock) it sleeps; a tap on the
//     home screen or a shake on the lock screen wakes it for a few minutes.
//   - Its size is the size the player gave it in the game (one app with the game).
//   - Lock screen (no touch there): the pet greets you with a hop when the screen turns
//     on, giggles when you shake the phone, hops when you tilt the phone up, and flies
//     or walks towards the side you tilt it to. A GIF background is animated on the
//     lock screen and kept still on the home screen.
//   Android runs this whenever the home screen or lock screen is visible, and pauses it
//   when an app covers the screen.
//
// How to find things:
//   [EDIT]  = a setting you can safely change (sizes, speeds, what is switched on...)
//   [LOGIC] = rules for how the pet behaves (what plays after what)
//   [FIX]   = places to look first if something goes wrong
//
// Sections in this file:
//   1. Which pet is shown                                  -> search "SECTION 1"
//   2. Settings (size, taps, what the pet does where)      -> search "SECTION 2"
//   3. Loaded images and saved data                        -> search "SECTION 3"
//   4. Pet state (position, animation, moving, sensors)    -> search "SECTION 4"
//   5. Wallpaper lifecycle (start, resize, show/hide)      -> search "SECTION 5"
//   6. Loading a pet + animation rules (hatch, tickle...)  -> search "SECTION 6"
//   7. Touch: tap, tap to move (home screen)               -> search "SECTION 7"
//   8. Background (default, own pictures, GIF, animation)  -> search "SECTION 8"
//   9. Drawing each frame                                  -> search "SECTION 9"
//  10. Home screen or lock screen?                         -> search "SECTION 10"
//  11. What the pet does by itself; travelling, jumping    -> search "SECTION 11"
//  12. Phone movement: shake and tilt                      -> search "SECTION 12"
//  13. Sleeping at night and low energy                    -> search "SECTION 13"
//
// Adding more pets: you don't need to change this file. See PetCatalog.kt.
//
// One app with the Godot game: this file works unchanged there. It then follows the
// game's save (chosen pet, hatched, size) through GameSave in PetCatalog.kt.
//
// Related files:
//   PetCatalog.kt             - the list of pets and the animation layout ([ADD PET])
//   SetWallpaperActivity.kt   - the setup screens (questions, pet choice, photo picker)
//   assets/wallpaper_frames/<id>/*.png  - frames packed by the Godot add-on (one app)
//   assets/pets/<name>/*.png             - frames copied by hand (wallpaper-only app)
//   res/drawable-nodpi/pet_default_bg.png  - the Project P wallpaper (still picture)
//   assets/wallpaper_bg_frames/*           - its animation frames, if you supply any
//   AndroidManifest.xml       - registers this wallpaper with Android
// =====================================================================================

package com.yourname.projectp.wallpaper

import android.app.KeyguardManager
import android.app.WallpaperManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.*
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.ExifInterface
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.service.wallpaper.WallpaperService
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.ViewConfiguration
import java.io.File
import java.util.Calendar
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * The pets this app can show.
 *   - Inside the Godot game's app: the list the add-on packed (same pets as pet.gd).
 *   - Wallpaper-only app: the PETS list in PetCatalog.kt.
 * [FIX] If the wallpaper shows the wrong pets, check the Output line of the Godot export
 *       ("Project P Wallpaper: ... pets: ...").
 */
fun availablePets(context: Context): List<PetType> {
    val fromGame = try {
        context.assets.open(PetCatalog.GAME_PET_LIST).bufferedReader().use { it.readText() }
    } catch (e: Exception) {
        null                           // no list from the game: wallpaper-only app
    }
    val pets = if (fromGame != null) PetCatalog.fromGameList(fromGame) else emptyList()
    return pets.ifEmpty { PetCatalog.PETS }
}

/**
 * How the pets animate and behave (animations, actions, waiting times).
 *   - Inside the Godot game's app: ANIMS and ACTIONS from pet.gd, packed by the add-on.
 *   - Wallpaper-only app: the lists in PetCatalog.kt.
 */
fun petTable(context: Context): PetTable {
    val fromGame = try {
        context.assets.open(PetCatalog.GAME_TABLE).bufferedReader().use { it.readText() }
    } catch (e: Exception) {
        null                           // not packed by the game: use PetCatalog's lists
    }
    return if (fromGame != null) PetCatalog.tableFromGame(fromGame) else PetCatalog.defaultTable()
}

/**
 * Which of a pet's frame files belong to which animation, in playing order:
 * { "pet_idle": ["idle_a_00.png", ...], "move": [...], ... }.
 *   - Inside the Godot game's app: the list the add-on wrote (frames.txt in the pet's
 *     folder), sorted with pet.gd's own rules, so the wallpaper always agrees with the
 *     game about which file is which.
 *   - Otherwise: sorted here by file name with PetCatalog.groupFrames().
 * [FIX] An animation is missing on the phone: open the wallpaper setup and tap
 *       "Check my pet". It shows how many frames each animation got.
 */
fun petFrameFiles(context: Context, folder: String): Map<String, List<String>> {
    val inFolder = try {
        (context.assets.list(folder) ?: emptyArray()).toList()
    } catch (e: Exception) {
        emptyList()
    }
    val listed = try {
        context.assets.open("$folder/${PetCatalog.FRAME_LIST}").bufferedReader()
            .use { it.readText() }
    } catch (e: Exception) {
        null
    }
    if (listed != null) {
        // Keep only files that really are in the app
        val groups = PetCatalog.framesFromList(listed)
            .mapValues { (_, files) -> files.filter { it in inFolder } }
            .filterValues { it.isNotEmpty() }
        if (groups.isNotEmpty()) return groups
    }
    return PetCatalog.groupFrames(inFolder.filter { it.lowercase().endsWith(".png") })
}

/**
 * The phone's battery: how full it is (0..100, or -1 if the phone doesn't say) and
 * whether it is plugged in. Android hands this out to every app; no permission needed.
 */
fun phoneBattery(context: Context): Pair<Int, Boolean> {
    val info = try {
        context.applicationContext.registerReceiver(
            null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    } catch (e: Exception) {
        null
    } ?: return -1 to false
    val level = info.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
    val full = info.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
    val percent = if (level >= 0 && full > 0) level * 100 / full else -1
    val plugged = info.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
    return percent to plugged
}

/**
 * One frame's soft outline, for the glow around a listening pet: the frame's shape,
 * blurred, made from a small copy of the frame (frameW x frameH pixels). `left` and
 * `top` say where it sits compared with that copy (it is a little bigger on every side).
 */
private class Glow(
    val shape: Bitmap, val left: Int, val top: Int, val frameW: Int, val frameH: Int
)

/**
 * One of the user's own pictures: the one for the home screen or the one for the lock
 * screen. Filled in by loadPicture() (SECTION 8).
 */
private class UserPicture(val fileName: String) {
    var fitted: Bitmap? = null     // the picture cut and scaled to the screen (null = none)
    @Suppress("DEPRECATION")
    var gif: Movie? = null         // the same picture as a GIF, if it is an animated one
    var stamp = 0L                 // when the file was last changed (reload only if newer)
}

/** Android asks this service for an "engine" each time the wallpaper is shown. */
class PetWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = PetEngine()

    // The animations, the actions and the other rules for the pets: from pet.gd when the
    // wallpaper is inside the Godot game's app, otherwise from PetCatalog.kt. Read once.
    private val rules: PetTable by lazy { petTable(this) }

    // [LOGIC] A pet woken up at night stays awake until this moment (milliseconds since
    //         the phone was switched on). Kept here so the home screen and the lock
    //         screen agree.
    @Volatile private var awakeUntil = 0L

    // ===== THE LOADED PET'S PICTURES (shared) ========================================
    // Android can run several engines at once (home screen, lock screen, the preview).
    // They all show the same pet, so its pictures are loaded once here and shared, and
    // the old pet's pictures are thrown away BEFORE the new pet's are loaded. That keeps
    // memory low when the pet is changed, which matters with many frames per pet.
    // [EDIT] The most memory one pet's frames may use, in megabytes. Bigger pets are
    //        loaded at half size (and drawn at the same size on screen) to fit.
    private val frameMemoryLimitMb = 96
    private var loadedPetId: String? = null
    private var loadedFrames: Map<String, List<Bitmap>> = emptyMap()
    // The animations whose frames are fly_ frames: the pet bobs in the air while it
    // travels with one of these.
    private var loadedBobAnims: Set<String> = emptySet()
    private var loadedFrameW = 128          // size of one frame file in pixels
    private var loadedFrameH = 128

    /** The pet's pictures, loading them first if another pet (or none) is loaded. */
    private fun framesFor(pet: PetType): Map<String, List<Bitmap>> {
        if (pet.id == loadedPetId) return loadedFrames
        freeFrames()                         // old pet out first, then the new one in
        loadedFrames = try {
            loadFrames(pet.folder)
        } catch (e: Throwable) {
            emptyMap()                       // no pictures: the background still shows
        }
        loadedPetId = pet.id
        return loadedFrames
    }

    private fun freeFrames() {
        val old = loadedFrames
        loadedFrames = emptyMap()
        loadedPetId = null
        old.values.flatten().distinct().forEach { it.recycle() }
    }

    // Loads the pet's frames, sorted into animations by petFrameFiles() (top of this
    // file): with the list from the Godot game, or by file name.
    // [FIX] If an action shows the wrong pictures, check ANIMS in pet.gd (one app with
    //       the game) or the names listed in PetCatalog.ANIMS (wallpaper-only app).
    private fun loadFrames(folder: String): Map<String, List<Bitmap>> {
        val grouped = petFrameFiles(this, folder)
        // Frames named fly_... mean the pet flies (and bobs in the air) with that animation
        loadedBobAnims = grouped.filterValues {
            it.firstOrNull()?.lowercase()?.startsWith("fly") == true
        }.keys
        // Measure one frame, then decide whether the frames must be loaded smaller.
        val firstName = grouped.values.flatten().firstOrNull() ?: return emptyMap()
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        assets.open("$folder/$firstName").use { BitmapFactory.decodeStream(it, null, bounds) }
        loadedFrameW = bounds.outWidth.coerceAtLeast(1)
        loadedFrameH = bounds.outHeight.coerceAtLeast(1)
        val count = grouped.values.sumOf { it.size }
        var shrink = 1
        while (loadedFrameW.toLong() * loadedFrameH * 4L * count / (shrink * shrink) >
            frameMemoryLimitMb * 1024L * 1024L
        ) shrink *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = shrink }
        val loaded = LinkedHashMap<String, List<Bitmap>>()
        for ((anim, files) in grouped) {
            loaded[anim] = files.mapNotNull { name ->
                assets.open("$folder/$name").use { BitmapFactory.decodeStream(it, null, opts) }
            }
        }
        // [LOGIC] Movements with several versions (ANIM_SETS in pet.gd / PetCatalog.kt):
        //         besides the whole animation, each version gets its own entry, named
        //         "trick#1", "trick#2", ... (the same pictures, not loaded twice). The
        //         pet plays ONE of them at a time, see oneVersion() in SECTION 11.
        for ((anim, perVersion) in rules.sets) {
            val all = loaded[anim] ?: continue
            if (perVersion <= 0) continue
            for (v in 0 until all.size / perVersion) {
                loaded["$anim#${v + 1}"] =
                    all.subList(v * perVersion, (v + 1) * perVersion).toList()
            }
        }
        return loaded
    }

    // A helper thread that prepares the animated Project P wallpaper's next frame, so
    // loading big pictures never makes the pet stutter (SECTION 8).
    private val frameLoader = Executors.newSingleThreadExecutor()

    // The wallpaper was removed or replaced: give the memory back.
    override fun onDestroy() {
        frameLoader.shutdown()
        freeFrames()
        super.onDestroy()
    }

    /** The engine does all the work: drawing, animation, touch and phone movement. */
    @Suppress("DEPRECATION")   // android.graphics.Movie (GIF) is old but works everywhere
    inner class PetEngine : Engine() {

        // ===== SECTION 1: WHICH PET IS SHOWN =========================================
        // The animation layout and the list of pets live in PetCatalog.kt.
        // [ADD PET] New pets are added there (or in pet.gd for the one-app setup).
        // The animations, the actions and the waiting times: from pet.gd when the
        // wallpaper is inside the Godot game's app, otherwise from PetCatalog.kt.
        private val table = rules
        private val anims = table.anims
        // Used for an animation name nobody listed, so nothing can go wrong with it.
        private val plainAnim = Anim(8, 8, false, emptyList())
        // One version of a movement ("trick#2") has the speed and looping of "trick".
        private fun animOf(name: String) =
            anims[name] ?: anims[name.substringBefore('#')] ?: plainAnim

        // ===== SECTION 2: SETTINGS ====================================================
        // [EDIT] How many taps on the egg before it hatches.
        private val tapsToHatch = 3
        // [EDIT] true = the pet is as big as the player made it in the game (pinching it
        //        there), so it looks the same in the app and on the home screen. Resize
        //        it in the game and the wallpaper follows the next time it is shown.
        //        false = always use drawScale below.
        private val sizeFollowsGame = true
        // [EDIT] Pet size on screen when the game's size isn't used (wallpaper-only app,
        //        or sizeFollowsGame = false): 2f = each 128px frame is drawn at 256px.
        //        Use 1.5f for smaller, 3f for bigger.
        private val drawScale = 2f
        // [EDIT] true if the pet frames are pixel art (keeps hard pixel edges);
        //        false for smooth, painted frames (softens the edges when scaled).
        private val petIsPixelArt = false
        // [EDIT] Same choice for the Project P wallpaper picture (pet_default_bg.png).
        private val defaultBackgroundIsPixelArt = false

        // --- Moving the pet on the home screen ---
        // [EDIT] Tap to move: tap the pet (it giggles and glows softly while it listens),
        //        then tap a spot and it goes there. false switches this off.
        private val tapToMove = true
        // [EDIT] How many seconds the pet keeps listening for the "go there" tap.
        private val listenSeconds = 4f
        // [EDIT] true = a tap mostly above or below the pet makes every pet jump there
        //        (jump frames, then landing frames). false = pets with fly_ frames fly
        //        there instead and only walking pets jump.
        private val flyersJumpUpAndDown = true
        // [EDIT] Moving the pet by dragging it with a finger. Off, because the home screen
        //        reacts to the same drag (opens the app list, switches pages). With true,
        //        both ways of moving the pet work.
        private val dragToMove = false
        // [EDIT] Show the soft glow around a listening pet and at the spot it's going to.
        private val showMarks = true
        // [EDIT] The glow: its colour (a warm white) with a wider, softer edge in a
        //        second colour (amber, so the glow also shows on a white picture); how
        //        strong it is at most (0f = invisible, 1f = strongest; 0.7f is subtle);
        //        how far it reaches around the pet as a share of the pet's width; and
        //        the size of the glow at the spot the pet is going to (in dp; 26 is
        //        about the size of a fingertip).
        private val glowColor = Color.rgb(255, 248, 225)
        private val glowEdgeColor = Color.rgb(255, 186, 84)
        private val glowStrength = 0.7f
        private val glowReach = 0.09f
        private val spotGlowDp = 26f
        // [EDIT] true = where the home screen reports taps on empty space, only those
        //        taps send the pet somewhere (a tap on an app icon just opens the app).
        //        false = any tap sends it. See onCommand() in SECTION 7.
        private val useHomeScreenTapReports = true

        // --- What the pet does on which screen ---
        // [EDIT] Doing things by itself now and then (the ACTIONS list: travelling,
        //        hopping, playing a movement). false = it only rests and blinks there.
        //        WHAT it does and HOW OFTEN is not set here: inside the Godot game's app
        //        that is ACTIONS and ACTION_WAIT_MIN / MAX in pet.gd (SECTION 0); in the
        //        wallpaper-only app it is ACTIONS in PetCatalog.kt.
        private val roamOnLockScreen = true
        private val roamOnHomeScreen = true
        // [EDIT] Reacting to shaking and tilting the phone. Off on the home screen by
        //        default, because normal handling of the phone would keep setting it off.
        private val motionOnLockScreen = true
        private val motionOnHomeScreen = false
        // [EDIT] A little hop when the lock screen appears (screen turned on).
        //        (A sleeping pet doesn't greet.)
        private val greetOnLockScreen = true
        // [EDIT] Sleeping at night and low energy on a low battery (SECTION 13). The
        //        hours, the battery percent and the low-energy list are set in pet.gd
        //        (SECTION 0) or, for the wallpaper-only app, in PetCatalog.kt.
        private val sleepsAtNight = true
        private val tiresOnLowBattery = true
        // [EDIT] Moving backgrounds (a GIF the user picked, or the animated Project P
        //        wallpaper): where they play. Where they don't play, they stand still.
        //        Playing on the home screen too costs more battery.
        private val animateBackgroundOnLockScreen = true
        private val animateBackgroundOnHomeScreen = false
        // [EDIT] Speed of the animated Project P wallpaper, in frames per second.
        //        8 is calm; use 12 for smoother movement (needs more frames).
        private val defaultAnimationFps = 8

        // --- Travelling ---
        // [EDIT] Travel speed, in screen widths per second (0.25 = 4 seconds to cross).
        private val moveSpeed = 0.25f
        // [EDIT] How high flying pets bob while travelling, as a share of the pet's height.
        private val moveBob = 0.06f
        // [EDIT] Which way the pet faces in its fly_/walk_ frames. If it travels
        //        backwards, change this to false.
        private val moveFramesFaceRight = true

        // --- Hopping (greeting, tilt up) and jumping to a spot (tap to move) ---
        // [EDIT] Hop height as a share of the pet's height, and how long a hop lasts.
        private val hopHeight = 0.5f
        private val hopSeconds = 0.7f
        // [EDIT] Speed of a jump to another spot, in screen heights per second (0.8 = the
        //        whole screen in 1.25 seconds), and how much higher the arc gets with
        //        distance (0 = flat, 0.25 = a quarter of the distance).
        private val jumpSpeed = 0.8f
        private val jumpArc = 0.25f

        // --- Phone movement ---
        // [EDIT] How hard a shake must be (higher = shake harder). 7 is a clear shake.
        private val shakeStrength = 7f
        // [EDIT] How far to tilt sideways, from the way the phone is normally held, before
        //        the pet travels that way (higher = more tilt). 2.5 needs a clear tilt of
        //        about 20 degrees.
        private val tiltSideways = 2.5f
        // [EDIT] How many degrees the top of the phone must be raised, within about a
        //        second, for a hop.
        private val tiltUpDegrees = 18f

        // ===== SECTION 3: LOADED IMAGES AND SAVED DATA ================================
        // Small saved settings: chosen pet, pet position ("x", "y") with the pet's size
        // at that moment ("w", "h"), and, for each pet, whether it has hatched
        // ("hatched_<id>").
        // [FIX] To reset the pets to eggs while testing: clear the app's storage in
        //       Android Settings > Apps > (your app) > Storage.
        private val prefs = getSharedPreferences(PetCatalog.PREFS, Context.MODE_PRIVATE)
        // Every pet this app can show (from the game's pet.gd, or PetCatalog.PETS).
        private val pets = availablePets(this@PetWallpaperService)

        // The chosen pet and its frames. Loaded by loadPet() (SECTION 6), and reloaded
        // when another pet is picked in the game or the setup screen.
        // frames["egg_idle"] = the egg_idle pictures in order, and so on for every action.
        // [FIX] If the pet doesn't show, check the export's Output line names this pet.
        private var pet: PetType = PetCatalog.byId(pets, null)
        private var frames: Map<String, List<Bitmap>> = emptyMap()
        // The animations this pet flies with (fly_ frames): it bobs in the air with them.
        private var bobAnims: Set<String> = emptySet()
        // Size of one frame file in pixels, measured from the first PNG (e.g. 128).
        private var frameW = 128
        private var frameH = 128
        // Size of the pet on screen, in pixels. Set by applySize() (SECTION 6).
        private var petW = frameW * drawScale
        private var petH = frameH * drawScale

        // Paint without smoothing (hard pixel edges) and with smoothing (soft edges).
        private val pixelPaint = Paint().apply { isFilterBitmap = false; isAntiAlias = false }
        private val smoothPaint = Paint().apply { isFilterBitmap = true }
        private val petPaint = if (petIsPixelArt) pixelPaint else smoothPaint
        // The glow around a listening pet and at its destination (SECTION 9).
        private val glowPaint = Paint().apply { isAntiAlias = true; isFilterBitmap = true }
        private val spotPaint = Paint().apply { isAntiAlias = true }
        // Made the first time a frame glows, then kept (see glowOf).
        private val glows = HashMap<Bitmap, Glow>()
        // The round glow at the destination: bright in the middle, fading to nothing.
        private val spotLight: Shader by lazy {
            RadialGradient(
                0f, 0f, 1f,
                intArrayOf(
                    glowColor, Color.argb(110, Color.red(glowColor), Color.green(glowColor),
                        Color.blue(glowColor)),
                    Color.argb(0, Color.red(glowColor), Color.green(glowColor),
                        Color.blue(glowColor))),
                floatArrayOf(0f, 0.4f, 1f), Shader.TileMode.CLAMP)
        }
        // Its wider, softer edge in the second colour (shows on a light picture too).
        private val spotEdge: Shader by lazy {
            val r = Color.red(glowEdgeColor)
            val g = Color.green(glowEdgeColor)
            val b = Color.blue(glowEdgeColor)
            RadialGradient(
                0f, 0f, 1.35f,
                intArrayOf(Color.argb(150, r, g, b), Color.argb(90, r, g, b),
                    Color.argb(0, r, g, b)),
                floatArrayOf(0f, 0.6f, 1f), Shader.TileMode.CLAMP)
        }
        // [EDIT] Colour used if pet_default_bg.png is missing.
        private val fallbackColor = Color.parseColor("#F6E7F0")
        // The Project P wallpaper (res/drawable-nodpi/pet_default_bg.png) cut and scaled
        // to the screen. Loaded the first time it's needed (SECTION 8).
        private var defaultFitted: Bitmap? = null
        private var defaultTried = false
        // The user's own pictures (null inside = none chosen): one for the home screen and,
        // if they said their lock screen is different, one for the lock screen.
        private val homePicture = UserPicture(SetWallpaperActivity.BACKGROUND_FILE)
        private val lockPicture = UserPicture(SetWallpaperActivity.LOCK_BACKGROUND_FILE)
        // The animated Project P wallpaper: the names of its frame files, in order (empty =
        // no animation, the still picture is used). See "ANIMATED PROJECT P WALLPAPER" in
        // SECTION 8.
        private val defaultFrameFiles: List<String> = try {
            (assets.list(PetCatalog.DEFAULT_BG_FRAMES) ?: emptyArray())
                .filter { it.substringAfterLast('.').lowercase() in PetCatalog.PICTURE_TYPES }
                .sortedWith(PetCatalog.FRAME_ORDER)
        } catch (e: Throwable) {
            emptyList()
        }
        private var shownFrame: Bitmap? = null   // the frame on screen, fitted to the screen
        private var readyFrame: Bitmap? = null   // the next frame, prepared and waiting
        private var spareFrame: Bitmap? = null   // a finished frame, reused for the next one
        private var shownFrameIndex = -1
        private var readyFrameIndex = -1
        private var frameIsLoading = false
        private var frameShownSince = 0L
        private var frameBatch = 0               // goes up when the screen size changes
        private var frameFailures = 0            // unreadable frames in a row
        // Runs the animation timer on the main thread.
        private val handler = Handler(Looper.getMainLooper())
        // How far a finger can move and still count as a tap (Android's standard value).
        private val tapSlop =
            ViewConfiguration.get(this@PetWallpaperService).scaledTouchSlop.toFloat()
        // A touch counts as a tap only if the finger lifts within this time (milliseconds).
        private val MAX_TAP_MILLIS = 350L
        // A trip is undone if the wallpaper is hidden this soon after the tap (SECTION 11).
        private val UNDO_TRIP_MILLIS = 800L
        // Tells us whether the phone is showing its lock screen (SECTION 10).
        private val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        // Tells us whether the screen is really on (not dimmed to an always-on display).
        private val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        // The phone's movement sensor (SECTION 12). null on devices without one.
        private val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        private val accelerometer: Sensor? =
            sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        // ===== SECTION 4: PET STATE ===================================================
        // Is the wallpaper on screen right now? (false while an app covers it)
        private var visible = false
        // Is it the lock screen we're showing on? (SECTION 10)
        private var onLockScreen = false
        // Is the screen fully on? false while it is off or showing an always-on display.
        private var awake = true
        // Screen size in pixels.
        private var screenW = 0f
        private var screenH = 0f
        // Top-left corner of the pet on screen.
        private var petX = 0f
        private var petY = 0f

        // Has the egg hatched? Saved per pet, so each pet keeps its own progress.
        private var hatched = false
        // Name of the animation playing now (a key in PetCatalog.ANIMS), its frame, and
        // when that frame was shown.
        private var current = "egg_idle"
        private var frame = 0
        private var frameShownAt = 0L
        // true while a play-once animation (hatching, tickle, hop) must not be interrupted.
        private var busy = false
        // Taps counted on the egg so far.
        private var eggTaps = 0

        // Finger tracking for taps and drags (SECTION 7).
        private var fingerDown = false // a finger is on the screen
        private var downOnPet = false  // ...and it first touched the pet
        private var dragging = false   // the pet is being carried (only with dragToMove)
        private var moved = false      // finger moved too far to count as a tap
        private var downX = 0f         // where the finger first touched
        private var downY = 0f
        private var grabX = 0f         // where on the pet the finger grabbed it
        private var grabY = 0f
        // Tap to move (SECTION 7): the pet listens for a "go there" tap until this time.
        private var listeningUntil = 0L
        private var listeningSince = 0L    // when it started listening (the glow fades in)
        // The spot it was sent to, marked until it arrives.
        private var markShown = false
        private var markX = 0f
        private var markY = 0f
        // Where and when that trip began (to undo it if the tap really opened an app).
        private var tripFromX = 0f
        private var tripFromY = 0f
        private var tripStartedAt = 0L
        // true once the home screen has told us about a tap on empty space (see
        // onCommand in SECTION 7). Remembered, so it's known right after a restart.
        private var homeReportsTaps = prefs.getBoolean("home_reports_taps", false)
        private var unreportedTaps = 0   // taps in a row the home screen didn't report

        // Travelling (SECTION 11).
        private var moving = false         // the pet is travelling across the screen
        private var travelAnim = "move"    // ...with this animation
        private var movingByTilt = false   // ...because the phone is tilted (not wandering)
        private var moveTargetX = 0f       // where it's going
        private var moveTargetY = 0f
        private var moveLineY = 0f         // its height along the way, without the bob
        private var moveTime = 0f          // seconds since setting off (for the bob)
        private var nextMoveIn = 10f       // seconds until it wanders off again
        private var facingLeft = false     // the pet is drawn mirrored (see travelPick)
        private var headingLeft = false    // which way its current or last trip goes
        // Hopping and jumping (SECTION 11). hopStartedAt = 0 means "not in the air".
        private var hopStartedAt = 0L
        private var hopMillis = 700f       // how long this hop or jump lasts
        private var hopArc = 0f            // how high its arc is, in pixels
        private var hopFromX = 0f          // where it took off
        private var hopFromY = 0f
        private var hopToX = 0f            // where it lands (same spot for a hop in place)
        private var hopToY = 0f
        private var lastGreetAt = 0L

        // Sleeping and low energy (SECTION 13)
        private var bedtime = false        // the phone's clock is in the sleeping hours
        private var clockReadAt = 0L
        private var lowEnergy = false      // the battery is low and the phone isn't charging
        private var batteryReadAt = 0L

        // Phone movement (SECTION 12).
        private var sensorOn = false
        private var gravityKnown = false
        private var gravX = 0f             // the slow, steady part of the sensor reading:
        private var gravY = 0f             // which way is "down" for the phone
        private var gravZ = 0f
        private var restX = 0f             // how far sideways the phone is normally held
        private var sideTilt = 0f          // sideways tilt compared with that
        private var slowLift = 0f          // how far the top has been raised lately
        private var lastSensorAt = 0L      // when the last reading arrived
        private var joltCount = 0          // sharp movements counted towards a shake
        private var firstJoltAt = 0L
        private var lastJoltAt = 0L
        private var lastCountedJoltAt = 0L
        private var lastShakeAt = 0L
        private var lastTiltHopAt = 0L

        // Timer bookkeeping.
        private var lastTickAt = 0L
        private var lastLockCheckAt = 0L
        private var gifStartedAt = 0L

        // The animation timer. Each tick it moves the pet's animation on, moves the pet if
        // it's travelling or hopping, draws, and schedules itself again. It ticks quickly
        // (about 30 times a second) only while something is moving; otherwise it ticks at
        // the animation's own speed to save battery. It stops when the wallpaper is hidden.
        private val tick = object : Runnable {
            override fun run() {
                if (!visible) return
                val now = SystemClock.uptimeMillis()
                val dt = (now - lastTickAt).coerceIn(0L, 250L) / 1000f
                lastTickAt = now
                try {
                    // Another engine switched to a new pet: follow it
                    if (frames !== loadedFrames) loadPet()
                    if (now - lastLockCheckAt > 100L) updateLockState()
                    if (!awake) {
                        // Screen off or always-on display: do nothing, look again shortly
                        handler.postDelayed(this, 200L)
                        return
                    }
                    stepAnimation(now)
                    stepMoving(dt)
                    stepHop(now)
                    stepRest()
                    stepActionTimer(dt)
                    stepDefaultAnimation(now)
                    drawFrame()
                } catch (e: Throwable) {
                    // Never let one bad frame take the whole wallpaper down.
                }
                handler.postDelayed(this, nextTickDelay())
            }
        }

        private fun nextTickDelay(): Long =
            if (moving || hopStartedAt != 0L || backgroundIsAnimating() ||
                (showMarks && isListening())      // the glow breathes smoothly
            ) 33L
            else (1000L / animOf(current).fps).coerceAtMost(250L)   // timers need ticks

        // Run the timer right now (used when something starts moving between ticks).
        private fun tickNow() {
            if (!visible) return
            handler.removeCallbacks(tick)
            handler.post(tick)
        }

        init {
            loadPet()     // load the chosen pet before anything is drawn
        }

        // ===== SECTION 5: WALLPAPER LIFECYCLE =========================================
        // Called once when the wallpaper starts.
        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            setTouchEventsEnabled(true)   // without this the pet can't be tapped or dragged
        }

        // Called when the screen size is known or changes (e.g. first start, rotation).
        override fun onSurfaceChanged(
            holder: SurfaceHolder, format: Int, width: Int, height: Int
        ) {
            super.onSurfaceChanged(holder, format, width, height)
            screenW = width.toFloat()
            screenH = height.toFloat()
            applySize()                   // the pet's size depends on the screen's size
            loadPosition()
            try {
                // Screen size changed: every picture is fitted again at the new size
                defaultFitted = null
                defaultTried = false
                homePicture.stamp = 0L
                lockPicture.stamp = 0L
                forgetDefaultFrames()
                loadPicturesIfChanged()
            } catch (e: Throwable) {
                // Not enough memory for a fitted copy: the plain colour is drawn instead.
            }
            // The surface can be made again while the wallpaper stays visible: make sure
            // the animation timer is running.
            visible = isVisible
            drawFrame()
            tickNow()
        }

        // Called with true when the home/lock screen appears and false when an app covers it
        // or the screen turns off. This is what hides the pet in other apps and saves battery.
        override fun onVisibilityChanged(isVisible: Boolean) {
            visible = isVisible
            handler.removeCallbacks(tick)
            try {
                if (isVisible) {
                    if (PetCatalog.byId(pets, chosenPetId()).id != pet.id) {
                        // Another pet was picked (in the game or the setup screen): switch.
                        // Only the pet changes; the background stays as it is.
                        loadPet()
                    } else if (!hatched && GameSave.isHatched(filesDir, pet.id)) {
                        // The pet hatched in the game since we last looked
                        hatched = true
                        playIdle()
                    }
                    applySize()                   // resized in the game since last time?
                    loadPosition()
                    refreshRest()                 // asleep or awake, tired or not: know
                                                  // it before the first picture is drawn
                    loadPicturesIfChanged()       // picks up newly chosen pictures
                    updateLockState()
                    lastTickAt = SystemClock.uptimeMillis()
                    gifStartedAt = lastTickAt
                    drawFrame()                   // right picture for this screen, at once
                    if (onLockScreen && awake && greetOnLockScreen) greet()
                } else {
                    settleDown()                  // finish any trip or hop cleanly
                    dragging = false              // a finger that never lifted is forgotten
                    moved = false
                    // The screen is switching off and the lock screen has its own picture:
                    // draw it now, so it's already there when the screen comes back on.
                    if (lockPicture.fitted != null && !power.isInteractive && !onLockScreen) {
                        onLockScreen = true
                        drawFrame()
                    }
                }
            } catch (e: Throwable) {
                // Keep the wallpaper running even if something above goes wrong.
            }
            updateSensor()
            tickNow()                             // restart the animation (if visible)
        }

        // Called when the wallpaper's drawing surface goes away: stop everything.
        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            visible = false
            handler.removeCallbacks(tick)
            updateSensor()
            super.onSurfaceDestroyed(holder)
        }

        // Called when the wallpaper is removed or replaced: stop and give the memory back.
        override fun onDestroy() {
            visible = false
            handler.removeCallbacks(tick)
            updateSensor()
            try {
                forgetGlows()
                forgetDefaultFrames()
                defaultFitted?.recycle()
                defaultFitted = null
                for (p in listOf(homePicture, lockPicture)) {
                    p.fitted?.recycle()
                    p.fitted = null
                    p.gif = null
                }
            } catch (e: Throwable) {
                // nothing to do: the memory is freed later by Android
            }
            super.onDestroy()
        }

        // ===== SECTION 6: LOADING A PET AND ANIMATION RULES ===========================
        // Loads the chosen pet's frames and saved progress, and starts it idling.
        // The background is not touched here.
        private fun loadPet() {
            // If the old pet was mid-trip or mid-hop, put it back down first
            if (moving) petY = moveLineY
            if (hopStartedAt != 0L) {
                petX = hopToX
                petY = hopToY
                savePosition()
            }
            movingByTilt = false
            markShown = false
            listeningUntil = 0L
            pet = PetCatalog.byId(pets, chosenPetId())
            forgetGlows()                // they belong to the old pet's pictures
            frames = framesFor(pet)      // loads the pictures (see the top of this file)
            bobAnims = loadedBobAnims
            frameW = loadedFrameW
            frameH = loadedFrameH
            applySize()
            // Hatched if it hatched on the wallpaper, or in the game (one app with the game)
            hatched = prefs.getBoolean("hatched_${pet.id}", false) ||
                GameSave.isHatched(filesDir, pet.id)
            eggTaps = 0
            moving = false
            hopStartedAt = 0L
            facingLeft = false
            playIdle()
            resetRoamTimer()
            clampPet()
        }

        // [LOGIC] HOW BIG THE PET IS ON SCREEN.
        //   One app with the game: the size the player gave the pet in the game (pinch
        //   it there; saved as "size" in the game's save file), or pet_size from pet.gd
        //   if it was never resized. The game draws a frame at
        //       frame size x pet size x (phone screen / game screen)
        //   pixels, and so does the wallpaper: the pet looks the same in both.
        //   Wallpaper-only app (or sizeFollowsGame = false): frame size x drawScale.
        //   When the size changes, the pet keeps its middle where it was.
        // Why there is no resizing on the home screen itself: a wallpaper only gets a
        // copy of each touch, and a pinch there already belongs to the home screen (it
        // opens its own menu on most phones), so both would react at once.
        // [FIX] The pet is the wrong size on the home screen: open the game, pinch the pet
        //       to the size you want, go back to the home screen. "Check my pet" in the
        //       wallpaper setup shows the size it found.
        private fun applySize() {
            var scale = drawScale
            if (sizeFollowsGame && table.fromGame && screenW > 0f) {
                val size = GameSave.size(filesDir, pet.id)
                    ?: table.defaultSize.takeIf { it > 0f }
                if (size != null) scale = size * table.gamePixel(screenW, screenH)
            }
            if (screenW > 0f) {          // never bigger than the screen
                scale = min(scale, min(screenW / frameW, screenH / frameH))
            }
            val w = frameW * scale
            val h = frameH * scale
            if (w == petW && h == petH) return
            petX += (petW - w) / 2f      // keep its middle where it was
            petY += (petH - h) / 2f
            petW = w
            petH = h
            if (screenW > 0f) clampPet()
        }

        // Which pet to show: the one chosen in the Godot game if the wallpaper is inside
        // the game's app (see GameSave in PetCatalog.kt), otherwise the one picked in the
        // wallpaper's own setup screen.
        private fun chosenPetId(): String? =
            GameSave.chosenPet(filesDir) ?: prefs.getString(PetCatalog.KEY_PET, null)

        // Does this pet have pictures for an animation?
        private fun has(name: String) = (frames[name]?.size ?: 0) > 0

        // Start an animation from its first frame.
        private fun play(name: String) {
            current = name
            frame = 0
            frameShownAt = SystemClock.uptimeMillis()
        }

        // Go back to resting: egg_idle before hatching; after it pet_idle (blinking), or
        // "sleep" at night (see restAnim in SECTION 13).
        private fun playIdle() {
            busy = false
            play(restAnim())
        }

        // Shows the next frame when the current one has been on screen long enough.
        // Looping animations wrap around; play-once animations call onAnimationFinished().
        private fun stepAnimation(now: Long) {
            val a = animOf(current)
            if (now - frameShownAt < 1000L / a.fps) return
            frameShownAt = now
            val count = frames[current]?.size ?: 0     // frames actually found for it
            when {
                frame < count - 1 -> frame++
                a.loop -> frame = 0
                else -> onAnimationFinished(current)
            }
        }

        // [LOGIC] What plays after each play-once animation ends.
        //         Change these lines to change the order of animations.
        private fun onAnimationFinished(name: String) {
            when (name) {
                // egg cracks -> pet comes out. If hatching and emerging are one animation
                // (frames named egg_hatch_emerge_..), there is no pet_emerge to play.
                "egg_hatch" -> if (has("pet_emerge")) play("pet_emerge") else finishHatching()
                "pet_emerge" -> finishHatching()
                "ticklish" -> play("recovery")               // tickled -> calms down
                "recovery", "landing", "greet" -> playIdle() // -> back to resting
                // "jump" holds its last frame while the pet is in the air or carried
                "jump" -> if (!moving && hopStartedAt == 0L && !dragging) playIdle()
                // Any other play-once animation (e.g. "trick#2", "low_energy#1", or one
                // you added to ACTIONS): back to resting. While the pet is travelling or in the air
                // with it, it holds the last frame until it arrives.
                else -> if (!moving && hopStartedAt == 0L) playIdle()
            }
        }

        // The pet is out of its egg: remember it and start resting.
        private fun finishHatching() {
            hatched = true
            prefs.edit().putBoolean("hatched_${pet.id}", true).apply()
            playIdle()
        }

        // Can the pet start something new right now? (hatched, not mid-animation, not held)
        private fun isFree() = hatched && !busy && !dragging

        // [LOGIC] Tickle: ticklish, then recovery (see onAnimationFinished), then idle.
        //         Used by a tap on the home screen and by shaking the phone.
        private fun tickle() {
            if (!isFree()) return
            stopMoving()
            busy = true
            play("ticklish")
            tickNow()
        }

        // [LOGIC] What a tap on the pet does.
        //         Egg: count taps, hatch after tapsToHatch (SECTION 2).
        //         Pet: tickle, and listen for a "go there" tap (SECTION 7).
        //         Sleeping pet: the tap wakes it up (SECTION 13); the next tap tickles.
        private fun onTap() {
            val wokeIt = wakeUp()     // (also keeps an awake pet awake at night)
            if (hatched && tapToMove && current != "sleep") {
                // Listen (again) for the next tap, even if it is still giggling
                val now = SystemClock.uptimeMillis()
                if (!isListening()) listeningSince = now
                listeningUntil = now + (listenSeconds * 1000f).toLong()
            }
            if (wokeIt || current == "sleep") {   // it was asleep: this tap woke it,
                drawFrame()                       // nothing more
                return
            }
            if (busy) {               // hatching, being tickled or in the air: nothing new
                drawFrame()
                return
            }
            if (!hatched) {
                eggTaps++
                if (eggTaps >= tapsToHatch) {
                    busy = true
                    when {
                        has("egg_hatch") -> play("egg_hatch")     // hatches (and emerges)
                        has("pet_emerge") -> play("pet_emerge")   // only emerge frames
                        else -> finishHatching()                  // no hatching frames
                    }
                }
            } else {
                tickle()
            }
            drawFrame()
        }

        // ===== SECTION 7: TOUCH (TAP AND TAP TO MOVE, HOME SCREEN) ====================
        // [LOGIC] A tap is a finger that goes down and up without moving.
        //         Tap on the pet        -> onTap(): the egg counts taps; the pet giggles and
        //                                  listens for listenSeconds (it glows softly).
        //         Tap somewhere else while it listens -> goTo(): the pet travels there.
        //         Anything that isn't a tap (a swipe, a long drag) is left to the home
        //         screen: it opens the app list or switches pages, and the pet stays put.
        //         With dragToMove (SECTION 2) the pet can also be carried by a finger.
        // The lock screen keeps all touches for itself, so none of this runs there.
        // A wallpaper only gets a copy of each touch; it can't keep the home screen from
        // reacting to it too. That's why moving the pet uses taps: the home screen does
        // nothing on a tap on empty space.
        override fun onTouchEvent(event: MotionEvent) {
            try {
                handleTouch(event)
            } catch (e: Throwable) {
                // ignore: a touch must never crash the wallpaper
            }
            super.onTouchEvent(event)
        }

        private fun handleTouch(event: MotionEvent) {
            when (event.actionMasked) {
                // Finger touches the screen: remember where, and whether it was on the pet
                MotionEvent.ACTION_DOWN -> {
                    fingerDown = true
                    dragging = false
                    moved = false
                    downX = event.x
                    downY = event.y
                    downOnPet = isOnPet(event.x, event.y)
                    // Carrying the pet (only with dragToMove); the hatching egg is left alone
                    if (dragToMove && downOnPet && !(busy && !hatched)) {
                        stopMoving()                      // grabbing it ends any trip
                        if (hopStartedAt != 0L) {         // ...or jump, right where it is
                            hopStartedAt = 0L
                            playIdle()
                            savePosition()
                        }
                        markShown = false
                        dragging = true
                        grabX = event.x - petX
                        grabY = event.y - petY
                    }
                }
                // A second finger: this is a gesture for the home screen, not a tap
                MotionEvent.ACTION_POINTER_DOWN -> moved = true
                // Finger moves: past tapSlop it's no longer a tap
                MotionEvent.ACTION_MOVE -> if (fingerDown) {
                    if (!moved && hypot(event.x - downX, event.y - downY) > tapSlop) {
                        moved = true
                        if (dragging && hatched) { busy = false; play("jump") }   // picked up
                    }
                    if (dragging && moved) {
                        petX = event.x - grabX
                        petY = event.y - grabY
                        clampPet()
                        drawFrame()
                    }
                }
                // Finger lifts: a tap, or the end of carrying the pet
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (fingerDown) {
                    fingerDown = false
                    // A tap is short; a long press belongs to the home screen (its menu)
                    val wasTap = !moved && event.actionMasked == MotionEvent.ACTION_UP &&
                        event.eventTime - event.downTime < MAX_TAP_MILLIS
                    if (dragging) {
                        dragging = false
                        if (moved) {
                            if (hatched) play("landing")
                            savePosition()
                            resetRoamTimer()
                        }
                    }
                    if (wasTap) {
                        if (downOnPet) onTap()
                        // Home screens that report taps on empty space do so through
                        // onCommand() below; for the others, any tap counts.
                        else if (isListening()) onTapElsewhere(event.x, event.y)
                    }
                }
            }
        }

        // [LOGIC] Many home screens (Pixel and others built on the same base) tell the
        //         wallpaper when the user taps EMPTY space, not an app icon or a widget.
        //         Once a home screen has done that, only those taps send the pet
        //         somewhere, so tapping an app icon while the pet listens just opens the
        //         app. On home screens that never report taps, every tap counts.
        //         If a home screen stops reporting (the user switched to another one),
        //         three taps in a row without a report switch back to "every tap counts".
        // [FIX] The pet doesn't go to tapped spots although it glows: set
        //       useHomeScreenTapReports (SECTION 2) to false.

        // A tap away from the pet, seen through the touch copy, while the pet listens.
        private fun onTapElsewhere(x: Float, y: Float) {
            if (!homeReportsTaps) {
                goTo(x, y)                         // this home screen doesn't report taps
                return
            }
            // The home screen's own report (onCommand) normally follows and sends the pet.
            // Three taps in a row without one: it doesn't report (any more).
            unreportedTaps++
            if (unreportedTaps >= 3) {
                setHomeReportsTaps(false)
                goTo(x, y)
            }
        }

        private fun setHomeReportsTaps(reports: Boolean) {
            unreportedTaps = 0
            if (homeReportsTaps == reports) return
            homeReportsTaps = reports
            prefs.edit().putBoolean("home_reports_taps", reports).apply()
        }

        override fun onCommand(
            action: String?, x: Int, y: Int, z: Int, extras: Bundle?, resultRequested: Boolean
        ): Bundle? {
            try {
                if (useHomeScreenTapReports && action == WallpaperManager.COMMAND_TAP) {
                    setHomeReportsTaps(true)
                    if (!isOnPet(x.toFloat(), y.toFloat()) && isListening()) {
                        goTo(x.toFloat(), y.toFloat())
                    }
                }
            } catch (e: Throwable) {
                // ignore: a command must never crash the wallpaper
            }
            return super.onCommand(action, x, y, z, extras, resultRequested)
        }

        // [LOGIC] Is this spot on the pet? Inside its frame, AND on (or within a
        //         fingertip of) the drawn part of the picture. The empty corners of the
        //         frame don't count, so a big pet doesn't swallow taps meant for the app
        //         icons around it.
        // [EDIT] tapReachDp: how far from the drawn part a tap still counts (in dp).
        private val tapReachDp = 14f
        private fun isOnPet(x: Float, y: Float): Boolean {
            if (x < petX || x > petX + petW || y < petY || y > petY + petH) return false
            if (petW <= 0f || petH <= 0f) return false
            try {
                val picture = frames[current]?.getOrNull(frame) ?: return true
                if (picture.isRecycled) return true
                val reach = tapReachDp * resources.displayMetrics.density
                for (stepY in -1..1) for (stepX in -1..1) {
                    var px = ((x + stepX * reach - petX) / petW * picture.width).toInt()
                    val py = ((y + stepY * reach - petY) / petH * picture.height).toInt()
                    if (facingLeft) px = picture.width - 1 - px      // drawn mirrored
                    if (px < 0 || py < 0 || px >= picture.width || py >= picture.height) continue
                    if (Color.alpha(picture.getPixel(px, py)) > 40) return true
                }
                return false
            } catch (e: Throwable) {
                return true           // can't look at the picture: the whole frame counts
            }
        }

        // Is the pet waiting for a "go there" tap? (never on the lock screen)
        private fun isListening() = tapToMove && hatched && !onLockScreen &&
            SystemClock.uptimeMillis() < listeningUntil

        // [LOGIC] Tap to move: sends the pet to the tapped spot (its middle ends up there).
        //         Mostly to the left or right -> it travels with its move frames (fly,
        //                                        walk...), facing the way it goes.
        //         Mostly up or down           -> it jumps there: jump frames while it is
        //                                        in the air, landing frames on arrival.
        //         (With flyersJumpUpAndDown = false, flying pets fly everywhere.)
        //         A pet without the needed frames uses the other way; with neither, it
        //         simply appears at the spot.
        private fun goTo(x: Float, y: Float) {
            if (!hatched || dragging || current == "sleep") return
            // A giggle is cut short; a greeting, a jump or a landing finish first (the pet
            // keeps listening, so the tap can simply be repeated)
            if (busy && (current == "ticklish" || current == "recovery")) playIdle()
            if (busy || hopStartedAt != 0L) return
            if (moving && markShown) return        // already on its way (same tap, twice)
            stopMoving()
            val toX = (x - petW / 2f).coerceIn(0f, max(0f, screenW - petW))
            val toY = (y - petH / 2f).coerceIn(0f, max(0f, screenH - petH))
            val dx = toX - petX
            val dy = toY - petY
            if (hypot(dx, dy) < tapSlop) return    // already there
            listeningUntil = 0L                    // one trip per tap on the pet
            tripFromX = petX
            tripFromY = petY
            tripStartedAt = SystemClock.uptimeMillis()
            markX = x
            markY = y
            markShown = true
            val upOrDown = abs(dy) > abs(dx)
            val flies = listOf("move", "move_left", "move_right").any { it in bobAnims }
            val mayJump = has("jump") && (flyersJumpUpAndDown || !flies)
            when {
                upOrDown && mayJump -> jumpTo(toX, toY)
                canTravel("move") -> startMoving(toX, false, toY)
                has("jump") -> jumpTo(toX, toY)
                else -> {                          // no frames for either: just be there
                    petX = toX
                    petY = toY
                    markShown = false
                    savePosition()
                    drawFrame()
                }
            }
        }

        // Where the pet sits. Saved when it arrives somewhere (or is put down after a drag),
        // together with how big it was then.
        private fun savePosition() {
            prefs.edit().putFloat("x", petX).putFloat("y", petY)
                .putFloat("w", petW).putFloat("h", petH).apply()
        }

        // [EDIT] Where the pet starts the very first time: centred, 60% down the screen.
        //        After that, the saved position is used.
        // If the pet has been resized since its position was saved, it stays centred on
        // the same spot.
        private fun loadPosition() {
            if (screenW <= 0f || dragging || moving || hopStartedAt != 0L) return
            if (prefs.contains("x")) {
                val savedW = prefs.getFloat("w", frameW * drawScale)
                val savedH = prefs.getFloat("h", frameH * drawScale)
                petX = prefs.getFloat("x", 0f) + (savedW - petW) / 2f
                petY = prefs.getFloat("y", 0f) + (savedH - petH) / 2f
            } else {
                petX = (screenW - petW) / 2f
                petY = screenH * 0.6f
            }
            clampPet()
        }

        // ===== SECTION 8: BACKGROUND ==================================================
        // What is behind the pet, in this order:
        //   1. On the lock screen: the user's lock screen picture, if they chose one.
        //   2. The user's home screen picture, if they chose one (also used on the lock
        //      screen when they said both screens are the same).
        //   3. Otherwise the Project P wallpaper: animated if you supplied frames,
        //      else the still picture.
        // The pictures are chosen in SetWallpaperActivity and saved in the app's private
        // storage (files/background.img and files/background_lock.img).
        // Changing the pet never changes any of this.

        // Loads the user's pictures if they are new or were replaced.
        private fun loadPicturesIfChanged() {
            loadPicture(homePicture)
            loadPicture(lockPicture)
            if (homePicture.fitted != null) {
                // The user's own picture is in use: the Project P wallpaper isn't needed
                forgetDefaultFrames()
                defaultFitted?.recycle()
                defaultFitted = null
                defaultTried = false
            }
        }

        private fun loadPicture(p: UserPicture) {
            val file = File(filesDir, p.fileName)
            if (!file.exists()) {                  // none chosen (or it was removed)
                p.fitted?.recycle()
                p.fitted = null
                p.gif = null
                p.stamp = 0L
                return
            }
            if (file.lastModified() == p.stamp && p.fitted != null) return
            if (screenW <= 0f || screenH <= 0f) return
            try {
                // Read the size first, then load a smaller copy so big pictures
                // don't use too much memory
                // [FIX] If big photos crash the app (out of memory), this is the place.
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.path, bounds)
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= screenW &&
                    bounds.outHeight / (sample * 2) >= screenH
                ) sample *= 2
                val opts = BitmapFactory.Options().apply { inSampleSize = sample }
                var bmp = BitmapFactory.decodeFile(file.path, opts) ?: return
                // Turn photos the right way up if the camera stored them sideways
                // [FIX] If a photo shows sideways, check this rotation part.
                val rotation = when (ExifInterface(file.path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
                if (rotation != 0f) {
                    bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height,
                        Matrix().apply { postRotate(rotation) }, true)
                }
                val fitted = fitToScreen(bmp, smoothPaint)
                bmp.recycle()
                p.fitted?.recycle()
                p.fitted = fitted
                p.stamp = file.lastModified()
                p.gif = loadGif(file)
            } catch (e: Throwable) {
                p.fitted = null       // unreadable picture -> the next choice in the list
                p.gif = null
            }
        }

        // If the picture is a GIF with more than one frame, returns it ready to animate.
        // [FIX] A GIF that stays still on the lock screen: check it really is a .gif file
        //       (some gallery apps save a still copy), and animateBackgroundOnLockScreen.
        //       Very large GIFs (full-HD with many frames) may be too big to load; they
        //       then show as a still picture. Smaller GIFs (about 480px wide) play best.
        private fun loadGif(file: File): Movie? {
            return try {
                val header = ByteArray(4)
                file.inputStream().use { it.read(header) }
                if (String(header, Charsets.US_ASCII) != "GIF8") return null
                Movie.decodeFile(file.path)?.takeIf { it.duration() > 0 }
            } catch (e: Throwable) {
                null
            }
        }

        // [LOGIC] Which of the user's pictures belongs on the screen showing now
        //         (null = none chosen: the Project P wallpaper is used).
        private fun pictureForThisScreen(): UserPicture? = when {
            onLockScreen && lockPicture.fitted != null -> lockPicture
            homePicture.fitted != null -> homePicture
            else -> null
        }

        // May a moving background play on the screen showing now? (SECTION 2)
        private fun animationAllowedHere() =
            if (onLockScreen) animateBackgroundOnLockScreen else animateBackgroundOnHomeScreen

        // Is the Project P wallpaper in use, and does it have frames that can be read?
        private fun defaultHasFrames() = pictureForThisScreen() == null &&
            defaultFrameFiles.isNotEmpty() && frameFailures < defaultFrameFiles.size

        // Is the background moving right now (a GIF, or the animated Project P wallpaper)?
        private fun backgroundIsAnimating() = awake && animationAllowedHere() &&
            (pictureForThisScreen()?.gif != null ||
                (defaultHasFrames() && defaultFrameFiles.size > 1))

        // Draws the background (see the list at the top of this section).
        private fun drawBackground(canvas: Canvas) {
            // Start from a plain colour, so see-through pictures don't show leftovers
            canvas.drawColor(fallbackColor)
            val own = pictureForThisScreen()
            val movie = own?.gif
            val picture = when {
                own != null -> own.fitted
                // Animated Project P wallpaper: the frame on screen. Where it doesn't
                // play (home screen), the last frame shown simply stays.
                defaultHasFrames() && shownFrame != null -> shownFrame
                else -> defaultPicture()
            }
            if (movie != null && backgroundIsAnimating()) {
                drawGifCover(canvas, movie)
            } else if (picture != null && !picture.isRecycled) {
                canvas.drawBitmap(picture, 0f, 0f, null)   // already fitted to the screen
            }
        }

        // The still Project P wallpaper (res/drawable-nodpi/pet_default_bg.png), fitted to
        // the screen. The setup screens use the same picture.
        // [EDIT] To change it, replace that PNG (same file name). In the Godot project
        //        that is addons/projectp_wallpaper/default_wallpaper.png.
        // It's looked up by name, so this file works unchanged in the wallpaper-only app
        // and inside the Godot game's app. If the PNG is missing, a plain colour is used.
        private fun defaultPicture(): Bitmap? {
            if (defaultFitted != null || defaultTried || screenW <= 0f) return defaultFitted
            defaultTried = true
            try {
                val id = resources.getIdentifier("pet_default_bg", "drawable", packageName)
                if (id == 0) return null
                val raw = BitmapFactory.decodeResource(
                    resources, id, BitmapFactory.Options().apply { inScaled = false }
                ) ?: return null
                defaultFitted = fitToScreen(
                    raw, if (defaultBackgroundIsPixelArt) pixelPaint else smoothPaint)
                raw.recycle()
            } catch (e: Throwable) {
                defaultFitted = null
            }
            return defaultFitted
        }

        // Returns a copy of a picture that is exactly the size of the screen, "center
        // cropped": it fills the whole screen without stretching, like a normal wallpaper
        // (edges that don't fit are cut off evenly on both sides).
        private fun fitToScreen(bmp: Bitmap, paint: Paint): Bitmap {
            val w = screenW.toInt().coerceAtLeast(1)
            val h = screenH.toInt().coerceAtLeast(1)
            val fitted = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            drawFitted(Canvas(fitted), bmp, w, h, paint)
            return fitted
        }

        private fun drawFitted(canvas: Canvas, bmp: Bitmap, w: Int, h: Int, paint: Paint) {
            val scale = max(w.toFloat() / bmp.width, h.toFloat() / bmp.height)
            val drawnW = bmp.width * scale
            val drawnH = bmp.height * scale
            val left = (w - drawnW) / 2f
            val top = (h - drawnH) / 2f
            canvas.drawBitmap(bmp, null, RectF(left, top, left + drawnW, top + drawnH), paint)
        }

        // The same "center crop" for the GIF's current frame.
        private fun drawGifCover(canvas: Canvas, movie: Movie) {
            val elapsed = SystemClock.uptimeMillis() - gifStartedAt
            movie.setTime((elapsed % movie.duration()).toInt())
            val scale = max(screenW / movie.width(), screenH / movie.height())
            canvas.save()
            canvas.translate(
                (screenW - movie.width() * scale) / 2f, (screenH - movie.height() * scale) / 2f)
            canvas.scale(scale, scale)
            movie.draw(canvas, 0f, 0f, smoothPaint)
            canvas.restore()
        }

        // ----- ANIMATED PROJECT P WALLPAPER -------------------------------------------
        // If you supply frames (pictures named in order, e.g. frame_00.jpg, frame_01.jpg...
        // in addons/projectp_wallpaper/default_wallpaper_frames/ of the Godot project, or
        // assets/wallpaper_bg_frames/ of the wallpaper-only app), the Project P wallpaper
        // plays them in a loop where moving backgrounds are allowed (SECTION 2).
        // [LOGIC] Only two or three frames are in memory at any time: the one on screen
        //         and the next one, which a helper thread loads and fits to the screen
        //         while the current one is showing. So the number of frames costs app
        //         size, not memory. If loading is slower than defaultAnimationFps, the
        //         animation just runs a little slower.
        // [FIX] Still picture although frames were added: the export's Output line must
        //       say "... background frames added", and the user must be using the
        //       Project P wallpaper (not their own picture).

        // Called every tick: shows the next frame when it's time, and orders the one after.
        // Where the animation doesn't play (home screen), only the first frame is loaded,
        // and after that whichever frame was last shown stays.
        private fun stepDefaultAnimation(now: Long) {
            if (!defaultHasFrames() || screenW <= 0f) return
            val playing = backgroundIsAnimating()
            if (!playing && shownFrame != null) return
            val next = readyFrame
            val interval = 1000L / defaultAnimationFps
            if (next != null && (shownFrame == null || now - frameShownSince >= interval)) {
                if (shownFrame == null) {
                    // The first frame replaces the still picture, which is no longer needed
                    defaultFitted?.recycle()
                    defaultFitted = null
                    defaultTried = false
                }
                spareFrame = shownFrame          // the old frame's memory is used again
                shownFrame = next
                shownFrameIndex = readyFrameIndex
                readyFrame = null
                // Keep an even rhythm; start counting afresh after a pause
                frameShownSince =
                    if (now - frameShownSince > 2 * interval) now else frameShownSince + interval
            }
            val wantNext = shownFrame == null || (playing && defaultFrameFiles.size > 1)
            if (wantNext && readyFrame == null && !frameIsLoading) {
                requestDefaultFrame((shownFrameIndex + 1) % defaultFrameFiles.size)
            }
        }

        // Asks the helper thread for one frame, fitted to the screen.
        private fun requestDefaultFrame(index: Int) {
            val name = defaultFrameFiles.getOrNull(index) ?: return
            val w = screenW.toInt().coerceAtLeast(1)
            val h = screenH.toInt().coerceAtLeast(1)
            val reuse = spareFrame?.takeIf { it.width == w && it.height == h && !it.isRecycled }
            spareFrame = null
            val batch = frameBatch
            frameIsLoading = true
            try {
                frameLoader.execute {
                    // (helper thread) load the picture and draw it fitted into `target`
                    val target = try {
                        val raw = assets.open("${PetCatalog.DEFAULT_BG_FRAMES}/$name")
                            .use { BitmapFactory.decodeStream(it) }
                        if (raw == null) null else {
                            val out = reuse ?: Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                            out.eraseColor(fallbackColor)      // wipe the frame it held before
                            drawFitted(Canvas(out), raw, w, h, Paint().apply {
                                isFilterBitmap = !defaultBackgroundIsPixelArt
                            })
                            raw.recycle()
                            out
                        }
                    } catch (e: Throwable) {
                        null
                    }
                    // (back on the main thread) keep it, unless the screen size changed
                    handler.post {
                        if (batch == frameBatch) {
                            frameIsLoading = false
                            if (target != null) {
                                readyFrame = target
                                readyFrameIndex = index
                                frameFailures = 0
                            } else {
                                // Unreadable frame: skip it and carry on with the next.
                                // If no frame at all can be read, the still picture is
                                // used (see defaultHasFrames).
                                frameFailures++
                                shownFrameIndex = index
                                spareFrame = reuse
                            }
                        }
                    }
                }
            } catch (e: Throwable) {
                frameIsLoading = false           // the wallpaper is shutting down
            }
        }

        // Drops the loaded frames (screen size changed). Frames still being prepared by
        // the helper thread are ignored when they arrive.
        private fun forgetDefaultFrames() {
            frameBatch++
            frameIsLoading = false
            // (a frame the helper thread is still working on is never one of these three)
            shownFrame?.recycle()
            readyFrame?.recycle()
            spareFrame?.recycle()
            shownFrame = null
            readyFrame = null
            spareFrame = null
            shownFrameIndex = -1
            readyFrameIndex = -1
            frameFailures = 0
        }

        // ===== SECTION 9: DRAWING EACH FRAME ==========================================
        // Keeps the pet fully on screen.
        private fun clampPet() {
            petX = petX.coerceIn(0f, maxOf(0f, screenW - petW))
            petY = petY.coerceIn(0f, maxOf(0f, screenH - petH))
        }

        // Draws one picture: background first, then the current pet frame on top.
        // Called by the animation timer and while dragging.
        // [FIX] If the pet shows the wrong picture, check loadFrames() (top of this file) and
        //       the names in PetCatalog.ANIMS.
        private fun drawFrame() {
            val holder = surfaceHolder
            val canvas = try { holder.lockCanvas() } catch (e: Exception) { null } ?: return
            try {
                drawBackground(canvas)
                // The current frame; if this pet has no pictures for the animation, show
                // its resting picture instead of nothing.
                val picture = frames[current]?.getOrNull(frame)
                    ?: frames["pet_idle"]?.firstOrNull().takeIf { hatched }
                    ?: frames["egg_idle"]?.firstOrNull()
                val now = SystemClock.uptimeMillis()
                if (showMarks && markShown) drawSpotGlow(canvas, now)
                if (picture != null && !picture.isRecycled) {   // (recycled = pet just changed)
                    val dst = RectF(petX, petY, petX + petW, petY + petH)
                    val mirrored = facingLeft
                    if (mirrored) {
                        // Mirror the pet so it faces the way it travels
                        canvas.save()
                        canvas.scale(-1f, 1f, petX + petW / 2f, petY + petH / 2f)
                    }
                    val glow = listeningGlow(now)
                    if (glow > 0f) drawPetGlow(canvas, picture, glow)    // under the pet
                    canvas.drawBitmap(picture, null, dst, petPaint)
                    if (mirrored) canvas.restore()
                }
            } catch (e: Throwable) {
                // skip this frame
            } finally {
                try { holder.unlockCanvasAndPost(canvas) } catch (e: Exception) { }
            }
        }

        // [LOGIC] Tap to move shows two soft glows instead of marks:
        //           - around the pet while it listens for the "go there" tap: the pet's own
        //             shape, blurred and drawn under it, so it seems to light up;
        //           - at the spot it is travelling to: a small round light.
        //         Both breathe slowly, fade in, and the pet's glow fades out as the
        //         listening time ends. Each is a warm white light with a wider amber
        //         edge, so it shows on dark and on light pictures.
        // [EDIT] Colours, strength and sizes: glowColor, glowEdgeColor, glowStrength,
        //        glowReach and spotGlowDp in SECTION 2; showMarks = false hides both.

        // How strong the pet's glow is right now: 0 = none ... 1 = full.
        private fun listeningGlow(now: Long): Float {
            if (!showMarks || !isListening() || moving || hopStartedAt != 0L) return 0f
            val fadeIn = ((now - listeningSince) / 250f).coerceIn(0f, 1f)
            val fadeOut = ((listeningUntil - now) / 600f).coerceIn(0f, 1f)
            return fadeIn * fadeOut * breath(now)
        }

        // A slow breath between 0.75 and 1, once every 1.6 seconds.
        private fun breath(now: Long): Float =
            0.875f + 0.125f * sin((now % 1600L) / 1600f * 2f * PI.toFloat())

        // The blurred outline of one frame. Made once per frame and kept, because
        // blurring takes a moment. It is made from a small copy of the frame (a glow has
        // no detail), which keeps it quick and light on memory.
        private fun glowOf(picture: Bitmap): Glow? {
            glows[picture]?.let { return it }
            if (glows.size >= 160) forgetGlows()         // (keeps memory small)
            var small: Bitmap? = null
            return try {
                val shrink = min(1f, 96f / max(picture.width, picture.height))
                small = Bitmap.createScaledBitmap(
                    picture, max(1, (picture.width * shrink).toInt()),
                    max(1, (picture.height * shrink).toInt()), true)
                val blur = Paint().apply {
                    maskFilter = BlurMaskFilter(
                        max(2f, small.width * glowReach), BlurMaskFilter.Blur.NORMAL)
                }
                val corner = IntArray(2)
                val shape = small.extractAlpha(blur, corner)
                Glow(shape, corner[0], corner[1], small.width, small.height)
                    .also { glows[picture] = it }
            } catch (e: Throwable) {
                null                                     // no glow rather than no pet
            } finally {
                if (small != null && small !== picture) small.recycle()
            }
        }

        private fun forgetGlows() {
            val old = glows.values.toList()
            glows.clear()
            old.forEach { it.shape.recycle() }
        }

        // The glow around the pet. `level` = how strong (0..1).
        private fun drawPetGlow(canvas: Canvas, picture: Bitmap, level: Float) {
            val glow = glowOf(picture) ?: return
            if (glow.shape.isRecycled) return
            val sx = petW / glow.frameW              // glow pixels -> screen pixels
            val sy = petH / glow.frameH
            val dst = RectF(
                petX + glow.left * sx, petY + glow.top * sy,
                petX + (glow.left + glow.shape.width) * sx,
                petY + (glow.top + glow.shape.height) * sy)
            // The softer edge in the second colour, a little wider than the light
            val edge = RectF(dst)
            edge.inset(-petW * 0.04f, -petH * 0.04f)
            glowPaint.color = glowEdgeColor
            glowPaint.alpha = (level * glowStrength * 150f).toInt().coerceIn(0, 255)
            canvas.drawBitmap(glow.shape, null, edge, glowPaint)
            // The light itself
            glowPaint.color = glowColor
            glowPaint.alpha = (level * glowStrength * 255f).toInt().coerceIn(0, 255)
            canvas.drawBitmap(glow.shape, null, dst, glowPaint)
        }

        // The glow at the spot the pet is travelling to.
        private fun drawSpotGlow(canvas: Canvas, now: Long) {
            val fadeIn = ((now - tripStartedAt) / 200f).coerceIn(0f, 1f)
            val level = fadeIn * breath(now)
            val radius = spotGlowDp * resources.displayMetrics.density * (0.9f + 0.1f * level)
            canvas.save()
            canvas.translate(markX, markY)
            canvas.scale(radius, radius)
            spotPaint.shader = spotEdge
            spotPaint.alpha = (level * glowStrength * 255f).toInt().coerceIn(0, 255)
            canvas.drawCircle(0f, 0f, 1.35f, spotPaint)
            spotPaint.shader = spotLight
            spotPaint.alpha = (level * min(1f, glowStrength * 1.3f) * 255f).toInt()
                .coerceIn(0, 255)
            canvas.drawCircle(0f, 0f, 1f, spotPaint)
            canvas.restore()
        }

        // ===== SECTION 10: HOME SCREEN OR LOCK SCREEN? ================================
        // The lock screen gets the greeting, the phone-movement reactions and the animated
        // GIF. Android 14 and newer can tell a wallpaper which screen it's on; older
        // versions are asked whether the phone is locked.
        // [FIX] If the lock screen pet behaves like the home screen one (or the other way
        //       round), this is where the decision is made.
        private val flagsMethod = try {
            Engine::class.java.getMethod("getWallpaperFlags")     // Android 14+
        } catch (e: Throwable) {
            null
        }

        private fun updateLockState() {
            lastLockCheckAt = SystemClock.uptimeMillis()
            val flags = try { flagsMethod?.invoke(this) as? Int } catch (e: Throwable) { null }
            val nowOnLock = when {
                isPreview -> false
                flags == 2 -> true                    // this copy is only for the lock screen
                // this copy is only for the home screen (reliable from Android 15 on)
                flags == 1 && Build.VERSION.SDK_INT >= 35 -> false
                else -> keyguard.isKeyguardLocked     // otherwise: is the phone locked?
            }
            val nowAwake = try { power.isInteractive } catch (e: Throwable) { true }
            val wokeUp = nowAwake && !awake
            val changed = nowOnLock != onLockScreen || nowAwake != awake
            onLockScreen = nowOnLock
            awake = nowAwake
            if (!changed) return
            gifStartedAt = SystemClock.uptimeMillis()
            if (!awake) {
                settleDown()                              // screen dimmed: put the pet down
                drawFrame()                               // and show this screen's picture
            }
            if (!onLockScreen && movingByTilt) stopMoving()
            updateSensor()
            // Phones with an always-on display keep the wallpaper "visible" while dimmed,
            // so the greeting is also given when the screen wakes up.
            if (wokeUp) refreshRest()                     // (unless the pet is asleep by now)
            if (wokeUp && onLockScreen && greetOnLockScreen) greet()
        }

        // ===== SECTION 11: WHAT THE PET DOES BY ITSELF; TRAVELLING, JUMPING ===========
        // [LOGIC] While the hatched pet rests (pet_idle: blinking) and nobody is touching
        //         it, a timer runs down (table.waitMin..waitMax seconds). Then, between
        //         two blinks, it picks ONE action from the ACTIONS list at random (by
        //         weight), does it, and goes back to resting; the timer starts again.
        //           "blink"  -> nothing new: it keeps resting and blinking
        //           "travel" -> goes sideways to a random spot with that animation, facing
        //                       the way it goes; fly_ frames bob in the air
        //           "hop"    -> jumps up on the spot, then "landing"
        //           "play"   -> plays that animation once where it stands. If the
        //                       animation has several versions (ANIM_SETS, e.g. "trick"
        //                       with two tricks of 8 frames), ONE version is played.
        //         On a low battery it picks from the low-energy list instead, and while
        //         it sleeps it does nothing by itself (SECTION 13).
        //         Actions the pet has no frames for are left out. The list itself is in
        //         pet.gd (one app with the game) or PetCatalog.kt (wallpaper-only app).
        // [FIX] The pet only blinks and never does anything else: tap "Check my pet" in
        //       the wallpaper setup. An action needs frames for its animation.
        private fun resetRoamTimer() {
            nextMoveIn = table.waitMin + Random.nextFloat() * (table.waitMax - table.waitMin)
        }

        private fun stepActionTimer(dt: Float) {
            val allowed = if (onLockScreen) roamOnLockScreen else roamOnHomeScreen
            if (!allowed || !isFree() || moving || hopStartedAt != 0L) return
            if (current != "pet_idle" || screenW <= 0f) return
            if (isListening()) return                  // it's waiting to be sent somewhere
            // While the phone is held tilted to one side, the tilt decides where it goes
            val tilted = sensorOn && gravityKnown && abs(sideTilt) > tiltSideways &&
                SystemClock.uptimeMillis() - lastSensorAt < 1000L
            if (tilted) return
            nextMoveIn -= dt
            if (nextMoveIn > 0f) return
            if (frame % table.blinkFrames != 0) return // let the current blink finish first
            resetRoamTimer()
            val action = pickAction() ?: return
            doAction(action)
        }

        // Can the pet do this action? (switched on, and it has the frames for it)
        private fun canDo(action: Action) = action.weight > 0f && (action.kind == "blink" ||
            (if (action.kind == "travel") canTravel(action.anim) else has(action.anim)))

        // Picks one action at random; a bigger weight is picked more often.
        private fun pickAction(): Action? {
            val choices = actionsNow().filter { canDo(it) }
            var pick = Random.nextFloat() * choices.sumOf { it.weight.toDouble() }.toFloat()
            for (action in choices) {
                pick -= action.weight
                if (pick <= 0f) return action
            }
            return choices.lastOrNull()
        }

        // Starts one action.
        private fun doAction(action: Action) {
            when (action.kind) {
                "travel" -> {
                    val room = max(0f, screenW - petW)
                    var target = Random.nextFloat() * room
                    if (abs(target - petX) < screenW * 0.25f) {
                        // Too short a trip: go towards the farther side of the screen
                        target = if (petX > room / 2f) 0f else room
                    }
                    startMoving(target, false, null, action.anim)
                }
                "hop" -> jumpTo(petX, petY, action.anim)
                "play" -> {
                    if (animOf(action.anim).loop) return   // a looping one would never end
                    busy = true                // no tickling until it has finished
                    play(oneVersion(action.anim))   // ends in onAnimationFinished -> resting
                    tickNow()
                }
                // "blink": nothing to do, it simply keeps resting
            }
        }

        // [LOGIC] An animation listed in ANIM_SETS has several versions, made when the
        //         pet is loaded: "trick#1", "trick#2", ... This picks one of them at
        //         random. For any other animation it returns the animation itself.
        private fun oneVersion(anim: String): String {
            var count = 0
            while (has("$anim#${count + 1}")) count++
            return if (count == 0) anim else "$anim#${1 + Random.nextInt(count)}"
        }

        // Sets off towards a spot (the pet's top-left corner). byTilt = started by tilting
        // the phone. Without targetY the pet stays at its height (wandering, tilting).
        private fun startMoving(
            targetX: Float, byTilt: Boolean, targetY: Float? = null, anim: String = "move"
        ) {
            if (!isFree() || hopStartedAt != 0L || !canTravel(anim)) return
            if (byTilt && current == "sleep") return        // tilting doesn't wake it
            val lineY = if (moving) moveLineY else petY
            val toX = targetX.coerceIn(0f, max(0f, screenW - petW))
            val toY = (targetY ?: lineY).coerceIn(0f, max(0f, screenH - petH))
            if (hypot(toX - petX, toY - lineY) < 4f) return   // already there
            val wasMoving = moving
            if (!moving) {
                moveLineY = petY
                moveTime = 0f
            }
            moving = true
            movingByTilt = byTilt
            moveTargetX = toX
            moveTargetY = toY
            if (abs(toX - petX) >= 4f) headingLeft = toX < petX   // (straight up/down: as before)
            val (picked, mirrored) = travelPick(anim, headingLeft) ?: return
            travelAnim = picked
            facingLeft = mirrored
            if (current != picked) play(picked)
            if (!wasMoving) tickNow()
        }

        // [LOGIC] Which animation the pet travels with, and whether it is drawn mirrored.
        //         `base` is the animation named in ACTIONS, normally "move".
        //           going left  -> "move_left" frames, if the pet has them
        //           going right -> "move_right" frames, if the pet has them
        //           only one of the two -> that one, mirrored for the other direction
        //           neither -> "move" itself (fly_ / walk_ / run_ frames), mirrored when
        //                      it goes the other way than the frames face
        //                      (moveFramesFaceRight, SECTION 2)
        //         Returns null if the pet has no frames to travel with.
        private fun travelPick(base: String, goingLeft: Boolean): Pair<String, Boolean>? {
            val own = base + if (goingLeft) "_left" else "_right"
            val other = base + if (goingLeft) "_right" else "_left"
            return when {
                has(own) -> own to false
                has(other) -> other to true
                has(base) -> base to (goingLeft == moveFramesFaceRight)
                else -> null
            }
        }

        // Does the pet have frames to travel with (this animation or its _left / _right)?
        private fun canTravel(base: String) =
            has(base) || has(base + "_left") || has(base + "_right")

        // Moves the pet a little each tick, in a straight line, until it reaches its spot.
        private fun stepMoving(dt: Float) {
            if (!moving) return
            moveTime += dt
            val step = moveSpeed * screenW * dt
            val gapX = moveTargetX - petX
            val gapY = moveTargetY - moveLineY
            val gap = hypot(gapX, gapY)
            if (gap <= step) {
                petX = moveTargetX
                moveLineY = moveTargetY
                stopMoving()
                return
            }
            petX += gapX / gap * step
            moveLineY += gapY / gap * step
            // Flying pets bob above their line of travel
            val bobs = travelAnim in bobAnims
            petY = moveLineY - (if (bobs) abs(sin(moveTime * 3f)) * moveBob * petH else 0f)
        }

        // Ends a trip: back to resting, facing forward, position saved.
        private fun stopMoving() {
            if (!moving) return
            moving = false
            movingByTilt = false
            markShown = false
            petY = moveLineY
            facingLeft = false
            playIdle()
            savePosition()
            resetRoamTimer()
        }

        // [LOGIC] A hop in place: the pet plays "jump" while it rises and comes back down,
        //         then "landing", then rests. Used for the greeting and for tilting the
        //         phone up.
        private fun hop() {
            if (!isFree() || hopStartedAt != 0L) return
            if (current == "sleep" || isAsleep()) return    // a sleeping pet stays asleep
            stopMoving()                 // first back onto its line, then up from there
            jumpTo(petX, petY)
        }

        // [LOGIC] A jump to another spot (tap to move, up or down): the same as a hop, but
        //         the pet travels to the spot in an arc. The 8 jump frames play as it takes
        //         off and the last one is held while it is in the air; the 8 landing frames
        //         play when it arrives. Jumping down, it rises a little first and then
        //         drops. Longer jumps take longer (jumpSpeed) and arc higher (jumpArc).
        private fun jumpTo(toX: Float, toY: Float, anim: String = "jump") {
            if (!isFree() || hopStartedAt != 0L) return
            stopMoving()
            busy = true
            hopFromX = petX
            hopFromY = petY
            hopToX = toX.coerceIn(0f, max(0f, screenW - petW))
            hopToY = toY.coerceIn(0f, max(0f, screenH - petH))
            val distance = hypot(hopToX - hopFromX, hopToY - hopFromY)
            val seconds = max(hopSeconds, distance / (jumpSpeed * max(screenH, 1f)))
            hopMillis = seconds * 1000f
            hopArc = hopHeight * petH + jumpArc * distance
            hopStartedAt = SystemClock.uptimeMillis()
            play(if (has(anim)) anim else "jump")
            tickNow()
        }

        private fun stepHop(now: Long) {
            if (hopStartedAt == 0L) return
            val t = (now - hopStartedAt) / hopMillis                // 0 at the start, 1 at the end
            if (t >= 1f) {
                endHop()
                return
            }
            petX = hopFromX + (hopToX - hopFromX) * t
            petY = hopFromY + (hopToY - hopFromY) * t - sin(t * PI.toFloat()) * hopArc
        }

        // Touchdown: the pet is at its spot; landing frames, then resting.
        private fun endHop() {
            if (hopStartedAt == 0L) return
            hopStartedAt = 0L
            markShown = false
            val travelled = hopToX != hopFromX || hopToY != hopFromY
            petX = hopToX
            petY = hopToY
            if (travelled) {
                savePosition()
                resetRoamTimer()
            }
            if (has("landing")) play("landing") else playIdle()   // landing -> idle
        }

        // [LOGIC] Greeting when the lock screen appears. Not more often than every
        //         5 seconds, so quick screen flickers don't repeat it.
        //         If the pet has its own greeting frames (greet_00.png, hello_00.png or
        //         wave_00.png, see "greet" in PetCatalog.ANIMS) they are played; otherwise
        //         the pet greets with a hop.
        private fun greet() {
            val now = SystemClock.uptimeMillis()
            if (now - lastGreetAt < 5000L) return
            if (isAsleep()) return                 // it sleeps through the screen turning on
            lastGreetAt = now
            if (has("greet") && isFree()) {
                stopMoving()
                busy = true
                play("greet")
                tickNow()
            } else {
                hop()
            }
        }

        // Called when the wallpaper is hidden: put the pet down where it belongs.
        // [LOGIC] A pet on its way to a tapped spot is put at that spot. But if the
        //         wallpaper is hidden within a moment of the tap, the tap really opened an
        //         app (its icon was under the finger): then the pet goes back where it was.
        private fun settleDown() {
            val onTapTrip = markShown && (moving || hopStartedAt != 0L)
            val tapOpenedAnApp =
                onTapTrip && SystemClock.uptimeMillis() - tripStartedAt < UNDO_TRIP_MILLIS
            if (moving && onTapTrip) {             // finish the trip at once
                petX = moveTargetX
                moveLineY = moveTargetY
            }
            stopMoving()
            if (hopStartedAt != 0L) {              // finish the jump at once
                hopStartedAt = 0L
                petX = hopToX
                petY = hopToY
                savePosition()
                playIdle()
            }
            if (tapOpenedAnApp) {
                petX = tripFromX
                petY = tripFromY
                savePosition()
            }
            // never left hanging in the air, or frozen on a travelling frame
            if (hatched && current != restAnim()) playIdle()
            markShown = false
            listeningUntil = 0L
            fingerDown = false
            dragging = false
            moved = false
        }

        // ===== SECTION 12: PHONE MOVEMENT (SHAKE AND TILT) ============================
        // Uses the phone's movement sensor, which also works on the lock screen.
        // [LOGIC] Shake the phone        -> tickle (a sleeping pet wakes up instead).
        //         Tilt the top up quickly -> hop.
        //         Tilt sideways           -> travel towards the lower side, for as long as
        //                                    the phone stays tilted.
        // The sensor is only switched on while the wallpaper is visible on a screen where
        // it's allowed (SECTION 2), so it costs no battery the rest of the time.
        private val sensorListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                try {
                    onPhoneMoved(event.values[0], event.values[1], event.values[2])
                } catch (e: Throwable) {
                    // ignore
                }
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { }
        }

        private fun updateSensor() {
            val allowed = if (onLockScreen) motionOnLockScreen else motionOnHomeScreen
            val want = visible && awake && allowed && accelerometer != null
            if (want && !sensorOn) {
                gravityKnown = false
                sensorOn = sensorManager.registerListener(
                    sensorListener, accelerometer, SensorManager.SENSOR_DELAY_UI)
            } else if (!want && sensorOn) {
                sensorManager.unregisterListener(sensorListener)
                sensorOn = false
            }
        }

        // x, y, z = the sensor reading: x points to the phone's right, y to its top, z out
        // of the screen. At rest the reading points "up" with a strength of about 9.8.
        // (This assumes the phone is used upright, like the game.)
        private fun onPhoneMoved(x: Float, y: Float, z: Float) {
            val now = SystemClock.uptimeMillis()
            if (!gravityKnown) {
                gravX = x; gravY = y; gravZ = z
                restX = x.coerceIn(-0.8f * tiltSideways, 0.8f * tiltSideways)
                sideTilt = gravX - restX
                slowLift = liftOf(x, y, z)
                gravityKnown = true
                lastSensorAt = now
                return
            }
            // Seconds since the last reading. The smoothing below uses real time, so it
            // behaves the same whether the phone sends 15 or 100 readings a second.
            val dt = ((now - lastSensorAt).coerceIn(1L, 200L)) / 1000f
            lastSensorAt = now
            // Split the reading: the slow part is how the phone is held (gravity), the
            // fast part is the hand moving it.
            val follow = 1f - exp(-dt / 0.4f)
            gravX += follow * (x - gravX)
            gravY += follow * (y - gravY)
            gravZ += follow * (z - gravZ)
            val dx = x - gravX
            val dy = y - gravY
            val dz = z - gravZ
            val jolt = sqrt(dx * dx + dy * dy + dz * dz)

            // --- Shake: two sharp movements within 0.7 seconds ---
            if (jolt > shakeStrength) {
                if (now - firstJoltAt > 700L) {
                    firstJoltAt = now
                    joltCount = 0
                    lastCountedJoltAt = 0L
                }
                if (now - lastCountedJoltAt > 150L) {     // one count per back-and-forth
                    joltCount++
                    lastCountedJoltAt = now
                }
                lastJoltAt = now
                if (joltCount >= 2 && now - lastShakeAt > 1500L) {
                    lastShakeAt = now
                    joltCount = 0
                    if (!wakeUp()) tickle()       // asleep: the shake wakes it
                }
                return
            }
            if (now - lastJoltAt < 400L) return      // still being shaken: ignore tilts

            // --- Tilt sideways: travel towards the lower side ---
            // The tilt is measured against how the phone is normally held (restX), not
            // against perfectly level: most people hold a phone a little to one side, and
            // that must not send the pet to the edge or stop it doing things by itself.
            // restX follows the hand slowly, so a tilt has to be a clear movement.
            // sideTilt is below zero when the right edge was lowered, above zero for the left.
            // It only follows up to a point, so a phone held far over to one side still
            // counts as tilted, and levelling it again doesn't send the pet the other way.
            restX += (1f - exp(-dt / 6f)) * (gravX - restX)
            restX = restX.coerceIn(-0.8f * tiltSideways, 0.8f * tiltSideways)
            sideTilt = gravX - restX
            val onTapTrip = moving && !movingByTilt && markShown   // sent by a tap: let it go
            if (abs(sideTilt) > tiltSideways && !onTapTrip) {
                val room = max(0f, screenW - petW)
                startMoving(if (sideTilt < 0f) room else 0f, true)
            } else if (moving && movingByTilt && abs(sideTilt) < tiltSideways * 0.6f) {
                stopMoving()                         // phone is back as it was held
            }

            // --- Tilt up: the top of the phone raised quickly ---
            // slowLift follows the phone's angle with a delay of about a second. A quick
            // raise gets ahead of it; a slow one (just picking the phone up) doesn't.
            val lift = liftOf(gravX, gravY, gravZ)
            if (now - lastTiltHopAt < 2000L) {
                slowLift = lift                      // just hopped: start measuring afresh
            } else {
                slowLift += (1f - exp(-dt / 1.0f)) * (lift - slowLift)
                if (lift - slowLift > tiltUpDegrees) {
                    lastTiltHopAt = now
                    slowLift = lift
                    hop()
                }
            }
        }

        // How far the top of the phone is raised, in degrees: 0 = lying flat (or on its
        // side), 90 = standing upright, below 0 = top pointing down.
        private fun liftOf(x: Float, y: Float, z: Float): Float {
            val strength = sqrt(x * x + y * y + z * z)
            if (strength < 1f) return 0f             // falling or no reading: no angle
            return Math.toDegrees(asin((y / strength).coerceIn(-1f, 1f)).toDouble()).toFloat()
        }

        // ===== SECTION 13: SLEEPING AT NIGHT AND LOW ENERGY ===========================
        // [LOGIC] SLEEP. Between table.sleepFrom and table.sleepUntil by the phone's own
        //         clock (11 PM to 6 AM unless changed) the hatched pet rests with its
        //         "sleep" frames instead of pet_idle. Asleep, it does nothing by itself,
        //         doesn't greet and isn't moved by tilting the phone.
        //         WAKING IT UP: tap it (home screen) or shake the phone (lock screen). It
        //         is then awake for table.awakeMinutes (5): it blinks, does its actions,
        //         can be tickled and sent to a spot. Every tap or shake in that time
        //         starts the minutes again. After that it goes back to sleep; in the
        //         morning it wakes up by itself.
        //         A pet without sleep frames simply stays awake.
        // [LOGIC] LOW ENERGY. While the battery is at or below table.lowBatteryPercent
        //         (15) and the phone isn't charging, the pet picks what it does from
        //         the low-energy list (its low_energy movements, one version at a
        //         time) instead of ACTIONS. Plug the phone in and it is its old self.
        // [EDIT] The hours, the minutes awake, the percent and the low-energy list: in
        //        pet.gd SECTION 0 (one app with the game) or PetCatalog.kt (wallpaper-
        //        only app). sleepsAtNight / tiresOnLowBattery (SECTION 2) switch them off
        //        for the wallpaper alone.
        // [FIX] The pet never sleeps or never looks tired: tap "Check my pet" in the
        //       wallpaper setup. It shows whether the pet has sleep and low_energy
        //       frames, the hours, and the battery level the wallpaper sees.

        // Looks at the phone's clock (at most every 5 seconds).
        private fun readClock(force: Boolean = false) {
            val now = SystemClock.uptimeMillis()
            if (!force && now - clockReadAt < 5000L) return
            clockReadAt = now
            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)   // 0..23
            val from = table.sleepFrom
            val until = table.sleepUntil
            bedtime = sleepsAtNight && (
                if (from <= until) hour >= from && hour < until      // e.g. 1 to 6
                else hour >= from || hour < until)                   // e.g. 23 to 6
        }

        // Looks at the battery (at most every 30 seconds).
        private fun readBattery(force: Boolean = false) {
            val now = SystemClock.uptimeMillis()
            if (!force && now - batteryReadAt < 30000L) return
            batteryReadAt = now
            val (percent, plugged) = phoneBattery(this@PetWallpaperService)
            lowEnergy = tiresOnLowBattery && percent >= 0 && !plugged &&
                percent <= table.lowBatteryPercent
        }

        // Is the pet woken up for a while?
        private fun isWokenUp() = SystemClock.elapsedRealtime() < awakeUntil

        // Should the pet be asleep right now?
        private fun isAsleep() = hatched && bedtime && has("sleep") && !isWokenUp()

        // The animation the pet rests with right now.
        private fun restAnim() = when {
            !hatched -> "egg_idle"
            isAsleep() -> "sleep"
            else -> "pet_idle"
        }

        // The screen just came on: look at the clock and the battery right away, and put
        // the pet to sleep or wake it without waiting, so it is never seen "wrong".
        private fun refreshRest() {
            readClock(true)
            readBattery(true)
            if (!busy && !moving && hopStartedAt == 0L &&
                (current == "pet_idle" || current == "sleep") && current != restAnim()
            ) playIdle()
        }

        // Falling asleep and waking up by itself: the resting animation it should have
        // now is another one than it is playing (the clock passed the sleeping hour, the
        // morning came, or its minutes awake are over).
        private fun stepRest() {
            readClock()
            readBattery()
            if (!hatched || busy || dragging || moving || hopStartedAt != 0L) return
            if (current != "pet_idle" && current != "sleep") return
            if (current == restAnim()) return
            // (an awake pet finishes its blink first)
            if (current == "sleep" || frame % table.blinkFrames == 0) playIdle()
        }

        // A tap or a shake: keeps the pet awake for awakeMinutes (this only matters at
        // night). Returns true if the pet was asleep and this woke it up.
        private fun wakeUp(): Boolean {
            if (!hatched) return false
            if (bedtime) {
                awakeUntil =
                    SystemClock.elapsedRealtime() + (table.awakeMinutes * 60000f).toLong()
            }
            if (current != "sleep") return false
            playIdle()                           // back to blinking
            resetRoamTimer()
            tickNow()
            return true
        }

        // The list the pet picks its next action from: the low-energy list while the
        // battery is low and the pet has frames for something in it, otherwise ACTIONS.
        private fun actionsNow(): List<Action> =
            if (lowEnergy && table.lowActions.any { it.kind != "blink" && canDo(it) }) {
                table.lowActions
            } else {
                table.actions
            }
    }
}
