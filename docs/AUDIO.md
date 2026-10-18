# Audio plan

The full file list is `docs/AUDIO_LIST.md` (generated from `tools/build_audio_manifest.py`, which also
writes `audio/manifest.json`). Today: **116 sounds, 457 files** (P0 188, P1 99, P2 170).
This document is the reasoning: what the game should sound like, how it is wired, and how to make it.

## What audio has to do in this game

1. **Sell the pitch.** In a pitching game the glove pop is the reward. It is the most-heard sound,
   so it gets the most takes (3 speed tiers x 5) and it is positional: it comes from the catcher's
   mitt, 18 m in front of you, and that is how you know where it landed even before you look.
2. **Make contact legible.** Bat crack tiers (sweet / good / weak) tell you what happened a half-second
   before the ball is visible. Same sound language as the edge/center and corner halo feedback.
3. **Give the park a pulse.** A crowd bed that follows the game state (inning, runners, score margin)
   plus short one-shot reactions. The crowd is what makes a single pitch feel like it matters.
4. **Never fatigue.** Hundreds of pitches per session: every frequent sound needs variants, random
   pitch (+-4%) and volume (+-1.5 dB), and no two identical takes in a row.
5. **Be comfortable in VR.** Nothing sudden and loud near the head; no music that fights the
   directional cues; low-frequency rumble kept short (it reads as a physical hit on headphones).

## Recommendations

**Music: light and optional.** Menu theme, a quiet game underscore, and short stings (inning change,
home run, win/loss). A real ballpark has an organ and a PA, not a score, so the in-game music is
organ stabs between batters plus a very low stem under the crowd. Stems (base / rhythm / tension)
are P2: fade them by game state. Music has its own bus and its own slider, default low.

**Voices: few, and not words you have to translate.** Umpire calls (Strike / Ball / Out / Safe /
Foul), a handful of effort grunts, a generic stadium PA ("Now batting", fictional league, names
are not spoken so we never record a name). Crowd shouts are distant and unintelligible on purpose.
No commentary track.

**Spatial.** Everything physical is an `AudioStreamPlayer3D` at its source (mitt, bat, fielder's
glove, base, wall). Crowd beds, music, UI and the PA are 2D. Crowd reactions are 2D so they wrap
the head. Use Godot's built-in attenuation (inverse-square, max distance ~120 m); no HRTF plugin
is needed on Quest streamed through Virtual Desktop. Outfield catches should be quiet and slightly
lowpassed with distance so a deep fly ball sounds far.

**Buses.** `Master > { SFX, Crowd, Music, UI, Voice }`. Sliders for each in Options. A light
reverb send on Crowd and Voice (the bowl), none on SFX except the wall and stands. Duck Music by
6 dB under Voice and big crowd roars. Pausing ducks everything but UI.

**Performance.** Pool ~24 `AudioStreamPlayer3D` nodes (steals the quietest when full). Short one-shots
as 44.1 kHz mono ogg (decode on load) or wav for sub-half-second pops (zero latency matters for bat
and mitt). Loops as ogg. Total budget ~40 MB uncompressed; far less as ogg.

**Latency matters most for the bat.** The crack must start on the same frame as contact. Use wav,
preloaded, and trigger from the exact contact event in `bullpen.gd` (the same place the hit is
resolved), not from a later animation callback.

## Event mapping (what plays when)

| Game event | Sound |
|---|---|
| Pitch caught | `glove_pop_*` by speed, at the catcher's mitt; `ump_strike` 0.15 s later if a strike |
| Ball / dirt ball | `ump_ball` (quiet), `glove_pop_dirt_block` + `ball_skid_dirt` |
| Swing | `bat_swing_*` by swing speed; `batter_swing_grunt` occasionally |
| Contact | `bat_crack_*` by exit velocity and sweet-spot; `crowd_oooh` for a fly; foul tip -> `bat_foul_tip` |
| Ball bounces / rolls | `ball_bounce_dirt` / `ball_bounce_grass`, `ball_roll_*` while rolling |
| Fielded / thrown / caught | `glove_scoop_ground` or `glove_catch_fly`, `throw_whoosh`, `glove_catch_throw` |
| Out / safe | `ump_out` / `ump_safe`, `tag_slap`, `slide_dirt`, `base_bag_thump` |
| Strikeout | `ump_strike_three`, `crowd_cheer_medium`, `music_strikeout_sting` (P2) |
| Run scores | `scoreboard_run_chime`, `crowd_cheer_*` by margin |
| Home run | `home_run_crack`, `crowd_roar_hr`, `scoreboard_hr_horn`, `music_home_run_fanfare`, `ball_into_stands` |
| Walk / HBP / error | `crowd_boo` or `crowd_groan`; HBP also `ball_hits_batter` + `crowd_gasp` |
| Half-inning change | `music_inning_change`, organ stinger |
| Game over | `music_victory` / `music_loss`, `pa_final_score` |

## Crowd intensity (a single number)

`crowd = clamp(base + 0.25*runners_on + 0.3*late_close + 0.2*two_strikes, 0, 1)`; pick bed `low`
(<0.35), `medium`, `high` (>0.75), `tense` for late and close with two strikes; crossfade 2 s.
Reaction one-shots are scaled by the same number so a routine out in a blowout is polite.

## How to make it

No single route covers everything, so use the cheapest good route per category.

| Category | Best route | Why |
|---|---|---|
| Glove pops, bat cracks, bounces, steps, slides, rattles (about 60% of files) | **Record it yourself** (foley): a phone or small recorder, a real ball, a mitt, a wooden bat (a cheap one), a cardboard-and-towel "wall". Several takes each, pick the best; normalise and trim | These are the sounds that sell the game and are easy to get real. A $100 handheld recorder beats any library for matching pop to mitt |
| The rest of the physical SFX (whooshes, thuds, UI ticks) | **Synthesize** (`tools/make_placeholder_audio.py` style noise bursts + envelopes), or layer library clips | Cheap, consistent, and gives day-one placeholders |
| Crowd beds and cheers | **Licensed library** (CC0 / Sonniss GDC bundles, freesound CC0) layered and loop-edited; or record a real game | Needs many voices; a library is far better than faking it |
| Umpire / PA / grunts | **Record a voice** (you, a friend, or a hired voice actor for a few dollars per line); light EQ for the PA | A handful of short lines; a real person sounds far better than TTS here |
| Music | **Commission or use royalty-free packs**; or compose in a DAW (BandLab, LMMS, Reaper). AI music tools are usable for menu and sting drafts but check each tool's commercial licence and keep the prompts and receipts | Original loops are 1-2 hours of work for a composer; organ and brass cartoon style is easy to source |

**Tooling:** Audacity or Reaper (record and edit), `ffmpeg` (batch convert to ogg/wav, loudnorm),
a free sampler or synth (Vital, Surge XT) for stings. Master everything to about -16 LUFS for
loops and -12 for one-shots, peak under -1 dBFS, so the buses start balanced.

**Licensing rules.** Keep a `audio/CREDITS.md`: file, source, licence. CC0 or paid commercial only
(no CC-BY-NC). Any AI-generated audio: record the tool, plan, date and prompt.

## Order of work

1. **Placeholders** (day one): synthesize every P0 id from its `recipe` so the game is never
   silent and every hook can be tested. `audio/manifest.json` has the recipe name for each.
2. **Record the P0 physical sounds** (one afternoon): mitt pops, bat cracks/swings, bounces,
   steps, slide, tag.
3. **Crowd beds + cheers** from a library; **umpire lines** recorded.
4. **Menu music + stings**, then P1 polish (PA, organ, scoreboard).
5. P2 last: stems, vendors, fireworks, walk-ups.

## Naming and layout

`audio/<category>/<id>_<NN>.wav|ogg`, e.g. `audio/pitching/glove_pop_hard_03.wav`. The audio
manager loads by id and variant count from `manifest.json`: it picks randomly, never the same
take twice in a row, and a missing file is silent, so work can land one file at a time.

## What is built

- `scripts/audio_manager.gd` (`AudioManager`): loads `audio/manifest.json`, makes the buses, plays by id
  (`play(id, position)`, `play_later(seconds, id, position)`), a pool of 20 positional and 10 head-locked
  players, a different take each time with a little pitch and volume jitter, silent (not an error) when a
  sound has no file yet. Also the crowd (four looping beds crossfaded by `set_crowd(level, tense)`), music
  (`play_music(id)`, crossfaded), and `apply_volumes()` for the player's sliders.
- `tools/make_placeholder_audio.py`: synthesizes a stand-in for every P0 and P1 sound (`--all` adds P2) into
  `audio/<dir>/<id>_NN.wav`. It never overwrites an existing file, so a real recording dropped in as
  `<id>_NN.wav` or `.ogg` simply wins (an `.ogg` is preferred when both exist).
- Options > Sound: Master, Effects, Crowd, Music and Voices, in 25% steps, saved with the other settings.
- Wired in `bullpen.gd`: glove pops by pitch speed (and dirt, backstop, hit-by-pitch, the corner chime),
  umpire calls (strike, ball, strike three, out, safe, foul), swing whoosh and grunt, bat crack by exit
  velocity, bunts and foul tips, long-fly "ooh", home run crack/stands/horn/fanfare/roar, ball bounce
  (dirt or grass), wall, fielder catches and scoops, throws, tags, slides, base thumps, footsteps (dirt
  on the infield, grass elsewhere), crowd reactions to every result, run chime, inning-change jingle, PA
  "now batting", organ stingers, menu hover/select/back/error, pause open/close, mark-moment.
  The crowd bed follows inning, runners on, a close late game and two strikes.

## Not wired

Only two sounds have no trigger: `pa_pitching_change` (there are no substitutions in the game yet) and
`pa_number_digits` (the PA never reads a number or a name, on purpose). Wire them when those features exist.

Also wired since: the pitch whiz that follows the ball in, a tired arm's breathing, wind / light-tower hum /
dugout chatter, fans, vendors and seats now and then, a rolling ball, fence rattle, foul pole, bat flip and
drop, dive thud, "mine!" calls, cloth, walk-up songs, the music stems (rhythm with men on, tension late and
close), clapping and the organ charge in a rally, the seventh-inning stretch, fireworks, win and loss music,
menu toggle and notice sounds, balk / infield-fly / time / play-ball calls. Music stems must be exactly the
same length as the base track so they stay in step.

## Replacing a placeholder

1. Record or make the sound, trim, normalise (see "How to make it").
2. Name it `audio/<dir>/<id>_01.wav` (or `.ogg`), where `<dir>` and the number of takes are in
   `docs/AUDIO_LIST.md`. Replace the placeholder of the same name.
3. Run `tools/godot.sh --headless --import` once (Godot imports new audio), then play.
4. `AudioManager.missing_ids()` lists whatever still has no file at all.
