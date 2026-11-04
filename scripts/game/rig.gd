extends RefCounted
## A stickman's body: procedural animation driven by what the fighter is doing, two-bone IK for
## knees and elbows, and a verlet ragdoll for knockdowns and deaths.
##
## Every frame the rig places the hip, neck, head, hands and feet from the fighter's state
## (a walk cycle whose planted foot never slides, a leaning torso, guard / punch / aim / swing
## arm targets), then solves knees and elbows so every bone keeps its length. Positions are
## first worked out in "local" space — origin on the ground under the fighter, +x the way they
## face, +y down — and then mirrored into the world.

const Weapons := preload("res://scripts/game/weapons.gd")

const HEAD_R := 7.5
const NECK := 3.0
const TORSO := 25.0
const UPPER := 14.0
const FORE := 14.0
const THIGH := 21.0
const SHIN := 21.0
const STAND_HIP := 39.5
const CROUCH_HIP := 25.0
const ARM := UPPER + FORE
const LEG := THIGH + SHIN
const RUN_SPEED := 300.0

const JOINTS := ["hip", "neck", "head", "elbow_n", "hand_n", "elbow_f", "hand_f", "knee_n", "foot_n", "knee_f", "foot_f"]
## [a, b, length]. "n" is the limb nearer the camera, "f" the far one.
const BONES := [
	["hip", "neck", TORSO], ["neck", "head", NECK + HEAD_R],
	["neck", "elbow_n", UPPER], ["elbow_n", "hand_n", FORE], ["neck", "elbow_f", UPPER], ["elbow_f", "hand_f", FORE],
	["hip", "knee_n", THIGH], ["knee_n", "foot_n", SHIN], ["hip", "knee_f", THIGH], ["knee_f", "foot_f", SHIN],
]

## World-space joint positions, read by the renderer and by hit detection.
var j := {}
## Recent sword-tip positions (world) for the slash trail.
var trail: Array = []
## Grip position and angle of the held weapon (world), for drawing and for muzzle maths.
var grip := Vector2.ZERO
var grip_angle := 0.0
var grip_flip := false
var ragdoll: Ragdoll = null

var _phase := 0.0
var _speed_k := 0.0
var _lean := 0.1
var _hip_h := STAND_HIP
var _crouch_k := 0.0
var _land := 0.0
var _was_ground := true
var _air_feet := [Vector2(6, -2), Vector2(-6, -2)]
var _hands := [Vector2(12, -60), Vector2(6, -56)]
var _time := 0.0
var _blend_from := {}
var _blend := 0.0
var _hurt := 0.0
var _tilt := 0.0


# --- Maths helpers ---------------------------------------------------------------------------

static func ease_out(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k)


static func smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## The middle joint of a two-bone chain from `a` reaching for `t`. `bend` +1 puts the joint on
## the clockwise side of a→t (elbows: below a forward-reaching arm), -1 on the other side
## (knees: in front of a leg reaching down). Unreachable targets straighten the chain.
static func ik(a: Vector2, t: Vector2, l1: float, l2: float, bend: float) -> Vector2:
	var d := t - a
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var dir := d.normalized() if d.length_squared() > 0.0001 else Vector2.DOWN
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	return a + dir.rotated(acos(cos_a) * bend) * l1


## Moves `t` towards `a` until it is within `reach`.
static func limit(a: Vector2, t: Vector2, reach: float) -> Vector2:
	var d := t - a
	return a + d.limit_length(reach)


func to_world(owner_pos: Vector2, facing: int, p: Vector2) -> Vector2:
	return owner_pos + Vector2(p.x * facing, p.y)


func to_local(owner_pos: Vector2, facing: int, p: Vector2) -> Vector2:
	var d := p - owner_pos
	return Vector2(d.x * facing, d.y)


# --- Animation -------------------------------------------------------------------------------

## Poses the body for fighter `f` (stickman.gd) after it moved by `dt` seconds.
func update(f: RefCounted, dt: float) -> void:
	_time += dt
	if ragdoll:
		j = ragdoll.p.duplicate()
		return
	var facing: int = f.facing
	var vel: Vector2 = f.vel
	var ground: bool = f.on_ground
	var local_vx: float = vel.x * facing
	var speed := absf(vel.x)
	_speed_k = lerpf(_speed_k, clampf(speed / RUN_SPEED, 0.0, 1.25), 1.0 - exp(-14.0 * dt))
	var run_k := clampf(_speed_k, 0.0, 1.0)
	_crouch_k = move_toward(_crouch_k, 1.0 if f.crouching else 0.0, dt * 9.0)
	_hurt = maxf(0.0, _hurt - dt * 4.0)
	if f.hurt_t > 0.0:
		_hurt = maxf(_hurt, f.hurt_t / 0.25)
	if ground and not _was_ground:
		_land = clampf(f.land_speed / 900.0, 0.25, 1.0)
	_was_ground = ground
	_land = maxf(0.0, _land - dt * 6.0)

	# Gait: the cycle advances with distance travelled, so feet never skate.
	var stride := lerpf(58.0, 96.0, run_k)
	var duty := lerpf(0.6, 0.4, run_k)
	if ground:
		_phase = fposmod(_phase + local_vx * dt / stride, 1.0)
	var moving_k := smoothstep(0.03, 0.25, _speed_k) if ground else 0.0

	# Hip height and lean.
	# A loose fighting stance when standing still: feet apart, knees a little soft.
	var ready_k := (1.0 - moving_k) * (1.0 - _crouch_k) if ground else 0.0
	var hip_h := lerpf(STAND_HIP, CROUCH_HIP, _crouch_k) - run_k * 2.5 - _land * 9.0 - ready_k * 2.0
	var breathe := sin(_time * 2.6) * 0.6 * (1.0 - moving_k)
	var lean_target := 0.06 + run_k * 0.2 * signf(local_vx) * moving_k + _crouch_k * 0.35 - _hurt * 0.45
	if not ground:
		lean_target = 0.04 + clampf(vel.y / 2500.0, -0.12, 0.2) + clampf(local_vx / 2000.0, -0.1, 0.15)
	var attack := _attack_pose(f)
	lean_target += attack.lean
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-12.0 * dt))
	var hip_dx: float = attack.dx - _hurt * 3.0

	# Feet.
	var feet: Array = [Vector2.ZERO, Vector2.ZERO]
	var spread := lerpf(lerpf(5.5, 8.5, ready_k), 9.0, _crouch_k)
	if ground:
		for i in 2:
			var stand := Vector2(hip_dx + (spread if i == 0 else -spread), 0.0)
			var p := fposmod(_phase + (0.0 if i == 0 else 0.5), 1.0)
			var walk: Vector2
			var half := duty * stride * 0.5
			if p < duty:
				walk = Vector2(hip_dx + lerpf(half, -half, p / duty), 0.0)
			else:
				var t := (p - duty) / (1.0 - duty)
				var lift := lerpf(6.0, 12.0, run_k) * sin(PI * t) + run_k * 5.0 * sin(PI * minf(t * 1.6, 1.0)) * (1.0 - t)
				walk = Vector2(hip_dx + lerpf(-half, half, smooth(t)), -lift)
			feet[i] = stand.lerp(walk, moving_k)
		_air_feet = [feet[0], feet[1]]
		# Keep the hip low enough for planted feet to reach the ground.
		for i in 2:
			if feet[i].y > -0.5:
				var dx: float = feet[i].x - hip_dx
				hip_h = minf(hip_h, sqrt(maxf(0.0, (LEG * 0.985) * (LEG * 0.985) - dx * dx)))
		if moving_k > 0.0:
			var bob := lerpf(1.2, -2.0, run_k) * cos(TAU * 2.0 * (_phase - duty * 0.5))
			hip_h += bob * moving_k
	else:
		hip_h = STAND_HIP - 1.0
		var rising: bool = vel.y < -80.0
		var tuck := clampf(-vel.y / 800.0, 0.0, 1.0)
		var targets := [
			Vector2(hip_dx + 9.0 + tuck * 3.0, -hip_h + (24.0 if rising else 36.0) - tuck * 2.0),
			Vector2(hip_dx - 7.0, -hip_h + (33.0 if rising else 38.0)),
		]
		for i in 2:
			_air_feet[i] = (_air_feet[i] as Vector2).lerp(targets[i], 1.0 - exp(-16.0 * dt))
		feet = [_air_feet[0], _air_feet[1]]
	hip_h += breathe * 0.3
	_hip_h = hip_h

	var hip := Vector2(hip_dx, -hip_h)
	var torso_dir := Vector2(sin(_lean), -cos(_lean))
	var neck := hip + torso_dir * TORSO + Vector2(0, breathe * 0.4)
	var aim: Vector2 = f.aim_local()
	_tilt = lerpf(_tilt, clampf(aim.y, -0.6, 0.6) * 0.5 - _hurt * 0.5, 1.0 - exp(-10.0 * dt))
	var head := neck + Vector2(sin(_lean * 0.5 + _tilt * 0.6), -cos(_lean * 0.5 + _tilt * 0.6)) * (NECK + HEAD_R)
	var shoulder := neck

	# Arms.
	var hands := _arm_targets(f, attack, shoulder, run_k, moving_k, ground, dt)
	var pos: Vector2 = f.pos
	var out := {}
	out.hip = hip
	out.neck = neck
	out.head = head
	out.hand_n = limit(shoulder, hands[0], ARM - 0.05)
	out.hand_f = limit(shoulder, hands[1], ARM - 0.05)
	out.elbow_n = ik(shoulder, out.hand_n, UPPER, FORE, 1.0)
	out.elbow_f = ik(shoulder, out.hand_f, UPPER, FORE, 1.0)
	out.foot_n = limit(hip, feet[0], LEG - 0.05)
	out.foot_f = limit(hip, feet[1], LEG - 0.05)
	out.knee_n = ik(hip, out.foot_n, THIGH, SHIN, -1.0)
	out.knee_f = ik(hip, out.foot_f, THIGH, SHIN, -1.0)
	out["shoulder"] = shoulder

	# Getting up out of a ragdoll: slide the end points from where the body lay.
	if _blend > 0.0:
		_blend = maxf(0.0, _blend - dt / 0.45)
		var k := smooth(_blend)
		for key in ["hip", "neck", "head", "hand_n", "hand_f", "foot_n", "foot_f"]:
			if _blend_from.has(key):
				out[key] = (out[key] as Vector2).lerp(_blend_from[key], k)
		out.elbow_n = ik(out.neck, out.hand_n, UPPER, FORE, 1.0)
		out.elbow_f = ik(out.neck, out.hand_f, UPPER, FORE, 1.0)
		out.knee_n = ik(out.hip, out.foot_n, THIGH, SHIN, -1.0)
		out.knee_f = ik(out.hip, out.foot_f, THIGH, SHIN, -1.0)

	j = {}
	for key: String in out:
		j[key] = to_world(pos, facing, out[key])
	_update_grip(f, shoulder, out, pos, facing)


## Extra lean and hip shift for the current attack: {"lean", "dx"}.
func _attack_pose(f: RefCounted) -> Dictionary:
	var kind: String = f.attack_kind
	if kind == "" or f.attack_t < 0.0:
		return {"lean": 0.0, "dx": 0.0}
	var t: float = f.attack_progress()
	match kind:
		"punch":
			var ext := _punch_ext(t)
			var heavy: bool = f.combo_step == 2
			return {"lean": ext * (0.3 if heavy else 0.16), "dx": ext * (6.0 if heavy else 3.0)}
		"sword":
			var k := sin(PI * clampf(t * 1.4, 0.0, 1.0))
			return {"lean": k * 0.22, "dx": k * 5.0}
		"throw", "grenade":
			var k := clampf((t - 0.25) / 0.3, 0.0, 1.0)
			return {"lean": -0.15 * (1.0 - k) + 0.2 * sin(PI * k), "dx": 3.0 * k}
		"fire":
			return {"lean": -0.06 * (1.0 - t), "dx": -2.0 * (1.0 - t)}
	return {"lean": 0.0, "dx": 0.0}


## Punch extension 0..1 over the punch's progress: fast out, short hold, eased back.
static func _punch_ext(t: float) -> float:
	if t < 0.3:
		return ease_out(t / 0.3)
	if t < 0.45:
		return 1.0
	return 1.0 - smooth((t - 0.45) / 0.55)


## Where the near and far hands want to be (local space).
func _arm_targets(f: RefCounted, attack: Dictionary, shoulder: Vector2, run_k: float, moving_k: float,
		ground: bool, dt: float) -> Array:
	var weapon: String = f.weapon
	var aim: Vector2 = f.aim_local()
	var kind: String = f.attack_kind
	var t: float = f.attack_progress()
	var hands: Array
	var snap := false
	if weapon in ["pistol", "shotgun", "crossbow"]:
		# Arms follow the gun; the gun follows the aim.
		var d: Dictionary = Weapons.def(weapon)
		var reach: float = d.reach
		var recoil: float = f.recoil
		var g := shoulder + aim * ARM * reach - aim * recoil * float(d.recoil)
		g += Vector2(0, 2.5 + sin(TAU * _phase * 2.0) * 1.2 * moving_k)
		hands = [g, g]
		snap = true
	elif weapon == "sword":
		if kind == "sword" and t >= 0.0 and t <= 1.0:
			var a := _sword_arm_angle(t, f.combo_step % 2 == 1)
			hands = [shoulder + Vector2.from_angle(a) * ARM * 0.95, shoulder + Vector2(-9, 15)]
			snap = true
		else:
			hands = [shoulder + Vector2(9, 12) + Vector2(0, sin(TAU * _phase * 2.0) * 1.5 * moving_k), shoulder + Vector2(-8, 16)]
	elif (kind == "grenade" or kind == "throw") and t >= 0.0:
		var hold := shoulder + Vector2(-15, -12)
		var release := shoulder + aim * ARM * 0.98
		var after := shoulder + Vector2(14, 18)
		var hn: Vector2
		if t < 0.3:
			hn = (shoulder + Vector2(6, 14)).lerp(hold, ease_out(t / 0.3))
		elif t < 0.5:
			hn = hold.lerp(release, smooth((t - 0.3) / 0.2))
		else:
			hn = release.lerp(after, smooth((t - 0.5) / 0.5))
		hands = [hn, shoulder + Vector2(10, 6)]
		snap = true
	elif weapon == "grenade":
		hands = [shoulder + Vector2(5, 22), shoulder + Vector2(10, 4)]
	else:
		# Fists: a loose guard that turns into pumping arms at speed.
		var guard_n := shoulder + Vector2(15, -3)
		var guard_f := shoulder + Vector2(9, 1)
		var swing := cos(TAU * _phase) * 0.85 * run_k
		var pump_n := shoulder + _arm_fk(-swing, 1.45)
		var pump_f := shoulder + _arm_fk(swing, 1.45)
		var guard_k := 1.0 - moving_k * clampf(run_k * 1.4, 0.0, 1.0)
		hands = [pump_n.lerp(guard_n, guard_k), pump_f.lerp(guard_f, guard_k)]
		if not ground:
			var up := clampf(f.vel.y / 700.0, -1.0, 1.0)
			hands = [shoulder + Vector2(12, -2 - 8 * up), shoulder + Vector2(-10, 4 - 10 * up)]
		if kind == "punch" and t >= 0.0:
			var ext := _punch_ext(t)
			var heavy: bool = f.combo_step == 2
			var use_far: bool = f.combo_step == 1
			var target := shoulder + aim * ARM + Vector2(2, -1)
			if heavy:
				# A rising hook: starts low and drives up through the target.
				target = shoulder + (aim * ARM).rotated(-0.25) + Vector2(3, -3)
			var idx := 1 if use_far else 0
			hands[idx] = (guard_f if use_far else guard_n).lerp(target, ext)
			snap = true
		if _hurt > 0.0:
			hands[0] = (hands[0] as Vector2).lerp(shoulder + Vector2(-6, -14), _hurt * 0.7)
			hands[1] = (hands[1] as Vector2).lerp(shoulder + Vector2(-14, -4), _hurt * 0.7)
	if snap:
		_hands = [hands[0], hands[1]]
	else:
		var k := 1.0 - exp(-26.0 * dt)
		_hands = [(_hands[0] as Vector2).lerp(hands[0], k), (_hands[1] as Vector2).lerp(hands[1], k)]
	return _hands


## Hand offset from the shoulder for an upper arm swung `u` forward from hanging straight down
## and an elbow bent `bend` further forward.
static func _arm_fk(u: float, bend: float) -> Vector2:
	return Vector2(sin(u), cos(u)) * UPPER + Vector2(sin(u + bend), cos(u + bend)) * FORE


## Arm angle (local, 0 = straight ahead, negative = up) during a sword swing. Odd swings come
## back up from below.
static func _sword_arm_angle(t: float, upward: bool) -> float:
	var from := -2.3
	var to := 0.95
	if upward:
		from = 1.0
		to = -1.7
	if t < 0.18:
		return lerpf(from * 0.7, from, ease_out(t / 0.18))
	if t < 0.45:
		return lerpf(from, to, smooth((t - 0.18) / 0.27))
	return lerpf(to, to * 0.4 + 0.5, smooth((t - 0.45) / 0.55))


## Works out the held weapon's grip point and angle (world) from the posed hands.
func _update_grip(f: RefCounted, shoulder: Vector2, out: Dictionary, pos: Vector2, facing: int) -> void:
	var weapon: String = f.weapon
	var aim: Vector2 = f.aim_local()
	var local_angle := aim.angle()
	var hand: Vector2 = out.hand_n
	if weapon in ["pistol", "shotgun", "crossbow"]:
		local_angle -= f.recoil * float(Weapons.def(weapon).kick)
	elif weapon == "sword":
		var t: float = f.attack_progress()
		if f.attack_kind == "sword" and t >= 0.0 and t <= 1.0:
			local_angle = (hand - shoulder).angle() + 0.15
		else:
			local_angle = -1.15
	elif weapon == "grenade":
		local_angle = -0.4
	grip = to_world(pos, facing, hand)
	grip_flip = facing < 0
	grip_angle = local_angle if facing > 0 else PI - local_angle
	if weapon in ["pistol", "shotgun", "crossbow"]:
		# The supporting hand moves to the foregrip.
		var fg: Vector2 = Weapons.def(weapon).fore
		var fore_local := limit(shoulder, hand + fg.rotated(local_angle), ARM - 0.05)
		j.hand_f = to_world(pos, facing, fore_local)
		j.elbow_f = to_world(pos, facing, ik(shoulder, fore_local, UPPER, FORE, 1.0))
	if weapon == "sword":
		var tip := grip + Vector2.from_angle(grip_angle) * 40.0
		trail.push_front(tip)
		if trail.size() > 7:
			trail.pop_back()
	elif not trail.is_empty():
		trail.clear()


func head_pos() -> Vector2:
	return j.get("head", Vector2.ZERO)


## Starts the get-up blend from the ragdoll's current shape and drops the ragdoll.
func end_ragdoll(owner_pos: Vector2, facing: int) -> void:
	if ragdoll == null:
		return
	_blend_from = {}
	for key: String in ragdoll.p:
		_blend_from[key] = to_local(owner_pos, facing, ragdoll.p[key])
	_blend = 1.0
	_land = 0.0
	ragdoll = null


func start_ragdoll(vel: Vector2) -> Ragdoll:
	ragdoll = Ragdoll.new()
	ragdoll.setup(j, vel)
	return ragdoll


# --- Ragdoll ---------------------------------------------------------------------------------

## Verlet particles at the joints held together by stick constraints. The world collides the
## particles with the level; the constraints keep the bones their length and stop knees and
## elbows folding through themselves.
class Ragdoll:
	const DT := 1.0 / 120.0
	var p := {}
	var o := {}
	var links: Array = []
	var age := 0.0
	var still := 0.0
	var grounded := 0

	func setup(joints: Dictionary, vel: Vector2) -> void:
		for key: String in JOINTS:
			var at: Vector2 = joints.get(key, joints.get("hip", Vector2.ZERO))
			p[key] = at
			o[key] = at - vel * DT
		for b: Array in BONES:
			links.append([b[0], b[1], b[2], 1.0])
		# Soft braces: head stays roughly over the torso, limbs can't fold flat.
		links.append(["hip", "head", TORSO + NECK + HEAD_R - 1.0, 0.25])
		links.append(["neck", "hand_n", ARM * 0.35, -0.5])
		links.append(["neck", "hand_f", ARM * 0.35, -0.5])
		links.append(["hip", "foot_n", LEG * 0.45, -0.5])
		links.append(["hip", "foot_f", LEG * 0.45, -0.5])
		links.append(["knee_n", "knee_f", 3.0, -0.3])

	## Pushes the particles near `at` by `impulse` (px/s), falling off with distance.
	func push(at: Vector2, impulse: Vector2, radius := 40.0) -> void:
		for key: String in p:
			var d: float = (p[key] as Vector2).distance_to(at)
			var k := clampf(1.0 - d / radius, 0.15, 1.0)
			o[key] = (o[key] as Vector2) - impulse * DT * k
		still = 0.0

	func kick(key: String, impulse: Vector2) -> void:
		if o.has(key):
			o[key] = (o[key] as Vector2) - impulse * DT

	func velocity() -> Vector2:
		return ((p.hip as Vector2) - (o.hip as Vector2)) / DT

	func center() -> Vector2:
		return ((p.hip as Vector2) + (p.neck as Vector2)) * 0.5

	func bounds() -> Rect2:
		var r := Rect2(p.hip, Vector2.ZERO)
		for key: String in p:
			r = r.expand(p[key])
		return r.grow(3.0)
