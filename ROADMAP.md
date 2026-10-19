# VR Baseball: review and roadmap

Written 2026-10-18, after the audio pass. This replaces the five-line roadmap that used to be in
`DESIGN.md`. `DESIGN.md` remains the record of how each system works; this file is where the game
stands and what to build next, in order.

Every claim is tagged:
- **[measured]**: a number we ran today.
- **[code]**: read from the source.
- **[estimate]**: judgement.

Sizes are in working sessions like the ones we have been doing:
- **S**: one session.
- **M**: 2-4 sessions.
- **L**: 5 or more sessions.

---

## Phased checklist

`[x]` done, `[ ]` open, `[~]` partly done (the note says what is left). The detail, reasoning and exit
criteria for each phase are in section 5; this is the at-a-glance view. Updated 2026-10-18.

### Phase 0 - Safety and housekeeping (M0) - DONE
- [x] Put the project under git; baseline commit before the fixes
- [x] Commit the placeholder audio (so real recordings can never be ignored by accident)
- [x] B1 main menu music, and pause ducking and loops
- [x] B2 delayed sounds run on game time (stop while paused)
- [x] B3 left-handed batters (box side, mirrored figure, hit-by-pitch side)
- [x] B4 check swing no longer draws from the gameplay random numbers
- [x] B5 `PERFORMANCE.md` numbers updated; superseded "not modelled" notes in `DESIGN.md` marked
- [x] B6 off-screen bottom half seeded from the game seed (`--seed=N`, logged)
- [x] Test: every sound id the code plays exists in the manifest (`hygiene_test`)
- [x] Test: the menu theme plays on the main menu; pause ducks (`hygiene_test`)
- [x] Refresh `PLAYTEST.md` for the new behaviours
- [x] `ROADMAP.md` at the project root

### Phase 1 - Run standalone on a Quest 3 (M1) - SKIPPED FOR NOW (needs the headset and an export setup)
- [ ] Android export preset, arm64, OpenXR vendors plugin for Meta; `tools/deploy.sh`
- [ ] Measure on the device: frame time, draw calls, a busy play (double play with dust and sound)
- [ ] Measure the third-out frame (off-screen bottom half) on the device
- [ ] Measure the 71 `Label3D` nodes (boards) and audio memory (24 MB of PCM)
- [ ] If the numbers ask: spread `HalfInningSim` over frames or a thread
- [ ] If the numbers ask: bake board text into textures / cut the label count
- [ ] If the numbers ask: convert loops and music to Ogg; reduce per-frame Doll work for far dolls
- [ ] `--quest-budget` mode in `perf.sh` with device-calibrated limits
- [ ] Exit: a 3-inning game runs at the headset's refresh rate in busy plays, or a written PC-VR-only decision

### Phase 2 - Playtest and tune what exists (M2) - NEXT, needs you in the headset
- [ ] Work through `docs/PLAYTEST.md` (sections 0-12) with logging on and marks
- [ ] Pitching feel: funnel per assist, release timing; gesture confusion matrix (each gesture at 80%+)
- [ ] Animation readability from the mound (catcher glove, slides and dives, soft vs paper at distance)
- [ ] Audio mix: bus levels, mitt pop and bat crack on the frame, crowd busyness; drop placeholders worse than silence
- [ ] Haptics: amplitudes and durations by feel
- [ ] Balance: BABIP (about .33, slightly high), triple-play rate, steal success, AI intentional walks
- [ ] Challenges: are the six fair and fun (parameters at the top of `scripts/scenario.gd`)
- [ ] Exit: two full 3-inning games with no blocking marks; confusion matrix in `DESIGN.md`; tuned mix

### Phase 3 - Split `bullpen.gd` (M3) - MOSTLY DONE
- [x] `SoundDirector` (what is heard and why)
- [x] `PlateCrew` (catcher and umpire, signals, own test)
- [x] `FieldProps` (dust, dropped bats, game-time delay queue, own test)
- [x] `BatterPresenter` (walk-on, box side, takes, bat drop, own test)
- [x] `PlayDirector` (fielders, ball hand-to-glove, throws, runners, callouts)
- [x] `LiveHit` / `LivePitch` data classes (were inner classes)
- [ ] `PitchFlight` (pitch launch, flight, landing, contact detection)
- [ ] `HumanPitcher` (XR input, throw detection, funnel aim, delivery timing, pickoff throws)
- [ ] `GameDirector` (game flow, AI pitcher pacing, steals, menu hooks); `bullpen.gd` under 800 lines (now about 2,800)
- [ ] Event bus: typed events (`pitch_arrived`, `contact`, `play_event`, `pa_over`, `half_over`, `game_over`) replacing the remaining direct calls
- [ ] Typed plans (`PlayPlan`, `RunnerPlan`, `ThrowPlan`) instead of dictionaries
- [~] One RNG per concern: gameplay, cosmetic and bottom-half generators are separate and seeded; the AI classes (`AIPitcher`, `BatterAI`, `Defense`, `GameState`) still self-seed for the half you pitch
- [~] Test: a seed replays the game (only the bottom half is covered so far)
- [~] Each presenter has a test (`PlateCrew`, `FieldProps`, `BatterPresenter` do; `SoundDirector` and `PlayDirector` are covered only through the full-game tests)

### Phase 4 - Core VR feel (M4) - STARTED
- [x] Controller haptics (event table, Options > Haptics, menu pulses in the pointing hand)
- [ ] Hand model holding the ball; grip shape that teaches the recognised pitch at easier assists
- [ ] Glove model on the off hand
- [ ] Pitch lab (Bullpen mode rebuilt): recognised pitch, spin axis, break, speed, location, "what made it a slider"
- [ ] First-run tutorial: calibrate your normal throw, then one gesture per pitch type
- [ ] Catcher signs (pitch and location called, shake-offs, a bonus for hitting the sign)
- [ ] Comebackers: catch a ball hit at you with the glove hand
- [ ] Seated mode with height calibration
- [ ] Verify left-handed throwing end to end
- [ ] Colour-blind palette for the zone colours
- [ ] Text for umpire calls
- [ ] Exit: a new player can calibrate, learn three pitches and play a game with no one explaining

### Phase 5 - A game you come back to (M5) - HALF DONE
- [x] Persistence: saved game lines, lifetime totals, best games per leaderboard (`PlayerProfile`)
- [x] Stats screen (main menu) with lifetime lines and top five per board
- [x] Local leaderboards per mode, length and assist level, ranked by Game Score
- [x] Challenge scenarios: six, with 0-3 stars, a Challenges menu, results saved
- [x] Tests never touch the player's profile
- [ ] Per-pitch-type metrics over time in the profile; box scores per game
- [ ] Leaderboards for Fielding mode
- [ ] Create a pitcher (name, hand, look)
- [ ] A season of starts in a fictional league; the other games simulated with the existing engine (`HalfInningSim` generalised)
- [ ] Standings and your stat line
- [ ] Ratings that grow from use (command, stamina, new pitches from the pitch lab); physics never gated
- [ ] League data: fictional teams, names, parks, uniform colours, a schedule
- [ ] Exit: a 10-start season playable with saved progress, standings and a stats screen

### Phase 6 - More roles (M6)
- [~] Human fielding: 1B to RF exist (`--field-pos`); open: pitcher and catcher, first base taking throws, tuning in the headset
- [ ] Wild throws let runners advance
- [ ] Fielding drills ("ten grounders to short")
- [ ] Catcher as a position (framing and blocking mini-game)
- [ ] Hitting: bat in hand with tracked swing physics (reuse `BattedBall`), pitch recognition, timing feedback
- [ ] Batting practice and home-run derby
- [ ] Role switching in a game (pitch your half, hit in the bottom, or field)

### Phase 7 - Rest of the rulebook and the manager (M7)
- [x] Intentional walk (pause menu, pitching mode)
- [ ] Rundowns
- [ ] Squeeze, hit-and-run, infield in
- [ ] Base umpires
- [ ] Pitching changes you control (bullpen phone), mound visits, an intentional-walk gesture
- [ ] Pickoff moves from the stretch; pitcher covering first and backing up bases
- [ ] Platoon effects (left-handed batters now exist)
- [ ] Pitching change PA call (`pa_pitching_change`, the one sound with no trigger) and `pa_number_digits`

### Phase 8 - Production (M8, mostly assets)
- [ ] Commit to one art style (decision 3 below)
- [ ] Proper character models, or the procedural rig refined in the chosen style
- [ ] Hero pass: catcher, batter, your own hands
- [ ] 2-3 parks, day and night
- [ ] Animated crowd (shader bob, stand for home runs)
- [ ] Record and source the P0 audio (mitt, bat, crowd, umpire voice), then P1; real music
- [ ] Menu and board art pass, transitions, between-innings presentation
- [ ] Store readiness if shipping on Meta (comfort rating, performance, entitlement, privacy policy)

### Later
- [ ] Async ghost multiplayer (same seed, same lineup)
- [ ] Weather and altitude
- [ ] Replay camera for big plays

### Decisions waiting for you
- [ ] Standalone Quest or PC VR as the target (recommendation: measure in Phase 1 first)
- [ ] Arcade/challenges first or career first (recommendation: challenges first; challenges are now in)
- [ ] One art style, soft or paper
- [ ] When hitting comes (largest feature after career; needs Phase 3 finished)

### Animation and audio, from the earlier plans
- [x] Catcher glove tracking with IK, block, chase, pop-up throw; umpire calls and movement
- [x] Batter on the shared rig: swing, bunt, check swing, flinch, bat carry and drop, left-handed mirror
- [x] Fielder scoop, backhand, jump catch, reaction step, tag, dive
- [x] Runner lead bounce, fly-ball watching, turn lean, slide, dive-back, celebration
- [x] Dust puffs; throws end in the receiver's glove; double-play pivot man throws on
- [x] `AudioManager` with buses, crowd beds, music and stems, loops that follow the ball; 457 placeholder files; all but two sounds wired
- [ ] Chalk puffs, grass kick, glove-pop ring, bat-hit flash; coaches; dugout reactions; high fives and helmet toss
- [ ] Real recordings replacing the placeholders (`docs/AUDIO.md`, `docs/AUDIO_LIST.md`)

---

## 1. Where the game is

| Area | State |
|---|---|
| Size | 11.3k lines of GDScript in `scripts/`, 3.1k in `tests/` (23 suites), Python and shell tooling **[measured]** |
| Pitching (the core) | Throw detection, wrist and technique model producing 7 pitch types, data-validated aim funnel, custom flight physics, fatigue, delivery timing, pickoffs and balks **[code]** |
| Batting AI | Perceive / decide / time / aim / collide model; six archetypes plus rated players; bunts; check swings **[code]** |
| Defense and running | Interception search per fielder; throws scored by expected outs; DP/TP, tag-ups, hedging, liner double-offs, time plays, cutoffs, steals, wild pitches **[code]** |
| Rules | Count, innings, two-sided games (bottom half simulated off-screen), extras, walk-off, HBP, IBB, infield fly, ground-rule double, dropped third strike, relievers **[code]** |
| People | One 11-bone `Doll` rig, two skins (soft and paper), about 20 clips plus IK; catcher, umpire, batter, fielders and runners all on it **[code]** |
| Presentation | Park, boards, scoreboard, zone markers, dust; a full audio system with 457 placeholder files **[code]** |
| Modes | Pitching: playable. Spectate: playable. Fielding: partial (any position from 1B to RF via `--field-pos`, but not pitcher or catcher, and untuned in the headset). Hitting: not built. **[code]** |
| Meta | Settings and menu only. Stats and leaderboards say "coming soon"; leaderboard keys exist but nothing is stored. No career. **[code]** |
| Tested where | Headless tests and desktop screenshots. Played in the headset only through Virtual Desktop from the PC, and not since the last several features. **[code / from our sessions]** |

The simulation is the game's strength. Most of the rest has been built quickly on top of it and
has not yet been felt in the headset.

---

## 2. What is good (keep doing it)

1. **The simulation is pure, separate and tested.**
   - `GameState`, `Baserunning`, `Defense`, `BatterAI`, `StealModel`, `MenuModel`, `Settings` and
     `AudioManager` have no scene dependencies and are covered by headless suites. **[code]**
   - Rule changes this week (triple play, time play, dropped third strike) landed with tests that
     state the rule. That is why so much could be added without the game falling over. **[code]**
2. **Pitch types come from technique, and the aim funnel is built on recorded data.**
   - The novel idea (no menus: the way you throw is the pitch) is backed by real recordings from
     two players, and the aim funnel is calibrated on replay. **[code / DESIGN.md]**
   - This is the hook that makes the game worth playing in VR.
3. **The game can be observed.**
   - `GameLog` records events, marks with snapshots, a watchdog that marks itself, and
     `log_summary.py`.
   - Playtests produce evidence instead of recollection.
4. **Draw-call discipline has held.**
   - A person is one draw call.
   - The crowd, fence and dust are MultiMeshes.
   - 75 draw calls on average (82 at most) in the busy demo, against a 220 hard limit and a plan of
     about 120. **[measured]**
5. **All tooling runs without the headset.**
   - Tests, perf, screenshots and probes run with `--xr-mode off`, and debug flags (`--situation`,
     `--hit-test`, `--cam`, `--doll-demo`) let any scenario be reproduced on the desktop.
6. **Audio is data-driven.**
   - One manifest, placeholders generated from it, and real files that replace them one at a time
     with no code changes.

---

## 3. What is not so good (ordered by risk)

### 3.1 There is no version control **[measured]**
`git status` says this is not a repository. That is 15k lines, edited by scripted patches,
several of which half-applied this week (indentation-mismatched anchors) and had to be repaired by
hand. One bad patch or a disk problem and there is nothing to return to. A `.gitignore` is already
written. This is the cheapest, most important fix on this list.

### 3.2 It has never run on a Quest by itself
**[measured: there is no `export_presets.cfg`]**

Everything runs on the PC and streams to the headset. Every performance number is a PC number or a
draw-call count. Things that could hurt on standalone hardware **[estimate]**:
- **The bottom half inning is simulated in a single frame** at the third out (`HalfInningSim`,
  about 60 ms on the PC when last measured). On the Quest's CPU that is probably a few hundred ms:
  a visible freeze at every change of sides, which in VR is a comfort problem, not just a hitch.
- **71 `Label3D` nodes** **[measured]**. The boards and scoreboard are most of the draw calls and
  re-mesh their text when it changes.
- **Doll animation.** About 20 dolls each run keyframe sampling and IK in GDScript every frame.
- **Audio is about 24 MB of PCM WAV** **[measured]**, partly loaded at once (crowd beds, music
  stems).

None of this is known to be a problem. That is the point: nothing has been measured on the device.
The `Mobile` renderer was chosen for the Quest, so either commit to measuring there or decide that
PC VR is the target (see section 6).

### 3.3 `bullpen.gd` holds almost the whole game **[measured]**
3,646 lines, 133 functions and 123 member variables: a third of all the code. It does all of this:
- XR input and the throwing pipeline
- pitch flight
- contact
- ball-in-play playback
- fielder, runner, catcher and umpire animation triggers
- the batter's lifecycle
- steals and pickoffs
- the game flow and the menus
- HUD and boards
- logging
- every sound trigger

Every feature this week went into it, and every feature next month will too unless it is split. The
symptoms are already here:
- **Integration bugs that unit tests cannot see.** Two of them are in section 4.
- **Fragile edits.** Patches anchor on long text and fail, or worse, half-apply.
- **Untyped dictionaries everywhere.** Plays, plans, runners and throws are dictionaries, so a
  misspelled key (`r.get("forced_out")`) silently returns the default instead of failing. **[code]**

### 3.4 Much of what was built recently has not been seen or heard
**[from our sessions]**

The catcher's glove IK, umpire movement, slides, dives, the batter on the rig, fielder catch
variety, dust, and the whole audio layer were checked by tests and a few desktop screenshots only.
The audio has never been listened to. The animation was judged from stills. The next
headset session will produce a long list, and it should come before more features pile on top of
these.

### 3.5 What makes it feel like VR is missing **[code]**
- **No haptics at all.** No grip, release, catch, contact or ball-in-glove pulse.
- **The controllers are drawn as boxes.** No hand holding a ball, no glove on the off hand while
  pitching.
- **The pitch gestures are hidden.** The gesture guide exists only in `DESIGN.md`. A new player has
  no way to learn that a wrist twist throws a slider.
- **No catcher signs.** The original roadmap had them, and they are the natural way to give the
  gestures a purpose (the catcher calls a curve, you try to throw one).

### 3.6 The meta loop is a stub **[code]**
- Stats and leaderboards are greyed out.
- `GameConfig.leaderboard_key()` exists, but nothing persists between sessions except settings.
- No career, no created pitcher, no progression, although `DESIGN.md` describes one (ratings shrink
  release noise, assist is the dial).

Without these a session has no "one more game" pull.

### 3.7 Docs have drifted **[code]**
- `DESIGN.md` is an append-only log: early sections say "not modelled: steals, bunts, bottom
  halves..." and later sections build them.
- `PERFORMANCE.md` still says 30/47 draw calls and calls the batter 7 draw calls. Today it is 75
  average, 82 at most, and the batter is 2.

### 3.8 Smaller design debts
- **Randomness is not reproducible.** About 20 calls to the global `randf()`/`randi()`/`randf_range()` in `bullpen.gd` **[measured]** and the bottom-half
  seed (taken from the clock) make games impossible to replay. The check-swing decision draws from
  the gameplay generator `_run_rng`, so a purely visual choice shifts later steal and wild-pitch
  outcomes. Reproducible seeds matter for regression tests now and for ghost multiplayer later.
  **[code]**
- **Two sources of game results.** `GameState.in_play` without a plan still uses the old dice
  rules (kept for tests), so the two can disagree. **[code]**
- **The art direction is undecided.** Soft and paper players are mixed at random. Paper players
  now face a fixed axis, so from some angles they look thin, and batters are always soft. Mixing
  was meant to be a prototype comparison. **[code]**
- **Colour carries meaning with no colour-blind alternative.** The pitch-location colours are a
  red/green scale. **[code]**

---

## 4. Bugs found during this review (fix in M0)

| # | Bug | Evidence |
|---|---|---|
| B1 | **The main menu is silent, and nothing ducks during pause.** `_process` returns while any menu is open, before `_update_audio` runs, so its menu branch can never run: the main menu at launch has no music. In pause, the game music and crowd carrying on is what `_update_audio` intends, but `AUDIO.md` promises that pausing ducks everything but UI, and nothing does. Loops such as the pitch whiz and a rolling ball also keep sounding while paused. My last summary said "menu music plays in the menus": that was wrong. | [code] `bullpen.gd` `_process`, `_update_audio` |
| B2 | **Delayed sounds run on two clocks.** `_sfx_later` uses scene-tree timers (real time) while `_later_call` uses game time, which stops in a menu. Crowd reactions and umpire calls queued just before a pause fire during the pause; dust and the catcher's throw wait. | [code] |
| B3 | **Left-handed batters are drawn and hit as right-handers.** `Team.generate` makes about 30% of hitters left-handed (`bats_right = rng.randf() < 0.7`), but `bats_right` is never passed to `CartoonBatter`, and `PitchLocation.hits_batter` assumes a right-hander. A lefty therefore stands in the wrong box and is "hit" by pitches on the wrong side. | [code] `team.gd:54` |
| B4 | **A cosmetic choice changes the game.** The check swing draws from the gameplay RNG (see 3.8). | [code] `_batter_takes` |
| B5 | **`PERFORMANCE.md` numbers are stale** (see 3.7). | [measured] |
| B6 | **The bottom half is seeded from the clock**, so a game cannot be reproduced even with a fixed seed. | [code] `_simulate_bottom_half` |

---

## 5. Roadmap

### Why this order
1. **Protect the work, then measure on the real target.** A feature that cannot run at 72-90 Hz
   standalone has to be redesigned anyway, so measure before building more.
2. **Feel what exists before adding more.** The recent layers are unplayed; tuning them is cheap
   now and expensive later.
3. **Split the scene script before the two big features (career, hitting).** Both would
   otherwise land in `bullpen.gd`.
4. **Then make it a game you return to** (feel, then meta), then widen the roles, then production.

### M0. Safety and housekeeping (S)

**Status: done 2026-10-18** (details at the end of this section).
- `git init`, first commit, then commit per feature. For the 24 MB of generated placeholder audio,
  do not ignore `audio/**/*.wav`: real recordings deliberately take the same names and extension,
  so they would be ignored too. Either commit the placeholders (simplest; 24 MB is fine), or have
  the generator write the exact paths it created into a generated `.gitignore` block, so only those
  are ignored.
- Fix B1-B6. For B1, give the menu its own small audio update and route all delays through one
  clock (game time, plus an explicit "real time" option for UI).
- Add a test that every `_sfx("...")` id in the code exists in the manifest. Add an integration
  test that opens the menu and checks the menu theme is playing (this would have caught B1).
- Consolidate the docs: trim `DESIGN.md` "not modelled" lists that are now built, update
  `PERFORMANCE.md`, and point `PLAYTEST.md` at the new behaviours (catcher, umpire, slides, audio,
  volume menu).

**Exit criteria:** the project is in git; B1-B6 are fixed with tests; the docs agree with the code.

**M0 results (2026-10-18)**
- Project under git; baseline commit before the fixes. Placeholder audio is committed (simplest; 11.5 MB packed), so real recordings can never be ignored by accident.
- B1/B2: `_process` now runs `_update_menu_audio` while a menu is open: the main menu plays `music_menu` with no crowd or ambience; pause ducks Music/Crowd/SFX/Voice by 12 dB (the UI bus is exempt) and cuts the whiz and roll loops. Delayed sounds wait on a game-time queue inside `AudioManager`, so they stop while paused.
- B3: `CartoonBatter.home_transform(right)` (a left-hander is the whole figure mirrored); the batter's box, walk-on path and hit-by-pitch zone follow `Player.bats_right`; `--lefty` forces it for screenshots.
- B4/B6: `--seed=N` (logged in the session header) seeds the gameplay generator, a separate cosmetic generator and the off-screen bottom half, which no longer reads the clock. Still unseeded (M3): the `randomize()` calls inside `AIPitcher`, `BatterAI`, `Defense` and `GameState` for the half you pitch.
- B5: `PERFORMANCE.md` and the superseded "not modelled" lists in `DESIGN.md` brought up to date; `PLAYTEST.md` has a new section for the animation and sound work.
- New `tests/hygiene_test.gd`: every sound id the code plays is in the manifest, cosmetic code does not touch the gameplay RNG, a seed replays the bottom half, left-handers, delayed sounds pause, and the menu audio.

### M1. Run standalone on a Quest 3 (M)
- Android export: the export template, an arm64 preset, and the OpenXR vendors plugin for Meta.
  Sideload with `adb` or Meta Quest Developer Hub. Add `tools/deploy.sh`.
- Measure on the device: frame time (OVR Metrics Tool overlay), draw calls, the third-out frame,
  a busy play (a double play with dust and sounds), and the boards.
- Likely fixes, only if the numbers ask for them:
  - **Bottom half:** spread `HalfInningSim` across frames (one plate appearance per frame) or run
    it on a thread. It is pure logic, so either is easy.
  - **Boards:** bake board text into one texture per board, or cut the `Label3D` count.
  - **Audio:** convert loops and music to Ogg.
  - **Dolls:** reduce per-frame work for dolls far away or off-screen.
- Add a `--quest-budget` mode to `perf.sh` with device-calibrated limits.

**Exit criteria:** a 3-inning game runs standalone at the headset's refresh rate during busy plays,
and no frame takes more than 2x budget at the third out. Or a written decision that PC VR is the
target (section 6).

### M2. Playtest and tune what exists (M; repeat as needed)
Work through `docs/PLAYTEST.md` in the headset with logging on and marks for anything wrong. Then
tune from the logs, not memory:
- **Pitching feel:** the aim funnel per assist, the release timing, and gesture recognition.
  Record a tagged session and build a confusion matrix of intended vs recognised pitch. Target:
  each gesture recognised at 80% or better for you, then for a second player.
- **Animation readability from the mound:**
  - Is the catcher's glove convincing?
  - Do slides and dives read at 25-40 m?
  - Is paper or soft better at distance?
- **Audio mix:**
  - Levels per bus.
  - Do the glove pop and the bat crack land on the frame?
  - Is the crowd bed too busy?
  - Are any placeholders so bad they are worse than silence? Drop those until real files exist.
- **Game balance:** BABIP (about .33, slightly high), the triple-play rate, steal success, and how
  often the AI manager walks someone intentionally.

**Exit criteria:**
- Two full 3-inning games with no blocking marks.
- A gesture confusion matrix written into `DESIGN.md`.
- A tuned audio mix.
- A short list of animation fixes done.

### M3. Split `bullpen.gd` (M)

**Status: seams 1-5 done (2026-10-18), the rest open.** Extracted: `SoundDirector` (what is heard and why), `PlateCrew` (catcher and umpire, signals, own test), `FieldProps` (dust, dropped bats, game-time delay queue, own test), `BatterPresenter` (walk-on, box side, takes, bat drop, own test), `PlayDirector` (the whole on-field playback: fielders, ball hand-to-glove, throws, runners, callouts), and the `LiveHit` / `LivePitch` data classes (were inner classes). `bullpen.gd` went from 3,646 to about 2,760 lines. Still in it: XR input and the throwing pipeline, pitch flight and contact, the steal / pickoff flow, human fielding, HUD and boards, the log, the menu hooks. Open for M3: `PitchFlight`, `HumanPitcher`, `GameDirector`, an event bus replacing the remaining scene-to-director calls, typed plans, one RNG per concern (the AI classes still seed themselves). Each move kept the whole suite green.
Move one seam at a time, with `lifecycle_test` and the whole suite green after each move. The order
below goes from lowest risk to highest:
1. **`SoundDirector`**: `_sfx*`, `_crowd_react`, `_update_audio`, footsteps. Have it *listen to
   game events* instead of being called from dozens of places.
2. **`PlateCrew`**: catcher and umpire (`_catcher_*`, `_ump_*`).
3. **`BatterPresenter`**: walk-on and walk-off, bat props, swing, take, check-swing presentation.
4. **`PlayDirector`**: `Hit`, `_update_hit`, `_update_play`, `_build_throws`, `_animate_plan`, the
   callout labels.
5. **`PitchFlight`**: `Pitch`, launch, flight, land, contact detection.
6. **`HumanPitcher`**: XR input, `ThrowDetector`, funnel aim, delivery timing, pickoff throws.
7. **`GameDirector`**: game flow, AI pitcher pacing, steals, the menu hooks. What remains of
   `bullpen.gd` becomes this.

Alongside the split:
- **A small event bus.** `GameDirector` emits typed events (`pitch_arrived`, `contact`,
  `play_event`, `pa_over`, `half_over`, `game_over`) and the presenters (sound, plate crew, boards)
  subscribe. Most of today's scattered `_sfx` calls and animation triggers disappear into
  subscribers.
- **Typed plans.** Replace the play, plan and runner dictionaries with small classes (`PlayPlan`,
  `RunnerPlan`, `ThrowPlan`) one at a time, starting with the runner, which has the most keys.
- **One RNG per concern.** Rules, AI and cosmetics each get their own generator, all seeded from a
  game seed. Add a "same seed, same game" test.

**Exit criteria:** `bullpen.gd` is under 800 lines; each presenter has at least one test; a seeded
game replays the same.

### M4. Core VR feel (M)

**Status: haptics done (2026-10-18); hands, pitch lab, tutorial, signs, comebackers open.** `Haptics` (`scripts/haptics.gd`): a pure event table (`profile(event, strength)`) says which hand feels what and how hard: grab, release (harder with speed), the mitt's pop (mostly the glove hand, softer in the dirt), contact, a glove catch, throws, a rumble on a home run or strikeout, a balk's buzz, and menu hover / select / error in the pointing controller. Options > Haptics: Off / Low / Normal / Strong, saved. `tests/haptics_test.gd`; the full-game test checks the mitt and bat pulses happen. Not yet felt on a real controller: the amplitudes and durations are first guesses.
- **Haptics:**
  - grip
  - release (scaled by speed)
  - glove pop on the off hand while pitching
  - a catch in fielding
  - a pickoff throw
  - a short buzz on a balk
- **Hands:**
  - a hand model holding the ball (the grip shape could show the recognised pitch while you
    wind up, as a teaching aid at the easier assist levels)
  - a glove on the off hand
- **Pitch lab** (Bullpen mode, rebuilt):
  - Throw and see the recognised pitch, spin axis, break, velocity and location at once.
  - A "what made it a slider" explanation, such as "wrist twist 2.1x your normal".
  - Your arsenal over time.
- **A first-run tutorial** built on the pitch lab:
  - calibrate your normal throw (the model already calibrates over about 15 throws; make that an
    explicit, friendly step)
  - then learn one gesture per pitch type
- **Catcher signs:** the catcher shows a pitch and location before each pitch, and you can shake him
  off. Score bonus or command bonus for hitting the sign. This turns recognition from a curiosity
  into a skill.
- **Comebackers:** a ball hit back at you that you can catch with the glove hand. The pitcher
  fielding his position is listed as missing, and in VR this is a big moment.
- **Comfort and accessibility:**
  - seated mode with height calibration
  - left-handed throwing (verify it end to end)
  - a colour-blind palette for zone colours
  - text for umpire calls

**Exit criteria:** a new player can calibrate, learn three pitches and play a game without being
told anything out loud.

### M5. Make it a game you come back to (L)

**Status: persistence, stats screen, local leaderboards and six challenges done (2026-10-18); career and league data open.** `PlayerProfile` (`scripts/player_profile.gd`, `user://profile.json`) keeps every finished game you pitch, lifetime totals (which outlive the capped history), the ten best games per leaderboard key (mode, length and assist, ranked by Bill James Game Score), and challenge records. Main menu > Stats & leaderboards shows lifetime lines and the top five per board. Play > Challenges lists six `Scenario`s (`scripts/scenario.gd`: Escape the jam, Strike out the side, Pick him off, Paint the corners, Protect the lead, No-hitter): each sets up its inning, outs, runners (real players), count and score, is judged after every event, and earns 0-3 stars; the result is saved and you return to the menu. Tests: `profile_test`, `scenario_test` (including a run in the real scene). Test runs write to `user://test_profile.json`, never the player's profile. Open: a created pitcher, seasons and standings, league data, and the Fielding mode's own boards.
1. **Persistence:**
   - a save file with your pitching history
   - per-game box scores
   - season and career stat lines
   - per-pitch-type metrics
   - all fed from `StatsTracker`
2. **Stats screen and local leaderboards:**
   - Fill in the greyed-out row, using the existing `leaderboard_key()` (per mode, length and
     assist).
   - Show best games, K records, fastest pitch, longest outing.
3. **Challenges / scenarios.** A cheap, high-value mode, because `--situation` already does the hard
   part. Examples:
   - "Bases loaded, nobody out, 9th, up by one."
   - "Strike out the side."
   - "Hit all four corners."
   - "Pick off the runner."
   - "No-hit a lineup of Sluggers."

   Each has a short leaderboard of its own.
4. **Career:**
   - Create a pitcher (name, hand, look).
   - Pitch your starts in a season of a fictional league. Other games are simulated with the
     existing engine (`HalfInningSim` generalises into a full-game sim).
   - Standings, your stat line, and ratings that grow from use: command from strike-throwing,
     stamina from pitch counts, new pitches unlocked by recognised use in the pitch lab.
   - Keep the stated rule: physics is never gated by level; ratings shrink noise and widen the
     arsenal.
5. **League data:** fictional teams, names, parks and uniform colours (`Team.generate` is the
   start), and a schedule.

**Exit criteria:** a 10-start season can be played with saved progress, standings and a stats screen.

### M6. More roles (L)
1. **Fielding, finished:**
   - The positions that are left: pitcher and catcher. The catcher could have framing and
     blocking as a mini-game.
   - Tune 1B to RF in the headset (catch radius, throw cone, locomotion).
   - First base taking throws as the human.
   - Real throws, so wild throws let runners advance.
   - Locomotion tuned from M2.
   - Drills ("ten grounders to short").
2. **Hitting:**
   - A bat in your hands with tracked swing physics, reusing `BattedBall`.
   - Pitch recognition against the existing AI pitcher.
   - Timing feedback (early/late in ms, like the pitching readouts).
   - Batting practice and home-run derby modes.
3. **Role switching in a game.** Pitch your half, hit in the bottom (replacing the off-screen sim
   when you choose), or field a position. This needs M3's split to be clean.

### M7. The rest of the rulebook and the manager (M)
- Rundowns: runner and fielders, with throws that chase him.
- Squeeze, hit-and-run, the infield in.
- Base umpires (so out and safe calls at bases have a body).
- You as manager:
  - the bullpen phone and pitching changes you control
  - mound visits
  - intentional walks (the pause-menu version could be a gesture)
- Pickoff moves from the stretch; the pitcher covering first; backing up bases.
- Platoon effects once left-handed batters exist (B3).
- Pitching changes on the PA (`pa_pitching_change` is the one sound still not wired).

### M8. Production (L, mostly assets)
- **Art:** commit to one style (section 6). Then:
  - proper character models, or the procedural rig refined in that style
  - a hero pass on the catcher, batter and your own hands
  - 2-3 parks
  - day and night
  - an animated crowd (shader bob, a stand-up for home runs)
- **Audio:** record and source the P0 list (`docs/AUDIO.md`: mitt, bat, crowd, umpire voice), then
  P1. Real music or licensed packs.
- **UI and presentation:** a board and menu art pass, transitions, between-innings presentation
  (line score, pitch count).
- **Store readiness**, if shipping on Meta:
  - comfort ratings
  - performance checks
  - an entitlement check
  - a privacy policy if anything goes online

### Later
- **Async ghost multiplayer:** race a friend's pitching line on the same lineup with the same seed.
  M3's seeded RNG makes this possible.
- **Weather and altitude** affecting the ball (the physics supports it).
- **A replay camera** for big plays, recorded from the plan data.

---

## 6. Decisions only you can make

None of these block M0-M3. M4 onward goes better once they are settled.

1. **Standalone Quest or PC VR?**
   - Today the game runs on the PC and streams.
   - Standalone is the bigger audience and the harder budget.
   - PC VR frees the budget and drops M1's risk.
   - Recommendation: measure in M1 before deciding.
2. **Arcade or career focus first?**
   - Challenges and leaderboards (fast to build, replayable), or a season with a created pitcher
     (deeper, slower)?
   - Recommendation: challenges first. They reuse `--situation` and give career mode its scoring.
3. **One art style?**
   - Soft and paper are mixed at random as a prototype.
   - Pick one after M2's headset look, or keep both as a setting (it costs little now and doubles
     every animation check later).
4. **When does hitting come?**
   - It is the largest single feature after career and needs M3's split.
   - If hitting is part of what makes this "a full game" for you, it moves ahead of career.

---

## 7. Keeping this file honest
- Tick milestones here as they finish, with the date and any measured exit numbers.
- When a section of `DESIGN.md` is superseded, trim it rather than appending a correction.
