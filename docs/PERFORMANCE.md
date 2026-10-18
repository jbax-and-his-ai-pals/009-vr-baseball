# Performance on Quest 3

The target is a standalone Quest 3 at 90 Hz (11.1 ms a frame), Godot mobile renderer, 2x MSAA.
In VR a missed frame is worse than a plainer picture, so we budget early and measure often.

## What costs what

On a Quest the first resource to run out is **draw calls** (CPU-side submission), then
**fill rate** (transparent overdraw, resolution), then triangles. Script work and memory
allocation matter too, but this game does very little per frame.

| Budget | Now (idle / busy) | Limit | Notes |
|---|---|---|---|
| Draw calls | 30 / 47 (+8 when the fielders are in view) | 220 (hard), ~120 (plan to stay under) | `tools/perf.sh --budget` fails above 220 |
| Triangles | 156k / 165k | 350k (hard) | cheap compared with draw calls |
| Large transparent surfaces | 2 (strike zone, netting) | keep <= 3 | overdraw is costly on mobile GPUs |
| Per-frame script cost | small | keep allocation out of `_process` | trails rebuild only when they change |

"Busy" = 8 pitches in the air, batter swinging, two batted balls with tracers.

## Rules for adding content

1. **A character is one or two draw calls.** Build bodies from primitives and bake them with
   `MeshMerger` (vertex colors, one shared material). Only parts that animate independently get
   their own mesh: the batter is legs, torso+head, four arm segments and the bat = 7 (he is the
   hero figure; background people such as the catcher and umpire are 1 each). Do **not** add a `MeshInstance3D`
   per limb. Nine fielders built per-limb would be 100+ calls on their own.
2. **Static scenery is merged.** `Stadium` collects opaque props into one mesh; add new props
   through its `_add()`. Anything repeated (fans, fence segments, stands) is a `MultiMesh`.
3. **One material for opaque stuff.** `MeshMerger.vertex_color_material()`. Per-object materials
   defeat state-change batching and add cost.
4. **No shadows, no real-time GI, no SSAO/glow/fog, no dynamic lights beyond the one sun.**
   They are off; keep them off.
5. **Avoid new large transparent quads.** Use alpha only for small things (zone, tracer lines).
6. **Don't use the physics engine for the ball.** The ball is a custom integrator; there are no
   physics bodies in the scene. Keep it that way, and keep AI/fielding logic cheap per frame.
7. **Textures:** none yet. If added, ASTC/ETC2 compressed, small, atlased.

## Measuring

Everything here runs **without the headset** (see `tools/`): `--xr-mode off` stops Godot from
starting OpenXR, so Virtual Desktop is never touched.

| Command | What it does |
|---|---|
| `tools/test.sh` | all headless tests, including `perf_test` (estimated draw calls / triangles vs budget; governor behavior) |
| `tools/perf.sh [--demo] [--budget]` | really renders the scene in an off-screen window and reports draw calls, objects, triangles, node counts, memory |
| `tools/shot.sh <view> [--demo --profile=MVP]` | writes PNG frames to `tools/shots/` so a change can be looked at |
| `tools/godot.sh <args>` | any Godot command, headset-free |

Draw calls and triangle counts are the same on any GPU, so `perf.sh` is a faithful budget check
even though the PC GPU's frame time is not comparable to a Quest's.

## Runtime safety net

`PerfGovernor` watches frame time (against 90 Hz in VR, 60 Hz on desktop) and steps quality down
after about a second of sustained slowness, ignoring one-off hitches, then climbs back slowly:

| Level | Crowd | Netting | Render scale |
|---|---|---|---|
| 0 | full | on | 1.0 |
| 1 | 50% | off | 1.0 |
| 2 | 20% | off | 0.85 |
| 3 | 8% | off | 0.70 |

Gameplay is never touched. `-- --no-governor` disables it, `-- --perf` prints a line a second
(frame ms, draw calls, k-triangles, level).

Quest render tuning (90 Hz request, foveation, variable-rate shading, governor-driven render
scale) is behind the `xr_tuning` export on the Bullpen node and is **off by default**. A headset
test over Virtual Desktop went black right after start-up with it on, and it buys nothing over
a stream. Enable it only for a standalone build, and test it there. VRS must never be a project
setting: it blanks the desktop view.

The game prints `XR: started on ...` at start-up and an `XR heartbeat` line every 5 s into
`%APPDATA%\Godotpp_userdata\VR Baseball\logs\godot.log`, so a blank-screen report leaves a
trail.

## What is NOT verified yet

* **Real Quest 3 numbers.** Virtual Desktop renders on the PC GPU and streams video, so it says
  nothing about on-device GPU time, thermals, or CPU cost on the Quest's mobile chip. The budgets
  above are conservative estimates, and the counts are right, but only an installed build
  confirms them.
* **Standalone export.** Needs a JDK, the Android SDK, Godot export templates, and the Godot
  OpenXR Vendors plugin. None are installed here. Once exported: use Meta's OVR Metrics Tool for
  GPU %, frame time, and thermals; `--perf` for the in-game line.
* **Foveation / refresh-rate settings** are applied by name and untested on a device; the
  runtime may ignore them.
* **Fill rate** of the crowd and netting at Quest resolution has not been measured.

## When this starts to hurt (in order)

1. Draw calls creeping past ~120: merge more, or instance more.
2. Add a pitch/hit pool instead of creating and freeing meshes every pitch.
3. LOD the crowd (already scaled by the governor) and the far stands.
4. Reduce `MSAA` or render scale before cutting content.
