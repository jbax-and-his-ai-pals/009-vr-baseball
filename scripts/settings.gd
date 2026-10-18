class_name Settings
extends RefCounted
## What the player chose, and what survives between sessions: handedness, assist level,
## comfort and performance options, and the last game played. One source of truth: the menu
## edits it, the game reads it, and it saves to a small config file.
##
## Assist is three named presets, not raw sliders. A preset bakes in the aim funnel, the glove
## and the throw cone, and each preset gets its own leaderboard, so an easy preset can never
## skew a harder board.

const PATH := "user://settings.cfg"
const VERSION := 1

const ASSISTS := ["Casual", "Standard", "Pro"]
const HANDS := ["right", "left"]
const QUALITY := ["Auto", "Quest", "High"]
const LOCOMOTION := ["smooth", "teleport"]

## The numbers an assist preset stands for. Standard is what the game has always played like.
const ASSIST_VALUES := {
	"Casual":   {"funnel_x": 0.28, "funnel_y": 0.20, "aim_assist": 1.0, "catch_radius": 0.45, "throw_cone": 34.0},
	"Standard": {"funnel_x": 0.40, "funnel_y": 0.30, "aim_assist": 1.0, "catch_radius": 0.34, "throw_cone": 26.0},
	"Pro":      {"funnel_x": 0.60, "funnel_y": 0.48, "aim_assist": 0.5, "catch_radius": 0.28, "throw_cone": 18.0},
}

## What each assist level means, in words, for the menu.
const ASSIST_NOTES := {
	"Casual": "wide aim funnel, big glove, forgiving throws",
	"Standard": "the intended feel",
	"Pro": "narrow funnel, small glove, throws must be on line",
}

var hand := "right"                # throwing hand
var assist := "Standard"
var quality := "Auto"              # Auto: governor decides; Quest: tuned settings; High: no tuning
var locomotion := "smooth"
var vignette := true               # darken the edges while moving (fielding)
var snap_turn := false
var developer := false             # reveals logging / debug options in the menu
var last_game := {}                # GameConfig.to_dict() of the last game started
## Volume per bus, 0..1 (the UI bus follows Effects). Music starts low: it is a background.
var volumes := {"Master": 1.0, "SFX": 1.0, "Crowd": 0.8, "Music": 0.5, "Voice": 1.0}


func assist_values() -> Dictionary:
	return ASSIST_VALUES[assist]


func throwing_hand_name() -> StringName:
	return &"right_hand" if hand == "right" else &"left_hand"


func to_dict() -> Dictionary:
	return {"version": VERSION, "hand": hand, "assist": assist, "quality": quality,
		"locomotion": locomotion, "vignette": vignette, "snap_turn": snap_turn,
		"developer": developer, "volumes": volumes, "last_game": last_game}


## Accepts anything: unknown or invalid values fall back to the defaults, so an old or
## hand-edited file can never put the game in a state the menu cannot show.
static func from_dict(d: Dictionary) -> Settings:
	var s := Settings.new()
	s.hand = d.get("hand", s.hand) if d.get("hand", "") in HANDS else s.hand
	s.assist = d.get("assist", s.assist) if d.get("assist", "") in ASSISTS else s.assist
	s.quality = d.get("quality", s.quality) if d.get("quality", "") in QUALITY else s.quality
	s.locomotion = d.get("locomotion", s.locomotion) if d.get("locomotion", "") in LOCOMOTION else s.locomotion
	s.vignette = bool(d.get("vignette", s.vignette))
	s.snap_turn = bool(d.get("snap_turn", s.snap_turn))
	s.developer = bool(d.get("developer", s.developer))
	var vols = d.get("volumes", {})
	if vols is Dictionary:
		for k in s.volumes:
			if vols.has(k) and (vols[k] is float or vols[k] is int):
				s.volumes[k] = clampf(float(vols[k]), 0.0, 1.0)
	var lg = d.get("last_game", {})
	s.last_game = lg if lg is Dictionary else {}
	return s


func save(path: String = PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Settings: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return true


## A missing or damaged file is not an error: you just get the defaults.
static func load_from(path: String = PATH) -> Settings:
	if not FileAccess.file_exists(path):
		return Settings.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return Settings.new()
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		return from_dict(json.data)
	return Settings.new()
