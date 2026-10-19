extends SceneTree
## The catcher's signs: sensible calls for the situation, the spot flipped for a left-hander, grading
## a thrown pitch against the call, and the whole thing in the scene (a sign is shown, can be shaken
## off, is graded and counted, and ends up on your line and in your totals).
## Run: godot --headless --path . -s res://tests/signs_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _calls(sit: Dictionary, n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var kinds := {}
	var cells := {}
	for i in n:
		var s := CatcherSigns.call_pitch(sit, [], rng)
		kinds[s.pitch] = int(kinds.get(s.pitch, 0)) + 1
		cells[s.cell] = int(cells.get(s.cell, 0)) + 1
	return {"kinds": kinds, "cells": cells}


func _init() -> void:
	var empty := [false, false, false]
	# Two strikes: chase pitches off the plate, mostly breaking balls low and away.
	var two := _calls({"balls": 0, "strikes": 2, "outs": 0, "bases": empty, "batter_side": 1.0}, 500)
	_check(int(two.cells.get("chase-low-away", 0)) > 280 and int(two.cells.get("chase-high", 0)) > 80, "with two strikes he calls a chase pitch (%s)" % str(two.cells))
	# Three balls: a fastball he can throw for a strike.
	var full := _calls({"balls": 3, "strikes": 0, "outs": 0, "bases": empty, "batter_side": 1.0}, 300)
	var only_fast: bool = full.kinds.size() == 1 and full.kinds.has("Fastball")
	var any_chase := false
	for c in full.cells:
		any_chase = any_chase or String(c).begins_with("chase")
	_check(only_fast and not any_chase, "with three balls it is a fastball in the zone")
	# A runner on third and fewer than two outs: nothing in the dirt.
	var third := _calls({"balls": 0, "strikes": 2, "outs": 0, "bases": [false, false, true], "batter_side": 1.0}, 300)
	var dirt := 0
	for c in third.cells:
		if String(c).begins_with("low") or c == "chase-low-away":
			dirt += int(third.cells[c])
	_check(dirt == 0, "with a runner on third nothing is called in the dirt")
	# Ahead in the count: breaking and offspeed pitches low.
	var ahead := _calls({"balls": 0, "strikes": 1, "outs": 1, "bases": empty, "batter_side": 1.0}, 400)
	var offspeed: int = ahead.kinds.get("Curveball", 0) + ahead.kinds.get("Slider", 0) + ahead.kinds.get("Changeup", 0)
	_check(offspeed > 200 and ahead.kinds.get("Fastball", 0) > 40, "ahead in the count he mixes in offspeed (%s)" % str(ahead.kinds))
	# Only what the pitcher throws.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var only := true
	for i in 200:
		var s := CatcherSigns.call_pitch({"balls": 0, "strikes": 2, "outs": 0, "bases": empty, "batter_side": 1.0}, ["Fastball", "Four-seam"], rng)
		only = only and s.pitch == "Fastball"
	_check(only, "he never calls a pitch you do not have")

	# The spot depends on which side the batter stands.
	var right := CatcherSigns.cell_target("low-away", 1.0)
	var left := CatcherSigns.cell_target("low-away", -1.0)
	_check(right.x < 0.0 and left.x > 0.0 and right.y == left.y and absf(right.x + left.x) < 0.001, "away from a right-hander is the other side from away from a left-hander")
	_check(CatcherSigns.cell_target("low-in", 1.0).x > 0.0 and CatcherSigns.cell_words("low-away") == "low and away" and CatcherSigns.cell_words("chase-low-away") == "off the plate, low and away", "the words read naturally")

	# Grading.
	var sign := {"pitch": "Slider", "cell": "low-away", "target": Vector2(-0.22, 0.55), "words": "Slider, low and away"}
	_check(CatcherSigns.grade(sign, "Slider", -0.20, 0.60).perfect, "right pitch, right spot")
	_check(CatcherSigns.grade(sign, "Cutter", -0.20, 0.60).perfect, "a cutter counts for a slider (same family)")
	var wrong_spot := CatcherSigns.grade(sign, "Slider", 0.25, 1.1)
	_check(wrong_spot.type and not wrong_spot.loc and not wrong_spot.perfect, "right pitch, wrong spot")
	var wrong_pitch := CatcherSigns.grade(sign, "Fastball", -0.22, 0.55)
	_check(not wrong_pitch.type and wrong_pitch.loc and not wrong_pitch.perfect, "right spot, wrong pitch")
	_check(not CatcherSigns.grade({}, "Slider", 0.0, 0.9).perfect, "no sign, nothing to hit")

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	_check(not bp.manager.sign.is_empty() and bp.manager.sign_label.visible and bp.manager.sign_marker.visible and bp.manager.sign_label.text.begins_with("SIGN:"), "a sign is shown before the first pitch (%s)" % bp.manager.sign_label.text)
	var first := String(bp.manager.sign.words)
	var changed := false
	for i in 12:
		bp.manager.shake_off()
		if String(bp.manager.sign.words) != first:
			changed = true
			break
	_check(changed and int(bp.manager.sign_tally.shaken) >= 1, "shaking him off gets another call")
	# Grade a pitch that matches.
	var p := LivePitch.new()
	p.label = String(bp.manager.sign.pitch)
	p.analysis = {"reached": true}
	var tg: Vector2 = bp.manager.sign.target
	bp.manager.grade_sign(p, Vector3(tg.x, tg.y, 0.0))
	_check(int(bp.manager.sign_tally.called) == 1 and int(bp.manager.sign_tally.perfect) == 1, "a pitch that matches the call is a sign hit")
	var line: Dictionary = bp._game_line()
	_check(int(line.signs) == 1 and int(line.sign_hits) == 1, "it goes on your line")
	var prof := PlayerProfile.new()
	prof.record_game(GameConfig.new(), line)
	_check(prof.lifetime_lines().any(func(x): return String(x).begins_with("Catcher signs: 1 of 1")), "and into your lifetime totals")
	bp._settings.signs = false
	bp.manager.refresh_sign()
	_check(bp.manager.sign.is_empty() and not bp.manager.sign_label.visible and not bp.manager.sign_marker.visible, "with the setting off there is no sign")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
