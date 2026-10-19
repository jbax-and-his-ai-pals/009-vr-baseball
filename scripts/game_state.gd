class_name GameState
extends RefCounted
## The scorebook: balls, strikes, outs, innings, runners, runs, and whose turn it is to bat.
## Pure rules, no nodes, so the whole game can be simulated and tested without a window.
##
## It is a pitcher's-eye game: one lineup bats against the home defense, and an "inning" is that
## lineup's turn at bat (three outs). So the line it keeps is the pitcher's: pitches, strikeouts,
## walks, hits, runs and innings pitched.
##
## Feed it what happened:
##   pitch("ball" | "called_strike" | "swinging_strike" | "foul" | "foul_tip")
##   in_play(play)   - a Defense.resolve() result for a fair ball (or a foul out)
## Each returns an event dictionary describing what changed, for the HUD and scoreboard.

var innings := 9
var inning := 1
var outs := 0
var balls := 0
var strikes := 0
var bases: Array = [null, null, null]       # runner (Player or true) on 1st, 2nd, 3rd
var lineup: Array[Player] = []
var order_index := 0
var over := false

# The pitcher's line.
var pitch_count := 0
var batters_faced := 0
var strikeouts := 0
var walks := 0
var hits := 0
var errors := 0
var runs := 0
var outs_recorded := 0
var home_runs := 0
var hit_by_pitches := 0
var wild_pitches := 0
var intentional_walks := 0
var stolen_bases := 0
var caught_stealing := 0
var pickoffs := 0
var balks := 0
var sacrifices := 0

# The other half. The top of the inning is what you pitch; the bottom is played by
# `bottom_sim` (a Callable taking the inning and returning {"runs": int, "hits": int}) at the
# moment the third out is made. With no bottom_sim and allow_extra false the game is the old
# one-sided "innings of three outs" (used by simple tests).
var bottom_sim := Callable()
var bottom_live := false                    # the bottom half is played by someone (finish_bottom), not simulated
var awaiting_bottom := false                # the top is over and the bottom has not been reported yet
var allow_extra := false
var max_extra := 6                          # extra innings before a tie is called
var home_score := 0                         # the home team's runs
var home_team_hits := 0
var home_inning_runs: Array[int] = []
var walk_off := false
var inning_runs: Array[int] = []        # runs scored in each inning, by inning

var rng := RandomNumberGenerator.new()


func _init(batting_order: Array[Player] = [], total_innings: int = 9) -> void:
	lineup = batting_order
	innings = total_innings
	rng.randomize()


## Runs go to the total and to the inning they scored in (for the line score).
func _score(n: int) -> void:
	if n <= 0:
		return
	runs += n
	while inning_runs.size() < inning:
		inning_runs.append(0)
	inning_runs[inning - 1] += n


func current_batter() -> Player:
	if lineup.is_empty():
		return null
	return lineup[order_index % lineup.size()]


func runners_text() -> String:
	var on := []
	for i in 3:
		if bases[i] != null:
			on.append(["1B", "2B", "3B"][i])
	return "bases empty" if on.is_empty() else ", ".join(on)


func count_text() -> String:
	return "%d-%d" % [balls, strikes]


func innings_pitched_text() -> String:
	return "%d.%d" % [outs_recorded / 3, outs_recorded % 3]


func line_text() -> String:
	return "%d P | %s IP | %d K | %d BB | %d H | %d R" % [pitch_count, innings_pitched_text(), strikeouts, walks, hits, runs]


func situation_text() -> String:
	if over:
		return "FINAL"
	return "Inning %d | %d out | count %s | %s" % [inning, outs, count_text(), runners_text()]


func _event() -> Dictionary:
	return {"pa_over": false, "result": "", "runs": 0, "outs_added": 0, "half_over": false,
		"game_over": false, "text": "", "batter": current_batter()}


## One pitch that did not end up in play.
func pitch(outcome: String) -> Dictionary:
	var ev := _event()
	if over:
		return ev
	pitch_count += 1
	match outcome:
		"ball":
			balls += 1
			if balls >= 4:
				return _walk(ev)
		"called_strike", "swinging_strike":
			strikes += 1
			if strikes >= 3:
				ev.text = "Strike three (%s)" % ("looking" if outcome == "called_strike" else "swinging")
				return _strikeout(ev)
		"foul":
			if strikes < 2:        # a foul can never be strike three
				strikes += 1
		"foul_tip":
			# A tip is a foul ball: a strike with fewer than two, but never strike three.
			if strikes < 2:
				strikes += 1
		"foul_bunt":
			# A foul bunt is always a strike, even with two (the one foul that can be strike three).
			strikes += 1
			if strikes >= 3:
				ev.text = "Strike three (foul bunt)"
				return _strikeout(ev)
		"hit_by_pitch":
			hit_by_pitches += 1
			return _take_first(ev, "Hit by pitch", "hit_by_pitch")
	ev.text = _call_text(outcome)
	return ev


func _call_text(outcome: String) -> String:
	var name: String = {"ball": "Ball", "called_strike": "Called strike", "swinging_strike": "Swinging strike",
		"foul": "Foul", "foul_tip": "Foul tip"}.get(outcome, outcome)
	return "%s - count %s" % [name, count_text()]


func _walk(ev: Dictionary) -> Dictionary:
	walks += 1
	return _take_first(ev, "Walk", "walk")


## The batter is awarded first base (a walk or a hit by pitch): forced runners move up one.
func _take_first(ev: Dictionary, label: String, result: String) -> Dictionary:
	var scored := 0
	if bases[0] != null:
		if bases[1] != null:
			if bases[2] != null:
				scored = 1
			bases[2] = bases[1]
		bases[1] = bases[0]
	bases[0] = current_batter()
	_score(scored)
	ev.runs = scored
	ev.text = label + (" (run scores)" if scored > 0 else "")
	return _end_pa(result, ev)


## The pitch got past the catcher (or he could not hold it): every runner moves up a base.
## Call it after (or instead of) the pitch's own result. Returns what it did.
func wild_pitch(passed_ball: bool = false) -> Dictionary:
	var ev := _event()
	if over:
		return ev
	var moved := false
	var scored := 0
	var nb: Array = [null, null, null]
	for i in [2, 1, 0]:
		var r = bases[i]
		if r == null:
			continue
		var dest: int = i + 1
		if dest >= 3:
			scored += 1
		else:
			nb[dest] = r
		moved = true
	if not moved:
		return ev
	bases = nb
	wild_pitches += 1
	_score(scored)
	ev.runs = scored
	ev.result = "passed_ball" if passed_ball else "wild_pitch"
	ev.text = ("Passed ball" if passed_ball else "Wild pitch") + (", %d run%s score" % [scored, "" if scored == 1 else "s"] if scored > 0 else "")
	return ev


## Strike three, but the catcher did not hold it and the batter ran. Only legal with first base
## open or two outs (the caller checks). reaches: he made it to first; otherwise he is thrown out.
func dropped_third_strike(reaches: bool) -> Dictionary:
	var ev := _event()
	if over:
		return ev
	pitch_count += 1
	strikes = 3
	if not reaches:
		ev.text = "Strike three (dropped, thrown out at first)"
		return _strikeout(ev)
	strikeouts += 1
	ev.result = "strikeout"
	ev["batter_reached"] = true
	# He takes first; anyone forced ahead of him moves up.
	var scored := 0
	if bases[0] != null:
		if bases[1] != null:
			if bases[2] != null:
				scored = 1
			bases[2] = bases[1]
		bases[1] = bases[0]
	bases[0] = current_batter()
	_score(scored)
	ev.runs = scored
	ev.text = "Strike three, dropped - the batter reaches first" + (" (run scores)" if scored > 0 else "")
	return _end_pa("strikeout", ev, false)


## A runner went on the pitch. safe: he made it (the base is his); otherwise he is out.
func steal(from_base: int, safe: bool) -> Dictionary:
	var ev := _event()
	if over or from_base < 1 or from_base > 3 or bases[from_base - 1] == null:
		return ev
	var runner = bases[from_base - 1]
	var names := ["", "second", "third", "home"]
	if safe and from_base == 3:
		# A runner breaking from third on a squeeze that goes wrong but not for him: he scores.
		bases[2] = null
		stolen_bases += 1
		ev.result = "stolen_base"
		ev.text = "Safe at home"
		ev.runs = 1
		_score(1)
		return ev
	if safe and from_base < 3 and bases[from_base] == null:
		bases[from_base] = runner
		bases[from_base - 1] = null
		stolen_bases += 1
		ev.result = "stolen_base"
		ev.text = "Stolen base (%s)" % names[from_base]
		return ev
	bases[from_base - 1] = null
	caught_stealing += 1
	ev.result = "caught_stealing"
	ev.text = "Caught stealing %s" % names[from_base]
	ev.outs_added = 1
	_add_outs(1, ev)
	_clear_count_if_half_over(ev)
	return ev


## A throw over caught him off the bag.
func pickoff(base: int) -> Dictionary:
	var ev := _event()
	if over or base < 1 or base > 3 or bases[base - 1] == null:
		return ev
	bases[base - 1] = null
	pickoffs += 1
	ev.result = "pickoff"
	ev.text = "Picked off %s" % ["", "first", "second", "third"][base]
	ev.outs_added = 1
	_add_outs(1, ev)
	_clear_count_if_half_over(ev)
	return ev


## One runner takes the next base without it being a steal (he beat a rundown). From third he scores.
func advance_runner(base: int) -> Dictionary:
	var ev := _event()
	if over or base < 1 or base > 3 or bases[base - 1] == null:
		return ev
	var runner = bases[base - 1]
	if base < 3 and bases[base] != null:
		return ev                                   # the next base is taken: he cannot
	bases[base - 1] = null
	ev.result = "advance"
	if base == 3:
		_score(1)
		ev.runs = 1
		ev.text = "Scores on the rundown"
	else:
		bases[base] = runner
		ev.text = "Beats the rundown to %s" % ["", "second", "third"][base]
	return ev


## The pitcher did something illegal with a runner on: every runner moves up a base.
func balk() -> Dictionary:
	var ev := wild_pitch()
	if ev.get("result", "") == "":
		return ev
	wild_pitches -= 1            # not a wild pitch
	balks += 1
	ev.result = "balk"
	ev.text = "Balk" + (", %d run%s score" % [int(ev.runs), "" if int(ev.runs) == 1 else "s"] if int(ev.runs) > 0 else "")
	return ev


func _clear_count_if_half_over(ev: Dictionary) -> void:
	if ev.get("half_over", false):
		balls = 0
		strikes = 0


## The defense walks him on purpose: no pitches, and the same forced advance as a walk.
func intentional_walk() -> Dictionary:
	var ev := _event()
	if over:
		return ev
	intentional_walks += 1
	walks += 1
	return _take_first(ev, "Intentional walk", "walk")


func _strikeout(ev: Dictionary) -> Dictionary:
	strikeouts += 1
	ev.outs_added = 1
	ev.result = "strikeout"
	_add_outs(1, ev)
	return _end_pa("strikeout", ev, false)


## A fair ball put in play (or a foul caught for an out). `play` is Defense.resolve()'s result.
func in_play(play: Dictionary, plan: PlayPlan = null) -> Dictionary:
	var ev := _event()
	if over:
		return ev
	pitch_count += 1
	if plan != null:
		return _apply_plan(play, plan, ev)
	var result: String = play.get("result", "out")
	var batter := current_batter()
	match result:
		"home_run":
			var rs := 1
			for i in 3:
				if bases[i] != null:
					rs += 1
			bases = [null, null, null]
			_score(rs)
			hits += 1
			home_runs += 1
			ev.runs = rs
			ev.text = "Home run, %d run%s" % [rs, "" if rs == 1 else "s"]
			return _end_pa("home_run", ev)
		"single", "double", "triple", "inside_park_hr", "error":
			var n := 1 if result == "error" else int(play.get("bases", 1))
			if result == "error":
				errors += 1
			else:
				hits += 1
			var scored := _advance_on_hit(n, batter)
			_score(scored)
			ev.runs = scored
			var nm: String = {1: "Single", 2: "Double", 3: "Triple", 4: "Inside-the-park home run"}.get(n, "Hit")
			if result == "error":
				nm = "Reached on an error"
			ev.text = nm + ((", %d run%s score" % [scored, "" if scored == 1 else "s"]) if scored > 0 else "")
			if n >= 4:
				bases = [null, null, null]
			return _end_pa(result, ev)
		_:
			# An out: caught, forced at first, or a foul out.
			return _out_in_play(play, ev)


## Record a play whose runners were already decided by Baserunning.plan().
func _apply_plan(play: Dictionary, plan: PlayPlan, ev: Dictionary) -> Dictionary:
	var result: String = plan.result if plan.result != "" else String(play.get("result", "out"))
	if plan.text == "Infield fly rule, batter is out":
		result = "out"
	var scored: int = plan.runs
	var added: int = plan.outs_added
	var text := ""
	match result:
		"home_run":
			hits += 1
			home_runs += 1
			text = "Home run, %d run%s" % [scored, "" if scored == 1 else "s"]
		"single", "double", "triple", "inside_park_hr", "error":
			if result == "error":
				errors += 1
				text = "Reached on an error"
			else:
				hits += 1
				var n := int(play.get("bases", 1))
				text = {1: "Single", 2: "Double", 3: "Triple", 4: "Inside-the-park home run"}.get(n, "Hit")
				if play.get("ground_rule", false):
					text = "Ground-rule double"
			if scored > 0:
				text += ", %d run%s score" % [scored, "" if scored == 1 else "s"]
			if added > 0:
				text += ", runner thrown out" if added == 1 else ", %d runners thrown out" % added
		"fielders_choice":
			text = plan.text if plan.text != "" else "Fielder's choice"
			if scored > 0:
				text += ", %d run%s score" % [scored, "" if scored == 1 else "s"]
		_:
			text = plan.text if plan.text != "" else String(play.get("text", "Out"))
			# A bunt that gives himself up to move a runner: a sacrifice, not an at-bat.
			if play.get("bunt", false) and added == 1:
				var moved := false
				var bat_out := false
				for rr in plan.runners:
					if int(rr.from) > 0 and not rr.out and int(rr.to) != int(rr.from):
						moved = true
					if int(rr.from) == 0 and rr.out:
						bat_out = true
				if moved and bat_out:
					sacrifices += 1
					text = "Sacrifice bunt" + (" (%s)" % plan.text if plan.text != "" and not plan.text.begins_with("Groundout") else "")
					result = "sacrifice"
			if plan.text == "":
				text += plan.suffix
			if scored > 0:
				text += ", %d run%s score" % [scored, "" if scored == 1 else "s"]
	bases = (plan.final_bases as Array).duplicate()
	_score(scored)
	ev.runs = scored
	ev.outs_added = added
	ev.text = text
	if added > 0:
		_add_outs(added, ev)
	return _end_pa("home_run" if result == "home_run" else ("out" if result == "out" else result), ev, false)


func _out_in_play(play: Dictionary, ev: Dictionary) -> Dictionary:
	var caught_in_air: bool = play.get("caught_in_air", false)
	var added := 1
	var text: String = play.get("text", "Out")
	var scored := 0
	if not caught_in_air and bases[0] != null and outs < 2 and rng.randf() < 0.45:
		# A ground ball with a runner on first: two.
		added = 2
		text += " (double play)"
		bases[0] = null
		# Runners on second and third move up (the runner from third scores if it is not the third out).
		if bases[2] != null and outs + 2 < 3:
			scored += 1
		bases[2] = bases[1]
		bases[1] = null
	elif outs < 2:
		var deep: bool = caught_in_air and Vector2(play.get("field_pos", Vector3.ZERO).x, play.get("field_pos", Vector3.ZERO).z).length() > 55.0
		if deep and bases[2] != null and rng.randf() < 0.75:
			scored += 1
			bases[2] = null
			text += " (sacrifice fly)"
		elif not caught_in_air and rng.randf() < 0.6:
			# Runners move up on a ground ball out.
			if bases[2] != null:
				scored += 1
				bases[2] = null
			if bases[1] != null:
				bases[2] = bases[1]
				bases[1] = null
			if bases[0] != null and bases[1] == null:
				bases[1] = bases[0]
				bases[0] = null
	# No run counts if the third out is made on this play.
	if outs + added >= 3:
		scored = 0
	_score(scored)
	ev.runs = scored
	ev.outs_added = added
	ev.text = text
	_add_outs(added, ev)
	return _end_pa("out", ev, false)


## Move every runner up n bases. Returns the runs that scored. The batter takes the base n.
func _advance_on_hit(n: int, batter: Player) -> int:
	var scored := 0
	var new_bases: Array = [null, null, null]
	for i in [2, 1, 0]:
		var r = bases[i]
		if r == null:
			continue
		var dest: int = (i + 1) + n
		# The runner on second scores from a single often enough to matter.
		if n == 1 and i == 1 and rng.randf() < 0.45:
			dest = 4
		if dest >= 4:
			scored += 1
		else:
			new_bases[dest - 1] = r
	if n >= 4:
		scored += 1
	else:
		new_bases[n - 1] = batter if batter != null else true
	bases = new_bases
	return scored


func _add_outs(n: int, ev: Dictionary) -> void:
	outs += n
	outs_recorded += n
	if outs >= 3:
		ev.half_over = true
		ev["inning_ended"] = inning
		outs = 0
		bases = [null, null, null]
		_finish_top_half(ev)


## The top of the inning is over: play the bottom, then decide whether the game goes on.
func _finish_top_half(ev: Dictionary) -> void:
	if not bottom_sim.is_valid() and not allow_extra:
		inning += 1
		if inning > innings:
			over = true
			ev.game_over = true
		return
	var regulation_done := inning >= innings
	if regulation_done and home_score > runs:
		# The home team is already ahead after the top of the last inning: no bottom half.
		over = true
		ev.game_over = true
		return
	if bottom_live:
		# The bottom half is played by someone: wait here until finish_bottom() brings the result.
		awaiting_bottom = true
		ev["bottom_live"] = true
		return
	var result := {"runs": 0, "hits": 0}
	if bottom_sim.is_valid():
		result = bottom_sim.call(inning)
	_resolve_bottom(result, ev)


## A bottom half that was played live is over: `runs` and `hits` are what the home team did in it.
## Returns an event with game_over set if that ends the game.
func finish_bottom(runs: int, hits: int) -> Dictionary:
	var ev := _event()
	if not awaiting_bottom:
		return ev
	awaiting_bottom = false
	ev["inning_ended"] = inning
	_resolve_bottom({"runs": runs, "hits": hits}, ev)
	return ev


func _resolve_bottom(result: Dictionary, ev: Dictionary) -> void:
	var regulation_done := inning >= innings
	while home_inning_runs.size() < inning:
		home_inning_runs.append(0)
	home_inning_runs[inning - 1] = int(result.runs)
	home_score += int(result.runs)
	home_team_hits += int(result.hits)
	ev["home_runs_scored"] = int(result.runs)
	if regulation_done and home_score > runs:
		over = true
		walk_off = true
		ev.game_over = true
		return
	if regulation_done and (home_score < runs or inning >= innings + max_extra):
		over = true
		ev.game_over = true
		return
	inning += 1


## "FINAL: Away 4, Home 3" with the extra innings noted.
func final_text() -> String:
	var t := "FINAL: Away %d, Home %d" % [runs, home_score]
	if inning > innings:
		t += " (%d innings)" % inning
	if walk_off:
		t += " - walk-off"
	return t


func _end_pa(result: String, ev: Dictionary, reset_bases_unused: bool = true) -> Dictionary:
	ev.pa_over = true
	if ev.result == "":
		ev.result = result
	batters_faced += 1
	balls = 0
	strikes = 0
	order_index = (order_index + 1) % maxi(lineup.size(), 1)
	return ev
