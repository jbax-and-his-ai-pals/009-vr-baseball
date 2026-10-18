class_name AIPitcher
extends RefCounted
## A computer pitcher driven by a Player's pitching ratings.
##
##   velocity   - how hard he throws (pitch speed)
##   command    - how close the ball lands to where he aimed (location scatter)
##   movement   - how much his pitches break (spin)
##   repertoire - which pitches he has
##
## It produces the same thing a human throw produces - a release position, velocity and spin -
## so the batter, the physics and the fielders cannot tell the difference. Pitch speeds are on
## this game's scale (a real 92 mph fastball is ~68 here), matching a human's throws in VR.

const GAME_SPEED := 0.74           # real mph -> this game's mph at a rating of 50

var player: Player
var rng := RandomNumberGenerator.new()
var last_kind := ""
var pitches_thrown := 0
## False for tests and probes that throw many pitches with one pitcher and want his fresh stuff.
var track_fatigue := true


func _init(p: Player = null) -> void:
	player = p if p != null else Player.new()
	rng.randomize()


func _choose_kind() -> String:
	var rep := player.repertoire
	if rep.is_empty():
		return "Fastball"
	# A fastball most of the time, the rest spread across his other pitches, never the same
	# off-speed pitch three times in a row.
	if rng.randf() < 0.5 or rep.size() == 1:
		return rep[0]
	var others := rep.slice(1)
	var k: String = others[rng.randi() % others.size()]
	if k == last_kind and rng.randf() < 0.6:
		k = rep[0]
	return k


## Where he is trying to throw it: usually the zone, sometimes just off the edge.
func _aim() -> Vector3:
	if rng.randf() < 0.70:
		return Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(0.55, 1.15), 0.0)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	match rng.randi() % 3:
		0:
			return Vector3(side * rng.randf_range(0.36, 0.5), rng.randf_range(0.5, 1.1), 0.0)
		1:
			return Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(1.32, 1.5), 0.0)
		_:
			return Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.2, 0.38), 0.0)


## One pitch. release is where the ball leaves his hand (the mound).
func next_pitch(release: Vector3) -> Dictionary:
	var kind := _choose_kind()
	last_kind = kind
	pitches_thrown += 1
	var def: Dictionary = PitchPhysics.CANNED[kind]
	# A tired arm loses speed and command.
	var tired := player.fatigue(pitches_thrown - 1) if track_fatigue else 0.0
	var mph: float = float(def.mph) * GAME_SPEED * Player.factor(player.velocity, 0.45) * rng.randf_range(0.98, 1.02) * (1.0 - 0.07 * tired)
	var spin: Vector3 = (def.rpm as Vector3) * PitchPhysics.RPM_TO_RADS * Player.factor(player.movement, 0.5)
	var aim := _aim()
	# Command is how far the ball ends up from the aim point: from ~0.5 m off to ~0.1 m.
	var sigma := lerpf(0.50, 0.10, clampf(player.command / 100.0, 0.0, 1.0)) * (1.0 + 0.55 * tired)
	var actual := aim + Vector3(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma * 0.85), 0.0)
	actual.y = clampf(actual.y, 0.05, 2.3)
	var vel := PitchPhysics.solve_aim(release, mph / PitchPhysics.MPS_TO_MPH, spin, actual)
	return {
		"kind": kind, "mph": mph, "release": release, "vel": vel, "spin": spin,
		"aim": aim, "actual": actual, "flutter_amp": 0.0, "flutter_seed": 0.0,
		"analysis": PitchPhysics.analyze(release, vel, spin),
	}
