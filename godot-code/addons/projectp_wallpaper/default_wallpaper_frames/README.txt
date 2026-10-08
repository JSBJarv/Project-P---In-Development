ANIMATED PROJECT P WALLPAPER (optional)
=======================================
Put the animation frames of the default wallpaper in this folder.
With no pictures here, the wallpaper shows the still picture (default_wallpaper.png).

Rules for the frames
- Name them in playing order: frame_00.jpg, frame_01.jpg, frame_02.jpg, ...
  (always two digits, so frame_02 comes before frame_10)
- JPG, PNG or WebP. JPG is best: smaller files and faster to load.
- All the same size, portrait, the same shape as default_wallpaper.png.
  1080 x 1920 pixels is a good size.
- 8 to 24 frames make a nice loop. The last frame should lead back into the first.
- Make default_wallpaper.png (one folder up) the same picture as frame_00, so the still
  and the animation match.

After adding or changing frames: export the game again from Godot.
The Output panel then says: "Project P Wallpaper: animated default wallpaper, N background
frames added."

Speed: defaultAnimationFps in android/src/PetWallpaperService.kt (SECTION 2).
Where it plays: animateBackgroundOnLockScreen / animateBackgroundOnHomeScreen (same place).

Godot doesn't show this folder on purpose (the .gdignore file keeps the frames out of the
game itself). Use your computer's file explorer.
