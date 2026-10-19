class_name Park
extends RefCounted
## A ballpark: how far the fence is in every direction, how tall the wall is, what time of day it is
## and what colors it wears. The fence and the wall are rules (a fly ball is a homer or it is not),
## the rest is the look. Three parks to start; every team can call one home.
##
##   Park.now()                  the park the game is being played in (set Park.current before the world is built)
##   Park.by_id("harbor")        a park by id; unknown ids give the default
##   park.fence_radius(psi)      meters from home plate to the fence in direction psi (degrees from
##                               center field; positive toward third base / left field)

const DEFAULT_ID := "harbor"

static var current: Park = null

var id := DEFAULT_ID
var name := "Harbor Field"
var left_line := 100.0          # down the third-base (left field) line
var right_line := 100.0         # down the first-base (right field) line
var center := 122.0             # dead center
var wall_height := 3.0
var night := false
var air := 1.0                  # air density relative to sea level: thin air (< 1) lets a fly ball carry
var wind := Vector3.ZERO        # m/s, the way the air moves: +z blows out to center, +x toward left field
var note := ""
var grass := Color(0.30, 0.62, 0.30)
var grass_stripe := Color(0.36, 0.70, 0.34)
var infield_grass := Color(0.27, 0.58, 0.27)
var dirt := Color(0.72, 0.52, 0.34)
var wall := Color(0.10, 0.28, 0.20)
var tiers: Array[Color] = [Color(0.22, 0.32, 0.65), Color(0.70, 0.20, 0.24), Color(0.22, 0.32, 0.65), Color(0.90, 0.78, 0.28)]
var sky := Color(0.53, 0.78, 0.95)
var ambient := 0.6


## The park in use (the default one until something sets Park.current).
static func now() -> Park:
	if current == null:
		current = by_id(DEFAULT_ID)
	return current


static func ids() -> Array:
	return ["harbor", "cozy", "canyon", "summit"]


static func by_id(park_id: String) -> Park:
	return Park.make(park_id if park_id in ids() else DEFAULT_ID)


static func make(park_id: String) -> Park:
	var p := Park.new()
	match park_id:
		"cozy":
			p.id = "cozy"
			p.name = "Cozy Yard"
			p.left_line = 84.0
			p.right_line = 94.0
			p.center = 110.0
			p.wall_height = 2.4
			p.note = "short porch in left, a low wall: homers are cheap"
			p.grass = Color(0.34, 0.60, 0.26)
			p.grass_stripe = Color(0.40, 0.67, 0.30)
			p.infield_grass = Color(0.30, 0.55, 0.24)
			p.dirt = Color(0.66, 0.42, 0.28)
			p.wall = Color(0.55, 0.12, 0.14)
			p.tiers = [Color(0.55, 0.14, 0.18), Color(0.90, 0.80, 0.55), Color(0.55, 0.14, 0.18), Color(0.30, 0.38, 0.30)]
			p.sky = Color(0.74, 0.84, 0.92)
		"summit":
			p.id = "summit"
			p.name = "Summit Field"
			p.left_line = 104.0
			p.right_line = 104.0
			p.center = 128.0
			p.wall_height = 3.3
			p.air = 0.80
			p.note = "high in the mountains: thin air, fly balls carry a long way"
			p.grass = Color(0.36, 0.60, 0.28)
			p.grass_stripe = Color(0.42, 0.66, 0.32)
			p.infield_grass = Color(0.32, 0.55, 0.26)
			p.dirt = Color(0.60, 0.46, 0.34)
			p.wall = Color(0.22, 0.26, 0.20)
			p.tiers = [Color(0.30, 0.24, 0.55), Color(0.85, 0.80, 0.90), Color(0.30, 0.24, 0.55), Color(0.55, 0.50, 0.40)]
			p.sky = Color(0.45, 0.72, 0.98)
		"canyon":
			p.id = "canyon"
			p.name = "Canyon Park"
			p.left_line = 108.0
			p.right_line = 108.0
			p.center = 135.0
			p.wall_height = 4.6
			p.night = true
			p.note = "a night game in a big park with a tall wall: fly balls die"
			p.grass = Color(0.20, 0.46, 0.26)
			p.grass_stripe = Color(0.24, 0.52, 0.30)
			p.infield_grass = Color(0.18, 0.42, 0.24)
			p.dirt = Color(0.58, 0.42, 0.32)
			p.wall = Color(0.08, 0.16, 0.30)
			p.tiers = [Color(0.12, 0.20, 0.42), Color(0.20, 0.34, 0.60), Color(0.12, 0.20, 0.42), Color(0.60, 0.62, 0.70)]
			p.sky = Color(0.06, 0.08, 0.20)
			p.ambient = 0.34
			p.wind = Vector3(0.0, 0.0, -3.5)
		_:
			p.note = "a fair park: 100 m down the lines, 122 to center"
	return p


## Meters from home plate to the fence in direction psi (degrees; positive is toward third base).
func fence_radius(psi_deg: float) -> float:
	var a := absf(psi_deg)
	if a <= 45.0:
		var line := left_line if psi_deg >= 0.0 else right_line
		return line + (center - line) * cos(deg_to_rad(a) * 2.0)
	var line_end := left_line if psi_deg >= 0.0 else right_line
	var t := (180.0 - a) / 135.0
	return 22.0 + (line_end - 22.0) * pow(t, 3.0)


## A short sentence for the menu.
func describe() -> String:
	var extra := ""
	if air < 0.95:
		extra += ", thin air"
	if wind.length() >= 1.0:
		extra += ", " + wind_text()
	return "%s - %d m down the lines, %d to center, %.1f m wall%s%s" % [name, int((left_line + right_line) * 0.5), int(center), wall_height, ", night" if night else "", extra]


## "wind 8 mph, blowing out to left" - how the air is moving, for a notice.
func wind_text() -> String:
	var mph := wind.length() * 2.237
	if mph < 2.0:
		return "calm"
	var out := wind.z >= 0.0
	var along := absf(wind.z)
	var across := absf(wind.x)
	var way := "out" if out else "in"
	if across > along * 1.5:
		way = "across, toward left" if wind.x > 0.0 else "across, toward right"
	elif across > along * 0.4:
		way = way + " to " + ("left" if wind.x > 0.0 else "right") if out else way + " from " + ("right" if wind.x > 0.0 else "left")
	return "wind %d mph, blowing %s" % [roundi(mph), way]
