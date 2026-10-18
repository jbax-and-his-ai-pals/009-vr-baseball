# VR Baseball - design decisions

## Decisions so far
- **Platform:** Meta Quest standalone (Godot, OpenXR, Mobile renderer). Develop on PC over Virtual Desktop / Link.
- **Art:** minimal, cartoony, low-poly. Physics and mechanics outrank visual realism.
- **Data:** fictional league, teams and players.
- **Modes stay separate** (Pure / Assisted / Career) with separate leaderboards, so no mode skews the board.
- **Focus first:** pitching. Fielding and hitting come later (role switching a la Totally Baseball).

## Pitching model
- Ball flight is a custom fixed-step integrator (gravity + drag + Magnus), not Godot physics. See `scripts/pitch_physics.gd`.
- Release velocity and spin come from sampled controller pose (`scripts/throw_detector.gd`); spin comes from wrist rotation.
- Release: grip-open with latency compensation, or auto-release at hand-speed peak.
- `velocity_gain` / `spin_gain` / `LIFT_SCALE` are tuning knobs; expect to retune on a real headset.

## Aim: what the recorded throws taught us
Per-pitch logs live in `%APPDATA%\Godotpp_userdata\VR Baseball	hrows_*.jsonl` (hand path, grip, outcome).
- Hand velocity *at release* rotates ~1 deg/ms, and grip-open timing is only known to ~7 ms, so it scatters ~2 m at the plate. Unusable for aiming.
- Gaze (head direction) was steadier but players do not always look where they throw. Rejected. Off-hand "glove pointing" also rejected.
- **Current: FUNNEL.** Location = zone center + scaled-down deviation of the hand's travel direction (190..40 ms before release) from the player's learned usual aim (EMA). Defaults x 0.25, y 0.15. Spin/speed still come from the arm.
- Validated: replay predicted 62% strikes, live 18 throws gave 61% (plate spread x 0.34 m, y 0.23 m).
- Ideas not yet done: soft-limit wild throws; correct the hand-travel point for release position/posture (it correlates 0.6-0.7 with release x/height); per-tier funnel gains; rating-driven noise.

## Pitch types come from technique (no menus, no signs)
`scripts/wrist_model.gd` compares each throw to the player's own usual throw, using controller rotation per m/s of hand speed (raw rotation is 0.91 correlated with speed, so raw spin would make every hard throw a curve):
- extra wrist snap -> backspin fades, then topspin: curveball. Lazy wrist -> more carry.
- doorknob twist -> sidespin and lost carry: slider (opposite twist: screwball/arm-side).
- arm slot lower than usual -> spin axis tilts arm-side and backspin drops: two-seam / sinker.
- rolling the wrist about the throw line -> glove-side tilt: cutter.
- almost no wrist rotation -> spin fades out, deterministic flutter fades in: knuckleball.
- much slower throw: changeup.
Handedness mirrors. `scripts/pitch_namer.gd` only *labels* the result. Baselines adapt from ordinary throws only (not deliberate off-style ones). `technique_gain` scales all deviations. Left controller X cycles a practice tag saved in each log line, to collect labeled throws for tuning. Baseline numbers and gains are from one player's un-coached throws: expect to retune with deliberate pitches.

## What a second, untrained thrower taught us (233 throws, a young first-time player)
- Technique differs a lot between people: snap-per-speed was 2.7 +/- 0.45 for player A but 0.8 +/- 2.2 for B; hand-direction scatter was 14-18 deg for B vs 5-6 deg for A. Fixed baselines tuned on one player do not transfer.
- 24% of B's "throws" were drops (< 4 m/s hand speed). They are now ignored (MIN_THROW_SPEED), not launched at a forced 27 mph and counted.
- Extrapolating the hand's travel line 17 m blew up whenever the hand was not heading at the plate (47% of throws), and those outliers dragged the learned "usual aim" from (1.4, 2.2) m to (-5.7, 11.7) m. Aim is now measured as angles, clipped, and normalized by the player's own learned scatter.
- Result (replay): ~52-66% strikes for both players at the same landing spread, regardless of how erratic the thrower is. Skill shows up as deliberate shifts bigger than your own noise.
- Wrist baselines and spreads calibrate to the player over the first ~15 throws, then adapt slowly and skip deliberate outliers.

## First deliberate-technique session (82 tagged throws)
- Rotation per m/s of hand speed (~2.7 rad/s per m/s = 1 / 0.37 m) is just the forearm swinging about the elbow. A "bigger snap" mostly produces a faster hand (speed 10.5 -> 18.8 m/s), not a different ratio. Only an extra flick on top of that raises the ratio (3 of 10 "big snap" throws did).
- Clearly separable gestures: slow throw (changeup), wrist twist (large rotation about the vertical axis, snap ratio drops), gyro roll (rotation about the throw line, plus a cross-body sweep). Weak: low arm (the hand is lower, but mostly because harder throws finish lower; hand height beyond what speed explains was ~6 cm), stiff wrist (rotation per speed 2.4 vs 3.0, noisy).
- Fixes from this data: baseline anchored after 10 throws (mixed styles had dragged "normal" from snap 2.7 / 10 m/s / slot -0.21 to 2.0 / 14 m/s / -0.42 over 80 throws); arm slot judged against what this speed produces; knuckleball = rotation per speed >= ~1.5 normal-scatters below normal and not a slow throw; pitch names judged at a reference flight time (break scales with time^2, so slow pitches over-break).

## Gesture guide (what the model listens for; every pitch is relative to YOUR usual throw)
- **Fastball**: your usual, compact throw.
- **Curveball**: a hard wrist flick at release *on top of* a moderate-speed throw (best results ~14-18 m/s hand speed). Going all-out (>20 m/s) pushes the arm to do the work and the flick ratio falls back to normal.
- **Slider**: sweep the controller's nose sideways at release (rotation about the vertical axis); the forward snap drops.
- **Cutter**: roll the controller about the line it points along (spiral / screwdriver), with a bit of cross-body sweep.
- **Sinker / two-seam**: a lower arm slot than your speed would give, and a roll the opposite way (sidearm). The hand starting high in the windup and dropping later reads as normal-slot.
- **Changeup**: a normal-arc throw that is clearly slower.
- **Knuckleball**: push it. Dead-straight hand path (>=0.95 chord/arc), slower than usual, little rotation. Spin fades out, deterministic flutter fades in.
Findings: a slow push gave path straightness ~0.96 vs ~0.89 for a normal throw and ~0.7 for a big arm swing. The detector's history logged for analysis was extended to 0.55 s to capture the windup.

## Second tagged session (127 throws, one contiguous block per tag)
- wrist twist: 18/19 sliders - the most reliable gesture. low arm: genuinely lower (slot -0.62 vs -0.27 m, dropped 0.62 m from windup peak) and, like twist, sweeps the controller sideways (that sweep is inherent to sidearm, so it is now discounted as the arm gets lower -> sinker / two-seam instead of slider).
- big snap: the wrist-flick-per-speed ratio did not move (2.83 vs 2.86). What did: a much bigger, higher windup (hand peaked 0.32 m above head vs 0.19), hard throw (16.7 vs 11.2 m/s), bigger pointer rotation. The curve gesture is therefore "higher/bigger windup" OR extra flick, whichever is larger.
- gyro roll vs twist: roll shows ~2x the gyro ratio, less sideways sweep, a smaller overall motion, and the lowest windup of any tag (0.13). A rolled controller also yaws, so some sideways rotation is credited to the roll.
- slow vs shove: a slow throw is a scaled-down normal throw (rotation per speed unchanged, path as straight as normal: 0.92 vs 0.92). Push-detection by absolute straightness did not hold across sessions (0.96 then 0.92 for slow), so push is now straighter *than the player's own normal* and slower. A true shove (thrust from the chest, little forearm rotation) has not been recorded yet; tag "shove".
- 7 of 127 throws had frame gaps >30 ms (streaming hitches) and were excluded from stats.

## Knuckleball: shot-put finish (proposed, not built yet)
- Player rejected "push from chest = pitch". Proposal: low windup (hand stays below head height; only ~10% of recorded throws were below +0.10 m above head) AND a rising finish (hand moving up in the last ~110 ms).
- Evidence the finish is unique: of 193 recorded throws only 10 had a rising hand at release, best +1.4 m/s / +8 deg; typical was -1.3 to -3.0 m/s / -8 to -17 deg. A shot put should be about +3..+6 m/s / +20..+40 deg.
- Windup height is a continuous but noisy axis: medians 0.14 (gyro roll) .. 0.29 (big snap) m above head with ~0.08 m IQR. High (>0.30) is reliable (curve); low needs about 0.15 m below the player's normal.
- Aim: a rising finish makes the hand-direction aim read "very high", so the knuckleball must ignore the vertical aim component.
- Tag "shot put" replaces "shove" for the next recording session.

## Progression idea
Physics never gated by level. Assist level is the dial; career ratings (command, stuff, stamina) shrink release noise and unlock grips/pitch mastery.

## Park and batter (built)
- `scripts/stadium.gd`: grass + mowing stripes, infield dirt/grass/base paths, bases, chalk (foul lines, batter's boxes), warning track, fence with cap, 4-tier stands (full behind the plate and down the lines, bleachers in the outfield), 1100 low-poly fans, dugouts, backstop netting, light towers, scoreboard. Rings and crowd are MultiMeshes (one draw call each). `fence_radius(psi)` defines the park outline: ~122 m to center, 100 m down the lines, ~22 m behind home.
- `scripts/batter.gd`: static cartoon batter in the right-hand box (mirror with `right_handed = false`). Not interactive yet.
- Preview views without a headset: `godot --path . -- --overview | --behind-plate | --batter` (pair with `--write-movie out.png --quit-after 6` to dump frames).
- Not yet measured on a Quest: draw calls are low (~100) but fill rate from the transparent netting and the crowd has not been profiled.

## Batter intelligence and batted balls (built)
- `batter_profile.gd`: six profiles, weakest to strongest - Little Leaguer, Rookie, Contact Hitter, Slugger, All-Star, MVP - each with eye, contact, power, timing, recognition, aggression (0..1) and a typical attack angle.
- `batter_ai.gd`: PERCEIVE (location noise grows with break and flutter) -> DECIDE (swing odds from how far outside the zone it *looks*) -> TIME (he swings for the speed he expects; the part of a speed change he fails to read, scaled by (1-recognition)^2, becomes an early/late swing) -> AIM (bat plane / sweet spot error shrinks with contact, grows off the heart of the zone) -> COLLIDE (bat and ball meet partway; both have slopes, so a swing plane that matches the pitch's descent forgives timing; good hitters match it).
- Outcomes: take, whiff, foul tip, or a hit with exit velocity (power, sweet spot, vertical offset, timing), launch angle (attack angle and where the bat meets the ball), spray (timing), backspin/sidespin.
- `batted_ball.gd`: drag (Cd .33) + Magnus, bounces, rolling, fence/wall/home run, foul lines. Sanity: 100 mph @ 28 deg ~ 125 m; 107 mph @ 32 deg ~ 138 m.
- Everything is resolved at release (pitch flight is deterministic), logged under "batter" in each throw's JSON, and played back at contact: swing animation, cyan tracer, orange landing ring, distance label, and a HUD report (outcome, exit velo, launch, spray, distance/ft, apex, hang time; "Rolls X m" for grounders).
- Controls: left Y (or P on desktop) cycles the batter. Debug: `-- --profile=MVP`, `--hit`, `--swing-test`.
- Calibration notes: weak batters make little contact once breaking balls and real speed changes are mixed in (rookie ~46% on fastballs only, ~7% on changeups mixed in); the top profiles make contact on ~85-95% of swings. No fielders yet, so every ball in play just flies/rolls.

## Performance (Quest 3) and headset-free tooling
- Budgets, rules and measurements live in `docs/PERFORMANCE.md`. Idle 17 draw calls, busy 34, ~100k triangles (limit 220 / 350k).
- Characters, ball and static props are baked with `MeshMerger` (vertex colors, one shared material): one or two draw calls each. New content must follow that.
- `PerfGovernor` degrades only crowd / netting / render scale under sustained slowness.
- All tooling is headset-free (`--xr-mode off`): `tools/test.sh`, `tools/perf.sh`, `tools/shot.sh`, `tools/godot.sh`. Tests write to a scratch log, never the player's.
- Gotcha: `rendering/vrs/mode=2` as a project setting blanks the desktop view; VRS is turned on at runtime only under XR. Vertex colors need `vertex_color_is_srgb = true` or everything looks washed out.

## Batter swing, people, zone (latest)
- The swing is now driven to the ball: `CartoonBatter.swing_to(point, contact_in)` solves hands and bat so the sweet spot is on `point` at contact, using joint-based arms (two capsules per arm through an elbow). For a hit the point is the ball; for a whiff it is where he aimed, so the bat visibly passes above/below. `snap_to_contact()` puts the bat exactly there at the instant the game resolves contact. Measured: the sweet spot is ~7 cm from the ball centre at contact (ball + barrel radius is 7.2 cm), at normal and rapid-fire pitch spacing.
- A batter still finishing a swing cannot start another (SWING_RECOVERY): pitches that arrive too soon are takes.
- Default batter is now Contact Hitter so balls actually go in play; Y cycles.
- Strike zone is larger: 0.60 m wide, 0.40-1.30 m tall (was 0.43 x 0.60). Funnel spread widened to 0.40 / 0.30 m per sigma and clamped at 4 sigma, so a poor throw is clearly poor (about 8% of real throws are now >0.5 m outside; worst ~1.2 m) while the average throw is still a fair strike (~54%).
- `Figure` (limbs by joints, lathe-turned bat) and `People` (catcher in a crouch, plate umpire) build cartoon people into one mesh each.
- Park: ad boards on the wall, tier railings, a roof over the best seats, on-deck circles and coach boxes, fans with heads, clouds, floodlight banks. Idle 30 draw calls, busy 47, ~160k triangles.
- Debug: `--contact-demo` (perfect swing at one pitch, prints bat-to-ball distance), `--demo-interval=S`.

## Fielders: balls in play become outs and hits (built)
- `defense.gd` (`Defense`, pure logic): 8 fielders (C, 1B, 2B, SS, 3B, LF, CF, RF) plus an abstract pitcher (the player). Each has top speed, reaction, reach, dive range, arm and transfer time; a team `skill` (0..1) scales speed, reaction and glove.
- For each ball in play the defense walks the ball's recorded path and finds, per fielder, the first sample he can be standing at (reaction + acceleration loss of 0.45 s + speed, reach 1.35 m, a dive adds reach and a little speed), then lets him settle on the most comfortable sample within 0.33 s. Earliest interception wins.
- In the air and reached: out (flyout / lineout / popout; foul out in foul territory) unless he fails the catch, which is more likely the harder he had to work, the harder it was hit, and when diving. Fielded on the ground: throw to first against the runner (RUNNER_TIMES 4.15 / 7.55 / 10.95 / 14.45 s), noise on close plays; if safe the runner takes more bases while he beats the throw (deep balls add a relay). Routine plays are occasionally errors (about 1-2%).
- Calibration (tests/defense_test.gd): BABIP .26-.34 across profiles, errors 1-2%, a pop-up is caught 98%, a routine grounder to SS is an out ~97%, a hard grounder in the 5-6 hole falls ~94%, a gap liner falls about 63%.
- Visuals: fielders are one mesh each (`People.fielder`); the play timeline drives them (run, dive, cover first, face the throw), the ball (flight -> glove -> throw arc -> base), and the batter becomes a runner with SAFE / OUT / HOME RUN labels. The HUD announces the result when the play ends, with running Outs / Hits / HR / Errors.
- Debug: `-- --hit-test=EV:LAUNCH:SPRAY` injects a batted ball (e.g. `78:-4:15` is a routine grounder to short, `103:17:-24` a gap liner); cameras `--infield`, `--outfield`.
- Fixed along the way: a fielder could "intercept" every ball at t=0 because it starts inside the catcher's reach; grounders lost 18% of their speed per bounce (now 10%).
- *(Superseded: runners, force and double plays, tag-ups, balks, steals, the count and innings are all built; see the later sections. Still open: the pitcher fielding his position, fielders drifting before the pitch, errors on throws.)*

## Players, ratings, teams and modes (foundation for what comes next)
- **`Player`** (`player.gd`): name, number, position, handedness and ratings 0-100 (50 = average everyday player, 80 elite, 20 poor). Hitting: contact, power, eye, timing, recognition, plus aggression (approach) and loft. Running/fielding: speed, fielding_range, hands, arm. Pitching: velocity, command, movement, stamina, repertoire. `Player.factor(rating, spread)` turns a rating into a multiplier where 50 is the calibrated baseline.
- **`Team`** (`team.gd`): colors, batting order, position -> player. `Team.generate(name, quality, seed)` builds a roster with positional tendencies (SS range, CF speed, C arm...); `archetype_roster()` is the six-batter practice squad.
- Everything reads ratings instead of private constants: `BatterProfile.from_player()` for batters, `Defense.from_team()` for every fielder's speed, reaction, reach, dive, arm and glove, `Player.run_factor()` for runner speed.
- **`AIPitcher`** (`ai_pitcher.gd`): velocity sets speed, command sets how far the ball lands from the aim point (0.5 m -> 0.1 m), movement scales spin, repertoire picks the pitches. It produces the same release/velocity/spin a human throw does, so batter, physics and defense cannot tell the difference.
- **`GameMode`** (`game_mode.gd`): roles are human or AI, so a mode is a different assignment. Playable: **Pitching** (you pitch) and **Spectate** (all AI; the viewer moves behind the plate). Reserved and flagged `supported = false`: **Fielding** (a human takes a position) and **Hitting**. Switch with the `game_mode_name` export on the Bullpen node or `-- --mode=spectate`.
- Evidence ratings separate results (tests/players_test.gd): elite vs poor defense on the same gap liner 93% vs 39% outs; a soft dribbler is an out 47% vs a slow runner and 0% vs a fast one; AI pitcher command 90 vs 20 lands 0.16 m vs 0.49 m from the aim point and throws 70% vs 36% strikes; velocity 85 vs 20 is ~19 mph faster; stuff cuts contact per swing from 90% to 81% and hits per swing by about a quarter. Batters now find fast pitches harder to read (plate speed above ~58 mph adds difficulty).
- **Next for human fielding**: the fielding interception test already exists per fielder; a human fielder replaces that fielder's AI with controller-driven movement and a glove, and Defense skips him. Next for a lineup: a plate-appearance loop with the count, advancing the batting order and the half-inning.

## The count and the at-bat loop (built)
- **`GameState`** (`game_state.gd`, pure rules): balls, strikes, outs, inning, runners on 1B/2B/3B, the batting order, and the pitcher's line (pitches, IP, K, BB, H, R, HR). It is a pitcher's-eye game: one lineup bats against the home defense and an "inning" is that lineup's three outs; the line is the pitcher's.
- Rules in: four balls is a walk that forces runners; three strikes is a strikeout (looking or swinging); a foul is a strike but never strike three; a foul tip is a foul (a strike with fewer than two, never strike three); a bases-loaded walk forces in a run; hits advance runners (a runner on second scores from a single 45% of the time); a ground ball with a runner on first and fewer than two outs is a double play 45% of the time; a deep fly with a runner on third and fewer than two outs scores him 75%; no run counts on the play that makes the third out; three outs end the inning and clear the bases; the game ends after the set number of innings and a new one starts 8 s later.
- In the game: each pitch's outcome goes to the scorebook when it lands (ball, called strike, swinging strike) or when the play ends (in play, foul, foul tip); the batter's profile comes from the lineup player, the scoreboard in center field shows inning, outs, count, runs/hits/K/BB and who is up, runner figures stand on the occupied bases, and the HUD shows the situation and your pitching line. `lineup_mode`: **Game** (the lineup comes up in order) or **Practice** (the batter you pick stays; Y cycles them; the count still counts).
- Balance after simulating twelve nine-inning games with an average AI pitcher vs an average lineup: ~3.4 pitches per batter, K 30%, BB 11%, ~8 hits, ~3.8 runs, ~1.2 HR per game. To get there, bat speed was raised (29.5 to 38.5 m/s across the power rating) and contact penalties softened; an MVP now averages ~98 mph exit velocity, a Slugger hits 14% of its balls in play over the fence.
- Tests: `tests/game_state_test.gd` covers every rule above and runs a full simulated game through the real batter, defense and AI pitcher.
- Debug: `-- --situation=outs:1,bases:101,count:2-1,inning:4`, `--mode=spectate`, `--demo-interval=S`.
- *(Superseded: bottom halves, HBP, wild pitches, steals, bunts, fatigue, relievers, extras are built. Still open: pinch hitters and substitutions you control, per-batter career stat lines.)*

## Roadmap
Moved to `ROADMAP.md` (a review of the whole game and milestones M0-M8, written 2026-10-18).

## Live baserunning and human fielding (built)

**Runners on a ball in play** are planned, not dice-rolled. `Baserunning.plan(play, bases, outs, batter, rng)`
turns the defense's play (who fielded it, when, with what arm) into a timeline for every runner:
- Hits: runners go base-to-base; a runner already on base *tries for the extra base* when the throw
  to the next base would arrive late (`est = ball_time - run_time`, noisy), and is thrown out when
  it isn't. Runner speed comes from the `Player` run factor; a lead off the bag saves `LEAD_GAIN`.
- Fly balls: tag-up only when deep enough to matter (third > 42 m, second > 78 m, first > 100 m),
  and only when the throw does not beat him. Third out ends it; no run on the third out.
- Grounders: with a runner on first and fewer than two outs the defense tries for two. The throw to
  second has to beat the runner, then the pivot (`PIVOT` 0.62 s + the throw) has to beat the batter.
  About 40% of grounders with a man on first become double plays (the old coin-flip was 45%).
- `GameState.in_play(play, plan)` records what the plan says happened (hits, runs, outs, text such
  as "Double play 6-4-3"); without a plan it still uses the old dice rules (kept for tests).
- The scene animates `plan.runners` (the batter figure plus the three base figures) and shows
  OUT / SAFE / RUN callouts from `plan.events` using a pool of four labels.

**Human fielding** (`--mode=fielding`, `--field-pos=3..9`, export `fielding_position`):
- You stand at your position facing the plate; left thumbstick runs (at your fielder's speed),
  the off-hand controller is the glove. If the ball comes within `HumanFielding.CATCH_RADIUS`
  (0.34 m) of the glove it is yours: a ball in the air is an out; a grounder you then grab with the
  throwing hand and throw (release velocity x `velocity_gain`, capped by the fielder's arm).
- Whichever base the throw is closest to heading for (within 26 deg) is the base; the ball's flight
  time plus the receiver's catch pause is compared with that runner's arrival from the plan.
  A force at second can turn two (the AI pivot). A throw nowhere near a base is a throwing error.
- Only balls the AI would have given to *your* position become your chance (`Defense.resolve`
  computes it once with you and once without you: the second is what happens if you miss).
  Hold the ball 5 s and it is an infield single.
- Debug without a headset: `--mode=fielding --auto-field` puts the glove on the ball when your
  fielder would have reached it and throws to first 0.7 s after; add `--hit-test=EV:LA:SPRAY`
  and `--situation=` to force a ball at a position with runners on.

*(Mostly superseded. Still open: wild throws letting runners advance, infield-in and no-doubles defenses, playing the pitcher or catcher yourself, and tuning the human position in the headset: catch radius, throw cone and locomotion speed.)*

## Settings and GameConfig (menu foundation, built)

`Settings` (`scripts/settings.gd`, saved to `user://settings.cfg`) holds what the *player* chose:
throwing hand, assist preset, quality, locomotion/comfort, developer flag, last game. Assist is
three presets (Casual / Standard / Pro) that bake in the aim funnel, `aim_assist`, glove radius
and throw cone; Standard equals the previous hard-coded feel. Bad or missing files fall back to
defaults. `GameConfig` (`scripts/game_config.gd`) is one game: mode, activity (Game / Practice /
Bullpen), fielding position, innings (1/3/9), practice batter, assist. `normalized()` repairs
anything meaningless, and `leaderboard_key()` makes boards per mode, position, length and assist
(practice and spectating have none). `bullpen.gd` applies both in `_ready` (`apply_settings`,
`apply_config`); command-line flags still override, and `--no-settings` ignores the saved file.
Bullpen currently maps onto Practice; a true no-lineup bullpen comes with the menu.

## The menu (built)

Flow: **Main** (Continue, Play, Options, Stats [coming soon], Quit) -> **Play** (Pitching, Fielding,
Spectate, Hitting [coming soon]) -> **Setup** (position for fielding, Game / Practice / Bullpen,
innings 1/3/9, practice batter, assist, Start; the Start row says which leaderboard the game is
scored on, or "not scored") and **Options** (hand, assist, quality, movement, vignette, snap turn,
developer). In a game the left menu button (Esc on desktop) opens **Pause**: Resume, Restart,
Options, Main menu.
- `MenuModel` is pure data (screens, rows, what choosing does) and is unit-tested; `GameMenu`
  draws it as a panel 1.8 m in front of you with a laser from each controller (trigger selects)
  or mouse / arrows / Enter / Backspace / Esc on a desktop. About two draw calls per row, and
  nothing exists while no menu is open.
- Starting, restarting and leaving to the main menu *reload the scene* with the request carried
  in `Session` (static), so the XR rig, camera and mode are always built fresh. The game does not
  update while a menu is open.
- The menu opens at launch only when there are no debug flags (or with `--menu`); every test and
  tool path therefore behaves as before. Tests that instantiate the scene set `menu_on_start=false`.
- Assist changes apply immediately; hand and quality apply on the next game start.

## Boards, scoreboard, ball and the batter's comings and goings (built)

- **Stat boards** (`StatBoard`, `StatsTracker`): three boards hang still in the park instead of
  following your head: PITCHING (IP, pitches, K, BB, H tiles; per pitch type: count, average and
  max mph, strike %, whiff %), BATTING (AVG, H, HR, K, average exit velocity tiles; a line per
  batter in the lineup, totals, hardest hit and longest) and LAST PITCH (the report and notices).
  A board is one merged mesh plus one label per table column. `StatsTracker` is pure bookkeeping
  fed from pitch outcomes and plate-appearance results.
- **Center-field scoreboard** (`Scoreboard`): a ballpark board with the line score by inning
  (AWAY batting, HOME as dashes since bottom halves are not modeled), R H E, ball / strike / out
  lights, who is at bat with today's line, who is pitching, and the last pitch's speed and type.
  Runs per inning come from `GameState.inning_runs`.
- **Ball** (`BallVisual`): a larger ball (0.052 m visual radius; physics unchanged) with the real
  two-lobed seam and tick stitches drawn into one texture, rotated so the seam stays off the
  texture poles. It spins visibly in flight (slowed so it reads).
- **Batter lifecycle**: a strikeout walks the batter off to the dugout while the next batter walks
  on; a walk sends the batter jogging to first with forced runners advancing (live); a ball in
  play turns the batter into a runner after the follow-through; every runner who is out walks back
  to the dugout (three pooled figures). Pitching waits (`_batter_ready`) until the next batter is
  in the box, for you (the ball cannot be picked up) and for the AI pitcher. A watchdog readies
  him after 2 s if a path ever fails to. Plays are announced when the fielder has the ball and
  the runners are done, not when the ball stops rolling; the home-run trot is 0.8x a normal run.
- Cost: draw calls went from about 49 to about 77 (labels): the boards and scoreboard are most
  of it. `--cam=x,y,z:lx,ly,lz` places the desktop camera for screenshots.

## Runner caution on balls in the air, and a batter-visibility bug (fixed)

- **Bug:** `_animate_plan` hid the batter figure whenever `t >= hide_at and _batter.visible`, every
  frame. An older play still walking its runners off therefore hid the *next* batter as soon as he
  walked on (you pitched to nothing), and a strikeout re-triggered the walk-on every frame. The
  hide (and the walk-on it starts) now happens once per plan (`plan.batter_hidden`).
- **Hedging:** on a ball hanging in the air at least `AIR_TIME` (1.7 s), runners on base go a
  third of the way (`HEDGE`) and wait. If it drops they continue from there (so they lose the
  waiting time); if it is caught and not deep enough to tag on, they run back and touch their
  base; if it is deep (third > 42 m, second > 78 m, first > 100 m) they stay on the bag, tag at
  the catch and go if the throw is late. Plans carry `keys` (time, position) for the animator.
- **Outfielders** stand deeper: corners (+-40, 80), center 98 m (were +-38/74/92) so ordinary
  fly balls are caught instead of landing behind them; gap tests were re-aimed accordingly.
- Home runs are in: about 2.7% of balls in play (roughly one per nine innings per lineup).

## Throws between players, launch angles, who fields it (built)

- **Throws** go to the glove of the fielder covering the base (`Baserunning.RECEIVE_SPOT`; first
  baseman, the middle infielder who is not the thrower, third baseman, catcher), leave the hand
  at shoulder height and arc higher the farther they go. Throws over 62 m go through a cutoff man
  standing in line (SS or 2B, up to 30 m from the base) who holds the ball a moment and throws on;
  receivers and cutoff men are given movements into place. The ball is carried up from where it
  was caught (a grounder is in the dirt) to the throwing hand rather than appearing at chest height.
- **Launch angle** was almost uniform from -45 to +70 degrees (too many topped balls and towering
  pop-ups). The vertical offset now moves it 46 degrees per bat-radius instead of 65 and the swing
  plane is matched to the pitch's descent less aggressively. Measured over 1,700 balls in play:
  median 12 degrees, 10th/90th percentile -20/+42, about 48% ground balls, 22% line drives,
  28% fly balls, 2% pop-ups (`tools/la_probe.gd`). Weak contact (low exit speed at 25-45 degrees)
  is what makes bloopers.
- **Who fields a ball**: fielders who can all reach it within 0.25 s are ordered by how hard they
  must run, then by distance, instead of by list order (the left fielder used to win ties).

## Edge / center of the zone (built)

Where a pitch crosses inside the strike zone now matters. `BatterAI` computes `edge` (0 at dead
center, 1 at the edge of the zone, using the zone's own half width and height) and uses it twice:
the batter's aim error grows from 0.9x at the center to 1 + penalty at the edge (penalty 0.40 for
a poor contact hitter down to 0.20 for a great one), and exit speed is scaled from 1.08x at the
center to 0.99x at the edge. Measured with the same fastball (`tools/control_probe.gd`): a
contact hitter makes contact on 91% of swings at the heart and 80% on the corner, with a 46% vs
7% hard-hit share; an all-star 90% vs 78% contact and 67% vs about 30% hard hit. Overall league
numbers stay similar (exit speed median 83 mph, about 3% home runs per ball in play).

## Pitch location feedback (built)

`PitchLocation` names and colors where a pitch crossed the plate with the same "edge" the batter
uses: MIDDLE (amber, easy to hit), IN ZONE (light green), GOOD LOCATION (green), CORNER (bright
green with a gold halo), JUST OFF (orange), BALL (red), WAY OFF (dark red); its strike call always
agrees with the umpire's. `ZoneMarkers` draws the last 10 pitches as dots on the zone in the park
(one multimesh; newest largest) and the LAST PITCH board draws the same pitches as a larger
strike-zone chart with the zone's hard-to-hit rim and easy-to-hit middle tinted. A halo marks the
result: gold = a corner you were not hit on, cyan = in play, white = swing and miss, grey = foul.
The report line says e.g. "STRIKE CORNER".

## Figures: soft and paper dolls on one rig (prototype, built)

`Doll` is a person on an 11-bone skeleton (pelvis, torso, head, two 2-bone arms, two 2-bone legs)
drawn as one skinned mesh, so a person is one draw call in either style:
- **SOFT**: capsule body, real 3D, full twists and sideways swings.
- **PAPER**: flat cut-out cards with an outline. It always shows its flat side to the camera,
  mirroring to face left or right, keeps only the in-plane motion, bounces higher and waddles.
- Same clips for both (`_CLIPS`: overhand, sidearm, underhand, catch, celebrate as keyframes per
  bone) plus a run/stance layer driven by how fast the node is being moved, so the game only
  places the figure. Fielders, runners, leavers and base runners are dolls; each person's style
  is picked at random once (`--doll-style=soft|paper` forces one; `--doll-demo` shows a row of
  both style side by side looping through the clips, use `--cam=...` to look at it).
- Throws are started so the ball leaves the hand at the planned release (an overhand throw above
  30 m, sidearm above 12 m, underhand flips under that); the receiving fielder and cutoff man are
  told to catch as it arrives; a fielder catches as the ball reaches him.
- *(Superseded: the batter, catcher and umpire are dolls now; slide, dive and reaction clips exist. See "Animation pass 2".)*

## Runner and throw decisions, audited (built)

**Runners on balls in the air** (`Baserunning._hit` / `_caught`): with fewer than two outs they
lead off a third of the way and watch it; if it lands they go from there (they lose the time spent
waiting), if it is caught they go back and touch the base, and on a deep catch they stay on the
bag and tag at the catch. **With two outs they go on contact**, no hedge (a catch ends the inning
anyway, and no run counts on the third out).

**Where a fielder throws a ground ball** (`ground_options` / `choose_ground_throw`): each option is
scored by the expected number of outs, using the real arrival times of the ball and of each
forced runner with a soft margin (`P_SIGMA`):
- `first`: the sure out (what the defense already decided at first),
- `force` at second, third or home on a forced runner,
- `dp2` (second, then first) and `dphome` (home, then first), only with fewer than two outs.
He turns two when it is worth at least 1.15 outs, otherwise he goes for the lead runner when he
has a real chance (0.78+ if a sure out at first exists, 0.30+ if the batter would be safe
anyway), otherwise he takes the out at first. A throw that cannot get there is not made. A fielder
standing at the bag steps on it. A clean ground ball the batter beats is a **fielder's choice** when
a force is worth taking (no hit, an at-bat; `result: fielders_choice`).

*(The throw on a hit is built, next section. Still open: rundowns, infield-in, a runner breaking on a throw to another base.)*

## The throw on a hit (built)

On a hit the defense has one throw (`Baserunning._hit`). Every runner's contest with the ball is
scored (can the ball beat him to the base he is going for, or to home if he is scoring), and the
throw goes to the lead runner he has at least a 25% chance of getting; failing that, to whichever
play has at least a 10% chance; if nobody is gettable it goes to the base that holds the batter
(the planned relay) and no one is thrown at. Only that one runner can be out, whether the throw is
a close play (it is then out or safe by the margin and shown either way) or an easy score (no throw
home at all). The batter takes second on a throw home when he can. This replaces independent
chances for each runner to be thrown out on the same play.

## More of the rulebook (built)

- **Hit by pitch**: a pitch you do not offer at that crosses where his body is (`PitchLocation.hits_batter`:
  about 0.6-1.3 m to the third-base side, knees to shoulders) hits him: he takes first, forced
  runners move up, a bases-loaded one scores, it is a plate appearance and not an at-bat or a walk.
- **Wild pitches and passed balls**: with runners on, a pitch far enough outside the zone (or in
  the dirt) gets past the catcher with a probability that grows with the distance (4% rising to
  about 54%), and a strike-ish pitch gets by about 0.8% of the time (a passed ball). Every
  runner moves up a base and the runner on third scores; it is shown (runners run, a WILD PITCH /
  PASSED BALL callout) and counted (`GameState.wild_pitches`).
- **Infield fly rule**: runners on first and second (or loaded), fewer than two outs, and a high
  fair fly an infielder can catch (landing inside 46 m, 1.8 s hang): the batter is out whether it
  is caught or dropped, and nobody is forced. ("Infield fly rule, batter is out".)
- A bug fixed on the way: a foul ball's late announcement could mark the batter ready while the
  next ball in play had already taken him out of the box (you pitched to nothing).

*(Superseded by "The rest of the rulebook" below, which builds stolen bases, pickoffs, bunts, balks, ground-rule doubles, intentional walks, extra innings, bottom halves and fatigue.)*

## The rest of the rulebook (built)

- **Two-sided games.** At the third out `GameState` plays the bottom half through `bottom_sim`
  (`HalfInningSim`: the same AI pitcher, batter, ball physics, defense and baserunning as the
  half you pitch, out of sight, ~60 ms). The scoreboard's HOME row, R/H totals and the final line
  are real; a home team that leads after the top of the last inning does not bat; a lead taken in
  the last bottom half is a walk-off; ties go to extra innings (up to `max_extra`, then are
  called). Without `bottom_sim` and `allow_extra` the old one-sided game is unchanged.
- **Intentional walk.** The pause menu has "Intentional walk" in a game you pitch; the AI manager
  does it with first base open, a runner in scoring position, a power hitter up, and two outs or
  the late innings. No pitches, a walk.
- **Fatigue and relievers.** `Player.fatigue(pitches)` (onset ~60 pitches, spent 45 later, later
  with more stamina). The AI pitcher loses up to 7% of his speed and widens his misses by 55%;
  your arm loses 6% of its speed and your aim funnel widens 30%, and tells you once. The AI
  manager brings in a reliever (`Team.relief_pitcher`) when the starter is spent or has given up
  5 runs, between batters.
- **Ground-rule double.** A ball that lands fair and then bounces over the fence (`BattedBall`
  `ground_rule`) is dead: exactly two bases for everyone, no throws. A caught ball, or one
  fielded before it leaves, is a normal play.
- **Bunts.** `BatterAI` squares around in a bunting situation (a runner on first or second, fewer
  than two outs and strikes; likelier for a weak hitter) and bunts strikes: 10-22 mph, down a line,
  a pop-up if he gets under it, a foul if he gets a piece. A foul bunt is a strike even with two
  (strike three). Runners go on the bunt; the pitcher is not asked to field it while you pitch.
  A bunt that gives himself up to move a runner is a sacrifice (a plate appearance, no at-bat).
- **The running game.** `StealModel` (pure) and the pause-free flow in `bullpen.gd`:
  - **Your delivery time** is measured from the moment your hand gets moving to the release.
    The runner breaks when it starts (a chance per pitch from his speed and aggression, more
    with two outs), his time to the next base comes from his lead, and it is judged against your
    delivery + the pitch's flight + the catcher's pop time (1.85 s). A 0.65 s delivery gets
    a typical runner almost every time; 1.45 s almost never. Delivery time is shown on the
    board when runners are on.
  - **Leads** grow while you ignore a runner (each pitch since you last threw over, up to 4.2 m)
    and shrink after a throw over; the figure stands that far off the bag.
  - **Throw over:** throw toward a base (within 26 degrees of it) instead of the plate. A bigger
    lead and a more accurate, harder throw help catch him (at most 35%); a throw to a base nobody
    is on, or dropping the ball after starting your motion, with a runner on, is a **balk** and
    every runner moves up.
  - A ball put in play on a steal keeps the runner's head start.

Still not built: squeeze plays, hit-and-run, pitching changes you control, hitting for yourself, rundowns, base umpires. See `ROADMAP.md`.

## The session log (built)

`GameLog` writes `user://events_<time>.jsonl` next to the throw log (one JSON object per line, `t`
seconds since the session started, `kind`, then fields, plus `s` = a short state picture:
inning, outs, count, who is on, score). Kinds: `session` (header: mode, settings, args, lineups,
engine, renderer), `pitch` (type, speed, where it crossed and its location class, whether the
batter swung and how, outcome, wild pitch, delivery time with runners on, fatigue), `contact`
(exit speed, launch, spray, hit kind, distance, who fielded it and when, whether it was caught
in the air, what each runner did, the throws), `play_result`, `half_over`, `game_over`,
`steal_break` / `steal_resolve`, `pickoff`, `balk`, `delivery_start`, `walk_on`, `pa_exit`,
`pitcher_change`, `intentional_walk`, `menu`, `perf` (a 5 s window: fps, average and worst
frame, draw calls, nodes, memory, quality level), `spike` (a frame over 60 ms with a snapshot
of what was happening) and `mark`.

A **mark** is the B button on the throwing hand (F on a desktop): it rewrites the last 25 entries
with a full state snapshot (batter visibility, readiness, open plays, steal/aux/walk-on flags,
leads, the quality level...). The game also marks itself ("watchdog") when the batter has been
not-ready for two seconds with nothing to explain it. `tools/log_summary.py` summarizes the
newest log: counts, locations, delivery times, steals, performance by third of the session, slow
frames, and every mark with the entries before it. Off with `--no-log`; tests that set
`ThrowLogger.override_path` write to a scratch file.

## Catcher, umpire and edge cases

- The catcher and plate umpire are `Doll`s with roles (`catcher`: deep squat, gear, big mitt; `umpire`: black uniform, leans in). The mitt follows the pitch through a two-bone glove IK (`Doll.aim_glove`); unreachable pitches are reached for, dirt balls trigger a block, wild pitches send him chasing. The umpire rings up strikes/outs/safe/foul and steps aside on a fair ball.
- New whole-body poses: `slide`, `dive`, `block`. See `docs/ANIMATION.md` for the plan.
- Rules added: triple play (runners on first and second, none out), line-drive double-off, time play (a run counts if it crosses before a tag for the third out), dropped third strike (first open or two outs), strikeout on a steal.
- Audio plan: `docs/AUDIO.md` and `docs/AUDIO_LIST.md` (457 files; generated by `tools/build_audio_manifest.py`). Not implemented in code yet.

## Animation pass 2

- The batter is a `Doll` (role "batter") plus a bat prop. The bat goes exactly where the swing says (sweet spot on the contact point); both arms are solved to the grip every frame (`Doll.aim_glove` for the lead hand, `Doll.aim_hand` for the top hand), and the body steps toward a pitch that is out of arm's reach (`Doll.body_shift`). Bunt, check swing, flinch, a bat carried low on the walk up and dropped on a hit or walk. Batters are always the soft skin (the bat is real 3D).
- Fielders pick a catch animation from where the ball is (`Bullpen._catch_clip`), react to the crack of the bat, and tag instead of catching when the out is a tag. Receivers' balls end in their actual glove (`Doll.glove_world`).
- Runners: toe bounce on a lead (`idle_bounce`), watch a fly ball (`watching`), lean into turns from the node's turn rate, dive back on a pickoff, celebrate on scoring.
- Double plays: each throw is made by the man who took the last one (pivot man at second); receivers are picked from an ordered list of candidates who are free to cover the base.
- Dust: `DustPuffs`, a pooled MultiMesh, for slides, blocks, dive-backs, dropped bats and dirt landings.

## Audio

`AudioManager` (see `docs/AUDIO.md`) plays everything by id from `audio/manifest.json`; placeholder
files come from `tools/make_placeholder_audio.py` and are replaced by dropping real files of the same
name. The bullpen calls it through `_sfx` / `_sfx_later`; the crowd bed and music are driven by
`_update_audio` twice a second from the game state. Volumes live in `Settings.volumes` and the
Options > Sound screen.

## Scene script split (in progress)

`bullpen.gd` is being broken up (see `ROADMAP.md`, M3). Extracted so far: `SoundDirector` (decides what is heard; owns the `AudioManager`), `PlateCrew` (catcher and umpire; reports what happened through signals), `FieldProps` (dust, dropped bats, a game-time delay queue). The scene still owns the rest and passes them what happened.
