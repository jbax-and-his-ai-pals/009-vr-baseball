class_name GameBus
extends RefCounted
## The things that happen in a game, announced once and heard by whoever cares. The code that makes
## something happen (a pitch arriving, the bat meeting the ball, a play ending) says so here; the code
## that reacts (sound, haptics, dust, the crowd, the dugouts, a challenge's score, the logs) listens.
## Neither side knows the other. Everything is emitted synchronously, in the order things happen.
##
## Who listens: `Reactions` (what you see, hear and feel), `Activities` (derby, lesson, challenges),
## `Manager` (the sign you were given), `GameResults` (the book), `SessionRecorder` (the logs).

## The pitch reached the plate and was not hit: taken for a ball or a strike, swung at and missed, or it hit the
## batter. `outcome` is the umpire's word: "ball", "called_strike", "swinging_strike" or "hit_by_pitch".
signal pitch_arrived(pitch: LivePitch, outcome: String)

## The bat met the ball (fair, foul, a tip or a bunt). The details are in `pitch.bat` and `pitch.sim`.
signal contact_made(pitch: LivePitch)

## Either of the above: a pitch has had its result. `outcome` as above, or "in_play" / "foul" after contact.
signal pitch_resolved(pitch: LivePitch, outcome: String)

## A batted ball came down (or hit the wall, or left the park).
signal ball_landed(hit: LiveHit)

## The game changed: a pitch result, a play, a steal, a walk. `ev` is the scorebook's event (GameState),
## `extra` what only the scene knows (exit velocity, distance).
signal event_happened(ev: Dictionary, extra: Dictionary)

## The scene has finished updating itself for that event (the next batter, the runners, the score).
signal event_settled(ev: Dictionary)

## A plate appearance ended, a half inning ended, the game ended (each follows `event_settled`).
signal pa_over(ev: Dictionary)
signal half_over(ev: Dictionary)
signal game_over(ev: Dictionary)

## A play on a batted ball reached the book. `text` is what the board says.
signal play_announced(hit: LiveHit, text: String, ev: Dictionary)
