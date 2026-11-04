extends Node
## Headless checks for the simulation:
##   godot --headless --path . res://tests/test_sim.tscn
## Exits with code 1 when any check fails.

const World := preload("res://scripts/game/world.gd")
const Stickman := preload("res://scripts/game/stickman.gd")
const Rig := preload("res://scripts/game/rig.gd")
const AI := preload("res://scripts/game/ai.gd")
const Levels := preload("res://scripts/game/levels.gd")
const Weapons := preload("res://scripts/game/weapons.gd")

var failures := 0
var checks := 0


func _ready() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		only = arg
	var tests := [
		"test_ik", "test_walk_cycle", "test_props_settle", "test_nav_links", "test_punch_crate",
		"test_barrel_chain", "test_weapons", "test_grenade", "test_sword_deflect", "test_ragdoll",
		"test_knockdown_getup", "test_fall_death", "test_bots",
	]
	for t: String in tests:
		if only != "" and not t.contains(only):
			continue
		var before := failures
		call(t)
		print("%s %s" % ["ok  " if failures == before else "FAIL", t])
	print("%d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("  FAIL: ", msg)


func make_world(level: String, n: int, seed_value := 7) -> World:
	var w := World.new()
	var players := []
	for i in n:
		players.append({"id": i, "color": Color.RED})
	w.setup(level, players, seed_value)
	return w


## Skips the countdown so fighters can act.
func start(w: World) -> void:
	w.state = "fight"
	w.state_t = 0.0
	w.sudden_death = false


func run(w: World, seconds: float, inputs := {}) -> void:
	for i in int(seconds * 120.0):
		w.step(inputs)


func place(w: World, id: int, at: Vector2, facing := 1) -> Stickman:
	var f := w.fighter(id)
	f.pos = at
	f.vel = Vector2.ZERO
	f.facing = facing
	f.aim = Vector2(facing, 0)
	return f


func bone_error(j: Dictionary) -> float:
	var worst := 0.0
	for b: Array in Rig.BONES:
		var d: float = (j[b[0]] as Vector2).distance_to(j[b[1]])
		worst = maxf(worst, absf(d - float(b[2])))
	return worst


# --- Tests -----------------------------------------------------------------------------------

func test_ik() -> void:
	var a := Vector2.ZERO
	for t: Vector2 in [Vector2(10, 30), Vector2(0, 41), Vector2(30, 5), Vector2(-20, -10), Vector2(80, 0)]:
		var k := Rig.ik(a, t, 21.0, 21.0, -1.0)
		check(absf(k.length() - 21.0) < 0.01, "upper bone length for %s" % t)
		var reach := Rig.limit(a, t, 41.9)
		check(absf(k.distance_to(reach) - 21.0) < 0.05 or t.length() > 42.0, "lower bone length for %s" % t)
	# Knees bend forward, elbows below a forward-reaching arm.
	check(Rig.ik(Vector2.ZERO, Vector2(0, 38), 21, 21, -1.0).x > 0.0, "knee bends forward")
	check(Rig.ik(Vector2.ZERO, Vector2(20, 0), 14, 14, 1.0).y > 0.0, "elbow hangs below")
	# Every pose the fighters go through keeps bone lengths.
	var w := make_world("fabrika", 2)
	start(w)
	var f := place(w, 0, Vector2(150, 620))
	var worst := 0.0
	var plan := [{"move": 1.0}, {"move": 1.0, "attack": true}, {"jump": true, "jump_held": true}, {"down": true}, {"move": -1.0}]
	for step in plan:
		for i in 40:
			w.step({0: step})
			worst = maxf(worst, bone_error(f.rig.j))
	f.weapon = "shotgun"
	f.ammo = 5
	for i in 60:
		w.step({0: {"attack": i == 5, "aim": Vector2(1, -0.4)}})
		worst = maxf(worst, bone_error(f.rig.j))
	check(worst < 0.6, "bones keep their length while animating (worst %.2f)" % worst)


func test_walk_cycle() -> void:
	var w := make_world("catilar", 2)
	start(w)
	var f := place(w, 0, Vector2(490, 470))
	place(w, 1, Vector2(1160, 580), -1)
	w.props.clear()
	run(w, 0.5)
	var slides := 0
	var planted := 0
	var prev := {}
	for i in 240:
		w.step({0: {"move": 1.0 if i < 100 else 0.0}})
		for key in ["foot_n", "foot_f"]:
			var p: Vector2 = f.rig.j[key]
			if absf(p.y - 470.0) < 0.6 and prev.has(key) and absf((prev[key] as Vector2).y - 470.0) < 0.6:
				planted += 1
				if absf(p.x - (prev[key] as Vector2).x) > 1.6:
					slides += 1
			prev[key] = p
	check(f.pos.x > 700.0 and f.pos.x < 800.0, "ran to the right and stopped (x=%.0f)" % f.pos.x)
	check(planted > 100, "feet plant on the ground while running (%d)" % planted)
	check(slides < planted * 0.08, "planted feet don't skate (%d of %d)" % [slides, planted])
	var hip: Vector2 = f.rig.j.hip
	check(hip.y < 470.0 - 30.0 and hip.y > 470.0 - 42.0, "hip at a standing height (%.1f)" % (470.0 - hip.y))


func test_props_settle() -> void:
	for id: String in Levels.ORDER:
		var w := make_world(id, 4)
		run(w, 1.5)
		var lv := Levels.get_level(id)
		check(w.props.size() == lv.crates.size() + lv.barrels.size(), "%s keeps all its props (%d)" % [id, w.props.size()])
		for p in w.props:
			check(p.on_ground and p.vel.length() < 1.0, "%s: %s at %s rests" % [id, p.kind, p.rect.position])
			for r in w.solids:
				check(not p.rect.intersects(r), "%s: %s not inside a block" % [id, p.kind])
		for f: Stickman in w.fighters:
			check(f.on_ground and f.alive, "%s: fighter %d stands at spawn" % [id, f.id])
			for p in w.props:
				check(not f.hurt_rect().intersects(p.rect.grow(-2.0)), "%s: fighter %d spawns clear of props" % [id, f.id])


func test_nav_links() -> void:
	for id: String in Levels.ORDER:
		var w := make_world(id, 2)
		var nav = w.nav
		# Every surface can reach every other.
		var unreachable := []
		for a in nav.surfaces:
			for b in nav.surfaces:
				if a != b and nav.path(a, b, (a.x0 + a.x1) * 0.5).is_empty():
					unreachable.append("%d→%d" % [a.idx, b.idx])
		check(unreachable.is_empty(), "%s: every surface reachable (missing %s)" % [id, ", ".join(unreachable)])


func test_punch_crate() -> void:
	var w := make_world("fabrika", 2)
	start(w)
	w.props = w.props.filter(func(p) -> bool: return p.rect.get_center().distance_to(Vector2(200, 600)) < 30.0)
	check(w.props.size() == 1, "one crate left")
	var f := place(w, 0, Vector2(160, 620))
	place(w, 1, Vector2(1200, 620), -1)
	run(w, 0.3)
	for i in 6:
		w.step({0: {"attack": true}})
		run(w, 0.3)
	check(w.props.is_empty(), "three punches break the crate")
	check(w.pickups.size() == 1, "the crate drops a weapon")
	check(w.stats[0].crates == 1, "crate credited")
	run(w, 1.0)
	for i in 60:
		w.step({0: {"move": 1.0}})
	check(f.weapon != "", "walking over the weapon picks it up (%s)" % f.weapon)
	check(f.ammo > 0 or f.weapon == "sword", "picked-up weapon has ammo")


func test_barrel_chain() -> void:
	var w := make_world("fabrika", 2)
	start(w)
	w.props.clear()
	w.add_prop("barrel", Vector2(520, 395))
	w.add_prop("crate", Vector2(562, 395))
	w.add_prop("barrel", Vector2(605, 395))
	var a := place(w, 0, Vector2(820, 395), -1)
	var b := place(w, 1, Vector2(468, 395), 1)
	a.weapon = "pistol"
	a.ammo = 10
	run(w, 0.4)
	var explosions := 0
	var crates := 0
	w.step({0: {"attack": true, "aim": (Vector2(605, 373) - a.center()).normalized()}})
	for i in 200:
		w.step({0: {"aim": Vector2(-1, 0)}})
		for e: Dictionary in w.events:
			if e.type == "explosion":
				explosions += 1
			if e.type == "crate":
				crates += 1
				check(w.pickups.size() >= 1, "the crate dropped its weapon")
		w.events.clear()
	check(explosions == 2, "both barrels blew up (%d)" % explosions)
	check(w.props.is_empty() and crates == 1, "the crate between them broke")
	check(b.hp < 100.0, "fighter next to the barrels got hurt (hp %.0f)" % b.hp)
	check(a.hp == 100.0, "the shooter was out of range")
	check(w.stats[0].barrels == 2, "both barrels credited to the shooter (%d)" % w.stats[0].barrels)


func test_weapons() -> void:
	for type in ["pistol", "shotgun", "crossbow", "sword"]:
		var w := make_world("insaat", 2)
		start(w)
		w.props.clear()
		var a := place(w, 0, Vector2(100, 640), 1)
		var b := place(w, 1, Vector2({"sword": 140.0, "shotgun": 220.0}.get(type, 560.0), 640), -1)
		a.weapon = type
		a.ammo = int(Weapons.def(type).ammo)
		run(w, 0.3)
		w.step({0: {"attack": true}})
		run(w, 1.0)
		check(b.hp < 100.0, "%s hurts (hp %.0f)" % [type, b.hp])
		if type != "sword":
			check(a.ammo == int(Weapons.def(type).ammo) - 1, "%s used one round" % type)
	# Firing an empty gun throws it.
	var w2 := make_world("insaat", 2)
	start(w2)
	var c := place(w2, 0, Vector2(300, 640), 1)
	c.weapon = "pistol"
	c.ammo = 0
	w2.step({0: {"attack": true}})
	run(w2, 0.4)
	check(c.weapon == "", "empty gun gets thrown")


func test_grenade() -> void:
	var w := make_world("insaat", 2)
	start(w)
	w.props.clear()
	var a := place(w, 0, Vector2(200, 640), 1)
	var b := place(w, 1, Vector2(480, 640), -1)
	a.weapon = "grenade"
	a.ammo = 3
	run(w, 0.3)
	w.step({0: {"attack": true}})
	var exploded := false
	for i in 400:
		w.step({})
		for e: Dictionary in w.events:
			if e.type == "explosion":
				exploded = true
		w.events.clear()
	check(exploded, "grenade explodes")
	check(a.ammo == 2, "one grenade used (%d left)" % a.ammo)
	check(b.hp < 100.0 or not b.alive, "grenade thrown at range hurts the target (hp %.0f)" % b.hp)


func test_sword_deflect() -> void:
	var w := make_world("insaat", 2)
	start(w)
	w.props.clear()
	var a := place(w, 0, Vector2(300, 640), 1)
	var b := place(w, 1, Vector2(700, 640), -1)
	a.weapon = "pistol"
	a.ammo = 10
	b.weapon = "sword"
	b.ammo = -1
	run(w, 0.3)
	w.step({0: {"attack": true}, 1: {"attack": true}})
	var deflects := 0
	for i in 120:
		w.step({})
		for e: Dictionary in w.events:
			if e.type == "deflect":
				deflects += 1
		w.events.clear()
	check(deflects == 1, "the sword knocks the bullet back (%d)" % deflects)
	check(b.hp == 100.0, "the swordsman isn't hit")
	check(a.hp < 100.0, "the shooter takes their own bullet (hp %.0f)" % a.hp)


func test_ragdoll() -> void:
	var w := make_world("insaat", 2)
	start(w)
	w.props.clear()
	var f := place(w, 1, Vector2(640, 410), -1)
	run(w, 0.3)
	w.hit_fighter(f, 200.0, Vector2(-500, -400), 0, "pistol", f.center(), false)
	check(not f.alive and f.is_down(), "a killing blow ragdolls the body")
	var worst := 0.0
	for i in 480:
		w.step({})
		for b: Array in Rig.BONES:
			var d: float = (f.rig.ragdoll.p[b[0]] as Vector2).distance_to(f.rig.ragdoll.p[b[1]])
			worst = maxf(worst, absf(d - float(b[2])))
	check(worst < 3.0, "ragdoll keeps its bones (worst stretch %.2f)" % worst)
	var rd = f.rig.ragdoll
	for key: String in rd.p:
		var p: Vector2 = rd.p[key]
		check(not is_nan(p.x) and not is_nan(p.y), "ragdoll %s is finite" % key)
	check(rd.velocity().length() < 30.0, "the body comes to rest (%.1f)" % rd.velocity().length())
	var hip: Vector2 = rd.p.hip
	check(hip.y < 660.0, "body rests on a surface, not in the floor (hip y %.0f)" % hip.y)


func test_knockdown_getup() -> void:
	var w := make_world("insaat", 2)
	start(w)
	w.props.clear()
	w.add_prop("barrel", Vector2(330, 640))
	var f := place(w, 0, Vector2(400, 640), 1)
	place(w, 1, Vector2(1100, 640), -1)
	run(w, 0.3)
	f.hp = 200.0
	w.ignite(w.props[0], 1, 0.0)
	var downed := false
	for i in 120:
		w.step({})
		downed = downed or f.is_down()
	check(downed, "an explosion knocks the fighter off their feet")
	run(w, 4.0)
	check(f.alive and not f.is_down(), "the fighter gets back up")
	check(f.on_ground, "and stands on the ground (y %.0f)" % f.pos.y)
	for i in 60:
		w.step({0: {"move": 1.0}})
	check(f.vel.x > 100.0, "and can run again")


func test_fall_death() -> void:
	var w := make_world("fabrika", 2)
	start(w)
	var f := place(w, 0, Vector2(560, 400), 1)
	f.last_hitter = 1
	f.last_hit_time = w.time
	var killed := false
	for i in 240:
		w.step({})
		for e: Dictionary in w.events:
			if e.type == "kill" and e.victim == 0:
				killed = true
				check(e.killer == 1, "the last hitter gets the kill for a fall")
		w.events.clear()
	check(killed and not f.alive, "falling into the pit kills")
	check(w.state == "over" and w.winner == 1, "the last one standing wins the round")


func test_bots() -> void:
	var totals := {"rounds": 0, "ended": 0, "kills": 0, "falls": 0, "self_falls": 0, "crates": 0, "barrels": 0, "pickups": 0, "shots": 0, "length": 0.0}
	var seed_value := 11
	for id: String in Levels.ORDER:
		for k in 3:
			seed_value += 1
			var w := make_world(id, 4, seed_value)
			w.sudden_death = true
			var bots := []
			for i in 4:
				var b := AI.new()
				b.setup(i, [1, 2, 1, 2][i], seed_value * 10 + i)
				bots.append(b)
			var steps := 0
			while not w.finished and steps < 120 * 150:
				var inputs := {}
				for b in bots:
					inputs[b.id] = b.think(w, World.DT)
				w.step(inputs)
				steps += 1
				for e: Dictionary in w.events:
					match e.type:
						"kill":
							totals.kills += 1
							if e.weapon == "fall":
								totals.falls += 1
								if e.killer < 0 and not w.sudden:
									totals.self_falls += 1
						"crate":
							totals.crates += 1
						"pickup":
							totals.pickups += 1
						"explosion":
							totals.barrels += 1
				w.events.clear()
			totals.rounds += 1
			totals.length += steps / 120.0
			if w.finished:
				totals.ended += 1
			else:
				printerr("  round on %s (seed %d) did not finish: %d alive" % [id, seed_value, w.alive_fighters().size()])
	print("  bots: ", totals)
	check(totals.ended == totals.rounds, "every bot round ends (%d/%d)" % [totals.ended, totals.rounds])
	check(totals.crates >= totals.rounds * 2, "bots break crates (%d)" % totals.crates)
	check(totals.pickups >= totals.rounds * 2, "bots pick up weapons (%d)" % totals.pickups)
	check(totals.kills >= totals.rounds * 3 - 2, "bots kill each other (%d)" % totals.kills)
	check(totals.falls <= totals.kills * 0.45, "most deaths are fights, not falls (%d of %d)" % [totals.falls, totals.kills])
	check(totals.self_falls <= totals.rounds * 0.25, "bots rarely walk off ledges on their own (%d)" % totals.self_falls)
	check(totals.length / totals.rounds < 80.0, "rounds take under 80 s on average (%.1f)" % (totals.length / totals.rounds))
