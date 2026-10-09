# =====================================================================================
# battle_screen.gd  -  THE DOJO: PLAYS A BATTLE ON SCREEN (landscape)
# =====================================================================================
# What this file does:
#   1. Turns the phone to landscape (1280 x 720) while the Dojo is open.
#   2. Takes the player's pet (stats from pet_stats.gd) and an opponent, and lets
#      battle_sim.gd decide the whole fight at once.
#   3. Plays the fight back as animation, Pockie Ninja style: HP and Mana bars, skill
#      banner, dashes, projectiles, damage numbers, critical hits, status pop-ups,
#      and a Victory / Defeat card. Buttons: 1x / 2x / 4x speed and Skip.
#   4. "Back" turns the phone to portrait again and returns to the main menu.
#
# Where it goes:
#   battle.tscn (a Node2D with this script). The main menu's Dojo button opens it.
#   It reads GameData.battle_request = {"player": "<pet id>", "opponent": "<pet id>"};
#   an empty or missing opponent = a random other pet with the same total stat points.
#
# How to find things:
#   [EDIT]  = a setting you can safely change (sizes, speeds, colours, texts)
#   [LOGIC] = what leads to what
#   [FIX]   = places to look first if something goes wrong
#
# Sections in this file:
#   1. Settings                                      -> search "SECTION 1"
#   2. Start-up: landscape, the fight                -> search "SECTION 2"
#   3. Building the screen                           -> search "SECTION 3"
#   4. Playing the fight back                        -> search "SECTION 4"
#   5. One action on screen                          -> search "SECTION 5"
#   6. Small effects (numbers, flashes, shake)       -> search "SECTION 6"
#   7. The end, speed buttons, leaving               -> search "SECTION 7"
# =====================================================================================

extends Node2D

# ===== SECTION 1: SETTINGS ===========================================================
# [EDIT] The Dojo's screen size (landscape) and the app's own size (portrait).
const BATTLE_SIZE := Vector2i(1280, 720)
const APP_SIZE := Vector2i(720, 1280)
# [EDIT] On a computer the window is turned too, to this size (width, height).
const DESKTOP_WINDOW := Vector2i(960, 540)
# [EDIT] Where the pets stand: share of the screen width, and the floor height.
const LEFT_X := 0.30
const RIGHT_X := 0.70
const FLOOR_Y := 0.78
# [EDIT] Timing in seconds at 1x speed (see "Smooth and efficient" in the concept doc).
const DASH_TIME := 0.25
const RETURN_TIME := 0.3
const PROJECTILE_TIME := 0.35
const HIT_STOP := 0.07
const HIT_STOP_CRIT := 0.11
const BETWEEN_HITS := 0.15
const BETWEEN_TURNS := 0.25
const NUMBER_TIME := 0.6
# [EDIT] Colours of the damage numbers.
const COLOR_DAMAGE := Color(1, 1, 1)
const COLOR_CRIT := Color(1.0, 0.86, 0.3)
const COLOR_HEAL := Color(0.55, 0.95, 0.55)
const COLOR_MANA := Color(0.5, 0.75, 1.0)
const COLOR_MISS := Color(0.75, 0.77, 0.82)
const COLOR_BLOCK := Color(0.65, 0.85, 1.0)
const OUTLINE := Color(0.13, 0.09, 0.07)
# [EDIT] Total stat points of a random opponent when the player's pet is untrained.
const MIN_OPPONENT_POINTS := 150
# The main scene to go back to.
const MAIN_SCENE := "res://main.tscn"

var _result: Dictionary = {}
var _fighters: Array = []           # two BattleFighter nodes
var _bars: Array = []               # per side: {"hp", "ghost", "mana", "spirit", "label", "status"}
var _max_hp := [1, 1]
var _max_mana := [1, 1]
var _banner: Label
var _banner_sub: Label
var _turn_label: Label
var _end_card: Control
var _camera: Camera2D
var _dim: ColorRect
var _layer: CanvasLayer
var _skip := false
var _size := Vector2(BATTLE_SIZE)

# ===== SECTION 2: START-UP ===========================================================
func _ready() -> void:
	_go_landscape()
	await get_tree().process_frame          # let the new screen size settle
	await get_tree().process_frame
	_size = get_viewport_rect().size
	_result = _run_fight()
	if _result.is_empty():
		_leave()
		return
	_build_screen()
	await _play_all()

# [LOGIC] The phone turns to landscape; the game's own size becomes 1280 x 720 so
#         everything is laid out for a wide screen. _leave() undoes both.
func _go_landscape() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	get_window().content_scale_size = BATTLE_SIZE
	if not OS.has_feature("mobile") and not DisplayServer.get_name() == "headless":
		get_window().size = DESKTOP_WINDOW

func _go_portrait() -> void:
	Engine.time_scale = 1.0
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	get_window().content_scale_size = APP_SIZE
	if not OS.has_feature("mobile") and not DisplayServer.get_name() == "headless":
		get_window().size = Vector2i(DESKTOP_WINDOW.y, DESKTOP_WINDOW.x)

# Picks the two pets and runs the whole fight (battle_sim.gd).
# [FIX] "pet not in pets.json": the id in the request (or the chosen pet) must be one of
#       the ids in res://data/pets.json and PETS in pet.gd.
func _run_fight() -> Dictionary:
	var req: Dictionary = GameData.battle_request
	var ids: Array = GameData.pets.keys()
	var player: String = req.get("player", "")
	if not GameData.pets.has(player):
		player = ids[0]
	var opponent: String = req.get("opponent", "")
	if not GameData.pets.has(opponent):
		var others := ids.filter(func(x): return x != player)
		opponent = others[randi() % others.size()]
	var my_stats := PetStats.get_stats(player)
	var total := 0
	for s in my_stats:
		total += my_stats[s]
	var level := PetStats.get_level(player)
	# [LOGIC] Both pets fight in their evolution form: its name, its battle frames and the
	#         stage's flat stat bonus (evolution.gd). The practice opponent gets the form
	#         its sample stats and the same level would give it.
	var my_form := Evolution.current(player)
	var a := BattleSim.make_snapshot(player, Evolution.battle_stats(player, my_stats, my_form.stage),
		level, "", [], my_form)
	var their_stats := BattleSim.sample_stats(opponent, maxi(total, MIN_OPPONENT_POINTS))
	var their_form := Evolution.form_from_stats(opponent, their_stats, level, my_form.stage == "final")
	var b := BattleSim.make_snapshot(opponent, Evolution.battle_stats(opponent, their_stats, their_form.stage),
		level, "", [], their_form)
	if a.is_empty() or b.is_empty():
		return {}
	var seed_value := int(Time.get_unix_time_from_system()) ^ randi()
	var r := BattleSim.new().run(a, b, seed_value)
	print("Project P: Dojo - %s vs %s, seed %d, %d events, winner %s." % [player, opponent,
		seed_value, r.events.size(), r.fighters[r.winner].name])
	return r

# ===== SECTION 3: BUILDING THE SCREEN ================================================
func _build_screen() -> void:
	# Background: sky, distant hills, floor (stand-in until the Dojo art is ready).
	# It reaches 200 px past every edge so the ultimate's camera zoom never shows a gap.
	var m := 200.0
	var sky := Polygon2D.new()
	sky.polygon = PackedVector2Array([Vector2(-m, -m), Vector2(_size.x + m, -m), _size + Vector2(m, m), Vector2(-m, _size.y + m)])
	sky.vertex_colors = PackedColorArray([Color("#3b3358"), Color("#3b3358"), Color("#f2b38a"), Color("#f2b38a")])
	add_child(sky)
	var hills := Polygon2D.new()
	var pts := PackedVector2Array([Vector2(-m, _size.y * 0.62)])
	for k in 9:
		pts.append(Vector2(-m + (_size.x + 2 * m) * k / 8.0, _size.y * (0.52 + 0.06 * sin(k * 1.7))))
	pts.append_array([Vector2(_size.x + m, _size.y * 0.62), _size + Vector2(m, m), Vector2(-m, _size.y + m)])
	hills.polygon = pts
	hills.color = Color("#6a5a7e")
	add_child(hills)
	var floor_poly := Polygon2D.new()
	var fy := _size.y * FLOOR_Y - 30
	floor_poly.polygon = PackedVector2Array([Vector2(-m, fy), Vector2(_size.x + m, fy), _size + Vector2(m, m), Vector2(-m, _size.y + m)])
	floor_poly.color = Color("#a88466")
	add_child(floor_poly)

	# The two pets
	for side in 2:
		var f: Dictionary = _result.fighters[side]
		var fighter := BattleFighter.new()
		var pet_folder: String = load("res://pet.gd").get_script_constant_map().get("PETS", {}).get(f.pet_id,
			"res://pets/" + f.pet_id)
		pet_folder = Evolution.art_folder(f.pet_id, pet_folder, true, f.get("form", ""))
		fighter.position = _home(side)
		add_child(fighter)
		fighter.setup(f.pet_id, f.element, side == 0, pet_folder)
		_fighters.append(fighter)
		_max_hp[side] = f.max_hp
		_max_mana[side] = f.max_mana

	_camera = Camera2D.new()
	_camera.position = _size / 2.0
	add_child(_camera)
	_camera.make_current()

	# Everything on top: bars, banner, buttons
	_layer = CanvasLayer.new()
	add_child(_layer)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_dim)
	for side in 2:
		_bars.append(_make_bars(side))
	var vs := _label("VS", 44, Color(1, 0.9, 0.6))
	vs.position = Vector2(_size.x / 2 - 40, 22)
	vs.size = Vector2(80, 50)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(vs)
	_turn_label = _label("", 22, Color(0.95, 0.92, 0.85))
	_turn_label.position = Vector2(_size.x / 2 - 80, 74)
	_turn_label.size = Vector2(160, 30)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(_turn_label)

	# Skill banner at the bottom
	var panel := Panel.new()
	panel.position = Vector2(_size.x * 0.15, _size.y - 92)
	panel.size = Vector2(_size.x * 0.7, 72)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.12, 0.1, 0.85)
	style.border_color = Color(0.85, 0.68, 0.38)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(panel)
	_banner = _label("", 28, Color(1, 0.97, 0.9))
	_banner.position = Vector2(20, 6)
	_banner.size = Vector2(panel.size.x - 40, 36)
	panel.add_child(_banner)
	_banner_sub = _label("", 18, Color(0.9, 0.82, 0.7))
	_banner_sub.position = Vector2(20, 40)
	_banner_sub.size = Vector2(panel.size.x - 40, 26)
	panel.add_child(_banner_sub)

	# Speed buttons
	var row := HBoxContainer.new()
	row.position = Vector2(_size.x - 330, _size.y - 150)
	row.add_theme_constant_override("separation", 8)
	for spec in [["1x", 1.0], ["2x", 2.0], ["4x", 4.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(70, 48)
		b.pressed.connect(func(): Engine.time_scale = spec[1])
		row.add_child(b)
	var skip := Button.new()
	skip.text = "Skip"
	skip.custom_minimum_size = Vector2(90, 48)
	skip.pressed.connect(func(): _skip = true)
	row.add_child(skip)
	_layer.add_child(row)

func _home(side: int) -> Vector2:
	return Vector2(_size.x * (LEFT_X if side == 0 else RIGHT_X), _size.y * FLOOR_Y)

# Name, HP bar (with a trailing "ghost" bar), Mana bar and Spirit bar for one side.
func _make_bars(side: int) -> Dictionary:
	var f: Dictionary = _result.fighters[side]
	var w := _size.x * 0.36
	var x := 24.0 if side == 0 else _size.x - 24.0 - w
	var box := Control.new()
	box.position = Vector2(x, 16)
	_layer.add_child(box)
	var name_l := _label("%s  Lv.%d" % [f.name, f.level], 24, Color(1, 0.96, 0.88))
	name_l.size = Vector2(w, 30)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(name_l)
	var el := _label(GameData.elements.get(f.element, {}).get("name", ""), 16, GameData.element_color(f.element))
	el.position = Vector2(0, 28)
	el.size = Vector2(w, 20)
	el.horizontal_alignment = name_l.horizontal_alignment
	box.add_child(el)
	# The white "ghost" bar (with the dark background) sits under the red HP bar and
	# follows it down a moment later, so you can see how much a hit took.
	var ghost := _bar(box, Vector2(0, 50), Vector2(w, 22), Color(1, 1, 1, 0.85), _max_hp_of(side), true)
	var hp := _bar(box, Vector2(0, 50), Vector2(w, 22), Color("#e5534b"), _max_hp_of(side))
	var hp_text := _label("", 15, Color.WHITE)
	hp_text.position = Vector2(0, 51)
	hp_text.size = Vector2(w, 20)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hp_text)
	var mana := _bar(box, Vector2(0, 76), Vector2(w, 12), Color("#4f9be8"), f.max_mana, true)
	var spirit := _bar(box, Vector2(0, 92), Vector2(w * 0.5, 8), Color("#f2c440"), 100, true)
	if side == 1:
		spirit.position.x = w * 0.5
	var status := _label("", 16, Color(1, 0.85, 0.6))
	status.position = Vector2(0, 104)
	status.size = Vector2(w, 22)
	status.horizontal_alignment = name_l.horizontal_alignment
	box.add_child(status)
	hp.value = f.max_hp
	ghost.value = f.max_hp
	hp_text.text = "%d / %d" % [f.max_hp, f.max_hp]
	mana.value = f.max_mana
	spirit.value = 0
	return {"hp": hp, "ghost": ghost, "hp_text": hp_text, "mana": mana, "spirit": spirit, "status": status}

func _max_hp_of(side: int) -> int:
	return int(_result.fighters[side].max_hp)

func _bar(parent: Control, pos: Vector2, size: Vector2, color: Color, max_value: float,
		with_back := false) -> ProgressBar:
	var b := ProgressBar.new()
	b.add_theme_font_size_override("font_size", 1)   # no text, so the bar can be thin
	b.custom_minimum_size = size
	b.position = pos
	b.size = size
	b.max_value = max_value
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.08, 0.1, 0.75) if with_back else Color(0, 0, 0, 0)
	back.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", back)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ===== SECTION 4: PLAYING THE FIGHT BACK =============================================
# [LOGIC] The fight is already decided. Each event is played in order; after each one
#         the bars are set to the exact values the simulator recorded, so the screen
#         can never disagree with the result. Skip jumps straight to the end.
func _play_all() -> void:
	await _wait(0.6)
	for ev in _result.events:
		if _skip:
			break
		await _play_event(ev)
		_sync(ev)
		await _wait(BETWEEN_TURNS)
	if not _result.events.is_empty():
		_sync(_result.events[-1])
	await _show_end()

func _sync(ev: Dictionary) -> void:
	for side in 2:
		var b: Dictionary = _bars[side]
		var hp: int = ev.hp[side]
		b.hp.value = hp
		b.hp_text.text = "%d / %d" % [hp, _max_hp[side]]
		var t := create_tween()
		t.tween_property(b.ghost, "value", float(hp), 0.4).set_delay(0.15)
		b.mana.value = ev.mana[side]
		b.spirit.value = ev.spirit[side]
		var tags := PackedStringArray()
		if int(ev.shield[side]) > 0:
			tags.append("Shield %d" % ev.shield[side])
		for st in ev.statuses[side]:
			tags.append(GameData.status_effects.get(st, {}).get("name", st))
		b.status.text = "  ".join(tags)
	_turn_label.text = "TURN %02d" % int(ev.get("turn", 0))

# ===== SECTION 5: ONE ACTION ON SCREEN ===============================================
func _play_event(ev: Dictionary) -> void:
	var actor: int = ev.get("actor", 0)
	var me: BattleFighter = _fighters[actor]
	var foe: BattleFighter = _fighters[1 - actor]
	var kind: String = ev.get("kind", "")
	match kind:
		"tick":
			for step in ev.steps:
				await _play_step(step, false)
			return
		"skip":
			_set_banner("%s can't move" % _result.fighters[actor].name, ev.get("name", ""))
			var t := create_tween()
			t.tween_property(me, "rotation", 0.12, 0.08)
			t.tween_property(me, "rotation", -0.12, 0.12)
			t.tween_property(me, "rotation", 0.0, 0.08)
			await t.finished
			return
	var el_name: String = GameData.elements.get(ev.get("element", ""), {}).get("name", "")
	var sub := "%s technique" % el_name if el_name != "" else ("Basic attack" if kind == "basic" else "Technique")
	if kind == "ultimate":
		sub = "Ultimate " + sub.to_lower()
	_set_banner("%s  /  %s" % [_result.fighters[actor].name.to_upper(), String(ev.get("name", "")).to_upper()], sub)
	var template: String = ev.get("template", "melee")
	if kind == "ultimate":
		await _ultimate_intro(me)
	var hits := []
	var others := []
	for step in ev.steps:
		if step.get("kind", "") == "hit" and step.get("source", "") == "" and int(step.get("target", -1)) != actor:
			hits.append(step)
		else:
			others.append(step)
	if hits.is_empty():
		# Self skills (heal, shield, buffs) and hexes
		me.play("cast_special")
		if template == "hex":
			await _projectile(me, foe, ev.get("element", "none"), true)
		else:
			await _aura(me, ev.get("element", "none"))
		for step in ev.steps:
			await _play_step(step, false)
		if kind == "ultimate":
			_end_ultimate()
		return
	var melee: bool = template in ["melee", "combo"] or (kind == "ultimate" and ev.get("type", "") == "physical")
	if melee:
		me.play("dash")
		var t := create_tween()
		var target := foe.position + Vector2(-120 if actor == 0 else 120, 0)
		t.tween_property(me, "position", target, DASH_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		await t.finished
		me.play("ultimate" if kind == "ultimate" else "attack_physical")
	else:
		me.play("ultimate" if kind == "ultimate" else "cast_special")
		await _wait(0.12)
		if template == "area":
			await _burst(foe.position + Vector2(0, -40), ev.get("element", "none"), 1.6)
		else:
			await _projectile(me, foe, ev.get("element", "none"), false)
	for step in ev.steps:
		await _play_step(step, true)
		if step in hits:
			await _wait(BETWEEN_HITS)
	if melee:
		var back := create_tween()
		back.tween_property(me, "position", _home(actor), RETURN_TIME).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
		await back.finished
	if kind == "ultimate":
		_end_ultimate()

# One result step: a hit (with dodge / block / crit), a heal, a status, a shield ...
func _play_step(step: Dictionary, in_attack: bool) -> void:
	var k: String = step.get("kind", "")
	var target: int = int(step.get("target", 0))
	var who: BattleFighter = _fighters[target]
	var above := who.position + Vector2(0, -190)
	match k:
		"hit":
			if step.get("dodged", false):
				who.play("dodge")
				var t := create_tween()
				var dx := -50.0 if target == 0 else 50.0
				t.tween_property(who, "position:x", _home(target).x + dx, 0.12)
				t.tween_property(who, "position:x", _home(target).x, 0.18)
				_number("MISS" if not step.get("evaded", false) else "EVADE", above, COLOR_MISS, 30)
				return
			var crit: bool = step.get("crit", false)
			await _hit_stop(HIT_STOP_CRIT if crit else HIT_STOP)
			who.flash()
			who.play("block" if step.get("blocked", false) else "hurt")
			_knockback(target)
			if crit:
				_shake(6.0)
				_number("CRITICAL", above + Vector2(0, -34), COLOR_CRIT, 22)
			var text := "-%d" % int(step.get("dmg", 0))
			var color := COLOR_CRIT if crit else COLOR_DAMAGE
			match step.get("source", ""):
				"burn":
					text = "BURN -%d" % int(step.get("dmg", 0))
					color = GameData.element_color("fire")
				"counter":
					text = "COUNTER -%d" % int(step.get("dmg", 0))
				"reflect":
					text = "SPIKES -%d" % int(step.get("dmg", 0))
			if step.get("blocked", false):
				_number("BLOCK", above + Vector2(0, -34), COLOR_BLOCK, 22)
			_number(text, above, color, 40 if crit else 34)
			_bars[target].hp.value = maxf(0.0, _bars[target].hp.value - int(step.get("dmg", 0)) + int(step.get("absorbed", 0)))
		"heal":
			_number("+%d" % int(step.get("amount", 0)), above, COLOR_HEAL, 32)
			await _aura(who, "none", COLOR_HEAL)
		"shield":
			_number("SHIELD", above, COLOR_BLOCK, 26)
			await _aura(who, "none", COLOR_BLOCK)
		"buff":
			_number("%s UP" % String(step.get("stat", "")).to_upper(), above, COLOR_HEAL, 24)
		"counter_ready":
			_number("COUNTER STANCE", above, COLOR_BLOCK, 22)
		"evade_ready":
			_number("GUARD", above, COLOR_BLOCK, 24)
		"mana_steal":
			_number("-%d MANA" % int(step.get("amount", 0)), above, COLOR_MANA, 24)
		"cleanse":
			if not (step.get("removed", []) as Array).is_empty():
				_number("CLEANSED", above, COLOR_HEAL, 22)
		"status":
			var info: Dictionary = GameData.status_effects.get(step.get("status", ""), {})
			if step.get("landed", false):
				_number(String(info.get("name", step.get("status", ""))).to_upper(), above + Vector2(0, -40),
					Color(info.get("color", "#ffffff")), 24)
			else:
				_number("IMMUNE" if step.get("immune", false) else "RESIST", above + Vector2(0, -40), COLOR_MISS, 20)
	await _wait(0.05)

func _set_banner(title: String, sub: String) -> void:
	_banner.text = title
	_banner_sub.text = sub

# ===== SECTION 6: SMALL EFFECTS ======================================================
# A floating number (or word): pops in large, rises and fades.
func _number(text: String, at: Vector2, color: Color, font_size: int) -> void:
	var l := _label(text, font_size, color)
	l.size = Vector2(320, font_size + 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.pivot_offset = l.size / 2
	l.position = at - l.size / 2 + Vector2(randf_range(-12, 12), 0)
	l.scale = Vector2.ONE * 1.4
	_layer.add_child(l)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.12)
	t.parallel().tween_property(l, "position:y", l.position.y - 24, NUMBER_TIME)
	t.parallel().tween_property(l, "modulate:a", 0.0, NUMBER_TIME * 0.6).set_delay(NUMBER_TIME * 0.4)
	t.tween_callback(l.queue_free)

func _hit_stop(seconds: float) -> void:
	for f in _fighters:
		f.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait(seconds)
	for f in _fighters:
		f.process_mode = Node.PROCESS_MODE_INHERIT

func _knockback(side: int) -> void:
	var f: BattleFighter = _fighters[side]
	var dx := -12.0 if side == 0 else 12.0
	var t := create_tween()
	t.tween_property(f, "position:x", f.position.x + dx, 0.06)
	t.tween_property(f, "position:x", _home(side).x, 0.2)

func _shake(strength: float) -> void:
	var t := create_tween()
	for k in 5:
		t.tween_property(_camera, "offset", Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), 0.03)
	t.tween_property(_camera, "offset", Vector2.ZERO, 0.03)

# Stand-in projectile: a glowing ball in the element's colour (replace with the
# element's effect sheet later - see "Skill effects" in the concept doc).
func _projectile(from: BattleFighter, to: BattleFighter, element: String, small: bool) -> void:
	var ball := _glow(GameData.element_color(element) if element != "none" else Color.WHITE, 10.0 if small else 18.0)
	ball.position = from.position + Vector2(40 if from == _fighters[0] else -40, -90)
	add_child(ball)
	var t := create_tween()
	t.tween_property(ball, "position", to.position + Vector2(0, -90), PROJECTILE_TIME)
	await t.finished
	ball.queue_free()
	await _burst(to.position + Vector2(0, -90), element, 0.8 if small else 1.0)

func _burst(at: Vector2, element: String, size: float) -> void:
	var ring := _glow(GameData.element_color(element) if element != "none" else Color.WHITE, 20.0 * size)
	ring.position = at
	add_child(ring)
	var t := create_tween()
	t.tween_property(ring, "scale", Vector2.ONE * 3.0, 0.22)
	t.parallel().tween_property(ring, "modulate:a", 0.0, 0.22)
	await t.finished
	ring.queue_free()

func _aura(who: BattleFighter, element: String, color := Color.TRANSPARENT) -> void:
	var c := color if color.a > 0.0 else (GameData.element_color(element) if element != "none" else Color(1, 1, 1))
	var ring := _glow(c, 70.0)
	ring.position = who.position + Vector2(0, -70)
	ring.modulate.a = 0.0
	add_child(ring)
	var t := create_tween()
	t.tween_property(ring, "modulate:a", 0.7, 0.15)
	t.tween_property(ring, "modulate:a", 0.0, 0.3)
	await t.finished
	ring.queue_free()

func _glow(color: Color, radius: float) -> Node2D:
	var n := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in 24:
		pts.append(Vector2.from_angle(TAU * k / 24.0) * radius)
	n.polygon = pts
	n.color = color
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	n.material = mat
	return n

func _ultimate_intro(who: BattleFighter) -> void:
	var t := create_tween()
	t.tween_property(_dim, "color:a", 0.5, 0.25)
	t.parallel().tween_property(_camera, "zoom", Vector2.ONE * 1.1, 0.3)
	t.parallel().tween_property(_camera, "position", (who.position + _size / 2.0) / 2.0, 0.3)
	await t.finished
	await _aura(who, who.element)

func _end_ultimate() -> void:
	var t := create_tween()
	t.tween_property(_dim, "color:a", 0.0, 0.25)
	t.parallel().tween_property(_camera, "zoom", Vector2.ONE, 0.3)
	t.parallel().tween_property(_camera, "position", _size / 2.0, 0.3)

func _wait(seconds: float) -> void:
	if _skip:
		return
	await get_tree().create_timer(seconds).timeout

# ===== SECTION 7: THE END, SPEED, LEAVING ============================================
func _show_end() -> void:
	_skip = false
	_end_ultimate()
	var winner: int = _result.winner
	_fighters[1 - winner].play("knockout")
	_fighters[1 - winner].queue_redraw()
	_fighters[winner].play("victory")
	var won := winner == 0
	_set_banner("%s WINS" % _result.fighters[winner].name.to_upper(),
		"Battle complete" + ("  -  time's up, more HP left" if _result.reason == "timeout" else ""))
	_end_card = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.11, 0.1, 0.92)
	style.border_color = Color(0.9, 0.72, 0.4)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	_end_card.add_theme_stylebox_override("panel", style)
	_end_card.size = Vector2(380, 200)
	_end_card.position = Vector2(_size.x / 2 - 190, _size.y * 0.24)
	_layer.add_child(_end_card)
	var title := _label("VICTORY" if won else "DEFEAT", 52, COLOR_CRIT if won else COLOR_MISS)
	title.size = Vector2(380, 70)
	title.position = Vector2(0, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_card.add_child(title)
	var last: Dictionary = _result.events[-1] if not _result.events.is_empty() else {}
	var hp_left: int = last.get("hp", [0, 0])[winner] if not last.is_empty() else 0
	var info := _label("%s  /  %d HP" % [_result.fighters[winner].name, hp_left], 22, Color(1, 0.95, 0.85))
	info.size = Vector2(380, 30)
	info.position = Vector2(0, 86)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_card.add_child(info)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 52)
	back.position = Vector2(110, 130)
	back.pressed.connect(_leave)
	_end_card.add_child(back)
	Engine.time_scale = 1.0

# [LOGIC] Back: portrait again, then the main menu (main.tscn starts on the menu).
func _leave() -> void:
	_go_portrait()
	get_tree().change_scene_to_file(MAIN_SCENE)

# The phone's Back button also leaves the Dojo.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_leave()
