# =====================================================================================
# battle_sim.gd  -  THE BATTLE ITSELF (no pictures, no sound - just the rules)
# =====================================================================================
# What this file does:
#   Decides a whole fight between two pets before anything is shown, Pockie Ninja style:
#     two pet snapshots (stats, skills, element) + a seed number  ->  a list of events
#     ("turn 3: Moonstep uses Moon Claw, 240 damage, critical", ...) and the winner.
#   The battle screen (battle_screen.gd) only plays that list back as animation. The
#   same seed and snapshots always give exactly the same fight, so a fight can be
#   replayed, tested thousands of times (balance_runner.gd) and checked by a server.
#
# How to use it:
#   var a := BattleSim.make_snapshot("gym_wolf", PetStats.get_stats("gym_wolf"))
#   var b := BattleSim.make_snapshot("moonstep", {...})
#   var result := BattleSim.new().run(a, b, 12345)
#   result.winner (0 or 1), result.events (Array), result.rounds
#
# All numbers come from res://data/balance.json and skills.json.
#
# How to find things:
#   [EDIT]  = a setting you can safely change
#   [LOGIC] = rules of the fight (what leads to what)
#   [FIX]   = places to look first if something goes wrong
#
# Sections in this file:
#   1. Snapshots (a pet ready to fight)              -> search "SECTION 1"
#   2. The fight: rounds and turns                   -> search "SECTION 2"
#   3. Choosing a skill (the pet's tactics)          -> search "SECTION 3"
#   4. Attacks and damage                            -> search "SECTION 4"
#   5. Skill effects (status, heal, shield ...)      -> search "SECTION 5"
#   6. Combat stats (HP, dodge, block, crit ...)     -> search "SECTION 6"
#   7. Passives                                      -> search "SECTION 7"
#   8. Helpers                                       -> search "SECTION 8"
#
# Event format (what the battle screen reads):
#   {"turn": 4, "round": 2, "actor": 0, "kind": "skill" | "ultimate" | "basic" | "skip"
#    | "tick" | "regen", "skill": id, "name": "Gale Fist", "element": "wind",
#    "template": "melee", "type": "physical",
#    "steps": [ {"kind": "hit", "target": 1, "dmg": 180, "crit": true, "blocked": false,
#                "dodged": false, "absorbed": 0}, {"kind": "status", "target": 1,
#                "status": "burn", "landed": true}, {"kind": "heal", ...}, ... ],
#    "hp": [a, b], "mana": [a, b], "spirit": [a, b], "shield": [a, b],
#    "statuses": [["burn"], []]}
# =====================================================================================

class_name BattleSim
extends RefCounted

const DEBUFFS := ["burn", "cut", "mark", "silence", "stun", "sleep"]

var _db: GameDataLoader
var _b: Dictionary                 # balance.json
var _rng := RandomNumberGenerator.new()
var _f: Array = []                 # the two fighters (Dictionaries, see _fighter())
var _events: Array = []
var _turn := 0
var _round := 0

# ===== SECTION 1: SNAPSHOTS ==========================================================
# A pet ready to fight: who it is, its stats and level, and its skills with mastery
# already applied. Snapshots are plain data, so they can be saved and sent to a server
# for multiplayer (the other player's pet fights as its last snapshot).
# element = "" uses the pet's suggested element from pets.json.
# skills = [] uses the pet's default loadout (pets.json), in priority order.
static func make_snapshot(pet_id: String, stats: Dictionary, level := 10, element := "",
		skills: Array = []) -> Dictionary:
	var db := GameDataLoader.shared()
	var p := db.pet(pet_id)
	if p.is_empty():
		push_error("Project P: pet '%s' is not in pets.json" % pet_id)
		return {}
	var full := {}
	for s in PetStats.STATS:
		full[s] = int(stats.get(s, 10))
	var loadout: Array = skills if not skills.is_empty() else p.get("skills", [])
	var resolved := []
	for sid in loadout:
		resolved.append(_resolve_skill(sid, full))
	return {
		"pet_id": pet_id, "name": p.get("name", pet_id), "level": level,
		"element": element if element != "" else p.get("element", "none"),
		"stats": full, "skills": resolved,
		"ultimate": _resolve_skill(p.get("ultimate", ""), full),
		"passive": p.get("passive", {}).duplicate(true),
	}

# [LOGIC] A skill with its mastery breakpoints applied: when the pet's stat reaches
#         "at", the fields in "mods" replace the skill's own (skills.json).
static func _resolve_skill(skill_id: String, stats: Dictionary) -> Dictionary:
	var s: Dictionary = GameDataLoader.shared().skill(skill_id).duplicate(true)
	if s.is_empty():
		return {}
	s["id"] = skill_id
	for m in s.get("mastery", []):
		if int(stats.get(m.get("stat", ""), 0)) >= int(m.get("at", 99999)):
			for key in m.get("mods", {}):
				s[key] = m["mods"][key]
	return s

# A pet with sample stats for tests and practice fights: `total` points shared out,
# 40% to its favoured stat and 15% to each of the other four.
static func sample_stats(pet_id: String, total := 200) -> Dictionary:
	var fav: String = GameDataLoader.shared().pet(pet_id).get("favoured", "str")
	var out := {}
	for s in PetStats.STATS:
		out[s] = int(round(total * (0.40 if s == fav else 0.15)))
	return out

# ===== SECTION 2: THE FIGHT ==========================================================
# [LOGIC] Each round both pets act once, the faster first (Speed = AGI + 2 x level).
#         A pet that is knocked out ends the fight. After max_rounds (balance.json) the
#         pet with the larger share of its HP left wins.
func run(a: Dictionary, b: Dictionary, seed_value: int) -> Dictionary:
	_db = GameDataLoader.shared()
	_b = _db.balance
	_rng.seed = seed_value
	_f = [_fighter(a), _fighter(b)]
	_events = []
	_turn = 0
	_round = 0
	for i in 2:
		_on_battle_start(i)
	var max_rounds := int(_b.get("battle", {}).get("max_rounds", 30))
	var winner := -1
	var reason := "timeout"
	while _round < max_rounds and winner < 0:
		_round += 1
		for i in _turn_order():
			if _alive(0) and _alive(1):
				_take_turn(i, 1 - i)
		for i in 2:
			_f[i]["speed_bonus"] = _f[i].get("next_speed_bonus", 0)
			_f[i]["next_speed_bonus"] = 0
		if not _alive(0) or not _alive(1):
			reason = "ko"
			winner = 0 if _alive(0) else 1
	if winner < 0:
		var share0: float = float(_f[0]["hp"]) / _f[0]["max_hp"]
		var share1: float = float(_f[1]["hp"]) / _f[1]["max_hp"]
		winner = 0 if share0 > share1 else (1 if share1 > share0 else _rng.randi_range(0, 1))
	return {
		"winner": winner, "reason": reason, "rounds": _round, "seed": seed_value,
		"events": _events,
		"fighters": [_summary(0), _summary(1)],
	}

func _turn_order() -> Array:
	var s0 := _speed(0)
	var s1 := _speed(1)
	if _round == 1:                                     # First Light passive
		var f0 := _passive_kind(0) == "first_turn"
		var f1 := _passive_kind(1) == "first_turn"
		if f0 != f1:
			return [0, 1] if f0 else [1, 0]
	if s0 == s1:
		return [0, 1] if _rng.randf() < 0.5 else [1, 0]
	return [0, 1] if s0 > s1 else [1, 0]

# [LOGIC] One pet's turn: start-of-turn effects (burn, regen), Mana regen, then either
#         it is stunned / asleep, or it uses its ultimate (Spirit 100), a skill, or a
#         basic attack. Cooldowns and status timers count down at the end of its turn.
func _take_turn(i: int, j: int) -> void:
	_turn += 1
	var me: Dictionary = _f[i]
	me["turns_taken"] = int(me.get("turns_taken", 0)) + 1
	_start_of_turn(i)
	if not _alive(i):
		return
	me["mana"] = mini(me["max_mana"], me["mana"] + int(round(_mana_regen(i))))
	_gain_spirit(i, float(_b.get("spirit", {}).get("per_turn", 5)))
	# Stunned or asleep: the turn is lost (and it can't be stunned again next turn)
	for st in ["stun", "sleep"]:
		if me["statuses"].has(st):
			me["statuses"].erase(st)
			me["just_skipped"] = true
			_push({"actor": i, "kind": "skip", "name": _db.status_effects.get(st, {}).get("name", st),
				"status": st, "steps": []})
			_end_of_turn(i)
			return
	me["just_skipped"] = false
	var ev := {}
	if me["spirit"] >= float(_b.get("spirit", {}).get("max", 100)) and _can_use_skills(i) \
			and not me["ultimate"].is_empty():
		me["spirit"] = 0.0
		ev = _use_skill(i, j, me["ultimate"], "ultimate")
	else:
		var pick := _choose_skill(i, j)
		if pick.is_empty():
			ev = _use_skill(i, j, _basic_attack(), "basic")
		else:
			ev = _use_skill(i, j, pick, "skill")
	_push(ev)
	_end_of_turn(i)

func _start_of_turn(i: int) -> void:
	var me: Dictionary = _f[i]
	var steps := []
	_passive_turn_start(i, steps)
	if me["statuses"].has("burn"):
		var burn: Dictionary = me["statuses"]["burn"]
		var dmg := int(burn.get("power", 10))
		var after := []
		_apply_damage(i, dmg, after, false, "burn", -1)
		steps.append({"kind": "hit", "target": i, "dmg": dmg, "source": "burn"})
		steps.append_array(after)
	if not steps.is_empty():
		_push({"actor": i, "kind": "tick", "name": "", "steps": steps})

func _end_of_turn(i: int) -> void:
	var me: Dictionary = _f[i]
	for sid in me["cooldowns"].keys():
		me["cooldowns"][sid] = maxi(0, me["cooldowns"][sid] - 1)
	for st in me["statuses"].keys():
		var e: Dictionary = me["statuses"][st]
		e["turns"] = int(e.get("turns", 1)) - 1
		if e["turns"] <= 0:
			me["statuses"].erase(st)
	var keep := []
	for buff in me["buffs"]:
		buff["turns"] -= 1
		if buff["turns"] > 0:
			keep.append(buff)
	me["buffs"] = keep
	if me["counter"].size() > 0:
		me["counter"]["turns"] = int(me["counter"]["turns"]) - 1
		if me["counter"]["turns"] <= 0:
			me["counter"] = {}

# ===== SECTION 3: CHOOSING A SKILL ===================================================
# [LOGIC] The pet's tactics: it goes down its skill list in order and uses the first
#         skill that is off cooldown, affordable and makes sense right now:
#           heal only below 60% HP, shield / evade / counter / buff only when not
#           already active, a status-only skill only if the enemy doesn't have it yet.
#         Nothing fits -> basic attack (free). Later, players set their own rules.
func _choose_skill(i: int, j: int) -> Dictionary:
	if not _can_use_skills(i):
		return {}
	var me: Dictionary = _f[i]
	for s in me["skills"]:
		if s.is_empty() or int(me["cooldowns"].get(s["id"], 0)) > 0:
			continue
		if _cost(i, s) > me["mana"]:
			continue
		if _makes_sense(i, j, s):
			return s
	return {}

func _makes_sense(i: int, j: int, s: Dictionary) -> bool:
	var me: Dictionary = _f[i]
	var enemy: Dictionary = _f[j]
	var deals_damage := s.has("scaling")
	for e in s.get("effects", []):
		match e.get("op", ""):
			"heal":
				if not deals_damage and float(me["hp"]) / me["max_hp"] > 0.6:
					return false
			"shield":
				if not deals_damage and me["shield"] > 0:
					return false
			"evade":
				if int(me["evade"].get("count", 0)) > 0:
					return false
			"counter":
				if me["counter"].size() > 0:
					return false
			"buff":
				for buff in me["buffs"]:
					if buff["stat"] == e.get("stat", ""):
						return false
			"status":
				if not deals_damage and enemy["statuses"].has(e.get("status", "")):
					return false
	return true

func _can_use_skills(i: int) -> bool:
	return not _f[i]["statuses"].has("silence")

func _cost(i: int, s: Dictionary) -> int:
	if _passive_kind(i) == "free_every":                       # Scholar passive
		var n := int(_f[i]["passive"].get("n", 3))
		if (int(_f[i].get("skills_used", 0)) + 1) % n == 0:
			return 0
	return int(s.get("cost", 0))

func _basic_attack() -> Dictionary:
	var ba: Dictionary = _b.get("basic_attack", {})
	return {"id": "basic", "name": ba.get("name", "Basic Strike"), "element": "none",
		"type": "physical", "template": "melee", "cost": 0, "cooldown": 0,
		"scaling": {"base": ba.get("base", 10), "str": ba.get("str", 0.6), "agi": ba.get("agi", 0.4)}}

# ===== SECTION 4: ATTACKS AND DAMAGE =================================================
func _use_skill(i: int, j: int, s: Dictionary, kind: String) -> Dictionary:
	var me: Dictionary = _f[i]
	var steps := []
	if kind == "skill":
		me["mana"] -= _cost(i, s)
		me["skills_used"] = int(me.get("skills_used", 0)) + 1
		if int(s.get("cooldown", 0)) > 0:
			me["cooldowns"][s["id"]] = int(s["cooldown"]) + 1   # +1: counts down at this turn's end
	var acted_first: bool = _f[j].get("last_acted_round", -1) != _round
	_passive_before_attack(i, acted_first)
	me["last_acted_round"] = _round
	if s.has("scaling"):
		var hits := int(s.get("hits", 1))
		for h in hits:
			if not _alive(j):
				break
			_attack_once(i, j, s, h, 1.0, steps)
			if s.get("per_hit_effects", false) or _has_per_hit(s):
				_run_effects(i, j, s, steps, true)
		if s.has("extra_hit") and _alive(j):                    # mastery: one more hit
			_attack_once(i, j, s, hits, float(s["extra_hit"]), steps)
		if s.has("bonus_hit_per_debuff") and _alive(j):         # Library of Stars
			var n := 0
			for st in _f[j]["statuses"]:
				if DEBUFFS.has(st):
					n += 1
			var bonus := s.duplicate(true)
			bonus["scaling"] = s["bonus_hit_per_debuff"]
			for k in n:
				if _alive(j):
					_attack_once(i, j, bonus, hits + k, 1.0, steps)
	_run_effects(i, j, s, steps, false)
	return {"actor": i, "kind": kind, "skill": s.get("id", ""), "name": s.get("name", ""),
		"element": s.get("element", "none"), "template": s.get("template", "melee"),
		"type": s.get("type", "physical"), "steps": steps}

# [LOGIC] One hit: evade (Starfall) -> dodge -> damage = (base + stat shares) x element
#         x (1 - defence) x critical x 0.95-1.05 -> block halves it -> shield absorbs ->
#         HP. Then counters and reflects. Every number is in balance.json.
func _attack_once(i: int, j: int, s: Dictionary, hit_index: int, fraction: float, steps: Array) -> void:
	var me: Dictionary = _f[i]
	var foe: Dictionary = _f[j]
	var step := {"kind": "hit", "target": j, "dmg": 0, "crit": false, "blocked": false,
		"dodged": false, "absorbed": 0}
	# Evade (Starfall): the attack misses and the defender strikes back
	if int(foe["evade"].get("count", 0)) > 0:
		foe["evade"]["count"] -= 1
		step["dodged"] = true
		step["evaded"] = true
		steps.append(step)
		var back := _after_defence(i, _raw_damage(j, foe["evade"].get("counter", {"agi": 1.0}), 0.0),
			"physical", 0.0)
		_apply_damage(i, back, steps, true, "counter", j)
		steps.append({"kind": "hit", "target": i, "dmg": back, "source": "counter"})
		return
	# Dodge
	if _rng.randf() < _dodge(j):
		step["dodged"] = true
		steps.append(step)
		if _passive_kind(j) == "dodge_speed":                  # Moonlit Reflex
			foe["next_speed_bonus"] = int(foe["passive"].get("amount", 15))
		return
	var raw := _raw_damage(i, s.get("scaling", {}), 0.0) * fraction
	# Element: strong / weak, plus the bonus for using the pet's own element
	var el: String = s.get("element", "none")
	if el != "none":
		raw *= _db.element_multiplier(el, foe["element"])
		if el == me["element"]:
			raw *= 1.0 + float(_b.get("same_element_bonus", 0.15))
	raw *= _passive_damage_mult(i, s)
	raw *= float(_b.get("damage_scale", 1.0))          # one dial for how fast fights go
	raw = _after_defence(j, raw, s.get("type", "physical"), float(s.get("guard_ignore", 0.0)))
	# Critical
	var crit_chance := _crit(i) + float(s.get("crit_bonus", 0.0)) \
		+ float(s.get("crit_bonus_per_hit", 0.0)) * hit_index
	if s.get("crit_if_marked", false) and foe["statuses"].has("mark"):
		crit_chance = 1.0
	if _rng.randf() < crit_chance:
		step["crit"] = true
		raw *= _crit_damage(i)
	var rnd: Array = _b.get("damage_random", [0.95, 1.05])
	raw *= _rng.randf_range(float(rnd[0]), float(rnd[1]))
	var dmg := maxi(1, int(round(raw)))
	# Block halves the damage (Shell Up: the first hit is always blocked)
	var blocked := false
	var physical: bool = s.get("type", "physical") == "physical"
	var can_block := physical or not bool(_b.get("block", {}).get("physical_only", false))
	if _passive_kind(j) == "first_hit_blocked" \
			and int(foe.get("shell_used", 0)) < int(foe["passive"].get("count", 1)):
		foe["shell_used"] = int(foe.get("shell_used", 0)) + 1
		blocked = true
	elif can_block and _rng.randf() < _block(j):
		blocked = true
	if blocked:
		dmg = maxi(1, int(round(dmg * float(_b.get("block", {}).get("damage_taken", 0.5)))))
		step["blocked"] = true
	step["dmg"] = dmg
	var after := []                        # what the damage set off (e.g. a shield refresh)
	step["absorbed"] = _apply_damage(j, dmg, after, s.get("pierce_shield", false), s.get("id", ""), i,
		step["crit"])
	steps.append(step)
	steps.append_array(after)
	# Iron Stance: blocking strikes back
	if blocked and foe["counter"].size() > 0 and _alive(j) and _alive(i):
		var back := _after_defence(i, _raw_damage(j, foe["counter"].get("scaling", {"str": 0.6}), 0.0),
			"physical", 0.0)
		_apply_damage(i, back, steps, false, "counter", j)
		steps.append({"kind": "hit", "target": i, "dmg": back, "source": "counter"})
		if _rng.randf() < float(foe["counter"].get("stun_chance", 0.0)):
			_add_status(i, "stun", 1, 0, steps)
	# Ink Spikes: part of physical damage comes back
	if _passive_kind(j) == "reflect_physical" and s.get("type", "") == "physical" and _alive(i):
		var back := maxi(1, int(round(dmg * float(foe["passive"].get("pct", 0.1)))))
		_apply_damage(i, back, steps, false, "reflect", j)
		steps.append({"kind": "hit", "target": i, "dmg": back, "source": "reflect"})

# base + share of each stat, e.g. {"base": 15, "str": 1.2} = 15 + 1.2 x STR
func _raw_damage(i: int, scaling: Dictionary, extra: float) -> float:
	var total := float(scaling.get("base", 0)) + extra
	for st in PetStats.STATS:
		total += float(scaling.get(st, 0.0)) * _stat(i, st)
	return total

# Guard cuts physical damage, Ward cuts arcane: defence / (defence + 300).
func _after_defence(j: int, raw: float, type: String, ignore: float) -> int:
	var d := _guard(j) if type == "physical" else _ward(j)
	d *= 1.0 - ignore
	var k := float(_b.get("defense_k", 300))
	return maxi(1, int(round(raw * (1.0 - d / (d + k)))))

# Takes damage off the shield first, then HP. Returns how much the shield absorbed.
func _apply_damage(j: int, dmg: int, steps: Array, pierce: bool, source: String, by: int,
		crit := false) -> int:
	var t: Dictionary = _f[j]
	var absorbed := 0
	if not pierce and t["shield"] > 0:
		absorbed = mini(t["shield"], dmg)
		t["shield"] -= absorbed
	var to_hp := dmg - absorbed
	t["hp"] = maxi(0, t["hp"] - to_hp)
	if to_hp > 0 and t["statuses"].has("sleep"):            # Sleep breaks when hit
		t["statuses"].erase("sleep")
	var sp: Dictionary = _b.get("spirit", {})
	_gain_spirit(j, float(sp.get("per_damage_taken", 100)) * to_hp / t["max_hp"])
	if by >= 0:
		_gain_spirit(by, float(sp.get("per_damage_dealt", 50)) * to_hp / t["max_hp"])
	if crit and _passive_kind(j) == "arcane_stacks":         # Deep Focus resets on a crit
		t["stacks"] = 0
	_passive_after_damage(j, steps)
	return absorbed

# ===== SECTION 5: SKILL EFFECTS ======================================================
func _has_per_hit(s: Dictionary) -> bool:
	for e in s.get("effects", []):
		if e.get("per_hit", false):
			return true
	return false

# Runs the skill's effects in order. per_hit = true runs only the effects marked
# "per_hit" (after each hit); false runs the others (once, after all hits).
func _run_effects(i: int, j: int, s: Dictionary, steps: Array, per_hit: bool) -> void:
	var me: Dictionary = _f[i]
	for e in s.get("effects", []):
		if bool(e.get("per_hit", false)) != per_hit:
			continue
		match e.get("op", ""):
			"status":
				if not _alive(j):
					continue
				var power := int(round(_raw_damage(i, e.get("power", {}), 0.0)))
				_try_status(i, j, e.get("status", ""), float(e.get("chance", 1.0)),
					int(e.get("turns", 1)), power, steps)
			"heal":
				var amount: float = float(e.get("pct_max_hp", 0.0)) * me["max_hp"] \
					+ _raw_damage(i, e.get("scaling", {}), 0.0)
				var healed := mini(me["max_hp"] - me["hp"], int(round(amount)))
				me["hp"] += healed
				steps.append({"kind": "heal", "target": i, "amount": healed})
			"shield":
				var amount: float = float(e.get("pct_max_hp", 0.0)) * me["max_hp"] \
					+ float(e.get("pct_max_mana", 0.0)) * me["max_mana"] \
					+ _raw_damage(i, e.get("scaling", {}), 0.0)
				me["shield"] = maxi(me["shield"], int(round(amount)))
				steps.append({"kind": "shield", "target": i, "amount": me["shield"]})
			"buff":
				me["buffs"].append({"stat": e.get("stat", ""), "amount": float(e.get("amount", 0.1)),
					"turns": int(e.get("turns", 2)) + 1})
				steps.append({"kind": "buff", "target": i, "stat": e.get("stat", ""),
					"amount": e.get("amount", 0.1)})
			"counter":
				me["counter"] = {"turns": int(e.get("turns", 2)) + 1,
					"scaling": e.get("scaling", {"str": 0.6}), "stun_chance": e.get("stun_chance", 0.0)}
				steps.append({"kind": "counter_ready", "target": i})
			"evade":
				me["evade"] = {"count": int(e.get("count", 1)), "counter": e.get("counter", {"agi": 1.0})}
				steps.append({"kind": "evade_ready", "target": i})
			"mana_steal":
				var took := mini(_f[j]["mana"], int(e.get("amount", 20)))
				_f[j]["mana"] -= took
				me["mana"] = mini(me["max_mana"], me["mana"] + took)
				steps.append({"kind": "mana_steal", "target": j, "amount": took})
			"cleanse":
				var removed := []
				for st in me["statuses"].keys():
					if DEBUFFS.has(st) and removed.size() < int(e.get("count", 1)):
						me["statuses"].erase(st)
						removed.append(st)
				steps.append({"kind": "cleanse", "target": i, "removed": removed})

# [LOGIC] Chance to land = skill chance + (attacker INT - target VIT) x 0.001, kept
#         between 5% and 95% (balance.json). Statuses nobody resists (mark) always land
#         at the skill's own chance.
func _try_status(i: int, j: int, status: String, chance: float, turns: int, power: int,
		steps: Array) -> void:
	var info: Dictionary = _db.status_effects.get(status, {})
	var resist: String = info.get("resisted_by", "")
	var c := chance
	if resist != "":
		c += (_stat(i, "int") - _stat(j, resist)) * float(_b.get("status_chance_per_point", 0.001))
		c = clampf(c, float(_b.get("status_chance_min", 0.05)), float(_b.get("status_chance_max", 0.95)))
		if chance >= 1.0:
			c = 1.0
	var landed := _rng.randf() < c
	if landed:
		landed = _add_status(j, status, turns, power, steps)
	else:
		steps.append({"kind": "status", "target": j, "status": status, "landed": false})

func _add_status(j: int, status: String, turns: int, power: int, steps: Array) -> bool:
	var t: Dictionary = _f[j]
	var info: Dictionary = _db.status_effects.get(status, {})
	# Unbothered: the first debuff is ignored and fills Spirit instead
	if _passive_kind(j) == "first_debuff_immune" and not t.get("immune_used", false) \
			and DEBUFFS.has(status):
		t["immune_used"] = true
		_gain_spirit(j, float(t["passive"].get("spirit_on_debuff", 15)))
		steps.append({"kind": "status", "target": j, "status": status, "landed": false, "immune": true})
		return false
	# Stun and Sleep can't hit a pet that just lost a turn to them
	if info.get("no_repeat", false) and t.get("just_skipped", false):
		steps.append({"kind": "status", "target": j, "status": status, "landed": false, "immune": true})
		return false
	var cur: Dictionary = t["statuses"].get(status, {})
	var stacks := mini(int(cur.get("stacks", 0)) + 1, int(info.get("max_stacks", 1)))
	t["statuses"][status] = {"turns": maxi(turns, int(cur.get("turns", 0))), "stacks": stacks,
		"power": maxi(power, int(cur.get("power", 0)))}
	steps.append({"kind": "status", "target": j, "status": status, "landed": true, "stacks": stacks})
	return true

# ===== SECTION 6: COMBAT STATS =======================================================
# The pet's stat right now: trained value x buffs x passives (Grit).
func _stat(i: int, st: String) -> float:
	var f: Dictionary = _f[i]
	var v := float(f["stats"].get(st, 10))
	var mult := 1.0
	for buff in f["buffs"]:
		if buff["stat"] == st:
			mult += float(buff["amount"])
	if _passive_kind(i) == "low_hp_stat" and f["passive"].get("stat", "") == st \
			and float(f["hp"]) / f["max_hp"] < float(f["passive"].get("threshold", 0.3)):
		mult += float(f["passive"].get("pct", 0.2))
	return v * mult

func _max_hp(stats: Dictionary, level: int) -> int:
	var h: Dictionary = _b.get("hp", {})
	return int(round(float(h.get("base", 400)) + float(h.get("per_vit", 12)) * stats["vit"]
		+ float(h.get("per_str", 4)) * stats["str"] + float(h.get("per_level", 20)) * level))

func _max_mana(stats: Dictionary) -> int:
	var m: Dictionary = _b.get("mana", {})
	return int(round(float(m.get("base", 100)) + float(m.get("per_spi", 4)) * stats["spi"]
		+ float(m.get("per_int", 2)) * stats["int"]))

func _mana_regen(i: int) -> float:
	var m: Dictionary = _b.get("mana_regen", {})
	return float(m.get("base", 10)) + float(m.get("per_spi", 0.3)) * _stat(i, "spi")

func _speed(i: int) -> float:
	var s: Dictionary = _b.get("speed", {})
	return float(s.get("per_agi", 1.0)) * _stat(i, "agi") + float(s.get("per_level", 2)) * _f[i]["level"] \
		+ float(_f[i].get("speed_bonus", 0))

# cap x stat / (stat + k): rises fast early, flattens later, never reaches the cap.
func _soft(cap: float, stat: float, k: float) -> float:
	return cap * stat / (stat + k)

func _block(i: int) -> float:
	var b: Dictionary = _b.get("block", {})
	var v := _soft(float(b.get("cap", 0.35)), _stat(i, "str"), float(b.get("k", 300)))
	for buff in _f[i]["buffs"]:
		if buff["stat"] == "block":
			v += float(buff["amount"])
	if _f[i]["statuses"].has("cut"):
		var cut: Dictionary = _f[i]["statuses"]["cut"]
		v -= float(_db.status_effects.get("cut", {}).get("per_stack", 0.05)) * int(cut.get("stacks", 1))
	return clampf(v, 0.0, 0.75)

func _dodge(i: int) -> float:
	var d: Dictionary = _b.get("dodge", {})
	return _soft(float(d.get("cap", 0.30)), _stat(i, "agi"), float(d.get("k", 400)))

func _crit(i: int) -> float:
	var c: Dictionary = _b.get("crit", {})
	return minf(float(c.get("cap", 0.30)), float(c.get("base", 0.05))
		+ _soft(float(c.get("extra", 0.25)), _stat(i, "agi"), float(c.get("k", 500))))

func _crit_damage(i: int) -> float:
	var c: Dictionary = _b.get("crit_damage", {})
	return minf(float(c.get("cap", 2.0)), float(c.get("base", 1.5)) + float(c.get("per_str", 0.0005)) * _stat(i, "str"))

func _guard(i: int) -> float:
	var g: Dictionary = _b.get("guard", {})
	return float(g.get("per_str", 0.5)) * _stat(i, "str") + float(g.get("per_vit", 0.5)) * _stat(i, "vit")

func _ward(i: int) -> float:
	var w: Dictionary = _b.get("ward", {})
	return float(w.get("per_int", 0.5)) * _stat(i, "int") + float(w.get("per_spi", 0.5)) * _stat(i, "spi")

func _gain_spirit(i: int, amount: float) -> void:
	var sp: Dictionary = _b.get("spirit", {})
	var bonus := 1.0 + float(sp.get("spi_bonus_per_point", 0.005)) * _stat(i, "spi")
	_f[i]["spirit"] = minf(float(sp.get("max", 100)), _f[i]["spirit"] + amount * bonus)

# ===== SECTION 7: PASSIVES ===========================================================
# [LOGIC] Each pet's passive (pets.json "passive.kind"):
#   free_every          Scholar: every n-th skill costs no Mana            (SECTION 3)
#   low_hp_stat         Grit: below threshold HP, +pct to one stat          (SECTION 6)
#   dodge_speed         Moonlit Reflex: after dodging, +amount Speed next round
#   regen               Hearty Meal / Regenerate: heal pct HP every n turns
#   first_strike_stacks Overheat: +pct damage per round it acts first (max stacks)
#   start_shield        Hydrated: shield of pct HP at the start; once more below refresh_below
#   first_hit_blocked   Shell Up: the first `count` hits taken are always blocked (SECTION 4)
#   arcane_stacks       Deep Focus: arcane damage +pct per own turn (max), reset by a crit
#   first_turn          First Light: always acts first in round 1           (SECTION 2)
#   first_debuff_immune Unbothered: ignores the first debuff, gains Spirit  (SECTION 5)
#   reflect_physical    Ink Spikes: sends pct of physical damage back       (SECTION 4)
func _passive_kind(i: int) -> String:
	return _f[i]["passive"].get("kind", "")

func _on_battle_start(i: int) -> void:
	var f: Dictionary = _f[i]
	if _passive_kind(i) == "start_shield":
		f["shield"] = int(round(f["max_hp"] * float(f["passive"].get("pct", 0.05))))

func _passive_turn_start(i: int, steps: Array) -> void:
	var f: Dictionary = _f[i]
	match _passive_kind(i):
		"regen":
			var every := maxi(1, int(f["passive"].get("every", 1)))
			if int(f["turns_taken"]) % every == 0 and f["hp"] < f["max_hp"]:
				var healed := mini(f["max_hp"] - f["hp"], int(round(f["max_hp"] * float(f["passive"].get("pct", 0.03)))))
				f["hp"] += healed
				steps.append({"kind": "heal", "target": i, "amount": healed, "source": "passive"})
		"arcane_stacks":
			f["stacks"] = mini(int(f["passive"].get("max", 5)), int(f.get("stacks", 0)) + 1)

func _passive_before_attack(i: int, acted_first: bool) -> void:
	var f: Dictionary = _f[i]
	if _passive_kind(i) == "first_strike_stacks":
		f["stacks"] = mini(int(f["passive"].get("max", 4)), int(f.get("stacks", 0)) + 1) if acted_first else 0

func _passive_damage_mult(i: int, s: Dictionary) -> float:
	var f: Dictionary = _f[i]
	match _passive_kind(i):
		"first_strike_stacks":
			return 1.0 + float(f["passive"].get("pct", 0.05)) * int(f.get("stacks", 0))
		"arcane_stacks":
			if s.get("type", "") == "arcane":
				return 1.0 + float(f["passive"].get("pct", 0.05)) * int(f.get("stacks", 0))
	return 1.0

func _passive_after_damage(j: int, steps: Array) -> void:
	var f: Dictionary = _f[j]
	if _passive_kind(j) == "start_shield" and not f.get("shield_refreshed", false) \
			and f["hp"] > 0 and float(f["hp"]) / f["max_hp"] < float(f["passive"].get("refresh_below", 0.5)):
		f["shield_refreshed"] = true
		f["shield"] = maxi(f["shield"], int(round(f["max_hp"] * float(f["passive"].get("pct", 0.05)))))
		steps.append({"kind": "shield", "target": j, "amount": f["shield"], "source": "passive"})

# ===== SECTION 8: HELPERS ============================================================
func _fighter(snap: Dictionary) -> Dictionary:
	var stats: Dictionary = snap.get("stats", {})
	var level := int(snap.get("level", 10))
	var f := {
		"pet_id": snap.get("pet_id", ""), "name": snap.get("name", ""), "level": level,
		"element": snap.get("element", "none"), "stats": stats,
		"skills": snap.get("skills", []), "ultimate": snap.get("ultimate", {}),
		"passive": snap.get("passive", {}),
		"cooldowns": {}, "statuses": {}, "buffs": [], "counter": {}, "evade": {},
		"shield": 0, "spirit": 0.0, "speed_bonus": 0, "next_speed_bonus": 0,
	}
	f["max_hp"] = _max_hp(stats, level)
	f["hp"] = f["max_hp"]
	f["max_mana"] = _max_mana(stats)
	f["mana"] = f["max_mana"]
	return f

func _summary(i: int) -> Dictionary:
	var f: Dictionary = _f[i]
	return {"pet_id": f["pet_id"], "name": f["name"], "element": f["element"], "level": f["level"],
		"max_hp": f["max_hp"], "max_mana": f["max_mana"], "hp": f["hp"]}

func _alive(i: int) -> bool:
	return _f[i]["hp"] > 0

# Adds an event with the state of both pets after it (what the screen shows).
func _push(ev: Dictionary) -> void:
	ev["turn"] = _turn
	ev["round"] = _round
	ev["hp"] = [_f[0]["hp"], _f[1]["hp"]]
	ev["mana"] = [_f[0]["mana"], _f[1]["mana"]]
	ev["spirit"] = [int(_f[0]["spirit"]), int(_f[1]["spirit"])]
	ev["shield"] = [_f[0]["shield"], _f[1]["shield"]]
	ev["statuses"] = [_f[0]["statuses"].keys(), _f[1]["statuses"].keys()]
	_events.append(ev)
