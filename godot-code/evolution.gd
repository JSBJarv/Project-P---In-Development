# =====================================================================================
# evolution.gd  -  WHEN A PET EVOLVES AND WHICH FORM IT BECOMES
# =====================================================================================
# What this file does:
#   Decides a pet's stage (baby -> child -> adult -> final) from its level, and its
#   branch from how its STR, INT and AGI compare:
#     Martial (STR), Arcane (INT), Swift (AGI), Harmony (all close), and at Final also
#     the hybrids Martial-Arcane, Martial-Swift, Arcane-Swift (top two close).
#   The branch is decided at the moment the pet evolves and then kept, so training
#   afterwards never changes a form the player already has.
#   All numbers and form names are in res://data/evolution.json.
#
# How to use it (from any script):
#   Evolution.check("nocti")        -> call after the level changes or the Trial is won;
#                                      returns {"evolved": true, "from": {...}, "to": {...}}
#                                      when the pet just evolved (show the evolution moment)
#   Evolution.current("nocti")      -> {"stage": "adult", "branch": "Arcane",
#                                       "id": "runeowl", "name": "Runeowl", "animal": "Barn owl"}
#   Evolution.preview("nocti")      -> the form it is heading for, shortly before it evolves
#   Evolution.battle_stats("nocti") -> trained stats + this stage's flat bonus
#   Evolution.art_folder("nocti", "res://pets/nocti") -> the folder with this form's frames
#
# Where the form art goes:
#   res://pets/<pet id>/forms/<form id>/          care-screen frames (same names as the pet's)
#   res://pets/<pet id>/forms/<form id>/battle/   battle frames
#   A form without its own frames simply uses the pet's normal frames.
#
# How to find things:
#   [EDIT]  = a setting you can safely change
#   [LOGIC] = what leads to what
#   [FIX]   = places to look first if something goes wrong
#
# Sections in this file:
#   1. Settings                                      -> search "SECTION 1"
#   2. Stage and branch rules                        -> search "SECTION 2"
#   3. The pet's form (saved)                        -> search "SECTION 3"
#   4. Battle and art                                -> search "SECTION 4"
#   5. Saving                                        -> search "SECTION 5"
# =====================================================================================

class_name Evolution
extends RefCounted

# ===== SECTION 1: SETTINGS ===========================================================
const STAGES := ["baby", "child", "adult", "final"]
const BRANCH_STAT := {"Martial": "str", "Arcane": "int", "Swift": "agi"}
# [EDIT] Folder (inside the pet's folder) that holds the art of each form.
const FORMS_FOLDER := "forms"

# ===== SECTION 2: STAGE AND BRANCH RULES =============================================
# [LOGIC] Stage from level: child at stages.child, adult at stages.adult, final at
#         stages.final - but final only once the Trial battle is won (final_needs_trial).
static func stage_for(level: int, trial_won := false) -> String:
	var s: Dictionary = _data().get("stages", {})
	if level >= int(s.get("final", 45)) and (trial_won or not _data().get("final_needs_trial", true)):
		return "final"
	if level >= int(s.get("adult", 25)):
		return "adult"
	if level >= int(s.get("child", 10)):
		return "child"
	return "baby"

# Share of STR, INT and AGI in percent of the three added up: {"str": 45.0, ...}
static func shares(stats: Dictionary) -> Dictionary:
	var total := 0.0
	for s in BRANCH_STAT.values():
		total += maxf(0.0, float(stats.get(s, 0)))
	var out := {}
	for s in BRANCH_STAT.values():
		out[s] = 100.0 / 3.0 if total <= 0.0 else 100.0 * maxf(0.0, float(stats.get(s, 0))) / total
	return out

# [LOGIC] The branch for a stage ("" for baby and child):
#   1. Harmony  - all three shares within branch_rule.harmony_within points (rare)
#   2. Hybrid   - Final only: the top two shares within branch_rule.hybrid_within,
#                 named higher stat first in Martial, Arcane, Swift order (Martial-Arcane ...)
#   3. Pure     - the top stat's branch (Adults that are close still take their top stat)
# [FIX] A pet keeps landing on a branch you didn't expect: print Evolution.shares(stats)
#       and compare with branch_rule in evolution.json.
static func branch_for(stats: Dictionary, stage: String) -> String:
	if stage != "adult" and stage != "final":
		return ""
	var rule: Dictionary = _data().get("branch_rule", {})
	var sh := shares(stats)
	var order: Array = BRANCH_STAT.keys()          # ties go to Martial, then Arcane, then Swift
	order.sort_custom(func(a, b): return sh[BRANCH_STAT[a]] > sh[BRANCH_STAT[b]] \
		or (sh[BRANCH_STAT[a]] == sh[BRANCH_STAT[b]] and BRANCH_STAT.keys().find(a) < BRANCH_STAT.keys().find(b)))
	var top: float = sh[BRANCH_STAT[order[0]]]
	var second: float = sh[BRANCH_STAT[order[1]]]
	var low: float = sh[BRANCH_STAT[order[2]]]
	if top - low <= float(rule.get("harmony_within", 6)):
		return "Harmony"
	if stage == "final" and top - second < float(rule.get("hybrid_within", 8)):
		var pair := [order[0], order[1]]
		pair.sort_custom(func(a, b): return BRANCH_STAT.keys().find(a) < BRANCH_STAT.keys().find(b))
		return "%s-%s" % pair
	return order[0]

# The form for a pet, stage and branch: {"stage", "branch", "id", "name", "animal"}.
# Baby and child have no form of their own (id "", the pet's own name).
static func form_for(pet_id: String, stage: String, branch: String) -> Dictionary:
	var out := {"stage": stage, "branch": branch, "id": "",
		"name": GameDataLoader.shared().pet(pet_id).get("name", pet_id), "animal": ""}
	if stage == "adult" or stage == "final":
		var f: Dictionary = _data().get("forms", {}).get(pet_id, {}).get(stage, {}).get(branch, {})
		if f.is_empty():
			push_warning("Project P: no %s %s form for '%s' in evolution.json" % [stage, branch, pet_id])
		else:
			out["id"] = f.get("id", "")
			out["name"] = f.get("name", out["name"])
			out["animal"] = f.get("animal", "")
	return out

# The form a pet with these stats and level would have, without saving anything.
# Used for practice opponents and previews.
static func form_from_stats(pet_id: String, stats: Dictionary, level: int, trial_won := false) -> Dictionary:
	var stage := stage_for(level, trial_won)
	return form_for(pet_id, stage, branch_for(stats, stage))

# ===== SECTION 3: THE PET'S FORM (SAVED) =============================================
# The pet's current form, as saved when it last evolved.
static func current(pet_id: String) -> Dictionary:
	var cfg := _load()
	var sec := _section(pet_id)
	var stage: String = cfg.get_value(sec, "evo_stage", "")
	if stage == "":
		# Never checked yet: work out the stage from the level (keeps old saves working).
		var lvl := PetStats.get_level(pet_id)
		stage = stage_for(lvl, bool(cfg.get_value(sec, "trial_won", false)))
		return form_for(pet_id, stage, branch_for(PetStats.get_stats(pet_id), stage))
	return form_for(pet_id, stage, cfg.get_value(sec, "evo_branch", ""))

# [LOGIC] Call after the level changes or the Trial is won. If the level (and Trial)
#         now allow a later stage than the saved one, the pet evolves: the branch is
#         worked out from its stats right now and saved. A pet never goes back a stage.
# Returns {"evolved": false, "to": current form} or {"evolved": true, "from": ..., "to": ...}.
static func check(pet_id: String) -> Dictionary:
	var cfg := _load()
	var sec := _section(pet_id)
	var before := current(pet_id)
	var saved: String = cfg.get_value(sec, "evo_stage", "")
	var target := stage_for(PetStats.get_level(pet_id), bool(cfg.get_value(sec, "trial_won", false)))
	if saved != "" and STAGES.find(target) <= STAGES.find(saved):
		return {"evolved": false, "to": before}
	var branch := branch_for(PetStats.get_stats(pet_id), target)
	cfg.set_value(sec, "evo_stage", target)
	cfg.set_value(sec, "evo_branch", branch)
	cfg.save(PetStats.SAVE_PATH)
	var after := form_for(pet_id, target, branch)
	var evolved: bool = saved != "" and after.stage != before.stage
	if evolved:
		print("Project P: %s evolved into %s (%s %s)." % [pet_id, after.name, after.stage, after.branch])
	return {"evolved": evolved, "from": before, "to": after}

# The form the pet is heading for, from preview_levels_before levels before Adult or
# Final ({} when no evolution is near). Includes "shares" so the app can show the stat
# mix and players can still steer the branch through what they train.
static func preview(pet_id: String) -> Dictionary:
	var lvl := PetStats.get_level(pet_id)
	var stages: Dictionary = _data().get("stages", {})
	var before := int(_data().get("preview_levels_before", 3))
	var now: String = current(pet_id).stage
	for next in ["adult", "final"]:
		var at := int(stages.get(next, 99))
		if STAGES.find(now) < STAGES.find(next) and lvl >= at - before:
			var stats := PetStats.get_stats(pet_id)
			var f := form_for(pet_id, next, branch_for(stats, next))
			f["shares"] = shares(stats)
			f["at_level"] = at
			return f
	return {}

# Marks the Trial battle as won (needed for Final), then checks for evolution.
static func win_trial(pet_id: String) -> Dictionary:
	var cfg := _load()
	cfg.set_value(_section(pet_id), "trial_won", true)
	cfg.save(PetStats.SAVE_PATH)
	return check(pet_id)

# ===== SECTION 4: BATTLE AND ART =====================================================
# [LOGIC] Trained stats plus the stage's flat bonus (stage_bonus in evolution.json).
static func battle_stats(pet_id: String, stats := {}, stage := "") -> Dictionary:
	var base: Dictionary = stats if not stats.is_empty() else PetStats.get_stats(pet_id)
	var st: String = stage if stage != "" else current(pet_id).stage
	var bonus := int(_data().get("stage_bonus", {}).get(st, 0))
	var out := {}
	for s in base:
		out[s] = int(base[s]) + bonus
	return out

# The folder with this form's frames, or base_folder when the form has none yet.
# battle = true -> the form's battle folder's parent is returned the same way, so
# BattleFighter.setup(...) can add "battle" to it as usual.
# [FIX] Form art not showing: the folder must be <pet folder>/forms/<form id>/ with the
#       form id from evolution.json (e.g. res://pets/nocti/forms/runeowl/).
static func art_folder(pet_id: String, base_folder: String, battle := false, form_id := "") -> String:
	var fid: String = form_id if form_id != "" else str(current(pet_id).id)
	if fid == "":
		return base_folder
	var folder := base_folder.path_join(FORMS_FOLDER).path_join(fid)
	if _has_png(folder.path_join("battle") if battle else folder):
		return folder
	return base_folder

static func _has_png(folder: String) -> bool:
	var dir := DirAccess.open(folder)
	if dir == null:
		return false
	for f in dir.get_files():
		if f.trim_suffix(".import").trim_suffix(".remap").get_extension().to_lower() == "png":
			return true
	return false

# ===== SECTION 5: SAVING =============================================================
# Saved next to the pet's stats in user://pet.cfg, section "stats_<pet id>":
# evo_stage, evo_branch, trial_won.
static func _section(pet_id: String) -> String:
	return "stats_" + pet_id

static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PetStats.SAVE_PATH)
	return cfg

static func _data() -> Dictionary:
	return GameDataLoader.shared().evolution
