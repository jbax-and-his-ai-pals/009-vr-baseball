class_name People
extends RefCounted
## Static cartoon people, each baked into ONE mesh (one draw call). Joints are written as points
## and joined with capsules, so adding a fielder or a runner is a matter of listing joints.
## All figures face +Z (toward the pitcher) in their own frame; callers place and rotate them.

const SKIN := Color(0.96, 0.78, 0.62)
const NAVY := Color(0.12, 0.17, 0.50)
const GRAY := Color(0.55, 0.57, 0.62)
const SHOE := Color(0.10, 0.10, 0.12)


## The catcher in a crouch with his mitt out as the target.
static func catcher(parent: Node, at: Vector3) -> MeshInstance3D:
	var m := MeshMerger.new()
	for s in [-1.0, 1.0]:
		var hip := Vector3(s * 0.17, 0.50, -0.02)
		var knee := Vector3(s * 0.30, 0.54, 0.30)
		var ankle := Vector3(s * 0.26, 0.09, 0.10)
		Figure.limb(m, hip, knee, 0.105, GRAY)                       # thigh
		Figure.limb(m, knee, ankle, 0.095, NAVY)                     # shin guard
		Figure.ball(m, knee, 0.115, NAVY)                            # knee pad
		Figure.block(m, ankle + Vector3(0.0, -0.04, 0.07), Vector3(0.13, 0.08, 0.30), SHOE)
	Figure.limb(m, Vector3(0.0, 0.52, -0.02), Vector3(0.0, 0.66, -0.04), 0.20, GRAY)              # seat
	Figure.limb(m, Vector3(0.0, 0.74, -0.04), Vector3(0.0, 1.06, 0.10), 0.225, NAVY)              # chest protector
	Figure.block(m, Vector3(0.0, 0.90, 0.20), Vector3(0.30, 0.34, 0.06), Color(0.85, 0.85, 0.9)) # protector plate
	var head := Vector3(0.0, 1.33, 0.13)
	Figure.ball(m, head, 0.155, SKIN)
	Figure.ball(m, head + Vector3(0.0, 0.01, 0.08), 0.185, Color(0.16, 0.16, 0.20), Vector3(1.0, 1.0, 0.7))  # mask
	Figure.ball(m, head + Vector3(0.0, 0.07, -0.02), 0.175, NAVY, Vector3(1.0, 0.8, 1.0))                    # helmet
	Figure.limb(m, Vector3(0.22, 1.00, 0.06), Vector3(0.17, 0.64, -0.08), 0.065, NAVY)                      # throwing arm, back
	var shoulder := Vector3(-0.23, 1.00, 0.08)
	var elbow := Vector3(-0.26, 0.86, 0.34)
	var mitt := Vector3(-0.05, 0.85, 0.52)
	Figure.limb(m, shoulder, elbow, 0.065, NAVY)
	Figure.limb(m, elbow, mitt - Vector3(0.0, 0.0, 0.08), 0.058, SKIN)
	Figure.ball(m, mitt + Vector3(0.0, 0.0, 0.06), 0.17, Color(0.50, 0.30, 0.13), Vector3(1.0, 1.0, 0.55))   # mitt
	Figure.ball(m, mitt + Vector3(0.0, 0.0, 0.10), 0.075, Color(0.38, 0.22, 0.09), Vector3(1.0, 1.0, 0.5))   # pocket
	return m.build_instance(parent, at)


## The plate umpire standing behind the catcher, leaning in to see the pitch.
static func umpire(parent: Node, at: Vector3) -> MeshInstance3D:
	var m := MeshMerger.new()
	for s in [-1.0, 1.0]:
		var hip := Vector3(s * 0.13, 0.90, 0.0)
		var knee := Vector3(s * 0.16, 0.50, 0.08)
		var ankle := Vector3(s * 0.20, 0.08, 0.02)
		Figure.limb(m, hip, knee, 0.095, GRAY)
		Figure.limb(m, knee, ankle, 0.075, GRAY)
		Figure.block(m, ankle + Vector3(0.0, -0.035, 0.06), Vector3(0.12, 0.08, 0.28), SHOE)
	Figure.limb(m, Vector3(0.0, 0.90, 0.0), Vector3(0.0, 1.02, 0.02), 0.18, GRAY)                 # hips
	Figure.limb(m, Vector3(0.0, 1.10, 0.03), Vector3(0.0, 1.42, 0.10), 0.20, Color(0.08, 0.10, 0.14))  # shirt
	Figure.block(m, Vector3(0.0, 1.26, 0.22), Vector3(0.28, 0.30, 0.05), Color(0.20, 0.22, 0.26)) # chest protector
	for s in [-1.0, 1.0]:
		Figure.ball(m, Vector3(s * 0.22, 1.44, 0.08), 0.075, Color(0.08, 0.10, 0.14))
		Figure.limb(m, Vector3(s * 0.22, 1.44, 0.08), Vector3(s * 0.24, 1.10, 0.14), 0.058, Color(0.08, 0.10, 0.14))
		Figure.limb(m, Vector3(s * 0.24, 1.10, 0.14), Vector3(s * 0.20, 0.90, 0.22), 0.050, SKIN)
	var head := Vector3(0.0, 1.66, 0.16)
	Figure.ball(m, head, 0.15, SKIN)
	Figure.ball(m, head + Vector3(0.0, 0.0, 0.07), 0.17, Color(0.14, 0.14, 0.18), Vector3(1.0, 1.0, 0.6))   # mask
	Figure.ball(m, head + Vector3(0.0, 0.07, -0.02), 0.165, Color(0.06, 0.07, 0.10), Vector3(1.0, 0.7, 1.0)) # cap
	return m.build_instance(parent, at)


## A fielder (or, with glove = false and other colors, a baserunner) in an athletic ready stance,
## facing +Z. One mesh, one draw call.
static func fielder(parent: Node, at: Vector3, jersey: Color, pants: Color, cap: Color, glove: bool = true) -> MeshInstance3D:
	var m := MeshMerger.new()
	for s in [-1.0, 1.0]:
		var hip := Vector3(s * 0.14, 0.88, 0.0)
		var knee := Vector3(s * 0.20, 0.50, 0.12)
		var ankle := Vector3(s * 0.26, 0.09, 0.02)
		Figure.limb(m, hip, knee, 0.088, pants)
		Figure.limb(m, knee, ankle + Vector3(0.0, 0.10, 0.0), 0.070, pants)
		Figure.limb(m, ankle + Vector3(0.0, 0.10, 0.0), ankle, 0.058, Color(0.95, 0.95, 0.95))
		Figure.block(m, ankle + Vector3(0.0, -0.035, 0.07), Vector3(0.12, 0.08, 0.28), SHOE)
	Figure.limb(m, Vector3(0.0, 0.86, 0.0), Vector3(0.0, 0.98, 0.04), 0.17, pants)
	Figure.limb(m, Vector3(0.0, 1.05, 0.05), Vector3(0.0, 1.36, 0.16), 0.19, jersey)       # chest, leaning in
	Figure.block(m, Vector3(0.0, 1.18, 0.30), Vector3(0.05, 0.30, 0.03), Color(0.97, 0.97, 0.97))
	var head := Vector3(0.0, 1.58, 0.20)
	Figure.ball(m, head, 0.148, SKIN)
	Figure.ball(m, head + Vector3(0.0, 0.06, -0.01), 0.158, cap, Vector3(1.0, 0.78, 1.0))   # cap
	Figure.block(m, head + Vector3(0.0, 0.035, 0.15), Vector3(0.20, 0.025, 0.14), cap)        # bill
	for z in [-0.06, 0.06]:
		Figure.ball(m, head + Vector3(z, 0.02, 0.13), 0.02, Color(0.08, 0.08, 0.10))
	# Arms hanging forward, ready.
	Figure.limb(m, Vector3(-0.22, 1.30, 0.14), Vector3(-0.27, 1.02, 0.30), 0.058, jersey)
	Figure.limb(m, Vector3(-0.27, 1.02, 0.30), Vector3(-0.16, 0.88, 0.46), 0.052, SKIN)
	Figure.limb(m, Vector3(0.22, 1.30, 0.14), Vector3(0.27, 1.02, 0.30), 0.058, jersey)
	Figure.limb(m, Vector3(0.27, 1.02, 0.30), Vector3(0.16, 0.88, 0.46), 0.052, SKIN)
	if glove:
		Figure.ball(m, Vector3(0.14, 0.86, 0.52), 0.115, Color(0.50, 0.30, 0.13), Vector3(1.0, 1.0, 0.6))
	return m.build_instance(parent, at)
