// =====================================================================================
// WallpaperBridge.kt  -  THE DOOR BETWEEN THE GODOT GAME AND ANDROID (one app only)
// =====================================================================================
// What this file does:
//   The game and the wallpaper are one app with one icon. This small file is the door
//   between them: it gives the game (GDScript) these things it can call.
//     openWallpaperSetup()  -> opens the setup screens (SetWallpaperActivity.kt)
//     isWallpaperOn()       -> true if the pet wallpaper is the phone's wallpaper now
//     batteryPercent()      -> how full the battery is, 0..100 (-1 = unknown)
//     isCharging()          -> true while the phone is plugged in
//   The last two are what pet.gd uses for the pet's low-energy behaviour (search
//   "_is_low_energy" there). Reading the battery level needs no permission.
//
// How the game uses it (see main_menu.gd, the "Wallpaper Selection" button):
//     if Engine.has_singleton("ProjectPWallpaper"):
//         Engine.get_singleton("ProjectPWallpaper").openWallpaperSetup()
//
// Only for the one-app setup (Part C). The Godot add-on copies this file into the
// Android build and registers it in the manifest. Do NOT add it to the wallpaper-only
// Android Studio project (Part B); it needs Godot's library and won't compile there.
//
// How to find things:
//   [EDIT]  = something you can safely change
//   [FIX]   = places to look first if something goes wrong
//
// [FIX] "Wallpaper Selection" does nothing on the phone (or shows the message meant
//       for computers): the name returned by getPluginName() below must match
//       PLUGIN_NAME in the add-on's plugin.gd and WALLPAPER_PLUGIN in main_menu.gd and
//       pet_picker.gd ("ProjectPWallpaper").
//
// Related files:
//   SetWallpaperActivity.kt      - the screens this opens
//   PetWallpaperService.kt       - the wallpaper itself
//   addons/projectp_wallpaper/plugin.gd  - registers this file when the game is exported
// =====================================================================================

package com.yourname.projectp.wallpaper

import android.app.WallpaperManager
import android.content.Intent
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

class WallpaperBridge(godot: Godot) : GodotPlugin(godot) {

    // The name the game asks for: Engine.get_singleton("ProjectPWallpaper")
    override fun getPluginName() = "ProjectPWallpaper"

    /** Opens the wallpaper setup screens on top of the game. */
    @UsedByGodot
    fun openWallpaperSetup() {
        val game = activity ?: return
        game.runOnUiThread {
            try {
                game.startActivity(Intent(game, SetWallpaperActivity::class.java))
            } catch (e: Exception) {
                // [FIX] Nothing opens: check the <activity> entry in the add-on's plugin.gd.
            }
        }
    }

    /** Is the pet wallpaper the phone's current wallpaper? */
    @UsedByGodot
    fun isWallpaperOn(): Boolean {
        val game = activity ?: return false
        return try {
            val info = WallpaperManager.getInstance(game).wallpaperInfo
            info != null && info.packageName == game.packageName &&
                info.serviceName == PetWallpaperService::class.java.name
        } catch (e: Exception) {
            false
        }
    }

    /** How full the battery is: 0..100, or -1 if the phone doesn't say. */
    @UsedByGodot
    fun batteryPercent(): Int {
        val game = activity ?: return -1
        return phoneBattery(game).first
    }

    /** Is the phone plugged in (charging or full)? */
    @UsedByGodot
    fun isCharging(): Boolean {
        val game = activity ?: return false
        return phoneBattery(game).second
    }
}
