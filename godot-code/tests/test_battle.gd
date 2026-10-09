# =====================================================================================
# test_battle.gd  -  QUICK CHECKS FOR THE BATTLE RULES AND DATA
# =====================================================================================
# Run from a terminal in the godot-code folder:
#   godot --headless -s res://tests/test_battle.gd
# It prints PASS or FAIL for each check and ends with a summary. Exit code 0 = all good.
# Run it after changing any JSON file in res://data/ or battle_sim.gd.
# =====================================================================================

extends SceneTree

var _fails := 0
var _passes := 0

func _initialize() -> void:
	var db := GameDataLoader.shared()

	_check("data has 12 pets", db.pets.size() == 12, "found %d" % db.pets.size())
	var problems := db.check()
	_check("every pet's skills, elements and statuses exist", problems.is_empty(), str(problems))

	# Every pet can fight every other pet without errors, and the fight ends
	var ids := db.pets.keys()
	var bad_fights := []
	var max_rounds := int(db.balance.get("battle", {}).get("max_rounds", 30))
	for a in ids:
		for b in ids:
			var r := BattleSim.new().run(BattleSim.make_snapshot(a, BattleSim.sample_stats(a)),
				BattleSim.make_snapshot(b, BattleSim.sample_stats(b)), 7)
			if not (r.winner in [0, 1]) or r.rounds > max_rounds or r.events.is_empty():
				bad_fights.append("%s vs %s" % [a, b])
			for ev in r.events:
				if ev.hp[0] < 0 or ev.hp[1] < 0:
					bad_fights.append("%s vs %s: HP below 0" % [a, b])
					break
	_check("all 144 pairings finish with a winner", bad_fights.is_empty(), str(bad_fights.slice(0, 5)))

	# Same seed -> exactly the same fight (needed for replays and the server)
	var s1 := BattleSim.make_snapshot("gym_wolf", BattleSim.sample_stats("gym_wolf"))
	var s2 := BattleSim.make_snapshot("moonstep", BattleSim.sample_stats("moonstep"))
	var r1 := BattleSim.new().run(s1, s2, 12345)
	var r2 := BattleSim.new().run(s1, s2, 12345)
	_check("same seed gives the same fight", JSON.stringify(r1.events) == JSON.stringify(r2.events))
	var r3 := BattleSim.new().run(s1, s2, 999)
	_check("a different seed gives a different fight", JSON.stringify(r1.events) != JSON.stringify(r3.events))

	# Mastery breakpoints change skills
	var weak := BattleSim.make_snapshot("gym_wolf", {"str": 100})
	var strong := BattleSim.make_snapshot("gym_wolf", {"str": 160})
	_check("Gale Fist gains its second hit at STR 150",
		not _skill(weak, "gale_fist").has("extra_hit") and _skill(strong, "gale_fist").has("extra_hit"))

	# Fights last a sensible time (balance target: 8-15 turns, see the concept doc)
	var turns := []
	for k in 50:
		var a: String = ids[k % ids.size()]
		var b: String = ids[(k * 5 + 3) % ids.size()]
		var r := BattleSim.new().run(BattleSim.make_snapshot(a, BattleSim.sample_stats(a)),
			BattleSim.make_snapshot(b, BattleSim.sample_stats(b)), k)
		turns.append(r.rounds)
	turns.sort()
	var median: int = turns[turns.size() / 2]
	_check("median fight length 4-20 rounds", median >= 4 and median <= 20, "median %d rounds" % median)

	# Training: flat Training Points, rising cost, daily cap
	_check("point cost rises with the stat", PetStats.point_cost(10) < PetStats.point_cost(150))

	# Evolution: stages, branches and forms (evolution.gd, evolution.json)
	_check("stage from level", Evolution.stage_for(5) == "baby" and Evolution.stage_for(10) == "child"
		and Evolution.stage_for(25) == "adult" and Evolution.stage_for(50) == "adult"
		and Evolution.stage_for(50, true) == "final")
	var cases := [
		[{"str": 60, "int": 20, "agi": 20}, "adult", "Martial"],
		[{"str": 20, "int": 60, "agi": 20}, "adult", "Arcane"],
		[{"str": 20, "int": 20, "agi": 60}, "final", "Swift"],
		[{"str": 34, "int": 33, "agi": 33}, "adult", "Harmony"],
		[{"str": 34, "int": 33, "agi": 33}, "final", "Harmony"],
		[{"str": 45, "int": 42, "agi": 13}, "final", "Martial-Arcane"],
		[{"str": 13, "int": 42, "agi": 45}, "final", "Arcane-Swift"],
		[{"str": 45, "int": 10, "agi": 45}, "final", "Martial-Swift"],
		[{"str": 45, "int": 42, "agi": 13}, "adult", "Martial"],
		[{"str": 50, "int": 50, "agi": 50}, "child", ""],
	]
	var wrong := []
	for c in cases:
		var got := Evolution.branch_for(c[0], c[1])
		if got != c[2]:
			wrong.append("%s %s -> %s (expected %s)" % [c[0], c[1], got, c[2]])
	_check("branch from STR / INT / AGI share", wrong.is_empty(), str(wrong))
	var form_ids := {}
	var missing := []
	for id in ids:
		for stage_branches in [["adult", ["Martial", "Arcane", "Swift", "Harmony"]],
				["final", ["Martial", "Arcane", "Swift", "Martial-Arcane", "Martial-Swift", "Arcane-Swift", "Harmony"]]]:
			for br in stage_branches[1]:
				var f := Evolution.form_for(id, stage_branches[0], br)
				if f.id == "" or form_ids.has("%s/%s" % [id, f.id]):
					missing.append("%s %s %s" % [id, stage_branches[0], br])
				form_ids["%s/%s" % [id, f.id]] = true
	_check("all 132 forms exist with unique ids", missing.is_empty() and form_ids.size() == 132, str(missing))
	_check("Gym Wolf Martial goes chow chow -> Tibetan mastiff",
		Evolution.form_for("gym_wolf", "adult", "Martial").animal == "Chow chow"
		and Evolution.form_for("gym_wolf", "final", "Martial").animal == "Tibetan mastiff")
	var boosted := Evolution.battle_stats("nocti", {"str": 10, "int": 10, "agi": 10, "vit": 10, "spi": 10}, "final")
	_check("Final stage adds its stat bonus", boosted.str > 10 and boosted.spi == boosted.str)
	_check("a form without art uses the pet's own frames",
		Evolution.art_folder("nocti", "res://pets/nocti", false, "runeowl") == "res://pets/nocti")

	print("\n%d passed, %d failed" % [_passes, _fails])
	GameDataLoader.release_shared()
	quit(1 if _fails > 0 else 0)

func _skill(snap: Dictionary, id: String) -> Dictionary:
	for s in snap.skills:
		if s.get("id", "") == id:
			return s
	return {}

func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		_passes += 1
		print("PASS  " + name)
	else:
		_fails += 1
		print("FAIL  " + name + ("  (" + detail + ")" if detail != "" else ""))
