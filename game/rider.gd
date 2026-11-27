extends Node3D
## Cel-shaded rider and bike built from primitives. Legs follow the pedals
## with two-bone IK, so the pedalling matches the simulated cadence.
## Local axes: +x forward, +y up, +z to the rider's right.

const Materials := preload("res://game/materials.gd")

const OUTLINE := 0.018
const C_FRAME := Color("2bb3a3")
const C_TYRE := Color("26262b")
const C_JERSEY := Color("e2513d")
const C_SHORTS := Color("2a2d3a")
const C_SKIN := Color("f0c09a")
const C_HELMET := Color("f5d547")
const C_SHOE := Color("f4f4f4")
const C_METAL := Color("b8bcc4")

const WHEEL_R := 0.34
const BB := Vector3(0.0, 0.3, 0.0)
const SADDLE := Vector3(-0.2, 0.95, 0.0)
const BARS := Vector3(0.5, 0.98, 0.0)
const CRANK := 0.17
const THIGH := 0.47
const SHIN := 0.47

enum Pose { RIDE, WALK, SIT }

var pose := Pose.RIDE
var crank_angle := 0.0
var wheel_angle := 0.0
var walk_phase := 0.0

var bike: Node3D
var body: Node3D
var _wheels: Array[Node3D] = []
var _crank: Node3D
var _limbs := {}  # name -> MeshInstance3D sized to its bone length
var _torso: MeshInstance3D
var _head: Node3D


func _ready() -> void:
	bike = Node3D.new()
	add_child(bike)
	body = Node3D.new()
	add_child(body)
	_build_bike()
	_build_body()
	_update_body()


# ---------------------------------------------------------------- building

func _mat(c: Color) -> ShaderMaterial:
	return Materials.toon(c, OUTLINE)


func _tube(parent: Node3D, a: Vector3, b: Vector3, r: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = a.distance_to(b)
	m.radial_segments = 8
	m.rings = 1
	mi.mesh = m
	mi.material_override = _mat(c)
	parent.add_child(mi)
	_orient(mi, a, b)
	return mi


## Places a Y-axis cylinder so it spans a to b.
func _orient(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.BACK)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _limb(name: String, length: float, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = length + r * 2.0
	m.radial_segments = 8
	m.rings = 2
	mi.mesh = m
	mi.material_override = _mat(c)
	body.add_child(mi)
	_limbs[name] = mi


func _build_bike() -> void:
	for x in [-0.52, 0.52]:
		var w := Node3D.new()
		w.position = Vector3(x, WHEEL_R, 0)
		bike.add_child(w)
		var tyre := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = WHEEL_R - 0.045
		tm.outer_radius = WHEEL_R
		tm.rings = 24
		tm.ring_segments = 6
		tyre.mesh = tm
		tyre.material_override = _mat(C_TYRE)
		tyre.rotation.x = PI / 2
		w.add_child(tyre)
		for k in 3:
			var a := k * PI / 3.0
			var dir := Vector3(cos(a), sin(a), 0) * (WHEEL_R - 0.05)
			_tube(w, -dir, dir, 0.008, C_METAL)
		_wheels.append(w)
	var rear := Vector3(-0.52, WHEEL_R, 0)
	var front := Vector3(0.52, WHEEL_R, 0)
	var seat_top := Vector3(-0.16, 0.86, 0)
	var head_top := Vector3(0.42, 0.88, 0)
	var head_bot := Vector3(0.46, 0.72, 0)
	_tube(bike, BB, seat_top, 0.022, C_FRAME)
	_tube(bike, seat_top, head_top, 0.02, C_FRAME)
	_tube(bike, BB, head_bot, 0.025, C_FRAME)
	_tube(bike, head_bot, head_top, 0.026, C_FRAME)
	_tube(bike, BB, rear, 0.015, C_FRAME)
	_tube(bike, seat_top, rear, 0.013, C_FRAME)
	_tube(bike, head_bot, front, 0.016, C_METAL)
	_tube(bike, seat_top, SADDLE + Vector3(0, -0.03, 0), 0.012, C_METAL)
	_tube(bike, head_top, BARS, 0.014, C_METAL)
	var bar := _tube(bike, BARS + Vector3(0, 0, -0.2), BARS + Vector3(0, 0, 0.2), 0.014, C_TYRE)
	bar.name = "Bar"
	var saddle := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.26, 0.05, 0.12)
	saddle.mesh = sm
	saddle.material_override = _mat(C_TYRE)
	saddle.position = SADDLE
	bike.add_child(saddle)
	for zx in [[0.12, 0.62], [-0.12, 0.62]]:
		var bottle := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.035
		bm.bottom_radius = 0.035
		bm.height = 0.2
		bm.radial_segments = 8
		bottle.mesh = bm
		bottle.material_override = _mat(Color("4aa3df"))
		bottle.position = BB.lerp(head_bot, 0.45) + Vector3(0, 0.05, 0)
		bottle.rotation.z = -0.9
		bike.add_child(bottle)
		break
	_crank = Node3D.new()
	_crank.position = BB
	bike.add_child(_crank)
	_tube(_crank, Vector3(0, 0, -0.08), Vector3(0, 0, 0.08), 0.02, C_METAL)
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.1
	rm.bottom_radius = 0.1
	rm.height = 0.01
	rm.radial_segments = 16
	ring.mesh = rm
	ring.material_override = _mat(C_METAL)
	ring.rotation.x = PI / 2
	ring.position.z = 0.06
	_crank.add_child(ring)


func _build_body() -> void:
	for side in ["l", "r"]:
		_limb("thigh_" + side, THIGH, 0.06, C_SHORTS)
		_limb("shin_" + side, SHIN, 0.045, C_SKIN)
		_limb("upper_arm_" + side, 0.3, 0.04, C_JERSEY)
		_limb("fore_arm_" + side, 0.28, 0.035, C_SKIN)
		var shoe := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.07, 0.09)
		shoe.mesh = bm
		shoe.material_override = _mat(C_SHOE)
		body.add_child(shoe)
		_limbs["shoe_" + side] = shoe
	_torso = MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.14
	tm.height = 0.62
	_torso.mesh = tm
	_torso.material_override = _mat(C_JERSEY)
	body.add_child(_torso)
	_head = Node3D.new()
	body.add_child(_head)
	var face := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.1
	fm.height = 0.2
	face.mesh = fm
	face.material_override = _mat(C_SKIN)
	_head.add_child(face)
	var helmet := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.125
	hm.height = 0.2
	hm.is_hemisphere = true
	helmet.mesh = hm
	helmet.material_override = _mat(C_HELMET)
	helmet.position = Vector3(-0.01, 0.02, 0)
	helmet.scale = Vector3(1.25, 1.0, 1.0)
	_head.add_child(helmet)


# ---------------------------------------------------------------- animation

## Called every frame. cadence in rpm, speed in m/s as seen on screen.
func animate(delta: float, cadence_rpm: float, ground_speed: float, new_pose: Pose) -> void:
	pose = new_pose
	crank_angle = fmod(crank_angle + cadence_rpm / 60.0 * TAU * delta, TAU)
	wheel_angle = fmod(wheel_angle + ground_speed / WHEEL_R * delta, TAU)
	if pose == Pose.WALK:
		walk_phase = fmod(walk_phase + delta * 5.0, TAU)
	for w in _wheels:
		w.rotation.z = -wheel_angle
	_crank.rotation.z = -crank_angle
	_update_body()


func _pedal(phase: float) -> Vector3:
	var a := -crank_angle + phase
	return BB + Vector3(cos(a), sin(a), 0) * CRANK


## Knee position for a hip and foot in the bike's side plane, knee forward.
func _ik(hip: Vector3, foot: Vector3, l1: float, l2: float, knee_dir := 1.0) -> Vector3:
	var to := Vector2(foot.x - hip.x, foot.y - hip.y)
	var d := clampf(to.length(), 0.05, l1 + l2 - 0.001)
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var dir := to.normalized().rotated(acos(cos_a) * knee_dir)
	return Vector3(hip.x + dir.x * l1, hip.y + dir.y * l1, foot.z)


func _set_limb(name: String, a: Vector3, b: Vector3) -> void:
	_orient(_limbs[name], a, b)


func _update_body() -> void:
	var hip: Vector3
	var shoulder: Vector3
	var hands: Array
	var feet: Array
	var knee_dir := 1.0
	match pose:
		Pose.RIDE:
			body.position = Vector3.ZERO
			bike.rotation = Vector3.ZERO
			bike.position = Vector3.ZERO
			hip = SADDLE + Vector3(-0.02, 0.07, 0)
			shoulder = Vector3(0.22, 1.36, 0)
			hands = [BARS + Vector3(0, 0, -0.18), BARS + Vector3(0, 0, 0.18)]
			feet = [_pedal(PI) + Vector3(0, 0, -0.12), _pedal(0.0) + Vector3(0, 0, 0.12)]
		Pose.WALK:
			# Pushing the bike, walking on its left.
			body.position = Vector3(0.05, 0, -0.5)
			bike.position = Vector3.ZERO
			bike.rotation = Vector3.ZERO
			hip = Vector3(0, 0.93, 0)
			shoulder = Vector3(0.08, 1.45, 0)
			hands = [BARS + Vector3(-0.05, 0, -0.2), BARS + Vector3(-0.05, 0, -0.2)]
			var s := sin(walk_phase) * 0.28
			feet = [Vector3(s, 0.04 + max(0.0, cos(walk_phase)) * 0.08, -0.09),
				Vector3(-s, 0.04 + max(0.0, -cos(walk_phase)) * 0.08, 0.09)]
		Pose.SIT:
			# Sitting in the grass next to the bike, which lies on its side.
			body.position = Vector3(0.3, 0, -1.1)
			bike.position = Vector3(0, 0.04, 0.2)
			bike.rotation = Vector3(-PI / 2 + 0.05, 0, 0)
			hip = Vector3(0, 0.14, 0)
			shoulder = Vector3(-0.15, 0.68, 0)
			hands = [Vector3(-0.38, 0.06, -0.18), Vector3(-0.38, 0.06, 0.18)]
			feet = [Vector3(0.82, 0.05, -0.12), Vector3(0.72, 0.18, 0.12)]
			knee_dir = 1.0
	var sides := ["l", "r"]
	for i in 2:
		var side: String = sides[i]
		var h := hip + Vector3(0, 0, -0.1 if i == 0 else 0.1)
		var f: Vector3 = feet[i] - body.position if pose == Pose.RIDE else feet[i]
		f.z = h.z
		var knee := _ik(h, f, THIGH, SHIN, knee_dir)
		_set_limb("thigh_" + side, h, knee)
		_set_limb("shin_" + side, knee, f)
		var shoe: Node3D = _limbs["shoe_" + side]
		shoe.position = f + Vector3(0.03, -0.02, 0)
		var sh := shoulder + Vector3(0, 0, -0.17 if i == 0 else 0.17)
		var hand: Vector3 = hands[i] - body.position
		if pose == Pose.SIT:
			hand = hands[i]
		var elbow := _ik(sh, hand, 0.3, 0.28, -1.0)
		elbow.z = lerpf(sh.z, hand.z, 0.5)
		_set_limb("upper_arm_" + side, sh, elbow)
		_set_limb("fore_arm_" + side, elbow, hand)
	_orient(_torso, hip, shoulder)
	var neck_dir := (shoulder - hip).normalized()
	_head.position = shoulder + neck_dir * 0.08 + Vector3(0.1 if pose == Pose.RIDE else 0.02, 0.1, 0)
