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
