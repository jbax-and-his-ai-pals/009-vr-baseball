extends Node3D
## Bullpen prototype: a mound, a plate, a catcher, and a throw you can feel.
## In a headset, hold the grip to pick up the ball, throw, and open your hand.
## You can grab the next ball immediately; the readout shows the last pitch to land.
## On desktop (no headset), press Space to throw canned pitches; run with
## `-- --demo` to throw them automatically.

enum ReleaseMode { GRIP_RELEASE, AUTO_PEAK }

## PURE: raw physics from your hand, no help. HAND_ASSIST: ball goes where the hand
## pointed (unstable, kept for comparison). FUNNEL: the direction your hand travelled
## in the second before release picks the location, but how far you miss the center is
## scaled down, so normal throwing scatter lands in or near the zone.
enum AimMode { PURE, HAND_ASSIST, FUNNEL }

## RAW: controller rotation straight to ball spin (every hard throw curves). WRIST_MODEL:
## technique decides the pitch: a plain throw is a fastball; extra wrist snap bends it down
## (curve), a doorknob twist breaks it sideways (slider), a low arm slot runs it arm-side
## and sinks it (sinker), a stiff wrist kills the spin (knuckleball), a slow throw is a
## changeup. See scripts/wrist_model.gd.
enum SpinMode { RAW, WRIST_MODEL }

@export var release_mode: ReleaseMode = ReleaseMode.GRIP_RELEASE
## Who controls what. Pitching: you pitch against AI batters and fielders. Spectate: an AI pitcher
## throws and you watch. (Fielding and Hitting exist as modes but are not built yet.)
## Open the main menu when the game starts (only when launched with no debug flags, or --menu).
@export var menu_on_start := true
@export_enum("Pitching", "Spectate", "Fielding", "Hitting") var game_mode_name: String = "Pitching"
## The position you play in Fielding mode (3 first base ... 9 right field; 6 is shortstop).
@export_range(1, 9, 1) var fielding_position := 6
## Game: a nine-inning game against a nine-man lineup, with the count, outs and runners.
## Practice: one batter you choose (Y / P cycles them), the count still counts but nobody new comes up.
@export_enum("Game", "Practice") var lineup_mode: String = "Game"
## Innings in a Game.
@export_range(1, 9, 1) var game_innings := 9
## Seconds between AI pitches in Spectate mode (the next waits for the play to finish).
@export_range(1.0, 15.0, 0.5) var spectate_interval := 4.0
## Quest-only render tuning: request 90 Hz, foveated rendering, variable-rate shading, and let the
## quality governor change render resolution. OFF by default. It is not needed over Virtual Desktop
## and a headset test went black right after start-up with it enabled; turn it on only for a
## standalone build and test it there.
@export var xr_tuning := false
## Who is batting. Left controller Y (or P on desktop) cycles through them.
@export_enum("Little Leaguer", "Rookie", "Contact Hitter", "Slugger", "All-Star", "MVP") var batter_profile: String = "Contact Hitter"
@export var spin_mode: SpinMode = SpinMode.WRIST_MODEL
## WRIST_MODEL: multiplies how far your technique differs from your usual throw.
## Raise it if your wrist moves little; lower it if pitches get too wild.
@export_range(0.5, 4.0, 0.05) var technique_gain := 1.0
## WRIST_MODEL: backspin on a plain throw, in rpm.
@export_range(0.0, 3000.0, 50.0) var fastball_backspin_rpm := 1700.0
## Left controller X button cycles this label, which is saved with every throw so
## differently-thrown pitches can be analyzed later.
@export var practice_tags: PackedStringArray = ["normal", "big snap", "wrist twist", "low arm", "shot put", "slow", "gyro roll"]
@export var aim_mode: AimMode = AimMode.FUNNEL
## Scales controller speed into ball speed.
@export_range(0.5, 5.0, 0.05) var velocity_gain := 2.4
## HAND_ASSIST only: 0 = pure physics, 1 = ball goes where the hand pointed.
@export_range(0.0, 1.0, 0.05) var aim_assist := 1.0
## FUNNEL: meters at the plate for each standard deviation of YOUR OWN aim scatter. The game
## learns how consistent you are, so an erratic thrower and a precise one both end up
## with the same spread; deliberate aim shifts bigger than your noise still move the ball.
## Raise for a harder, more skill-dependent game; lower for more forgiving.
@export_range(0.0, 1.0, 0.01) var funnel_spread_x := 0.40
@export_range(0.0, 1.0, 0.01) var funnel_spread_y := 0.30
## FUNNEL: how fast the learned usual aim and scatter follow your throws (0-1 per throw)
## once the first few throws have calibrated them.
@export_range(0.0, 1.0, 0.01) var aim_learn_rate := 0.08
## Hard cap on release speed, mph.
@export_range(60.0, 120.0, 1.0) var max_mph := 100.0
## Scales controller rotation into ball spin. A wrist snap is far slower than 2400 rpm.
@export_range(1.0, 20.0, 0.5) var spin_gain := 6.0
## Seconds before the detected grip-open that velocity is measured. The grip drops
## 1.0 -> 0.0 within ~15 ms, so this stays small.
@export_range(0.0, 0.1, 0.005) var velocity_latency := 0.015
## Same for spin (kept at its original value so curveballs feel unchanged).
@export_range(0.0, 0.1, 0.005) var spin_latency := 0.04
@export var throwing_hand: StringName = &"right_hand"

const LINGER_TIME := 1.5
const MAX_PITCHES := 8
const MITT_Z := -0.85
const BACKSTOP_Z := -8.0
## Assisted pitches never leave the hand slower than this (m/s), so a feeble
## throw does not become a 45-degree rainbow.
## FUNNEL reads the hand's travel direction between these times before release.
## Chosen from recorded throws: much steadier than the instant of release, where the
## velocity direction swings ~1 degree per ms.
const ZONE_CENTER := HumanPitcher.ZONE_CENTER
## Releases slower than this (m/s of hand speed) are not throws: the ball just drops.

var _xr_active := false
var _demo := false
var _demo_timer := 1.0
var _demo_interval := 0.35
var _camera: Camera3D
var _hand: XRController3D
var _human := HumanPitcher.new()          # you throwing: the controller, the release, your usual aim
var _detector: ThrowDetector:
	get: return _human.detector
## Learned usual aim direction (degrees right / up of straight at the plate) and how much
## it scatters. Start from a recorded player; the first throws calibrate them quickly.
var _aim_mu: Vector2:
	get: return _human.aim_mu
var _off_hand: XRController3D
var _tag_index := 0
var _tag_pressed := false
var _held: bool:
	get: return _human.held
	set(v): _human.held = v
var _zone_markers: ZoneMarkers
var _home_order := 0
var _catcher: Doll
var _umpire: Doll
var _base_ump_dolls: Array[Doll] = []
var _director := PlayDirector.new()   # puts a play on the field: fielders, ball, runners, callouts
var _dugouts: Dugouts               # teammates at the rails and the coaches
var _base_umps: BaseUmpires   # the three umpires at the bases
var _crew: PlateCrew          # drives the catcher and the umpire
var _props: FieldProps        # dust, dropped bats, and calls that wait for their moment
var _dust: DustPuffs          # _props.dust
var _profile := PlayerProfile.load_from()   # lifetime stats, leaderboards, challenge results
var _career: Career = Career.load_from()    # the saved season, if any
var _career_game := false                    # this game is the next start of the career
var _call_label: Label3D                    # the umpire's call as words, above the plate
var _call_label_until := 0.0
var _bat_call := ""                         # a play called with this pitch: "squeeze" or "hit_and_run" ("" for none)
var _daily := 0                            # a daily game: the day it belongs to (0 for an ordinary game)
var _haptics := Haptics.new()     # controller vibration
var _sound: SoundDirector
var _audio: AudioManager          # _sound.audio, for the loops that follow the ball
# The running game.
var _delivery_start: float:               # when your motion began (seconds), -1 if it has not
	get: return _human.delivery_start
var _last_delivery := 0.9            # how long the last delivery took, motion start to release
var _stats := StatsTracker.new()
var _batter: CartoonBatter
var _presenter: BatterPresenter           # the batter's walk-on, box, bat; owns the figure
var _batter_home: Transform3D:             # where he stands in his box
	get: return _presenter.home if _presenter != null else Transform3D.IDENTITY
	set(v):
		if _presenter != null:
			_presenter.home = v
var _walk_on: Dictionary:                  # the next batter's walk to the box
	get: return _presenter.walk if _presenter != null else {}
	set(v):
		if _presenter != null:
			_presenter.walk = v
var _leavers: Array[Node3D] = []   # figures that walk back to the dugout after an out
var _stadium: Stadium
var _xr_interface: XRInterface
var _governor := PerfGovernor.new()
var _perf_log := false
var _perf_timer := 0.0
var _heartbeat_timer := 0.0
var _batter_ai: BatterAI
var _profile_pressed := false
var _mode := GameMode.pitching()
var _home: Team                    # the defense (and the AI pitcher)
var _batting: Team                 # the practice squad at the plate
var _away: Team                    # the lineup that bats in a Game
var _batter_player: Player
var _ai_pitcher: AIPitcher
var _spectate_timer := 2.0
var _defense: Defense
var _game: GameState
var _base_runners: Array[Node3D] = []
var _field_nodes := {}            # fielder number -> Node3D
var _runner: Node3D
var _play_labels: Array[Label3D] = []
var _run_rng := RandomNumberGenerator.new()
var _fx_rng := RandomNumberGenerator.new()   # presentation choices only: never shares a stream with the rules
var fielding := FieldingControl.new()                 # human fielding, catching and the catcher's throw
var roles := RoleSwitch.new()                 # pitch the top halves, bat the bottom halves
var plays := RunnerPlays.new()                 # steals, throws over, rundowns, balks and the balls in the air that are not pitches
var acts := Activities.new()                 # derby, drills, challenges and the pitching lesson
var manager := Manager.new()                 # the pitcher's side of managing: signs, gestures, visits, changes, the infield alignment
var hud := HudText.new()                 # the stat boards, the scoreboard feed, notices and the words of a report
var slog := SessionRecorder.new()                 # the session log: events, snapshots, frame spikes, your throws
var results := GameResults.new()                 # what a finished game is worth: lines, the book, the career
var world := WorldBuilder.new()                 # builds the park, the people and the headset rig
var flight := PitchFlight.new()                 # pitches and batted balls: launch, flight, landing, contact, the play
var flow := GameFlow.new()                 # the batter's turn, the play's end and what follows an event
var menus := MenuHost.new()                 # opening, closing and answering the menus
var bus := GameBus.new()                 # what happens in the game, announced for whoever cares (see GameBus)
var replay := HighlightReplay.new()                 # a ghost replay of a big hit
var reactions := Reactions.new()                 # what you see, hear and feel about it
var _game_seed := 0
var forced_seed := -1                       # tests and replays: use this seed (the --seed= flag does the same)
var _origin: XROrigin3D
var _settings := Settings.new()
var _menu: GameMenu
var _config := GameConfig.new()
var _catch_radius := HumanFielding.CATCH_RADIUS
var _throw_cone := HumanFielding.THROW_CONE_DEG
var _game_time := 0.0
const SWING_RECOVERY := 0.75


func _init() -> void:
	reactions.host = self
	replay.host = self
	_wire_bus()
	menus.host = self
	flow.host = self
	flight.host = self
	world.host = self
	results.host = self
	slog.host = self
	hud.host = self
	manager.host = self
	acts.host = self
	plays.host = self
	roles.host = self
	fielding.host = self
	# --- directors are wired to the scene here


## Who listens to what (see GameBus). The code that makes things happen does not know these connections exist.
func _wire_bus() -> void:
	reactions.wire(bus)
	bus.pitch_arrived.connect(acts.on_pitch_arrived)
	bus.pitch_resolved.connect(acts.on_pitch_resolved)
	bus.pitch_resolved.connect(manager.on_pitch_resolved)
	bus.contact_made.connect(results.on_contact_made)
	bus.event_settled.connect(acts.on_event_settled)
	bus.event_settled.connect(manager.on_event_settled)
	bus.game_over.connect(results.on_game_over)
	bus.game_over.connect(slog.on_game_over)
	bus.half_over.connect(slog.on_half_over)
	bus.half_over.connect(hud.on_half_over)
	bus.play_announced.connect(replay.on_play_announced)
	bus.play_announced.connect(slog.on_play_announced)


func _ready() -> void:
	if ThrowLogger.override_path != "":
		_profile.save_path = "user://test_profile.json"      # a test run never touches the player's saved history
		if _career != null:
			_career.save_path = "user://test_career.json"
	_human.knobs = self
	_director.leads = plays.leads          # the scene asks where a runner stands before the world is built
	_demo = "--demo" in OS.get_cmdline_user_args()
	_settings = Settings.new() if "--no-settings" in OS.get_cmdline_user_args() else Settings.load_from()
	apply_settings(_settings)
	if throwing_hand == &"left_hand":
		_human.mirror_aim()          # a left-hander's usual aim starts on the other side
	# Did the menu (before a reload) ask for a particular game, or for the menu itself?
	var want_menu := false
	var user_args := OS.get_cmdline_user_args()
	if Session.pending != null:
		apply_config(Session.pending)
		Session.pending = null
	elif Session.show_menu:
		want_menu = true
	elif menu_on_start and (user_args.is_empty() or "--menu" in user_args):
		want_menu = true
	Session.show_menu = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			game_mode_name = a.substr(7)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--field-pos="):
			fielding_position = clampi(int(a.substr(12)), 1, 9)
	fielding.auto_field = "--auto-field" in OS.get_cmdline_user_args()
	apply_config(_current_config())
	for pa in OS.get_cmdline_user_args():
		if pa.begins_with("--park="):
			Park.current = Park.by_id(pa.substr(7))          # debug: play in this park
	_mode = GameMode.by_name(game_mode_name)
	if not _mode.human_fielders.is_empty():
		_mode = GameMode.fielding(fielding_position)
	if not _mode.supported:
		push_warning("Game mode '%s' is not built yet; using Pitching." % _mode.name)
		_mode = GameMode.pitching()
	if _career_game:
		_home = _career.user_team()
		_away = _career.opponent_team()
		game_innings = _career.innings_per_start
	else:
		_home = Team.generate("Home", 55.0, 7)
		_away = Team.generate("Away", 52.0, 14)
		if _daily > 0:
			_away = Team.generate("Away", 46.0 + float(_daily % 13), _daily * 31 + 5)      # the day's visitors, the same for everyone
		_away.jersey = Color(0.84, 0.16, 0.18)          # the visitors wear red (the runners and the batter already do)
		_away.pants = Color(0.95, 0.95, 0.97)
		_away.cap = Color(0.12, 0.17, 0.50)
	_batting = Team.archetype_roster()
	_defense = Defense.from_team(_home)
	_ai_pitcher = AIPitcher.new(_home.player_at(1))
	_new_game()
	_game_seed = forced_seed if forced_seed >= 0 else randi()
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--seed="):
			_game_seed = int(sa.substr(7))
	_run_rng.seed = _game_seed
	_fx_rng.seed = _game_seed ^ 0x5EED
	world.build_world()
	world.setup_xr()
	_haptics.hand = _hand
	_haptics.off_hand = _off_hand
	_haptics.set_level(_settings.haptics)
	PitchLocation.colorblind = _settings.colorblind
	if _mode.human_batter:
		_ensure_bat_view()
	menus.build_menu(want_menu)
	_sound = SoundDirector.new()
	add_child(_sound)
	_audio = _sound.audio
	_sound.mode = _mode
	_crew = PlateCrew.new()
	add_child(_crew)
	_crew.setup(_catcher, _umpire)
	_crew.blocked.connect(func(at: Vector3):
		if _dust:
			_dust.puff(at, 0.6, 3)
		_sfx_later(0.1, "ball_hits_gear", at + Vector3(0.0, 0.5, -0.05)))
	_director.defense = _defense
	_director.field_nodes = _field_nodes
	_director.runner = _runner
	_director.base_runners = _base_runners
	_director.leavers = _leavers
	_director.play_labels = _play_labels
	_director.leads = plays.leads
	_director.presenter = _presenter
	_director.crew = _crew
	_base_umps = BaseUmpires.new()
	add_child(_base_umps)
	_base_umps.setup(_base_ump_dolls[0], _base_ump_dolls[1], _base_ump_dolls[2])
	_base_umps.umpire_voice.connect(func(id: String, at: Vector3): _sound.umpire_says_at(id, at))
	_dugouts = Dugouts.new()
	_dugouts.setup(self, _home, _away, Callable(world, "doll_style"))
	_sound.umpire_spoke.connect(manager.on_umpire_spoke)
	_director.base_umps = _base_umps
	_director.props = _props
	_director.sound = _sound
	_director.human_num = Callable(fielding, "human_num")
	_director.refresh_base_runners = Callable(flow, "refresh_base_runners")
	_director.batter_hidden.connect(flow.on_batter_hidden)
	_crew.umpire_voice.connect(func(id: String): _sound.umpire_says(id))
	_crew.throw_started.connect(func(at: Vector3): _sfx_later(0.42, "throw_whoosh", at))
	_sound.umpire = _umpire
	_sound.batter = _batter
	_presenter.walk_step.connect(_on_walk_step)
	_presenter.arrived.connect(flow.on_batter_arrived)
	_sound.tired_source = Callable(manager, "arm_fatigue")
	_audio.apply_volumes(_settings.volumes)
	_menu.ui_sound.connect(func(id: String): _sfx(id))
	_menu.ui_haptic.connect(func(c: XRController3D, ev: String): _haptics.play_on(c, ev))
	GameLog.start({"mode": game_mode_name, "activity": lineup_mode, "innings": game_innings, "position": fielding_position,
		"assist": _settings.assist, "hand": _settings.hand, "settings": _settings.to_dict(), "xr": _xr_active,
		"args": OS.get_cmdline_user_args(), "throw_log": ThrowLogger.override_path, "menu_open": want_menu,
		"seed": _game_seed, "home_lineup": _home.lineup.map(func(x): return x.name), "away_lineup": _away.lineup.map(func(x): return x.name),
		"funnel": [funnel_spread_x, funnel_spread_y], "velocity_gain": velocity_gain})
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			batter_profile = a.substr(10)
		if a.begins_with("--demo-interval="):
			_demo_interval = float(a.substr(16))
	_batter_ai = BatterAI.new(BatterProfile.by_name(batter_profile))
	_batter_player = _player_named(batter_profile)
	_seed_rules()
	flow.sync_batter()
	if not _xr_active:
		_governor.set_refresh_rate(60.0)  # a desktop window is judged against 60 Hz, not a headset's 90
	if _props != null and (Park.now().wind.length() >= 1.0 or Park.now().air < 0.95) and not acts.derby:
		_props.later(2.5, func():
			var bits: Array = [Park.now().name]
			if Park.now().air < 0.95:
				bits.append("thin air")
			if Park.now().wind.length() >= 1.0:
				bits.append(Park.now().wind_text())
			hud.show_notice(", ".join(bits), false))
	if "--excite" in OS.get_cmdline_user_args():
		_stadium.pulse(1.0)                  # debug: the crowd on its feet (it settles over about five seconds)
	_perf_log = "--perf" in OS.get_cmdline_user_args()
	_governor.enabled = not ("--no-governor" in OS.get_cmdline_user_args())
	_governor.level_changed.connect(_on_quality_changed)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hit-test="):
			# Debug: a batted ball with a given exit velocity (mph), launch and spray (deg).
			var parts := a.substr(11).split(":")
			var spec := [float(parts[0]), float(parts[1]), float(parts[2])]
			get_tree().create_timer(0.5).timeout.connect(func(): flight.debug_hit(spec[0], spec[1], spec[2]))
	if "--contact-demo" in OS.get_cmdline_user_args():
		# Debug: one perfectly timed swing at one pitch, to inspect bat-ball contact.
		_batter_ai.debug_perfect = true
		_batter_ai.profile = BatterProfile.by_name("MVP")
		get_tree().create_timer(0.4).timeout.connect(func(): flight.debug_throw())
	if "--swing-test" in OS.get_cmdline_user_args():
		# Debug: swing once, 0.5 s in, so the animation can be inspected without a pitch.
		get_tree().create_timer(0.3).timeout.connect(func(): _batter.swing_to(Vector3(0.0, 0.9, 0.2), 0.3))
	if "--doll-demo" in OS.get_cmdline_user_args():
		world.spawn_doll_demo()
	hud.set_hud_idle()
	manager.refresh_sign()


## The half inning you do not pitch: your team bats against their pitcher, played out of sight.
func _simulate_bottom_half(inning: int) -> Dictionary:
	var their_pitcher: Player = _away.player_at(1)
	var r := HalfInningSim.play(_home.lineup, _home_order, their_pitcher, _away, _game_seed + 9000 + inning * 17)
	_home_order = int(r.next_index)
	return {"runs": int(r.runs), "hits": int(r.hits)}


## Sound lives in SoundDirector (scripts/sound_director.gd). These are the short names used around the scene.
func _sfx(id: String, at: Variant = null, db: float = 0.0) -> void:
	if _sound != null:
		_sound.sfx(id, at, db)


func _sfx_later(seconds: float, id: String, at: Variant = null, db: float = 0.0) -> void:
	if _sound != null:
		_sound.sfx_later(seconds, id, at, db)


func _on_footstep(at: Vector3) -> void:
	if _sound != null:
		_sound.footstep(at)


func _on_walk_step(at: Vector3) -> void:
	if _sound != null:
		_sound.walk_step(at)


# ------------------------------------------------------------------ the running game
func _runners_on() -> bool:
	return _game != null and (_game.bases[0] != null or _game.bases[1] != null or _game.bases[2] != null)


# ------------------------------------------------------------------ session log (see GameLog)


## An AI pitcher throws when the previous play is over and the interval has passed.
func _run_ai_pitcher(delta: float) -> void:
	_spectate_timer -= delta
	if _spectate_timer > 0.0:
		return
	var play_running: bool = flight.play_hit != null and not flight.play_hit.result_shown
	if play_running or not flow.batter_ready:
		return
	manager.maybe_change_pitcher()
	# The manager's call: with first base open and a dangerous hitter up, put him on.
	if manager.wants_intentional_walk():
		manager.issue_intentional_walk()
		return
	if plays.ai_throw_over():
		return
	_spectate_timer = spectate_interval
	var release := Vector3(0.0, PitchPhysics.MOUND_H + 1.85, PitchPhysics.MOUND_Z - 1.7)
	_last_delivery = clampf(_run_rng.randfn(1.05, 0.15) - 0.2 * (_ai_pitcher.player.command - 50.0) / 50.0, 0.7, 1.5)
	plays.on_delivery_start()
	var pitch := acts.derby_pitch(release) if acts.derby else _ai_pitcher.next_pitch(release)
	var mound_man = _field_nodes.get(1)
	if mound_man is Doll:
		# He winds up and throws: the ball leaves his hand as the arm comes through.
		(mound_man as Doll).throw_to(Vector3(0.0, 1.0, 0.0), "overhand", 0.75)
		_props.later(0.45, func():
			if _game != null and not _game.over and flow.batter_ready:
				flight.launch(release, pitch.vel, pitch.spin, pitch.kind))
	else:
		flight.launch(release, pitch.vel, pitch.spin, pitch.kind)


func _on_quality_changed(level: int) -> void:
	_stadium.set_quality(level)
	if _xr_interface and xr_tuning:
		_xr_interface.set("render_target_size_multiplier", PerfGovernor.render_scale(level))
	print("PerfGovernor: quality level %d (frame %.1f ms, target %.1f ms)" % [level, _governor.ema_ms, _governor.target_ms])


func _process(delta: float) -> void:
	menus.poll_menu_button()
	if _menu != null and _menu.is_open():
		if _sound != null:
			_sound.update_menu(delta, _menu.model.screen())
		return       # the game waits while a menu is up
	_game_time += delta
	replay.update(delta)
	if _call_label != null and _call_label.visible and _game_time > _call_label_until:
		_call_label.visible = false
	manager.seat_check()
	if _mode.human_batter and _batter != null:
		_batter.visible = false              # you are the batter
	flight.update_human_bat(Time.get_ticks_usec() / 1_000_000.0)
	if fielding.is_catcher():
		fielding.sample_glove(_game_time)
		fielding.poll_catcher_throw(delta, _game_time)
	manager.poll_gestures(delta)
	acts.run_drill(delta)
	if manager.visit_timer > 0.0:
		manager.visit_timer -= delta
	_crew.update(delta)
	_base_umps.update(delta)
	_props.update(delta)
	if _sound != null:
		_sound.update(delta, _game)
	slog.log_frame(delta)
	if _xr_active and _hand != null and _hand.get_is_active():
		var flag := _hand.is_button_pressed("by_button")
		if flag and not slog.mark_pressed:
			slog.mark_moment()
		slog.mark_pressed = flag
	flow.update_batter_lifecycle(delta)
	roles.update_roles(delta)
	if flow.game_over_timer > 0.0:
		flow.game_over_timer -= delta
		if flow.game_over_timer <= 0.0:
			_new_game()
			flow.sync_batter()
			hud.last_report = "New game."
			hud.refresh_hud()
	_governor.update(delta)
	if _xr_active:
		_heartbeat_timer += delta
		if _heartbeat_timer >= 5.0:
			_heartbeat_timer = 0.0
			print("XR heartbeat: %.1f ms | level %d | held %s | pitches %d | hits %d | head %s" % [
				_governor.ema_ms, _governor.level, _held, flight.pitches.size(), flight.hits.size(),
				_camera.global_position if _camera else "n/a"])
	if _perf_log:
		_perf_timer += delta
		if _perf_timer >= 1.0:
			_perf_timer = 0.0
			print("perf: %.1f ms | %d draw calls | %dk tris | level %d" % [
				_governor.ema_ms, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), _governor.level])
	var now := Time.get_ticks_usec() / 1_000_000.0
	if not _mode.human_pitcher:
		_run_ai_pitcher(delta)
	if hud.notice != "" and now > hud.notice_until:
		hud.notice = ""
		hud.refresh_hud()
	if _xr_active and _hand:
		_poll_tag()
		if _mode.human_pitcher:
			flight.poll_hand(now)
		if not _mode.human_fielders.is_empty():
			fielding.move_fielder(delta)
		if not _mode.human_fielders.is_empty() or _mode.human_pitcher:
			fielding.poll_fielding(now)
	elif _demo:
		_demo_timer -= delta
		if _demo_timer <= 0.0 and flow.batter_ready:
			_demo_timer = _demo_interval
			flight.debug_throw()
	for i in range(flight.hits.size() - 1, -1, -1):
		var h := flight.hits[i]
		flight.update_hit(h, delta)
		if h.done and h.linger <= 0.0:
			flight.free_hit(h)
			flight.hits.remove_at(i)
	for i in range(flight.pitches.size() - 1, -1, -1):
		var pitch := flight.pitches[i]
		if not pitch.landed:
			flight.update_flight(pitch, delta)
		else:
			pitch.linger -= delta
			if pitch.linger <= 0.0:
				flight.free_pitch(pitch)
				flight.pitches.remove_at(i)


func _unhandled_input(event: InputEvent) -> void:
	if not _xr_active and event.is_action_pressed("ui_accept"):
		flight.debug_throw()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		_cycle_profile()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		menus.toggle_pause()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		slog.mark_moment()


func _poll_tag() -> void:
	if _off_hand == null or not _off_hand.get_is_active() or practice_tags.is_empty():
		return
	var pressed := _off_hand.is_button_pressed("ax_button")
	if pressed and not _tag_pressed:
		_tag_index = (_tag_index + 1) % practice_tags.size()
		hud.refresh_hud()
	_tag_pressed = pressed
	var y_pressed := _off_hand.is_button_pressed("by_button")
	if y_pressed and not _profile_pressed:
		_cycle_profile()
	_profile_pressed = y_pressed


## Player preferences: handedness and the assist preset (funnel, glove, throw cone).
func apply_settings(s: Settings) -> void:
	throwing_hand = s.throwing_hand_name()
	apply_assist(s)


## The assist preset alone, which is safe to change in the middle of a game.
func apply_assist(s: Settings) -> void:
	_settings = s
	var a := s.assist_values()
	funnel_spread_x = a.funnel_x
	funnel_spread_y = a.funnel_y
	aim_assist = a.aim_assist
	_catch_radius = a.catch_radius
	_throw_cone = a.throw_cone


## The game as the exports and flags currently describe it.
func _current_config() -> GameConfig:
	var c := GameConfig.new()
	c.mode = game_mode_name
	c.position = fielding_position
	c.innings = game_innings
	c.batter = batter_profile
	c.assist = _settings.assist
	c.activity = "Game" if lineup_mode == "Game" else "Practice"
	c.scenario = acts.scenario_id
	c.career = _career_game
	c.two_way = roles.two_way
	c.daily = _daily
	c.park = Park.now().id
	if _career_game:
		c.innings = _career.innings_per_start
	return c.normalized()


## Set up the game a menu (or a flag) asked for.
func apply_config(c: GameConfig) -> void:
	c = c.normalized()
	_config = c
	game_mode_name = c.mode
	fielding_position = c.position
	game_innings = c.innings
	batter_profile = c.batter
	lineup_mode = "Game" if c.activity == "Game" else "Practice"
	acts.scenario_id = c.scenario
	acts.drill = c.activity == "Drill" and not acts.mode_is_not_fielding(c)
	acts.derby = c.activity == "Derby" and c.mode == "Hitting"
	acts.tutorial = Tutorial.new(_settings.tutorial_step) if c.tutorial else null
	roles.two_way = c.two_way
	_daily = c.daily
	if _daily > 0:
		forced_seed = GameConfig.daily_seed(_daily)
	Park.current = Park.by_id(_career.game_park() if c.career and _career != null else c.park)
	if _daily > 0:
		Park.now().wind = GameConfig.daily_wind(_daily)        # the day's weather
	_career_game = c.career and _career != null and not _career.is_over()


# ------------------------------------------------------------------ menus


func _ensure_bat_view() -> void:
	if flight.bat_view != null:
		return
	flight.bat_view = MeshInstance3D.new()          # the bat in your hand
	flight.bat_view.mesh = Figure.bat_mesh()
	flight.bat_view.material_override = MeshMerger.vertex_color_material()
	add_child(flight.bat_view)


## Every random stream of the rules comes from the game seed, so a seed replays a game exactly.
func _seed_rules() -> void:
	_ai_pitcher.rng.seed = _game_seed ^ 0xA17C
	_batter_ai.rng.seed = _game_seed ^ 0xBA77
	_defense.rng.seed = _game_seed ^ 0xDEF5
	_game.rng.seed = _game_seed ^ 0x6A3E


func _new_game() -> void:
	var order: Array[Player] = _away.lineup
	_game = GameState.new(order, game_innings)
	if _game_seed != 0:
		_game.rng.seed = _run_rng.randi()
	_game.allow_extra = true
	_game.bottom_live = roles.two_way and _mode.human_pitcher
	roles.top_game = null
	roles.bottom_end_timer = -1.0
	roles.bat_log = {"ab": 0, "h": 0, "hr": 0, "rbi": 0, "bb": 0, "k": 0}
	_game.bottom_sim = Callable(self, "_simulate_bottom_half")
	_home_order = 0
	if _sound != null:
		_sound.new_game()
	results.game_recorded = false
	fielding.fld = {"chances": 0, "caught": 0, "missed": 0, "errors": 0, "assists": 0, "frames": 0, "lost": 0, "blocks": 0, "passed": 0, "covers": 0, "uncovered": 0}
	acts.derby_outs = 0
	acts.derby_hr = 0
	acts.derby_done = false
	acts.drill_left = 10
	acts.drill_started = 0
	acts.drill_timer = 3.0
	acts.drill_done = false
	manager.sign_tally = {"called": 0, "perfect": 0, "type": 0, "loc": 0, "shaken": 0}
	manager.sign = {}
	manager.visit_used = false
	manager.visit_timer = 0.0
	manager.fatigue_credit = 0
	manager.user_left = false
	manager.left_line = {}
	_stats.reset()
	if _zone_markers:
		_zone_markers.clear()
	flow.aux_play = {}
	_walk_on = {}
	flow.batter_ready = true
	if _batter != null:
		_batter.visible = true
		_batter.transform = _batter_home
	if lineup_mode == "Game":
		for pl in order:
			_stats.add_batter(pl.name)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--situation="):
			# Debug: --situation=outs:1,bases:101,count:2-1,inning:4
			for part in a.substr(12).split(","):
				var kv := part.split(":")
				if kv.size() != 2:
					continue
				match kv[0]:
					"outs":
						_game.outs = int(kv[1])
					"inning":
						_game.inning = int(kv[1])
					"bases":
						for i in 3:
							_game.bases[i] = true if kv[1].substr(i, 1) == "1" else null
					"count":
						var c := kv[1].split("-")
						_game.balls = int(c[0])
						_game.strikes = int(c[1])
	acts.scenario = Scenario.by_id(acts.scenario_id) if acts.scenario_id != "" else null
	acts.scenario_done = false
	if acts.scenario != null:
		acts.scenario.apply(_game, _away.lineup)
		hud.show_notice("%s: %s" % [acts.scenario.title, acts.scenario.goal], true)
	flow.game_over_timer = -1.0
	flow.refresh_base_runners()
	hud.refresh_scoreboard()


func _player_named(n: String) -> Player:
	for p in _batting.lineup:
		if p.name == n:
			return p
	return _batting.lineup[1]


func _cycle_profile() -> void:
	if lineup_mode == "Game":
		manager.shake_off()                    # in a game Y shakes off the catcher's sign
		return
	var names: Array = []
	for b in BatterProfile.all():
		names.append(b.name)
	var i := names.find(_batter_ai.profile.name)
	_batter_ai.profile = BatterProfile.by_name(names[(i + 1) % names.size()])
	_batter_player = _player_named(_batter_ai.profile.name)
	_batter_ai.expected_time = 0.6
	hud.show_notice("Batter: %s" % _batter_ai.profile.name)


func _current_tag() -> String:
	return practice_tags[_tag_index % practice_tags.size()] if not practice_tags.is_empty() else ""


# ------------------------------------------------------------------ human fielding


## Meters from the nearer foul line (the lines run out from the plate at 45 degrees).
static func foul_line_distance(p: Vector3) -> float:
	return absf(absf(p.x) - p.z) * 0.7071


