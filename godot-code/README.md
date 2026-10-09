# Godot Code

The Godot project for Project P. Open this folder (the one containing `project.godot`) in **Godot 4.6** (Compatibility renderer).

Targets: Android, iOS, desktop. The pet app is portrait (720 × 1280); the Dojo battle turns the phone to landscape (1280 × 720) while it is open.

## Structure

```
godot-code/
├── project.godot            # project settings, autoload GameData, wallpaper add-on on
├── main.tscn                # Main: Pet + PetPicker + MainMenu (the app starts here)
├── pet.gd                   # the pet on screen (12 pet ids in PETS)
├── pet_picker.gd            # "Choose your pet" grid, 3 per row
├── main_menu.gd             # menu: Pet Selection, Wallpaper Selection, Dojo
├── pet_stats.gd             # trained stats + Training Points from real-life activity
├── evolution.gd             # stage + branch -> evolution form (Adult / Final), saved per pet
├── data/                    # ALL numbers: pets, skills, elements, balance, activities
│   ├── evolution.json       # evolution levels, branch rule and all 132 forms
│   ├── game_data.gd         # autoload "GameData" that loads the JSON files
│   └── README.md            # what every field and formula means
├── battle/
│   ├── battle_sim.gd        # the fight rules: snapshots + seed -> event log (no graphics)
│   ├── battle.tscn          # the Dojo scene (landscape)
│   ├── battle_screen.gd     # plays the event log: bars, banner, hits, numbers, end card
│   ├── battle_fighter.gd    # one pet in battle: its battle frames, or a drawn stand-in
│   └── balance_runner.gd    # fights every pet against every pet, writes a CSV
├── tests/test_battle.gd     # quick checks for data and battle rules
├── pets/<id>/               # pet frames (add yours) - battle frames in pets/<id>/battle/,
│                            #   evolution forms in pets/<id>/forms/<form id>/
├── menu/                    # menu art: background/, buttons/, splash/ (optional)
├── addons/projectp_wallpaper/   # packs the Android live wallpaper into the APK
├── android-wallpaper-only/  # only for Part B of the guide (ignored by Godot)
└── docs/                    # Android pet guide and pet.gd edit notes
```

## Adding the pet art

Nothing here needs code changes - drop files in and the scripts find them:

| What | Where | Names |
| --- | --- | --- |
| Pet frames (care screen + wallpaper) | `pets/<id>/` | as before: `egg_idle_00.png`, `idle_a_00.png` ... (see SECTION 0 of `pet.gd`) |
| Battle frames | `pets/<id>/battle/` | `battle_idle_00..07`, `attack_physical_00..07`, `cast_special_00..07`, `ultimate_00..07`, `dash_00..03`, `dodge_00..03`, `hurt_00..03`, `block_00..03`, `knockout_00..07`, `victory_00..07` - 128 × 128, facing right, feet on y = 120 |
| Evolution form frames | `pets/<id>/forms/<form id>/` and `pets/<id>/forms/<form id>/battle/` | same names as the pet's own frames; form ids are in `data/evolution.json` (e.g. `pets/gym_wolf/forms/ironfang/`). A form without frames uses the pet's own. |
| Splash art | `menu/splash/<id>.png` | 420 × 480 |
| Menu buttons | `menu/buttons/` | `pet_selection_00..02`, `wallpaper_selection_00..02`, `dojo_00..02`, `menu_00..02` |

Pet ids: `nocti`, `gym_wolf`, `moonstep`, `kindle`, `cinderpip`, `ripple`, `dozie`, `mossback`, `digby`, `sunhop`, `basko`, `quill`.
Until a pet has frames, the care screen shows nothing for it and the Dojo draws a round stand-in in its element colour.

## Checking and balancing

Run from a terminal in this folder (`godot` = your Godot 4.6 executable):

```bash
godot --headless --import --path .                                  # first time only
godot --headless --path . -s res://tests/test_battle.gd             # 14 checks, exit code 0 = all pass
godot --headless --path . -s res://battle/balance_runner.gd         # win rates of all 12 pets
godot --headless --path . -s res://battle/balance_runner.gd -- --fights 500 --total 300
```

Current balance (200 stat points each, level 10, 120 fights per pairing): every pet wins 40-61% of fights, median fight 9 rounds. Change numbers in `data/*.json`, then run both commands again.

## Pet + home-screen wallpaper

| File / folder | What it is |
| --- | --- |
| `pet.gd` | The pet: frames, hatching, tickle, drag/resize, actions, one trick at a time, low energy, sleep |
| `pet_picker.gd` | Pet selection grid with splash art (`res://menu/splash/<id>.png`) |
| `main_menu.gd` | Main menu: animated background, Pet Selection, Wallpaper Selection and Dojo buttons |
| `addons/projectp_wallpaper/` | Godot add-on (v1.8) that packs the Android live wallpaper into the game's APK |
| `docs/Project_P_Android_Pet_Guide.pdf` | Step-by-step guide (Part A game, Part B optional wallpaper app, Part C one app) |

Not run on a real phone yet. The project, tests, balance runner and a full Dojo battle were run in Godot 4.6 on Linux; the wallpaper add-on export was tested earlier in Godot 4.3 and 4.5.
