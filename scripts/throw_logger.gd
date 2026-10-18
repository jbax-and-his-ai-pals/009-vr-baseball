class_name ThrowLogger
extends RefCounted
## Appends one JSON line per pitch to user://throws_<timestamp>.jsonl so the
## motion behind each throw can be analyzed offline. The file is created on the
## first pitch. On Windows: %APPDATA%\Godot\app_userdata\VR Baseball\

## Tests set this so their throws go to a scratch file instead of the player's real logs.
static var override_path := ""
## `--no-log` on the command line (demo runs, screenshots) records nothing.
static var disabled := false

var path := ""
var count := 0
var _file: FileAccess


func record(entry: Dictionary) -> void:
	if disabled or "--no-log" in OS.get_cmdline_user_args() or "--no-log" in OS.get_cmdline_args():
		count += 1
		return
	if _file == null:
		if override_path != "":
			path = override_path
		else:
			path = "user://throws_%s.jsonl" % Time.get_datetime_string_from_system().replace(":", "-")
		_file = FileAccess.open(path, FileAccess.WRITE)
		if _file == null:
			push_warning("ThrowLogger: could not open %s" % path)
			return
		print("Logging throws to ", ProjectSettings.globalize_path(path))
	count += 1
	entry["n"] = count
	_file.store_line(JSON.stringify(entry))
	_file.flush()


static func vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


## Angle above horizontal, degrees. Positive = upward.
static func elevation_deg(v: Vector3) -> float:
	return rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))


## Angle left/right of straight at the plate, degrees. Positive = to the right.
static func azimuth_deg(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, -v.z))
