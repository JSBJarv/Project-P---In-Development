# =====================================================================================
# pet_stats.gd  -  A PET'S BATTLE STATS AND TRAINING (from real-life activity)
# =====================================================================================
# What this file does:
#   Keeps each pet's five trained stats (STR, INT, AGI, VIT, SPI), its level and its
#   Training Points, and turns real-life activity into stat points:
#     activity -> Training Points (flat, activities.json) -> stat points (each point
#     costs a little more than the last, with a daily soft and hard cap; balance.json).
#   Everything is saved in user://pet.cfg, the same file pet.gd uses, in a section
#   called "stats_<pet id>" so it never touches the pet's position or hatch state.
#
# How to use it (from any script):
#   PetStats.get_stats("nocti")                    -> {"str": 10, "int": 10, ...}
#   PetStats.add_activity("nocti", "focus_session", 2, true)  -> two verified 25-min
#                                                     focus sessions; returns what changed
#   PetStats.get_level("nocti")
#
# How to find things:
#   [EDIT]  = a setting you can safely change
#   [LOGIC] = what leads to what
#   [FIX]   = places to look first if something goes wrong
#
# Sections in this file:
#   1. Settings                                      -> search "SECTION 1"
#   2. Reading stats                                 -> search "SECTION 2"
#   3. Training from real-life activity              -> search "SECTION 3"
#   4. Saving                                        -> search "SECTION 4"
# =====================================================================================

class_name PetStats
extends RefCounted

# ===== SECTION 1: SETTINGS ===========================================================
const SAVE_PATH := "user://pet.cfg"
const STATS := ["str", "int", "agi", "vit", "spi"]

# ===== SECTION 2: READING STATS ======================================================
static func get_stats(pet_id: String) -> Dictionary:
	var start: Dictionary = _training().get("start_stats", {})
	var cfg := _load()
	var out := {}
	for s in STATS:
		out[s] = int(cfg.get_value(_section(pet_id), s, start.get(s, 10)))
	return out

static func get_level(pet_id: String) -> int:
	var lvl: int = int(GameDataLoader.shared().balance.get("battle", {}).get("level_default", 10))
	return int(_load().get_value(_section(pet_id), "level", lvl))

# Training Points stored towards the next point of each stat (0..cost).
static func get_progress(pet_id: String) -> Dictionary:
	var cfg := _load()
	var out := {}
	for s in STATS:
		out[s] = float(cfg.get_value(_section(pet_id), "tp_" + s, 0.0))
	return out

# [LOGIC] Cost of the next point of a stat: 1 + stat / 50 Training Points (balance.json
#         training.cost_base + cost_per_point x stat), so growth is fast early and slower later.
static func point_cost(stat_value: int) -> float:
	var t := _training()
	return float(t.get("cost_base", 1.0)) + float(t.get("cost_per_point", 0.02)) * stat_value

# ===== SECTION 3: TRAINING FROM REAL-LIFE ACTIVITY ===================================
# Adds `units` of an activity (see activities.json: 2 units of focus_session = 2 x 25
# minutes). verified = it came from Health Connect / HealthKit / the in-app timer; a
# manual entry counts balance.training.manual_entry_weight (half).
# Returns {"tp": {"int": 4.0}, "gained": {"int": 2}} - what was added.
static func add_activity(pet_id: String, activity: String, units: float, verified := true) -> Dictionary:
	var act: Dictionary = GameDataLoader.shared().activities.get(activity, {})
	if act.is_empty():
		push_warning("Project P: unknown activity '%s' (see data/activities.json)" % activity)
		return {}
	var t := _training()
	var tp := float(act.get("tp", 0)) * units
	if act.has("daily_max"):
		tp = minf(tp, float(act.get("tp", 0)) * float(act["daily_max"]))
	if not verified:
		tp *= float(t.get("manual_entry_weight", 0.5))
	var favoured: String = GameDataLoader.shared().pet(pet_id).get("favoured", "")
	var result := {"tp": {}, "gained": {}}
	for s in act.get("stats", {}):
		var share := tp * float(act["stats"][s])
		if s == favoured:
			share *= 1.0 + float(t.get("favoured_stat_bonus", 0.10))
		var gained := add_training_points(pet_id, s, share)
		result["tp"][s] = share
		result["gained"][s] = gained
	return result

# Adds Training Points to one stat, respecting today's caps, and turns them into stat
# points. Returns how many stat points were gained.
# [LOGIC] Up to daily_soft_cap TP a stat counts fully, then half up to daily_hard_cap,
#         then nothing - training more on one day doesn't help (protects health).
static func add_training_points(pet_id: String, stat: String, tp: float) -> int:
	if not STATS.has(stat) or tp <= 0.0:
		return 0
	var t := _training()
	var cfg := _load()
	var sec := _section(pet_id)
	var today := Time.get_date_string_from_system()
	if cfg.get_value(sec, "day", "") != today:
		for s in STATS:
			cfg.set_value(sec, "today_" + s, 0.0)
		cfg.set_value(sec, "day", today)
	var done := float(cfg.get_value(sec, "today_" + stat, 0.0))
	var soft := float(t.get("daily_soft_cap", 12))
	var hard := float(t.get("daily_hard_cap", 20))
	var counted := 0.0
	var left := tp
	while left > 0.0 and done < hard:
		var step := minf(left, (soft - done) if done < soft else (hard - done))
		counted += step * (1.0 if done < soft else float(t.get("after_soft_cap", 0.5)))
		done += step
		left -= step
	cfg.set_value(sec, "today_" + stat, done)
	var value := int(cfg.get_value(sec, stat, _training().get("start_stats", {}).get(stat, 10)))
	var bank := float(cfg.get_value(sec, "tp_" + stat, 0.0)) + counted
	var gained := 0
	while bank >= point_cost(value):
		bank -= point_cost(value)
		value += 1
		gained += 1
	cfg.set_value(sec, stat, value)
	cfg.set_value(sec, "tp_" + stat, bank)
	cfg.save(SAVE_PATH)
	return gained

# For testing: set a pet's stats directly, e.g. set_stats("nocti", {"int": 150}).
static func set_stats(pet_id: String, values: Dictionary, level := -1) -> void:
	var cfg := _load()
	for s in values:
		if STATS.has(s):
			cfg.set_value(_section(pet_id), s, int(values[s]))
	if level > 0:
		cfg.set_value(_section(pet_id), "level", level)
	cfg.save(SAVE_PATH)

# ===== SECTION 4: SAVING =============================================================
static func _section(pet_id: String) -> String:
	return "stats_" + pet_id

static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # a missing file is fine: everything starts at default
	return cfg

static func _training() -> Dictionary:
	return GameDataLoader.shared().balance.get("training", {})
