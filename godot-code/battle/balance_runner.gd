# =====================================================================================
# balance_runner.gd  -  FIGHTS EVERY PET AGAINST EVERY PET, MANY TIMES
# =====================================================================================
# Run from a terminal in the godot-code folder:
#   godot --headless -s res://battle/balance_runner.gd
#   godot --headless -s res://battle/balance_runner.gd -- --fights 500 --total 300
# Options (after the --):
#   --fights N   fights per pairing (default 200, half with each pet moving first)
#   --total N    stat points per pet, shared 40% favoured / 15% each other (default 200)
#   --level N    level of both pets (default 10)
# Writes user://balance_report.csv (Project > Open User Data Folder) and prints each
# pet's overall win rate. Target: every pet between 40% and 60% at equal stats.
# =====================================================================================

extends SceneTree

func _initialize() -> void:
	var args := _args()
	var fights := int(args.get("fights", 200))
	var total := int(args.get("total", 200))
	var level := int(args.get("level", 10))
	var db := GameDataLoader.shared()
	var ids: Array = db.pets.keys()
	var wins := {}
	var games := {}
	var rounds_all := []
	var lines := PackedStringArray(["pet,opponent,win_rate,avg_rounds"])
	var started := Time.get_ticks_msec()
	for a in ids:
		wins[a] = 0
		games[a] = 0
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var sa := BattleSim.make_snapshot(a, BattleSim.sample_stats(a, total), level)
			var sb := BattleSim.make_snapshot(b, BattleSim.sample_stats(b, total), level)
			var w := 0
			var r_sum := 0
			for k in fights:
				# Alternate sides so neither pet always gets the coin flip
				var a_first := k % 2 == 0
				var r := BattleSim.new().run(sa if a_first else sb, sb if a_first else sa, k * 7919 + 1)
				var a_won: bool = (r.winner == 0) == a_first
				if a_won:
					w += 1
				r_sum += r.rounds
				rounds_all.append(r.rounds)
			wins[a] += w
			games[a] += fights
			lines.append("%s,%s,%.3f,%.1f" % [a, b, float(w) / fights, float(r_sum) / fights])
	var path := "user://balance_report.csv"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
	rounds_all.sort()
	print("\nWin rate at equal stats (%d stat points, level %d, %d fights per pairing):" % [total, level, fights])
	var sorted_ids := ids.duplicate()
	sorted_ids.sort_custom(func(x, y): return float(wins[x]) / games[x] > float(wins[y]) / games[y])
	for id in sorted_ids:
		var rate: float = float(wins[id]) / games[id]
		var flag := "" if rate >= 0.4 and rate <= 0.6 else "   <- outside 40-60%"
		print("  %-10s %5.1f%%%s" % [id, rate * 100.0, flag])
	print("Median fight length: %d rounds. Report: %s (%s). Took %.1f s." % [
		rounds_all[rounds_all.size() / 2], path, ProjectSettings.globalize_path(path),
		(Time.get_ticks_msec() - started) / 1000.0])
	GameDataLoader.release_shared()
	quit()

func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].trim_prefix("--")] = a[i + 1]
	return out
