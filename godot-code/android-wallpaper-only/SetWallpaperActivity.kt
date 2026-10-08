// =====================================================================================
// SetWallpaperActivity.kt  -  THE WALLPAPER SETUP SCREENS
// =====================================================================================
// What this file does:
//   Asks the user, step by step:
//     1. Show your pet on your home screen and lock screen?   Yes / No
//     1b. Which pet?  (only shown when PetCatalog.kt lists more than one pet)
//     2. (Yes) Keep your current wallpaper behind the pet?
//          Yes -> pick that picture (or GIF) from the gallery (photo picker)
//          No  -> use the Project P wallpaper
//     2b. (after picking) Is your lock screen wallpaper different?
//          Yes -> pick the lock screen picture too
//          No  -> the same picture is used on both screens
//     3. Opens Android's wallpaper preview -> user chooses "Home and lock screens"
//   If the pet is already on the home screen, it offers "Change pet" (when there are
//   several), "Change background" and "Remove pet from home screen" instead.
//   "Check my pet" shows what the wallpaper found in the app for the chosen pet: how
//   many frames each animation has and which of its actions it can do. Use it when the
//   pet doesn't fly, walk or do its other movements on the phone.
//   Every screen shows the Project P wallpaper picture (pet_default_bg.png) behind a
//   soft panel with the question and the buttons.
//
// How it is opened:
//   - One app with the Godot game: from the "Wallpaper Selection" button in the game's
//     main menu (main_menu.gd -> WallpaperBridge.kt). There is no separate app icon.
//     Closing these screens, or pressing Back, returns to the main menu.
//   - Wallpaper-only app: from the app icon.
//
// Adding more pets: you don't need to change this file. Add them in PetCatalog.kt
// ([ADD PET]); the "Which pet?" screen lists them automatically.
//
// One app with the Godot game: the pet is chosen in the game, so "Which pet?" and
// "Change pet" are skipped here. Changing the pet never changes the background.
//
// Google Play safe: needs no permissions. Android's own photo picker only gives the
// app the one picture the user picks. (Android doesn't let apps read the wallpaper that
// is already set, which is why the user picks the picture once.)
//
// How to find things:
//   [EDIT]  = text or buttons you can safely change
//   [LOGIC] = which screen leads to which
//   [FIX]   = places to look first if something goes wrong
//
// Sections in this file:
//   1. Settings (file names of the saved pictures)   -> search "SECTION 1"
//   2. The question screens (incl. "Which pet?")     -> search "SECTION 2"
//   3. Helpers (screen look, status checks)          -> search "SECTION 3"
//   4. Photo picker                                  -> search "SECTION 4"
//   5. Opening Android's wallpaper preview           -> search "SECTION 5"
//
// Related files:
//   PetCatalog.kt           - the list of pets shown on the "Which pet?" screen
//   PetWallpaperService.kt  - the wallpaper itself (reads the photo and pet saved here)
//   WallpaperBridge.kt      - lets the Godot game open these screens (one app)
//   res/drawable-nodpi/pet_default_bg.png  - the picture behind these screens
// =====================================================================================

package com.yourname.projectp.wallpaper

import android.app.Activity
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.File

class SetWallpaperActivity : Activity() {

    // ===== SECTION 1: SETTINGS ======================================================
    companion object {
        // Names of the user's pictures inside the app's private storage: the one for the
        // home screen (also used on the lock screen if there is no separate one), and the
        // one for the lock screen. PetWallpaperService reads these same files.
        const val BACKGROUND_FILE = "background.img"
        const val LOCK_BACKGROUND_FILE = "background_lock.img"
        // IDs used to recognise the photo picker's answer in onActivityResult():
        // which picture was being picked.
        private const val PICK_HOME_PICTURE = 1
        private const val PICK_LOCK_PICTURE = 2

        // [EDIT] Colours of the setup screens (the picture behind them is
        //        res/drawable-nodpi/pet_default_bg.png). "#E6" at the front of the panel
        //        colour is how solid it is: FF = solid, 00 = see-through.
        private const val PANEL_COLOR = "#E6FFF8EC"       // the soft panel
        private const val TEXT_COLOR = "#4A3423"          // the question text
        private const val BUTTON_COLOR = "#B5683C"        // the buttons
        private const val BUTTON_TEXT_COLOR = "#FFFFFF"   // the text on the buttons
        private const val EDGE_COLOR = "#F3E3CF"          // shown if the picture is missing
    }

    // Saved settings shared with the wallpaper (which pet was chosen).
    private val prefs by lazy { getSharedPreferences(PetCatalog.PREFS, MODE_PRIVATE) }
    // Every pet this app can show (from the game's pet.gd, or PetCatalog.PETS).
    private val pets by lazy { availablePets(this) }

    // true after we send the user to an Android screen (wallpaper preview or wallpaper
    // settings), so we show the first screen again with the new status when they return.
    private var backFromPreview = false

    // Runs when the setup is opened (from the main menu's Wallpaper Selection button, or
    // the app icon in the wallpaper-only app).
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showStart()
    }

    // Runs every time this screen comes back into view.
    override fun onResume() {
        super.onResume()
        if (backFromPreview) {        // user came back from Android's wallpaper preview
            backFromPreview = false
            showStart()
        }
    }

    // ===== SECTION 2: THE QUESTION SCREENS ==========================================
    // [EDIT] All the text the user sees is in the screen(...) calls below.
    //        Each screen is: screen("message", "button text" to { what it does }, ...)

    // [LOGIC] First screen.
    //   Pet already on the home screen -> Change pet / Change background / Remove pet / Close
    //   Not yet                        -> Question 1: show the pet? Yes / No
    private fun showStart() {
        if (isPetWallpaperOn()) {
            val buttons = mutableListOf<Pair<String, () -> Unit>>()
            if (hasSeveralPets()) buttons += "Change pet" to { askWhichPet { finishSetup() } }
            buttons += "Change background" to { askKeepWallpaper() }
            buttons += "Check my pet" to { showPetCheck() }
            buttons += "Remove pet from home screen" to { removePet() }
            buttons += "Close" to { finish() }
            screen(
                "Your ${chosenPet().name} is on your home screen and lock screen." +
                    "\n\nBackground: " + when {
                        hasLockPhoto() -> "your own pictures (home and lock screen)"
                        hasOwnPhoto() -> "your own picture"
                        else -> "Project P wallpaper"
                    },
                *buttons.toTypedArray()
            )
        } else {
            screen(
                "Show your pet on your home screen and lock screen?",
                "Yes, show my pet" to {
                    // Several pets -> ask which one first; one pet -> skip that question
                    if (hasSeveralPets()) askWhichPet { askKeepWallpaper() } else askKeepWallpaper()
                },
                "No, not now" to {
                    screen(
                        "Okay! Your pet will stay in the app.\n\n" +
                            "Come back here any time if you change your mind.",
                        "Close" to { finish() },
                        "Back" to { showStart() }
                    )
                },
                "Check my pet" to { showPetCheck() }
            )
        }
    }

    // [LOGIC] "Check my pet": what the wallpaper found in this app for the chosen pet.
    //   - how many frames each animation got (0 = it can't play that one),
    //   - which of its actions (the things it does by itself) are ready,
    //   - its tricks and low-energy movements (how many versions), sleep and size,
    //   - whether it has hatched (an egg doesn't move about).
    // [FIX] An animation shows 0 although the game plays it: export the game again with
    //       the add-on enabled, and read the "Project P Wallpaper:" lines in Godot's
    //       Output panel. They list the same numbers at export time.
    private fun showPetCheck() {
        val pet = chosenPet()
        val table = petTable(this)
        val files = petFrameFiles(this, pet.folder)
        fun count(anim: String) = files[anim]?.size ?: 0
        val text = StringBuilder("Pet check: ${pet.name}\n\nFrames per animation\n")
        for (name in table.anims.keys) {
            // Optional ones are left out when empty: the greeting, and pet_emerge when
            // hatching and emerging are one animation (egg_hatch_emerge_.. frames).
            if ((name == "greet" || name == "pet_emerge") && count(name) == 0) continue
            text.append("$name: ${count(name)}")
            // Movements with several versions: one version is played at a time
            val perVersion = table.sets[name] ?: 0
            if (perVersion > 0 && count(name) > 0) {
                val versions = count(name) / perVersion
                val spare = count(name) - versions * perVersion
                text.append(
                    if (versions > 0) " = $versions x $perVersion (one is played at a time)"
                    else " (fewer than $perVersion: played as one)")
                if (versions > 0 && spare > 0) text.append(", $spare left over")
            }
            text.append("\n")
        }
        // One line per action: ready, or why it is skipped.
        fun describe(actions: List<Action>) {
            for (action in actions) {
                if (action.kind == "blink" || action.weight <= 0f) continue
                val loops = table.anims[action.anim]?.loop == true
                // Travelling also works with the _left / _right frames of its animation
                val frames = if (action.kind == "travel") {
                    count(action.anim) + count(action.anim + "_left") +
                        count(action.anim + "_right")
                } else {
                    count(action.anim)
                }
                text.append("${action.kind} with ${action.anim}: ").append(
                    when {
                        frames == 0 -> "NO FRAMES, so it is skipped\n"
                        action.kind == "play" && loops -> "skipped, the animation loops\n"
                        else -> "ready\n"
                    }
                )
            }
        }
        text.append("\nWhat it does by itself\n")
        describe(table.actions)
        text.append("every ${table.waitMin.toInt()} to ${table.waitMax.toInt()} seconds\n")

        // Low energy and sleep
        val (percent, plugged) = phoneBattery(this)
        text.append("\nOn a low battery (${table.lowBatteryPercent}% or less, not charging)\n")
        describe(table.lowActions)
        val hasLowFrames = table.lowActions.any { a ->
            a.kind != "blink" && a.weight > 0f && (count(a.anim) > 0 || (a.kind == "travel" &&
                count(a.anim + "_left") + count(a.anim + "_right") > 0))
        }
        if (!hasLowFrames) text.append("nothing ready, so it keeps doing the list above\n")
        text.append("Battery now: ")
            .append(if (percent < 0) "unknown" else "$percent%")
            .append(if (plugged) ", charging\n" else "\n")
        text.append("\nSleep: ")
        if (count("sleep") == 0) {
            text.append("NO sleep frames, so it stays awake\n")
        } else if (table.sleepFrom == table.sleepUntil) {
            text.append("switched off (both hours are the same)\n")
        } else {
            text.append("from ${table.sleepFrom}:00 to ${table.sleepUntil}:00; ").append(
                if (table.awakeMinutes <= 0f) "it can't be woken (AWAKE_MINUTES is 0)\n"
                else "a tap or a shake wakes it for ${table.awakeMinutes} minutes\n")
        }

        // Size
        text.append("\nSize: ")
        val savedSize = GameSave.size(filesDir, pet.id)
        text.append(
            when {
                !table.fromGame -> "drawScale in PetWallpaperService.kt\n"
                savedSize != null -> "$savedSize, as set in the game\n"
                table.defaultSize > 0f -> "${table.defaultSize}, pet_size in pet.gd " +
                    "(not resized in the game yet)\n"
                else -> "drawScale in PetWallpaperService.kt\n"
            })
        val hatched = prefs.getBoolean("hatched_${pet.id}", false) ||
            GameSave.isHatched(filesDir, pet.id)
        text.append("\nHatched: ").append(if (hatched) "yes" else "no (an egg stays put)")
        text.append("\nLists come from: ")
            .append(if (table.fromGame) "the game (pet.gd)" else "this app (PetCatalog.kt)")
        screen(text.toString(), "Back" to { showStart() })
    }

    // [LOGIC] Question 1b: which pet? One button per available pet.
    //   Saves the choice for the wallpaper, then runs `next` (the following question).
    //   [ADD PET] Nothing to change here: new pets in PetCatalog.kt appear automatically.
    private fun askWhichPet(next: () -> Unit) {
        val buttons = pets.map { p ->
            p.name to {
                prefs.edit().putString(PetCatalog.KEY_PET, p.id).apply()
                next()
            }
        }
        screen(
            "Which pet should live on your home screen?",
            *buttons.toTypedArray(),
            "Back" to { showStart() }
        )
    }

    // [LOGIC] Question 2: keep the current wallpaper?
    //   Yes -> photo picker (SECTION 4), then question 2b
    //   No  -> delete any saved pictures so the Project P wallpaper is used, then finishSetup()
    //   If pictures were already picked earlier, they can simply be kept (no gallery needed).
    private fun askKeepWallpaper() {
        if (hasOwnPhoto()) {
            screen(
                "Which background should be behind the pet?",
                (if (hasLockPhoto()) "Keep the pictures I chose before"
                else "Keep the picture I chose before") to { finishSetup() },
                "Pick different pictures" to { pickBackground(PICK_HOME_PICTURE) },
                "Use the Project P wallpaper" to { useProjectPWallpaper() },
                "Back" to { showStart() }
            )
            return
        }
        screen(
            "Keep your current wallpaper behind the pet?\n\n" +
                "If yes, pick the picture you use as your home screen wallpaper now from " +
                "your gallery. A GIF is animated on the lock screen.",
            "Yes, keep my wallpaper" to { pickBackground(PICK_HOME_PICTURE) },
            "No, use the Project P wallpaper" to { useProjectPWallpaper() },
            "Back" to { showStart() }
        )
    }

    // [LOGIC] Question 2b, asked after the home screen picture was picked:
    //   is the lock screen wallpaper a different picture?
    //   Yes -> photo picker again, for the lock screen picture, then finishSetup()
    //   No  -> delete any saved lock screen picture (both screens use the same one)
    // The pet is on both screens either way.
    private fun askLockScreenPicture() {
        val buttons = mutableListOf<Pair<String, () -> Unit>>()
        buttons += "No, it's the same picture" to {
            File(filesDir, LOCK_BACKGROUND_FILE).delete()
            finishSetup()
        }
        buttons += "Yes, pick my lock screen picture" to { pickBackground(PICK_LOCK_PICTURE) }
        if (hasLockPhoto()) {
            buttons += "Keep the lock screen picture I chose before" to { finishSetup() }
        }
        buttons += "Back" to { askKeepWallpaper() }
        screen(
            "Is your lock screen wallpaper a different picture?\n\n" +
                "If yes, pick it too, so each screen keeps its own picture behind the pet.",
            *buttons.toTypedArray()
        )
    }

    // Removes the user's pictures, so the Project P wallpaper is used on both screens.
    private fun useProjectPWallpaper() {
        File(filesDir, BACKGROUND_FILE).delete()
        File(filesDir, LOCK_BACKGROUND_FILE).delete()
        finishSetup()
    }

    // [LOGIC] Last screen.
    //   Pet already on -> just confirm (the wallpaper reloads the background by itself)
    //   Not yet        -> explain the last step, then open Android's wallpaper preview
    private fun finishSetup() {
        if (isPetWallpaperOn()) {
            // Already on: the wallpaper picks up the new pet or background by itself
            screen(
                "Done! You'll see the change next time you go to your home screen.",
                "Close" to { finish() }
            )
        } else {
            screen(
                "Last step!\n\nOn the next screen, tap \"Set wallpaper\" " +
                    "and choose \"Home and lock screens\".",
                "Continue" to { openWallpaperPreview() },
                "Back" to { askKeepWallpaper() }
            )
        }
    }

    // ===== SECTION 3: HELPERS =======================================================

    /** Shows a message with a column of buttons. Every screen above uses this. */
    // [EDIT] To change how all screens look (text size, spacing, colours), edit this
    //        function and the colours in SECTION 1.
    // Layout: the Project P wallpaper picture fills the screen; on top of it a rounded
    // panel holds the message and the buttons. The panel scrolls if there are many
    // buttons (e.g. a long "Which pet?" list).
    private fun screen(message: String, vararg buttons: Pair<String, () -> Unit>) {
        val dp = resources.displayMetrics.density
        val pad = (24 * dp).toInt()                                 // 24dp spacing

        // The panel: message at the top, then one button per choice
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable().apply {
                setColor(Color.parseColor(PANEL_COLOR))
                cornerRadius = 24 * dp
            }
        }
        panel.addView(TextView(this).apply {
            text = message
            textSize = 18f
            setTextColor(Color.parseColor(TEXT_COLOR))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, pad / 2)
        })
        for ((label, action) in buttons) {
            panel.addView(Button(this).apply {
                text = label
                isAllCaps = false
                setTextColor(Color.parseColor(BUTTON_TEXT_COLOR))
                backgroundTintList = ColorStateList.valueOf(Color.parseColor(BUTTON_COLOR))
                setOnClickListener { action() }
            }, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = (8 * dp).toInt()
            })
        }

        // The picture behind everything, filling the screen without stretching
        val root = FrameLayout(this)
        root.setBackgroundColor(Color.parseColor(EDGE_COLOR))
        val pictureId = resources.getIdentifier("pet_default_bg", "drawable", packageName)
        if (pictureId != 0) {
            root.addView(ImageView(this).apply {
                setImageResource(pictureId)
                scaleType = ImageView.ScaleType.CENTER_CROP
            }, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
        // The panel sits in the middle; the scroll area keeps it usable on small screens
        val holder = FrameLayout(this).apply { setPadding(pad, pad, pad, pad) }
        holder.addView(panel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.CENTER))
        root.addView(ScrollView(this).apply {
            isFillViewport = true      // keeps short screens centred
            addView(holder, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setContentView(root)
    }

    // Should we ask "Which pet?" Only with more than one pet in PetCatalog.kt, and only
    // when the Godot game hasn't chosen one (inside the game's app, the game decides).
    private fun hasSeveralPets() =
        pets.size > 1 && GameSave.chosenPet(filesDir) == null

    // The pet that will be shown: the game's choice, else the one picked here, else
    // the first pet.
    private fun chosenPet() = PetCatalog.byId(
        pets, GameSave.chosenPet(filesDir) ?: prefs.getString(PetCatalog.KEY_PET, null)
    )

    // Has the user picked their own picture? (false = Project P wallpaper is used)
    private fun hasOwnPhoto() = File(filesDir, BACKGROUND_FILE).exists()

    // Has the user picked a separate picture for the lock screen?
    private fun hasLockPhoto() = hasOwnPhoto() && File(filesDir, LOCK_BACKGROUND_FILE).exists()

    // Is our pet wallpaper the phone's current wallpaper?
    // [FIX] If the first screen shows the wrong status, check this.
    private fun isPetWallpaperOn(): Boolean {
        val info = WallpaperManager.getInstance(this).wallpaperInfo ?: return false
        return info.packageName == packageName &&
            info.serviceName == PetWallpaperService::class.java.name
    }

    // "Remove pet from home screen": apps can't put back the user's old wallpaper,
    // so this opens Android's own wallpaper settings for the user to pick one.
    private fun removePet() {
        // Let the user pick a different wallpaper in Android's own wallpaper settings
        val intent = Intent(Intent.ACTION_SET_WALLPAPER)
        try {
            startActivity(Intent.createChooser(intent, "Choose a new wallpaper"))
            backFromPreview = true
        } catch (e: Exception) {
            val msg = "Open your phone's wallpaper settings to choose another wallpaper."
            Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
        }
    }

    // ===== SECTION 4: PHOTO PICKER (no permission needed) ===========================
    // Opens Android's photo picker so the user can choose their wallpaper picture.
    // Android 13+ uses the new photo picker; older phones use the file chooser.
    // Only pictures are offered (photos, PNGs, GIFs...), not videos.
    // `which` says which picture is being picked: PICK_HOME_PICTURE or PICK_LOCK_PICTURE.
    private fun pickBackground(which: Int) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ photo picker, pictures only
            Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
        } else {
            Intent(Intent.ACTION_GET_CONTENT).apply { type = "image/*" }
        }
        try {
            startActivityForResult(intent, which)
        } catch (e: Exception) {
            // [FIX] Some phones don't have the new picker: fall back to the file chooser.
            try {
                val fallback = Intent(Intent.ACTION_GET_CONTENT).apply { type = "image/*" }
                startActivityForResult(fallback, which)
            } catch (e2: Exception) {
                val msg = "No gallery app was found to pick a picture."
                Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
            }
        }
    }

    // Runs when the photo picker closes.
    // Saves a copy of the chosen picture for PetWallpaperService. After the home screen
    // picture it asks about the lock screen (question 2b); after the lock screen picture
    // it goes to finishSetup().
    // A GIF is copied as it is, so the wallpaper can animate it on the lock screen.
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_HOME_PICTURE && requestCode != PICK_LOCK_PICTURE) return
        val fileName =
            if (requestCode == PICK_LOCK_PICTURE) LOCK_BACKGROUND_FILE else BACKGROUND_FILE
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) return     // cancelled: stay on the question
        try {
            // Copy the photo into the app's own storage so the wallpaper can always read it.
            // Written to a .tmp file first, then renamed, so the wallpaper never reads a
            // half-written photo.
            val temp = File(filesDir, "$fileName.tmp")
            temp.delete()                                      // leftover from an earlier try
            val input = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("picture can't be opened")
            input.use { temp.outputStream().use { output -> it.copyTo(output) } }
            if (temp.length() == 0L || !temp.renameTo(File(filesDir, fileName))) {
                throw IllegalStateException("picture can't be saved")
            }
            if (requestCode == PICK_HOME_PICTURE) askLockScreenPicture() else finishSetup()
        } catch (e: Exception) {
            // [FIX] Shown if the photo can't be read (e.g. a cloud photo that isn't downloaded).
            val msg = "Couldn't use that picture. Try another one."
            Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
        }
    }

    // ===== SECTION 5: OPEN ANDROID'S WALLPAPER PREVIEW ==============================
    // Opens the preview for our pet wallpaper; the user taps "Set wallpaper" there.
    // Apps can't set a live wallpaper by themselves, so this step is always the user's.
    // [FIX] "This phone doesn't support live wallpapers": a few phones (some Android Go
    //       models) have no live wallpapers at all; the pet then stays in the app.
    private fun openWallpaperPreview() {
        try {
            startActivity(
                Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).putExtra(
                    WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                    ComponentName(this, PetWallpaperService::class.java)
                )
            )
            backFromPreview = true
        } catch (e: Exception) {
            val msg = "This phone doesn't support live wallpapers."
            Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
        }
    }
}
