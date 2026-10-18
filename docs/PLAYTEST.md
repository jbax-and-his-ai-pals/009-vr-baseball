# Playtest checklist

Everything here was built and tested without a headset, so none of the VR interaction has been
felt yet. Work top to bottom; each section is one sitting (10-20 minutes). For each item,
"Look for" is what to notice. Tick it or write one line of what you saw.

## How to report things (read this first)

The game writes two logs as you play, to `%APPDATA%\Godot\app_userdata\VR Baseball\`:

| File | What it has |
|---|---|
| `events_<time>.jsonl` | Every pitch (where it crossed, how the batter reacted), every ball in play and what the fielders and runners did, steals, pickoffs, balks, the batter's walk-ons, game flow, frame-time windows every 5 s, frames over 60 ms with what was going on, menu use. |
| `throws_<time>.jsonl` | Your motion for each pitch (hand path, release, spin), as before. |

**Mark a moment:** press **B on your throwing hand** (F on a desktop) the instant you see
something wrong. It writes the last 25 events and a full snapshot of the game state, and shows
"Marked this moment in the log". Then keep playing. After the session send me the two newest files
plus one line per mark ("mark 3: the batter never came out after the fly out"). If the game
notices something impossible (for example it waited two seconds for a batter who should have been
there) it marks itself with "watchdog".

If something looks wrong and you did not mark it, note roughly how many minutes in it was; the
log has timestamps for every event.

Useful: also look at the Godot output panel on the PC for red errors, and copy anything red.

---

## 0. It starts (5 min)
- [ ] Launch in VR: no black screen, menu appears at eye level in front of you (may take 1-3 s).
- [ ] Both controllers show a laser; the row under it lights; trigger selects; no double-fires.
- [ ] Play -> Pitching -> Game -> Start loads the mound.
- [ ] Options: hand, assist, quality cycle and survive a relaunch.
- [ ] Pause (left menu button): Resume / Restart / Options / Main menu all work, game freezes while open.
- [ ] Frame feel on the stream: smooth, or hitching? Note when.

## 1. Pitching basics (20+ pitches)
- [ ] Grab with grip, throw, open hand: release timing feels natural.
- [ ] You can throw strikes on purpose; pitch types still come from how you throw.
- [ ] The three stat boards: PITCHING and LAST PITCH either side of you, BATTING behind the plate; all legible; numbers update after each pitch.
- [ ] The strike-zone dots after each pitch: color matches where it crossed (green strike, amber middle, orange just off, red ball); gold halo on a corner you did not get hit on.
- [ ] Count, outs, runs on the center-field scoreboard and the boards agree.
- [ ] Casual / Standard / Pro assist: different enough? Which feels right as the default?
- [ ] Left-handed option.

## 2. The at-bat loop and the batter's comings and goings
- [ ] After a strikeout the batter walks off to the red dugout and a new one walks on; you cannot pick up the ball until he is in the box.
- [ ] After a walk or hit-by-pitch the batter jogs to first, forced runners move up.
- [ ] After a ball in play the batter becomes a runner; an out walks back to the dugout.
- [ ] After a foul ball (including a caught foul) the same batter is still there, or the next one comes out - never an empty box.
- [ ] Between batters the pitch dots clear.
- [ ] Waits between pitches: anything over ~10 s that is not a long play?

## 3. Rules to try to make happen
Try to cause each of these on purpose (a Practice game helps; Pause -> Main menu -> Pitching -> Practice).
- [ ] Hit by pitch: throw at the batter's body on his side.
- [ ] Wild pitch / passed ball: bounce pitches in the dirt with a runner on.
- [ ] Intentional walk: Pause -> "Intentional walk" with a runner on second.
- [ ] Infield fly: runners on first and second, fewer than two outs, a pop-up ("Infield fly rule, batter is out").
- [ ] Bunt: a weak hitter with a runner on first and no outs squares around sometimes; sacrifice bunt text.
- [ ] Foul bunt with two strikes is a strikeout.
- [ ] Ground-rule double: rare; note it if you see it.
- [ ] Extra innings: a tie after nine goes on (use a 1-inning game to test: Pitching -> Game -> 1 inning).
- [ ] The HOME row of the scoreboard fills in each inning; the final line says who won, walk-off noted.

## 4. The running game (your delivery time is the lever)
- [ ] With a runner on first, a "Delivery x.xx s" line shows after each pitch.
- [ ] Runners break for second sometimes; a quick delivery (under ~0.7 s) catches some, a slow one (over ~1.2 s) lets almost all of them go.
- [ ] A STEAL ATTEMPT line says safe or OUT and the scoreboard agrees a moment later.
- [ ] The runner stands further off the bag the longer you ignore him.
- [ ] Throw to first (toward the bag, not the plate): the ball goes to the first baseman's glove; with a big lead you sometimes pick him off.
- [ ] Throw toward a base with nobody on it: BALK, runners move up.
- [ ] Start your motion and drop the ball with a runner on: balk.
- [ ] Is it clear when you are throwing to a base versus the plate? Too easy to do by accident?

## 5. Ball in play: runners and throws (watch, do not throw)
Spectate (Play -> Spectate) is good for a long look.
- [ ] Runners move during the play, not afterwards.
- [ ] Fly ball with fewer than two outs: runners lead off a bit, wait, then go if it drops, or come back and touch the base if it is caught; deep catches: they stay and tag.
- [ ] Two outs: runners go on contact.
- [ ] Ground ball with a man on first: the throw goes to second, then first; "Double play 6-4-3" in the text; sometimes just the force.
- [ ] Bases loaded: sometimes the throw goes home.
- [ ] A fielder's choice: lead runner out at second while the batter reaches first.
- [ ] A close play at the plate: the throw goes home and sometimes gets him.
- [ ] A runner scoring easily is not thrown at; the ball goes to a cutoff man.
- [ ] Long throws go through a cutoff man (shortstop or second baseman).
- [ ] The center fielder takes fly balls hit near him, not the left fielder running across.
- [ ] Fielders look right: soft 3D or paper doll, mixed; throws and catches animate.
- [ ] Anything that looks silly: sliding, floating, walking through each other.

## 6. Human fielding (Play -> Fielding)
- [ ] You stand at your position facing home; left thumbstick runs; glove visible on the off hand.
- [ ] Catch a grounder, catch a fly; throw to first, second, third; wild throw is "Throwing error".
- [ ] Start a double play on a force at second.
- [ ] Hold the ball 5 s: infield single.
- [ ] Any motion sickness? (vignette and snap turn are saved but not wired yet.)

## 7. The long game
- [ ] Play a full 3-inning game: the pitcher board shows pitch types and totals; "Your arm is getting tired" appears around 60+ pitches; velocity and accuracy fall off.
- [ ] In Spectate: the AI starter gets replaced ("New pitcher: ...") after about 100 pitches or 5 runs allowed.
- [ ] Final line, restart after ~8 s.
- [ ] Does it get more sluggish over a long game? Note the minute; the perf lines in the log show frame time over time.

## 8. Comfort and performance
- [ ] 15+ minutes continuous: discomfort, and where it starts.
- [ ] Frame drops: during a ball in play with everyone moving, at inning change (the bottom half is simulated; a short hitch is possible), at the start of a game.
- [ ] Text readable on the boards at your distance; the center-field board readable from the mound.

---

## Numbers I will tune from your answers
Funnel spread (Casual 0.28/0.20, Standard 0.40/0.30, Pro 0.60/0.48), glove radius (0.45/0.34/0.28 m),
throw cone (34/26/18 deg), fielder speed, hold limit (5 s), delivery detection threshold
(hand speed 1.6 m/s), steal chance and run times, lead growth, pickoff chance (max 35%), fatigue
onset (60 pitches), bunt rate, wild-pitch rate, hit rate (a bit high: about a third of balls in
play), menu distance.

## Known gaps (do not report these)
Stats/leaderboards are stubs; Hitting is not built; Bullpen currently equals Practice; quality,
vignette, snap turn and movement options are stored but not wired; no squeeze or hit-and-run;
no rundowns; the batter, catcher and umpire use the older static figures; the knuckleball
"shot put" gesture is unbuilt; the pitcher and catcher cannot be played; the pitcher figure does
not field bunts while you pitch.

---

## 10. People, animation and sound (new; none of it has been seen or heard in the headset)

Animation (look from the mound, then from behind the plate):
- [ ] Catcher: the mitt follows each pitch to where it crosses; a wide or low pitch is reached for; a dirt ball is blocked (dust); he pops up and throws on a steal.
- [ ] Umpire: a call gesture after each strike, out, safe and foul; he steps aside on a ball in play and is back behind the plate before the next batter.
- [ ] Batter: bat hangs low on the walk up and comes up in the box; waggle; swing hands stay on the bat; bunts square around; the odd check swing; flinch from a pitch at him; bat dropped (flipped on a homer). **Left-handed hitters** stand on the first-base side.
- [ ] Fielders: scoop on grounders, backhand to the side, jump catch on a high ball, a small sink at the crack of the bat, a glove sweep on tags; throws end in the receiver's glove, and in a double play the shortstop (not the second baseman) throws on to first.
- [ ] Runners: bounce on a lead, watch a fly ball, slide with dust, dive back on a pickoff, celebrate on scoring.
- [ ] Paper players no longer turn toward your head when you look around.

Sound (headphones in the headset; these are crude placeholders, judge timing and level, not quality):
- [ ] Main menu has its own music; pausing quiets the game and the ball-in-flight sounds stop.
- [ ] Glove pop is at the catcher's mitt and on the beat of the catch; harder pitch, harder pop.
- [ ] Bat crack on contact, louder for a harder hit; home run: crack, crowd roar, horn, fireworks.
- [ ] Crowd grows with runners on and a close late game; the umpire's calls are audible but not loud.
- [ ] Anything that is annoying or repeats too much: note the sound name (`docs/AUDIO_LIST.md`).
- [ ] Options > Sound sliders work and persist.
