# Game Design

Full concept: the "Project P - Pet Battle System Concept" doc (battle, stats, evolution, skills, elements, the 12-pet roster).

## Pet

- 12 original pets, each tied to one real-life habit and unlocked by doing it (Nocti the owl is the starter egg)
- Pixel art, 128 × 128 frames, feet on y = 120 (the Project P standard cell)
- Growth stages: Egg → Baby → Child (Lv 10) → Adult (Lv 25, branch by STR / INT / AGI share) → Final (Lv 45)
- Care stats and care actions; lives on the home and lock screen as a live wallpaper

## Stats (raised only by real-life activity)

- Trained: Strength, Intelligence, Agility, Vitality (HP), Spirit (Mana)
- Derived: Max HP, Max Mana, Mana regen, Speed, Block, Dodge, Critical, Guard, Ward
- Activity → Training Points (flat) → stat points (rising cost, daily soft and hard cap)
- Numbers: `godot-code/data/balance.json`, `activities.json`

## Battle (Dojo)

- Pockie Ninja-style auto-battle, landscape, decided by a headless simulator from two pet snapshots + a seed
- 4 skills in priority order + ultimate (Spirit 100) + passive; six elements; status effects
- Async multiplayer later: the opponent fights as their last saved snapshot
- Numbers: `godot-code/data/skills.json`, `pets.json`, `elements.json`, `status_effects.json`

## Abilities

- Passives (one per pet, see `pets.json`)
- Later: cards / gems that augment skill effects, gear, Dojo Tower

## Economy

- Shop, inventory; stats and skills are never sold (cosmetics, artist-made pets)

## Platforms

Android first, then iOS and desktop. One APK with the game and the wallpaper.
