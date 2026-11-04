extends RefCounted
## A bot. Every think it picks a goal — run from a grenade or a lit barrel, grab a weapon, break
## a crate, or go after an enemy — then walks the level's nav graph towards it and fights with
## whatever it holds. It returns the same input Dictionary a human's controls produce.

const Stickman := preload("res://scripts/game/stickman.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const Nav := preload("res://scripts/game/nav.gd")

## Per difficulty (easy, normal, hard).
const REACTION := [0.65, 0.3, 0.13]
const AIM_ERROR := [0.22, 0.08, 0.03]
const THINK := [0.28, 0.15, 0.09]
const DODGE := [0.0, 0.5, 1.2]
const SHOT_PAUSE := [0.7, 0.18, 0.0]
## Distance each weapon likes to fight from: [min, max].
const RANGE := {"": [0.0, 34.0], "pistol": [140.0, 520.0], "shotgun": [60.0, 230.0], "crossbow": [200.0, 700.0],
		"sword": [0.0, 44.0], "grenade": [170.0, 460.0]}

var id := 0
var diff := 1
var rng := RandomNumberGenerator.new()
var goal := {}
var _think := 0.0
var _path: Array = []
var _link: Nav.Link = null
var _link_t := 0.0
## The surface last stood on, and whether the bot has started the move in `_link` (only
## then may it leave that surface).
var _home: Nav.Surface = null
var _committed := false
## Where this bot actually takes off for `_link` (clear of crates and barrels).
var _take := 0.0
## Links that didn't work out lately: link -> time they may be tried again.
var _banned := {}
var _clock := 0.0
var _see := 0.0
var _aim_err := 0.0
var _pause := 0.0
var _stuck := 0.0
var _last_x := 0.0
var _jump_cool := 0.0
var _punch_cool := 0.0
var _target_id := -1


func setup(fighter_id: int, difficulty: int, seed_value: int) -> void:
	id = fighter_id
	diff = clampi(difficulty, 0, 2)
	rng.seed = seed_value


func think(w: RefCounted, dt: float) -> Dictionary:
	var out := {"move": 0.0, "jump": false, "jump_held": false, "down": false, "attack": false,
			"attack_held": false, "throw": false, "aim": Vector2.ZERO}
	var f: Stickman = w.fighter(id)
	if f == null or not f.alive or f.is_down() or not w.can_act():
		return out
	_clock += dt
	_jump_cool = maxf(0.0, _jump_cool - dt)
	_punch_cool = maxf(0.0, _punch_cool - dt)
	_pause = maxf(0.0, _pause - dt)
	_think -= dt
	if _think <= 0.0:
		_think = THINK[diff] * rng.randf_range(0.8, 1.25)
		_aim_err = rng.randf_range(-AIM_ERROR[diff], AIM_ERROR[diff])
		_choose_goal(w, f)
	_navigate(w, f, out, dt)
	_fight(w, f, out, dt)
	return out


# --- Goals -----------------------------------------------------------------------------------

func _choose_goal(w: RefCounted, f: Stickman) -> void:
	# Get away from anything about to blow up.
	for s in w.shots:
		if s.kind == "grenade" and s.pos.distance_to(f.center()) < 175.0 and s.fuse < 1.6:
			goal = {"kind": "flee", "pos": s.pos}
			return
	for p in w.props:
		if p.kind == "barrel" and p.fuse >= 0.0 and p.center().distance_to(f.center()) < 170.0:
			goal = {"kind": "flee", "pos": p.center()}
			return
	var nav: Nav = w.nav
	var enemy := _pick_enemy(w, f)
	var armed := f.weapon != "" and (f.ammo > 0 or f.weapon == "sword")
	if not armed:
		var best_cost := INF
		var best := {}
		for p in w.pickups:
			if not p.usable():
				continue
			var c := nav.travel_cost(f.pos, p.pos)
			if c < best_cost and c < 1100.0:
				best_cost = c
				best = {"kind": "pickup", "pos": p.pos}
		for p in w.props:
			if p.kind != "crate" or not p.on_ground:
				continue
			var stand := Vector2(p.center().x, p.rect.end.y)
			var c := nav.travel_cost(f.pos, stand) + 60.0
			if c < best_cost:
				best_cost = c
				best = {"kind": "crate", "pos": stand, "obj": p}
		if enemy != null:
			var c := nav.travel_cost(f.pos, enemy.pos)
			# Brawl when someone is close or there's nothing to pick up.
			if c < 160.0 or best.is_empty() or (c < best_cost * 0.5):
				best = {"kind": "enemy", "pos": enemy.pos, "id": enemy.id}
		goal = best if not best.is_empty() else {"kind": "wander", "pos": Vector2(rng.randf_range(100, 1180), f.pos.y)}
		return
	if enemy != null:
		goal = {"kind": "enemy", "pos": enemy.pos, "id": enemy.id}
	else:
		goal = {"kind": "wander", "pos": f.pos}


func _pick_enemy(w: RefCounted, f: Stickman) -> Stickman:
	var best: Stickman = null
	var best_score := INF
	for o: Stickman in w.fighters:
		if o == f or not o.alive:
			continue
		var score := o.pos.distance_to(f.pos) + absf(o.pos.y - f.pos.y) + o.hp * 1.5
		if o.id == _target_id:
			score *= 0.7
		if w.line_clear(f.center(), o.center(), false):
			score *= 0.5
		if score < best_score:
			best_score = score
			best = o
	_target_id = best.id if best else -1
	return best


# --- Moving ----------------------------------------------------------------------------------

func _navigate(w: RefCounted, f: Stickman, out: Dictionary, dt: float) -> void:
	var nav: Nav = w.nav
	if goal.is_empty():
		return
	var target: Vector2 = goal.pos
	if goal.kind == "enemy":
		var e: Stickman = w.fighter(goal.id)
		if e and e.alive:
			target = e.pos
	var cur := nav.surface_at(f.pos) if f.on_ground else null
	if cur:
		if cur != _home or not _link:
			_committed = false
		_home = cur
	var desired := target.x

	if goal.kind == "flee":
		var away := signf(f.pos.x - target.x)
		if away == 0.0:
			away = 1.0 if rng.randf() < 0.5 else -1.0
		desired = f.pos.x + away * 200.0
		if cur:
			if desired < cur.x0 + 12.0 or desired > cur.x1 - 12.0:
				# Cornered: hop over it instead.
				desired = f.pos.x - away * 200.0
				if _jump_cool <= 0.0:
					out.jump = true
					_jump_cool = 0.5
			desired = clampf(desired, cur.x0 + 12.0, cur.x1 - 12.0)
		_steer(f, out, desired, 4.0)
		out.jump_held = true
		return

	# Mid-air: finish the move that's underway, otherwise come back down where we left.
	if not f.on_ground:
		if _link and _committed:
			var to: Nav.Surface = nav.surfaces[_link.to]
			var straight := _link.hi > _link.lo
			var wait: bool = _link.kind == "jump" and to.y < nav.surfaces[_link.from].y - 3.0 \
					and absf(_link.land_x - _link.take_x) < 70.0 and f.pos.y > to.y - 2.0 and f.vel.y < 0.0
			if straight:
				_steer(f, out, _take, 2.0)
			elif not wait:
				_steer(f, out, _link.land_x, 2.0)
			out.jump_held = true
		else:
			_steer(f, out, _over_home(desired), 6.0)
			out.jump_held = f.vel.y < 0.0
		return

	if cur == null:
		# Standing on a crate or barrel: walk towards the target, nav takes over once down.
		_steer(f, out, desired, 6.0)
		_unstick(f, out, dt)
		return
	var dest := nav.surface_under(target)
	if _link and nav.surfaces[_link.to] == cur:
		_link = null
	if dest == null or dest == cur:
		_link = null
		desired = _standoff(w, f, target, cur)
		_steer(f, out, desired, 6.0)
		_unstick(f, out, dt)
		return
	if _link == null or nav.surfaces[_link.from] != cur:
		for l in _banned.keys():
			if _banned[l] < _clock:
				_banned.erase(l)
		_path = nav.path(cur, dest, f.pos.x, _banned)
		_link = _path[0] if not _path.is_empty() else null
		_link_t = 0.0
		if _link:
			_take = _pick_take(w, f, _link)
			if is_nan(_take):
				_banned[_link] = _clock + 5.0
				_link = null
	if _link == null:
		desired = clampf(target.x, cur.x0 + 14.0, cur.x1 - 14.0)
		_steer(f, out, desired, 6.0)
		_unstick(f, out, dt)
		return
	_link_t += dt
	if _link_t > 4.0:
		_banned[_link] = _clock + 6.0
		_link = null
		return
	var off := absf(f.pos.x - _take)
	var straight := _link.hi > _link.lo
	match _link.kind:
		"walk", "fall":
			_committed = true
			_steer(f, out, _link.land_x, 2.0)
		"drop":
			if off < 10.0:
				out.down = true
				out.jump = true
				_committed = true
			else:
				_steer(f, out, _take, 4.0)
		"jump":
			if off < 9.0:
				if _jump_cool <= 0.0:
					out.jump = true
					out.jump_held = true
					_jump_cool = 0.35
					_committed = true
				if not straight and absf(_link.land_x - _link.take_x) >= 70.0:
					_steer(f, out, _link.land_x, 2.0)
			else:
				_steer(f, out, _take, 3.0)
	if _link and _link.kind != "fall" and _link.kind != "walk":
		# Never stroll off a ledge on the way to the take-off point.
		var edge_l := cur.x0 + 10.0
		var edge_r := cur.x1 - 10.0
		if (f.pos.x < edge_l and out.move < 0.0) or (f.pos.x > edge_r and out.move > 0.0):
			out.move = 0.0
	_unstick(f, out, dt)


## A take-off point for `l` near the bot that isn't blocked by a crate or barrel — on the
## way there, or (for straight-up jumps) sitting on the platform above. NAN if there's none.
func _pick_take(w: RefCounted, f: Stickman, l: Nav.Link) -> float:
	var nav: Nav = w.nav
	var a: Nav.Surface = nav.surfaces[l.from]
	var b: Nav.Surface = nav.surfaces[l.to]
	var best := NAN
	var x := l.lo
	while x <= l.hi + 0.1:
		var ok := true
		for p in w.props:
			if p.dead:
				continue
			var r: Rect2 = p.rect
			if r.intersects(Rect2(x - 13.0, a.y - 70.0, 26.0, 68.0)):
				ok = false
			elif l.kind == "jump" and r.intersects(Rect2(x - 13.0, b.y - 60.0, 26.0, 58.0)):
				ok = false
			# Crates and barrels between here and there block the walk.
			elif absf(r.end.y - a.y) < 2.0 and r.position.x < maxf(x, f.pos.x) and r.end.x > minf(x, f.pos.x):
				ok = false
		if ok and (is_nan(best) or absf(x - f.pos.x) < absf(best - f.pos.x)):
			best = x
		if l.hi <= l.lo:
			break
		x += 6.0
	return best


## `x` kept over the surface last stood on, for when the bot is airborne by accident.
func _over_home(x: float) -> float:
	if _home == null:
		return x
	return clampf(x, _home.x0 + 14.0, _home.x1 - 14.0)


## Where to stand when the target is on the same surface: weapons keep their distance.
func _standoff(w: RefCounted, f: Stickman, target: Vector2, cur: Nav.Surface) -> float:
	var x := target.x
	if goal.kind == "enemy":
		var r: Array = RANGE.get(f.weapon if f.ammo > 0 or f.weapon == "sword" else "", RANGE[""])
		var dx := f.pos.x - target.x
		var dist := absf(dx)
		var side := signf(dx) if dx != 0.0 else 1.0
		if dist < r[0]:
			x = target.x + side * (r[0] + 30.0)
		elif dist > r[1]:
			x = target.x + side * r[1] * 0.8
		else:
			x = f.pos.x
	elif goal.kind == "crate":
		var p = goal.get("obj")
		if p and not p.dead:
			var side := signf(f.pos.x - p.center().x)
			if side == 0.0:
				side = 1.0
			x = p.center().x + side * (p.rect.size.x * 0.5 + 16.0)
	return clampf(x, cur.x0 + 12.0, cur.x1 - 12.0)


func _steer(f: Stickman, out: Dictionary, x: float, tolerance: float) -> void:
	var dx := x - f.pos.x
	if absf(dx) > tolerance:
		out.move = signf(dx)
	elif absf(dx) > tolerance * 0.5:
		out.move = signf(dx) * 0.4


## Jumps over whatever blocks the way, and gives up on a goal it can't reach.
func _unstick(f: Stickman, out: Dictionary, dt: float) -> void:
	if out.move != 0.0 and (f.hit_wall or absf(f.pos.x - _last_x) < 0.3):
		_stuck += dt
	else:
		_stuck = 0.0
	_last_x = f.pos.x
	if f.hit_wall and out.move != 0.0 and _jump_cool <= 0.0 and f.weapon != "" and goal.get("kind") != "crate":
		out.jump = true
		out.jump_held = true
		_jump_cool = 0.4
	if _stuck > 0.7:
		if _jump_cool <= 0.0:
			out.jump = true
			out.jump_held = true
			_jump_cool = 0.4
		if _stuck > 2.0:
			_stuck = 0.0
			_link = null
			goal = {"kind": "wander", "pos": Vector2(rng.randf_range(100, 1180), f.pos.y)}


# --- Fighting --------------------------------------------------------------------------------

func _fight(w: RefCounted, f: Stickman, out: Dictionary, dt: float) -> void:
	var enemy: Stickman = w.fighter(_target_id) if _target_id >= 0 else null
	if enemy != null and not enemy.alive:
		enemy = null
	var origin := f.center()

	# Unarmed: punch whoever is in reach, and the crate we came for.
	if f.weapon == "":
		_see = 0.0
		for o: Stickman in w.fighters:
			if o == f or not o.alive:
				continue
			var d := o.center() - origin
			if absf(d.x) < 40.0 and absf(d.y) < 46.0 and _punch_cool <= 0.0:
				out.aim = Vector2(signf(d.x) if d.x != 0.0 else f.facing, clampf(d.y / 60.0, -0.4, 0.4))
				out.attack = true
				_punch_cool = [0.42, 0.24, 0.12][diff]
				return
		if goal.get("kind") == "crate":
			var p = goal.get("obj")
			if p and not p.dead:
				var d: Vector2 = p.center() - origin
				if absf(d.x) < 46.0 and absf(d.y) < 50.0 and _punch_cool <= 0.0:
					out.aim = d.normalized() if d.length() > 1.0 else Vector2(f.facing, 0)
					out.move = 0.0
					out.attack = true
					_punch_cool = 0.2
		return

	# An empty gun is only good for throwing.
	if f.is_gun() and f.ammo <= 0:
		if enemy and enemy.center().distance_to(origin) < 420.0 and w.line_clear(origin, enemy.center(), true):
			out.aim = (enemy.center() - origin).normalized()
		out.throw = true
		return

	_dodge(w, f, out, dt)
	# Whoever is in the line of fire right now beats the one we were walking to.
	var r_w: Array = RANGE.get(f.weapon, [0.0, 600.0])
	var reach: float = r_w[1] * 1.35 if f.is_gun() else 70.0
	var best_score := INF
	for o: Stickman in w.fighters:
		if o == f or not o.alive:
			continue
		var d := o.center().distance_to(origin)
		if d > reach or not w.line_clear(origin, o.center(), true):
			continue
		var score := d * (0.7 if o == enemy else 1.0)
		if score < best_score:
			best_score = score
			if o != enemy:
				_see = minf(_see, REACTION[diff] * 0.5)
			enemy = o
	if enemy == null:
		_see = 0.0
		return
	var target := enemy.center()
	var to := target - origin
	var dist := to.length()

	match f.weapon:
		"sword":
			if absf(to.x) < 58.0 and absf(to.y) < 64.0:
				out.aim = Vector2(signf(to.x) if to.x != 0.0 else f.facing, 0)
				_see += dt
				if _see > REACTION[diff] * 0.6:
					out.attack = true
			else:
				_see = 0.0
		"grenade":
			if dist > 150.0 and dist < 520.0 and absf(to.y) < 260.0:
				_see += dt
				if _see > REACTION[diff] + 0.2 and _pause <= 0.0:
					out.aim = _lob(f, target)
					out.attack = true
					_pause = 1.0
			else:
				_see = 0.0
		_:
			var barrel := _barrel_shot(w, f, origin)
			var clear_props := barrel == Vector2.ZERO
			if barrel != Vector2.ZERO:
				target = barrel
			else:
				# A crate in the way gets shot open.
				var hit: Dictionary = w.raycast(origin, target, f.id, false, true)
				if not hit.is_empty() and hit.kind == "prop" and hit.obj.kind == "crate" and hit.t * dist < 320.0:
					target = hit.obj.center()
					clear_props = false
			to = target - origin
			dist = to.length()
			var r: Array = RANGE.get(f.weapon, [0.0, 600.0])
			if dist < r[1] * 1.35 and w.line_clear(origin, target, clear_props):
				_see += dt
				out.aim = w.lead_aim(f.weapon, origin, target).rotated(_aim_err)
				if _see > REACTION[diff] and _pause <= 0.0 and f.cooldown <= 0.0:
					out.attack = true
					_pause = SHOT_PAUSE[diff] * rng.randf_range(0.5, 1.5)
			else:
				_see = maxf(0.0, _see - dt * 2.0)


## Shoots a barrel when an enemy stands next to it and we're safely away.
func _barrel_shot(w: RefCounted, f: Stickman, origin: Vector2) -> Vector2:
	if diff == 0:
		return Vector2.ZERO
	for p in w.props:
		if p.kind != "barrel" or p.fuse >= 0.0:
			continue
		var c: Vector2 = p.center()
		if c.distance_to(origin) < 190.0:
			continue
		for o: Stickman in w.fighters:
			if o == f or not o.alive or o.center().distance_to(c) > 95.0:
				continue
			var hit: Dictionary = w.raycast(origin, c, f.id, true, true)
			if not hit.is_empty() and hit.kind == "prop" and hit.obj == p:
				return c
	return Vector2.ZERO


## Throw direction that lands a grenade near `target`.
func _lob(f: Stickman, target: Vector2) -> Vector2:
	var speed: float = Weapons.def("grenade").speed
	var g := Stickman.GRAVITY * 0.9
	var start := f.center() - Vector2(0, 6)
	var best := Vector2(f.facing, -1).normalized()
	var best_err := INF
	for i in 24:
		var lift := lerpf(-1.25, 0.15, i / 23.0)
		var ang := (0.0 if target.x >= start.x else PI) + lift * (1.0 if target.x >= start.x else -1.0)
		var v := Vector2.from_angle(ang) * speed + f.vel * 0.4
		# Time to come down to the target's height.
		var a := 0.5 * g
		var b := v.y
		var c := start.y - target.y
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			continue
		var t := (-b + sqrt(disc)) / (2.0 * a)
		var err := absf(start.x + v.x * t - target.x)
		if err < best_err:
			best_err = err
			best = Vector2.from_angle(ang)
	# The throw adds a little lift of its own when aimed explicitly.
	var facing := 1.0 if target.x >= start.x else -1.0
	return best.rotated(0.2 * facing)


## Hops out of the line of fire now and then.
func _dodge(w: RefCounted, f: Stickman, out: Dictionary, dt: float) -> void:
	if DODGE[diff] <= 0.0 or not f.on_ground or _jump_cool > 0.0:
		return
	for o: Stickman in w.fighters:
		if o == f or not o.alive or not o.is_gun() or o.ammo <= 0:
			continue
		var d := f.center() - o.center()
		if absf(d.y) > 70.0 or absf(d.x) > 700.0 or signf(d.x) != float(o.facing):
			continue
		if rng.randf() < DODGE[diff] * dt * 2.0:
			out.jump = true
			out.jump_held = rng.randf() < 0.5
			_jump_cool = 0.6
			return
