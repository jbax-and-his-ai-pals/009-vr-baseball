class_name SoundDirector
extends Node
## Decides WHAT should be heard for what is happening in the game; AudioManager knows HOW to play it.
## The scene tells it things happened (a pitch arrived, the bat hit the ball, a result came in) and
## it picks the sound, where it comes from and how loud, and runs the crowd, ambience and music.
##
## Nothing here touches gameplay or the random numbers the rules use.

const MITT_Z := -0.85
const BACKSTOP_Z := -6.6

var audio: AudioManager
var mode: GameMode                       # who is human (set by the scene)
var umpire: Node3D                       # where the umpire's voice comes from
var batter: Node3D                       # ... and the batter's
## Returns your arm's fatigue 0..1 (only asked while you pitch, twice a second).
var tired_source := Callable()
## Set when a home run was hit: the bat is flipped, not just dropped.
var flip_next := false

var _tick := 0.0
var _clock := 0.0                        # game time (stops while paused), for "not more than every 2 minutes"
var _game_start_said := false
var _stretch_done := false
var _last_charge := -999.0


func _init() -> void:
	audio = AudioManager.new()
	add_child(audio)


## A new game: the openings and the one-per-game moments are available again.
func new_game() -> void:
	_game_start_said = false
	_stretch_done = false


# ------------------------------------------------------------------ plain playing
func sfx(id: String, at: Variant = null, db: float = 0.0) -> void:
	audio.play(id, at, db)


func sfx_later(seconds: float, id: String, at: Variant = null, db: float = 0.0) -> void:
	audio.play_later(seconds, id, at, db)


func _head(node: Node3D, up: float) -> Variant:
	return node.global_position + Vector3(0.0, up, 0.0) if node != null else null


## A person's footstep: dirt on the infield, grass elsewhere.
func footstep(at: Vector3) -> void:
	var dirt := Vector2(at.x, at.z - 13.0).length() < 24.0
	sfx("step_dirt_run" if dirt else "step_grass_run", at + Vector3(0.0, 0.1, 0.0), -9.0)


func walk_step(at: Vector3) -> void:
	sfx("step_walk", at + Vector3(0.0, 0.1, 0.0), -8.0)


## The umpire says something.
func umpire_says(id: String) -> void:
	sfx(id, _head(umpire, 1.5))


func umpire_says_later(seconds: float, id: String, db: float = 0.0) -> void:
	sfx_later(seconds, id, _head(umpire, 1.5), db)


# ------------------------------------------------------------------ the pitch and the bat
## Which glove pop a pitch makes, by how fast it arrives.
static func pop_for(mph: float) -> String:
	if mph < 55.0:
		return "glove_pop_soft"
	return "glove_pop_medium" if mph < 70.0 else "glove_pop_hard"


## The pitch gets to the plate: the mitt, the dirt, or the batter.
func pitch_arrives(a: Dictionary, outcome: String, plate: Vector3) -> void:
	var mitt := Vector3(clampf(plate.x, -1.0, 1.0), clampf(plate.y, 0.1, 1.9), MITT_Z)
	if not a.get("reached", false) or plate.y < 0.18:
		sfx("ball_skid_dirt", Vector3(plate.x, 0.0, 0.3))
		sfx_later(0.12, "glove_pop_dirt_block", Vector3(0.0, 0.5, -1.0))
		return
	if outcome == "hit_by_pitch":
		sfx("ball_hits_batter", Vector3(plate.x, plate.y, 0.0))
		sfx_later(0.15, "batter_hurt_grunt", _head(batter, 1.5))
		sfx_later(0.2, "crowd_gasp")
		return
	sfx(pop_for(float(a.get("plate_mph", 60.0))), mitt)
	if absf(plate.x) > 1.2 or plate.y > 2.0:
		sfx_later(0.15, "ball_hits_backstop", Vector3(plate.x, 1.0, BACKSTOP_Z))
	elif outcome == "called_strike":
		var loc := PitchLocation.classify(plate.x, plate.y)
		if loc.halo:
			sfx_later(0.25, "corner_chime")


## The batter swings: the whoosh at the contact time, by how fast the pitch is.
func swing(pitch_mph: float, contact_in: float) -> void:
	var id := "bat_swing_slow" if pitch_mph < 55.0 else ("bat_swing_medium" if pitch_mph < 70.0 else "bat_swing_fast")
	sfx_later(maxf(contact_in - 0.12, 0.0), id, _head(batter, 1.1))
	if randf() < 0.3:
		sfx_later(maxf(contact_in - 0.1, 0.0), "batter_swing_grunt", _head(batter, 1.5), -4.0)


## The bat meets the ball: the crack, by how hard it was hit.
func contact(b: Dictionary, sim: Dictionary, at: Vector3) -> void:
	if b.kind == "foul tip":
		sfx("bat_foul_tip", at)
		return
	if b.get("bunt", false):
		sfx("bat_bunt_tap", at)
		return
	var ev := float(b.ev)
	sfx("bat_crack_sweet" if ev >= 92.0 else ("bat_crack_good" if ev >= 75.0 else "bat_crack_weak"), at)
	if ev < 62.0 and randf() < 0.05:
		sfx("bat_break", at, -2.0)                  # a jammed one: the bat splinters
	flip_next = bool(sim.home_run)
	if sim.home_run:
		sfx("home_run_crack", at, -3.0)
	elif float(sim.get("apex", 0.0)) > 14.0 and float(sim.get("distance", 0.0)) > 55.0 and sim.fair:
		sfx_later(0.6, "crowd_oooh")


# ------------------------------------------------------------------ the crowd's answer
func crowd_react(ev: Dictionary, game: GameState) -> void:
	if ev.is_empty():
		return
	var result := String(ev.get("result", ""))
	match result:
		"home_run":
			sfx_later(0.5, "crowd_roar_hr")
			sfx_later(0.8, "scoreboard_hr_horn")
			sfx_later(1.0, "pa_home_run_call")
			sfx_later(1.5, "music_home_run_fanfare", null, -4.0)
			sfx_later(2.5, "fireworks", null, -6.0)
		"triple":
			sfx_later(0.4, "crowd_cheer_big")
		"double":
			sfx_later(0.4, "crowd_cheer_medium")
		"single", "strikeout":
			sfx_later(0.4, "crowd_cheer_medium" if result == "strikeout" else "crowd_cheer_small")
			if result == "strikeout":
				sfx_later(0.5, "music_strikeout_sting", null, -6.0)
		"out", "fielders_choice", "sacrifice":
			sfx_later(0.4, "crowd_cheer_small", null, -4.0)
		"walk":
			sfx_later(0.3, "crowd_boo", null, -4.0)
		"error":
			sfx_later(0.4, "crowd_groan")
	if int(ev.get("runs", 0)) > 0 and result != "home_run":
		sfx_later(0.6, "scoreboard_run_chime")
		sfx_later(0.5, "crowd_cheer_medium" if int(ev.runs) < 2 else "crowd_cheer_big")
	if ev.get("half_over", false) and not ev.get("game_over", false):
		sfx_later(1.0, "organ_inning_tune" if randf() < 0.4 else "music_inning_change", null, -4.0)
		sfx_later(4.5, "pa_now_pitching")
		if int(ev.get("inning_ended", 0)) == 7 and not _stretch_done:
			_stretch_done = true
			sfx_later(3.0, "seventh_inning_stretch", null, -4.0)      # everybody up
	if ev.get("game_over", false) and game != null:
		var mine: bool = mode != null and (mode.human_pitcher or not mode.human_fielders.is_empty())     # you are the home side
		var won: bool = game.home_score > game.runs
		sfx_later(0.8, "pa_final_score")
		sfx_later(1.5, "crowd_applause_polite")
		sfx_later(2.0, "music_loss" if (mine and not won) else "music_victory", null, -4.0)


# ------------------------------------------------------------------ ambience, crowd bed and music
## While a menu is up the game does not run, but its sound still has to behave: the main menu has
## its own theme and no ballpark; a pause ducks the game's sound and stops anything that was mid-flight.
func update_menu(delta: float, screen: String) -> void:
	audio.set_paused(true)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	if screen == "pause":
		return
	audio.set_crowd_on(false)
	audio.set_stems(0.0, 0.0)
	for key in ["wind", "buzz", "dugout", "breath", "clap"]:
		audio.loop_off(key)
	audio.play_music("music_menu")


## The ambience, crowd bed and music follow the game: quiet and sparse early, louder with men on
## and a close game late, hushed and tense with two strikes in a tight ninth.
func update(delta: float, game: GameState) -> void:
	audio.set_paused(false)
	_clock += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	audio.set_crowd_on(true)
	audio.play_music("music_game_base")
	# The park around you.
	audio.loop_on("wind", "stadium_wind", -20.0)
	audio.loop_on("buzz", "light_tower_buzz", -28.0)
	audio.loop_on("dugout", "dugout_chatter", -24.0)
	if game == null:
		return
	# A new game: the ump and the PA open it.
	if not _game_start_said:
		_game_start_said = true
		sfx("ui_start_game", null, -4.0)
		sfx_later(0.8, "pa_welcome")
		umpire_says_later(2.6, "ump_play_ball")
	var runners := game.bases[0] != null or game.bases[1] != null or game.bases[2] != null
	var level := 0.22 + minf(game.inning, 9) * 0.015
	var on_scoring := game.bases[1] != null or game.bases[2] != null
	for i in 3:
		if game.bases[i] != null:
			level += 0.1
	var close: bool = absi(game.runs - game.home_score) <= 2
	var late: bool = game.inning >= 7
	if late and close:
		level += 0.18
	var tense: bool = late and close and game.strikes == 2 and game.outs >= 1
	audio.set_crowd(level, tense)
	audio.set_stems(1.0 if runners else 0.0, 1.0 if (late and close) else 0.0)
	# Clapping along when it is a rally; the organ calls a charge, at most every couple of minutes.
	var rally: bool = level > 0.65 and on_scoring and game.outs < 2
	if rally:
		audio.loop_on("clap", "crowd_clap_rhythm", -12.0)
		if _clock - _last_charge > 120.0:
			_last_charge = _clock
			sfx("organ_charge", null, -4.0)
	else:
		audio.loop_off("clap")
	# A tired arm: your own breathing.
	if mode != null and mode.human_pitcher and tired_source.is_valid():
		var tired := float(tired_source.call())
		if tired > 0.45:
			audio.loop_on("breath", "arm_tired_breath", -26.0 + (tired - 0.45) * 30.0)
		else:
			audio.loop_off("breath")
	# People in the stands, now and then.
	_crowd_noises()


func _crowd_noises() -> void:
	if randf() < 0.05:
		var a := randf_range(-1.0, 4.1)
		sfx("fan_shout", Vector3(cos(a) * 75.0, 6.0, sin(a) * 75.0 + 20.0), -8.0)
	if randf() < 0.02:
		var a2 := randf_range(-1.0, 4.1)
		sfx("vendor_shout", Vector3(cos(a2) * 55.0, 5.0, sin(a2) * 55.0 + 20.0), -8.0)
	if randf() < 0.012:
		var a3 := randf_range(-1.0, 4.1)
		sfx("seat_flip_clatter", Vector3(cos(a3) * 60.0, 5.0, sin(a3) * 60.0 + 20.0), -10.0)
