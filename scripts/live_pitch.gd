class_name LivePitch
extends RefCounted
## A pitch in flight: where it is, what the batter and defense decided about it, and how it ended.

var ball: MeshInstance3D
var trail_inst: MeshInstance3D
var trail_mesh := ImmediateMesh.new()
var trail := PackedVector3Array()
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var spin := Vector3.ZERO
var flight_time := 0.0
var accum := 0.0
var steps := 0
var landed := false
var linger := 0.0
var label := ""
var analysis := {}
var flutter_amp := 0.0
var flutter_seed := 0.0
var bat := {}            # BatterAI.evaluate() result for this pitch
var sim := {}            # BattedBall.simulate() result when the pitch is hit
var play := {}           # Defense.resolve() result for it
var swing_peak := 0.0               # the fastest your bat's barrel moved while the ball was near the plate
var human_chance := false          # the human fielder owns this ball
var play_fallback := {}            # what happens if he does not get it
