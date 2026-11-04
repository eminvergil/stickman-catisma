extends RefCounted
## One round of the fight, stepped at a fixed 120 Hz: the level, the fighters, crates and
## barrels, weapons lying around, shots in flight, explosions and the effects they leave.
##
## The world knows nothing about screens or devices. Each `step` takes one input Dictionary per
## fighter id; what the player should hear or see happen is queued in `events`.

const Stickman := preload("res://scripts/game/stickman.gd")
const Rig := preload("res://scripts/game/rig.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const Levels := preload("res://scripts/game/levels.gd")
const Nav := preload("res://scripts/game/nav.gd")

const DT := 1.0 / 120.0
const GRAVITY := 2300.0
const KILL_Y := 790.0
const COUNTDOWN := 1.8
const SUDDEN_DEATH := 75.0
const ROUND_END := 2.4
const CRATE := Vector2(38, 38)
const BARREL := Vector2(30, 44)
const CRATE_HP := 24.0
const PICKUP_LIFE := 22.0
const MAX_PARTICLES := 900


class Prop:
	var kind := "crate"
	var rect := Rect2()
	var vel := Vector2.ZERO
	var hp := 24.0
	var fuse := -1.0
	var lit_by := -1
	var shake := 0.0
	var on_ground := false
	var dead := false
	## Sudden-death barrels fall from the sky and blow up where they land.
	var sky := false
	var look := 0

	func center() -> Vector2:
		return rect.get_center()


class Pickup:
	var type := ""
	var ammo := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var angle := 0.0
	var spin := 0.0
	var on_ground := false
	var age := 0.0
	var thrown_by := -1
	## While > 0 a thrown weapon hurts whoever it hits.
	var danger := 0.0
	var dead := false

	func usable() -> bool:
		return not dead and danger <= 0.0 and (ammo > 0 or type == "sword")


class Shot:
	var kind := "bullet"  # bullet, pellet, bolt, grenade
	var weapon := ""
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var start := Vector2.ZERO
	var vel := Vector2.ZERO
	var owner := -1
	var damage := 0.0
	var knock := 0.0
	var prop_damage := 0.0
	var life := 1.0
	var gravity := 0.0
	var fuse := 0.0
	var angle := 0.0
	var spin := 0.0
	var age := 0.0
	var dead := false
	var deflected := false


class Particle:
	var kind := ""
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 1.0
	var max_life := 1.0
	var size := 2.0
	var color := Color.WHITE
	var angle := 0.0
	var spin := 0.0
	var gravity := 0.0
	var drag := 0.0
	var collide := false


var level_id := ""
var solids: Array[Rect2] = []
var oneways: Array[Rect2] = []
var fighters: Array = []
var props: Array = []
var pickups: Array = []
var shots: Array = []
var particles: Array = []
## {"kind": "scorch"|"bolt"|"blood", "pos", "angle", "size", "life", "color"}
var decals: Array = []
## Explosion fireballs: {"pos", "t", "radius"}
var blasts: Array = []
var events: Array = []
var nav: Nav
var time := 0.0
var state := "countdown"
var state_t := 0.0
var winner := -1
var finished := false
var sudden := false
var rng := RandomNumberGenerator.new()
var max_crates := 6
var blood := true
var sudden_death := true
## Per fighter id: {"kills", "damage", "crates", "barrels", "headshots", "deflects"}
var stats := {}
var _drop_timer := 6.0
var _sky_timer := 0.0
var _ids := {}


## `players` is [{"id", "color"}...] in spawn order.
func setup(level: String, players: Array, seed_value := -1) -> void:
	level_id = level
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var lv := Levels.get_level(level)
	solids = Levels.solids(level)
	oneways = Levels.oneways(level)
	max_crates = lv.max_crates
	for c: Array in lv.crates:
		add_prop("crate", Vector2(c[0], c[1]))
	for b: Array in lv.barrels:
		add_prop("barrel", Vector2(b[0], b[1]))
	var spawns: Array = lv.spawns.duplicate()
	for i in players.size():
		var info: Dictionary = players[i]
		var s: Array = spawns[i % spawns.size()]
		var f := Stickman.new()
		f.setup(info.id, Vector2(s[0], s[1]), info.color)
		fighters.append(f)
		_ids[f.id] = f
		stats[f.id] = {"kills": 0, "damage": 0.0, "crates": 0, "barrels": 0, "headshots": 0, "deflects": 0}
	nav = Nav.new()
	nav.build(self)


func fighter(fid: int) -> Stickman:
	return _ids.get(fid)


func add_prop(kind: String, bottom_center: Vector2) -> Prop:
	var p := Prop.new()
	p.kind = kind
	var size := CRATE if kind == "crate" else BARREL
	p.rect = Rect2(bottom_center - Vector2(size.x * 0.5, size.y), size)
	p.hp = CRATE_HP
	p.look = rng.randi() % 4
	props.append(p)
	return p


func can_act() -> bool:
	return state == "fight"


func alive_fighters() -> Array:
	return fighters.filter(func(f: Stickman) -> bool: return f.alive)


# --- Stepping --------------------------------------------------------------------------------

func step(inputs: Dictionary) -> void:
	time += DT
	state_t += DT
	if state == "countdown" and state_t >= COUNTDOWN:
		state = "fight"
		state_t = 0.0
		events.append({"type": "go"})
	for f: Stickman in fighters:
		f.tick_knock = Vector2.ZERO
		f.update(self, inputs.get(f.id, {}), DT)
	_update_shots()
	_update_props()
	_update_pickups()
	_update_ragdolls()
	for f: Stickman in fighters:
		if f.alive and not f.is_down() and f.tick_knock.length() >= Stickman.KNOCKDOWN:
			f.knock_down(f.tick_knock)
		if f.alive and f.pos.y > KILL_Y:
			_fell(f)
	_update_particles()
	_update_blasts()
	if state == "fight":
		_supply_drops()
		_sudden_death()
	_check_round()


func _check_round() -> void:
	if state == "fight":
		var alive := alive_fighters()
		if alive.size() <= 1:
			state = "over"
			state_t = 0.0
			winner = alive[0].id if alive.size() == 1 else -1
			events.append({"type": "round_over", "winner": winner})
	elif state == "over":
		if winner >= 0 and not fighter(winner).alive:
			winner = -1
			events.append({"type": "round_over", "winner": -1})
		if state_t >= ROUND_END:
			finished = true


# --- Collision -------------------------------------------------------------------------------

## Moves `box` by `motion`, X then Y, stopping at solids, props (except `skip`) and — when
## falling and not dropping through — the tops of one-way platforms. Obstacles the box already
## overlapped are ignored so nothing gets flung through them.
func sweep(box: Rect2, motion: Vector2, drop := false, skip: Prop = null) -> Dictionary:
	var res := {"ground": false, "oneway": false, "wall": false, "ceil": false}
	var blockers: Array[Rect2] = solids.duplicate()
	for p: Prop in props:
		if not p.dead and p != skip:
			blockers.append(p.rect)
	var inside := {}
	for i in blockers.size():
		if box.intersects(blockers[i]):
			inside[i] = true
	if motion.x != 0.0:
		box.position.x += motion.x
		for i in blockers.size():
			var r := blockers[i]
			if inside.has(i) or not box.intersects(r):
				continue
			if motion.x > 0.0:
				box.position.x = r.position.x - box.size.x
			else:
				box.position.x = r.end.x
			res.wall = true
	if motion.y != 0.0:
		var prev_bottom := box.end.y
		box.position.y += motion.y
		for i in blockers.size():
			var r := blockers[i]
			if inside.has(i) or not box.intersects(r):
				continue
			if motion.y > 0.0:
				box.position.y = r.position.y - box.size.y
				res.ground = true
			else:
				box.position.y = r.end.y
				res.ceil = true
		if motion.y > 0.0 and not drop:
			for r in oneways:
				if prev_bottom <= r.position.y + 0.5 and box.end.y >= r.position.y \
						and box.position.x < r.end.x and box.end.x > r.position.x:
					box.position.y = r.position.y - box.size.y
					res.ground = true
					res.oneway = true
	res["box"] = box
	return res


## Pushes `box` out of anything solid it overlaps, along the shortest way out.
func depenetrate(box: Rect2) -> Rect2:
	var blockers: Array[Rect2] = solids.duplicate()
	for p: Prop in props:
		if not p.dead:
			blockers.append(p.rect)
	for r in blockers:
		if not box.intersects(r):
			continue
		var left := box.end.x - r.position.x
		var right := r.end.x - box.position.x
		var up := box.end.y - r.position.y
		var down := r.end.y - box.position.y
		var m := minf(minf(left, right), minf(up, down))
		if m == up:
			box.position.y -= up
		elif m == left:
			box.position.x -= left
		elif m == right:
			box.position.x += right
		else:
			box.position.y += down
	return box


func move_fighter(f: Stickman, dt: float) -> void:
	var h := f.height()
	var box := depenetrate(Rect2(f.pos.x - Stickman.WIDTH * 0.5, f.pos.y - h, Stickman.WIDTH, h))
	var r := sweep(box, f.vel * dt, f.drop_t > 0.0)
	var b: Rect2 = r.box
	f.pos = Vector2(b.get_center().x, b.end.y)
	f.hit_wall = r.wall
	if r.wall:
		f.vel.x = 0.0
	if r.ground and f.vel.y >= 0.0:
		f.vel.y = 0.0
		f.on_ground = true
		f.ground_oneway = r.oneway
	else:
		f.on_ground = false
	if r.ceil and f.vel.y < 0.0:
		f.vel.y = 0.0


func can_stand(f: Stickman) -> bool:
	var box := Rect2(f.pos.x - Stickman.WIDTH * 0.5, f.pos.y - Stickman.HEIGHT, Stickman.WIDTH, Stickman.HEIGHT - 1.0)
	for r in solids:
		if box.intersects(r):
			return false
	for p: Prop in props:
		if not p.dead and box.intersects(p.rect):
			return false
	return true


## Nearest x to `at.x` where a box of `w`×`h` standing on `at` fits.
func free_x(at: Vector2, w: float, h: float) -> float:
	for off in [0.0, 12.0, -12.0, 24.0, -24.0, 36.0, -36.0, 48.0, -48.0]:
		var box := Rect2(at.x + off - w * 0.5, at.y - h, w, h - 1.0)
		var ok := true
		for r in solids:
			if box.intersects(r):
				ok = false
				break
		if ok:
			for p: Prop in props:
				if not p.dead and box.intersects(p.rect):
					ok = false
					break
		if ok:
			return at.x + off
	return at.x


## Height of the first surface under `at` within `max_drop`, or INF.
func ground_below(at: Vector2, max_drop: float) -> float:
	var best := INF
	var all: Array[Rect2] = solids.duplicate()
	all.append_array(oneways)
	for p: Prop in props:
		if not p.dead:
			all.append(p.rect)
	for r in all:
		if at.x >= r.position.x and at.x <= r.end.x and r.position.y >= at.y - 4.0 and r.position.y - at.y <= max_drop:
			best = minf(best, r.position.y)
	return best


## Slab test: where along a→b (0..1) the segment enters `r`, or -1. Inside counts as 0.
static func seg_rect(a: Vector2, b: Vector2, r: Rect2) -> float:
	var d := b - a
	var tmin := 0.0
	var tmax := 1.0
	for axis in 2:
		var p0: float = a[axis]
		var dd: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(dd) < 0.000001:
			if p0 < lo or p0 > hi:
				return -1.0
		else:
			var t1 := (lo - p0) / dd
			var t2 := (hi - p0) / dd
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


static func seg_circle(a: Vector2, b: Vector2, c: Vector2, radius: float) -> float:
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	var qc := f.dot(f) - radius * radius
	if qc <= 0.0:
		return 0.0
	if qa < 0.000001:
		return -1.0
	var qb := 2.0 * f.dot(d)
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return -1.0
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## First thing a shot from `a` to `b` touches: {"t", "kind": "wall"|"prop"|"fighter", "obj",
## "head"}, or an empty Dictionary. Fighter `skip` is ignored.
func raycast(a: Vector2, b: Vector2, skip := -1, with_fighters := true, with_props := true) -> Dictionary:
	var best := {}
	var best_t := 2.0
	for r in solids:
		var t := seg_rect(a, b, r)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"t": t, "kind": "wall", "obj": null, "oneway": false}
	for r in oneways:
		var t := seg_rect(a, b, r)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"t": t, "kind": "wall", "obj": null, "oneway": true}
	if with_props:
		for p: Prop in props:
			if p.dead:
				continue
			var t := seg_rect(a, b, p.rect)
			if t >= 0.0 and t < best_t:
				best_t = t
				best = {"t": t, "kind": "prop", "obj": p}
	if with_fighters:
		for f: Stickman in fighters:
			if not f.alive or f.id == skip:
				continue
			var head := false
			var t := -1.0
			if f.is_down():
				t = seg_rect(a, b, f.hurt_rect())
			else:
				var th := seg_circle(a, b, f.rig.head_pos(), Rig.HEAD_R + 1.5)
				var neck: Vector2 = f.rig.j.get("neck", f.pos - Vector2(0, 60))
				var body := Rect2(f.pos.x - 8.0, neck.y - 2.0, 16.0, f.pos.y - neck.y + 2.0)
				var tb := seg_rect(a, b, body)
				if th >= 0.0 and (tb < 0.0 or th <= tb):
					t = th
					head = true
				else:
					t = tb
			if t >= 0.0 and t < best_t:
				best_t = t
				best = {"t": t, "kind": "fighter", "obj": f, "head": head}
	return best


func line_clear(a: Vector2, b: Vector2, with_props := true) -> bool:
	return raycast(a, b, -1, false, with_props).is_empty()


# --- Aiming ----------------------------------------------------------------------------------

## Aim for fighters without a mouse or stick: straight ahead, bent towards a target in front.
## Guns look for an enemy near the line of fire, then for a crate or barrel; fists point the
## punch at whoever or whatever is within reach, so crates on the floor get hit too.
func assist_aim(f: Stickman) -> Vector2:
	var base := Vector2(f.facing, 0)
	if f.weapon == "":
		return _assist_fist(f, base)
	if not f.is_gun():
		return base
	var origin := f.center()
	var best := base
	var best_score := INF
	for o: Stickman in fighters:
		if o == f or not o.alive:
			continue
		var target := o.center()
		var to := target - origin
		if to.x * f.facing <= 0.0 or to.length() > 950.0:
			continue
		var ang := absf(angle_difference(base.angle(), to.angle()))
		if ang > 0.45 or not line_clear(origin, target, false):
			continue
		var score := ang + to.length() / 2000.0
		if score < best_score:
			best_score = score
			best = lead_aim(f.weapon, origin, target)
	if best_score < INF:
		return best
	for p: Prop in props:
		if p.dead:
			continue
		var to := p.center() - origin
		if to.x * f.facing <= 8.0 or to.length() > 460.0:
			continue
		var ang := absf(angle_difference(base.angle(), to.angle()))
		if ang > 0.55:
			continue
		var hit := raycast(origin, p.center(), f.id, false, true)
		if hit.is_empty() or hit.obj != p:
			continue
		var score := ang + to.length() / 1500.0
		if score < best_score:
			best_score = score
			best = lead_aim(f.weapon, origin, p.center())
	return best


func _assist_fist(f: Stickman, base: Vector2) -> Vector2:
	var shoulder: Vector2 = f.rig.j.get("neck", f.pos - Vector2(0, 62))
	var best := base
	var best_d := INF
	var targets: Array = []
	for o: Stickman in fighters:
		if o != f and o.alive:
			targets.append(o.center())
	for p: Prop in props:
		if not p.dead:
			targets.append(p.center())
	for c: Vector2 in targets:
		var d := c - shoulder
		var ahead := d.x * f.facing
		if ahead < -2.0 or ahead > 58.0 or d.y < -50.0 or d.y > 72.0:
			continue
		if d.length() < best_d:
			best_d = d.length()
			best = d.normalized()
	if best_d == INF:
		return base
	var ang := clampf(angle_difference(base.angle(), best.angle()), -1.0, 1.0)
	return base.rotated(ang)


## Direction to fire `weapon` from `from` to hit `to`, lifting crossbow bolts for their drop.
func lead_aim(weapon: String, from: Vector2, to: Vector2) -> Vector2:
	var d := Weapons.def(weapon)
	var g: float = d.get("gravity", 0.0)
	if g > 0.0:
		var dist := absf(to.x - from.x)
		var v: float = d.speed
		to.y -= g * dist * dist / (2.0 * v * v)
	return (to - from).normalized()


# --- Attacks ---------------------------------------------------------------------------------

func sound(name: String, at: Vector2, db := 0.0) -> void:
	events.append({"type": "sound", "name": name, "pos": at, "db": db})


func shake(amount: float) -> void:
	events.append({"type": "shake", "amount": amount})


func fire(f: Stickman) -> void:
	var d := Weapons.def(f.weapon)
	var rig := f.rig
	var dir := f.aim
	var origin := f.center() - Vector2(0, 8)
	var muzzle := Weapons.muzzle(f.weapon, rig.grip, rig.grip_angle, rig.grip_flip)
	var block := raycast(origin, muzzle, f.id, false, true)
	if not block.is_empty():
		muzzle = origin.lerp(muzzle, maxf(0.0, float(block.t) - 0.02))
	var count := int(d.get("pellets", 1))
	for i in count:
		var s := Shot.new()
		s.weapon = f.weapon
		s.kind = "pellet" if count > 1 else ("bolt" if f.weapon == "crossbow" else "bullet")
		var spread: float = d.get("spread", 0.012)
		var ang := dir.angle() + (rng.randf_range(-spread, spread) if count > 1 else rng.randf_range(-spread, spread))
		var speed: float = d.speed * (rng.randf_range(0.85, 1.1) if count > 1 else 1.0)
		s.vel = Vector2.from_angle(ang) * speed
		s.pos = muzzle
		s.prev = muzzle
		s.start = muzzle
		s.owner = f.id
		s.damage = d.damage
		s.knock = d.knock
		s.prop_damage = d.prop
		s.life = d.life
		s.gravity = d.get("gravity", 0.0)
		s.angle = ang
		shots.append(s)
	_spark(muzzle, dir, 5 if count > 1 else 3, Color("#ffd36a"), 300.0)
	_particle("flash", muzzle, Vector2.ZERO, 0.06, 14.0 if count > 1 else 9.0, Color("#fff2b0"), dir.angle())
	if f.weapon != "crossbow":
		var shell := _particle("shell", rig.grip, Vector2(-f.facing * rng.randf_range(80, 160), rng.randf_range(-260, -160)), 1.2, 2.5,
				Color("#d9a63a") if count == 1 else Color("#b8322a"), 0.0)
		shell.gravity = GRAVITY * 0.8
		shell.spin = rng.randf_range(-20, 20)
		shell.collide = true
	if d.has("self_push"):
		f.vel -= dir * float(d.self_push)
		if dir.y > 0.5:
			f.on_ground = false
	sound(d.sound, muzzle)
	shake(5.0 if count > 1 else 1.5)


func punch_hit(f: Stickman, heavy: bool) -> void:
	var data: Dictionary = Weapons.FIST_FINISHER if heavy else Weapons.FIST
	var shoulder: Vector2 = f.rig.j.get("neck", f.pos - Vector2(0, 62))
	var reach := shoulder + f.aim * 26.0
	var zone := Rect2(reach - Vector2(17, 18), Vector2(34, 42))
	var landed := false
	for o: Stickman in fighters:
		if o == f or not o.alive or not zone.intersects(o.hurt_rect()):
			continue
		var knock := Vector2(f.facing * float(data.knock), -float(data.knock) * (0.55 if heavy else 0.2))
		hit_fighter(o, data.damage, knock, f.id, "fist", reach, false)
		landed = true
	for o: Stickman in fighters:
		if not o.alive and o.is_down() and zone.intersects(o.hurt_rect()):
			o.rig.ragdoll.push(reach, Vector2(f.facing * 350.0, -150.0), 40.0)
	for p: Prop in props:
		if not p.dead and zone.intersects(p.rect):
			damage_prop(p, data.prop, f.id, reach)
	if landed:
		sound("punch_h" if heavy else "punch", reach)
		shake(4.0 if heavy else 2.0)


func sword_hit(f: Stickman) -> void:
	var data := Weapons.def("sword")
	var shoulder: Vector2 = f.rig.j.get("neck", f.pos - Vector2(0, 62))
	var zone := Rect2(shoulder + Vector2(f.facing * 28.0 - 36.0, -46.0), Vector2(72, 92))
	for o: Stickman in fighters:
		if o == f or not o.alive or f.hit_set.has(o.id) or not zone.intersects(o.hurt_rect()):
			continue
		f.hit_set[o.id] = true
		var at := o.center()
		hit_fighter(o, data.damage, Vector2(f.facing * float(data.knock), -170.0), f.id, "sword", at, false)
		sound("slice", at)
		shake(4.0)
	for p: Prop in props:
		if p.dead or f.hit_set.has(p) or not zone.intersects(p.rect):
			continue
		f.hit_set[p] = true
		damage_prop(p, data.prop, f.id, p.center())
	# Swatting shots out of the air sends them back.
	for s: Shot in shots:
		if s.dead or s.kind == "grenade" or s.owner == f.id or not zone.has_point(s.pos):
			continue
		s.vel = Vector2(-s.vel.x, -s.vel.y * 0.3 - 40.0)
		s.owner = f.id
		s.deflected = true
		s.life = maxf(s.life, 0.6)
		s.start = s.pos
		_spark(s.pos, s.vel.normalized(), 8, Color("#fff5c0"), 380.0)
		sound("clang", s.pos)
		stats[f.id].deflects += 1
		events.append({"type": "deflect", "by": f.id})


func throw_grenade(f: Stickman) -> void:
	var lift := 0.2 if f.aim_explicit else 0.62
	var ang := f.aim.angle() - lift * f.facing
	var s := Shot.new()
	s.kind = "grenade"
	s.weapon = "grenade"
	s.pos = f.rig.j.get("hand_n", f.center())
	s.prev = s.pos
	s.vel = Vector2.from_angle(ang) * float(Weapons.def("grenade").speed) + f.vel * 0.4
	s.owner = f.id
	s.fuse = Weapons.def("grenade").fuse
	s.spin = 14.0 * f.facing
	shots.append(s)
	sound("pin", s.pos, -4.0)
	sound("throw", s.pos, -2.0)


func throw_weapon(f: Stickman) -> void:
	var p := Pickup.new()
	p.type = f.weapon
	p.ammo = f.ammo
	p.pos = f.rig.j.get("hand_n", f.center())
	p.vel = f.aim * 900.0 + Vector2(0, -120) + f.vel * 0.4
	p.spin = 16.0 * f.facing
	p.thrown_by = f.id
	p.danger = 1.0
	pickups.append(p)
	f.weapon = ""
	f.ammo = 0
	f.pickup_block = 0.35
	sound("throw", p.pos)


## Deals damage with knockback and blood. Killing blows and credit for them are handled here.
func hit_fighter(f: Stickman, amount: float, knock: Vector2, attacker: int, weapon: String, at: Vector2, head: bool) -> void:
	if not f.alive:
		return
	if attacker >= 0 and attacker != f.id and stats.has(attacker):
		stats[attacker].damage += minf(amount, maxf(f.hp, 0.0))
		if head:
			stats[attacker].headshots += 1
	var killed := f.damage(amount, knock, attacker, weapon, time)
	if blood:
		var n := clampi(int(amount / 5.0), 2, 14)
		for i in n:
			var dir := knock.normalized().rotated(rng.randf_range(-0.7, 0.7)) if knock.length() > 1.0 else Vector2.UP.rotated(rng.randf_range(-1.2, 1.2))
			var b := _particle("blood", at, dir * rng.randf_range(90, 330) + Vector2(0, -60), rng.randf_range(0.5, 1.0), rng.randf_range(1.5, 3.2), Color("#b3121b"), 0.0)
			b.gravity = GRAVITY * 0.6
			b.collide = true
	sound("hurt", at, -6.0)
	events.append({"type": "hit", "id": f.id, "amount": amount, "head": head})
	if killed:
		_kill(f, attacker, weapon, knock, head)


func _kill(f: Stickman, attacker: int, weapon: String, knock: Vector2, head: bool) -> void:
	f.die(knock)
	_drop_weapon(f)
	var credit := attacker
	if credit < 0 or credit == f.id:
		credit = f.last_hitter if time - f.last_hit_time < 5.0 else -1
	if credit >= 0 and stats.has(credit):
		stats[credit].kills += 1
	events.append({"type": "kill", "killer": credit, "victim": f.id, "weapon": weapon, "head": head})
	sound("death", f.center(), -2.0)


func _fell(f: Stickman) -> void:
	f.alive = false
	f.gone = true
	f.hp = 0.0
	f.weapon = ""
	var credit := f.last_hitter if time - f.last_hit_time < 5.0 else -1
	if credit >= 0 and stats.has(credit):
		stats[credit].kills += 1
	events.append({"type": "kill", "killer": credit, "victim": f.id, "weapon": "fall", "head": false})
	sound("splash" if level_id == "kopru" else "fall", Vector2(f.pos.x, 700))
	if level_id == "kopru":
		for i in 14:
			var p := _particle("drop", Vector2(f.pos.x + rng.randf_range(-12, 12), 660), Vector2(rng.randf_range(-120, 120), rng.randf_range(-420, -200)), 0.9, 3.0, Color("#bfe6ff"), 0.0)
			p.gravity = GRAVITY * 0.7


func _drop_weapon(f: Stickman) -> void:
	if f.weapon == "" or (f.ammo <= 0 and f.weapon != "sword"):
		f.weapon = ""
		return
	var p := Pickup.new()
	p.type = f.weapon
	p.ammo = f.ammo
	p.pos = f.rig.j.get("hand_n", f.center())
	p.vel = Vector2(rng.randf_range(-120, 120), -260)
	p.spin = rng.randf_range(-12, 12)
	pickups.append(p)
	f.weapon = ""
	f.ammo = 0


# --- Crates and barrels ----------------------------------------------------------------------

func damage_prop(p: Prop, amount: float, by: int, at: Vector2) -> void:
	if p.dead:
		return
	p.shake = 1.0
	if p.kind == "barrel":
		sound("barrel_hit", at, -4.0)
		_spark(at, Vector2.UP, 3, Color("#ffcf6a"), 200.0)
		return
	p.hp -= amount
	if p.hp <= 0.0:
		break_crate(p, by)
	else:
		sound("crate_hit", at, -2.0)
		_splinters(at, 3)


## A shot or blast sets a barrel's fuse; it goes off a moment later.
func ignite(p: Prop, by: int, delay := 0.06) -> void:
	if p.dead or p.kind != "barrel":
		return
	if p.fuse < 0.0 or p.fuse > delay:
		p.fuse = delay
		p.lit_by = by
		if by >= 0 and stats.has(by):
			stats[by].barrels += 1
		sound("fuse", p.center(), -6.0)


func break_crate(p: Prop, by: int) -> void:
	if p.dead:
		return
	p.dead = true
	if by >= 0 and stats.has(by):
		stats[by].crates += 1
	events.append({"type": "crate", "by": by})
	sound("crate_break", p.center())
	_splinters(p.center(), 16)
	var w := Pickup.new()
	w.type = Weapons.random_type(rng)
	w.ammo = int(Weapons.def(w.type).ammo)
	w.pos = p.center()
	w.vel = Vector2(rng.randf_range(-70, 70), -330)
	w.spin = rng.randf_range(-10, 10)
	pickups.append(w)


func _update_props() -> void:
	for p: Prop in props:
		if p.dead:
			continue
		p.shake = maxf(0.0, p.shake - DT * 5.0)
		p.vel.y = minf(p.vel.y + GRAVITY * DT, 1400.0)
		if p.on_ground:
			p.vel.x = move_toward(p.vel.x, 0.0, 1500.0 * DT)
		var falling := p.vel.y
		var r := sweep(p.rect, p.vel * DT, false, p)
		p.rect = r.box
		if r.wall:
			p.vel.x *= -0.3
		if r.ceil:
			p.vel.y = 0.0
		var was := p.on_ground
		p.on_ground = r.ground
		if r.ground:
			p.vel.y = 0.0
			_tip_over(p)
			if not was and falling > 350.0:
				sound("drop", Vector2(p.center().x, p.rect.end.y), -6.0)
				dust(Vector2(p.center().x, p.rect.end.y), 6)
				if p.sky:
					ignite(p, -1, 0.0)
		if p.rect.position.y > KILL_Y:
			p.dead = true
			continue
		if p.fuse >= 0.0:
			p.fuse -= DT
			if p.fuse <= 0.0:
				p.dead = true
				explode(p.center(), p.lit_by, "barrel")
	props = props.filter(func(p: Prop) -> bool: return not p.dead)


## A prop resting mostly over thin air slides off the edge it is perched on.
func _tip_over(p: Prop) -> void:
	var bottom := p.rect.end.y
	var lo := INF
	var hi := -INF
	var supports: Array[Rect2] = solids.duplicate()
	supports.append_array(oneways)
	for o: Prop in props:
		if o != p and not o.dead:
			supports.append(o.rect)
	for r in supports:
		if absf(r.position.y - bottom) > 1.5:
			continue
		var a := maxf(r.position.x, p.rect.position.x)
		var b := minf(r.end.x, p.rect.end.x)
		if b > a:
			lo = minf(lo, a)
			hi = maxf(hi, b)
	if hi <= lo:
		return
	if hi - lo < p.rect.size.x * 0.4:
		var dir := signf(p.center().x - (lo + hi) * 0.5)
		p.vel.x = dir * 160.0
		p.rect.position.x += dir * 1.5


func explode(at: Vector2, owner: int, cause: String) -> void:
	var radius: float = Weapons.EXPLOSION.radius
	sound("boom", at)
	shake(16.0)
	events.append({"type": "explosion", "pos": at})
	blasts.append({"pos": at, "t": 0.0, "radius": radius})
	for f: Stickman in fighters:
		if not f.alive:
			if f.is_down() and not f.gone:
				var to := f.center() - at
				if to.length() < radius * 1.3:
					f.rig.ragdoll.push(f.center(), to.normalized() * 900.0 * (1.0 - to.length() / (radius * 1.3)) + Vector2(0, -400), 90.0)
			continue
		var c := f.center()
		var to := c - at
		var d := to.length()
		if d > radius + 14.0:
			continue
		var k := 1.0 - clampf(d / (radius + 14.0), 0.0, 1.0)
		if not line_clear(at, c, false):
			k *= 0.35
		var dir := to.normalized() if d > 1.0 else Vector2.UP
		var knock := dir * float(Weapons.EXPLOSION.knock) * (0.35 + 0.65 * k) + Vector2(0, -330.0 * (0.4 + k))
		hit_fighter(f, lerpf(12.0, Weapons.EXPLOSION.damage, k), knock, owner, cause, c, false)
	for p: Prop in props:
		if p.dead:
			continue
		var to := p.center() - at
		var d := to.length()
		if d > radius + 20.0:
			continue
		var k := 1.0 - clampf(d / (radius + 20.0), 0.0, 1.0)
		if p.kind == "crate":
			break_crate(p, owner)
		else:
			ignite(p, owner, rng.randf_range(0.12, 0.24))
			p.vel += (to.normalized() if d > 1.0 else Vector2.UP) * 380.0 * k + Vector2(0, -260.0 * k)
			p.on_ground = false
	for w: Pickup in pickups:
		var to := w.pos - at
		if to.length() < radius:
			w.vel += to.normalized() * 500.0 + Vector2(0, -300)
			w.on_ground = false
			w.spin = rng.randf_range(-20, 20)
	# Fire, smoke, sparks and a scorch mark.
	for i in 18:
		var dir := Vector2.from_angle(rng.randf_range(0, TAU))
		var fire := _particle("fire", at + dir * rng.randf_range(0, 30), dir * rng.randf_range(60, 260) + Vector2(0, -80), rng.randf_range(0.35, 0.7), rng.randf_range(10, 22), Color("#ffb347"), 0.0)
		fire.drag = 3.0
	for i in 14:
		var dir := Vector2.from_angle(rng.randf_range(0, TAU))
		var smoke := _particle("smoke", at + dir * rng.randf_range(0, 40), dir * rng.randf_range(30, 120) + Vector2(0, -90), rng.randf_range(0.9, 1.8), rng.randf_range(14, 28), Color(0.2, 0.19, 0.2, 0.75), 0.0)
		smoke.drag = 1.6
	_spark(at, Vector2.UP, 26, Color("#ffdf8a"), 700.0, PI)
	for i in 8:
		var deb := _particle("debris", at, Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(200, 520) + Vector2(0, -250), rng.randf_range(0.8, 1.6), rng.randf_range(2.5, 4.5), Color("#3a3a40"), 0.0)
		deb.gravity = GRAVITY
		deb.spin = rng.randf_range(-20, 20)
		deb.collide = true
	var gy := ground_below(at, 70.0)
	if gy != INF:
		decals.append({"kind": "scorch", "pos": Vector2(at.x, gy), "size": rng.randf_range(46, 60), "life": 30.0, "angle": 0.0, "color": Color.BLACK})


# --- Shots -----------------------------------------------------------------------------------

func _update_shots() -> void:
	for s: Shot in shots:
		if s.dead:
			continue
		s.age += DT
		if s.kind == "grenade":
			_grenade(s)
			continue
		s.prev = s.pos
		s.vel.y += s.gravity * DT
		s.pos += s.vel * DT
		s.angle = s.vel.angle()
		s.life -= DT
		var hit := raycast(s.prev, s.pos, s.owner)
		_push_corpses(s)
		if hit.is_empty():
			if s.life <= 0.0 or s.pos.y > KILL_Y or s.pos.x < -200.0 or s.pos.x > 1480.0:
				s.dead = true
			continue
		var at := s.prev.lerp(s.pos, hit.t)
		s.pos = at
		s.dead = true
		match hit.kind:
			"wall":
				if s.kind == "bolt":
					decals.append({"kind": "bolt", "pos": at, "angle": s.angle, "size": 1.0, "life": 9.0, "color": Color.WHITE})
					sound("bolt_hit", at, -4.0)
				else:
					_spark(at, -s.vel.normalized(), 4 if s.kind == "bullet" else 2, Color("#ffd36a"), 220.0)
					_dust_puff(at, 2)
					if s.kind == "bullet" and rng.randf() < 0.3:
						sound("ricochet", at, -10.0)
			"prop":
				var p: Prop = hit.obj
				if p.kind == "barrel":
					ignite(p, s.owner)
					_spark(at, -s.vel.normalized(), 5, Color("#ffcf6a"), 260.0)
				else:
					damage_prop(p, s.prop_damage, s.owner, at)
			"fighter":
				var f: Stickman = hit.obj
				var dmg := s.damage * (1.6 if hit.head else 1.0)
				if s.kind == "pellet":
					var travelled := s.start.distance_to(at)
					dmg *= clampf(1.3 - travelled / 420.0, 0.35, 1.15)
				var knock := s.vel.normalized() * s.knock + Vector2(0, -60)
				hit_fighter(f, dmg, knock, s.owner, s.weapon, at, hit.head)
				if s.kind == "bolt":
					sound("bolt_hit", at)
				if hit.head:
					events.append({"type": "headshot", "pos": at})
	shots = shots.filter(func(s: Shot) -> bool: return not s.dead)


## Bullets passing through a body that's lying around give it a shove.
func _push_corpses(s: Shot) -> void:
	for f: Stickman in fighters:
		if f.alive or f.gone or not f.is_down():
			continue
		if seg_rect(s.prev, s.pos, f.hurt_rect()) >= 0.0:
			f.rig.ragdoll.push(s.pos, s.vel * 0.12, 26.0)


func _grenade(s: Shot) -> void:
	s.fuse -= DT
	s.vel.y = minf(s.vel.y + GRAVITY * 0.9 * DT, 1300.0)
	s.prev = s.pos
	var box := Rect2(s.pos - Vector2(5, 5), Vector2(10, 10))
	var r := sweep(box, s.vel * DT)
	var speed := s.vel.length()
	if r.wall:
		s.vel.x = -s.vel.x * 0.5
	if r.ceil:
		s.vel.y = -s.vel.y * 0.4
	if r.ground:
		if absf(s.vel.y) > 140.0:
			s.vel.y = -s.vel.y * 0.42
		else:
			s.vel.y = 0.0
		s.vel.x *= 0.72
	if (r.wall or r.ceil or r.ground) and speed > 160.0:
		sound("bounce", s.pos, -6.0)
	s.pos = (r.box as Rect2).get_center()
	s.spin = s.vel.x * 0.025
	s.angle += s.spin * DT
	if s.pos.y > KILL_Y:
		s.dead = true
	elif s.fuse <= 0.0:
		s.dead = true
		explode(s.pos, s.owner, "grenade")


# --- Weapons on the ground -------------------------------------------------------------------

func _update_pickups() -> void:
	for w: Pickup in pickups:
		if w.dead:
			continue
		w.age += DT
		w.vel.y = minf(w.vel.y + GRAVITY * DT, 1300.0)
		var box := Rect2(w.pos - Vector2(9, 5), Vector2(18, 10))
		var prev := w.pos
		var r := sweep(box, w.vel * DT)
		w.pos = (r.box as Rect2).get_center()
		if w.danger > 0.0:
			_thrown_hit(w, prev)
		if r.wall:
			w.vel.x = -w.vel.x * 0.4
			w.danger = 0.0
		if r.ceil:
			w.vel.y = 0.0
		if r.ground:
			if not w.on_ground and w.vel.y > 260.0:
				sound("bounce", w.pos, -12.0)
			w.vel.y = -w.vel.y * 0.25 if w.vel.y > 260.0 else 0.0
			w.vel.x *= 0.6
			w.danger = 0.0
		w.on_ground = r.ground
		if w.on_ground and absf(w.vel.x) < 20.0:
			w.angle = lerp_angle(w.angle, 0.0, 1.0 - exp(-12.0 * DT))
			w.spin = 0.0
		else:
			w.angle += w.spin * DT
		var life := PICKUP_LIFE if w.usable() or w.danger > 0.0 else 2.5
		if w.age > life or w.pos.y > KILL_Y:
			w.dead = true
	# Empty-handed fighters grab what they walk over.
	for f: Stickman in fighters:
		if not f.alive or f.is_down() or f.weapon != "" or f.pickup_block > 0.0 or f.attack_kind == "throw":
			continue
		var reach := Rect2(f.pos.x - 22.0, f.pos.y - 60.0, 44.0, 64.0)
		for w: Pickup in pickups:
			if w.usable() and reach.has_point(w.pos):
				f.weapon = w.type
				f.ammo = w.ammo
				f.combo_step = 0
				w.dead = true
				sound("pickup", w.pos, -2.0)
				events.append({"type": "pickup", "id": f.id, "weapon": w.type})
				break
	pickups = pickups.filter(func(w: Pickup) -> bool: return not w.dead)


func _thrown_hit(w: Pickup, prev: Vector2) -> void:
	if w.vel.length() < 250.0:
		w.danger = 0.0
		return
	var hit := raycast(prev, w.pos, w.thrown_by if w.age < 0.25 else -1, true, true)
	if hit.is_empty() or hit.kind == "wall":
		return
	if hit.kind == "fighter":
		var f: Stickman = hit.obj
		if f.id == w.thrown_by and w.age < 0.25:
			return
		hit_fighter(f, Weapons.THROWN.damage, w.vel.normalized() * float(Weapons.THROWN.knock) + Vector2(0, -120), w.thrown_by, "thrown", w.pos, hit.head)
		sound("punch_h", w.pos)
	elif hit.kind == "prop":
		var p: Prop = hit.obj
		if p.kind == "barrel":
			ignite(p, w.thrown_by)
		else:
			damage_prop(p, 20.0, w.thrown_by, w.pos)
	w.danger = 0.0
	w.vel = Vector2(-w.vel.x * 0.25, -180.0)


# --- Ragdolls --------------------------------------------------------------------------------

func _update_ragdolls() -> void:
	var blockers: Array[Rect2] = solids.duplicate()
	for p: Prop in props:
		if not p.dead:
			blockers.append(p.rect)
	for f: Stickman in fighters:
		var rd: Rig.Ragdoll = f.rig.ragdoll
		if rd == null or f.gone:
			continue
		_step_ragdoll(rd, blockers)
		if not f.alive:
			f.rig.j = rd.p.duplicate()
			if (rd.p.hip as Vector2).y > KILL_Y + 150.0:
				f.gone = true
		elif (rd.p.hip as Vector2).y > KILL_Y:
			f.pos = rd.p.hip
			_fell(f)


func _step_ragdoll(rd: Rig.Ragdoll, blockers: Array[Rect2]) -> void:
	rd.age += DT
	# A one-way platform only holds the body when its hip is above it, so a body that flew
	# up through a platform can't end up hanging from it by the head.
	var hip_before: Vector2 = rd.o.hip
	var floors: Array[Rect2] = []
	for r in oneways:
		if hip_before.y <= r.position.y + 4.0:
			floors.append(r)
	var g := Vector2(0, GRAVITY * DT * DT)
	for key: String in rd.p:
		var cur: Vector2 = rd.p[key]
		var v: Vector2 = (cur - (rd.o[key] as Vector2)) * 0.995
		rd.o[key] = cur
		rd.p[key] = cur + v + g
	for it in 6:
		for l: Array in rd.links:
			var a: Vector2 = rd.p[l[0]]
			var b: Vector2 = rd.p[l[1]]
			var d := b - a
			var length := d.length()
			var rest: float = l[2]
			var stiff: float = l[3]
			if stiff < 0.0:
				if length >= rest:
					continue
				stiff = -stiff
			if length < 0.0001:
				continue
			var k := (length - rest) / length * 0.5 * stiff
			rd.p[l[0]] = a + d * k
			rd.p[l[1]] = b - d * k
		for key: String in rd.p:
			_collide_particle(rd, key, Rig.HEAD_R if key == "head" else 2.5, blockers, floors)
	var speed := rd.velocity().length()
	rd.still = rd.still + DT if speed < 40.0 else 0.0


func _collide_particle(rd: Rig.Ragdoll, key: String, r: float, blockers: Array[Rect2], floors: Array[Rect2]) -> void:
	var p: Vector2 = rd.p[key]
	var o: Vector2 = rd.o[key]
	var landed := false
	for rect in blockers:
		var g := rect.grow(r)
		if not g.has_point(p):
			continue
		var left := p.x - g.position.x
		var right := g.end.x - p.x
		var up := p.y - g.position.y
		var down := g.end.y - p.y
		var m := minf(minf(left, right), minf(up, down))
		if m == up:
			p.y = g.position.y
			landed = true
		elif m == down:
			p.y = g.end.y
		elif m == left:
			p.x = g.position.x
		else:
			p.x = g.end.x
	for rect in floors:
		var top := rect.position.y - r
		if o.y <= top + 0.5 and p.y > top and p.x > rect.position.x and p.x < rect.end.x:
			p.y = top
			landed = true
	if landed:
		o.x = lerpf(o.x, p.x, 0.22)
		rd.o[key] = o
	rd.p[key] = p


# --- Supply drops and sudden death -----------------------------------------------------------

func _supply_drops() -> void:
	_drop_timer -= DT
	if _drop_timer > 0.0:
		return
	_drop_timer = rng.randf_range(5.0, 8.0)
	var crates := props.filter(func(p: Prop) -> bool: return p.kind == "crate").size()
	if crates >= max_crates:
		return
	var x := _drop_x()
	if is_nan(x):
		return
	var p := add_prop("crate", Vector2(x, -40))
	p.vel.y = 200.0
	events.append({"type": "supply", "x": x})


func _sudden_death() -> void:
	if not sudden_death:
		return
	if not sudden and state_t >= SUDDEN_DEATH:
		sudden = true
		_sky_timer = 1.0
		events.append({"type": "sudden"})
		sound("alarm", Vector2(640, 360))
	if not sudden:
		return
	_sky_timer -= DT
	if _sky_timer > 0.0:
		return
	_sky_timer = rng.randf_range(0.9, 1.4)
	var x := _drop_x()
	var alive := alive_fighters()
	if not alive.is_empty() and rng.randf() < 0.5:
		x = (alive[rng.randi() % alive.size()] as Stickman).pos.x + rng.randf_range(-40, 40)
	if is_nan(x):
		return
	var p := add_prop("barrel", Vector2(clampf(x, 30, 1250), -50))
	p.sky = true
	p.vel.y = 300.0


## A random x above some surface, away from fighters' heads.
func _drop_x() -> float:
	var surfaces: Array[Rect2] = []
	for r in solids:
		if r.size.x >= 80.0 and r.position.y > 0.0 and r.position.x > -50.0:
			surfaces.append(r)
	surfaces.append_array(oneways)
	for attempt in 12:
		var s := surfaces[rng.randi() % surfaces.size()]
		var x := rng.randf_range(maxf(s.position.x, 0.0) + 22.0, minf(s.end.x, 1280.0) - 22.0)
		var ok := true
		for f: Stickman in fighters:
			if f.alive and absf(f.pos.x - x) < 46.0:
				ok = false
		for p: Prop in props:
			if absf(p.center().x - x) < 40.0 and absf(p.rect.end.y - s.position.y) < 4.0:
				ok = false
		if ok:
			return x
	return NAN


# --- Effects ---------------------------------------------------------------------------------

func _particle(kind: String, at: Vector2, v: Vector2, life: float, size: float, color: Color, angle: float) -> Particle:
	var p := Particle.new()
	p.kind = kind
	p.pos = at
	p.vel = v
	p.life = life
	p.max_life = life
	p.size = size
	p.color = color
	p.angle = angle
	if particles.size() >= MAX_PARTICLES:
		particles.pop_front()
	particles.append(p)
	return p


func _spark(at: Vector2, dir: Vector2, n: int, color: Color, speed: float, spread := 0.9) -> void:
	for i in n:
		var v := dir.rotated(rng.randf_range(-spread, spread)) * rng.randf_range(speed * 0.4, speed)
		var p := _particle("spark", at, v, rng.randf_range(0.12, 0.3), rng.randf_range(1.0, 2.0), color, 0.0)
		p.gravity = GRAVITY * 0.5
		p.drag = 2.0


func _splinters(at: Vector2, n: int) -> void:
	for i in n:
		var v := Vector2(rng.randf_range(-260, 260), rng.randf_range(-420, -80))
		var p := _particle("splinter", at + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)), v, rng.randf_range(0.8, 1.6),
				rng.randf_range(3.0, 7.0), Color("#a8743f").darkened(rng.randf_range(0.0, 0.35)), rng.randf_range(0, TAU))
		p.gravity = GRAVITY
		p.spin = rng.randf_range(-18, 18)
		p.collide = true


func dust(at: Vector2, n: int) -> void:
	for i in n:
		var p := _particle("dust", at + Vector2(rng.randf_range(-10, 10), -2), Vector2(rng.randf_range(-140, 140), rng.randf_range(-50, -10)),
				rng.randf_range(0.35, 0.6), rng.randf_range(4, 8), Color(0.85, 0.82, 0.75, 0.45), 0.0)
		p.drag = 4.0


func _dust_puff(at: Vector2, n: int) -> void:
	for i in n:
		var p := _particle("dust", at, Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 10)), 0.35, rng.randf_range(3, 5), Color(0.8, 0.78, 0.72, 0.5), 0.0)
		p.drag = 4.0


func _update_particles() -> void:
	for p: Particle in particles:
		p.life -= DT
		if p.drag > 0.0:
			p.vel *= maxf(0.0, 1.0 - p.drag * DT)
		p.vel.y += p.gravity * DT
		var next := p.pos + p.vel * DT
		if p.collide and p.vel.y > 0.0:
			var gy := ground_below(p.pos, p.vel.y * DT + 2.0)
			if gy != INF and next.y >= gy:
				next.y = gy
				if p.kind == "blood":
					if decals.size() < 260:
						decals.append({"kind": "blood", "pos": Vector2(next.x, gy), "size": p.size * rng.randf_range(1.2, 2.2), "life": 25.0, "angle": 0.0, "color": p.color.darkened(0.2)})
					p.life = 0.0
				else:
					p.vel = Vector2(p.vel.x * 0.5, -p.vel.y * 0.25)
					p.spin *= 0.5
					if absf(p.vel.y) < 30.0:
						p.vel = Vector2.ZERO
						p.gravity = 0.0
		p.pos = next
		p.angle += p.spin * DT
	particles = particles.filter(func(p: Particle) -> bool: return p.life > 0.0)
	for d: Dictionary in decals:
		d.life -= DT
	decals = decals.filter(func(d: Dictionary) -> bool: return d.life > 0.0)


func _update_blasts() -> void:
	for b: Dictionary in blasts:
		b.t += DT
	blasts = blasts.filter(func(b: Dictionary) -> bool: return b.t < 0.6)
