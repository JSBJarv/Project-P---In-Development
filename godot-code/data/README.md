# Game data

Every number the battle and training use lives in these JSON files. Change a value, then run the tests and the balance runner (see `../README.md`). Keys starting with `_` are notes and are ignored.

## balance.json - the formulas

| Combat stat | Formula |
| --- | --- |
| Max HP | `hp.base + hp.per_vit × VIT + hp.per_str × STR + hp.per_level × level` |
| Max Mana | `mana.base + mana.per_spi × SPI + mana.per_int × INT` |
| Mana regen per turn | `mana_regen.base + mana_regen.per_spi × SPI` |
| Speed (who acts first) | `speed.per_agi × AGI + speed.per_level × level` |
| Block chance | `block.cap × STR / (STR + block.k)` (+ buffs, − Cut); a block multiplies damage by `block.damage_taken`; `physical_only` = arcane attacks can't be blocked |
| Dodge chance | `dodge.cap × AGI / (AGI + dodge.k)` |
| Critical chance | `crit.base + crit.extra × AGI / (AGI + crit.k)`, at most `crit.cap` |
| Critical damage | `crit_damage.base + crit_damage.per_str × STR`, at most `crit_damage.cap` |
| Guard (cuts physical) | `guard.per_str × STR + guard.per_vit × VIT` |
| Ward (cuts arcane) | `ward.per_int × INT + ward.per_spi × SPI` |

**Damage of one hit:** `(scaling.base + Σ scaling.stat × stat) × element × same-element bonus × passive × damage_scale × (1 − defence / (defence + defense_k)) × critical × random(damage_random)`, then halved on a block, then shields absorb it.

- `element_strong` / `element_weak`: multiplier when the skill's element is strong / weak against the target's element (`elements.json`).
- `same_element_bonus`: extra when a pet uses a skill of its own element.
- `damage_scale`: one dial for how fast fights end (target 8-15 rounds).
- Status chance: `skill chance + (attacker INT − target's resist stat) × status_chance_per_point`, kept between `status_chance_min` and `status_chance_max`.
- Spirit (ultimate gauge, 0-100): `+per_turn` each turn, `+per_damage_taken × damage / own max HP`, `+per_damage_dealt × damage / enemy max HP`, all × `(1 + spi_bonus_per_point × SPI)`. At 100 the pet uses its ultimate.
- `battle.max_rounds`: after this many rounds the pet with more HP (as a share) wins.

**Training** (`training`): each stat point costs `cost_base + cost_per_point × current stat` Training Points. Per stat per day, the first `daily_soft_cap` TP count fully, then `after_soft_cap` up to `daily_hard_cap`, then nothing. Manual (unverified) entries count `manual_entry_weight`. A pet's favoured stat gets `favoured_stat_bonus` extra.

## pets.json

`name`, `animal`, `title`, `element` (suggested innate element), `favoured` (stat), `habit`, `unlock`, `skills` (default loadout, **in priority order** - put situational skills first and the cheap no-cooldown skill last, or the pet will only ever use the cheap one), `ultimate`, `passive`, `forms` (Adult forms: Martial / Arcane / Swift).

Passive kinds: `free_every` (n), `low_hp_stat` (threshold, stat, pct), `dodge_speed` (amount), `regen` (pct, every), `first_strike_stacks` (pct, max), `start_shield` (pct, refresh_below), `first_hit_blocked` (count), `arcane_stacks` (pct, max), `first_turn`, `first_debuff_immune` (spirit_on_debuff), `reflect_physical` (pct). Each is explained in SECTION 7 of `battle/battle_sim.gd`.

## skills.json

| Field | Meaning |
| --- | --- |
| `name`, `element` | Shown in the banner; `element` = fire / water / wind / earth / lunar / solar / none |
| `type` | `physical` (cut by Guard, can be blocked), `arcane` (cut by Ward), `support` |
| `template` | How it looks: `melee`, `combo`, `projectile`, `area`, `self`, `hex`, `ultimate` |
| `cost`, `cooldown` | Mana and turns before it can be used again |
| `scaling` | Damage: `base` + share of each stat, e.g. `{"base": 15, "str": 1.2}` |
| `hits` | Number of hits (default 1) |
| `crit_bonus`, `crit_bonus_per_hit`, `guard_ignore`, `pierce_shield`, `crit_if_marked`, `extra_hit`, `bonus_hit_per_debuff` | Optional extras |
| `effects` | Run in order after the hits: `status` (status, chance, turns, power, per_hit), `heal` (pct_max_hp, scaling), `shield` (pct_max_hp / pct_max_mana, scaling), `buff` (stat, amount, turns), `counter` (turns, scaling, stun_chance), `evade` (count, counter), `mana_steal` (amount), `cleanse` (count) |
| `mastery` | `[{"stat": "str", "at": 150, "mods": {...}}]` - when the pet's stat reaches `at`, the fields in `mods` replace the skill's own |

How a pet decides: it goes down its skill list and uses the first skill that is off cooldown, affordable and useful right now (heals only below 60% HP; shields, buffs, counters, evades only when not already active; status-only skills only if the enemy doesn't have that status yet). Otherwise it uses a free basic attack.

## elements.json, status_effects.json, activities.json

- **elements**: name, `strong_against`, `color` and `light` (used for effects, stand-ins and the recolour shader).
- **status_effects**: `kind`, `resisted_by` (stat), `max_stacks`, extras such as `per_stack` (Cut), `no_repeat` (Stun / Sleep can't land twice in a row), `breaks_on_damage` (Sleep).
- **activities**: real-life activity → Training Points: `tp` per `per` unit, `stats` (share per stat), optional `daily_max`, `source`.
