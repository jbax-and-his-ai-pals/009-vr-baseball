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
@export_enum("Pitching", "Spectate", "Fielding") var game_mode_name: String = "Pitching"
## The position you play in Fielding mode (3 first base ... 9 right field; 6 is shortstop).
@export_range(3, 9, 1) var fielding_position := 6
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

const GRAB_THRESHOLD := 0.7
const RELEASE_THRESHOLD := 0.4
const HOLD_OFFSET := Vector3(0.0, -0.02, -0.06)
const LINGER_TIME := 1.5
const MAX_PITCHES := 8
const MITT_Z := -0.85
const BACKSTOP_Z := -8.0
const FORWARD := Vector3(0.0, 0.0, -1.0)
## Assisted pitches never leave the hand slower than this (m/s), so a feeble
## throw does not become a 45-degree rainbow.
const MIN_ASSIST_SPEED := 12.0
## FUNNEL reads the hand's travel direction between these times before release.
## Chosen from recorded throws: much steadier than the instant of release, where the
## velocity direction swings ~1 degree per ms.
const FUNNEL_FROM := 0.19
const FUNNEL_TO := 0.04
const ZONE_CENTER := Vector2(0.0, (PitchPhysics.ZONE_BOTTOM + PitchPhysics.ZONE_TOP) * 0.5)
## Releases slower than this (m/s of hand speed) are not throws: the ball just drops.
const MIN_THROW_SPEED := 3.5

var _xr_active := false
var _demo := false
var _demo_timer := 1.0
var _demo_interval := 0.35
var _camera: Camera3D
var _hand: XRController3D
var _detector := ThrowDetector.new()
var _logger := ThrowLogger.new()
## Learned usual aim direction (degrees right / up of straight at the plate) and how much
## it scatters. Start from a recorded player; the first throws calibrate them quickly.
var _aim_mu := Vector2(4.4, -0.3)
var _aim_sigma := Vector2(6.0, 5.5)
var _aim_n := 0
var _notice := ""
var _notice_until := 0.0
var _last_grip := 0.0
var _wrist := WristModel.new()
var _off_hand: XRController3D
var _tag_index := 0
var _tag_pressed := false
var _held := false
var _held_ball: MeshInstance3D
var _pitches: Array[LivePitch] = []
var _ball_mesh: ArrayMesh
var _trail_mat: StandardMaterial3D
var _count := 0
var _strikes := 0
var _best_mph := 0.0
var _zone_markers: ZoneMarkers
var _doll_demo: Array = []
var _home_order := 0
var _catcher: Doll
var _umpire: Doll
var _director := PlayDirector.new()   # puts a play on the field: fielders, ball, runners, callouts
var _crew: PlateCrew          # drives the catcher and the umpire
var _props: FieldProps        # dust, dropped bats, and calls that wait for their moment
var _dust: DustPuffs          # _props.dust
var _profile := PlayerProfile.load_from()   # lifetime stats, leaderboards, challenge results
var _game_recorded := false
var _haptics := Haptics.new()     # controller vibration
var _sound: SoundDirector
var _audio: AudioManager          # _sound.audio, for the loops that follow the ball
var _was_in_menu := true
var _perf_sum := 0.0
var _perf_frames := 0
var _perf_max := 0.0
var _perf_spikes := 0
var _mark_pressed := false
# The running game.
var _delivery_start := -1.0          # when your motion began (seconds), -1 if it has not
var _last_delivery := 0.9            # how long the last delivery took, motion start to release
var _hand_prev := Vector3.ZERO
var _hand_prev_t := -1.0
var _steal := {}                     # a runner who is going: {from, runner, run_t, plan, apply_at, done}
var _leads := [2.4, 2.4, 2.4]        # meters each runner stands off his base
var _since_throw := [5, 5, 5]        # pitches since you last threw over, per base
var _flights: Array = []             # balls in the air that are not a pitch or a hit (throws)
var _tired_notice := false
var _relievers_used := 0
var _runs_at_pitcher_change := 0
var _doll_styles := {}
var _runner_styles := 0
var _doll_demo_step := 0
var _hud: Node3D                 # holds the stat boards
var _pitch_board: StatBoard
var _bat_board: StatBoard
var _info_board: StatBoard
var _stats := StatsTracker.new()
var _last_report := ""
var _canned_index := 0
var _batter: CartoonBatter
var _presenter: BatterPresenter           # the batter's walk-on, box, bat; owns the figure
var _batter_home: Transform3D:             # where he stands in his box
	get: return _presenter.home if _presenter != null else Transform3D.IDENTITY
	set(v):
		if _presenter != null:
			_presenter.home = v
var _batter_ready := true                  # in the box and pitching may go on
var _unready_for := 0.0
var _walk_on: Dictionary:                  # the next batter's walk to the box
	get: return _presenter.walk if _presenter != null else {}
	set(v):
		if _presenter != null:
			_presenter.walk = v
var _aux_play := {}                        # a walk or strikeout's own runner animation
var _leavers: Array[Node3D] = []   # figures that walk back to the dugout after an out
var _stadium: Stadium
var _xr_interface: XRInterface
var _governor := PerfGovernor.new()
var _perf_log := false
var _perf_timer := 0.0
var _heartbeat_timer := 0.0
var _batter_ai: BatterAI
var _hits: Array[LiveHit] = []
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
var _game_over_timer := -1.0
var _base_runners: Array[Node3D] = []
var _field_nodes := {}            # fielder number -> Node3D
var _runner: Node3D
var _play_labels: Array[Label3D] = []
var _run_rng := RandomNumberGenerator.new()
var _fx_rng := RandomNumberGenerator.new()   # presentation choices only: never shares a stream with the rules
var _game_seed := 0
var _last_report_extra := ""
var _origin: XROrigin3D
var _settings := Settings.new()
var _menu: GameMenu
var _menu_button_was := false
var _config := GameConfig.new()
var _catch_radius := HumanFielding.CATCH_RADIUS
var _throw_cone := HumanFielding.THROW_CONE_DEG
var _auto_field := false          # debug: the glove finds the ball and throws to first on its own
var _field_samples: Array = []    # [time, hand position] while holding a ball to throw
const FIELD_LOCOMOTION_MIN := 0.15
var _play_hit: LiveHit
var _outs := 0
var _hit_count := 0
var _errors := 0
var _homers := 0
var _swings := 0
var _game_time := 0.0
var _batter_free_at := 0.0   # a batter still finishing a swing cannot start another
const SWING_RECOVERY := 0.75
var _whiffs := 0
var _in_play := 0
var _best_ev := 0.0


func _ready() -> void:
	_director.leads = _leads          # the scene asks where a runner stands before the world is built
	_demo = "--demo" in OS.get_cmdline_user_args()
	_settings = Settings.new() if "--no-settings" in OS.get_cmdline_user_args() else Settings.load_from()
	apply_settings(_settings)
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
			fielding_position = clampi(int(a.substr(12)), 3, 9)
	_auto_field = "--auto-field" in OS.get_cmdline_user_args()
	apply_config(_current_config())
	_mode = GameMode.by_name(game_mode_name)
	if not _mode.human_fielders.is_empty():
		_mode = GameMode.fielding(fielding_position)
	if not _mode.supported:
		push_warning("Game mode '%s' is not built yet; using Pitching." % _mode.name)
		_mode = GameMode.pitching()
	_home = Team.generate("Home", 55.0, 7)
	_batting = Team.archetype_roster()
	_defense = Defense.from_team(_home)
	_ai_pitcher = AIPitcher.new(_home.player_at(1))
	_away = Team.generate("Away", 52.0, 14)
	_new_game()
	_game_seed = randi()
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--seed="):
			_game_seed = int(sa.substr(7))
	_run_rng.seed = _game_seed
	_fx_rng.seed = _game_seed ^ 0x5EED
	_build_world()
	_setup_xr()
	_haptics.hand = _hand
	_haptics.off_hand = _off_hand
	_haptics.set_level(_settings.haptics)
	_build_menu(want_menu)
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
	_director.leads = _leads
	_director.presenter = _presenter
	_director.crew = _crew
	_director.props = _props
	_director.sound = _sound
	_director.human_num = Callable(self, "_human_num")
	_director.refresh_base_runners = Callable(self, "_refresh_base_runners")
	_director.batter_hidden.connect(_on_batter_hidden)
	_crew.umpire_voice.connect(func(id: String): _sound.umpire_says(id))
	_crew.throw_started.connect(func(at: Vector3): _sfx_later(0.42, "throw_whoosh", at))
	_sound.umpire = _umpire
	_sound.batter = _batter
	_presenter.walk_step.connect(_on_walk_step)
	_presenter.arrived.connect(_on_batter_arrived)
	_sound.tired_source = Callable(self, "_arm_fatigue")
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
	_sync_batter()
	if not _xr_active:
		_governor.set_refresh_rate(60.0)  # a desktop window is judged against 60 Hz, not a headset's 90
	_perf_log = "--perf" in OS.get_cmdline_user_args()
	_governor.enabled = not ("--no-governor" in OS.get_cmdline_user_args())
	_governor.level_changed.connect(_on_quality_changed)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hit-test="):
			# Debug: a batted ball with a given exit velocity (mph), launch and spray (deg).
			var parts := a.substr(11).split(":")
			var spec := [float(parts[0]), float(parts[1]), float(parts[2])]
			get_tree().create_timer(0.5).timeout.connect(func(): _debug_hit(spec[0], spec[1], spec[2]))
	if "--contact-demo" in OS.get_cmdline_user_args():
		# Debug: one perfectly timed swing at one pitch, to inspect bat-ball contact.
		_batter_ai.debug_perfect = true
		_batter_ai.profile = BatterProfile.by_name("MVP")
		get_tree().create_timer(0.4).timeout.connect(func(): _debug_throw())
	if "--swing-test" in OS.get_cmdline_user_args():
		# Debug: swing once, 0.5 s in, so the animation can be inspected without a pitch.
		get_tree().create_timer(0.3).timeout.connect(func(): _batter.swing_to(Vector3(0.0, 0.9, 0.2), 0.3))
	if "--doll-demo" in OS.get_cmdline_user_args():
		_spawn_doll_demo()
	_set_hud_idle()


## First base open, a runner in scoring position, two outs or the late innings, and a hitter
## the defense does not want to pitch to: the AI manager walks him on purpose.
func _wants_intentional_walk() -> bool:
	if _game == null or _batter_player == null or _game.balls != 0 or _game.strikes != 0:
		return false
	if _game.bases[0] != null or (_game.bases[1] == null and _game.bases[2] == null):
		return false
	var late := _game.inning >= maxi(_game.innings - 2, 1)
	if _game.outs < 1 and not late:
		return false
	return _batter_player.power >= 68.0 and _batter_player.hitting_overall() >= 62.0 and _game.runs - _game.home_score <= 2


## Walk the batter on purpose (the manager's call, or the pause menu): no pitches, the usual
## forced advance, and he trots to first.
func _issue_intentional_walk() -> void:
	if _game == null or not _batter_ready or not _aux_play.is_empty() or _game.over:
		return
	_log("intentional_walk", {"batter": _batter_player.name if _batter_player else ""})
	var before := _game.bases.duplicate()
	var ev := _game.intentional_walk()
	_begin_pa_exit(ev, before)
	_last_report = "INTENTIONAL WALK
" + _event_text(ev)
	_after_event(ev)
	_refresh_hud()


## How worn out the human pitcher's arm is (0 fresh .. 1 spent), from his pitch count and the
## starter's stamina. Tells you once when it starts to show.
func _arm_fatigue() -> float:
	if _game == null or _home == null:
		return 0.0
	var f: float = _home.player_at(1).fatigue(_game.pitch_count)
	if f > 0.35 and not _tired_notice:
		_tired_notice = true
		_show_notice("Your arm is getting tired")
	return f


## The AI manager's call: a starter who is spent or getting hit hard is replaced by a reliever.
func _maybe_change_pitcher() -> void:
	if _ai_pitcher == null or _game == null:
		return
	var tired := _ai_pitcher.player.fatigue(_ai_pitcher.pitches_thrown)
	var rough := _game.runs - _runs_at_pitcher_change >= 5
	if tired < 0.9 and not rough:
		return
	if _game.outs != 0 or _game.balls != 0 or _game.strikes != 0:
		return               # changes happen between batters
	_relievers_used += 1
	_log("pitcher_change", {"tired": snappedf(tired, 0.01), "pitches": _ai_pitcher.pitches_thrown,
		"runs_since": _game.runs - _runs_at_pitcher_change})
	var rp := Team.relief_pitcher(50.0 + 2.0 * _relievers_used, 4000 + _relievers_used * 31)
	_ai_pitcher = AIPitcher.new(rp)
	_runs_at_pitcher_change = _game.runs
	_show_notice("New pitcher: %s" % rp.name)
	_refresh_scoreboard()


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


## He lets it go: a pitch at his body makes him jerk away, one near the zone sometimes
## draws a hitch of the bat (a check swing).
func _batter_takes(pitch: LivePitch) -> void:
	var what := _presenter.take(pitch.analysis, bool(pitch.bat.get("busy", false)), _batter_is_lefty(), _fx_rng.randf())
	if what == "check":
		_sfx_later(float(pitch.analysis.get("time", 0.5)) * 0.5, "bat_swing_slow", _batter.global_position + Vector3(0.0, 1.1, 0.0), -6.0)


## The batter lets go of the bat: it drops, bounces and lies there until the next one comes up.
func _drop_bat() -> void:
	var dropped = _presenter.drop_bat()
	if dropped == null:
		return
	var xf: Transform3D = dropped
	if _sound != null and _sound.flip_next:
		_sound.flip_next = false
		_sfx("bat_flip", xf.origin)
	_props.drop_bat(xf)


# ------------------------------------------------------------------ the running game
func _runners_on() -> bool:
	return _game != null and (_game.bases[0] != null or _game.bases[1] != null or _game.bases[2] != null)


## Your motion has started (or an AI pitcher is about to throw): a runner may break for the next
## base. Only one runner goes at a time.
func _on_delivery_start() -> void:
	if _runners_on():
		GameLog.event("delivery_start", {"s": _brief(), "t_hand": _delivery_start})
	if _game == null or not _runners_on() or not _steal.is_empty() or not _aux_play.is_empty() or _game.over:
		return
	var tired := 0.0
	if _mode.human_pitcher:
		tired = _arm_fatigue()
	for base in [2, 1]:
		var runner = _game.bases[base - 1]
		if not (runner is Player):
			continue
		var p := StealModel.steal_chance(runner as Player, base, _game.outs, _game.bases, tired)
		if _run_rng.randf() >= p:
			continue
		var lead: float = float(_leads[base - 1])
		var run_t := StealModel.run_time(runner as Player, base, lead)
		var plan := Baserunning.plan_steal(base, runner, run_t)
		_aux_play = {"plan": plan, "t": 0.0}
		_steal = {"from": base, "runner": runner, "run_t": run_t, "plan": plan}
		_log("steal_break", {"base": base, "runner": (runner as Player).name, "chance": snappedf(p, 0.001), "lead": lead,
			"run_t": run_t, "delivery_so_far": _last_delivery})
		_refresh_base_runners()
		return


## The pitch is in the catcher's glove (or it was hit and the steal was cancelled elsewhere):
## did the runner make it?
func _resolve_steal(a: Dictionary) -> void:
	if _steal.is_empty() or _steal.has("apply_at"):
		return
	var plan: Dictionary = _steal.plan
	var res := StealModel.resolve(_last_delivery, float(a.get("time", 0.5)), float(_steal.run_t), _run_rng)
	var t_now := float(_aux_play.get("t", 0.0)) if not _aux_play.is_empty() else 0.0
	var base := int(_steal.from)
	var t_ball: float = maxf(float(res.t_ball), t_now + 0.3)
	if res.safe:
		Baserunning.steal_safe(plan)
	else:
		Baserunning.steal_out(plan, t_ball)
	# The catcher's throw: from the plate to the glove of the man covering the base.
	var cover: int = RECEIVE_FOR_STEAL[base]
	var glove: Vector3 = (Baserunning.RECEIVE_SPOT[base + 1] as Vector3) + Vector3(0.0, 1.15, 0.0)
	var dur := Vector2(0.0 - glove.x, -1.35 - glove.z).length() / 33.0 + 0.1
	_spawn_flight(Vector3(0.0, 1.5, -1.2), glove, maxf(t_ball - dur - t_now, 0.05), dur, cover, not res.safe)
	# He comes up out of the crouch and throws; the arm starts early enough that the ball leaves on time.
	_crew.pop_throw_in(maxf(maxf(t_ball - dur - t_now, 0.05) - 0.42, 0.0), glove)
	_steal["safe"] = res.safe
	_steal["apply_at"] = t_ball
	_log("steal_resolve", {"base": base, "safe": res.safe, "delivery": _last_delivery, "flight": a.get("time", 0.0),
		"t_ball": res.t_ball, "t_run": res.t_run})
	_last_report_extra = "STEAL ATTEMPT: %s" % ("safe" if res.safe else "OUT")


func _finish_steal() -> void:
	if _steal.is_empty() or _steal.get("done", false):
		return
	_steal["done"] = true
	var base := int(_steal.from)
	# The scorebook only changes if he is still on that base (a walk or an inning change may have moved him).
	if _game.bases[base - 1] == _steal.runner:
		var ev := _game.steal(base, bool(_steal.safe))
		_last_report = ("STOLEN BASE\n" if _steal.safe else "CAUGHT STEALING\n") + _event_text(ev)
		_after_event(ev)
		_refresh_hud()
	_steal = {}


const RECEIVE_FOR_STEAL := {1: 6, 2: 5}




## A throw to a base (not a pitch): where it goes, whether it gets him, or a balk.
func _do_pickoff(base: int, from: Vector3, vel: Vector3, err: float) -> void:
	_haptics.play("release", 0.5)
	var runner = _game.bases[base - 1]
	var glove: Vector3 = (Baserunning.RECEIVE_SPOT[base] as Vector3) + Vector3(0.0, 1.15, 0.0)
	var speed := clampf(vel.length() * 0.85, 12.0, 30.0)
	var dist := Vector2(from.x - glove.x, from.z - glove.z).length()
	var dur := dist / speed + 0.1
	var receiver := HumanFielding.receiver(base, 1)
	_spawn_flight(from, glove, 0.0, dur, receiver)
	for i in 3:
		_since_throw[i] = 0
	if runner == null:
		if _runners_on():
			_call_balk("Threw to an empty base")
		else:
			_show_notice("Throw to %s" % ["", "first", "second", "third"][base])
		return
	var chance := StealModel.pickoff_chance(float(_leads[base - 1]), err, vel.length(), runner as Player)
	var out := _run_rng.randf() < chance
	_log("pickoff", {"base": base, "runner": (runner as Player).name, "lead": _leads[base - 1], "err_deg": err,
		"speed": vel.length(), "chance": snappedf(chance, 0.001), "out": out})
	if _aux_play.is_empty():
		var bag := Baserunning.BASE_POS[base] as Vector3
		var plan := Baserunning.plan_dive_back(base, runner, _director.stand_for(base), PlayDirector.BASE_STANDS[base - 1], dur + 0.25, out)
		_aux_play = {"plan": plan, "t": 0.0}
	_leads[base - 1] = StealModel.lead_after_throw()
	if out:
		var ev := _game.pickoff(base)
		_last_report = "PICKED OFF at %s\n" % ["", "first", "second", "third"][base] + _event_text(ev)
		_after_event(ev)
	else:
		_last_report = "Throw over to %s: safe" % ["", "first", "second", "third"][base]
	_refresh_hud()


func _call_balk(why: String) -> void:
	_haptics.play("buzz")
	_log("balk", {"why": why})
	_sfx_later(0.2, "ump_balk", _umpire.global_position + Vector3(0.0, 1.5, 0.0))
	var before := _game.bases.duplicate()
	var ev := _game.balk()
	if ev.get("result", "") == "":
		return
	if _aux_play.is_empty():
		var plan := Baserunning.plan_advance(before)
		(plan["events"] as Array).append({"t": 0.1, "base": 0, "text": "BALK", "kind": "out", "at": Vector3(0.0, 0.0, 0.0)})
		_aux_play = {"plan": plan, "t": 0.0}
		_refresh_base_runners(before)
	_last_report = "BALK - %s\n" % why + _event_text(ev)
	_after_event(ev)
	_refresh_hud()


## A ball in the air that is a throw: spawn it with a delay and a duration; the receiver puts his
## glove up as it arrives.
func _spawn_flight(from: Vector3, to: Vector3, delay: float, dur: float, receiver: int, tag: bool = false) -> void:
	var b := _make_ball()
	b.visible = false
	_flights.append({"ball": b, "from": from, "to": to, "t": 0.0, "delay": delay, "dur": maxf(dur, 0.1),
		"receiver": receiver, "caught": false, "tag": tag})


func _update_flights(delta: float) -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var f: Dictionary = _flights[i]
		f.t += delta
		var local := float(f.t) - float(f.delay)
		var ball: Node3D = f.ball
		if local < 0.0:
			continue
		var u := clampf(local / float(f.dur), 0.0, 1.0)
		var from: Vector3 = f.from
		var to: Vector3 = f.to
		var d := Vector2(from.x - to.x, from.z - to.z).length()
		ball.visible = true
		var bpos := from.lerp(to, u) + Vector3(0.0, clampf(0.07 * d, 0.2, 4.0) * 4.0 * u * (1.0 - u), 0.0)
		var catcher_node = _field_nodes.get(int(f.receiver))
		if catcher_node is Doll:
			bpos = bpos.lerp((catcher_node as Doll).glove_world(), smoothstep(0.75, 0.97, u))
		ball.global_position = bpos
		if local >= float(f.dur) - 0.25 and not f.caught:
			f.caught = true
			var rec = _field_nodes.get(int(f.receiver))
			if rec is Doll:
				(rec as Doll).play("tag" if bool(f.get("tag", false)) else "catch", 0.6)
				_sfx_later(0.25, "tag_slap" if bool(f.get("tag", false)) else "glove_catch_throw", (rec as Node3D).global_position + Vector3(0.0, 1.0, 0.0))
		if local >= float(f.dur) + 1.0:
			ball.queue_free()
			_flights.remove_at(i)


# ------------------------------------------------------------------ session log (see GameLog)
## A short picture of the game for a log line: inning, outs, count, who is on.
func _brief() -> Dictionary:
	if _game == null:
		return {}
	var on := ""
	for i in 3:
		on += str(i + 1) if _game.bases[i] != null else "-"
	return {"inn": _game.inning, "outs": _game.outs, "count": "%d-%d" % [_game.balls, _game.strikes], "on": on,
		"score": "%d-%d" % [_game.runs, _game.home_score]}


## Everything a bug report might need.
func _snapshot() -> Dictionary:
	var d := _brief()
	if _game == null:
		return d
	var names := []
	for i in 3:
		names.append(_game.bases[i].name if _game.bases[i] is Player else ("?" if _game.bases[i] != null else ""))
	d["bases"] = names
	d["batter"] = _batter_player.name if _batter_player else ""
	d["pitches"] = _game.pitch_count
	d["ready"] = _batter_ready
	d["batter_visible"] = _batter.visible if _batter else null
	d["walk_on"] = not _walk_on.is_empty()
	d["aux"] = not _aux_play.is_empty()
	d["steal"] = not _steal.is_empty()
	d["hits_alive"] = _hits.size()
	d["plays_open"] = _play_in_progress()
	d["flights"] = _flights.size()
	d["unready_for"] = snappedf(_unready_for, 0.01)
	d["delivery_start"] = _delivery_start
	d["last_delivery"] = snappedf(_last_delivery, 0.01)
	d["leads"] = _leads
	d["since_throw"] = _since_throw
	d["mode"] = _mode.name if _mode else ""
	d["game_time"] = snappedf(_game_time, 0.01)
	d["frame_ms"] = snappedf(_governor.ema_ms, 0.1)
	d["quality_level"] = _governor.level
	return d


func _log(kind: String, data: Dictionary = {}) -> void:
	data["s"] = _brief()
	GameLog.event(kind, data)


## Flag this moment in the log (B on your throwing hand, F on a desktop).
func _mark_moment() -> void:
	GameLog.mark("player_flag", _snapshot())
	_sfx("ui_mark_moment")
	_show_notice("Marked this moment in the log", true)


## Frame times: a line every five seconds, and one for any frame over 60 ms with what was going on.
func _log_frame(delta: float) -> void:
	_perf_sum += delta
	_perf_frames += 1
	_perf_max = maxf(_perf_max, delta)
	if delta > 0.06 and _game_time > 3.0:
		_perf_spikes += 1
		var d := _snapshot()
		d["ms"] = snappedf(delta * 1000.0, 0.1)
		GameLog.event("spike", d)
	if _perf_sum >= 5.0:
		GameLog.event("perf", {"fps": snappedf(_perf_frames / _perf_sum, 0.1),
			"ms_avg": snappedf(_perf_sum / _perf_frames * 1000.0, 0.1), "ms_max": snappedf(_perf_max * 1000.0, 0.1),
			"spikes": _perf_spikes, "draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"level": _governor.level, "xr": _xr_active, "hits": _hits.size(), "pitches": _pitches.size(), "s": _brief()})
		_perf_sum = 0.0
		_perf_frames = 0
		_perf_max = 0.0
		_perf_spikes = 0


## Soft or paper, decided once per player so a person always looks the same. `--doll-style=soft`
## or `paper` forces one for everybody.
func _doll_style(key: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a == "--doll-style=soft":
			return Doll.Style.SOFT
		if a == "--doll-style=paper":
			return Doll.Style.PAPER
	if not _doll_styles.has(key):
		_doll_styles[key] = randi() % 2
	return _doll_styles[key]


func _runner_doll(at: Vector3) -> Doll:
	_runner_styles += 1
	var d := Doll.create(self, at, Color(0.84, 0.16, 0.18), Color(0.95, 0.95, 0.97), Color(0.12, 0.17, 0.50), false,
		_doll_style(100 + _runner_styles))
	d.crouch = 0.0
	d.footstep.connect(_on_footstep)
	return d


## Debug: a row of soft and paper figures side by side, each looping through the clips.
func _spawn_doll_demo() -> void:
	var navy := Color(0.12, 0.17, 0.50)
	var red := Color(0.84, 0.16, 0.18)
	for i in 8:
		var d := Doll.create(self, Vector3(-7.0 + i * 2.0, 0.0, 9.0), red if i % 2 == 0 else navy,
			Color(0.95, 0.95, 0.97) if i % 2 == 0 else Color(0.62, 0.64, 0.70), navy, true, i % 2)
		d.rotation.y = deg_to_rad(90.0) if i < 4 else deg_to_rad(-90.0)
		_doll_demo.append(d)
	var timer := Timer.new()
	timer.wait_time = 2.4
	timer.autostart = true
	timer.timeout.connect(func():
		_doll_demo_step += 1
		var kinds := ["overhand", "sidearm", "underhand", "catch", "scoop", "backhand", "jump", "react", "tag", "slide", "dive", "block",
			"ump_strike", "ump_safe", "ump_out", "celebrate", "fist_pump"]
		for k in _doll_demo.size():
			var d: Doll = _doll_demo[k]
			d.play(kinds[(_doll_demo_step + k / 2) % kinds.size()], 1.1))
	add_child(timer)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.78, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	add_child(sun)

	var mz := PitchPhysics.MOUND_Z
	var mh := PitchPhysics.MOUND_H
	# The park (grass, infield, stands, crowd, ...) and a batter standing in his box.
	_stadium = Stadium.new()
	add_child(_stadium)
	_presenter = BatterPresenter.new()
	add_child(_presenter)
	_presenter.setup(self)
	_batter = _presenter.batter
	_props = FieldProps.new()
	add_child(_props)
	_dust = _props.dust
	_props.bat_bounced.connect(func(at: Vector3): _sfx("bat_drop", at))

	# Mound, plate, rubber, backstop wall and the cartoon catcher: one baked mesh, one draw call.
	var field := MeshMerger.new()
	var mound := CylinderMesh.new()
	mound.top_radius = 2.7
	mound.bottom_radius = 3.4
	mound.height = mh
	field.add_at(mound, Color(0.72, 0.52, 0.34), Vector3(0.0, mh * 0.5, mz))
	var plate := BoxMesh.new()
	plate.size = Vector3(0.432, 0.02, 0.432)
	field.add_at(plate, Color.WHITE, Vector3(0.0, 0.015, 0.0))
	var rubber := BoxMesh.new()
	rubber.size = Vector3(0.61, 0.03, 0.15)
	field.add_at(rubber, Color.WHITE, Vector3(0.0, mh + 0.015, mz))
	var backstop := BoxMesh.new()
	backstop.size = Vector3(24.0, 3.0, 0.3)
	field.add_at(backstop, Color(0.2, 0.35, 0.25), Vector3(0.0, 1.5, BACKSTOP_Z - 0.2))
	field.build_instance(self)
	var navy_c := Color(0.12, 0.17, 0.50)
	_catcher = Doll.create(self, Vector3(0.0, 0.0, -1.35), navy_c, Color(0.62, 0.64, 0.70), navy_c, true, _doll_style(2), "catcher")
	_field_nodes[2] = _catcher
	_umpire = Doll.create(self, Vector3(0.0, 0.0, PlateCrew.UMP_HOME_Z), Color(0.20, 0.20, 0.25), Color(0.38, 0.38, 0.43),
		Color(0.08, 0.08, 0.10), false, _doll_style(3), "umpire")
	# The rest of the defense: one draw call each. The pitcher is the player, so he is abstract.
	var navy := Color(0.12, 0.17, 0.50)
	for f in _defense.fielders:
		if f.visible and f.num != 2:
			var node := Doll.create(self, f.home, navy, Color(0.62, 0.64, 0.70), navy, true, _doll_style(f.num))
			node.footstep.connect(_on_footstep)
			node.rotation.y = atan2(-f.home.x, -f.home.z)
			_field_nodes[f.num] = node
	if not _mode.human_fielders.is_empty():
		var me: Node3D = _field_nodes.get(int(_mode.human_fielders[0]))
		if me:
			me.visible = false
	# The batter becomes a runner once he hits it.
	_runner = _runner_doll(Vector3(0.98, 0.0, 0.0))
	_runner.visible = false
	for i in 3:
		var lv := _runner_doll(Vector3.ZERO)
		lv.visible = false
		_leavers.append(lv)
	# SAFE / OUT / RUN callouts: several can be up at once on a double play.
	for i in 4:
		var lab := Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.fixed_size = true
		lab.pixel_size = 0.0016
		lab.font_size = 80
		lab.outline_size = 16
		lab.no_depth_test = true
		lab.visible = false
		add_child(lab)
		_play_labels.append(lab)

	# Translucent strike zone at the front of the plate, facing the pitcher.
	var zone := QuadMesh.new()
	var zone_h := PitchPhysics.ZONE_TOP - PitchPhysics.ZONE_BOTTOM
	zone.size = Vector2(PitchPhysics.ZONE_HALF_W * 2.0, zone_h)
	var zone_inst := _add_mesh(zone, Color(1.0, 1.0, 1.0, 0.22), Vector3(0.0, PitchPhysics.ZONE_BOTTOM + zone_h * 0.5, 0.0))
	var zone_mat := zone_inst.material_override as StandardMaterial3D
	zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_zone_markers = ZoneMarkers.new()
	add_child(_zone_markers)

	# Shared ball mesh: a stitched baseball, one draw call for every ball (held, pitched, batted).
	_ball_mesh = BallVisual.mesh()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.albedo_color = Color(1.0, 0.9, 0.2)
	_held_ball = _make_ball()
	_held_ball.visible = false

	_build_boards()


## Three boards that hang still in the park (not on your head): what you have thrown, how the
## lineup has hit, and the last pitch's details.
func _build_boards() -> void:
	_hud = Node3D.new()
	add_child(_hud)
	var mound := Vector3(0.0, 0.0, PitchPhysics.MOUND_Z)
	# The two pitching boards stand just in front of the mound on either side, close enough to
	# read at a glance. The batting board hangs behind the plate, drawn large to be read from here.
	var specs := [
		["pitch", Vector3(-2.7, 3.1, 15.2), 2.5, 1.0],
		["info", Vector3(2.7, 2.8, 15.2), 2.7, 1.0],
		["bat", Vector3(0.0, 14.0, -6.5), 2.7, 4.6],
	]
	for sp in specs:
		var b := StatBoard.new()
		b.width = sp[2]
		_hud.add_child(b)
		b.position = sp[1]
		b.scale = Vector3.ONE * float(sp[3])
		# Face the mound, where you stand.
		var to_mound: Vector3 = mound - (sp[1] as Vector3)
		b.rotation.y = atan2(to_mound.x, to_mound.z)
		match sp[0]:
			"pitch":
				_pitch_board = b
			"bat":
				_bat_board = b
			_:
				_info_board = b


func _add_mesh(mesh: Mesh, color: Color, at: Vector3, parent: Node = null) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	inst.material_override = mat
	inst.position = at
	(parent if parent else self).add_child(inst)
	return inst


func _make_ball() -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	ball.mesh = _ball_mesh
	ball.material_override = BallVisual.material()
	add_child(ball)
	return ball


## True when this run was asked not to touch the headset: `--xr-mode off` (Godot's own flag,
## which also keeps OpenXR from starting) or `--no-xr`. Tests, screenshots and profiling use it so
## they never grab the Virtual Desktop session.
static func _xr_disabled_by_args() -> bool:
	var args := OS.get_cmdline_args()
	if "--no-xr" in args:
		return true
	var i := args.find("--xr-mode")
	return i >= 0 and i + 1 < args.size() and args[i + 1] == "off"


func _setup_xr() -> void:
	var mz := PitchPhysics.MOUND_Z
	var mh := PitchPhysics.MOUND_H
	var xr := XRServer.find_interface("OpenXR")
	if _xr_disabled_by_args():
		xr = null
	if xr and (xr.is_initialized() or xr.initialize()):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		_xr_active = true
		_xr_interface = xr
		print("XR: started on %s | render target %s | view count %d | tuning %s" % [
			xr.get_name(), xr.get_render_target_size(), xr.get_view_count(), "ON" if xr_tuning else "off"])
		if xr_tuning:
			# Quest-oriented render settings, by name so a runtime that lacks one is harmless.
			get_viewport().vrs_mode = Viewport.VRS_XR
			xr.set("display_refresh_rate", 90.0)
			xr.set("render_target_size_multiplier", 1.0)
			xr.set("foveation_level", 2)
			xr.set("foveation_dynamic", true)
			_governor.set_refresh_rate(90.0)
		var origin := XROrigin3D.new()
		origin.position = Vector3(0.0, mh, mz) if _mode.human_pitcher else Vector3(3.5, 0.0, -5.0)
		if not _mode.human_fielders.is_empty():
			var spot: Vector3 = _defense.fielder_by_num(int(_mode.human_fielders[0])).home
			origin.position = Vector3(spot.x, 0.0, spot.z)
			origin.rotation.y = atan2(spot.x, spot.z)       # face home plate
		_origin = origin
		add_child(origin)
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		_camera = cam
		for hand_name in [&"left_hand", &"right_hand"]:
			var ctrl := XRController3D.new()
			ctrl.tracker = hand_name
			origin.add_child(ctrl)
			var vis := BoxMesh.new()
			vis.size = Vector3(0.04, 0.04, 0.12)
			_add_mesh(vis, Color(0.2, 0.4, 0.9), Vector3.ZERO, ctrl)
			if hand_name == throwing_hand:
				_hand = ctrl
			else:
				_off_hand = ctrl
				if not _mode.human_fielders.is_empty():
					# The glove: a big brown mitt where the hand is.
					var mitt := BoxMesh.new()
					mitt.size = Vector3(0.20, 0.06, 0.24)
					_add_mesh(mitt, Color(0.45, 0.28, 0.12), Vector3(0.0, 0.0, -0.10), ctrl)
	else:
		var cam := Camera3D.new()
		var args := OS.get_cmdline_user_args()
		var cam_arg := ""
		for a in args:
			if a.begins_with("--cam="):
				cam_arg = a.substr(6)
		if cam_arg != "":
			# Debug: --cam=x,y,z:lx,ly,lz  (position : look-at)
			var halves := cam_arg.split(":")
			var pp := halves[0].split(",")
			var ll := halves[1].split(",")
			cam.position = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
			add_child(cam)
			cam.look_at(Vector3(float(ll[0]), float(ll[1]), float(ll[2])))
		elif "--overview" in args:
			cam.position = Vector3(-46.0, 38.0, -34.0)
			add_child(cam)
			cam.look_at(Vector3(0.0, 4.0, 40.0))
		elif "--behind-plate" in args:
			cam.position = Vector3(0.0, 1.6, -5.5)
			add_child(cam)
			cam.look_at(Vector3(0.0, 1.5, 30.0))
		elif "--infield" in args:
			cam.position = Vector3(-26.0, 13.0, 2.0)
			add_child(cam)
			cam.look_at(Vector3(0.0, 0.5, 26.0))
		elif "--outfield" in args:
			cam.position = Vector3(-30.0, 22.0, 20.0)
			add_child(cam)
			cam.look_at(Vector3(5.0, 0.0, 80.0))
		elif "--hit" in args:
			cam.position = Vector3(-2.5, 2.2, -3.0)
			add_child(cam)
			cam.look_at(Vector3(0.0, 8.0, 40.0))
		elif "--batter" in args:
			cam.position = Vector3(-1.2, 1.5, 4.0)
			add_child(cam)
			cam.look_at(Vector3(0.9, 1.1, 0.0))
		elif not _mode.human_fielders.is_empty():
			var fspot: Vector3 = _defense.fielder_by_num(int(_mode.human_fielders[0])).home
			cam.position = Vector3(fspot.x, 1.7, fspot.z)
			add_child(cam)
			cam.look_at(Vector3(0.0, 1.0, 0.0))
		elif not _mode.human_pitcher:
			cam.position = Vector3(3.5, 1.7, -5.0)
			add_child(cam)
			cam.look_at(Vector3(0.0, 1.5, 18.0))
		else:
			cam.position = Vector3(0.0, mh + 1.7, mz + 0.5)
			add_child(cam)
			cam.look_at(Vector3(0.0, 1.0, 0.0))
		cam.current = true
		_camera = cam


## An AI pitcher throws when the previous play is over and the interval has passed.
func _run_ai_pitcher(delta: float) -> void:
	_spectate_timer -= delta
	if _spectate_timer > 0.0:
		return
	var play_running: bool = _play_hit != null and not _play_hit.result_shown
	if play_running or not _batter_ready:
		return
	_maybe_change_pitcher()
	# The manager's call: with first base open and a dangerous hitter up, put him on.
	if _wants_intentional_walk():
		_issue_intentional_walk()
		return
	_spectate_timer = spectate_interval
	var release := Vector3(0.0, PitchPhysics.MOUND_H + 1.85, PitchPhysics.MOUND_Z - 1.7)
	_last_delivery = clampf(_run_rng.randfn(1.05, 0.15) - 0.2 * (_ai_pitcher.player.command - 50.0) / 50.0, 0.7, 1.5)
	_on_delivery_start()
	var pitch := _ai_pitcher.next_pitch(release)
	_launch(release, pitch.vel, pitch.spin, pitch.kind)


func _on_quality_changed(level: int) -> void:
	_stadium.set_quality(level)
	if _xr_interface and xr_tuning:
		_xr_interface.set("render_target_size_multiplier", PerfGovernor.render_scale(level))
	print("PerfGovernor: quality level %d (frame %.1f ms, target %.1f ms)" % [level, _governor.ema_ms, _governor.target_ms])


func _process(delta: float) -> void:
	_poll_menu_button()
	if _menu != null and _menu.is_open():
		if _sound != null:
			_sound.update_menu(delta, _menu.model.screen())
		return       # the game waits while a menu is up
	_game_time += delta
	_crew.update(delta)
	_props.update(delta)
	if _sound != null:
		_sound.update(delta, _game)
	_log_frame(delta)
	if _xr_active and _hand != null and _hand.get_is_active():
		var flag := _hand.is_button_pressed("by_button")
		if flag and not _mark_pressed:
			_mark_moment()
		_mark_pressed = flag
	_update_batter_lifecycle(delta)
	if _game_over_timer > 0.0:
		_game_over_timer -= delta
		if _game_over_timer <= 0.0:
			_new_game()
			_sync_batter()
			_last_report = "New game."
			_refresh_hud()
	_governor.update(delta)
	if _xr_active:
		_heartbeat_timer += delta
		if _heartbeat_timer >= 5.0:
			_heartbeat_timer = 0.0
			print("XR heartbeat: %.1f ms | level %d | held %s | pitches %d | hits %d | head %s" % [
				_governor.ema_ms, _governor.level, _held, _pitches.size(), _hits.size(),
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
	if _notice != "" and now > _notice_until:
		_notice = ""
		_refresh_hud()
	if _xr_active and _hand:
		_poll_tag()
		if _mode.human_pitcher:
			_poll_hand(now)
		if not _mode.human_fielders.is_empty():
			_move_fielder(delta)
			_poll_fielding(now)
	elif _demo:
		_demo_timer -= delta
		if _demo_timer <= 0.0 and _batter_ready:
			_demo_timer = _demo_interval
			_debug_throw()
	for i in range(_hits.size() - 1, -1, -1):
		var h := _hits[i]
		_update_hit(h, delta)
		if h.done and h.linger <= 0.0:
			_free_hit(h)
			_hits.remove_at(i)
	for i in range(_pitches.size() - 1, -1, -1):
		var pitch := _pitches[i]
		if not pitch.landed:
			_update_flight(pitch, delta)
		else:
			pitch.linger -= delta
			if pitch.linger <= 0.0:
				_free_pitch(pitch)
				_pitches.remove_at(i)


func _unhandled_input(event: InputEvent) -> void:
	if not _xr_active and event.is_action_pressed("ui_accept"):
		_debug_throw()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		_cycle_profile()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_pause()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_mark_moment()


func _poll_hand(now: float) -> void:
	if not _hand.get_is_active():
		return
	var grip := _hand.get_float("grip")
	_last_grip = grip
	_detector.add_sample(now, _hand.global_position, _hand.global_transform.basis.get_rotation_quaternion(), grip)
	if not _held:
		if grip > GRAB_THRESHOLD and _batter_ready:
			_held = true
			_haptics.play("grab")
			_detector.clear()
			_held_ball.visible = true
			_delivery_start = -1.0
			_hand_prev_t = -1.0
		return
	_held_ball.global_position = _hand.global_transform * HOLD_OFFSET
	# Your delivery starts when the arm gets going. The runners read it and break.
	var hp := _hand.global_position
	if _hand_prev_t >= 0.0 and now > _hand_prev_t and _delivery_start < 0.0:
		if hp.distance_to(_hand_prev) / (now - _hand_prev_t) > 1.6:
			_delivery_start = now
			_on_delivery_start()
	_hand_prev = hp
	_hand_prev_t = now
	if release_mode == ReleaseMode.AUTO_PEAK:
		var tp := _detector.find_release_peak(6.0, 0.85, FORWARD)
		if tp > 0.0:
			_release_from_hand(tp, 0.0, 0.0)
		elif grip < RELEASE_THRESHOLD:
			_drop_held()
	elif grip < RELEASE_THRESHOLD:
		_release_from_hand(now, velocity_latency, spin_latency)


func _poll_tag() -> void:
	if _off_hand == null or not _off_hand.get_is_active() or practice_tags.is_empty():
		return
	var pressed := _off_hand.is_button_pressed("ax_button")
	if pressed and not _tag_pressed:
		_tag_index = (_tag_index + 1) % practice_tags.size()
		_refresh_hud()
	_tag_pressed = pressed
	var y_pressed := _off_hand.is_button_pressed("by_button")
	if y_pressed and not _profile_pressed:
		_cycle_profile()
	_profile_pressed = y_pressed


## Put the right hitter at the plate: the lineup's next man in a Game, the chosen archetype in Practice.
func _sync_batter() -> void:
	if lineup_mode == "Game" and _game and _game.current_batter() != null:
		_batter_player = _game.current_batter()
		_batter_ai.profile = BatterProfile.from_player(_batter_player)
	_refresh_scoreboard()
	# A batter already standing in his box (the first of a game) takes the right side now; everyone
	# else is placed when he walks on, so the last batter never flips sides in front of you.
	if _batter_ready and _walk_on.is_empty() and _aux_play.is_empty() and not _play_in_progress() and _batter != null:
		_presenter.place_in_box(_batter_is_lefty())


func _batter_is_lefty() -> bool:
	if "--lefty" in OS.get_cmdline_user_args():
		return true                      # debug: make every batter left-handed
	return _batter_player != null and not _batter_player.bats_right


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


# ------------------------------------------------------------------ menus
func _build_menu(show_main: bool) -> void:
	_menu = GameMenu.new()
	add_child(_menu)
	var ctrls: Array[XRController3D] = []
	for c in [_hand, _off_hand]:
		if c != null:
			ctrls.append(c)
	var menu_model := MenuModel.new(_settings)
	menu_model.profile = _profile
	_menu.setup(menu_model, _camera, ctrls)
	_menu.chosen.connect(_on_menu_event)
	Session.current = _current_config()
	if show_main:
		_open_menu_main()


func _open_menu_main() -> void:
	_menu.open_main()
	_hud.visible = false


func _toggle_pause() -> void:
	if _menu == null:
		return
	if _menu.is_open():
		if _menu.model.screen() == "pause":
			_close_menu()
		return
	_menu.open_pause(Session.current if Session.current != null else _config)
	_sfx("ui_pause_open")
	_hud.visible = false


func _close_menu() -> void:
	_sfx("ui_pause_close")
	_menu.close()
	_hud.visible = true


func _poll_menu_button() -> void:
	if not _xr_active or _off_hand == null or not _off_hand.get_is_active():
		return
	var down := _off_hand.is_button_pressed("menu_button")
	if down and not _menu_button_was:
		_toggle_pause()
	_menu_button_was = down


func _on_menu_event(ev: Dictionary) -> void:
	_log("menu", {"event": ev.get("type", ""), "config": (ev.config as GameConfig).to_dict() if ev.has("config") else {}})
	match String(ev.get("type", "")):
		"settings":
			_settings.save()
			apply_assist(_settings)
			_haptics.set_level(_settings.haptics)
			if _audio:
				_audio.apply_volumes(_settings.volumes)
		"start":
			Session.pending = ev.config
			_settings.save()
			get_tree().reload_current_scene.call_deferred()
		"restart":
			Session.pending = Session.current if Session.current != null else _config
			get_tree().reload_current_scene.call_deferred()
		"main_menu":
			Session.show_menu = true
			get_tree().reload_current_scene.call_deferred()
		"resume":
			_close_menu()
		"intentional_walk":
			_close_menu()
			_issue_intentional_walk()
		"quit":
			get_tree().quit()


func _new_game() -> void:
	var order: Array[Player] = _away.lineup
	_game = GameState.new(order, game_innings)
	_game.allow_extra = true
	_game.bottom_sim = Callable(self, "_simulate_bottom_half")
	_home_order = 0
	if _sound != null:
		_sound.new_game()
	_game_recorded = false
	_stats.reset()
	if _zone_markers:
		_zone_markers.clear()
	_aux_play = {}
	_walk_on = {}
	_batter_ready = true
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
	_game_over_timer = -1.0
	_refresh_base_runners()
	_refresh_scoreboard()


func _player_named(n: String) -> Player:
	for p in _batting.lineup:
		if p.name == n:
			return p
	return _batting.lineup[1]


func _cycle_profile() -> void:
	if lineup_mode == "Game":
		_show_notice("Y cycles batters in Practice mode; in a Game the lineup comes up in order")
		return
	var names: Array = []
	for b in BatterProfile.all():
		names.append(b.name)
	var i := names.find(_batter_ai.profile.name)
	_batter_ai.profile = BatterProfile.by_name(names[(i + 1) % names.size()])
	_batter_player = _player_named(_batter_ai.profile.name)
	_batter_ai.expected_time = 0.6
	_show_notice("Batter: %s" % _batter_ai.profile.name)


func _current_tag() -> String:
	return practice_tags[_tag_index % practice_tags.size()] if not practice_tags.is_empty() else ""


func _drop_held() -> void:
	_held = false
	_held_ball.visible = false
	_delivery_start = -1.0
	_hand_prev_t = -1.0


func _release_from_hand(release_t: float, vel_latency: float, spin_latency: float) -> void:
	var from := _held_ball.global_position
	var est := _detector.estimate(release_t, vel_latency)
	var spin_est := _detector.estimate(release_t, spin_latency)
	var started := _delivery_start >= 0.0
	var began_at := _delivery_start
	_drop_held()
	if not est.valid:
		return
	if (est.velocity as Vector3).length() < MIN_THROW_SPEED:
		if started and _runners_on():
			_call_balk("Dropped the ball")
		else:
			_show_notice("Too soft - that was a drop. Throw it!")
		return
	# Thrown toward a base: a throw over (a pickoff try), or a balk if nobody is there.
	if from.z > 8.0:
		var pk := HumanFielding.pick_base(from, est.velocity, 26.0)
		if int(pk.base) in [1, 2, 3]:
			_do_pickoff(int(pk.base), from, est.velocity as Vector3, float(pk.err))
			return
	_last_delivery = clampf(release_t - began_at, 0.25, 3.0) if started else 0.9
	var tired := _arm_fatigue()
	var vel: Vector3 = (est.velocity as Vector3) * velocity_gain * (1.0 - 0.06 * tired)
	var max_speed := max_mph / PitchPhysics.MPS_TO_MPH
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	var spin_src: Vector3 = spin_est.spin if spin_est.valid else est.spin
	var hand_sign := 1.0 if throwing_hand == &"right_hand" else -1.0
	var shape := {}
	var spin: Vector3
	if spin_mode == SpinMode.WRIST_MODEL:
		_wrist.technique_gain = technique_gain
		_wrist.fastball_backspin = fastball_backspin_rpm * PitchPhysics.RPM_TO_RADS
		var slot := from.y - _camera.global_position.y
		var extras := {"straight": _detector.straightness(release_t)}
		var peak := _detector.peak_height(release_t)
		if peak > -100.0:
			extras["wind_peak"] = peak - _camera.global_position.y
		shape = _wrist.shape(spin_src, est.velocity, slot, hand_sign, extras)
		spin = shape.spin
	else:
		spin = spin_src * spin_gain
	var scaled := vel
	var funnel := {}
	match aim_mode:
		AimMode.HAND_ASSIST:
			vel = PitchPhysics.assist_velocity(from, vel, spin, aim_assist)
		AimMode.FUNNEL:
			funnel = _funnel_target(from, release_t)
			var target: Vector3 = funnel.target
			vel = PitchPhysics.solve_aim(from, maxf(vel.length(), MIN_ASSIST_SPEED), spin, target)
	var pitch := _launch(from, vel, spin, "Your pitch", shape.get("flutter", 0.0), _run_rng.randf() * 100.0)
	pitch.label = PitchNamer.name_pitch(pitch.analysis, _wrist.typical_mph(velocity_gain), hand_sign, shape.get("knuckle", false))
	_haptics.play("release", clampf(float(pitch.analysis.get("speed_mph", 60.0)) / 90.0, 0.0, 1.0))
	_log_throw(pitch, from, release_t, vel_latency, est, scaled, spin, funnel, shape)


## Where the pitch should cross the plate: the zone center plus how far this throw's aim
## differs from the player's usual aim, measured in units of the player's own scatter.
## Hands not travelling toward the plate give a centered target. Always returns a target.
func _funnel_target(from: Vector3, release_t: float) -> Dictionary:
	var a = _detector.position_at(release_t - FUNNEL_FROM)
	var b = _detector.position_at(release_t - FUNNEL_TO)
	var center := Vector3(ZONE_CENTER.x, ZONE_CENTER.y, 0.0)
	if a == null or b == null:
		return {"target": center, "fallback": true}
	var d: Vector3 = (b as Vector3) - (a as Vector3)
	var travel := d.length()
	if travel < 0.03 or d.z / travel > -0.2:
		return {"target": center, "fallback": true}
	var x := Vector2(rad_to_deg(atan2(d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
	var z_raw := (x - _aim_mu) / _aim_sigma
	# A very erratic throw is allowed to be very wrong: clamp wide, not tight.
	var z := Vector2(clampf(z_raw.x, -4.0, 4.0), clampf(z_raw.y, -4.0, 4.0))
	# A tired arm is less exact: the same wobble lands further from where you meant it.
	var wobble := 1.0 + 0.30 * _arm_fatigue()
	var target := Vector3(
		clampf(ZONE_CENTER.x + z.x * funnel_spread_x * wobble, -2.0, 2.0),
		clampf(ZONE_CENTER.y + z.y * funnel_spread_y * wobble, 0.0, 2.6), 0.0)
	var out := {"target": target, "fallback": false, "angle": x, "z": z,
		"mu_before": _aim_mu, "sigma_before": _aim_sigma}
	# Learn. The first throws calibrate fast and accept nearly anything; later ones skip
	# deliberate outliers so a one-off wild throw does not redefine "usual".
	var gate := 5.0 if _aim_n < 15 else 3.5
	if absf(z_raw.x) <= gate and absf(z_raw.y) <= gate:
		var rate := maxf(1.0 / (_aim_n + 3.0), aim_learn_rate)
		var dev := x - _aim_mu
		_aim_mu += dev * rate
		var v := _aim_sigma * _aim_sigma
		v += (dev * dev - v) * rate
		_aim_sigma = Vector2(maxf(2.0, sqrt(v.x)), maxf(2.0, sqrt(v.y)))
		_aim_n += 1
	return out


## One JSON line per throw: what the arm did, what the assist did, where it went.
func _log_throw(pitch: LivePitch, from: Vector3, release_t: float, latency: float, est: Dictionary, scaled: Vector3, spin: Vector3, funnel: Dictionary, shape: Dictionary) -> void:
	var raw: Vector3 = est.velocity
	var series := []
	for back_ms in [0, 20, 40, 60, 80, 120, 160]:
		var e := _detector.estimate(release_t, latency + back_ms / 1000.0)
		if e.valid:
			var ev: Vector3 = e.velocity
			series.append({"back_ms": back_ms, "speed": snappedf(ev.length(), 0.01),
				"elev": snappedf(ThrowLogger.elevation_deg(ev), 0.1), "azim": snappedf(ThrowLogger.azimuth_deg(ev), 0.1)})
	var samples := []
	for smp in _detector.recent(release_t - 0.55):
		samples.append({"ms": roundi((smp.t - release_t) * 1000.0), "p": ThrowLogger.vec(smp.p),
			"f": ThrowLogger.vec(smp.f), "g": snappedf(smp.g, 0.01)})
	var head := _camera.global_position
	var dir := scaled.normalized()
	var entry := {
		"time": Time.get_datetime_string_from_system(),
		"mode": "auto" if release_mode == ReleaseMode.AUTO_PEAK else "grip",
		"aim_mode": AimMode.keys()[aim_mode],
		"spin_mode": SpinMode.keys()[spin_mode],
		"tag": _current_tag(),
		"pitch_name": pitch.label,
		"gains": {"velocity": velocity_gain, "spin": spin_gain, "assist": aim_assist,
			"funnel_x": funnel_spread_x, "funnel_y": funnel_spread_y, "velocity_latency": latency, "spin_latency": spin_latency},
		"release_pos": ThrowLogger.vec(from),
		"head_pos": ThrowLogger.vec(head),
		"hand_minus_head": ThrowLogger.vec(from - head),
		"head_fwd": ThrowLogger.vec(-_camera.global_transform.basis.z),
		"hand_fwd": ThrowLogger.vec((_hand.global_transform.basis * FORWARD) if _hand else FORWARD),
		"grip_at_release": snappedf(_last_grip, 0.01),
		"raw": {"vel": ThrowLogger.vec(raw), "speed": snappedf(raw.length(), 0.01),
			"elev": snappedf(ThrowLogger.elevation_deg(raw), 0.1), "azim": snappedf(ThrowLogger.azimuth_deg(raw), 0.1),
			"spin": ThrowLogger.vec(est.spin)},
		"series": series,
		"scaled_mph": snappedf(scaled.length() * PitchPhysics.MPS_TO_MPH, 0.1),
		"final_vel": ThrowLogger.vec(pitch.vel),
		"final_elev": snappedf(ThrowLogger.elevation_deg(pitch.vel), 0.1),
		"samples": samples,
	}
	if dir.z < -0.01:
		entry["pointed_plate"] = ThrowLogger.vec(from + dir * (from.z / -dir.z))
	var unassisted := PitchPhysics.fly_to_plate(from, scaled, spin, true, 3.0, -100.0)
	if unassisted.reached:
		entry["unassisted_plate"] = ThrowLogger.vec(unassisted.pos)
	if not shape.is_empty():
		entry["wrist"] = {"z_snap": snappedf(shape.z_snap, 0.01), "z_side": snappedf(shape.z_side, 0.01),
			"z_gyro": snappedf(shape.z_gyro, 0.01), "z_slot": snappedf(shape.z_slot, 0.01),
			"tilt_deg": snappedf(shape.tilt_deg, 0.1), "stiff": snappedf(shape.stiff, 0.01),
			"flutter": snappedf(shape.flutter, 0.01), "push": snappedf(shape.push, 0.01), "z_wind": snappedf(shape.z_wind, 0.01), "spin_rpm": snappedf(spin.length() / PitchPhysics.RPM_TO_RADS, 1.0),
			"technique_gain": technique_gain,
			"baseline": {"snap": snappedf(_wrist.mean_snap, 0.001), "side": snappedf(_wrist.mean_side, 0.001),
				"gyro": snappedf(_wrist.mean_gyro, 0.001), "mag": snappedf(_wrist.mean_mag, 0.001),
				"slot": snappedf(_wrist.mean_slot, 0.001), "speed": snappedf(_wrist.mean_speed, 0.001)}}
	if funnel.has("target"):
		var f := {"target": ThrowLogger.vec(funnel.target), "fallback": funnel.fallback}
		if not funnel.fallback:
			var ang: Vector2 = funnel.angle
			var zz: Vector2 = funnel.z
			var mb: Vector2 = funnel.mu_before
			var sb: Vector2 = funnel.sigma_before
			f["az"] = snappedf(ang.x, 0.01)
			f["el"] = snappedf(ang.y, 0.01)
			f["z"] = [snappedf(zz.x, 0.01), snappedf(zz.y, 0.01)]
			f["mu_before"] = [snappedf(mb.x, 0.01), snappedf(mb.y, 0.01)]
			f["sigma_before"] = [snappedf(sb.x, 0.01), snappedf(sb.y, 0.01)]
		entry["funnel"] = f
	var bt: Dictionary = pitch.bat
	var bl := {"profile": _batter_ai.profile.name, "swing": bt.get("swing", false), "kind": bt.get("kind", "take"),
		"p_swing": snappedf(bt.get("p_swing", 0.0), 0.001)}
	if bt.get("swing", false):
		bl["t_err_ms"] = snappedf(float(bt.get("t_err", 0.0)) * 1000.0, 0.1)
		bl["dy"] = snappedf(bt.get("dy", 0.0), 0.001)
		bl["dx"] = snappedf(bt.get("dx", 0.0), 0.001)
		bl["z_m"] = snappedf(bt.get("z_m", 0.0), 0.001)
	if not pitch.sim.is_empty():
		var sm: Dictionary = pitch.sim
		bl["ev_mph"] = snappedf(sm.ev_mph, 0.1)
		bl["launch"] = snappedf(sm.launch, 0.1)
		bl["spray"] = snappedf(sm.spray, 0.1)
		bl["distance"] = snappedf(sm.distance, 0.1)
		bl["hang"] = snappedf(sm.hang_time, 0.01)
		bl["apex"] = snappedf(sm.apex, 0.1)
		bl["fair"] = sm.fair
		bl["home_run"] = sm.home_run
		if not pitch.play.is_empty():
			bl["play"] = pitch.play.get("result", "")
			bl["play_text"] = pitch.play.get("text", "")
	entry["batter"] = bl
	entry["game"] = {"inning": _game.inning, "outs": _game.outs, "balls": _game.balls, "strikes": _game.strikes,
		"bases": [_game.bases[0] != null, _game.bases[1] != null, _game.bases[2] != null],
		"batter": _batter_player.name if _batter_player else ""}
	var a := pitch.analysis
	entry["result"] = {"reached": a.reached, "strike": a.get("strike", false),
		"plate": ThrowLogger.vec(a.plate_pos) if a.reached else null}
	_logger.record(entry)


func _launch(from: Vector3, vel: Vector3, spin: Vector3, label: String, flutter_amp: float = 0.0, flutter_seed: float = 0.0) -> LivePitch:
	var pitch := LivePitch.new()
	pitch.pos = from
	pitch.vel = vel
	pitch.spin = spin
	pitch.label = label
	pitch.flutter_amp = flutter_amp
	pitch.flutter_seed = flutter_seed
	pitch.analysis = PitchPhysics.analyze(from, vel, spin, flutter_amp, flutter_seed)
	pitch.bat = _batter_ai.evaluate({"release": from, "vel": vel, "spin": spin,
		"situation": {"bases": [_game.bases[0] != null, _game.bases[1] != null, _game.bases[2] != null],
			"outs": _game.outs, "strikes": _game.strikes, "balls": _game.balls},
		"flutter_amp": flutter_amp, "flutter_seed": flutter_seed, "analysis": pitch.analysis})
	if pitch.bat.swing:
		# He is still finishing the previous swing: he cannot offer at this one.
		var contact_at := _game_time + float(pitch.bat.get("contact_time", 0.5))
		if contact_at < _batter_free_at:
			pitch.bat = {"swing": false, "contact": false, "kind": "take", "busy": true,
				"p_swing": pitch.bat.get("p_swing", 0.0)}
		else:
			_batter_free_at = contact_at + SWING_RECOVERY
	if pitch.bat.swing:
		_swings += 1
		var swing_at: Vector3 = pitch.bat.get("bat_target", Vector3(0.0, 0.85, 0.0))
		var swing_in := float(pitch.bat.get("contact_time", pitch.analysis.get("time", 0.5)))
		if pitch.bat.get("bunt", false):
			_batter.bunt_to(swing_at, swing_in)
		else:
			_batter.swing_to(swing_at, swing_in)
			if _sound != null:
				_sound.swing(float(pitch.analysis.get("plate_mph", 60.0)), swing_in)
		if pitch.bat.contact:
			var b: Dictionary = pitch.bat
			pitch.sim = BattedBall.simulate(b.contact_pos, b.vel, b.spin)
			if b.kind == "hit":
				_resolve_ball(pitch)
			else:
				pitch.play = {"result": "foul", "text": "Foul tip", "short": "Foul tip", "fielder": 0,
					"movements": [], "bases": 0, "field_time": 0.0, "field_pos": Vector3.ZERO, "foul_tip": true}
		else:
			_whiffs += 1
	else:
		_batter_takes(pitch)
	_crew.begin_pitch(pitch.analysis, float(pitch.bat.get("contact_time", 99.0)) if pitch.bat.get("contact", false) else 99.0)
	pitch.ball = _make_ball()
	pitch.ball.global_position = from
	if _audio != null:
		_audio.loop_on("whiz", "ball_flight_whiz", -16.0, null, pitch.ball)       # follows the ball in
	pitch.trail_inst = MeshInstance3D.new()
	pitch.trail_inst.mesh = pitch.trail_mesh
	pitch.trail_inst.material_override = _trail_mat
	add_child(pitch.trail_inst)
	pitch.trail.append(from)
	_pitches.append(pitch)
	while _pitches.size() > MAX_PITCHES:
		_free_pitch(_pitches.pop_front())
	return pitch


func _free_pitch(pitch: LivePitch) -> void:
	pitch.ball.queue_free()
	pitch.trail_inst.queue_free()


func _update_flight(pitch: LivePitch, delta: float) -> void:
	pitch.accum += delta
	var changed := false
	while pitch.accum >= PitchPhysics.SIM_DT and not pitch.landed:
		pitch.accum -= PitchPhysics.SIM_DT
		if pitch.bat.get("contact", false) and pitch.flight_time >= float(pitch.bat.contact_time):
			_contact(pitch)
			changed = true
			break
		var s := PitchPhysics.step(pitch.pos, pitch.vel, pitch.spin, PitchPhysics.SIM_DT, true, pitch.flight_time, pitch.flutter_amp, pitch.flutter_seed)
		var next_pos := s[0]
		var in_mitt := absf(next_pos.x) < 0.6 and next_pos.y > 0.2 and next_pos.y < 1.5
		if next_pos.z <= MITT_Z and pitch.pos.z > MITT_Z and in_mitt:
			pitch.pos = pitch.pos.lerp(next_pos, (pitch.pos.z - MITT_Z) / (pitch.pos.z - next_pos.z))
			_land(pitch)
			changed = true
			break
		if next_pos.y <= PitchPhysics.BALL_RADIUS or next_pos.z <= BACKSTOP_Z or pitch.flight_time > 3.0:
			pitch.pos = next_pos
			_land(pitch)
			changed = true
			break
		pitch.pos = next_pos
		pitch.vel = s[1]
		pitch.flight_time += PitchPhysics.SIM_DT
		pitch.steps += 1
		if pitch.steps % 4 == 0:
			pitch.trail.append(pitch.pos)
			changed = true
	pitch.ball.global_position = pitch.pos
	# The stitches show the spin, slowed down so it reads instead of strobing.
	if not pitch.landed and pitch.spin.length_squared() > 0.0001:
		pitch.ball.global_rotate(pitch.spin.normalized(), pitch.spin.length() * delta * 0.12)
	if changed:
		_rebuild_trail(pitch)


func _land(pitch: LivePitch) -> void:
	if _audio != null:
		_audio.loop_off("whiz")
	pitch.landed = true
	pitch.linger = LINGER_TIME
	pitch.trail.append(pitch.pos)
	var a := pitch.analysis
	_count += 1
	_best_mph = maxf(_best_mph, a.speed_mph)
	if a.reached and a.strike:
		_strikes += 1
	var outcome := "ball"
	var plate: Vector3 = a.get("plate_pos", Vector3.ZERO)
	if pitch.bat.get("swing", false):
		outcome = "swinging_strike"
	elif a.get("reached", false) and a.get("strike", false):
		outcome = "called_strike"
	elif a.get("reached", false) and PitchLocation.hits_batter(plate.x, plate.y, _batter_is_lefty()):
		outcome = "hit_by_pitch"
	_mark_pitch(a, outcome)
	if _sound != null:
		_sound.pitch_arrives(a, outcome, plate)
	if a.get("reached", false) and outcome != "hit_by_pitch":
		# The mitt: felt less when it was in the dirt.
		_haptics.play("pop", clampf(float(a.get("plate_mph", 60.0)) / 90.0, 0.0, 1.0) * (0.3 if plate.y < 0.18 else 1.0))
	var third := _game.strikes >= 2              # this strike is the third: the call is the strikeout's
	match outcome:
		"ball":
			_sfx_later(0.4, "ump_ball", _umpire.global_position + Vector3(0.0, 1.5, 0.0), -8.0)
		"called_strike":
			_crew.call_it("ump_strike", 0.3, 0.9, "" if third else "ump_strike")
		"swinging_strike":
			_crew.call_it("ump_strike", 0.35, 0.7, "" if third else "ump_strike")
		"hit_by_pitch":
			_crew.call_it("ump_point", 0.3, 1.0)
	if _runners_on() and _steal.is_empty():
		_last_report_extra = "Delivery %.2f s with runners on" % _last_delivery
	_resolve_steal(a)
	for i in 3:
		_since_throw[i] = int(_since_throw[i]) + 1
	# A pitch the catcher cannot handle: every runner moves up a base.
	var wild_ev := {}
	var wild_plan := {}
	if outcome != "hit_by_pitch" and not _game.bases.is_empty() and _game.bases != [null, null, null]:
		var off := PitchLocation.outside_by(plate.x, plate.y) if a.get("reached", false) else 0.9
		var p_wild := 0.0
		if off > 0.25:
			p_wild = 0.04 + 0.5 * clampf((off - 0.25) / 1.0, 0.0, 1.0)
		else:
			p_wild = 0.008                    # the odd passed ball
		if _run_rng.randf() < p_wild:
			var before := _game.bases.duplicate()
			wild_ev = _game.wild_pitch(off <= 0.25)
			if wild_ev.get("result", "") != "":
				wild_plan = Baserunning.plan_advance(before)
				wild_plan["events"].append({"t": 0.15, "base": 0, "text": "WILD PITCH" if off > 0.25 else "PASSED BALL",
					"kind": "safe", "at": Vector3(0.0, 0.0, 0.0)})
				wild_plan["_before"] = before
	var bases_before := _game.bases.duplicate()
	var ev: Dictionary
	# Strike three that gets away from the catcher: with first base open (or two outs) he can run.
	var strike_three: bool = _game.strikes == 2 and outcome in ["swinging_strike", "called_strike"]
	if strike_three and wild_ev.get("result", "") != "" and (_game.bases[0] == null or _game.outs == 2):
		ev = _game.dropped_third_strike(_run_rng.randf() < 0.55)
	else:
		ev = _game.pitch(outcome)
	if not wild_plan.is_empty() and not ev.get("pa_over", false) and _aux_play.is_empty():
		# Show them go: the batter stays put, the men on base run.
		var shown_from: Array = wild_plan["_before"]
		_aux_play = {"plan": wild_plan, "t": 0.0}
		_refresh_base_runners(shown_from)
	_begin_pa_exit(ev, bases_before)
	# The at-bat ended on a pitch a runner was running on (strike 'em out, throw 'em out).
	if ev.get("pa_over", false) and not _steal.is_empty() and _steal.has("apply_at"):
		_finish_steal()
	_stats.record_pitch(pitch.label, a.speed_mph, outcome)
	var loc := PitchLocation.classify(plate.x, plate.y)
	_log("pitch", {"n": _game.pitch_count, "label": pitch.label, "mph": a.speed_mph, "plate": plate,
		"reached": a.get("reached", false), "loc": loc.kind, "strike_zone": a.get("strike", false), "outcome": outcome,
		"swing": pitch.bat.get("swing", false), "bat": pitch.bat.get("kind", ""), "p_swing": pitch.bat.get("p_swing", 0.0),
		"t_err": pitch.bat.get("t_err", 0.0), "bunt": pitch.bat.get("bunt", false), "busy": pitch.bat.get("busy", false),
		"result": ev.get("result", ""), "text": ev.get("text", ""), "wild": wild_ev.get("result", ""),
		"delivery": _last_delivery if _runners_on() else null, "steal": not _steal.is_empty(),
		"fatigue": snappedf(_home.player_at(1).fatigue(_game.pitch_count), 0.01) if _home else 0.0,
		"on_before": bases_before.map(func(x): return x != null)})
	if ev.get("result", "") == "strikeout":
		_crew.call_it("ump_out", 0.55, 1.1, "ump_strike_three")             # strike three is rung up
	if wild_ev.get("result", "") != "":
		_crew.chase()
	var wild_text := _event_text(wild_ev)
	_last_report = _format_report(pitch.label, a) + _bat_line(pitch) + ("\n" + wild_text if wild_text != "" else "") \
		+ "\n" + _event_text(ev)
	_after_event(ev)
	_refresh_hud()
	print(_last_report.replace("\n", " | "))


func _bat_line(pitch: LivePitch) -> String:
	var b: Dictionary = pitch.bat
	if b.get("swing", false):
		return "\nBatter: swing and miss  (%s)" % _batter_ai.profile.name
	if pitch.analysis.get("reached", false):
		return "\nBatter takes: %s  (%s)" % ["called strike" if pitch.analysis.strike else "ball", _batter_ai.profile.name]
	return ""


## The bat meets the ball: end the pitch's flight and send a batted ball out.
func _contact(pitch: LivePitch) -> void:
	if _audio != null:
		_audio.loop_off("whiz")
	pitch.landed = true
	pitch.linger = LINGER_TIME
	pitch.trail.append(pitch.pos)
	var a := pitch.analysis
	var b: Dictionary = pitch.bat
	var sim: Dictionary = pitch.sim
	_count += 1
	_best_mph = maxf(_best_mph, a.speed_mph)
	if a.reached and a.strike:
		_strikes += 1
	var in_play: bool = b.kind == "hit" and (sim.fair or sim.home_run)
	if in_play:
		_batter_ready = false
	_mark_pitch(a, "in_play" if in_play else "foul")
	_stats.record_pitch(pitch.label, a.speed_mph, "in_play" if in_play else "foul")
	if in_play:
		_in_play += 1
	_best_ev = maxf(_best_ev, b.ev)
	_batter.snap_to_contact()
	if _sound != null:
		_sound.contact(b, sim, pitch.pos)
	_haptics.play("contact", clampf(float(b.ev) / 110.0, 0.0, 1.0))
	var head := _format_report(pitch.label, a)
	if "--contact-demo" in OS.get_cmdline_user_args():
		var gap := _batter.sweet_spot_world().distance_to(pitch.pos)
		print("CONTACT CHECK: bat sweet spot is %.1f cm from the ball at contact" % (gap * 100.0))
	var h := LiveHit.new()
	h.summary = sim
	h.points = sim.points
	h.dt = sim.dt
	h.report = _format_hit(b, sim)
	h.play = pitch.play
	h.bunt = bool(b.get("bunt", false))
	if sim.fair or sim.home_run:
		_crew.step_aside(float(sim.get("spray", 0.0)))
	h.play_end = _director.play_end_time(h.play, (h.points.size() - 1) * h.dt)
	if pitch.human_chance:
		h.human_chance = true
		h.fallback = pitch.play_fallback
		h.human_state = "waiting"
		h.chance_end = float(h.play.get("field_time", 2.0)) + 0.9
		# Until he has it, the batter runs and (on a grounder) forced runners go.
		h.plan = Baserunning.plan_hold(_game.bases, _batter_player, float(sim.get("apex", 0.0)) < 3.0)
		h.play_end = 1e9
		_last_report_extra = "YOUR BALL - get your glove on it"
	elif not h.play.is_empty() and h.play.get("result", "") not in ["foul", ""]:
		# Everyone on base runs on the same physics as the fielders.
		var head_start := {}
		if not _steal.is_empty():
			head_start[int(_steal.from)] = float(_aux_play.get("t", 0.0)) if not _aux_play.is_empty() else 0.0
			_steal = {}
			_aux_play = {}
		h.plan = Baserunning.plan(h.play, _game.bases, _game.outs, _batter_player, _run_rng, head_start)
		h.play_end = maxf(h.play_end, float(h.plan.end_time))
		# A double play (or a throw to a runner) changes where the ball goes and who covers.
		if h.plan.has("cover"):
			var cv: Dictionary = h.plan.cover
			var cf := _defense.fielder_by_num(int(cv.fielder))
			if not cf.is_empty():
				h.play.movements = (h.play.movements as Array).duplicate()
				h.play.movements.append({"fielder": cv.fielder, "from": cf.home, "to": cv.to,
					"t0": 0.3, "t1": maxf(float(cv.t) - 0.1, 0.8), "dive": false})
		h.throws = _director.build_throws(h)
		# Any play with runners (a caught foul ball too) takes the batter out of the box.
		_batter_ready = false
	_play_hit = h
	_director.start_play(h)
	h.ball = _make_ball()
	h.ball.global_position = pitch.pos
	if _audio != null and sim.fair and float(sim.get("apex", 9.0)) < 2.5 and not sim.home_run:
		# A grounder: it rolls along the dirt or the grass until somebody has it.
		var rest: Vector3 = sim.get("rest_pos", Vector3.ZERO)
		h.rolling = true
		_audio.loop_on("roll", "ball_roll_dirt" if Vector2(rest.x, rest.z - 14.0).length() < 26.0 else "ball_roll_grass", -10.0, null, h.ball)
	if h.play.get("infield_fly", false):
		_sfx_later(0.9, "ump_infield_fly", _umpire.global_position + Vector3(0.0, 1.5, 0.0))
	h.trail_inst = MeshInstance3D.new()
	h.trail_inst.mesh = h.trail_mesh
	var hit_mat := StandardMaterial3D.new()
	hit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_mat.albedo_color = Color(0.2, 0.95, 1.0)
	h.trail_inst.material_override = hit_mat
	add_child(h.trail_inst)
	_hits.append(h)
	# Keep the picture readable: only the two most recent batted balls leave a tracer.
	while _hits.size() > 2:
		_free_hit(_hits.pop_front())
	# At contact: the pitch, plus how hard and at what angle it was hit. The full result
	# (distance, hang time, where it went) appears when the ball lands.
	_last_report = head + "\nCONTACT: %s  %.0f mph, launch %+.0f deg" % [
		"foul tip" if b.kind == "foul tip" else "%s" % sim.kind, b.ev, b.la]
	if b.kind == "foul tip":
		var tip_before := _game.bases.duplicate()
		var tip_ev := _game.pitch("foul_tip")
		_begin_pa_exit(tip_ev, tip_before)
		_last_report += "\n" + _event_text(tip_ev)
		_after_event(tip_ev)
	_refresh_hud()
	print(_last_report.replace("\n", " | "))
	var pl: Dictionary = h.play
	var pn: Dictionary = h.plan
	var runner_moves := []
	for r in pn.get("runners", []):
		runner_moves.append({"who": r.who.name if r.who is Player else "?", "from": r.from, "to": r.to, "out": r.out,
			"out_base": r.out_base, "hedge": r.has("hedge")})
	_log("contact", {"contact_kind": b.kind, "bunt": b.get("bunt", false), "ev": b.ev, "la": b.la, "spray": b.get("spray", 0.0),
		"hit_kind": sim.get("kind", ""), "distance": sim.get("distance", 0.0), "apex": sim.get("apex", 0.0),
		"hang": sim.get("hang_time", 0.0), "fair": sim.get("fair", false), "wall": sim.get("wall", false),
		"home_run": sim.get("home_run", false), "ground_rule": sim.get("ground_rule", false),
		"play": pl.get("result", ""), "text": pl.get("text", ""), "fielder": pl.get("fielder", 0),
		"field_time": pl.get("field_time", 0.0), "field_pos": pl.get("field_pos", Vector3.ZERO),
		"caught_in_air": pl.get("caught_in_air", false), "clean_ground": pl.get("clean_ground", false),
		"infield_fly": pl.get("infield_fly", false), "human_chance": h.human_chance,
		"runners": runner_moves, "plan_outs": pn.get("outs_added", 0), "plan_runs": pn.get("runs", 0),
		"plan_text": pn.get("text", ""), "plan_result": pn.get("result", ""),
		"throws": (h.throws as Array).map(func(t): return {"base": t.get("base", 0), "by": t.get("by", 0), "rec": t.get("rec", 0)})})


func _format_hit(b: Dictionary, sim: Dictionary) -> String:
	if b.kind == "foul tip":
		return "FOUL TIP\nExit velo %.0f mph" % b.ev
	var outcome: String
	if sim.home_run:
		outcome = "HOME RUN!"
	elif not sim.fair:
		outcome = "FOUL BALL"
	elif sim.wall:
		outcome = "OFF THE WALL"
	else:
		outcome = sim.kind.to_upper()
	var where := BattedBall.spray_text(sim.spray)
	if sim.wall:
		var wall_at: Vector3 = sim.rest_pos
		var wall_d := Vector2(wall_at.x, wall_at.z).length()
		return "%s  (%s)
Exit velo %.0f mph | Launch %+.0f deg | Spray %+.0f deg
Reaches the wall at %.0f m (%.0f ft) | Apex %.1f m" % [
			outcome, where, sim.ev_mph, sim.launch, sim.spray, wall_d, wall_d * 3.28084, sim.apex]
	if sim.apex < 2.0 and not sim.home_run:
		# A ball that never leaves the ground: report where it rolls to.
		var rest: Vector3 = sim.rest_pos
		var roll := Vector2(rest.x, rest.z).length()
		return "%s  (%s)
Exit velo %.0f mph | Launch %+.0f deg | Spray %+.0f deg
Rolls %.0f m (%.0f ft) | %d bounces" % [
			outcome, where, sim.ev_mph, sim.launch, sim.spray, roll, roll * 3.28084, sim.bounces]
	var feet: float = sim.distance * 3.28084
	return "%s  (%s)\nExit velo %.0f mph | Launch %+.0f deg | Spray %+.0f deg\nDistance %.0f m (%.0f ft) | Apex %.1f m | Hang %.1f s" % [
		outcome, where, sim.ev_mph, sim.launch, sim.spray, sim.distance, feet, sim.apex, sim.hang_time]


func _update_hit(h: LiveHit, delta: float) -> void:
	if h.done:
		h.linger -= delta
		return
	h.t += delta
	var n := h.points.size()
	var path_end := (n - 1) * h.dt
	if h.human_state in ["waiting", "holding", "gripped"]:
		_update_human(h, delta)
	var fielded: bool = not h.play.is_empty() and int(h.play.get("fielder", 0)) != 0 \
		and h.play.get("result", "") not in ["home_run", "foul"] and h.human_state not in ["waiting"]
	var field_t: float = float(h.play.get("field_time", INF)) if fielded else INF

	# Where the ball is: along its flight; then with the fielder; then on its way to a base.
	var idx := 0
	if h.t < minf(path_end, field_t):
		idx = clampi(int(h.t / h.dt), 0, n - 2)
		var f := (h.t - idx * h.dt) / h.dt
		h.ball.global_position = h.points[idx].lerp(h.points[idx + 1], f)
	elif not fielded or h.t < field_t:
		idx = n - 1
		h.ball.global_position = h.points[n - 1]
	else:
		idx = clampi(int(minf(field_t, path_end) / h.dt), 0, n - 1)
		h.ball.global_position = _director.ball_with_fielder(h)

	if h.human_state in ["holding", "gripped"]:
		h.ball.global_position = _held_by_human(h)

	# Grow the trail while the ball is still on its own flight.
	if idx - h.last_idx >= 3 or h.t >= path_end:
		h.last_idx = idx
		h.trail_mesh.clear_surfaces()
		if idx >= 2:
			h.trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			var k := 0
			while k <= idx:
				h.trail_mesh.surface_add_vertex(h.points[k])
				k += 2
			h.trail_mesh.surface_add_vertex(h.points[idx])
			h.trail_mesh.surface_end()

	if h.rolling and (h.t >= minf(path_end, field_t) or h.done):
		h.rolling = false
		if _audio != null:
			_audio.loop_off("roll")
	# Where it came down.
	var grounder: bool = h.summary.wall or (h.summary.apex < 2.0 and not h.summary.home_run)
	var landed_due: bool = h.t >= path_end if grounder else h.t >= float(h.summary.get("landing_time", 1e9))
	if not h.landing_shown and (landed_due or h.t >= path_end):
		h.landing_shown = true
		_show_landing(h)

	if h == _play_hit:
		_director.update_play(h)
	if not h.result_shown and h.t >= h.play_end:
		h.result_shown = true
		_announce_play(h)
	if h.t >= maxf(maxf(h.play_end, path_end), _director.plan_anim_end(h.plan)):
		h.done = true
		h.ball.global_position = h.ball.global_position


# ------------------------------------------------------------------ human fielding
func _human_num() -> int:
	return int(_mode.human_fielders[0]) if not _mode.human_fielders.is_empty() else 0


## Where your glove is: the off-hand controller, a little in front of it.
func _glove_pos(h: LiveHit) -> Vector3:
	if _xr_active and _off_hand and _off_hand.get_is_active():
		return _off_hand.global_transform * Vector3(0.0, 0.0, -0.12)
	if _auto_field and h != null:
		# Debug: a glove that is where the ball will be when the fielder would have reached it.
		if h.t >= float(h.play.get("field_time", 0.0)) - 0.05:
			return h.ball.global_position
	return Vector3(0.0, -50.0, 0.0)


func _held_by_human(h: LiveHit) -> Vector3:
	if h.human_state == "gripped" and _xr_active and _hand:
		return _hand.global_transform * HOLD_OFFSET
	if _xr_active and _off_hand:
		return _glove_pos(h)
	return h.catch_pos


## Each frame while the ball is yours: did the glove get it? did you run out of time?
func _update_human(h: LiveHit, _delta: float) -> void:
	match h.human_state:
		"waiting":
			var ball := h.ball.global_position
			if ball.y < 3.2 and HumanFielding.in_glove(_glove_pos(h), ball, _catch_radius):
				_human_catch(h, ball)
			elif h.t > h.chance_end:
				_human_miss(h)
		"holding", "gripped":
			if _auto_field and h.human_state == "holding" and h.t - h.catch_t > 0.7:
				var from := h.ball.global_position
				var to_first: Vector3 = Defense.FIRST - from
				_human_throw(h, to_first.normalized() * 27.0)
			elif h.t - h.catch_t > HumanFielding.HOLD_LIMIT:
				_human_hold_too_long(h)


func _fielder_play(h: LiveHit, result: String, text: String, extra: Dictionary) -> Dictionary:
	var hn := _human_num()
	var fn := _defense.fielder_by_num(hn)
	var play := {"result": result, "text": text, "short": text, "fielder": hn, "fielder_name": fn.get("name", ""),
		"field_pos": h.catch_pos, "field_time": h.catch_t, "arm": float(fn.get("arm", 33.0)),
		"release_time": h.catch_t + float(fn.get("transfer", 0.45)), "bases": 0, "movements": [],
		"run_times": Defense.RUNNER_TIMES, "caught_in_air": false, "error": false}
	for k in extra:
		play[k] = extra[k]
	return play


func _human_catch(h: LiveHit, ball: Vector3) -> void:
	_haptics.play("catch")
	print("FIELDING: caught at t=%.2f y=%.2f" % [h.t, ball.y])
	h.catch_pos = ball
	h.catch_t = h.t
	var sim := h.summary
	var airborne: bool = ball.y > 0.30 and float(sim.get("landing_time", 0.0)) > 0.0 \
		and h.t <= float(sim.get("landing_time", 0.0)) + 0.04
	var fair: bool = sim.get("fair", false)
	var who: String = _defense.fielder_by_num(_human_num()).get("name", "")
	if airborne:
		var label := "Popout" if sim.get("kind", "") == "Pop-up" else ("Flyout" if sim.get("kind", "") == "Fly ball" else "Lineout")
		var text := "%s to %s" % [label, who] if fair else "Foul out to %s" % who
		h.play = _fielder_play(h, "out", text, {"caught_in_air": true, "foul_out": not fair})
		h.plan = Baserunning.plan(h.play, _game.bases, _game.outs, _batter_player, _run_rng)
		h.play_end = maxf(h.t + 0.6, float(h.plan.end_time))
		h.human_state = "done"
		_last_report_extra = "CAUGHT!"
		return
	if not fair:
		h.play = _fielder_play(h, "foul", "Foul ball", {})
		h.plan = {}
		h.play_end = h.t + 0.5
		h.human_state = "done"
		return
	h.play = _fielder_play(h, "out", "", {})
	h.human_state = "holding"
	_last_report_extra = "GOT IT - throw to a base!"
	h.play_end = 1e9


## The ball got past you (or you never reached it): the rest of the defense plays it.
func _human_miss(h: LiveHit) -> void:
	print("FIELDING: missed at t=%.2f" % h.t)
	h.human_state = "done"
	h.play = h.fallback if not h.fallback.is_empty() else {"result": "single", "text": "Single", "bases": 1,
		"field_pos": h.ball.global_position, "field_time": h.t, "movements": [], "fielder": 0}
	if h.play.get("result", "") in ["foul", ""]:
		h.plan = {}
		h.play_end = maxf(h.t + 0.5, float(h.play.get("field_time", 0.0)))
	else:
		h.plan = Baserunning.plan(h.play, _game.bases, _game.outs, _batter_player, _run_rng)
		h.play_end = maxf(h.t + 0.5, float(h.plan.end_time))
	_last_report_extra = "Got by you"


func _human_hold_too_long(h: LiveHit) -> void:
	h.human_state = "done"
	h.play = _fielder_play(h, "single", "Infield single (held the ball)", {"bases": 1})
	Baserunning.apply_throw(h.plan, 0, 0.0, _game.outs, h.catch_pos, _run_rng)
	h.play_end = maxf(h.t + 0.5, float(h.plan.end_time))


## You let go of the ball with this velocity (m/s, world space).
func _human_throw(h: LiveHit, vel: Vector3) -> void:
	_haptics.play("throw")
	var hn := _human_num()
	var fn := _defense.fielder_by_num(hn)
	var from := h.ball.global_position
	var choice := HumanFielding.pick_base(from, vel, _throw_cone)
	var speed := HumanFielding.throw_speed(vel.length(), 1.0, float(fn.get("arm", 33.0)))
	h.human_state = "thrown"
	h.catch_pos = from if h.catch_pos == Vector3.ZERO else h.catch_pos
	if choice.base == 0:
		# It sails: runners take the base they were going to and one more.
		var wild := _fielder_play(h, "error", "Throwing error, %s (E%d)" % [fn.get("name", ""), hn],
			{"bases": 1, "error": true})
		h.play = wild
		h.plan = Baserunning.plan(wild, _game.bases, _game.outs, _batter_player, _run_rng)
		h.play_end = maxf(h.t + 0.8, float(h.plan.end_time))
		_last_report_extra = "Wild throw!"
		return
	var base: int = choice.base
	print("FIELDING: throw to base %d at %.1f m/s (%.0f deg off)" % [base, speed, choice.err])
	var t_arrive := h.t + HumanFielding.arrival_delay(from, base, speed, float(choice.err))
	var target := HumanFielding.base_position(base)
	Baserunning.apply_throw(h.plan, base, t_arrive, _game.outs, from, _run_rng)
	(h.plan.throws as Array).insert(0, {"from": from, "to": target + Vector3(0.0, 1.0, 0.0),
		"t0": h.t, "t1": t_arrive, "base": base})
	var to_pos := HumanFielding.receiver(base, hn)
	var outs: int = h.plan.outs_added
	var text := ""
	var result := "out"
	if outs >= 2:
		text = "Double play %d-%d-3" % [hn, to_pos]
	elif outs == 1:
		var batter_out := false
		for r in h.plan.runners:
			if r.out and int(r.from) == 0:
				batter_out = true
		text = ("Groundout %d-%d" % [hn, to_pos]) if batter_out else ("Force out at %s, %d-%d" % [
			["", "first", "second", "third", "home"][base], hn, to_pos])
	else:
		result = "single"
		text = "Infield single"
	h.play = _fielder_play(h, result, text, {"bases": 1 if result == "single" else 0,
		"throw": h.plan.throws[0]})
	h.plan["text"] = text
	h.play_end = maxf(t_arrive + 0.6, float(h.plan.end_time))
	_last_report_extra = ("Throw to %s: %s" % [["", "first", "second", "third", "home"][base], "OUT" if outs > 0 else "safe"])


## Thumbstick locomotion: you run to the ball. Speed is your fielder's.
func _move_fielder(delta: float) -> void:
	if _origin == null or _off_hand == null or not _off_hand.get_is_active() or _camera == null:
		return
	var stick: Vector2 = _off_hand.get_vector2("primary")
	if stick.length() < FIELD_LOCOMOTION_MIN:
		return
	var speed := float(_defense.fielder_by_num(_human_num()).get("speed", 7.0))
	var yaw := _camera.global_rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var step := (fwd * stick.y + right * stick.x) * speed * delta
	_origin.global_position += step
	_origin.global_position.y = 0.0


## Holding a ball in the glove: grab it with your throwing hand and throw.
func _poll_fielding(now: float) -> void:
	var h := _holding_hit()
	if h == null or not _hand.get_is_active():
		_field_samples.clear()
		return
	_field_samples.append([now, _hand.global_position])
	while _field_samples.size() > 2 and now - float(_field_samples[0][0]) > 0.15:
		_field_samples.pop_front()
	var grip := _hand.get_float("grip")
	if h.human_state == "holding":
		if grip > GRAB_THRESHOLD and _hand.global_position.distance_to(_glove_pos(h)) < 0.45:
			h.human_state = "gripped"
			_field_samples.clear()
	elif h.human_state == "gripped" and grip < RELEASE_THRESHOLD and _field_samples.size() >= 2:
		var a: Array = _field_samples[0]
		var b: Array = _field_samples[_field_samples.size() - 1]
		var dt := maxf(float(b[0]) - float(a[0]), 0.02)
		var vel: Vector3 = ((b[1] as Vector3) - (a[1] as Vector3)) / dt * velocity_gain
		_human_throw(h, vel)
		_field_samples.clear()


func _holding_hit() -> LiveHit:
	for h in _hits:
		if h.human_state in ["holding", "gripped"]:
			return h
	return null


## A strikeout or a walk ended the at-bat on the pitch: the batter leaves the box (walks off,
## or jogs to first with the men ahead of him moving up) and the next batter walks on.
func _begin_pa_exit(ev: Dictionary, bases_before: Array) -> void:
	if not ev.get("pa_over", false):
		return
	_batter_ready = false
	_log("pa_exit", {"result": ev.get("result", ""), "text": ev.get("text", "")})
	var plan: Dictionary
	if String(ev.get("result", "")) in ["walk", "hit_by_pitch"] or ev.get("batter_reached", false):
		plan = Baserunning.plan_hold(bases_before, _batter_player, true)
		plan["hide_batter_at"] = 0.3
		if String(ev.get("result", "")) == "hit_by_pitch":
			(plan["events"] as Array).append({"t": 0.1, "base": 0, "text": "HIT BY PITCH", "kind": "out",
				"at": Vector3(0.9, 0.0, 0.0)})
	else:
		plan = Baserunning.plan_leave(_batter_player)
	plan["walk_on_when_hidden"] = true
	if String(ev.get("result", "")) == "strikeout":
		plan["keep_bat"] = true            # he carries it back to the dugout
	_aux_play = {"plan": plan, "t": 0.0}
	for lab in _play_labels:
		lab.visible = false
	_refresh_base_runners(bases_before)


## The next batter comes from the dugout to the box. Pitching waits until he is there.
func _begin_walk_on() -> void:
	_crew.return_to_plate()      # the umpire is back behind the plate for the next batter
	if _game != null and not _game.over:
		_sfx("pa_now_batting")
		if randf() < 0.4:
			_sfx("organ_stinger", null, -6.0)
	if _game != null and _game.over:
		_batter_ready = true
		return
	_batter_ready = false
	# A new batter: the last batter's pitch dots are done with.
	if _zone_markers:
		_zone_markers.clear()
	_refresh_hud()
	var duration := _presenter.begin_walk_on(_batter_is_lefty())
	_log("walk_on", {"duration": snappedf(duration, 0.01), "batter": _batter_player.name if _batter_player else ""})
	if _game != null and not _game.over and randf() < 0.5:
		_sfx("music_walkup", null, -10.0)


## True while a ball in play (one with runners moving) has not been announced yet.
func _play_in_progress() -> bool:
	for h in _hits:
		if not h.result_shown and not h.plan.is_empty():
			return true
	return false


func _update_batter_lifecycle(delta: float) -> void:
	_update_flights(delta)
	if not _steal.is_empty():
		if _steal.has("apply_at") and not _steal.get("done", false):
			# Decided on the base: put it in the book (also if the run animation has already ended).
			if _aux_play.is_empty() or float(_aux_play.t) >= float(_steal.apply_at):
				_finish_steal()
		elif _aux_play.is_empty():
			_steal = {}            # the delivery never became a pitch: nothing to resolve
	# Safety net: if nothing is happening that could make the batter ready, make him ready.
	var busy := not _aux_play.is_empty() or not _walk_on.is_empty()
	for h in _hits:
		if not h.result_shown:
			busy = true
	if _batter_ready or busy:
		_unready_for = 0.0
	else:
		_unready_for += delta
		if _unready_for > 2.0:
			GameLog.mark("watchdog: the batter was not ready for 2 s and nothing explained it", _snapshot())
			_batter_ready = true
			_batter.visible = true
			_batter.set_carry(false, true)
			_batter.transform = _batter_home
			_unready_for = 0.0
	if not _aux_play.is_empty():
		_aux_play.t += delta
		var plan: Dictionary = _aux_play.plan
		_director.animate_plan(plan, float(_aux_play.t))
		if float(_aux_play.t) >= _director.plan_anim_end(plan):
			_aux_play = {}
			_runner.visible = false
			for lv in _leavers:
				lv.visible = false
			_refresh_base_runners()
			_refresh_scoreboard()
	_presenter.update(delta)


## The batter-runner has left the box: his bat drops (unless he carries it off), and if the plan says
## so the next batter starts walking on.
func _on_batter_hidden(plan: Dictionary) -> void:
	if not plan.get("keep_bat", false):
		_drop_bat()
	_batter.visible = false
	if plan.get("walk_on_when_hidden", false):
		_begin_walk_on()


## He is in the box: the pitcher may throw.
func _on_batter_arrived() -> void:
	_sfx("batter_step_dirt", _batter_home.origin)
	if randf() < 0.5:
		_sfx_later(0.5, "bat_tap_plate", Vector3(0.0, 0.1, 0.0), -4.0)
	_batter_ready = true
	_refresh_hud()


## The play is over: tell the scorebook, say what happened.
func _announce_play(h: LiveHit) -> void:
	var play := h.play
	var text: String = play.get("text", "")
	var ev := {}
	if h.summary.get("home_run", false):
		text = "HOME RUN!"
		ev = _game.in_play({"result": "home_run"}, h.plan)
	elif play.is_empty():
		return
	elif play.get("foul_tip", false):
		# Already counted when the bat hit it (a tip into the mitt is a strike on the spot).
		_last_report = "FOUL TIP
" + h.report
		_refresh_hud()
		return
	elif play.get("result", "") == "foul":
		var bases_foul := _game.bases.duplicate()
		_crew.call_it("ump_foul", 0.1, 1.0)
		ev = _game.pitch("foul_bunt" if h.bunt else "foul")
		text = "Foul bunt" if h.bunt else "Foul ball"
		if ev.get("pa_over", false):
			_begin_pa_exit(ev, bases_foul)
	else:
		ev = _game.in_play(play, h.plan)
		if play.get("ground_rule", false):
			_sfx_later(0.3, "ump_time", _umpire.global_position + Vector3(0.0, 1.5, 0.0))      # dead ball: two bases
	if _runner:
		_runner.visible = false       # he is on a base now (or out): the base figures take over
	_last_report_extra = ""
	var lines := text.to_upper() + "\n" + h.report
	if not ev.is_empty():
		var extra := _event_text(ev)
		if extra != "":
			lines += "\n" + extra
	_last_report = lines
	_after_event(ev, {"ev": float(h.summary.get("ev_mph", 0.0)), "dist": float(h.summary.get("distance", 0.0))})
	_refresh_hud()
	_log("play_result", {"text": text, "result": ev.get("result", ""), "runs": ev.get("runs", 0), "outs_added": ev.get("outs_added", 0),
		"pa_over": ev.get("pa_over", false), "half_over": ev.get("half_over", false), "game_over": ev.get("game_over", false),
		"state_text": ev.get("text", ""), "duration": snappedf(h.t, 0.01)})
	print(_last_report.replace("\n", " | "))


## Words for what a pitch or play did to the game.
func _event_text(ev: Dictionary) -> String:
	if ev.is_empty():
		return ""
	var parts: Array[String] = []
	if ev.get("text", "") != "":
		parts.append(ev.text)
	if ev.get("runs", 0) > 0 and "run" not in String(ev.get("text", "")):
		parts.append("%d run%s" % [ev.runs, "" if ev.runs == 1 else "s"])
	if ev.get("pa_over", false) and ev.get("result", "") == "strikeout":
		parts.append("Strikeout")
	if ev.get("half_over", false):
		parts.append("THREE OUTS - end of inning %d" % int(ev.get("inning_ended", _game.inning - 1)))
		if ev.has("home_runs_scored"):
			parts.append("Bottom %d: Home %s" % [int(ev.inning_ended), "scores %d" % int(ev.home_runs_scored) if int(ev.home_runs_scored) > 0 else "goes down in order"])
	if ev.get("game_over", false):
		parts.append(_game.final_text() + " | " + _game.line_text())
	return " | ".join(parts)


## What you did in this game, as one pitching line.
func _game_line() -> Dictionary:
	var t := _stats.pitch_totals()
	var n := maxi(int(t.n), 1)
	return {"outs": _game.outs_recorded, "pitches": _game.pitch_count, "strikes": int(t.strikes), "k": _game.strikeouts,
		"bb": _game.walks, "h": _game.hits, "r": _game.runs, "hr": _game.home_runs,
		"max_mph": float(t.mph_max), "avg_mph": float(t.mph_sum) / n,
		"won": _game.home_score > _game.runs, "lost": _game.home_score < _game.runs,
		"score_for": _game.home_score, "score_against": _game.runs}


## A finished game goes in the book (only games you pitch that count for a leaderboard).
func _record_finished_game() -> void:
	if _game_recorded or not _mode.human_pitcher:
		return
	_game_recorded = true
	var cfg := _current_config()
	if not cfg.is_scored():
		return
	var line := _game_line()
	var r := _profile.record_game(cfg, line)
	_profile.save()
	var text := "Game Score %d" % int(r.score)
	if int(r.rank) == 1:
		text += " - best on this board!"
	elif int(r.rank) > 0:
		text += " - #%d on this board" % int(r.rank)
	_log("game_recorded", {"score": r.score, "rank": r.rank, "key": r.key, "line": line})
	_show_notice(text, true)


## After anything that changes the game: next batter, runners, scoreboard, game over.
func _after_event(ev: Dictionary, extra: Dictionary = {}) -> void:
	if ev.is_empty():
		return
	if _sound != null:
		_sound.crowd_react(ev, _game)
	match String(ev.get("result", "")):
		"home_run":
			_haptics.play("rumble", 1.0)
		"strikeout":
			_haptics.play("rumble", 0.3)
	if ev.get("pa_over", false):
		if _batter_player:
			_stats.record_result(_batter_player.name, String(ev.get("result", "out")),
				float(extra.get("ev", 0.0)), float(extra.get("dist", 0.0)))
		_sync_batter()
		if _aux_play.is_empty():
			_begin_walk_on()          # after a ball in play the next batter comes up now
	elif _aux_play.is_empty() and _walk_on.is_empty() and not _play_in_progress():
		_batter_ready = true          # a foul (or any pitch that did not end the at-bat): he is still up
	if ev.get("game_over", false):
		_record_finished_game()
		_game_over_timer = 8.0
		_log("game_over", {"final": _game.final_text(), "line": _game.line_text(), "stats": {"k": _game.strikeouts,
			"bb": _game.walks, "hits": _game.hits, "wp": _game.wild_pitches, "sb": _game.stolen_bases, "cs": _game.caught_stealing,
			"po": _game.pickoffs, "balks": _game.balks, "hbp": _game.hit_by_pitches, "sac": _game.sacrifices}})
	if ev.get("half_over", false):
		_log("half_over", {"inning": ev.get("inning_ended", 0), "home_runs_scored": ev.get("home_runs_scored", -1),
			"runs": _game.runs, "home": _game.home_score})
	if _aux_play.is_empty():
		_refresh_base_runners()
	_refresh_scoreboard()


func _refresh_scoreboard() -> void:
	if _stadium == null or _game == null:
		return
	var g := _game
	var who := _batter_player.name if _batter_player else ""
	var line := ""
	if _batter_player:
		var bs: Dictionary = _stats.batters.get(who, {})
		line = StatsTracker.avg_text(int(bs.get("h", 0)), int(bs.get("ab", 0))) if not bs.is_empty() else ""
		line = ("%s  %d-%d today" % [line, int(bs.get("h", 0)), int(bs.get("ab", 0))]) if not bs.is_empty() else ""
	var pitcher := "YOU" if _mode.human_pitcher else _ai_pitcher.player.name
	_stadium.set_scoreboard({
		"inning": g.inning, "innings": maxi(g.innings, g.inning), "inning_runs": g.inning_runs, "runs": g.runs,
		"home_inning_runs": g.home_inning_runs, "home_runs": g.home_score, "home_hits": g.home_team_hits,
		"hits": g.hits, "errors": g.errors, "balls": g.balls, "strikes": g.strikes, "outs": g.outs,
		"batter": who, "batter_line": line, "pitcher": pitcher,
		"last_kind": String(_stats.last_pitch.get("kind", "")), "last_mph": float(_stats.last_pitch.get("mph", 0.0)),
		"final": g.over})


## Figures on the bases that match the scorebook.
func _refresh_base_runners(bases: Array = []) -> void:
	if _game == null:
		return
	var on: Array = bases if bases.size() == 3 else _game.bases
	if _base_runners.is_empty():
		for i in 3:
			var fig := _runner_doll(_director.stand_for(i + 1))
			fig.idle_bounce = true             # on his toes off the bag
			fig.crouch = 0.6
			fig.visible = false
			_base_runners.append(fig)
	for i in 3:
		var who = on[i]
		_leads[i] = StealModel.lead(who as Player, int(_since_throw[i])) if who is Player else 2.4
		_base_runners[i].visible = on[i] != null
		(_base_runners[i] as Doll).watching = false
		_base_runners[i].position = _director.stand_for(i + 1)
		_base_runners[i].rotation.y = atan2(-Baserunning.BASE_POS[i + 1].x, -Baserunning.BASE_POS[i + 1].z)


func _show_landing(h: LiveHit) -> void:
	var sim := h.summary
	var bounce: Vector3 = sim.get("landing_pos", Vector3.ZERO)
	if sim.home_run:
		var fc: Vector3 = sim.get("fence_cross", bounce)
		_sfx("ball_into_stands", fc)
		if absf(absf(fc.x) - fc.z) < 1.5:
			_sfx_later(0.05, "ball_hits_pole", fc + Vector3(0.0, 2.0, 0.0))         # right down the line: off the pole
	elif sim.wall:
		_sfx("ball_hits_wall", sim.get("rest_pos", bounce) as Vector3)
		_sfx_later(0.12, "fence_rattle", sim.get("rest_pos", bounce) as Vector3)
	elif not sim.fair:
		_sfx_later(0.1, "seat_flip_clatter", bounce, -4.0)               # a foul into the seats
	elif sim.fair:
		var dirt := Vector2(bounce.x, bounce.z - 14.0).length() < 26.0
		_sfx("ball_bounce_dirt" if dirt else "ball_bounce_grass", bounce, -3.0)
	if _dust != null and not sim.home_run and Vector2(bounce.x, bounce.z - 14.0).length() < 26.0:
		_dust.puff(Vector3(bounce.x, 0.0, bounce.z), 0.5, 3)           # it came down in the infield dirt
	var spot: Vector3 = sim.landing_pos
	var shown_distance: float = sim.distance
	if sim.wall or (sim.apex < 2.0 and not sim.home_run):
		spot = sim.rest_pos
		shown_distance = Vector2(spot.x, spot.z).length()
	elif sim.home_run and sim.has("fence_cross"):
		spot = sim.fence_cross
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.25
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.1) if sim.fair else Color(0.9, 0.9, 0.9)
	h.marker = MeshInstance3D.new()
	h.marker.mesh = ring
	h.marker.material_override = mat
	h.marker.position = Vector3(spot.x, 0.05, spot.z)
	add_child(h.marker)
	h.label = Label3D.new()
	h.label.text = ("HR  %.0f m" if sim.home_run else "%.0f m") % shown_distance
	h.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	h.label.fixed_size = true
	h.label.pixel_size = 0.0016
	h.label.font_size = 64
	h.label.outline_size = 14
	h.label.modulate = Color(1.0, 0.85, 0.2)
	h.label.no_depth_test = true
	h.label.position = Vector3(spot.x, maxf(spot.y, 0.0) + 3.0, spot.z)
	add_child(h.label)
	if h.play.is_empty():
		_last_report = h.report
		_refresh_hud()
		print(h.report.replace("\n", " | "))


func _free_hit(h: LiveHit) -> void:
	if h.rolling and _audio != null:
		_audio.loop_off("roll")
	if h == _play_hit:
		_director.reset_fielders()
		_play_hit = null
	h.ball.queue_free()
	h.trail_inst.queue_free()
	if h.marker:
		h.marker.queue_free()
	if h.label:
		h.label.queue_free()


## Put this pitch on the zone as a dot colored by where it crossed, with a halo for the result.
func _mark_pitch(a: Dictionary, outcome: String) -> void:
	if _zone_markers == null or not a.get("reached", false):
		return
	var p: Vector3 = a.plate_pos
	_sfx("zone_dot_pop", Vector3(p.x, p.y, 0.0), -8.0)
	var loc := PitchLocation.classify(p.x, p.y)
	var halo := Color(0.0, 0.0, 0.0, 0.0)
	match outcome:
		"in_play":
			halo = Color(0.2, 0.9, 1.0, 1.0)
		"swinging_strike":
			halo = Color(1.0, 1.0, 1.0, 1.0)
		"foul":
			halo = Color(0.6, 0.6, 0.6, 1.0)
		_:
			if loc.halo:
				halo = Color(1.0, 0.82, 0.15, 1.0)      # a corner that was not hit
	_zone_markers.add(p.x, p.y, loc.color, halo)


func _format_report(label: String, a: Dictionary) -> String:
	var head := "%s\n%.1f mph | %d rpm" % [label, a.speed_mph, roundi(a.spin_rpm)]
	if not a.reached:
		return head + "\nDid not reach the plate"
	var p: Vector3 = a.plate_pos
	var text := head + "\nPlate %.1f mph in %.2fs" % [a.plate_mph, a.time]
	if a.has("ivb_in"):
		text += "\nInduced vert %+.1f in | horiz %+.1f in" % [a.ivb_in, a.hb_in]
	text += "\n%s  %s  (%+.1f in x, %.1f in y)" % [
		"STRIKE" if a.strike else "BALL", PitchLocation.classify(p.x, p.y).label, p.x * PitchPhysics.M_TO_IN, p.y * PitchPhysics.M_TO_IN]
	return text


## Inject a batted ball without a pitch (for looking at fielding and baserunning).
## The defense's answer for a ball in play. If a human plays the position that would field it,
## the ball is his chance, and the AI's version is what happens when he misses.
func _resolve_ball(pitch: LivePitch) -> void:
	var run_f := _batter_player.run_factor() * _run_rng.randf_range(0.97, 1.03)
	# You are the pitcher: the ball is not yours to field (yet), so an AI one stays out of it.
	var skip: Array = [1] if _mode.human_pitcher else []
	pitch.play = _defense.resolve(pitch.sim, run_f, skip)
	if pitch.bat.get("bunt", false):
		pitch.play["bunt"] = true
	if not _mode.human_fielders.is_empty():
		var hn: int = _mode.human_fielders[0]
		if int(pitch.play.get("fielder", 0)) == hn and pitch.play.get("result", "") != "home_run":
			pitch.human_chance = true
			pitch.play_fallback = _defense.resolve(pitch.sim, run_f, [hn])


func _debug_hit(ev_mph: float, launch_deg: float, spray_deg: float) -> void:
	var v := ev_mph / PitchPhysics.MPS_TO_MPH
	var la := deg_to_rad(launch_deg)
	var psi := deg_to_rad(spray_deg)
	var dir_h := Vector3(sin(psi), 0.0, cos(psi))
	var vel := dir_h * (v * cos(la)) + Vector3.UP * (v * sin(la))
	var spin := dir_h.cross(Vector3.UP).normalized() * (1800.0 * PitchPhysics.RPM_TO_RADS)
	var origin := Vector3(0.0, 0.9, 0.4)
	var rel := Vector3(0.0, PitchPhysics.MOUND_H + 1.85, PitchPhysics.MOUND_Z - 1.7)
	var pv := PitchPhysics.solve_aim(rel, 36.0, Vector3.ZERO, Vector3(0.0, 0.85, 0.0))
	var pitch := LivePitch.new()
	pitch.pos = origin
	pitch.label = "Test pitch"
	pitch.analysis = PitchPhysics.analyze(rel, pv, Vector3.ZERO)
	pitch.bat = {"swing": true, "contact": true, "kind": "hit", "ev": ev_mph, "la": launch_deg,
		"vel": vel, "spin": spin, "contact_pos": origin, "bat_target": origin, "contact_time": 0.0}
	pitch.sim = BattedBall.simulate(origin, vel, spin)
	_resolve_ball(pitch)
	pitch.ball = _make_ball()
	pitch.trail_inst = MeshInstance3D.new()
	pitch.trail_inst.mesh = pitch.trail_mesh
	add_child(pitch.trail_inst)
	_pitches.append(pitch)
	_swings += 1
	_contact(pitch)


func _debug_throw() -> void:
	var names := PitchPhysics.CANNED.keys()
	var key: String = names[_canned_index % names.size()]
	_canned_index += 1
	var def: Dictionary = PitchPhysics.CANNED[key]
	var rel := Vector3(0.0, PitchPhysics.MOUND_H + 1.85, PitchPhysics.MOUND_Z - 1.7)
	var spin: Vector3 = (def.rpm as Vector3) * PitchPhysics.RPM_TO_RADS
	var target := Vector3(randf_range(-0.15, 0.15), randf_range(0.6, 1.0), 0.0)
	var v := PitchPhysics.solve_aim(rel, float(def.mph) / PitchPhysics.MPS_TO_MPH, spin, target)
	_launch(rel, v, spin, key)


func _rebuild_trail(pitch: LivePitch) -> void:
	pitch.trail_mesh.clear_surfaces()
	if pitch.trail.size() < 2:
		return
	pitch.trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pitch.trail:
		pitch.trail_mesh.surface_add_vertex(p)
	pitch.trail_mesh.surface_end()


func _settings_line() -> String:
	var line := "mode: %s" % _mode.name
	if _mode.human_pitcher:
		line += " | %s aim | %s spin | tag: %s" % [
			AimMode.keys()[aim_mode].to_lower().replace("_", " "),
			SpinMode.keys()[spin_mode].to_lower().replace("_", " "), _current_tag()]
	else:
		line += "\npitching: " + _ai_pitcher.player.pitcher_line()
	if _batter_player:
		line += "\nat bat: " + _batter_player.hitter_line()
	return line


func _set_hud_idle() -> void:
	if _xr_active:
		_last_report = "Hold GRIP to pick up the ball.\nThrow, then open your hand."
	else:
		_last_report = "No headset found.\nPress SPACE to throw a canned pitch."
	_refresh_hud()


func _show_notice(text: String, quiet: bool = false) -> void:
	if not quiet:
		_sfx("ui_notice", null, -6.0)
	_notice = text
	_notice_until = Time.get_ticks_msec() / 1000.0 + 1.6
	_refresh_hud()


func _short_name(full: String) -> String:
	var parts := full.split(" ")
	if parts.size() < 2:
		return full
	return "%s. %s" % [parts[0].substr(0, 1), parts[parts.size() - 1]]


## Break a long report line at its " | " separators so it fits the board.
func _wrap(text: String, max_chars: int = 58) -> Array:
	var out: Array = []
	for raw in text.split("\n"):
		var line := ""
		for piece in raw.split(" | "):
			if line != "" and line.length() + piece.length() + 3 > max_chars:
				out.append(line)
				line = piece
			else:
				line = piece if line == "" else line + " | " + piece
		if line != "":
			out.append(line)
	return out


func _refresh_hud() -> void:
	if _pitch_board == null:
		return
	# --- Pitching: what you have thrown.
	var g := _game
	var t := _stats.pitch_totals()
	_pitch_board.title = "PITCHING"
	_pitch_board.subtitle = _mode.name if _mode else ""
	_pitch_board.accent = Color(0.12, 0.40, 0.78)
	_pitch_board.tiles = [
		[g.innings_pitched_text() if g else "0.0", "IP"], [str(g.pitch_count) if g else "0", "PITCHES"],
		[str(g.strikeouts) if g else "0", "K"], [str(g.walks) if g else "0", "BB"], [str(g.hits) if g else "0", "H"]]
	_pitch_board.columns = [{"head": "PITCH", "w": 0.34, "align": "l"}, {"head": "#", "w": 0.10, "align": "r"},
		{"head": "AVG", "w": 0.17, "align": "r"}, {"head": "MAX", "w": 0.15, "align": "r"},
		{"head": "STR%", "w": 0.12, "align": "r"}, {"head": "WHF%", "w": 0.12, "align": "r"}]
	var prow: Array = []
	for k in _stats.types_sorted():
		var x: Dictionary = _stats.by_type[k]
		prow.append([k, x.n, "%.0f" % _stats.avg_mph(x), "%.0f" % x.mph_max, "%.0f" % _stats.strike_pct(x),
			("%.0f" % _stats.whiff_pct(x)) if x.swings > 0 else "-"])
	if prow.is_empty():
		prow.append(["-", "", "", "", "", ""])
	else:
		prow.append(["TOTAL", t.n, "%.0f" % (_stats.avg_mph(t)), "%.0f" % t.mph_max, "%.0f" % _stats.strike_pct(t),
			("%.0f" % _stats.whiff_pct(t)) if t.swings > 0 else "-"])
	_pitch_board.rows = prow
	_pitch_board.total_row = prow.size() > 1
	var pl: Array = []
	if g:
		pl.append("%s   |   %d R" % [g.situation_text(), g.runs])
	_pitch_board.lines = pl
	_pitch_board.refresh()

	# --- Batting: how the lineup has done against you.
	var bt := _stats.batting_totals()
	_bat_board.title = "BATTING"
	_bat_board.subtitle = "vs you"
	_bat_board.accent = Color(0.72, 0.18, 0.20)
	_bat_board.tiles = [[StatsTracker.avg_text(bt.h, bt.ab), "AVG"], [str(bt.h), "H"], [str(bt.hr), "HR"],
		[str(bt.k), "K"], [("%.0f" % (_stats.ev_sum / maxf(float(_stats.ev_count), 1.0))) if _stats.ev_count > 0 else "-", "AVG EV"]]
	_bat_board.columns = [{"head": "BATTER", "w": 0.34, "align": "l"}, {"head": "AB", "w": 0.10, "align": "r"},
		{"head": "H", "w": 0.10, "align": "r"}, {"head": "HR", "w": 0.10, "align": "r"},
		{"head": "BB", "w": 0.10, "align": "r"}, {"head": "K", "w": 0.10, "align": "r"},
		{"head": "AVG", "w": 0.16, "align": "r"}]
	var brow: Array = []
	for n in _stats.batter_order:
		var b: Dictionary = _stats.batters[n]
		brow.append([_short_name(n), b.ab, b.h, b.hr, b.bb, b.k, StatsTracker.avg_text(b.h, b.ab)])
	brow.append(["TOTAL", bt.ab, bt.h, bt.hr, bt.bb, bt.k, StatsTracker.avg_text(bt.h, bt.ab)])
	_bat_board.rows = brow
	var bl: Array = []
	if _stats.ev_count > 0:
		bl.append("Hardest hit %.0f mph (%s)   |   Longest %.0f m" % [_stats.ev_max, _short_name(_stats.hardest_name), _stats.longest])
	_bat_board.lines = bl
	_bat_board.refresh()

	# --- The last pitch / play, and notices.
	_info_board.show_plot = true
	_info_board.plot = _zone_markers.entries() if _zone_markers else []
	_info_board.title = "LAST PITCH"
	_info_board.subtitle = _batter_player.name if _batter_player else ""
	_info_board.accent = Color(0.18, 0.50, 0.30)
	var info: Array = []
	if _notice != "":
		info.append(">> " + _notice)
	info.append_array(_wrap(_last_report))
	if _last_report_extra != "":
		info.append(">> " + _last_report_extra)
	if _batter_player:
		info.append_array(_wrap(_batter_player.hitter_line()))
	while info.size() > 9:
		info.pop_front()
	_info_board.lines = info
	_info_board.refresh()
