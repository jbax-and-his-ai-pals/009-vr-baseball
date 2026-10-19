class_name PlateCrew
extends Node
## The two people behind the plate: the catcher, whose glove follows each pitch (and who blocks,
## chases a wild one, and pops up to throw on a steal), and the umpire, who rings up the calls and
## gets out of the way of a ball in play. They are Dolls; the scene gives them to us.
##
## What happens that the rest of the game may want to react to comes out as signals, so this
## script knows nothing about sound, dust or the rules:
##   blocked(at)           the catcher dropped to block a ball in the dirt
##   umpire_voice(id)      the umpire's call is out (the sound to play)
##   throw_started(at)     the catcher began a throw (the sound of it leaves his hand 0.42 s later)

signal blocked(at: Vector3)
signal umpire_voice(id: String)
signal throw_started(at: Vector3)

const MITT_Z := -0.85
const UMP_HOME_Z := -2.45
const CATCHER_HOME := Vector3(0.0, 0.0, -1.35)
const CATCH_READY := Vector3(0.05, 0.80, -0.92)

var catcher: Doll
var umpire: Doll
var _track := {}                          # the pitch the catcher is tracking
var _chase := {}                          # a wild pitch: he goes after it
var _visit := {}                          # a mound visit: he walks out, talks, and walks back
var _ump_queue: Array = []                # calls waiting for their moment
var _ump_goal := Vector3(0.0, 0.0, UMP_HOME_Z)
var _later: Array = []                    # {"t": seconds left, "fn": Callable}


func setup(catcher_doll: Doll, umpire_doll: Doll) -> void:
	catcher = catcher_doll
	umpire = umpire_doll


func is_chasing() -> bool:
	return not _chase.is_empty()


# ------------------------------------------------------------------ the catcher
## A pitch has been thrown: the catcher reads where it is going and gets his glove there (or
## does what he can if it is not catchable). `contact_time` is when the bat will hit it (99 if never).
func begin_pitch(analysis: Dictionary, contact_time: float) -> void:
	if catcher == null:
		return
	var reached: bool = analysis.get("reached", false)
	var plate: Vector3 = analysis.get("plate_pos", Vector3(0.0, 0.05, 0.0))
	var flight: float = float(analysis.get("time", 0.5)) if reached else 0.45
	var dirt := (not reached) or plate.y < 0.18
	var catchable := reached and absf(plate.x) <= 1.05 and plate.y >= 0.10 and plate.y <= 1.9
	_track = {"t": 0.0, "flight": flight, "catchable": catchable, "dirt": dirt,
		"target": Vector3(clampf(plate.x, -1.15, 1.15), clampf(plate.y, 0.06, 1.85), MITT_Z + 0.10),
		"body_x": clampf(plate.x * 0.55, -0.55, 0.55), "blocked": false, "contact_time": contact_time}
	_chase = {}
	catcher.locomotion = false
	catcher.set_squat(1.0, 0.2)
	_ump_goal = Vector3(0.0, 0.0, UMP_HOME_Z)


func update(delta: float) -> void:
	for i in range(_later.size() - 1, -1, -1):
		var l: Dictionary = _later[i]
		l.t -= delta
		if l.t <= 0.0:
			_later.remove_at(i)
			(l.fn as Callable).call()
	_update_catcher(delta)
	_update_umpire(delta)


func _update_catcher(delta: float) -> void:
	if catcher == null:
		return
	if not _visit.is_empty():
		_update_visit(delta)
		return
	if not _chase.is_empty():
		_update_chase(delta)
		return
	if _track.is_empty():
		# Ready position: glove out in front at the middle of the zone, body square.
		catcher.position = catcher.position.lerp(CATCHER_HOME, clampf(delta * 6.0, 0.0, 1.0))
		catcher.aim_glove(CATCH_READY, 0.85)
		return
	var tr := _track
	tr.t += delta
	var u := clampf(float(tr.t) / maxf(float(tr.flight), 0.05), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var tgt: Vector3 = CATCH_READY.lerp(tr.target, e)
	# He shifts his body toward the pitch.
	catcher.position.x = lerpf(0.0, float(tr.body_x), e)
	var after := float(tr.t) - float(tr.flight)
	if bool(tr.dirt) and u > 0.6 and not tr.blocked:
		tr.blocked = true
		catcher.play("block", 0.95)             # drop to the knees and smother it
		blocked.emit(catcher.position + Vector3(0.0, 0.0, 0.25))
	if after > 0.0 and tr.catchable and not tr.dirt:
		# The pop: the mitt gives a little as the ball hits it, then settles back to frame it.
		var k := clampf(after / 0.25, 0.0, 1.0)
		tgt.z -= 0.11 * sin(k * PI) * (1.0 - 0.5 * k)
		tgt = tgt.lerp(CATCH_READY, clampf((after - 0.35) / 0.6, 0.0, 1.0))
		catcher.position.x = lerpf(float(tr.body_x), 0.0, clampf((after - 0.35) / 0.6, 0.0, 1.0))
	elif after > 0.0 and not tr.catchable:
		tgt = tr.target                           # he got the glove out as far as he could
	if float(tr.t) >= float(tr.contact_time):
		catcher.set_squat(0.35, 0.25)            # a ball was hit: he rises to see it
		catcher.release_glove()
		_track = {}
		return
	catcher.aim_glove(tgt, 1.0)
	if after > 1.4:
		_track = {}


## A wild pitch or passed ball: he turns, runs back to the backstop for it, and returns.
func chase() -> void:
	if catcher == null:
		return
	_chase = {"t": 0.0}
	catcher.locomotion = true
	catcher.release_glove()
	catcher.set_squat(0.0, 0.2)


func _update_chase(delta: float) -> void:
	var c := _chase
	c.t += delta
	var t: float = c.t
	var wall := Vector3(0.6, 0.0, -6.6)
	var pos := CATCHER_HOME
	if t < 1.3:
		pos = CATCHER_HOME.lerp(wall, t / 1.3)                  # run back to it
	elif t < 1.9:
		pos = wall                                      # pick it up
	elif t < 3.4:
		pos = wall.lerp(CATCHER_HOME, (t - 1.9) / 1.5)          # and walk it back
	else:
		_chase = {}
		catcher.locomotion = false
		catcher.set_squat(1.0, 0.4)
		return
	var face := (wall - CATCHER_HOME) if t < 1.9 else (CATCHER_HOME - wall)
	catcher.position = pos
	catcher.rotation.y = atan2(face.x, face.z) if t < 3.2 else 0.0


## A visit to the mound: he walks out, they talk, he walks back (about five seconds).
func visit_mound() -> void:
	if catcher == null or not _visit.is_empty():
		return
	_visit = {"t": 0.0}
	_track = {}
	catcher.locomotion = true
	catcher.release_glove()
	catcher.set_squat(0.0, 0.2)


func is_visiting() -> bool:
	return not _visit.is_empty()


func _update_visit(delta: float) -> void:
	var v := _visit
	v.t += delta
	var t: float = v.t
	var mound := Vector3(0.0, 0.0, 15.7)
	var pos := CATCHER_HOME
	var face := mound - CATCHER_HOME
	if t < 1.7:
		pos = CATCHER_HOME.lerp(mound, t / 1.7)
	elif t < 3.2:
		pos = mound
	elif t < 4.9:
		pos = mound.lerp(CATCHER_HOME, (t - 3.2) / 1.7)
		face = CATCHER_HOME - mound
	else:
		_visit = {}
		catcher.locomotion = false
		catcher.set_squat(1.0, 0.4)
		catcher.rotation.y = 0.0
		return
	catcher.position = pos
	catcher.rotation.y = atan2(face.x, face.z) if (t < 1.7 or t >= 3.2) else atan2(0.0, -1.0)


## Up out of the squat and a quick throw down to the base, `seconds` from now (so the ball leaves
## his hand on time), then back down for the next pitch.
func pop_throw_in(seconds: float, glove: Vector3) -> void:
	_later.append({"t": maxf(seconds, 0.0), "fn": func(): _pop_throw(glove)})


func _pop_throw(glove: Vector3) -> void:
	if catcher == null:
		return
	throw_started.emit(catcher.global_position + Vector3(0.0, 1.4, 0.0))
	catcher.set_squat(0.0, 0.15)
	catcher.throw_to(glove, "overhand", 0.6)
	_later.append({"t": 1.1, "fn": func():
		if catcher != null and _chase.is_empty():
			catcher.set_squat(1.0, 0.4)})


# ------------------------------------------------------------------ the umpire
## A call after a short beat: a gesture (the clip) and what he says (`voice`: "?" picks the usual
## one for the clip, "" is silent).
func call_it(clip: String, delay: float = 0.3, seconds: float = 0.9, voice: String = "?") -> void:
	if voice == "?":
		voice = {"ump_strike": "ump_strike", "ump_out": "ump_out", "ump_safe": "ump_safe", "ump_foul": "ump_foul"}.get(clip, "")
	_ump_queue.append({"t": delay, "clip": clip, "dur": seconds, "voice": voice})


## He gives way to a ball in play (toward the side the ball went)...
func step_aside(spray: float) -> void:
	_ump_goal = Vector3(-1.5 if spray > 0.0 else 1.5, 0.0, UMP_HOME_Z + 0.4)


## ...and is back behind the plate.
func return_to_plate() -> void:
	_ump_goal = Vector3(0.0, 0.0, UMP_HOME_Z)


func _update_umpire(delta: float) -> void:
	if umpire == null:
		return
	for i in range(_ump_queue.size() - 1, -1, -1):
		var q: Dictionary = _ump_queue[i]
		q.t -= delta
		if q.t <= 0.0:
			umpire.play(String(q.clip), float(q.dur))
			if String(q.voice) != "":
				umpire_voice.emit(String(q.voice))
			_ump_queue.remove_at(i)
	var d := _ump_goal - umpire.position
	if d.length() > 0.02:
		umpire.position += d.normalized() * minf(d.length(), 2.2 * delta)
		umpire.rotation.y = atan2(d.x, d.z) if d.length() > 0.3 else 0.0
	else:
		umpire.rotation.y = 0.0
