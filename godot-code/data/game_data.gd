# =====================================================================================
# game_data.gd  -  ALL GAME DATA (pets, skills, elements, balance numbers)
# =====================================================================================
# What this file does:
#   Reads the JSON files in res://data/ once and hands their contents to the rest of
#   the game: the battle simulator, the battle screen, training and the pet grid.
#   Change numbers in the JSON files, not here.
#
# Where it goes:
#   It is an autoload called "GameData" (Project > Project Settings > Globals), so any
#   script can write GameData.pet("nocti") or GameData.skill("gale_fist").
#   Scripts that run without the game (tests, the balance runner) use
#   GameDataLoader.shared() instead - it is the same data.
#
# How to find things:
#   [EDIT]  = a setting you can safely change
#   [LOGIC] = what leads to what
#   [FIX]   = places to look first if something goes wrong
#
# Sections in this file:
#   1. Settings                                      -> search "SECTION 1"
#   2. Loading                                       -> search "SECTION 2"
#   3. Looking things up                             -> search "SECTION 3"
#   4. Checking the data                             -> search "SECTION 4"
# =====================================================================================

class_name GameDataLoader
extends Node

# ===== SECTION 1: SETTINGS ===========================================================
# [EDIT] Where the data files are.
const DATA_FOLDER := "res://data"
const FILES := ["balance", "pets", "skills", "elements", "status_effects", "activities", "evolution"]

# Filled in by load_all(): file name -> its contents (keys starting with "_" removed).
var balance: Dictionary = {}
var pets: Dictionary = {}
var skills: Dictionary = {}
var elements: Dictionary = {}
var status_effects: Dictionary = {}
var activities: Dictionary = {}
var evolution: Dictionary = {}

# [LOGIC] The battle screen reads this to know who fights. The main menu's Dojo button
#         fills it in: {"player": "<pet id>", "opponent": "<pet id or empty>"}.
var battle_request: Dictionary = {}

static var _shared: GameDataLoader = null

# ===== SECTION 2: LOADING ============================================================
func _ready() -> void:
	load_all()
	_shared = self

# The same data for scripts that run outside the game (tests, balance runner).
static func shared() -> GameDataLoader:
	if _shared == null:
		_shared = GameDataLoader.new()
		_shared.load_all()
	return _shared

# [FIX] "Project P: data file ... could not be read": a comma or bracket is missing in
#       that JSON file. Paste it into any JSON checker to find the line.
func load_all() -> void:
	for f in FILES:
		var path := DATA_FOLDER.path_join(f + ".json")
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Project P: data file %s could not be read (JSON error)." % path)
			parsed = {}
		var clean := {}
		for key in parsed:
			if not str(key).begins_with("_"):     # "_about" is a note for people
				clean[key] = parsed[key]
		set(f, clean)
	var problems := check()
	for p in problems:
		push_warning("Project P data: " + p)
	print("Project P: game data loaded - %d pets, %d skills%s." % [pets.size(), skills.size(),
		"" if problems.is_empty() else ", %d problems (see warnings)" % problems.size()])

# Frees the shared copy made by shared() (tests and the balance runner call this
# before quitting, so Godot doesn't report leaked memory).
static func release_shared() -> void:
	if _shared != null and not _shared.is_inside_tree():
		_shared.free()
	_shared = null

# ===== SECTION 3: LOOKING THINGS UP ==================================================
func pet(id: String) -> Dictionary:
	return pets.get(id, {})

func skill(id: String) -> Dictionary:
	return skills.get(id, {})

func element_color(element: String) -> Color:
	return Color(elements.get(element, {}).get("color", "#d8d2c8"))

func element_light(element: String) -> Color:
	return Color(elements.get(element, {}).get("light", "#f4f0ea"))

# [LOGIC] Element multiplier of an attack of `attack` on a pet whose element is
#         `defend`: x1.25 strong, x0.8 weak, x1 otherwise (balance.json).
func element_multiplier(attack: String, defend: String) -> float:
	if elements.get(attack, {}).get("strong_against", []).has(defend):
		return float(balance.get("element_strong", 1.25))
	if elements.get(defend, {}).get("strong_against", []).has(attack):
		return float(balance.get("element_weak", 0.8))
	return 1.0

# ===== SECTION 4: CHECKING THE DATA ==================================================
# Returns a list of problems (empty = all good): skills a pet uses that don't exist,
# unknown elements or statuses. Printed as warnings when the game starts.
func check() -> Array:
	var problems := []
	for id in pets:
		var p: Dictionary = pets[id]
		if not elements.has(p.get("element", "")):
			problems.append("%s: unknown element '%s'" % [id, p.get("element", "")])
		for s in p.get("skills", []) + [p.get("ultimate", "")]:
			if not skills.has(s):
				problems.append("%s: skill '%s' is not in skills.json" % [id, s])
	for sid in skills:
		var s: Dictionary = skills[sid]
		var el: String = s.get("element", "none")
		if el != "none" and not elements.has(el):
			problems.append("skill %s: unknown element '%s'" % [sid, el])
		for e in s.get("effects", []):
			if e.get("op", "") == "status" and not status_effects.has(e.get("status", "")):
				problems.append("skill %s: unknown status '%s'" % [sid, e.get("status", "")])
	# Evolution: every pet has 4 Adult and 7 Final forms, each with an id and a name
	var forms: Dictionary = evolution.get("forms", {})
	for id in pets:
		var f: Dictionary = forms.get(id, {})
		for branch in ["Martial", "Arcane", "Swift", "Harmony"]:
			if not f.get("adult", {}).get(branch, {}).has("id"):
				problems.append("%s: no Adult %s form in evolution.json" % [id, branch])
		for branch in ["Martial", "Arcane", "Swift", "Martial-Arcane", "Martial-Swift", "Arcane-Swift", "Harmony"]:
			if not f.get("final", {}).get(branch, {}).has("id"):
				problems.append("%s: no Final %s form in evolution.json" % [id, branch])
	return problems
