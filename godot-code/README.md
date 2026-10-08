# Godot Code

The Godot project for Project P. Open this folder (the one containing `project.godot`) in the Godot editor.

Targets: Android, iOS, desktop.

## Suggested structure

```
godot-code/
├── project.godot
├── scenes/      # .tscn files
├── scripts/     # GDScript
├── assets/      # sprites imported from art-and-sprites/sprites
└── addons/
```

## Systems to build

- Pet: growth stages, care stats and actions
- Battle stats: Strength, Intelligence, Speed, Block, Dodge, Critical, Mana (raised by real-life activities)
- Passives, and later cards that augment skill effects
- Shop and inventory

## Pet + home-screen wallpaper (current working files)

These files go next to `project.godot` in your Godot project. The paths matter: the add-on
looks for `res://pet.gd`, and the main menu looks for `res://pet_picker.gd`.

| File / folder | What it is |
| --- | --- |
| `pet.gd` | The pet: frames, hatching, tickle, drag/resize, actions, one trick at a time, low energy, sleep |
| `pet_picker.gd` | Pet selection grid with splash art (`res://menu/splash/<id>.png`) |
| `main_menu.gd` | Main menu: animated background, Pet Selection and Wallpaper Selection buttons |
| `addons/projectp_wallpaper/` | Godot add-on (v1.8) that packs the Android live wallpaper into the game's APK |
| `docs/Project_P_Android_Pet_Guide.pdf` | Step-by-step guide (Part A game, Part B optional wallpaper app, Part C one app) |
| `docs/pet_gd_edits*.txt` | Find-and-replace edits for updating a hand-edited `pet.gd` |
| `android-wallpaper-only/` | Only for Part B of the guide (wallpaper as its own Android Studio app) |

Not run on a real phone yet: the Kotlin compiles, and `pet.gd` and the add-on export
were tested in Godot 4.3 and 4.5.
