class_name AudioManager
extends Node
## Every sound in the game goes through here: `audio.play("glove_pop_hard", position)`.
##
## The list of sounds (id, bus, whether it is positional, how many takes) is audio/manifest.json,
## built from tools/build_audio_manifest.py. The files are audio/<dir>/<id>_NN.wav (or .ogg).
## A sound with no file is silent, never an error, so recordings can arrive one at a time and
## replace the placeholders from tools/make_placeholder_audio.py without touching code.
##
## Rules it keeps so you never tire of a sound: a different take each time (never the same one
## twice in a row), a little random pitch and volume, and a pool of players that is never grown
## (the quietest or oldest is stolen when it is full).
##
## Buses: Master > SFX, Crowd, Music, UI, Voice. Crowd has a touch of reverb (the bowl).
## The crowd is four looping beds (low, medium, high, tense) crossfaded by one number, set_crowd().
## Music is one looping track at a time, crossfaded by play_music().

const MANIFEST := "res://audio/manifest.json"
const BUSES := ["SFX", "Crowd", "Music", "UI", "Voice"]
const POOL_3D := 20
const POOL_2D := 10
const BEDS := ["crowd_bed_low", "crowd_bed_medium", "crowd_bed_high", "crowd_bed_tense"]
const PITCH_JITTER := 0.04
const DB_JITTER := 1.5
## Sounds the player hears most never need the jitter muted; the interface wants none.
const NO_JITTER_BUSES := ["UI", "Music"]

static var instance: AudioManager

var enabled := true
var defs: Dictionary = {}                 # id -> manifest row
var _files: Dictionary = {}               # id -> Array[String]
var _cache: Dictionary = {}               # path -> AudioStream
var _last_take: Dictionary = {}           # id -> index of the take played last
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _bed_players: Dictionary = {}         # bed id -> AudioStreamPlayer
var _bed_target: Dictionary = {}          # bed id -> target linear gain
var _crowd_level := 0.3
var _crowd_on := false
var _music: AudioStreamPlayer
var _music_next: AudioStreamPlayer
var _loops: Dictionary = {}               # key -> {"p": player, "id": sound id, "target": linear gain, "follow": Node3D}
var _stems: Dictionary = {}               # stem id -> AudioStreamPlayer (in step with the game music)
var _stem_target: Dictionary = {}
var _music_id := ""
var _music_fade := 0.0
var _volumes := {"Master": 1.0, "SFX": 1.0, "Crowd": 0.8, "Music": 0.5, "UI": 0.8, "Voice": 1.0}
## What has been played lately (id and bus), newest last: for tests and the session log.
var recent: Array = []
var played := 0
var paused := false                       # the game is stopped (a menu is up): delayed sounds wait, the game's sound is ducked
var _pending: Array = []                  # delayed sounds: {"t": seconds left, "id", "at", "db"}
const PAUSE_DUCK_DB := -12.0
var counts: Dictionary = {}              # id -> times played (what a game actually used)
var missing := 0


func _ready() -> void:
	instance = self
	setup_buses()
	load_manifest()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 10.0
		p.max_distance = 160.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool2d.append(p2)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music_next = AudioStreamPlayer.new()
	_music_next.bus = "Music"
	add_child(_music_next)
	apply_volumes(_volumes)


func _exit_tree() -> void:
	if instance == self:
		instance = null


# ------------------------------------------------------------------ setup
## Make the buses if they are not there (the project has only Master). Safe to call twice.
static func setup_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(i, b)
		AudioServer.set_bus_send(i, "Master")
		if b == "Crowd":
			var rev := AudioEffectReverb.new()
			rev.room_size = 0.8
			rev.wet = 0.18
			AudioServer.add_bus_effect(i, rev)
		elif b == "Voice":
			var rev2 := AudioEffectReverb.new()
			rev2.room_size = 0.5
			rev2.wet = 0.08
			AudioServer.add_bus_effect(i, rev2)


func load_manifest(path: String = MANIFEST) -> void:
	defs.clear()
	_files.clear()
	if not FileAccess.file_exists(path):
		push_warning("AudioManager: no manifest at %s (the game will be silent)" % path)
		return
	var json := JSON.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or json.parse(f.get_as_text()) != OK or not (json.data is Dictionary):
		push_warning("AudioManager: cannot read %s" % path)
		return
	for s in json.data.get("sounds", []):
		defs[String(s.id)] = s
		_files[String(s.id)] = _find_files(s)


## The takes of one sound that exist on disk, in order. An .ogg replaces a .wav of the same take.
func _find_files(s: Dictionary) -> Array:
	var out: Array = []
	var dir := "res://audio/%s" % s.dir
	for v in range(1, int(s.variants) + 1):
		var stem := "%s/%s_%02d" % [dir, s.id, v]
		for ext in [".ogg", ".wav"]:
			if FileAccess.file_exists(stem + ext) or ResourceLoader.exists(stem + ext):
				out.append(stem + ext)
				break
	return out


## True if at least one take of this sound is on disk.
func has_sound(id: String) -> bool:
	return not (_files.get(id, []) as Array).is_empty()


## Sounds in the manifest that have no file yet (what is still to be made).
func missing_ids() -> Array:
	var out: Array = []
	for id in defs:
		if (_files.get(id, []) as Array).is_empty():
			out.append(id)
	return out


# ------------------------------------------------------------------ loading
func _stream(path: String, loop: bool) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path) as AudioStream
	if st == null:
		st = _load_raw(path)               # not imported yet (a fresh checkout, a test): read the file itself
	if st != null:
		if loop:
			_make_loop(st)
		_cache[path] = st
	return st


## Read a .wav (16-bit PCM) or .ogg straight from disk.
static func _load_raw(path: String) -> AudioStream:
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	if not path.ends_with(".wav"):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44:
		return null
	var channels := bytes.decode_u16(22)
	var rate := bytes.decode_u32(24)
	var bits := bytes.decode_u16(34)
	if bits != 16:
		return null
	# Find the "data" chunk.
	var pos := 12
	while pos + 8 <= bytes.size():
		var tag := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		if tag == "data":
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = rate
			w.stereo = channels == 2
			w.data = bytes.slice(pos + 8, pos + 8 + size)
			return w
		pos += 8 + size + (size & 1)
	return null


static func _make_loop(st: AudioStream) -> void:
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / (4 if w.stereo else 2)
	elif st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true


## Pick a take of `id` that is not the one played last.
func _pick(id: String) -> String:
	var files: Array = _files.get(id, [])
	if files.is_empty():
		return ""
	var i := randi() % files.size()
	if files.size() > 1 and i == int(_last_take.get(id, -1)):
		i = (i + 1 + randi() % (files.size() - 1)) % files.size()
	_last_take[id] = i
	return files[i]


# ------------------------------------------------------------------ playing
## Play a sound. `at` is a world position (the sound comes from there) or null (heard in the head);
## `db` adds to its volume and `pitch` multiplies its speed. Returns false if it could not play
## (no such sound, no file, or audio is off): never an error.
func play(id: String, at: Variant = null, db: float = 0.0, pitch: float = 1.0) -> bool:
	if not enabled or not defs.has(id):
		return false
	var path := _pick(id)
	if path == "":
		missing += 1
		return false
	var d: Dictionary = defs[id]
	var st := _stream(path, bool(d.loop))
	if st == null:
		missing += 1
		return false
	var jitter := not (String(d.bus) in NO_JITTER_BUSES)
	var p := pitch * (1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)) if jitter else pitch
	var v := db + (randf_range(-DB_JITTER, DB_JITTER) if jitter else 0.0)
	if at is Vector3 and bool(d.spatial) and not _pool3d.is_empty():
		var pl := _free_3d()
		pl.stream = st
		pl.bus = String(d.bus)
		pl.volume_db = v
		pl.pitch_scale = p
		pl.global_position = at
		pl.play()
	else:
		var pl2 := _free_2d()
		pl2.stream = st
		pl2.bus = String(d.bus)
		pl2.volume_db = v
		pl2.pitch_scale = p
		pl2.play()
	played += 1
	counts[id] = int(counts.get(id, 0)) + 1
	recent.append({"id": id, "bus": d.bus, "take": path, "at": at if at is Vector3 else null})
	if recent.size() > 40:
		recent.pop_front()
	return true


func _free_3d() -> AudioStreamPlayer3D:
	for p in _pool3d:
		if not p.playing:
			return p
	var best: AudioStreamPlayer3D = _pool3d[0]
	for p in _pool3d:
		if p.get_playback_position() > best.get_playback_position():
			best = p                           # the one that has been going longest
	return best


func _free_2d() -> AudioStreamPlayer:
	for p in _pool2d:
		if not p.playing:
			return p
	var best: AudioStreamPlayer = _pool2d[0]
	for p in _pool2d:
		if p.get_playback_position() > best.get_playback_position():
			best = p
	return best


## Play `id` `seconds` from now (a swing whoosh timed to the contact). The wait is in game time:
## it stops while the game is paused, like everything else.
func play_later(seconds: float, id: String, at: Variant = null, db: float = 0.0) -> void:
	if seconds <= 0.0:
		play(id, at, db)
		return
	_pending.append({"t": seconds, "id": id, "at": at, "db": db})


## The game stops (a menu is up) or goes on. Stopped: the game's sound is ducked (the interface is not),
## and sounds that only make sense while the ball is moving are cut.
func set_paused(on: bool) -> void:
	if on == paused:
		return
	paused = on
	if on:
		for key in ["whiz", "roll"]:
			loop_off(key)
	apply_volumes(_volumes)


func pending_count() -> int:
	return _pending.size()


# ------------------------------------------------------------------ the crowd
## Start or stop the crowd beds (they are silent while a menu is up, say).
func set_crowd_on(on: bool) -> void:
	_crowd_on = on
	if on:
		for id in BEDS:
			_ensure_bed(id)


## 0 is a sparse early-inning murmur, 1 is a roar's worth of tension. The beds crossfade to match.
func set_crowd(level: float, tense: bool = false) -> void:
	_crowd_level = clampf(level, 0.0, 1.0)
	_bed_target = {
		"crowd_bed_low": clampf(1.0 - _crowd_level * 2.4, 0.0, 1.0),
		"crowd_bed_medium": clampf(1.0 - absf(_crowd_level - 0.5) * 3.0, 0.0, 1.0),
		"crowd_bed_high": clampf((_crowd_level - 0.45) * 2.4, 0.0, 1.0),
		"crowd_bed_tense": 1.0 if tense else 0.0,
	}
	if tense:
		for k in ["crowd_bed_low", "crowd_bed_medium", "crowd_bed_high"]:
			_bed_target[k] = float(_bed_target[k]) * 0.4


func crowd_level() -> float:
	return _crowd_level


func _ensure_bed(id: String) -> AudioStreamPlayer:
	if _bed_players.has(id):
		return _bed_players[id]
	var files: Array = _files.get(id, [])
	if files.is_empty():
		return null
	var st := _stream(files[0], true)
	if st == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = "Crowd"
	p.volume_db = -60.0
	add_child(p)
	p.play()
	_bed_players[id] = p
	return p


## Gain of one bed, 0..1 (for tests).
func bed_gain(id: String) -> float:
	var p: AudioStreamPlayer = _bed_players.get(id)
	return db_to_linear(p.volume_db) if p != null and p.volume_db > -59.0 else 0.0


# ------------------------------------------------------------------ music
## Crossfade to this loop ("" fades to silence). The same track again does nothing.
func play_music(id: String, fade: float = 1.5) -> void:
	if id == _music_id:
		return
	_music_id = id
	if id != "music_game_base":
		for sid in _stems:
			(_stems[sid] as AudioStreamPlayer).queue_free()    # they only make sense over the base track
		_stems.clear()
	var swap := _music
	_music = _music_next
	_music_next = swap
	_music_fade = maxf(fade, 0.05)
	if id != "" and has_sound(id):
		_music.stream = _stream((_files[id] as Array)[0], true)
		_music.volume_db = -60.0
		_music.play()
	else:
		_music.stop()


func music_id() -> String:
	return _music_id


## A named loop (the ball whizzing in, a tired breath, wind, a rolling ball). Fades in and out, never
## doubles up under one key, and may follow a node (the ball). `db` is its steady level.
func loop_on(key: String, id: String, db: float = 0.0, at: Variant = null, follow: Node3D = null) -> void:
	var cur: Dictionary = _loops.get(key, {})
	if not cur.is_empty() and cur.id == id:
		cur.target = db_to_linear(db)
		cur.follow = follow
		cur.tracks = follow != null
		return
	if not cur.is_empty():
		loop_off(key)
	if not enabled or not defs.has(id) or (_files.get(id, []) as Array).is_empty():
		return
	var d: Dictionary = defs[id]
	var st := _stream((_files[id] as Array)[0], true)
	if st == null:
		return
	var p: Node
	if bool(d.spatial) and (at is Vector3 or follow != null):
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 10.0
		p3.max_distance = 160.0
		p3.stream = st
		p3.bus = String(d.bus)
		p3.volume_db = -60.0
		add_child(p3)
		p3.global_position = at if at is Vector3 else follow.global_position
		p3.play()
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = st
		p2.bus = String(d.bus)
		p2.volume_db = -60.0
		add_child(p2)
		p2.play()
		p = p2
	_loops[key] = {"p": p, "id": id, "target": db_to_linear(db), "follow": follow, "tracks": follow != null, "gain": 0.0}


func loop_off(key: String) -> void:
	if _loops.has(key):
		_loops[key].target = 0.0


func loop_active(key: String) -> bool:
	return _loops.has(key) and float(_loops[key].target) > 0.0


## The extra layers of the game music: a rhythm stem (men on base) and a tension stem (late, close).
## They are looped in step with the base track and only fade in and out. 0..1 each.
func set_stems(rhythm: float, tension: float) -> void:
	_stem_target = {"music_game_rhythm": clampf(rhythm, 0.0, 1.0), "music_game_tension": clampf(tension, 0.0, 1.0)}
	if _music_id != "music_game_base" or not _music.playing:
		return
	for id in _stem_target:
		if _stems.has(id) or not has_sound(id):
			continue
		var p := AudioStreamPlayer.new()
		p.stream = _stream((_files[id] as Array)[0], true)
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		p.play(_music.get_playback_position())      # in step with the base
		_stems[id] = p


func stem_gain(id: String) -> float:
	var p: AudioStreamPlayer = _stems.get(id)
	return db_to_linear(p.volume_db) if p != null and p.volume_db > -59.0 else 0.0


func _process(delta: float) -> void:
	if not paused:
		for i in range(_pending.size() - 1, -1, -1):
			var w: Dictionary = _pending[i]
			w.t -= delta
			if w.t <= 0.0:
				_pending.remove_at(i)
				play(String(w.id), w.at, float(w.db))
	for key in _loops.keys():
		var l: Dictionary = _loops[key]
		var pl: Node = l.p
		l.gain = move_toward(float(l.gain), float(l.target), delta / 0.6)
		pl.set("volume_db", linear_to_db(l.gain) if float(l.gain) > 0.003 else -60.0)
		if bool(l.tracks):
			if is_instance_valid(l.follow):
				if pl is AudioStreamPlayer3D:
					(pl as AudioStreamPlayer3D).global_position = (l.follow as Node3D).global_position
			else:
				l.target = 0.0                  # what it followed is gone
		if float(l.target) <= 0.0 and float(l.gain) <= 0.0:
			pl.queue_free()
			_loops.erase(key)
	for sid in _stems:
		var sp: AudioStreamPlayer = _stems[sid]
		var tgt := float(_stem_target.get(sid, 0.0)) if _music_id == "music_game_base" else 0.0
		var cur := db_to_linear(sp.volume_db) if sp.volume_db > -59.0 else 0.0
		cur = move_toward(cur, tgt, delta / 2.5)
		sp.volume_db = linear_to_db(cur) if cur > 0.003 else -60.0
	for id in _bed_players:
		var p: AudioStreamPlayer = _bed_players[id]
		var tgt := float(_bed_target.get(id, 0.0)) if _crowd_on else 0.0
		var cur := db_to_linear(p.volume_db) if p.volume_db > -59.0 else 0.0
		var next := move_toward(cur, tgt, delta / 2.0)
		p.volume_db = linear_to_db(next) if next > 0.003 else -60.0
	if _music_fade > 0.0:
		var step := delta / _music_fade
		var up := db_to_linear(_music.volume_db) if _music.volume_db > -59.0 else 0.0
		up = move_toward(up, 1.0, step)
		_music.volume_db = linear_to_db(up) if up > 0.003 else -60.0
		var down := db_to_linear(_music_next.volume_db) if _music_next.volume_db > -59.0 else 0.0
		down = move_toward(down, 0.0, step)
		_music_next.volume_db = linear_to_db(down) if down > 0.003 else -60.0
		if down <= 0.0 and _music_next.playing:
			_music_next.stop()
		if up >= 1.0 and down <= 0.0:
			_music_fade = 0.0


# ------------------------------------------------------------------ volumes
## Bus volumes from the player's settings: {"Master": 0..1, "SFX": .., "Crowd": .., "Music": .., "Voice": ..}.
## The UI bus follows SFX.
func apply_volumes(v: Dictionary) -> void:
	for k in v:
		_volumes[k] = clampf(float(v[k]), 0.0, 1.0)
	var duck := PAUSE_DUCK_DB if paused else 0.0
	_set_bus("Master", float(_volumes["Master"]))
	_set_bus("SFX", float(_volumes["SFX"]), duck)
	_set_bus("UI", float(_volumes["SFX"]) * 0.8)
	_set_bus("Crowd", float(_volumes["Crowd"]), duck)
	_set_bus("Music", float(_volumes["Music"]), duck)
	_set_bus("Voice", float(_volumes["Voice"]), duck)


static func _set_bus(name: String, linear: float, extra_db: float = 0.0) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)) + extra_db)


func volume(bus: String) -> float:
	return float(_volumes.get(bus, 1.0))
