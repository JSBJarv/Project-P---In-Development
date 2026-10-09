# =====================================================================================
# battle_fighter.gd  -  ONE PET ON THE BATTLE SCREEN (its picture and its moves)
# =====================================================================================
# What this file does:
#   Shows one pet in the Dojo and plays its battle animations. It uses the pet's battle
#   frames if they exist, and a simple drawn stand-in if they don't, so the battle works
#   before the art is ready.
#
# Battle frames (see the concept doc, "Battle sprite sheets"):
#   res://pets/<id>/battle/  with one PNG per frame, 128 x 128, facing right, feet on
#   y = 120, named by animation:
#     battle_idle_00.png ... (8)   attack_physical_00 ... (8)   cast_special_00 ... (8)
#     ultimate_00 ... (8)          dash_00 ... (4)              dodge_00 ... (4)
#     hurt_00 ... (4)              block_00 ... (4)             knockout_00 ... (8)
#     victory_00 ... (8)
#   The pet's id in front is allowed too (nocti_battle_idle_00.png). The sprite-sheet-
#   slicer skill exports frames like this. The opponent uses the same frames, mirrored.
#
# How to find things:
#   [EDIT]  = a setting you can safely change
#   [FIX]   = places to look first if something goes wrong
# =====================================================================================

class_name BattleFighter
extends Node2D

# [EDIT] Battle animations: name -> [frames per second, loops]. Same as the doc's table.
const ANIMS := {
	"battle_idle": [8.0, true], "attack_physical": [12.0, false], "cast_special": [12.0, false],
	"ultimate": [10.0, false], "dash": [12.0, false], "dodge": [12.0, false],
	"hurt": [12.0, false], "block": [12.0, false], "knockout": [10.0, false],
	"victory": [8.0, true],
}
# [EDIT] Frame size and feet line of the battle frames (the Project P standard cell).
const CELL := 128
const FEET_Y := 120
# [EDIT] How big the pet is drawn (2 = each frame pixel becomes 2 x 2).
const DRAW_SCALE := 2.0

var pet_id := ""
var element := "none"
var facing_right := true
var _sprite: AnimatedSprite2D = null
var _flash := 0.0                       # 0..1, white flash when hit
var _body_color := Color.WHITE
var _dark_color := Color.GRAY
var _ko := false

func setup(id: String, element_name: String, right: bool, folder: String) -> void:
	pet_id = id
	element = element_name
	facing_right = right
	_body_color = GameData.element_light(element)
	_dark_color = GameData.element_color(element).darkened(0.25)
	var frames := _load_frames(folder.path_join("battle"))
	if frames != null:
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = frames
		_sprite.centered = false
		_sprite.offset = Vector2(-CELL / 2.0, -FEET_Y)   # node position = the pet's feet
		_sprite.flip_h = not facing_right
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.scale = Vector2.ONE * DRAW_SCALE
		add_child(_sprite)
	play("battle_idle")

# Plays an animation; one-shot animations go back to battle_idle when they end.
func play(anim: String) -> void:
	if _ko and anim != "knockout":
		return
	if anim == "knockout":
		_ko = true
	if _sprite != null and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
		if not ANIMS.get(anim, [8.0, true])[1]:
			if not _sprite.animation_finished.is_connected(_back_to_idle):
				_sprite.animation_finished.connect(_back_to_idle)
	queue_redraw()

func _back_to_idle() -> void:
	if not _ko and _sprite.animation not in ["victory", "knockout"]:
		_sprite.play("battle_idle")

# White flash when the pet is hit.
func flash() -> void:
	var t := create_tween()
	t.tween_method(_set_flash, 1.0, 0.0, 0.12)

func _set_flash(v: float) -> void:
	_flash = v
	if _sprite != null:
		_sprite.modulate = Color(1, 1, 1).lerp(Color(3, 3, 3), v)
	queue_redraw()

# The stand-in pet: a round body in the element's colours, belly, eyes looking at the
# enemy, and a shadow. Drawn only when there are no battle frames.
func _draw() -> void:
	var s := DRAW_SCALE
	# shadow
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 34 * s, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO)
	if _sprite != null:
		return
	var dir := 1.0 if facing_right else -1.0
	var squash := 0.55 if _ko else 1.0
	var body := _body_color.lerp(Color.WHITE, _flash)
	var dark := _dark_color.lerp(Color.WHITE, _flash)
	draw_set_transform(Vector2(0, -36 * s * squash), 0.0, Vector2(1.0, squash))
	draw_circle(Vector2.ZERO, 38 * s, dark)
	draw_circle(Vector2.ZERO, 35 * s, body)
	draw_circle(Vector2(6 * dir * s, 12 * s), 18 * s, body.lightened(0.45))
	# ears
	for side in [-1.0, 1.0]:
		var base := Vector2(side * 20 * s, -26 * s)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-9 * s, 4 * s),
			base + Vector2(side * 4 * s, -20 * s), base + Vector2(9 * s, 6 * s)]), dark)
	# the pet's initial on its belly, so two stand-ins of one element can be told apart
	var font := ThemeDB.fallback_font
	var initial := pet_id.substr(0, 1).to_upper()
	draw_string(font, Vector2(6 * dir * s - 6 * s, 22 * s), initial, HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(14 * s), dark)
	# eyes
	if _ko:
		for ex in [-12.0, 10.0]:
			var c := Vector2((ex + 6 * dir) * s, -6 * s)
			draw_line(c - Vector2(4, 4) * s, c + Vector2(4, 4) * s, Color(0.15, 0.12, 0.18), 2 * s)
			draw_line(c + Vector2(-4, 4) * s, c + Vector2(4, -4) * s, Color(0.15, 0.12, 0.18), 2 * s)
	else:
		for ex in [-12.0, 10.0]:
			var c := Vector2((ex + 6 * dir) * s, -6 * s)
			draw_circle(c, 7 * s, Color.WHITE)
			draw_circle(c + Vector2(2.5 * dir * s, 1 * s), 4 * s, Color(0.15, 0.12, 0.18))
			draw_circle(c + Vector2((2.5 * dir + 1.5) * s, -0.5 * s), 1.4 * s, Color.WHITE)
	draw_set_transform(Vector2.ZERO)

# ===== FRAMES ========================================================================
# Builds SpriteFrames from the battle folder. Returns null when there are no frames.
# [FIX] Stand-in shape instead of your pet: check the folder res://pets/<id>/battle/
#       exists and the file names start with the animation names above.
func _load_frames(folder: String) -> SpriteFrames:
	var dir := DirAccess.open(folder)
	if dir == null:
		return null
	var files := []
	for f in dir.get_files():
		var fname := f.trim_suffix(".import").trim_suffix(".remap")
		if fname.get_extension().to_lower() == "png" and not files.has(fname):
			files.append(fname)
	files.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var found := 0
	for anim in ANIMS:
		frames.add_animation(anim)
		frames.set_animation_speed(anim, ANIMS[anim][0])
		frames.set_animation_loop(anim, ANIMS[anim][1])
		for f in files:
			var stem: String = f.get_basename().to_lower()
			var name_part := stem.rstrip("0123456789").trim_suffix("_")
			if name_part == anim or name_part.ends_with("_" + anim):
				frames.add_frame(anim, load(folder.path_join(f)))
				found += 1
	if found == 0 or frames.get_frame_count("battle_idle") == 0:
		return null
	print("Project P: battle frames for %s - %d frames." % [pet_id, found])
	return frames
