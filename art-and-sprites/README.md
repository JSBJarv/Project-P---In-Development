# Art Style and Sprites

## Art direction

- **Style:** 2D-3D hybrid (pseudo-3D) sprites with a chibi / super-deformed character design, in the vein of Ragnarok Online
- **Mood:** cozy, pastel palette
- **Pet sprites:** 64x64 pixel art; the pet is an original creature with multiple growth stages

## Folders

| Folder | Contents |
| --- | --- |
| `style-guide/` | Palette, proportions, reference sheets, do/don't examples |
| `sprites/pets/` | Pet sprites and animations, one subfolder per growth stage |
| `sprites/ui/` | Icons, buttons, shop and inventory art |
| `sprites/environment/` | Backgrounds, props, tiles |
| `source-files/` | Working files (e.g. `.aseprite`, `.psd`) before export |

## Conventions

- Export final sprites as PNG with transparency.
- Name files `subject_stage_action_frame.png`, e.g. `pet_baby_idle_01.png`.
- Keep working files in `source-files/`; only exported PNGs go into `sprites/`.
