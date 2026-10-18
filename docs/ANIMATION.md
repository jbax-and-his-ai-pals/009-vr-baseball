# Animation plan

Everyone who moves on the field is a `Doll` (scripts/doll.gd): an 11-bone skeleton drawn as one
skinned mesh in one of two skins (soft 3D or paper cut-out), with the same animations on both.
This document is what exists, what is missing, the rules we animate by, and the order to build
the rest.

## Where we are

| Who | Has | Missing |
|---|---|---|
| **Fielders** | ready stance, run cycle, overhand / sidearm / underhand throws timed so the ball leaves the hand at the planned release, plain catch, scoop (grounder), backhand (ball well to the side), jump catch (over his head), dive, tag (sweeping glove on a tag play), a small reaction sink at the crack of the bat, glove up to receive a throw; the ball ends in the receiver's actual glove | calling for it, cutoff-man point, back-pedal, drift on a fly ball |
| **Catcher** | deep squat, glove that follows the pitch, pop and settle, block on a dirt ball (with a dust puff), chase a wild pitch, pop-up throw to second/third on a steal | receiving a throw at the plate and the tag, stepping out to frame, mound visit |
| **Umpire** | stance leaning in, strike call, strike three, safe, foul, point; steps aside for a fair ball and returns | called-ball "no call" shift, check-swing appeal, balk call, mask-off for a play, bases umpires do not exist (the plate umpire rules on plays at home only) |
| **Runners** | run cycle, slide (with dust), head-first dive back on a pickoff, toe bounce on a lead, watching a fly ball with his head up while he waits to see if it is caught, leaning into turns (automatic from the turn rate), arms-up celebration on scoring | head-first slide choice, round-the-base touch, high five, helmet toss, disappointment |
| **Batter** | on the shared rig now (2 draw calls: the doll and the bat): stance with a bat waggle, swing with the arms solved to the real bat position (the body steps toward a far pitch), bunt (squares around), check swing, flinch from a pitch at his body, bat carried low on the walk up, bat dropped when he hits or walks (it falls, bounces and lies there) | take variations, toe-tap, bat flip, run out of the box in a batter's stride |
| **Coaches** | nothing | first and third base coaches (wave home, stop, hold up), dugout reactions |
| **Crowd** | static multimesh | cheer / groan / wave (a cheap vertex-shader bob on the instance), stand for a home run |
| **Effects** | ball seam spin, dust puffs (pooled MultiMesh, one draw call) on slides, dive-backs, dirt blocks, dropped bats and balls that land in the infield dirt | chalk puff on foul lines, grass kick, glove-pop ring, bat-hit flash |

## Rules we animate by

1. **Game logic decides, animation follows.** Timing comes from the plan (release time, arrival
   time, out time), never the other way round. Every throw animation starts early enough that
   the ball leaves the hand at the planned time (`_play_throw_animations`).
2. **Layers.** A base layer (stance / run cycle driven by how fast the node is moved), an action
   layer (a clip that overrides the bones it keys), and an overlay (an IK reach such as the
   catcher's glove, applied last). New behaviour should be a clip or an overlay, not a new
   special case.
3. **One rig, two skins.** A clip is bone rotations; the paper skin shows only the in-plane part
   (it keeps its profile to the camera). Anything that only works on one skin is a bug.
4. **One draw call per person.** Never add meshes to a person; add parts to the skinned mesh.
5. **Cheap to run.** 11 bones per doll, a few dozen dolls: bone updates are microseconds. Do not
   add per-frame allocation in `Doll._process`.
6. **Readable from 20-30 m.** Exaggerate: the pose that reads from the mound beats the realistic one.

## What triggers what (today)

| Game event | Animation |
|---|---|
| Pitch thrown | catcher tracks it (glove to where it will cross, body shifts); dirt ball -> block; wide -> reaches as far as he can |
| Strike called / swinging strike / strike three | umpire `ump_strike` / `ump_out` after the catch |
| Foul ball | umpire `ump_foul` |
| Hit by pitch | umpire `ump_point` |
| Fair ball | umpire steps aside; fielders run; the fielder catches 0.3 s before the ball arrives, or dives when the play says dive |
| Throw planned (t0) | thrower starts 0.42 s earlier (`overhand` over 30 m, `sidearm` 12-30 m, `underhand` under 12 m); receiver puts his glove up as it arrives |
| Out or steal at a base 2-4 | runner slides 0.5 s before he arrives |
| Play at the plate | umpire `ump_out` / `ump_safe` |
| Wild pitch / passed ball | catcher stands and chases the ball to the backstop and walks it back |

## Build order

**P0 (done, except where noted):**
1. DONE. Batter on the rig: stance, swing (the bat is a held prop whose sweet spot is driven to the real
   contact point exactly as today), take, check swing, bunt, bat drop, run out of the box. This
   retires the last multi-mesh character (7 draw calls).
2. DONE (reaction step, scoop, backhand, jump). Fielder variety: scoop and backhand (from where the ball is relative to the body), jump catch
   (ball above reach), glove-up on a high throw; a short "ball is hit" reaction step.
3. DONE (lead bounce, dive back, watching a fly ball; the touch lean is automatic from turning). Runner lead-off: crouch and bounce, dive back on a throw over (plan exists), tag-up stance,
   round-the-base lean.

**P1:**
4. DONE (pop-up throw on steals; a tag at the plate uses the fielder tag clip). Catcher throw: pop up and throw to second from the crouch (the steal plan already knows the
   release time); tag at the plate.
5. Scoring celebration DONE; the rest open. Celebrations: scoring runner, home-run trot gestures, dugout reactions, helmet toss.
6. Coaches at first and third.
7. Dust DONE (`scripts/dust_puffs.gd`); chalk open. Dust and chalk puffs (a handful of particles, pooled).

**P2:**
8. Crowd animation (shader bob, stand and wave on big plays).
9. Mound visit, manager walk, pitching-change walk-on.
10. Per-player quirks: stances, wind-ups of AI pitchers, walk-up gestures.

## How to author a new clip

1. Add it to `_CLIPS` in `doll.gd` as bone keyframes `[time 0..1, Vector3(x, y, z) degrees]`
   (x swings a limb back for a hanging arm and forward for an upright body; arm angles run past
   180: 0 hanging, 90 back, 180 up, 270 forward) or to `_POSES` for a whole-body pose that eases
   in and holds.
2. Look at it: `tools/godot.sh -- --doll-demo --cam=0,1.6,15:0,0.9,9` loops every clip on eight
   dolls (four of each skin).
3. Hook it to the event that causes it in `bullpen.gd`, timed from the plan, not a guess.
4. Add it to `tests/doll_test.gd` or `tests/catcher_test.gd` if it has a measurable property
   (a reach, a duration, a pose).

## If we later want authored art

The rig is a standard humanoid-shaped skeleton; an artist could replace the procedural meshes
with skinned glTF models and keep the clips by retargeting (the bone names are in `Doll.NAMES`).
Nothing in the game logic knows how a person is drawn.
