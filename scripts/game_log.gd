class_name GameLog
extends RefCounted
## A session log for playtesting: one JSON object per line in user://events_<time>.jsonl, next to
## the throw log. On Windows: %APPDATA%\Godot\app_userdata\VR Baseball\
##
## It records what happened and what state the game was in when it did (pitches with where they
## crossed and how the batter reacted, every play and what the runners and fielders did, steals,
## pickoffs, balks, the batter's comings and goings, game flow, performance windows and frame
## spikes, menu use) so a playtest note like "the batter was missing after the fly out" can be
## matched to the exact moment and the state around it.
##
## Every entry has "t" (seconds since the session started), "kind", and then its own fields.
## A MARK (the B button on your throwing hand, or F on a desktop) writes the last few entries
## again with a full state snapshot, so a moment you flag is easy to find.
##
## Off with --no-log. Tests that set ThrowLogger.override_path write to a scratch file instead.

const RECENT := 60

static var override_path := ""
static var disabled := false
static var path := ""
static var count := 0
static var _file: FileAccess
static var _t0 := 0.0
static var _recent: Array = []


static func enabled() -> bool:
	if disabled or ThrowLogger.disabled:
		return false
	var args := OS.get_cmdline_user_args()
	return not ("--no-log" in args or "--no-log" in OS.get_cmdline_args())


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0 - _t0


## Open the file and write the session header. Safe to call once per scene load.
static func start(session: Dictionary) -> void:
	close()
	_t0 = Time.get_ticks_msec() / 1000.0
	_recent.clear()
	count = 0
	if not enabled():
		return
	if override_path != "":
		path = override_path
	elif ThrowLogger.override_path != "":
		path = "user://test_events.jsonl"          # a test run: never the player's log
	else:
		path = "user://events_%s.jsonl" % Time.get_datetime_string_from_system().replace(":", "-")
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("GameLog: cannot open %s" % path)
		return
	print("Logging events to ", ProjectSettings.globalize_path(path))
	session["os"] = OS.get_name()
	session["engine"] = Engine.get_version_info().string
	session["renderer"] = ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")
	session["wall"] = Time.get_datetime_string_from_system()
	event("session", session)


static func close() -> void:
	_file = null


## One entry. `data` is anything JSON can hold (Vector3 and Color are converted).
static func event(kind: String, data: Dictionary = {}) -> void:
	var entry := {}
	for k in data:
		entry[k] = _clean(data[k])
	entry["t"] = snappedf(_now(), 0.001)
	entry["kind"] = kind               # always the event's own kind, never a field of the same name
	count += 1
	_recent.append(entry)
	while _recent.size() > RECENT:
		_recent.pop_front()
	if _file != null:
		_file.store_line(JSON.stringify(entry))
		_file.flush()


## A moment worth finding later: the recent entries and a full snapshot, written again.
static func mark(reason: String, snapshot: Dictionary) -> void:
	event("mark", {"reason": reason, "state": snapshot, "recent": _recent.slice(0, maxi(_recent.size() - 1, 0)).slice(-25)})


static func _clean(v) -> Variant:
	if v is Vector3:
		return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
	if v is Vector2:
		return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]
	if v is Color:
		return v.to_html()
	if v is float:
		if is_nan(v) or is_inf(v):
			return null
		return snappedf(v, 0.0001)
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _clean(v[k])
		return d
	if v is Array or v is PackedStringArray or v is PackedFloat32Array or v is PackedInt32Array:
		var a := []
		for x in v:
			a.append(_clean(x))
		return a
	if v is Player:
		return (v as Player).name
	if v is bool or v is int or v is String or v == null:
		return v
	return str(v)
