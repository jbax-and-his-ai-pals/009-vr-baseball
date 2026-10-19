extends SceneTree
## SoundDirector and PlayDirector on their own, without the full game: what is heard for what happens,
## and the play timing / receiver / catch rules of the play director.
## Run: godot --headless --path . -s res://tests/directors_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## An audio manager that only writes down what it was asked to play.
class Spy extends AudioManager:
	var heard: Array = []

	func play(id: String, _at: Variant = null, _db: float = 0.0, _pitch: float = 1.0) -> bool:
		heard.append(id)
		return true

	func play_later(_seconds: float, id: String, _at: Variant = null, _db: float = 0.0) -> void:
		heard.append(id)


func _sound() -> Array:
	var sd := SoundDirector.new()
	var spy := Spy.new()
	sd.audio.queue_free()
	sd.audio = spy
	sd.add_child(spy)
	root.add_child(sd)
	return [sd, spy]


func _init() -> void:
	var pair := _sound()
	var sd: SoundDirector = pair[0]
	var spy: Spy = pair[1]
	_check(SoundDirector.pop_for(40.0) == "glove_pop_soft" and SoundDirector.pop_for(60.0) == "glove_pop_medium" and SoundDirector.pop_for(80.0) == "glove_pop_hard", "the mitt pops by speed")

	sd.pitch_arrives({"reached": true, "plate_mph": 75.0}, "ball", Vector3(0.0, 0.1, 0.0))
	_check(spy.heard.has("ball_skid_dirt") and spy.heard.has("glove_pop_dirt_block"), "a pitch in the dirt skids and is blocked")
	spy.heard.clear()
	sd.pitch_arrives({"reached": true, "plate_mph": 75.0}, "hit_by_pitch", Vector3(0.9, 0.9, 0.0))
	_check(spy.heard.has("ball_hits_batter") and spy.heard.has("crowd_gasp"), "a hit batter is heard and the crowd gasps")
	spy.heard.clear()
	sd.pitch_arrives({"reached": true, "plate_mph": 75.0}, "called_strike", Vector3(0.28, 0.85, 0.0))
	_check(spy.heard.has("glove_pop_hard") and spy.heard.has("corner_chime"), "a corner strike pops and chimes")
	spy.heard.clear()
	sd.pitch_arrives({"reached": true, "plate_mph": 50.0}, "ball", Vector3(1.5, 1.0, 0.0))
	_check(spy.heard.has("glove_pop_soft") and spy.heard.has("ball_hits_backstop"), "a wild one goes to the backstop")
	spy.heard.clear()

	sd.contact({"kind": "hit", "ev": 100.0}, {"home_run": false, "apex": 3.0, "distance": 30.0, "fair": true}, Vector3.ZERO)
	_check(spy.heard == ["bat_crack_sweet"], "a hard hit is a sweet crack")
	spy.heard.clear()
	sd.contact({"kind": "hit", "ev": 80.0}, {"home_run": false, "apex": 3.0, "distance": 30.0, "fair": true}, Vector3.ZERO)
	sd.contact({"kind": "hit", "ev": 70.0}, {"home_run": false, "apex": 3.0, "distance": 30.0, "fair": true}, Vector3.ZERO)
	_check(spy.heard == ["bat_crack_good", "bat_crack_weak"], "a good one and a weak one")
	spy.heard.clear()
	sd.contact({"kind": "hit", "ev": 105.0}, {"home_run": true, "apex": 30.0, "distance": 120.0, "fair": true}, Vector3.ZERO)
	_check(spy.heard.has("home_run_crack") and sd.flip_next, "a homer cracks and the batter will flip the bat")
	spy.heard.clear()
	sd.contact({"kind": "foul tip", "ev": 40.0}, {}, Vector3.ZERO)
	sd.contact({"kind": "hit", "ev": 30.0, "bunt": true}, {}, Vector3.ZERO)
	_check(spy.heard == ["bat_foul_tip", "bat_bunt_tap"], "tips and bunts have their own sounds")
	spy.heard.clear()

	sd.crowd_react({"result": "home_run", "runs": 1}, null)
	_check(spy.heard.has("crowd_roar_hr") and spy.heard.has("fireworks") and not spy.heard.has("scoreboard_run_chime"), "a homer is a roar and fireworks, not the run chime")
	spy.heard.clear()
	sd.crowd_react({"result": "single", "runs": 2}, null)
	_check(spy.heard.has("crowd_cheer_small") and spy.heard.has("scoreboard_run_chime") and spy.heard.has("crowd_cheer_big"), "runs get the chime and a bigger cheer")
	spy.heard.clear()
	sd.crowd_react({"result": "strikeout"}, null)
	sd.crowd_react({"result": "walk"}, null)
	sd.crowd_react({"result": "error"}, null)
	_check(spy.heard.has("music_strikeout_sting") and spy.heard.has("crowd_boo") and spy.heard.has("crowd_groan"), "strikeouts, walks and errors")
	spy.heard.clear()
	sd.crowd_react({"half_over": true, "inning_ended": 7}, null)
	var stretches := spy.heard.count("seventh_inning_stretch")
	sd.crowd_react({"half_over": true, "inning_ended": 7}, null)
	_check(stretches == 1 and spy.heard.count("seventh_inning_stretch") == 1, "the seventh-inning stretch happens once")
	sd.new_game()
	sd.crowd_react({"half_over": true, "inning_ended": 7}, null)
	_check(spy.heard.count("seventh_inning_stretch") == 2, "and again in the next game")
	spy.heard.clear()
	var game := GameState.new(Team.generate("Away", 50.0, 3).lineup, 3)
	game.home_score = 2
	game.runs = 1
	sd.mode = GameMode.pitching()
	sd.crowd_react({"game_over": true}, game)
	_check(spy.heard.has("music_victory"), "your side wins: the victory music")
	spy.heard.clear()
	game.home_score = 0
	sd.crowd_react({"game_over": true}, game)
	_check(spy.heard.has("music_loss"), "your side loses: the loss music")
	spy.heard.clear()
	sd.mode = GameMode.spectate()
	sd.crowd_react({"game_over": true}, game)
	_check(spy.heard.has("music_victory") and not spy.heard.has("music_loss"), "a spectator hears the victory music whoever wins")
	var said := []
	sd.umpire_spoke.connect(func(id: String, delay: float): said.append([id, delay]))
	sd.umpire_says_later(0.5, "ump_ball")
	_check(said == [["ump_ball", 0.5]], "the umpire's words are announced for the call text")
	sd.queue_free()

	# The play director.
	var team := Team.generate("Home", 55.0, 7)
	var pd := PlayDirector.new()
	pd.defense = Defense.from_team(team)
	var fly := {"result": "out", "fielder": 8, "field_time": 3.0, "caught_in_air": true, "bases": 0}
	_check(is_equal_approx(pd.play_end_time(fly, 6.0), 3.5), "a fly ball ends half a second after the catch, not when the ball would have stopped")
	_check(pd.play_end_time({}, 4.0) == 4.0, "no play, no extra wait")
	var single := {"result": "single", "fielder": 6, "field_time": 2.0, "bases": 1, "run_times": [4.2, 8.0, 11.5, 15.0]}
	_check(is_equal_approx(pd.play_end_time(single, 1.0), 4.7), "a single lasts until he is on first")
	var hr := {"result": "home_run", "fielder": 0, "bases": 4, "run_times": [4.2, 8.0, 11.5, 15.0]}
	_check(is_equal_approx(pd.play_end_time(hr, 5.0), 12.0), "a homer lasts while he trots (0.8 of the circuit)")
	var thrown := {"result": "out", "fielder": 6, "field_time": 2.0, "bases": 0, "runner_out_at": 1, "run_times": [4.2, 8.0, 11.5, 15.0], "throw": {"t1": 4.0}}
	_check(is_equal_approx(pd.play_end_time(thrown, 1.0), 4.7), "a throw to first ends when the runner would have arrived")
	_check(pd.receiver_candidates(1, 6, Vector3.ZERO) == [3, 1, 4], "first base: the first baseman, then the pitcher, then the second baseman")
	_check(pd.receiver_for(2, 6, Vector3.ZERO) == 4 and pd.receiver_for(2, 4, Vector3.ZERO) == 6, "the middle infielders take each other's throws at second")
	_check(pd.receiver_for(2, 2, Vector3(0.0, 0.0, -1.0)) == 6 and pd.receiver_for(2, 2, Vector3(-9.0, 0.0, 10.0)) == 4, "from the plate it depends on which side of second he is")
	_check(pd.receiver_for(3, 6, Vector3.ZERO) == 5 and pd.receiver_for(4, 8, Vector3.ZERO) == 2, "third goes to the third baseman, home to the catcher")
	_check(pd.catch_clip({"field_pos": Vector3(0.0, 3.0, 40.0)}, 8) == "jump", "a high one is a jump")
	_check(pd.catch_clip({"field_pos": Vector3(8.5, 0.3, 32.5)}, 6) == "scoop", "a grounder at his feet is a scoop")
	_check(pd.catch_clip({"field_pos": Vector3(14.0, 0.3, 32.5)}, 6) == "backhand", "one well off to the side is a backhand")
	_check(pd.catch_clip({"field_pos": Vector3(8.5, 1.4, 32.5)}, 6) == "catch", "a chest-high one is a catch")
	var forced_out := {"runners": [{"out": true, "out_base": 2, "forced_out": true}]}
	var tag_out := {"runners": [{"out": true, "out_base": 2, "forced_out": false}]}
	_check(not pd.is_tag_play(forced_out, 2) and pd.is_tag_play(tag_out, 2) and not pd.is_tag_play(tag_out, 1), "a tag is an out at a base that was not a force (and never first)")
	_check(pd.plan_anim_end({}) == 0.0, "an empty plan has no animation")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
