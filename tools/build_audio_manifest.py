#!/usr/bin/env python3
"""Build the audio manifest (audio/manifest.json) and the human list (docs/AUDIO_LIST.md).

This file is the single source of truth for every sound the game wants. Edit the table, run

    python tools/build_audio_manifest.py

and both outputs are rewritten. The game reads audio/manifest.json; a sound with no file yet is
simply silent (or uses a placeholder from tools/make_placeholder_audio.py).

Columns: id, category, priority (P0 the game feels wrong without it, P1 polish, P2 later),
variants (how many different takes, to avoid repetition), seconds (about, per take), loop,
bus, 3d (positional in the world), trigger (what plays it), description (what it should sound
like and how to record or make it), recipe (the placeholder synthesis).
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# fmt: off
S = []


DIRS = {"Pitching and catching": "pitching", "Batting": "batting", "Ball in play": "ball", "Fielding and running": "fielding",
        "Umpire and announcer": "voices", "Crowd": "crowd", "Stadium": "stadium", "Interface": "ui", "Music": "music"}


def add(id, cat, pri, variants, secs, bus, trigger, desc, recipe, loop=False, three_d=True):
    S.append(dict(id=id, category=cat, dir=DIRS[cat], priority=pri, variants=variants, seconds=secs, loop=loop,
                  bus=bus, spatial=three_d, trigger=trigger, description=desc, recipe=recipe))


# ------------------------------------------------------------------ PITCHING
C = "Pitching and catching"
add("glove_pop_soft", C, "P0", 5, 0.35, "SFX", "pitch caught, under ~60 mph", "A baseball into a catcher's mitt, gentle: a soft dull pop with a little leather slap. Record a real ball into a real mitt at low speed, close mic, several takes.", "pop_soft")
add("glove_pop_medium", C, "P0", 5, 0.40, "SFX", "pitch caught, 60-80 mph", "The classic mitt pop: sharp slap then a short low thump. The most-heard sound in the game: record many takes, keep the best five that differ in pitch.", "pop_medium")
add("glove_pop_hard", C, "P0", 5, 0.45, "SFX", "pitch caught, over 80 mph", "A hard fastball in the mitt: loud crack-pop with a brief ring. Same mitt and mic as the others so they match.", "pop_hard")
add("glove_pop_dirt_block", C, "P0", 3, 0.5, "SFX", "dirt ball blocked", "A ball hitting dirt then chest protector: low thud with a puff of dirt. Drop a ball on packed dirt next to a padded chest.", "thud_low")
add("ball_hits_backstop", C, "P1", 3, 0.7, "SFX", "wild pitch reaches the backstop", "Ball into netting and padding: dull thud, then a short fabric rattle.", "thud_rattle")
add("ball_hits_gear", C, "P1", 3, 0.3, "SFX", "ball off the catcher's or umpire's gear", "A hard plastic and foam thump.", "thud_mid")
add("ball_hits_batter", C, "P0", 3, 0.35, "SFX", "hit by pitch", "A ball into a padded jersey or a thigh: a short dull whump (not a crack).", "thud_mid")
add("batter_hurt_grunt", C, "P1", 3, 0.5, "Voice", "hit by pitch", "A short pained grunt, no words.", "voice_grunt")
add("ball_skid_dirt", C, "P1", 3, 0.6, "SFX", "bounce pitch / dirt ball", "A ball skipping on dirt: two or three quick thuds with a dry scuff.", "thud_skip")
add("ball_flight_whiz", C, "P1", 2, 0.8, "SFX", "pitch in flight, follows the ball", "A very faint air whiz that rises as it approaches (looped, pitch-shifted by speed). Barely there; it should make the pitch feel fast without being heard as a sound effect.", "whoosh_thin", loop=True)
add("arm_tired_breath", C, "P1", 1, 4.0, "SFX", "your arm is tired", "A slow, close breath loop with a faint heartbeat under it. Never loud.", "breath", loop=True, three_d=False)
add("corner_chime", C, "P1", 3, 0.5, "UI", "a strike on a corner (gold halo)", "A short soft glass ding, pleasant, rising slightly. Reward, not an alarm.", "chime")
add("zone_dot_pop", C, "P2", 2, 0.12, "UI", "a pitch dot appears", "A tiny bubble tick.", "tick")

# ------------------------------------------------------------------ BATTING
C = "Batting"
for speed, n in (("slow", 4), ("medium", 4), ("fast", 4)):
    add("bat_swing_" + speed, C, "P0", n, 0.35, "SFX", "the batter swings (%s)" % speed, "Air cut by a bat: %s swing. Swing a real bat hard past a mic at three speeds; a thin rising whoosh." % speed, "whoosh_mid")
add("bat_crack_sweet", C, "P0", 8, 0.55, "SFX", "squared-up contact, 95+ mph exit", "The sound the game is about: a clean wooden-bat crack with bright ring and a short tail. Record real bat on real ball, several takes, and keep the eight that differ in pitch.", "crack_hard")
add("bat_crack_good", C, "P0", 6, 0.5, "SFX", "solid contact, 80-95 mph", "Slightly lower and shorter than the sweet crack.", "crack_mid")
add("bat_crack_weak", C, "P0", 6, 0.4, "SFX", "weak or jammed contact", "A dull clunk or a thunk with a tiny rattle: the ball off the handle or the end of the bat.", "clunk")
add("bat_foul_tip", C, "P0", 4, 0.25, "SFX", "foul tip", "A thin tick: just a brush of ball on bat.", "tick")
add("bat_bunt_tap", C, "P0", 4, 0.3, "SFX", "bunt", "A soft muted tap of a ball on a held bat.", "thud_soft")
add("bat_break", C, "P2", 2, 0.8, "SFX", "bat breaks (rare, on a jam)", "A splintering crack with a clatter of wood.", "crack_rattle")
add("bat_drop", C, "P1", 3, 0.9, "SFX", "bat dropped after a walk or hit", "A wooden bat clattering on dirt, one or two bounces.", "clatter")
add("bat_flip", C, "P2", 2, 0.8, "SFX", "a big-hit bat toss", "Whirl of a thrown bat then a clatter.", "clatter")
add("batter_swing_grunt", C, "P1", 4, 0.4, "Voice", "a full swing", "A short effort grunt, a different one each time.", "voice_grunt")
add("batter_step_dirt", C, "P1", 3, 0.2, "SFX", "batter digs in", "Cleats shifting in dirt.", "step_dirt")
add("bat_tap_plate", C, "P2", 2, 0.3, "SFX", "batter taps the plate", "Two light taps of a bat on a rubber plate.", "tick")

# ------------------------------------------------------------------ BALL IN PLAY
C = "Ball in play"
add("ball_bounce_dirt", C, "P0", 5, 0.25, "SFX", "ball hits the infield dirt", "A dull thump with a dry scuff.", "thud_low")
add("ball_bounce_grass", C, "P0", 5, 0.25, "SFX", "ball hits the grass", "A soft thump with a faint rustle.", "thud_soft")
add("ball_roll_grass", C, "P1", 2, 1.5, "SFX", "ball rolls on grass", "A quiet hushed roll, loopable.", "rumble", loop=True)
add("ball_roll_dirt", C, "P1", 2, 1.5, "SFX", "ball rolls on dirt", "A gritty quiet roll, loopable.", "rumble", loop=True)
add("ball_hits_wall", C, "P0", 5, 0.8, "SFX", "ball off the outfield wall", "A hard padded thud with a metal rattle behind it.", "thud_rattle")
add("fence_rattle", C, "P1", 3, 1.2, "SFX", "ball hits the fence", "A chain-link rattle fading out.", "rattle")
add("ball_into_stands", C, "P0", 3, 1.2, "SFX", "home run lands in the seats", "Ball hitting seats and bouncing: hollow plastic and metal clatters, with a little crowd reacting under it.", "clatter")
add("ball_hits_pole", C, "P2", 2, 1.0, "SFX", "off the foul pole", "A bright metallic ping that rings.", "ping")
add("home_run_crack", C, "P0", 2, 0.8, "SFX", "a home run (layered on top of the crack)", "A bigger bat crack with a boom underneath; the ball leaving the park.", "crack_hard")

# ------------------------------------------------------------------ FIELDING AND RUNNING
C = "Fielding and running"
add("glove_catch_fly", C, "P0", 6, 0.35, "SFX", "a fly ball is caught", "A softer, rounder pop than the catcher's: ball into a fielder's glove in the air.", "pop_soft")
add("glove_scoop_ground", C, "P0", 6, 0.35, "SFX", "a ground ball is fielded", "Leather scoop with a little grass.", "pop_soft")
add("glove_catch_throw", C, "P0", 6, 0.35, "SFX", "a throw is caught at a base", "A crisp smack: a hard throw in the glove.", "pop_medium")
add("catch_dive_thud", C, "P1", 4, 0.8, "SFX", "a diving catch", "A body hitting grass plus a glove pop.", "thud_low")
add("throw_whoosh", C, "P0", 6, 0.4, "SFX", "a fielder's throw leaves his hand", "A ball cutting air, fast and thin. Different lengths for short and long throws.", "whoosh_thin")
add("throw_grunt", C, "P1", 4, 0.4, "Voice", "a hard throw", "A short effort sound.", "voice_grunt")
add("fielder_call_mine", C, "P1", 4, 0.6, "Voice", "a fielder calls for the ball", "'Mine!' / 'I got it!' variations, shouted.", "voice_call")
add("step_dirt_run", C, "P0", 8, 0.18, "SFX", "running on dirt (one footfall)", "A single cleated footfall on dirt; played in sequence with random pitch.", "step_dirt")
add("step_grass_run", C, "P0", 8, 0.18, "SFX", "running on grass (one footfall)", "A single cleated footfall on grass.", "step_grass")
add("step_walk", C, "P2", 4, 0.3, "SFX", "walking", "Slow cleated steps.", "step_dirt")
add("slide_dirt", C, "P0", 4, 0.9, "SFX", "a runner slides", "A long dirt skid with cloth drag and a puff.", "skid")
add("base_bag_thump", C, "P0", 4, 0.3, "SFX", "a runner or fielder hits a base", "A soft canvas thump on a bag.", "thud_soft")
add("tag_slap", C, "P0", 4, 0.3, "SFX", "a tag", "Glove slapping a runner or his jersey.", "slap")
add("cloth_rustle", C, "P2", 3, 0.5, "SFX", "jerseys and gear moving", "Fabric swishes.", "swish")
add("dugout_chatter", C, "P2", 2, 30.0, "Crowd", "dugout ambience", "Low players' chatter, rhythmic claps and calls.", "murmur", loop=True)

# ------------------------------------------------------------------ UMPIRE AND VOICES
C = "Umpire and announcer"
add("ump_strike", C, "P0", 6, 0.9, "Voice", "called strike / swinging strike", "'Strike!' at different energies. Record a real person, loud and clipped.", "voice_call")
add("ump_strike_three", C, "P0", 4, 1.2, "Voice", "strikeout", "A longer, louder 'Strike three!' (punch-out).", "voice_call")
add("ump_ball", C, "P0", 4, 0.8, "Voice", "ball (low key: the umpire only murmurs it)", "'Ball.' short and flat.", "voice_call")
add("ump_out", C, "P0", 5, 0.9, "Voice", "an out at a base", "'Out!' firm.", "voice_call")
add("ump_safe", C, "P0", 5, 0.9, "Voice", "safe at a base", "'Safe!' open and long.", "voice_call")
add("ump_foul", C, "P0", 3, 0.9, "Voice", "foul ball", "'Foul ball!'", "voice_call")
add("ump_balk", C, "P1", 2, 1.0, "Voice", "a balk", "'Balk!'", "voice_call")
add("ump_infield_fly", C, "P1", 2, 1.6, "Voice", "infield fly rule", "'Infield fly, batter's out!'", "voice_call")
add("ump_time", C, "P2", 2, 0.8, "Voice", "time out / dead ball", "'Time!'", "voice_call")
add("ump_play_ball", C, "P1", 2, 1.2, "Voice", "game start", "'Play ball!'", "voice_call")
for n, line in (("now_batting", "Now batting..."), ("now_pitching", "Now pitching..."), ("pitching_change", "A pitching change"),
                ("welcome", "Welcome to the ballpark"), ("final_score", "That's the final"), ("home_run_call", "Home run!")):
    add("pa_" + n, C, "P1" if n in ("now_batting", "welcome", "final_score") else "P2", 2, 2.0, "Voice", "stadium PA: " + line, "Stadium announcer with the PA's slight echo and band-limiting: '%s' (generic: names are fictional and not spoken)." % line, "voice_call", three_d=False)
add("pa_number_digits", C, "P2", 100, 0.6, "Voice", "stadium PA reads a jersey number", "Numbers 0-99 so the announcer can say 'number 42'. Only if we want names or numbers read.", "voice_call", three_d=False)
add("vendor_shout", C, "P2", 6, 1.5, "Crowd", "vendors in the stands", "'Peanuts here!' 'Cold drinks!' far away, lightly reverbed.", "voice_call")
add("fan_shout", C, "P2", 12, 1.2, "Crowd", "individual fans", "'Let's go!' 'Come on!' 'Strike him out!' kids and adults, distant.", "voice_call")

# ------------------------------------------------------------------ CROWD
C = "Crowd"
for name, desc in (("low", "a sparse, relaxed crowd murmur: an early inning, nobody on"),
                   ("medium", "a mid-game crowd: steady conversation with some waves of noise"),
                   ("high", "an excited crowd: loud, rhythmic, runners in scoring position"),
                   ("tense", "a hushed, nervous crowd: a late close game with two strikes"),
                   ("pregame", "an arriving crowd with more movement and PA echo")):
    add("crowd_bed_" + name, C, "P0" if name in ("low", "medium", "high") else "P1", 1, 60.0, "Crowd", "ambience bed: " + name, desc + ". 60-second seamless loop, stereo, no single voice clearly audible.", "murmur", loop=True, three_d=False)
add("crowd_cheer_small", C, "P0", 4, 2.0, "Crowd", "a strike, a routine out", "A short polite cheer and a few claps.", "cheer")
add("crowd_cheer_medium", C, "P0", 4, 3.0, "Crowd", "a hit, a strikeout, a good play", "A solid cheer building then fading.", "cheer")
add("crowd_cheer_big", C, "P0", 4, 4.0, "Crowd", "a big hit, a game-ending strikeout", "A loud cheer with whoops.", "cheer")
add("crowd_roar_hr", C, "P0", 3, 6.0, "Crowd", "a home run", "The loudest sound in the game: a rising roar with a long tail.", "cheer")
add("crowd_groan", C, "P0", 4, 2.0, "Crowd", "a near miss, a ball, an error", "A collective 'ohhh' that falls in pitch.", "groan")
add("crowd_oooh", C, "P1", 4, 2.0, "Crowd", "a long fly ball in the air", "A rising anticipatory 'ooooh'.", "groan")
add("crowd_boo", C, "P1", 3, 2.5, "Crowd", "a walk, a bad call", "Boos, mixed.", "groan")
add("crowd_gasp", C, "P1", 3, 1.0, "Crowd", "wild pitch, hit by pitch, a close play", "A sharp collective intake.", "gasp")
add("crowd_clap_rhythm", C, "P2", 2, 8.0, "Crowd", "a rally: clap along", "A steady clap beat, loopable.", "cheer", loop=True)
add("crowd_applause_polite", C, "P1", 3, 3.0, "Crowd", "a walk-off, a new pitcher", "Polite applause.", "cheer")
add("seat_flip_clatter", C, "P2", 3, 1.0, "Crowd", "seats", "Stadium seats flipping and clapping.", "clatter")
add("stadium_wind", C, "P2", 1, 30.0, "Crowd", "open air", "Wind across an open bowl, faint; loopable.", "murmur", loop=True, three_d=False)

# ------------------------------------------------------------------ STADIUM
C = "Stadium"
add("scoreboard_run_chime", C, "P1", 2, 1.5, "SFX", "a run scores", "A bright scoreboard chime.", "chime", three_d=False)
add("scoreboard_hr_horn", C, "P1", 2, 3.0, "SFX", "a home run", "A big stadium horn blast with a short fanfare tail.", "horn", three_d=False)
add("organ_charge", C, "P1", 1, 3.0, "Music", "rally", "The 'charge!' organ riff (an original, not the trademarked one).", "chord", three_d=False)
add("organ_stinger", C, "P1", 3, 4.0, "Music", "between batters", "Short organ stabs.", "chord", three_d=False)
add("organ_inning_tune", C, "P2", 4, 20.0, "Music", "between innings", "Short original ballpark organ tunes.", "chord", three_d=False)
add("seventh_inning_stretch", C, "P2", 1, 60.0, "Music", "the seventh inning (a stretch of a long game)", "An original sing-along; crowd singing mixed in.", "chord", three_d=False)
add("light_tower_buzz", C, "P2", 1, 20.0, "SFX", "night ambience", "A faint electrical hum from far lights; loopable.", "murmur", loop=True, three_d=False)
add("fireworks", C, "P2", 3, 3.0, "SFX", "home run celebration", "A launch hiss, a boom, a crackle.", "boom", three_d=False)

# ------------------------------------------------------------------ UI
C = "Interface"
add("ui_hover", C, "P0", 1, 0.08, "UI", "a menu row is pointed at", "A tiny soft tick.", "tick", three_d=False)
add("ui_select", C, "P0", 2, 0.2, "UI", "a menu choice", "A friendly click.", "click", three_d=False)
add("ui_back", C, "P0", 1, 0.2, "UI", "back", "A softer descending click.", "click", three_d=False)
add("ui_toggle_on", C, "P1", 1, 0.2, "UI", "an option on", "A rising two-tone.", "click", three_d=False)
add("ui_toggle_off", C, "P1", 1, 0.2, "UI", "an option off", "A falling two-tone.", "click", three_d=False)
add("ui_error", C, "P1", 1, 0.3, "UI", "something not allowed", "A short soft buzz.", "buzz", three_d=False)
add("ui_pause_open", C, "P0", 1, 0.4, "UI", "pause menu opens", "A low whoosh-in; game sounds duck.", "whoosh_mid", three_d=False)
add("ui_pause_close", C, "P0", 1, 0.4, "UI", "pause menu closes", "The reverse.", "whoosh_mid", three_d=False)
add("ui_start_game", C, "P1", 1, 1.0, "UI", "a game starts", "A bat-on-ball crack with a short crowd swell.", "crack_mid", three_d=False)
add("ui_notice", C, "P1", 2, 0.3, "UI", "a notice appears", "A gentle ping.", "chime", three_d=False)
add("ui_mark_moment", C, "P1", 1, 0.4, "UI", "you marked a moment in the log", "A short camera-shutter click.", "click", three_d=False)

# ------------------------------------------------------------------ MUSIC
C = "Music"
add("music_menu", C, "P1", 1, 90.0, "Music", "main menu", "An upbeat, warm, cartoony theme with a ballpark feel: brass and organ, light drums. 90-second seamless loop.", "arp", loop=True, three_d=False)
add("music_game_base", C, "P1", 1, 120.0, "Music", "during a game: base stem", "A quiet, steady underscore: a gentle groove that never fights the crowd or the calls. Loop; stems line up with the layers below.", "arp", loop=True, three_d=False)
add("music_game_rhythm", C, "P2", 1, 120.0, "Music", "runners on base: added rhythm stem", "A drum and bass layer that fades in over the base stem.", "arp", loop=True, three_d=False)
add("music_game_tension", C, "P2", 1, 120.0, "Music", "late and close: added tension stem", "Sustained strings and a pulse that fades in over the base stem.", "arp", loop=True, three_d=False)
add("music_inning_change", C, "P1", 4, 5.0, "Music", "an inning ends", "A short bright jingle.", "arp", three_d=False)
add("music_strikeout_sting", C, "P2", 3, 2.0, "Music", "a strikeout", "A punchy two-second sting.", "arp", three_d=False)
add("music_home_run_fanfare", C, "P1", 2, 6.0, "Music", "a home run", "Brass fanfare.", "arp", three_d=False)
add("music_victory", C, "P1", 1, 10.0, "Music", "you win", "A triumphant fanfare.", "arp", three_d=False)
add("music_loss", C, "P1", 1, 6.0, "Music", "you lose", "A wry, short wah-wah ending (never sad).", "arp", three_d=False)
add("music_walkup", C, "P2", 5, 10.0, "Music", "a batter steps in", "Short generic walk-up riffs in different styles.", "arp", three_d=False)
# fmt: on


def main() -> None:
    out_dir = os.path.join(ROOT, "audio")
    os.makedirs(out_dir, exist_ok=True)
    total_files = sum(s["variants"] for s in S)
    by_cat = {}
    for s in S:
        by_cat.setdefault(s["category"], []).append(s)
    manifest = {"version": 1, "sounds": S,
                "buses": ["Master", "SFX", "Crowd", "Music", "UI", "Voice"],
                "totals": {"ids": len(S), "files": total_files,
                           "p0_files": sum(s["variants"] for s in S if s["priority"] == "P0"),
                           "p1_files": sum(s["variants"] for s in S if s["priority"] == "P1"),
                           "p2_files": sum(s["variants"] for s in S if s["priority"] == "P2")}}
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)

    lines = ["# Audio list", "",
             "Generated by `tools/build_audio_manifest.py` from the table in that file. Edit there, not here.", "",
             "**%d sounds, %d files to create** (P0 %d, P1 %d, P2 %d). A sound with several variants is recorded or made that many different times so it does not repeat. "
             "`3D` means it comes from a place in the world; otherwise it is heard in the head." % (
                 len(S), total_files, manifest["totals"]["p0_files"], manifest["totals"]["p1_files"], manifest["totals"]["p2_files"]), "",
             "Priorities: **P0** the game feels wrong without it, **P1** polish, **P2** later.", ""]
    for cat, items in by_cat.items():
        lines.append("## %s (%d files)" % (cat, sum(i["variants"] for i in items)))
        lines.append("")
        lines.append("| id | P | files | sec | bus | 3D | loop | when | what it is |")
        lines.append("|---|---|---|---|---|---|---|---|---|")
        for i in items:
            lines.append("| `%s` | %s | %d | %.2g | %s | %s | %s | %s | %s |" % (
                i["id"], i["priority"], i["variants"], i["seconds"], i["bus"], "yes" if i["spatial"] else "", "loop" if i["loop"] else "",
                i["trigger"], i["description"].replace("|", "/")))
        lines.append("")
    with open(os.path.join(ROOT, "docs", "AUDIO_LIST.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("%d sounds, %d files (P0 %d, P1 %d, P2 %d)" % (len(S), total_files, manifest["totals"]["p0_files"],
                                                         manifest["totals"]["p1_files"], manifest["totals"]["p2_files"]))


if __name__ == "__main__":
    main()
