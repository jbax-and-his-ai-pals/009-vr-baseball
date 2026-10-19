class_name HandModels
extends RefCounted
## What your controllers look like: a cartoon hand for the throwing hand (and for batting), a leather
## glove for the other. Each is one baked mesh, one draw call, in the controller's own frame:
## the origin is where you hold it, -Z is the way it points, +Y is up (the back of the hand / the glove's
## top). Mirrored for the left hand so a left hand looks like a left hand.

const SKIN := Color(0.95, 0.76, 0.60)
const SKIN_SHADE := Color(0.86, 0.64, 0.50)
const CUFF := Color(0.90, 0.90, 0.94)
const LEATHER := Color(0.55, 0.34, 0.16)
const LEATHER_DARK := Color(0.38, 0.22, 0.10)
const LACE := Color(0.95, 0.85, 0.40)


## A hand wrapped round the controller: palm, four curled fingers, a thumb on the side, a white cuff.
static func hand_mesh(right: bool = true) -> ArrayMesh:
	var s := 1.0 if right else -1.0
	var m := MeshMerger.new()
	Figure.block(m, Vector3(0.0, 0.0, 0.0), Vector3(0.080, 0.032, 0.090), SKIN)               # palm
	# Four fingers curl from the front edge of the palm down and back under it.
	for i in 4:
		var x := (-0.030 + 0.020 * i) * s
		var top := Vector3(x, 0.004, -0.046)
		var knuckle := Vector3(x, -0.016, -0.066)
		var tip := Vector3(x, -0.040, -0.044)
		Figure.limb(m, top, knuckle, 0.0095, SKIN)
		Figure.limb(m, knuckle, tip, 0.0090, SKIN_SHADE)
	# The thumb lies along the side, pointing forward.
	Figure.limb(m, Vector3(0.042 * s, 0.002, 0.010), Vector3(0.050 * s, 0.006, -0.040), 0.011, SKIN)
	# Sleeve cuff at the wrist.
	Figure.block(m, Vector3(0.0, -0.002, 0.075), Vector3(0.070, 0.050, 0.040), CUFF)
	return m.build()


## A fielder's glove: a thick pad with a pocket, four fingers and a thumb, a web, laces.
## The pocket faces -Z (toward where the ball comes from when you hold your hand out in front of you).
static func glove_mesh(right_hand_glove: bool = false) -> ArrayMesh:
	var s := 1.0 if right_hand_glove else -1.0           # the glove is worn on the hand that does not throw
	var m := MeshMerger.new()
	Figure.block(m, Vector3(0.0, 0.0, -0.060), Vector3(0.150, 0.060, 0.130), LEATHER)         # the pad
	Figure.block(m, Vector3(0.0, 0.0, -0.126), Vector3(0.120, 0.050, 0.012), LEATHER_DARK)    # the pocket's heel
	Figure.block(m, Vector3(0.0, 0.0, -0.032), Vector3(0.100, 0.064, 0.014), LEATHER_DARK)    # the strap across the back
	for i in 4:
		var x := (-0.050 + 0.033 * i) * s
		var lean := 0.006 * (i - 1.5)
		Figure.limb(m, Vector3(x, 0.0, -0.110), Vector3(x + lean, 0.004, -0.205), 0.0185, LEATHER)
		Figure.ball(m, Vector3(x + lean, 0.004, -0.222), 0.0185, LEATHER, Vector3(1.0, 0.9, 1.0))
	Figure.limb(m, Vector3(0.062 * s, 0.0, -0.040), Vector3(0.100 * s, 0.002, -0.150), 0.022, LEATHER)   # the thumb
	Figure.block(m, Vector3(0.080 * s, 0.002, -0.120), Vector3(0.050, 0.010, 0.050), LEATHER_DARK, Vector3(0.0, -25.0 * s, 0.0))  # the web
	for i in 4:                                                                                 # laces
		Figure.block(m, Vector3((-0.045 + 0.030 * i) * s, 0.031, -0.130), Vector3(0.006, 0.004, 0.030), LACE)
	Figure.block(m, Vector3(0.0, -0.002, 0.040), Vector3(0.075, 0.055, 0.050), LEATHER_DARK)  # the wrist band
	return m.build()


## Put a model on a controller node; returns the mesh instance.
static func attach(ctrl: Node3D, mesh: Mesh) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = MeshMerger.vertex_color_material()
	inst.name = "HandModel"
	ctrl.add_child(inst)
	return inst
