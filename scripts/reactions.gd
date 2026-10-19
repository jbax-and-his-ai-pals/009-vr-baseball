class_name Reactions
extends RefCounted
## What you see, hear and feel when something happens in the game: the mitt's pop and the umpire's word when a pitch
## arrives, the crack and the flash when the bat meets the ball, the sound and the dust when a batted ball comes down,
## and the crowd, the dugouts and the controller when the game changes. It listens to the GameBus; the code that makes
## things happen does not know any of this exists.

var host                                    # the bullpen scene (untyped: its members are reached by name)


func wire(bus: GameBus) -> void:
	bus.pitch_arrived.connect(on_pitch_arrived)
	bus.contact_made.connect(on_contact_made)
	bus.ball_landed.connect(on_ball_landed)
	bus.event_happened.connect(on_event_happened)


## The mitt (or the dirt, or the batter), the umpire's call, the buzz in your hand.
func on_pitch_arrived(pitch: LivePitch, outcome: String) -> void:
	var a: Dictionary = pitch.analysis
	var plate: Vector3 = a.get("plate_pos", Vector3.ZERO)
	if host._sound != null:
		host._sound.pitch_arrives(a, outcome, plate)
	if a.get("reached", false) and outcome != "hit_by_pitch":
		# The mitt: felt less when it was in the dirt.
		host._haptics.play("pop", clampf(float(a.get("plate_mph", 60.0)) / 90.0, 0.0, 1.0) * (0.3 if plate.y < 0.18 else 1.0))
		if host._dust != null and plate.y >= 0.18 and float(a.get("plate_mph", 0.0)) >= 62.0 and not host.fielding.is_catcher():
			host._dust.flash(Vector3(clampf(plate.x, -1.0, 1.0), plate.y, -0.75), 0.22)       # the mitt's pop
	var third: bool = host._game.strikes >= 2              # this strike is the third: the call is the strikeout's
	match outcome:
		"ball":
			host._sound.umpire_says_later(0.4, "ump_ball", -8.0)
		"called_strike":
			host._crew.call_it("ump_strike", 0.3, 0.9, "" if third else "ump_strike")
		"swinging_strike":
			host._crew.call_it("ump_strike", 0.35, 0.7, "" if third else "ump_strike")
		"hit_by_pitch":
			host._crew.call_it("ump_point", 0.3, 1.0)


## The crack, the buzz, the flash where bat meets ball.
func on_contact_made(pitch: LivePitch) -> void:
	var b: Dictionary = pitch.bat
	if host._sound != null:
		host._sound.contact(b, pitch.sim, pitch.pos)
	host._haptics.play("contact", clampf(float(b.ev) / 110.0, 0.0, 1.0))
	if host._dust != null and float(b.ev) > 55.0:
		host._dust.flash(pitch.pos, clampf(float(b.ev) / 250.0, 0.15, 0.45))


## Where a batted ball came down: the thud, the wall, the stands, the dirt, the chalk, the grass.
func on_ball_landed(h: LiveHit) -> void:
	var sim: Dictionary = h.summary
	var bounce: Vector3 = sim.get("landing_pos", Vector3.ZERO)
	if sim.home_run:
		var fc: Vector3 = sim.get("fence_cross", bounce)
		host._sfx("ball_into_stands", fc)
		if absf(absf(fc.x) - fc.z) < 1.5:
			host._sfx_later(0.05, "ball_hits_pole", fc + Vector3(0.0, 2.0, 0.0))         # right down the line: off the pole
	elif sim.wall:
		host._sfx("ball_hits_wall", sim.get("rest_pos", bounce) as Vector3)
		host._sfx_later(0.12, "fence_rattle", sim.get("rest_pos", bounce) as Vector3)
	elif not sim.fair:
		host._sfx_later(0.1, "seat_flip_clatter", bounce, -4.0)               # a foul into the seats
	elif sim.fair:
		var dirt: bool = Vector2(bounce.x, bounce.z - 14.0).length() < 26.0
		host._sfx("ball_bounce_dirt" if dirt else "ball_bounce_grass", bounce, -3.0)
	if host._dust != null and not sim.home_run and Vector2(bounce.x, bounce.z - 14.0).length() < 26.0:
		host._dust.puff(Vector3(bounce.x, 0.0, bounce.z), 0.5, 3)           # it came down in the infield dirt
	elif host._dust != null and not sim.home_run and not sim.wall and bounce.z > 0.0:
		if host.foul_line_distance(bounce) < 0.6:
			host._dust.puff(Vector3(bounce.x, 0.0, bounce.z), 0.4, 4, DustPuffs.CHALK)      # it hit the chalk
		else:
			host._dust.puff(Vector3(bounce.x, 0.0, bounce.z), 0.3, 4, DustPuffs.GRASS, 0.5) # it kicked up the outfield grass


## The crowd, the dugouts and your hand answer a change in the game.
func on_event_happened(ev: Dictionary, _extra: Dictionary) -> void:
	if host._sound != null:
		host._sound.crowd_react(ev, host._game)
	if host._stadium != null:
		host._stadium.pulse(crowd_excitement(ev))
	if host._dugouts != null:
		host._dugouts.react_event(ev, "home" if host.roles.top_game != null else "away")
		if ev.get("game_over", false):
			host._dugouts.cheer("home" if host._game.home_score > host._game.runs else "away", "celebrate", true)
	match String(ev.get("result", "")):
		"home_run":
			host._haptics.play("rumble", 1.0)
		"strikeout":
			host._haptics.play("rumble", 0.3)


## How far the crowd gets to its feet for this event (0 for nothing special).
static func crowd_excitement(ev: Dictionary) -> float:
	match String(ev.get("result", "")):
		"home_run":
			return 1.0
		"triple", "double":
			return 0.5
		"strikeout":
			return 0.3
	return 0.6 if int(ev.get("runs", 0)) > 0 else 0.0
