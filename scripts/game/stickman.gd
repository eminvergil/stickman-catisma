extends RefCounted
## One fighter: running, jumping, crouching, health, the held weapon and its attacks. The world
## (world.gd) moves the body through the level, spawns the shots and applies the hits; the rig
## (rig.gd) turns all of this into a moving body.
##
## `pos` is the point on the ground between the feet. Input is a Dictionary:
## {"move": -1..1, "jump": pressed, "jump_held", "down", "attack": pressed, "attack_held",
##  "throw": pressed, "aim": Vector2 (zero = aim where you face)}.

const Rig := preload("res://scripts/game/rig.gd")
const Weapons := preload("res://scripts/game/weapons.gd")

const RUN := 300.0
const CROUCH_RUN := 110.0
const ACCEL := 2600.0
const DECEL := 3400.0
const AIR_ACCEL := 1700.0
const GRAVITY := 2300.0
const JUMP_V := 800.0
const MAX_FALL := 1150.0
const WIDTH := 20.0
const HEIGHT := 78.0
const CROUCH_HEIGHT := 54.0
const MAX_HP := 100.0
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
## Jab, cross, hook: animation length and the time before the next punch may start.
const PUNCH_TIME := [0.24, 0.24, 0.36]
const PUNCH_COOLDOWN := [0.2, 0.2, 0.42]
const SWORD_TIME := 0.38
const THROW_TIME := 0.42
## Knockback that throws a fighter off their feet into a ragdoll.
const KNOCKDOWN := 520.0

var id := 0
var color := Color.WHITE
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var facing := 1
## Unit vector in world space.
var aim := Vector2.RIGHT
var aim_explicit := false
var on_ground := false
var ground_oneway := false
var hit_wall := false
var crouching := false
var hp := MAX_HP
var alive := true
var gone := false
var weapon := ""
var ammo := 0
var cooldown := 0.0
var attack_kind := ""
var attack_t := -1.0
var attack_len := 0.0
var attack_done := false
var combo_step := 0
var combo_timer := 0.0
## Fighters already hit by the current swing.
var hit_set := {}
var recoil := 0.0
var hurt_t := 0.0
var stun := 0.0
var down_t := 0.0
var getup_t := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var drop_t := 0.0
var land_speed := 0.0
var pickup_block := 0.0
var last_hitter := -1
var last_hit_time := -100.0
var last_hit_weapon := ""
## Knockback received during the current tick, to decide on knockdowns.
var tick_knock := Vector2.ZERO
var rig := Rig.new()


func setup(fighter_id: int, at: Vector2, col: Color) -> void:
	id = fighter_id
	pos = at
	color = col
	facing = 1 if at.x < 640.0 else -1
	aim = Vector2(facing, 0)
	rig.update(self, 0.0)


func height() -> float:
	return CROUCH_HEIGHT if crouching else HEIGHT


func is_down() -> bool:
	return rig.ragdoll != null


## Chest height, where aim assist and explosions measure from.
func center() -> Vector2:
	if rig.ragdoll:
		return rig.ragdoll.center()
	return pos - Vector2(0, height() * 0.58)


## Box that melee attacks and pickups test against.
func hurt_rect() -> Rect2:
	if rig.ragdoll:
		return rig.ragdoll.bounds()
	return Rect2(pos.x - WIDTH * 0.5, pos.y - height() - 4.0, WIDTH, height() + 4.0)


func aim_local() -> Vector2:
	return Vector2(aim.x * facing, aim.y)


func attack_progress() -> float:
	if attack_t < 0.0 or attack_len <= 0.0:
		return -1.0
	return clampf(attack_t / attack_len, 0.0, 1.0)


func is_gun() -> bool:
	return weapon != "" and Weapons.def(weapon).kind == "gun"


func update(w: RefCounted, inp: Dictionary, dt: float) -> void:
	if not alive:
		return
	_tick(dt)
	if is_down():
		_update_down(w, dt)
		return
	var can_act: bool = w.can_act() and getup_t <= 0.0
	var move: float = clampf(float(inp.get("move", 0.0)), -1.0, 1.0) if can_act else 0.0
	if stun > 0.0:
		move *= 0.25

	# Aim and facing.
	var explicit: Vector2 = inp.get("aim", Vector2.ZERO)
	aim_explicit = explicit.length_squared() > 0.01 and can_act
	if aim_explicit:
		aim = explicit.normalized()
		if absf(aim.x) > 0.06:
			facing = 1 if aim.x > 0.0 else -1
	else:
		var locked := attack_t >= 0.0 and attack_kind in ["punch", "sword"]
		if absf(move) > 0.2 and not locked:
			facing = 1 if move > 0.0 else -1
		aim = w.assist_aim(self)

	# Crouch, but only stand up where there's room.
	var want_crouch: bool = can_act and bool(inp.get("down", false)) and on_ground
	want_crouch = want_crouch or getup_t > 0.0
	if crouching and not want_crouch and not w.can_stand(self):
		want_crouch = true
	crouching = want_crouch

	# Running.
	var target := move * (CROUCH_RUN if crouching else RUN)
	if on_ground:
		var speeding_up := absf(target) > absf(vel.x) and (signf(target) == signf(vel.x) or vel.x == 0.0)
		var a := ACCEL if speeding_up else DECEL
		if stun > 0.0:
			a *= 0.35
		vel.x = move_toward(vel.x, target, a * dt)
	elif absf(vel.x) <= RUN + 1.0 or signf(target) != signf(vel.x):
		vel.x = move_toward(vel.x, target, AIR_ACCEL * dt * (0.3 if stun > 0.0 else 1.0))
	else:
		vel.x = move_toward(vel.x, signf(vel.x) * RUN, 260.0 * dt)

	# Jumping, and dropping through a platform with ↓ + jump.
	if on_ground:
		coyote = COYOTE
	if can_act and inp.get("jump", false):
		jump_buffer = JUMP_BUFFER
	if jump_buffer > 0.0 and coyote > 0.0 and stun <= 0.0:
		jump_buffer = 0.0
		coyote = 0.0
		if inp.get("down", false) and ground_oneway:
			drop_t = 0.22
			vel.y = 60.0
		else:
			vel.y = -JUMP_V
			w.sound("jump", pos, -6.0)
		on_ground = false
		crouching = false
	if vel.y < 0.0 and not inp.get("jump_held", false):
		vel.y += GRAVITY * 1.4 * dt
	vel.y = minf(vel.y + GRAVITY * dt, MAX_FALL)

	var was_ground := on_ground
	var falling := vel.y
	w.move_fighter(self, dt)
	if on_ground and not was_ground:
		land_speed = falling
		if falling > 450.0:
			w.sound("land", pos, -8.0)
			w.dust(pos, int(falling / 180.0))

	# Attacks.
	if can_act and attack_t < 0.0:
		if inp.get("throw", false) and weapon != "":
			if weapon == "grenade":
				_start_attack(w)
			else:
				_start(w, "throw", THROW_TIME, 0.3)
		elif cooldown <= 0.0 and (inp.get("attack", false) or inp.get("attack_held", false)):
			_start_attack(w)
	elif can_act and attack_kind == "punch" and cooldown <= 0.0 and inp.get("attack", false):
		_start_attack(w)
	_update_attack(w, dt)
	rig.update(self, dt)


func _tick(dt: float) -> void:
	cooldown = maxf(0.0, cooldown - dt)
	combo_timer = maxf(0.0, combo_timer - dt)
	recoil = maxf(0.0, recoil - dt * 7.0)
	hurt_t = maxf(0.0, hurt_t - dt)
	stun = maxf(0.0, stun - dt)
	getup_t = maxf(0.0, getup_t - dt)
	coyote = maxf(0.0, coyote - dt)
	jump_buffer = maxf(0.0, jump_buffer - dt)
	drop_t = maxf(0.0, drop_t - dt)
	pickup_block = maxf(0.0, pickup_block - dt)


func _start(w: RefCounted, kind: String, length: float, cool: float) -> void:
	attack_kind = kind
	attack_t = 0.0
	attack_len = length
	attack_done = false
	cooldown = cool
	hit_set = {}
	if kind == "throw":
		w.sound("swing", pos, -4.0)


func _start_attack(w: RefCounted) -> void:
	if weapon == "":
		combo_step = (combo_step + 1) % 3 if combo_timer > 0.0 else 0
		combo_timer = 0.55
		_start(w, "punch", PUNCH_TIME[combo_step], PUNCH_COOLDOWN[combo_step])
		w.sound("swing", pos, -6.0 if combo_step < 2 else -2.0)
		return
	var d := Weapons.def(weapon)
	match d.kind:
		"gun":
			if ammo <= 0:
				w.sound("empty", pos, -4.0)
				_start(w, "throw", THROW_TIME, 0.3)
				return
			_start(w, "fire", 0.18, d.rate)
			ammo -= 1
			recoil = 1.0
			attack_done = true
			w.fire(self)
		"melee":
			# A chop from above first; quick follow-ups alternate with an upward cut.
			combo_step = (combo_step + 1) % 2 if combo_timer > 0.0 else 0
			combo_timer = 0.7
			_start(w, "sword", SWORD_TIME, d.rate)
			w.sound("sword", pos, -2.0)
		"throw":
			_start(w, "grenade", THROW_TIME, d.rate)


## Applies the hit, the throw or the release at the right moment of the animation.
func _update_attack(w: RefCounted, dt: float) -> void:
	if attack_t < 0.0:
		return
	attack_t += dt
	var t := attack_progress()
	match attack_kind:
		"punch":
			if not attack_done and t >= 0.22:
				attack_done = true
				w.punch_hit(self, combo_step == 2)
		"sword":
			if t >= 0.2 and t <= 0.55:
				w.sword_hit(self)
		"grenade":
			if not attack_done and t >= 0.45:
				attack_done = true
				w.throw_grenade(self)
				ammo -= 1
				if ammo <= 0:
					weapon = ""
		"throw":
			if not attack_done and t >= 0.45:
				attack_done = true
				if weapon != "":
					w.throw_weapon(self)
	if attack_t >= attack_len:
		attack_t = -1.0
		attack_kind = ""


## Takes a hit. Returns true when it was the killing blow.
func damage(amount: float, knock: Vector2, attacker: int, weapon_name: String, now: float) -> bool:
	if not alive:
		return false
	hp -= amount
	hurt_t = 0.25
	stun = maxf(stun, 0.08 + knock.length() / 3500.0)
	tick_knock += knock
	if is_down():
		rig.ragdoll.push(center(), knock * 0.8, 60.0)
	else:
		vel += knock
		if knock.y < -150.0:
			on_ground = false
	if attacker >= 0 and attacker != id:
		last_hitter = attacker
		last_hit_time = now
		last_hit_weapon = weapon_name
	if attack_kind == "punch":
		attack_t = -1.0
		attack_kind = ""
	return hp <= 0.0


func knock_down(extra: Vector2) -> void:
	if is_down() or not alive:
		return
	var rd := rig.start_ragdoll(vel)
	rd.push(center(), extra * 0.35, 80.0)
	rd.kick("head", extra * 0.25)
	down_t = 0.9
	attack_t = -1.0
	attack_kind = ""
	crouching = false


func die(impulse: Vector2) -> void:
	alive = false
	hp = 0.0
	attack_t = -1.0
	attack_kind = ""
	if not is_down():
		var rd := rig.start_ragdoll(vel * 0.6)
		rd.push(center(), impulse * 0.6, 70.0)
		rd.kick("head", impulse * 0.3)


## Lying in a ragdoll: follow it, and stand back up once it has settled on the ground.
func _update_down(w: RefCounted, dt: float) -> void:
	var rd := rig.ragdoll
	down_t -= dt
	var hip: Vector2 = rd.p.hip
	pos = hip + Vector2(0, 30)
	vel = rd.velocity()
	rig.update(self, dt)
	if down_t > 0.0 or (vel.length() > 90.0 and down_t > -1.5):
		return
	# Stand up on the surface under whichever part of the body lies lowest on something.
	var ground_y := INF
	var stand_x := hip.x
	for key in ["hip", "neck", "foot_n", "foot_f", "head"]:
		var p: Vector2 = rd.p[key]
		var gy: float = w.ground_below(p - Vector2(0, 12), 40.0)
		if gy != INF and (ground_y == INF or absf(gy - hip.y) < absf(ground_y - hip.y)):
			ground_y = gy
			stand_x = p.x
	if ground_y == INF and down_t < -1.0:
		ground_y = w.ground_below(hip, 400.0)
	if ground_y == INF:
		return
	hip = Vector2(stand_x, hip.y)
	pos = Vector2(hip.x, ground_y)
	pos.x = w.free_x(pos, WIDTH, CROUCH_HEIGHT)
	vel = Vector2.ZERO
	on_ground = true
	var head: Vector2 = rd.p.head
	facing = 1 if head.x >= hip.x else -1
	rig.end_ragdoll(pos, facing)
	down_t = 0.0
	getup_t = 0.32
	stun = 0.32
	crouching = true
