class_name LiveHit
extends RefCounted
## A batted ball in play: played back along a path simulated at contact, with the play and the runners' plan it produced.

var ball: MeshInstance3D
var trail_inst: MeshInstance3D
var trail_mesh := ImmediateMesh.new()
var points := PackedVector3Array()
var dt := 1.0 / 120.0
var t := 0.0
var last_idx := 0
var summary := {}
var report := ""
var landing_shown := false
var rolling := false         # its roll on the ground is making a sound
var done := false
var linger := 5.0
var marker: MeshInstance3D
var label: Label3D
var play := {}            # Defense.resolve() result for this ball in play
var plan: PlayPlan = null   # Baserunning.plan(): every runner's timeline, throws, events (null until there is one)
var throws: Array[ThrowPlan] = []    # the ball's journey between fielders (relays included), in order
var anim_done := {}       # which throws and catches have had their animation started
var bunt := false         # he squared around to bunt
var human_chance := false # the human fielder is the one who would make this play
var human_state := ""     # "waiting" for the glove, "holding", "gripped", "thrown", "done"
var fallback := {}        # the AI's play if the human does not get to it
var chance_end := 0.0     # seconds after contact when his chance is over
var catch_t := 0.0
var catch_pos := Vector3.ZERO
var cover_t := -1.0       # you are the pitcher: when the batter reaches first, you must be on the bag (-1: no duty)
var cover_spot := Vector3.ZERO
var play_end := 0.0       # seconds after contact when the play is over
var result_shown := false
