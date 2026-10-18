class_name Player
extends RefCounted
## One ballplayer: who he is and how good he is. Every system reads ratings from here instead of
## carrying its own constants, so a faster runner, a stronger fielder or a better hitter is just
## a different Player.
##
## Ratings are 0-100 with 50 = an average everyday player, 80 = elite, 20 = poor. Convert them
## to game quantities with factor() so 50 always lands on the calibrated baseline.

var name := "Player"
var number := 0
var bats_right := true
var throws_right := true
## Primary defensive position as scored: 1 P, 2 C, 3 1B, 4 2B, 5 3B, 6 SS, 7 LF, 8 CF, 9 RF.
var position := 0

# --- Hitting
var contact := 50.0        # puts the bat on the ball
var power := 50.0          # bat speed -> exit velocity
var eye := 50.0            # sees the pitch, lays off balls
var timing := 50.0         # consistency of the swing time
var recognition := 50.0    # adjusts to speed changes, reads movement
var aggression := 50.0     # approach (a tendency, not a skill): swings more at hittable pitches
var loft := 10.0           # typical bat path, degrees

# --- Running and fielding
var speed := 50.0          # baserunning and chasing speed
var fielding_range := 50.0 # first step, reach and dive
var hands := 50.0          # glove: clean catches and routine plays
var arm := 50.0            # throwing speed

# --- Pitching
var velocity := 50.0       # pitch speed
var command := 50.0        # hits the spot he aims for
var movement := 50.0       # how much the ball moves
var stamina := 50.0        # how long a pitcher holds his stuff: tires later at higher ratings


## 0 fresh .. 1 spent, from how many pitches a pitcher has thrown. Starts around 60 pitches for
## an average arm (later with more stamina), and is fully spent about 45 pitches after that.
func fatigue(pitches: int) -> float:
	var onset := 60.0 + (stamina - 50.0) * 0.9
	return clampf((float(pitches) - onset) / 45.0, 0.0, 1.0)
var repertoire: Array[String] = ["Fastball", "Curveball", "Slider", "Changeup"]


## rating 0-100 -> multiplier around 1.0 (50 -> 1.0, 100 -> 1.2, 0 -> 0.8). spread widens it.
static func factor(rating: float, spread: float = 0.4) -> float:
	return 1.0 + spread * (clampf(rating, 0.0, 100.0) / 100.0 - 0.5)


## Speed as a runner: scales the whole run (4.15 s to first for a 50).
func run_factor() -> float:
	return factor(speed, 0.30)


func hitting_overall() -> float:
	return (contact * 1.2 + power + eye + timing * 0.8 + recognition * 0.8) / 4.8


func pitching_overall() -> float:
	return (velocity + command * 1.3 + movement * 0.9) / 3.2


func fielding_overall() -> float:
	return (fielding_range + hands + arm) / 3.0


## One-line summary for the HUD.
func hitter_line() -> String:
	return "%s #%d  CON %d  POW %d  EYE %d  SPD %d" % [name, number, roundi(contact), roundi(power), roundi(eye), roundi(speed)]


func pitcher_line() -> String:
	return "%s #%d  VEL %d  CMD %d  MOV %d" % [name, number, roundi(velocity), roundi(command), roundi(movement)]
