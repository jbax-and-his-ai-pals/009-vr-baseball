# Gameplay, next round: from good pitching to great, and a game around it

Written 2026-11-02. This is a design proposal with decisions for you; nothing in it is built yet
except the two fixes in "Done with this document". Claims are tagged like `ROADMAP.md`:
**[measured]** (a number from the logs or a test), **[code]** (read from the source),
**[estimate]** (judgement). Every logged number below comes from `python tools/throw_report.py`
over the 1,137 recorded throws and 60 catcher signs in your user folder.

Out of scope for this round: anything for a standalone Quest build.

---

## Part A - Pitching

### A1. What "great" means here

1. **What you meant is what you get.** When it isn't, you can tell that it was you, and why.
2. **Being steady is the skill.** Repeating your delivery is what improves with practice, and the
   game has to pay for it.
3. **Every pitch is a decision:** what to throw, where, and how hard, against a batter who remembers
   what you showed him.
4. **The body tells the truth.** Motion decides speed, movement and location. Picking which pitch
   should not be a guessing game.
5. **Respect the arm.** These are real throws, so effort and session length are designed around a
   human shoulder.

### A2. What the logs say

**1. Pitch type from motion does not survive real play.**
- **Signs not executed.** When the catcher called a slider, changeup or curve, the namer gave that
  pitch **1 time in 21** **[measured]**. Fifteen of those 21 came out as plain four-seamers or
  unnamed. Whether you were trying to follow every sign is unknown (see A9).
- **Accidental pitches.** In 539 untagged game throws only **38%** were named a plain fastball:
  - 15% sinker or two-seam
  - 13% curve, slider or slurve
  - 13% changeup or splitter
  - **8% knuckleball**
  - 11% unnamed (a bug, fixed below) **[measured]**
- **Why.** In **44%** of ordinary throws at least one of the four wrist readings is more than 1.5
  of your own standard deviations from usual **[measured]**. With four readings, normal noise alone
  produces that.
- **Hard to tell apart.** Even on deliberately tagged throws, a seven-way nearest-centroid
  classifier on the wrist readings gets **48%** right (chance is 14%) **[measured]**. Wrist twist
  and gyro roll get mixed up with each other (15 and 11 cross-calls), and "stiff wrist" is right 26%
  of the time. `ROADMAP.md` aims for 80% per gesture.
- **No threshold works.** One threshold per gesture on its own reading cannot fix it **[measured]**:

  | Threshold | Wrist twist caught | Gyro roll caught | Low arm caught | Ordinary throws called something |
  |---|---|---|---|---|
  | 1.5 sd | 55% | 43% | 45% | 29% |
  | 2.0 sd | 40% | 32% | 30% | 17% |
  | 2.5 sd | 28% | 20% | 11% | 9% |

  "Big snap" (the curve) is caught 7-15% at any threshold. A slow throw is the one reliable gesture:
  below 75% of usual speed catches 61% of deliberate slow throws, and 9% of ordinary throws fall
  below it.
- **Realism.** In real baseball the pitch is chosen by the grip, and the arm action is kept the
  *same* for every pitch on purpose, so the batter cannot read it. A system that needs a different
  arm motion per pitch both misreads ordinary throws and teaches the opposite of pitching.

**2. Getting steadier is not rewarded.**
- **The player got steadier.** Your hand-direction scatter went from 5.1/5.7 degrees (Oct 10) to
  **2.7/3.7 degrees (Oct 19)**, and release-point scatter from 0.14 m to 0.08 m **[measured]**.
- **The game didn't notice.** The aim funnel divides each throw by *your own* learned scatter
  **[code]**, so a steadier player gets the same spread at the plate as a sloppy one. The strike
  rate did not go up. It went down, because the Pro spread was raised from 0.40 to 0.60 m
  **[measured]**.
- **Replay.** Measuring the same throws against a *fixed* scatter (the 6.0/5.5 degree prior every
  player starts from) at the Standard spread gives **89% strikes vs 66%** for the steadiest session,
  and 72% vs 58% for the first one **[measured]**.

**3. Too many hit batters.** 15 of 226 game pitches hit the batter (**6.6%**), and 7.2% of logged
game throws missed by more than 0.8 m to the side **[measured]**. In real baseball it is well
under 1% of pitches **[estimate]**. The funnel clamps at 4 sd, which is up to 1.6-2.0 m **[code]**.

**4. Vertical misses come from release timing.** Within a session the vertical aim angle correlates
**+0.33 to +0.72** with release height relative to your head **[measured]**. A late release is
lower and points down; an early one is higher and points up. This is the real cause of high and
low misses, so keep it and explain it (A5).

**5. Effort costs nothing.** Hand-direction scatter is flat across speed (slow, middle and fast
thirds: 4.2/5.5, 4.0/4.5 and 3.9/5.4 degrees) **[measured]**. Nothing stops you throwing every
pitch at maximum effort. That is bad for strategy and bad for a real shoulder.

**6. The career VEL rating does nothing for you.** It is shown on the career screen, but your speed
is hand speed × `velocity_gain` **[code]**.

**7. Radar honesty.** Game speeds run at 0.74 of real baseball (`AIPitcher.GAME_SPEED`; a real
92 mph is 68 here) **[code]**. Your game pitches had a median of 61 mph (10th-90th percentile:
44-76) **[measured]**, so the radar reads like a high-school arm although the world is scaled to
match.

### A3. Proposal: the grip picks the pitch, your body makes it

A pitch has four parts. One is chosen, three are measured:

| Part | Where it comes from | What it decides |
|---|---|---|
| **Grip** | Chosen: the catcher's sign, or your thumbstick | Which pitch (its basic spin and speed) |
| **Arm** | Measured: hand speed against your own range | Velocity (and a command cost if you overthrow) |
| **Wrist** | Measured: the pitch's own action against your fastball | How much it moves; whether it hangs |
| **Look** | Measured: whether the delivery looks like your fastball | How early the batter reads it (deception) |

#### Choosing the grip
- **The catcher's sign sets the grip.** Accepting it is just throwing. **Y** shakes him off and he
  calls the next one (shake-off exists today **[code]**).
- **Calling your own pitch.** While you hold the ball, flick the throwing hand's thumbstick:
  - up: four-seam
  - down: changeup or splitter
  - toward your glove side: breaking ball
  - toward your arm side: sinker or two-seam
  - press: knuckleball

  Only pitches in your repertoire are offered. The catcher moves his target for the new pitch.
- **Seeing the grip.** It shows on the hand model (this closes the open roadmap item "visual grip on
  the hand model"), with a haptic tick on each change.
- **The grip locks** when your delivery starts (`delivery_start` exists **[code]**), so nothing
  changes mid-throw.
- **Rejected for the default: finger chords.** For example, index finger off the trigger for a
  knuckle curve. The action map binds trigger, A/B and thumbstick *touch* **[code]**, but no code
  reads them, and whether Virtual Desktop passes them through is unverified. Fingers also shift
  during a hard throw. Possible later as an option.

#### Velocity: effort against your own arm
- **Effort.** It is this throw's hand speed between your usual speed and your top speed, both
  learned from your own throws (the top is about the 90th percentile of your recent ones).
- **Speed.** Velocity is the pitcher's band at that effort, times the grip's factor.
  - **Bands** (in real-equivalent mph): Balanced 84-92, Power 88-96, Control 82-89. The career VEL
    rating moves the band, so it finally means something.
  - **Grip factors:** changeup 0.86, splitter 0.88, curve 0.82, slider 0.90, cutter 0.96,
    sinker 0.98.
- **Body size doesn't matter.** A kid, a seated player and a big adult all reach the top of their
  own band at their own maximum effort. Throwing harder for *you* is still faster.
- **Overthrowing costs command.** Above your usual speed + 1 sd, the miss spread grows (up to +25%)
  and the arm tires faster (×1.5). The logs show no natural trade-off (finding 5), so it has to be
  designed in. It is also what keeps players from throwing every pitch at full effort.
- **The radar shows real-equivalent speed** (game mph ÷ 0.74), so your usual throw reads about 82
  and a hard one about 90. The physics is unchanged. The Radar station (B2) also shows the raw hand
  speed honestly.

#### Movement: the pitch's own action, against your fastball
- **The grip gives a basic shape:** spin axis and rate, at the Standard floor of 60% of the pitch's
  full movement.
- **That pitch's own action** adds up to 40% more. Each pitch reads only its own reading, so a
  wrong reading cannot turn it into another pitch:

  | Pitch | Action read | Reading (exists today) |
  |---|---|---|
  | Slider | Wrist twist | `z_side` |
  | Cutter | Roll about the throw line | `z_gyro` |
  | Curveball | Over-the-top snap or high windup | `z_snap` + `z_wind` |
  | Sinker / two-seam | Lower arm slot | `z_slot` |
  | Changeup | Fade from pronation | negative `z_side` |
  | Splitter / knuckleball | A still wrist (low spin) | `stiff` |

- **A wrong or lazy action makes the pitch hang:** less break, sitting up belt-high. That is the
  real failure ("a hanging slider"), and the batter AI already punishes a hittable pitch. This
  replaces "you threw a different pitch than you meant". A knuckleball grip thrown with a spinning
  wrist does not knuckle: it is batting practice.
- **No more accidental pitches.** With the grip known, an ordinary throw with the four-seam grip is
  a four-seamer. Today 44% of ordinary throws drift into another pitch's reading (A2, item 1).
- **The assist dial**, as a movement floor:

  | Level | Movement floor | Action can |
  |---|---|---|
  | Casual | 100% | Only add |
  | Standard | 60% | Add, or make it hang |
  | Pro | 35% | Add, or make it hang, with more at stake |

- **Later: personal action templates** (A8, step 4). The tutorial records five of each pitch the
  way that feels right to *you*. The action is then measured along your own direction instead of a
  fixed axis. Recorded players differ too much for one axis: snap per hand speed was 2.7 ± 0.45 for
  one and 0.8 ± 2.2 for the other **[measured, DESIGN.md]**.

#### Command: steadiness is the skill
- **The target is the catcher's glove,** the sign's spot (or the zone centre with signs off). Today
  the funnel always aims at the zone centre, so hitting a corner means throwing differently from
  usual on purpose **[code]**. Pitchers throw to the glove with the same delivery, and the new
  model does too.
- **The miss.** It is this throw's direction minus your usual direction, divided by a
  **reference scatter**, times the spread. The learned usual direction stays, so a personal habit of
  throwing a little left is still removed.

  | Assist | Reference scatter | Effect |
  |---|---|---|
  | Casual | Your own | As today: everyone throws strikes |
  | Standard | Between your own and the fixed 6.0/5.5 degrees (geometric mean) | Steadiness counts partly |
  | Pro | The fixed 6.0/5.5 degrees | Your steadiness is your command |

- **The career command rating scales the reference** (×1.15 at 30 down to ×0.85 at 80), as
  `command_scale` already does **[code]**.
- **The edges only pay if you're steady** (normal approximation; Standard spread, aiming at the
  low-away corner) **[estimate]**:
  - The Oct 19 player (plate scatter 0.19/0.22 m) throws about **59%** strikes and paints the
    corner.
  - The Oct 10 player (0.35/0.33 m) throws about **41%**.
  - Aiming down the middle, the sloppy player is back to about 57% strikes (the steady one 90%),
    but they are hittable.

  That is the real trade between command and safety.
- **Squeezed tails.** Beyond 2 sd the miss is compressed (2 + 0.4 × the excess) instead of clamped
  at 4 sd. The target is hit batters at or below 1% of pitches (6.6% today).
- **Overthrowing widens the spread** (velocity section).
- **The pitch lab explains a vertical miss** from release height: "you let go early: high". Keep
  the measurement; it is the real cause (finding 4).

#### Deception: the batter reads your delivery (A8, step 6)
- **Today.** The batter keeps one expected flight time (`lerp(expected, actual, 0.35)` per pitch)
  and misreads a speed change by `(1 - recognition)^2` **[code]**. That is good, but it only covers
  speed.
- **Tells.** Compare each pitch's gross delivery to your fastball's: hand speed, windup height, arm
  slot, and the time from delivery start to release. A difference beyond your own scatter **tips**
  the pitch: that batter's recognition goes up for it.
- **The changeup is sold with fastball arm speed.** Slowing the arm tips it. This is the real rule,
  and it reverses today's mapping (slow arm = changeup).
- **The lab says what tips you:** "your curve's windup is 12 cm higher than your fastball's".
  Casual ignores tells.

#### Batter memory: sequencing matters (A8, step 6)
- **Per-batter memory** of what he has seen this game: pitch types and where they crossed.
- **Times through the order.** His recognition rises the third time he faces you.
- **Sitting on a pitch.** After the same pitch twice in a row, he times it better.
- **Tunnelling.** Two pitches that look the same until about 0.15 s before the plate and then split
  are harder to read. Measured from the two flights.
- **A scouting line on the sign marker:** "chases the slider low and away", "sits on the fastball".

### A4. What stays
The flight integrator, the aim solver, the wrist readings, the logs, the pitch lab and the lessons
all stay. Today's classifier becomes a **Freestyle** option ("technique picks the pitch"), for
comparison in the headset and for anyone who loves it.

### A5. Why not the two smaller fixes
- **(b) Keep only the separable gestures** (twist = slider, slow = changeup, everything else a
  fastball), with a dead zone. At 2.0 sd the false calls fall to 17%, but twist is caught only 40%
  of the time (A2). Still a coin flip, and it still teaches a different arm action per pitch.
- **(c) Keep pure motion and retune it.** 48% on deliberate, tagged throws from the player the model
  was tuned on is the ceiling we can see. Retuning moves the trade-off; it does not remove it.

### A6. Respect the arm (affects Part B)
- A 3-inning start is about 45-55 throws (3.4 pitches per batter **[measured, DESIGN.md]**).
- A 9-inning complete game is 130-150 real throws, too many for most people in one sitting
  **[estimate]**.
- Modes are therefore built around **30-60 throw sessions**: short starts, relief outings and
  contests. The overthrow cost (A3) keeps max effort occasional.

### A7. Testing without the headset
- **`tools/throw_report.py`** (new) reproduces every logged number in this document.
- **Next: a replay scorer.** It runs a candidate model (grip, movement, command) over the logged
  throws and reports strike rate, hit batters, miss distribution and accidental pitches. Python or
  the existing `tests/replay_labeled.gd`.
- **The throw log now keeps the full controller rotation per sample** (this commit). The pointing
  direction alone loses the wrist's roll, so the gyro reading could not be recomputed from old logs.
- **Every new model sits behind a setting**, so one headset session can compare old and new.

### A8. Build order (pitching)
1. **Quick wins** (1 session):
   - real-equivalent radar
   - command against a reference scatter, with the glove as target
   - squeezed tails
   - overthrow cost
   - the career VEL band
2. **Grip, then motion** (2-3 sessions):
   - grip from the sign or the thumbstick
   - movement from the pitch's own action, with hanging
   - the grip on the hand model
   - Freestyle kept as an option
   - the replay scorer
3. **Headset check:**
   - Freestyle vs Grip, 40 pitches each
   - a sign-following session
   - a tagged "good vs hanging" session for each pitch
4. **Personal templates** in the tutorial.
5. **Contest stations** (B2) use 1-2.
6. **Deception and batter memory** (3+ sessions).

### A9. What this data cannot tell us
- The tagged gesture data is essentially **one player** (player A). Player B's 233 throws were
  almost all one tag.
- The logged wrist readings came from whichever model version was live that day.
- **Did you try to follow the signs?** If you ignored the off-speed calls, finding 1's
  "1 in 21" overstates the problem. The 44% of ordinary throws read as something else stands on its
  own.

---

## Part B - Modes, teams, league

### B1. Where it is **[code]**
- **Career:** a season of starts (6/10/14) in an 8-team league with a double round robin, quick-sim
  for the other games, standings, rating growth, learned pitches and home parks. No playoffs.
- **Daily game.**
- **Six challenges.**
- **Hitting:** derby.
- **Fielding:** drills and positions.
- **Lessons and the pitch lab.**

### B2. Pitching Contest (build first)
Short, replayable, scored, and it doubles as a scored test of the new command and movement model.
Four stations of 10-15 throws each, about 45 throws in all:

1. **Strikeout 9.** The 3×3 panel board of the Japanese carnival game ("Struck Out"): nine
   numbered panels fill the zone, and you get 12 balls to knock them all out. The panels fall when
   hit (one MultiMesh). This is the purest command test.
2. **Radar.** Five throws. The best speed *that is a strike* counts. Shows effort vs command, with
   honest raw hand speed beside the real-equivalent number.
3. **Nasty.** Throw your best breaking ball and changeup. Scored by movement against your fastball
   (inches) and whether it lands in or near the zone. Tests the wrist action.
4. **Pressure.** 3-2 count, bases loaded, an All-Star at the plate: get him out.

**Scoring and boards:**
- Station points add up to a contest score, with local boards per assist level.
- A **Daily Contest** on the daily seed: the same batter and panels for everyone.
- Bronze, Silver and Gold tiers give a ladder.

**Reuse:** challenge scoring (stars), the daily seed, boards, the pitch lab's movement numbers.

### B3. More teams, with an identity each
- **16 fictional teams in two leagues of eight.** Each has a city, nickname, colours and a home
  park.
- **Parks.** Four exist and are parameterised (walls, distances, air, wind, colours, day or night)
  **[code]**. Eight are reachable by parameters alone.
- **A team identity changes its lineup:**

  | Identity | What it means |
  |---|---|
  | Power | Sluggers, high strikeouts |
  | Contact and speed | Few strikeouts, steals, bunts |
  | Patient | Walks, deep counts |
  | Free swingers | Chase off the plate |

  An identity makes each opponent a different pitching problem, which is the point of A3's
  sequencing.
- **Two hand-written stars per team:** a name, position, side, and a signature trait the scouting
  line can show. For example: "the Rams' Sledge Okafor: 40-homer power, can't lay off the slider low
  and away".
- **Code impact** **[code]**:
  - `League` already uses `TEAM_COUNT`, and its circle-method pairings work for any even number.
  - `TEAMS`, `PARKS` and the career rank line read from it.
  - To change: the 14-matchday cap, the "team 0 is always home" convention, and the season lengths
    in the menu (6/10/14 become 8/15/30).

### B4. Season 2.0
- **Playoffs.** The top four in each league play best-of-3 semis, then a best-of-3 final. You start
  game 1 of each series.
- **Relief outings.** Between starts, an optional save situation: one inning, about 15 throws. This
  gives short sessions inside a season.
- **Awards:** a Pitcher of the Year race (ERA, strikeouts and innings against the league) on the
  career screen.
- **Training focus between starts.** For example, a bullpen goal of "steady your release" grows
  command, and "sharpen the slider" grows that pitch's movement. This ties growth to what you
  practise.
- **Later:** multiple seasons (age, rating drift, league history).

### B5. Tournament
- **An 8-team bracket ("the Classic"):** two pools of four (a round robin, three games each), then
  semis and a final, about five games over an evening.
- **Pitch-count rules** force choices: 65 pitches a game at most, and two games' rest after 50 or
  more. You might start the opener, relieve in the semi and start the final. The AI uses the rest of
  your staff.
- **One `Bracket` class** serves both the season's playoffs and the tournament.
- **A daily or weekly tournament** on a shared seed comes later.

### B6. Build order (modes)
1. **Pitching Contest** (2 sessions, after the quick wins in A8 step 1).
2. **League expansion:** 16 teams, identities, stars, parks by parameter (2-3 sessions).
3. **`Bracket`:** season playoffs, then the tournament (2 sessions).
4. **Relief outings, awards, training focus** (2 sessions).

---

## Decisions for you

**Decided 2026-11-02: all four as recommended.** Grip then motion (Freestyle kept as an option);
steadiness is command, aimed at the catcher's glove; the Pitching Contest first; 16 teams in two
leagues.


1. **How the pitch type is chosen.**
   - **Recommended:** grip, then motion (A3), with Freestyle kept as an option.
   - Alternatives: fewer gestures with a dead zone, or retune pure motion (A5).
2. **What decides accuracy.**
   - **Recommended:** a fixed reference scatter at Standard and Pro (steadiness is command), aimed
     at the catcher's glove.
   - Alternative: keep each player's own scatter (everyone equally accurate; today's model).
3. **Which mode first.**
   - **Recommended:** the Pitching Contest.
   - Alternatives: season playoffs, or the tournament.
4. **League size.**
   - **Recommended:** 16 teams in two leagues.
   - Alternatives: 12 teams, or keep 8 and add identities.

Smaller calls this document makes unless you object: real-equivalent mph on the radar, the
overthrow cost, the velocity band from the VEL rating, squeezed tails.

## Done with this document
- **Fixed:** low pitches went unnamed. `PitchPhysics.analyze` compared each pitch with the same throw
  without spin lift, and for a knee-high fastball that comparison flight hit the ground before the
  plate, so the break could not be measured. That was 11% of game pitches **[measured]**, and 10 of
  the 39 fastball signs were graded misses because of it. The comparison flight now ignores the
  ground (`tests/pitch_namer_test.gd`).
- **Logging:** the throw log keeps the full controller rotation per sample, so the wrist's roll can
  be recomputed from future logs (`tests/human_pitcher_test.gd`).
- **New tool:** `tools/throw_report.py`.
