extends Node2D
## Draws a World. The backdrop and the platforms sit on their own layer that is only redrawn
## when the level changes; crates, barrels, weapons, fighters, shots and effects are redrawn
## every frame on top.

const World := preload("res://scripts/game/world.gd")
const Rig := preload("res://scripts/game/rig.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const Levels := preload("res://scripts/game/levels.gd")
const Stickman := preload("res://scripts/game/stickman.gd")
const UI := preload("res://scripts/ui.gd")

const OUTLINE := Color("#0f0f14")
const LIMB := 4.6
const BIG := Rect2(-1400, -900, 4080, 2520)

var world: World
## Fighter id -> short tag shown over the head ("P1", "B3").
var tags := {}
var show_tags := true
## World position of player one's crosshair; x < -999 hides it.
var crosshair := Vector2(-9999, 0)
var crosshair_color := Color.WHITE
## Where the view sits before screen shake is added.
var origin := Vector2.ZERO
var _back: Node2D
var _front: Node2D
var _time := 0.0
var _shake := 0.0
var _flash := 0.0


func _ready() -> void:
	_back = Node2D.new()
	add_child(_back)
	_back.draw.connect(_draw_back)
	_front = Node2D.new()
	add_child(_front)
	_front.draw.connect(_draw_front)


func set_world(w: World) -> void:
	world = w
	_back.queue_redraw()
	_front.queue_redraw()


func add_shake(amount: float) -> void:
	if Settings.get_value("shake"):
		_shake = minf(_shake + amount, 20.0)


func flash(amount: float) -> void:
	_flash = maxf(_flash, amount)


func _process(delta: float) -> void:
	_time += delta
	_shake = maxf(0.0, _shake - delta * 45.0)
	if _shake > 0.2:
		position = origin + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 0.55
	else:
		position = origin
	_flash = maxf(0.0, _flash - delta * 3.5)
	_front.queue_redraw()


# --- Helpers ---------------------------------------------------------------------------------

static func vgrad(ci: CanvasItem, r: Rect2, stops: Array) -> void:
	## `stops` is [[y_fraction, Color], ...] from top to bottom.
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		var y0: float = r.position.y + r.size.y * float(a[0])
		var y1: float = r.position.y + r.size.y * float(b[0])
		var pts := PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)])
		ci.draw_polygon(pts, PackedColorArray([a[1], a[1], b[1], b[1]]))


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color) -> void:
	ci.draw_set_transform(c, 0.0, Vector2(1.0, ry / maxf(rx, 0.01)))
	ci.draw_circle(Vector2.ZERO, rx, color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func box(ci: CanvasItem, r: Rect2, fill: Color, top: Color, edge := OUTLINE, top_h := 4.0) -> void:
	ci.draw_rect(r, fill)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, minf(top_h, r.size.y))), top)
	ci.draw_rect(r, edge, false, 2.0)


# --- Backdrops -------------------------------------------------------------------------------

func _draw_back() -> void:
	if world == null:
		return
	var ci := _back
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world.level_id)
	match world.level_id:
		"fabrika":
			_bg_factory(ci, rng)
		"catilar":
			_bg_city(ci, rng)
		"insaat":
			_bg_site(ci, rng)
		"kopru":
			_bg_bridge(ci, rng)
	_draw_platforms(ci, rng)


func _bg_factory(ci: CanvasItem, rng: RandomNumberGenerator) -> void:
	vgrad(ci, BIG, [[0.0, Color("#1c1430")], [0.36, Color("#3b2350")], [0.53, Color("#c2563a")], [0.6, Color("#f2a65a")], [1.0, Color("#f2a65a")]])
	ci.draw_circle(Vector2(905, 440), 150.0, Color(1.0, 0.82, 0.5, 0.12))
	ci.draw_circle(Vector2(905, 440), 92.0, Color("#ffd27a"))
	# Smoke stacks and a saw-tooth factory hall far behind.
	var far := Color("#5a2c4a")
	for c: Array in [[110, 240, 26], [190, 300, 20], [1030, 210, 30], [1110, 280, 22]]:
		ci.draw_rect(Rect2(c[0], c[1], c[2], 720 - c[1]), far)
		ci.draw_rect(Rect2(c[0] - 3, c[1], c[2] + 6, 8), far.darkened(0.15))
		for k in 7:
			var p := Vector2(c[0] + c[2] * 0.5 + k * 22.0 + rng.randf_range(-6, 6), c[1] - 14.0 - k * 16.0)
			ci.draw_circle(p, 10.0 + k * 3.5, Color(0.42, 0.3, 0.42, 0.22 - k * 0.025))
	var hall := PackedVector2Array([Vector2(-200, 720), Vector2(-200, 430)])
	var x := -200.0
	while x < 1480.0:
		hall.append(Vector2(x + 44.0, 400.0))
		hall.append(Vector2(x + 44.0, 430.0))
		x += 44.0
	hall.append(Vector2(1480, 720))
	ci.draw_colored_polygon(hall, Color("#4a2440"))
	for i in 26:
		var wx := -180.0 + i * 64.0
		ci.draw_rect(Rect2(wx, 470, 30, 22), Color(1.0, 0.75, 0.4, 0.25 if rng.randf() < 0.5 else 0.08))
	# Silos and pipes closer in.
	var near := Color("#331a33")
	for s: Array in [[640, 64, 330], [720, 52, 360]]:
		ci.draw_rect(Rect2(s[0], s[2], s[1], 720 - s[2]), near)
		ellipse(ci, Vector2(s[0] + s[1] * 0.5, s[2]), s[1] * 0.5, 10.0, near)
	ci.draw_line(Vector2(-200, 560), Vector2(1480, 560), Color("#2b1530"), 10.0)
	ci.draw_line(Vector2(-200, 548), Vector2(1480, 548), Color("#2b1530"), 4.0)
	# Overhead crane rail with a hanging hook.
	ci.draw_rect(Rect2(-200, 128, 1680, 12), Color("#2a1a2c"))
	for i in 30:
		ci.draw_line(Vector2(-200 + i * 56, 140), Vector2(-172 + i * 56, 128), Color("#3b2a3e"), 2.0)
	ci.draw_rect(Rect2(820, 140, 40, 16), Color("#2a1a2c"))
	ci.draw_line(Vector2(840, 156), Vector2(840, 214), Color("#1a1018"), 2.0)
	ci.draw_arc(Vector2(840, 222), 8.0, -PI * 0.5, PI, 10, Color("#1a1018"), 3.0, true)
	# The pit between the floors.
	vgrad(ci, Rect2(500, 620, 280, 420), [[0.0, Color("#140d18")], [0.4, Color("#050307")], [1.0, Color.BLACK]])


func _bg_city(ci: CanvasItem, rng: RandomNumberGenerator) -> void:
	vgrad(ci, BIG, [[0.0, Color("#05071a")], [0.35, Color("#0b1030")], [0.55, Color("#1d2858")], [1.0, Color("#2f3b6e")]])
	for i in 110:
		var p := Vector2(rng.randf_range(-300, 1580), rng.randf_range(-200, 380))
		ci.draw_circle(p, rng.randf_range(0.6, 1.6), Color(1, 1, 1, rng.randf_range(0.25, 0.9)))
	ci.draw_circle(Vector2(1090, 118), 54.0, Color(0.95, 0.93, 0.8, 0.08))
	ci.draw_circle(Vector2(1090, 118), 34.0, Color("#f2efd9"))
	ci.draw_circle(Vector2(1080, 110), 7.0, Color("#d9d5bd"))
	ci.draw_circle(Vector2(1100, 128), 5.0, Color("#d9d5bd"))
	ci.draw_circle(Vector2(1097, 104), 3.0, Color("#d9d5bd"))
	for layer in 2:
		var col := Color("#141a3a") if layer == 0 else Color("#0c1029")
		var x := -300.0
		while x < 1600.0:
			var w := rng.randf_range(44, 100)
			var top := rng.randf_range(300, 470) if layer == 0 else rng.randf_range(400, 560)
			ci.draw_rect(Rect2(x, top, w, 900), col)
			if rng.randf() < 0.3:
				ci.draw_line(Vector2(x + w * 0.5, top), Vector2(x + w * 0.5, top - 26), col, 2.0)
			for wy in range(int(top) + 10, 760, 16):
				for wx in range(int(x) + 6, int(x + w) - 6, 11):
					if rng.randf() < (0.12 if layer == 0 else 0.18):
						ci.draw_rect(Rect2(wx, wy, 4, 6), Color(1.0, 0.84, 0.48, 0.35 if layer == 0 else 0.55))
			x += w + rng.randf_range(2, 14)
	# Neon billboard over the right-hand roof.
	ci.draw_line(Vector2(1080, 465), Vector2(1080, 580), Color("#2a2f44"), 5.0)
	ci.draw_line(Vector2(1200, 465), Vector2(1200, 580), Color("#2a2f44"), 5.0)
	ci.draw_rect(Rect2(1058, 372, 164, 84), Color("#141526"))
	ci.draw_rect(Rect2(1058, 372, 164, 84), Color("#ff4fa3"), false, 3.0)
	UI.draw_text(ci, "ÇATIŞMA", Vector2(1140, 428), 34, Color("#ff7cc0"), 0)
	ci.draw_rect(Rect2(1054, 368, 172, 92), Color(1.0, 0.3, 0.64, 0.18), false, 6.0)
	# Water tower legs and the antenna.
	for lx in [552.0, 728.0]:
		ci.draw_line(Vector2(lx, 367), Vector2(lx - 8.0 * signf(lx - 640.0), 470), Color("#2b2430"), 6.0)
	ci.draw_line(Vector2(560, 420), Vector2(720, 400), Color("#2b2430"), 3.0)
	ci.draw_line(Vector2(560, 400), Vector2(720, 420), Color("#2b2430"), 3.0)
	ci.draw_line(Vector2(640, 252), Vector2(640, 355), Color("#2b2430"), 4.0)
	ci.draw_line(Vector2(640, 240), Vector2(640, 150), Color("#3a3f55"), 3.0)
	ci.draw_line(Vector2(626, 180), Vector2(654, 180), Color("#3a3f55"), 2.0)
	ci.draw_line(Vector2(630, 200), Vector2(650, 200), Color("#3a3f55"), 2.0)


func _bg_site(ci: CanvasItem, rng: RandomNumberGenerator) -> void:
	vgrad(ci, BIG, [[0.0, Color("#3d86c6")], [0.4, Color("#62ade3")], [0.6, Color("#bfe3f5")], [1.0, Color("#d8eef8")]])
	ci.draw_circle(Vector2(170, 112), 80.0, Color(1.0, 0.97, 0.8, 0.18))
	ci.draw_circle(Vector2(170, 112), 42.0, Color("#fff6cf"))
	for c: Array in [[360, 120, 1.0], [820, 80, 1.3], [1140, 170, 0.9], [-80, 220, 1.1]]:
		var at := Vector2(c[0], c[1])
		var k: float = c[2]
		for b: Array in [[0, 0, 26], [28, 6, 20], [-26, 8, 18], [12, -12, 18], [50, 12, 14]]:
			ci.draw_circle(at + Vector2(b[0], b[1]) * k, b[2] * k, Color(1, 1, 1, 0.88))
	var x := -300.0
	while x < 1600.0:
		var w := rng.randf_range(50, 110)
		var top := rng.randf_range(380, 520)
		ci.draw_rect(Rect2(x, top, w, 400), Color("#a9bfd1"))
		x += w + rng.randf_range(0, 10)
	# A tower crane on the skyline.
	var crane := Color("#7d93a8")
	ci.draw_line(Vector2(1010, 640), Vector2(1010, 110), crane, 8.0)
	for y in range(130, 640, 34):
		ci.draw_line(Vector2(1006, y), Vector2(1014, y + 34), crane.darkened(0.15), 2.0)
	ci.draw_line(Vector2(760, 120), Vector2(1250, 120), crane, 7.0)
	ci.draw_line(Vector2(1010, 70), Vector2(780, 120), crane, 2.0)
	ci.draw_line(Vector2(1010, 70), Vector2(1240, 120), crane, 2.0)
	ci.draw_line(Vector2(1010, 70), Vector2(1010, 110), crane, 5.0)
	ci.draw_rect(Rect2(1180, 110, 50, 26), crane.darkened(0.2))
	ci.draw_line(Vector2(860, 124), Vector2(860, 238), Color("#4a5563"), 2.0)
	ci.draw_arc(Vector2(860, 246), 8.0, -PI * 0.5, PI, 10, Color("#4a5563"), 3.0, true)
	# Void off both ends of the ground slab.
	vgrad(ci, Rect2(-400, 640, 460, 400), [[0.0, Color("#4a3a2c")], [0.3, Color("#1a130d")], [1.0, Color.BLACK]])
	vgrad(ci, Rect2(1220, 640, 460, 400), [[0.0, Color("#4a3a2c")], [0.3, Color("#1a130d")], [1.0, Color.BLACK]])


func _bg_bridge(ci: CanvasItem, rng: RandomNumberGenerator) -> void:
	vgrad(ci, BIG, [[0.0, Color("#1f1035")], [0.38, Color("#4a2456")], [0.5, Color("#c2496a")], [0.58, Color("#ff8a5c")], [0.62, Color("#ffb36b")], [1.0, Color("#ffb36b")]])
	for layer in 2:
		if layer == 1:
			ci.draw_circle(Vector2(640, 560), 150.0, Color(1.0, 0.8, 0.5, 0.15))
			ci.draw_circle(Vector2(640, 560), 84.0, Color("#ffd58f"))
		var pts := PackedVector2Array([Vector2(-400, 640)])
		var x := -400.0
		var base := 520.0 if layer == 0 else 560.0
		while x <= 1700.0:
			pts.append(Vector2(x, base - rng.randf_range(20, 110 if layer == 0 else 70)))
			x += rng.randf_range(70, 150)
		pts.append(Vector2(1700, 640))
		ci.draw_colored_polygon(pts, Color("#6b2f5a") if layer == 0 else Color("#4a1f45"))
	vgrad(ci, Rect2(-1400, 600, 4080, 1000), [[0.0, Color("#3d3f7d")], [0.15, Color("#26295a")], [1.0, Color("#0d1030")]])
	for i in 9:
		var y := 612.0 + i * 9.0
		var w := 150.0 - i * 13.0
		ci.draw_line(Vector2(640 - w, y), Vector2(640 + w, y), Color(1.0, 0.72, 0.45, 0.45 - i * 0.04), 2.0)
	# Bridge towers, piers and the cables.
	var steel := Color("#a83c2c")
	for t: Array in [[312, 428], [852, 968]]:
		for lx: float in t:
			ci.draw_rect(Rect2(lx - 7, 250, 14, 470), steel)
			ci.draw_rect(Rect2(lx - 7, 250, 4, 470), steel.lightened(0.15))
		ci.draw_rect(Rect2(t[0] - 7, 248, t[1] - t[0] + 14, 12), steel.darkened(0.2))
		ci.draw_line(Vector2(t[0], 270), Vector2(t[1], 390), steel.darkened(0.25), 4.0)
		ci.draw_line(Vector2(t[1], 270), Vector2(t[0], 390), steel.darkened(0.25), 4.0)
	var cable := Color("#2a1a2a")
	for seg: Array in [[Vector2(320, 252), Vector2(-40, 520)], [Vector2(420, 252), Vector2(565, 520)], [Vector2(860, 252), Vector2(715, 520)], [Vector2(960, 252), Vector2(1320, 520)], [Vector2(428, 256), Vector2(852, 256)]]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var sag := 60.0 if absf(a.y - b.y) < 10.0 else 30.0
		var pts := PackedVector2Array()
		for k in 21:
			var t := k / 20.0
			pts.append(a.lerp(b, t) + Vector2(0, sin(PI * t) * sag))
		ci.draw_polyline(pts, cable, 2.5, true)
	for hx in [580.0, 640.0, 700.0]:
		ci.draw_line(Vector2(hx, 256 + sin(PI * (hx - 428.0) / 424.0) * 60.0), Vector2(hx, 330), cable, 1.5)
	for px in [180.0, 1100.0]:
		ci.draw_rect(Rect2(px - 5, 312, 10, 210), Color("#3d2d38"))
	# The boat under the gap.
	ci.draw_colored_polygon(PackedVector2Array([Vector2(582, 616), Vector2(698, 616), Vector2(684, 642), Vector2(596, 642)]), Color("#5a3a24"))
	ci.draw_line(Vector2(590, 628), Vector2(690, 628), Color("#7a5232"), 2.0)
	ci.draw_line(Vector2(640, 610), Vector2(640, 560), Color("#4a3020"), 3.0)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(642, 562), Vector2(672, 596), Vector2(642, 598)]), Color("#e8dcc0"))


# --- Platforms -------------------------------------------------------------------------------

func _draw_platforms(ci: CanvasItem, rng: RandomNumberGenerator) -> void:
	var id := world.level_id
	var lv := Levels.get_level(id)
	for s: Array in lv.solids:
		var r := Rect2(s[0], s[1], s[2], s[3])
		match id:
			"fabrika":
				if r.size.y >= 90.0:
					r.size.y += 300.0
					box(ci, r, Color("#4a4552"), Color("#76707f"))
					for k in range(int(r.position.x) + 50, int(r.end.x), 60):
						ci.draw_line(Vector2(k, r.position.y + 5), Vector2(k, 720), Color("#3a3642"), 2.0)
					ci.draw_line(Vector2(r.position.x, r.position.y + 30), Vector2(r.end.x, r.position.y + 30), Color("#3a3642"), 2.0)
					# Hazard stripes along the edge of the pit.
					var edge := r.end.x if r.end.x < 640.0 else r.position.x
					var inward := -1.0 if r.end.x < 640.0 else 1.0
					for k in 4:
						var x0 := edge + inward * (k * 12.0)
						ci.draw_colored_polygon(PackedVector2Array([
							Vector2(x0, r.position.y), Vector2(x0 + inward * 6.0, r.position.y),
							Vector2(x0 + inward * 12.0, r.position.y + 6.0), Vector2(x0 + inward * 6.0, r.position.y + 6.0),
						]), Color("#f2c230"))
				else:
					box(ci, r, Color("#5d6573"), Color("#8f98a6"))
					ci.draw_circle(r.get_center() + Vector2(0, 4), 11.0, Color("#2a2e36"))
					ci.draw_circle(r.get_center() + Vector2(0, 4), 8.0, Color("#d9d3c0"))
					ci.draw_line(r.get_center() + Vector2(0, 4), r.get_center() + Vector2(5, -1), Color("#c0392b"), 2.0)
					for c in [Vector2(6, 10), Vector2(r.size.x - 6, 10), Vector2(6, r.size.y - 6), Vector2(r.size.x - 6, r.size.y - 6)]:
						ci.draw_circle(r.position + c, 2.0, Color("#3a3f4a"))
			"catilar":
				if r.size.y >= 100.0:
					r.size.y += 300.0
					box(ci, r, Color("#3a2c33"), Color("#6b5560"), OUTLINE, 7.0)
					for wy in range(int(r.position.y) + 26, 760, 42):
						for wx in range(int(r.position.x) + 22, int(r.end.x) - 30, 50):
							var lit := rng.randf() < 0.35
							ci.draw_rect(Rect2(wx, wy, 22, 26), Color("#ffcf6a", 0.85) if lit else Color("#1c1622"))
							ci.draw_rect(Rect2(wx, wy, 22, 26), Color("#22181e"), false, 2.0)
				else:
					box(ci, r, Color("#7d8691"), Color("#a5aeb8"))
					var c := r.get_center() + Vector2(0, 3)
					ci.draw_circle(c, minf(r.size.x, r.size.y) * 0.32, Color("#3b4048"))
					for k in 3:
						var a := _time * 0.0 + k * TAU / 3.0
						ci.draw_line(c, c + Vector2.from_angle(a) * minf(r.size.x, r.size.y) * 0.3, Color("#9aa3ad"), 2.0)
			"insaat":
				if r.size.x > 800.0:
					r.size.y += 300.0
					box(ci, r, Color("#7a6248"), Color("#9b7d5a"), OUTLINE, 6.0)
					for k in 60:
						ci.draw_circle(Vector2(rng.randf_range(r.position.x + 6, r.end.x - 6), rng.randf_range(r.position.y + 12, 715)), rng.randf_range(1.5, 3.5), Color("#5e4a36"))
				elif r.size.x >= 90.0:
					box(ci, r, Color("#8d8f94"), Color("#b0b2b6"))
					ci.draw_line(r.position + Vector2(20, 12), r.position + Vector2(34, 30), Color("#6d6f74"), 1.5)
					ci.draw_line(r.position + Vector2(70, 18), r.position + Vector2(60, 40), Color("#6d6f74"), 1.5)
					UI.draw_text(ci, "BETON", r.get_center() + Vector2(0, 9), 14, Color("#5a5c61"), 0)
				else:
					ci.draw_rect(r, Color("#a8473a"))
					for row in int(r.size.y / 8.0):
						var y := r.position.y + row * 8.0
						ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("#6e2a22"), 1.5)
						var off := 7.0 if row % 2 == 0 else 0.0
						for bx in range(int(r.position.x + off), int(r.end.x), 14):
							ci.draw_line(Vector2(bx, y), Vector2(bx, y + 8), Color("#6e2a22"), 1.5)
					ci.draw_rect(r, OUTLINE, false, 2.0)
			"kopru":
				if r.size.y >= 100.0:
					r.size.y += 300.0
					box(ci, r, Color("#3a2a35"), Color("#557a3a"), OUTLINE, 7.0)
					for k in 14:
						var p := Vector2(rng.randf_range(r.position.x + 10, r.end.x - 10), rng.randf_range(r.position.y + 20, 700))
						ci.draw_line(p, p + Vector2(rng.randf_range(-16, 16), rng.randf_range(6, 18)), Color("#2b1f28"), 2.0)
				else:
					box(ci, r, Color("#454a5c"), Color("#7a8299"))
					ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Color("#1a1c26"), 3.0)
					for px in range(int(r.position.x) + 12, int(r.end.x), 30):
						ci.draw_line(Vector2(px, r.position.y), Vector2(px, r.position.y - 22), Color("#7a2c22"), 2.0)
					ci.draw_line(Vector2(r.position.x, r.position.y - 22), Vector2(r.end.x, r.position.y - 22), Color("#b8432f"), 3.0)
					var broken := r.end.x if r.position.x < 640.0 else r.position.x
					var d := 1.0 if r.position.x < 640.0 else -1.0
					ci.draw_colored_polygon(PackedVector2Array([Vector2(broken, r.position.y), Vector2(broken + d * 8, r.position.y + 5), Vector2(broken - d * 2, r.end.y + 6), Vector2(broken - d * 6, r.end.y)]), Color("#454a5c"))
					ci.draw_line(Vector2(broken, r.end.y), Vector2(broken + d * 10, r.end.y + 24), Color("#5a5f70"), 1.5)
					ci.draw_line(Vector2(broken - d * 6, r.end.y), Vector2(broken + d * 4, r.end.y + 30), Color("#5a5f70"), 1.5)
	for o: Array in lv.oneways:
		var r := Rect2(o[0], o[1], o[2], Levels.ONEWAY_THICK)
		match id:
			"insaat":
				var below := 720.0
				for px: float in [r.position.x + 9.0, r.end.x - 9.0]:
					var to := _surface_below(Vector2(px, r.end.y + 1))
					below = minf(below, to)
					ci.draw_line(Vector2(px, r.end.y), Vector2(px, to), Color("#6c7480"), 4.0)
				if below - r.end.y > 40.0:
					ci.draw_line(Vector2(r.position.x + 9, r.end.y + 4), Vector2(r.end.x - 9, below - 4), Color("#6c7480", 0.7), 2.0)
					ci.draw_line(Vector2(r.end.x - 9, r.end.y + 4), Vector2(r.position.x + 9, below - 4), Color("#6c7480", 0.7), 2.0)
				box(ci, r, Color("#c58b4c"), Color("#e0aa6c"), OUTLINE, 3.0)
				for k in range(int(r.position.x) + 40, int(r.end.x), 48):
					ci.draw_line(Vector2(k, r.position.y + 2), Vector2(k, r.end.y - 1), Color("#8a5a2c"), 1.5)
			"catilar":
				for px in range(int(r.position.x) + 4, int(r.end.x), 22):
					ci.draw_line(Vector2(px, r.position.y), Vector2(px, r.position.y - 18), Color("#4d5566", 0.9), 2.0)
				ci.draw_line(Vector2(r.position.x, r.position.y - 18), Vector2(r.end.x, r.position.y - 18), Color("#5d6678"), 2.0)
				box(ci, r, Color("#3d4454"), Color("#6c7689"), OUTLINE, 3.0)
				for k in range(int(r.position.x) + 6, int(r.end.x) - 4, 8):
					ci.draw_line(Vector2(k, r.position.y + 4), Vector2(k + 5, r.end.y - 2), Color("#2a303c"), 1.0)
			_:
				# Steel I-beams for the factory and the bridge.
				var top := Color("#8a91a3") if id == "fabrika" else Color("#c25a40")
				var web := Color("#555b6b") if id == "fabrika" else Color("#7a3326")
				ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 4), top)
				ci.draw_rect(Rect2(r.position.x + 3, r.position.y + 4, r.size.x - 6, 4), web)
				ci.draw_rect(Rect2(r.position.x, r.position.y + 8, r.size.x, 4), top.darkened(0.25))
				ci.draw_rect(r, OUTLINE, false, 2.0)
				for k in range(int(r.position.x) + 10, int(r.end.x) - 4, 24):
					ci.draw_circle(Vector2(k, r.position.y + 6), 1.6, top.lightened(0.3))
				if id == "fabrika":
					for px: float in [r.position.x + 14.0, r.end.x - 14.0]:
						ci.draw_line(Vector2(px, r.position.y), Vector2(px, r.position.y - 400), Color("#2a2130", 0.75), 2.0)


func _surface_below(at: Vector2) -> float:
	var best := 720.0
	for r: Rect2 in world.solids:
		if at.x >= r.position.x and at.x <= r.end.x and r.position.y >= at.y:
			best = minf(best, r.position.y)
	for r: Rect2 in world.oneways:
		if at.x >= r.position.x and at.x <= r.end.x and r.position.y >= at.y:
			best = minf(best, r.position.y)
	return best


# --- Everything that moves -------------------------------------------------------------------

func _draw_front() -> void:
	if world == null:
		return
	var ci := _front
	if world.level_id == "kopru":
		for i in 4:
			var y := 618.0 + i * 24.0
			var pts := PackedVector2Array()
			for k in 43:
				var x := 210.0 + k * 20.5
				pts.append(Vector2(x, y + sin(x * 0.035 + _time * (1.6 + i * 0.3) + i) * 2.5))
			ci.draw_polyline(pts, Color(0.75, 0.82, 1.0, 0.22 - i * 0.04), 2.0, true)
	for d: Dictionary in world.decals:
		_draw_decal(ci, d)
	for w in world.pickups:
		_draw_pickup(ci, w)
	for p in world.props:
		_draw_prop(ci, p)
	for f: Stickman in world.fighters:
		if not f.alive and not f.gone:
			_draw_fighter(ci, f)
	for f: Stickman in world.fighters:
		if f.alive:
			_draw_fighter(ci, f)
	for s in world.shots:
		_draw_shot(ci, s)
	for p in world.particles:
		_draw_particle(ci, p)
	for b: Dictionary in world.blasts:
		var t: float = b.t / 0.6
		var r: float = b.radius
		ci.draw_circle(b.pos, r * (0.35 + t * 0.5), Color(1.0, 0.85, 0.45, 0.85 * (1.0 - t) * (1.0 - t)))
		ci.draw_circle(b.pos, r * (0.2 + t * 0.3), Color(1.0, 1.0, 0.85, maxf(0.0, 1.0 - t * 2.5)))
		ci.draw_arc(b.pos, r * (0.3 + t * 1.1), 0.0, TAU, 40, Color(1, 1, 1, 0.5 * (1.0 - t)), 6.0 * (1.0 - t) + 1.0, true)
	if show_tags:
		for f: Stickman in world.fighters:
			if f.alive:
				_draw_tag(ci, f)
	if crosshair.x > -999.0:
		var c := crosshair
		var col := Color(crosshair_color, 0.95)
		ci.draw_arc(c, 9.0, 0.0, TAU, 24, OUTLINE, 4.0, true)
		ci.draw_arc(c, 9.0, 0.0, TAU, 24, col, 2.0, true)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			ci.draw_line(c + d * 5.0, c + d * 13.0, col, 2.0, true)
	if _flash > 0.0:
		ci.draw_rect(BIG, Color(1.0, 0.95, 0.85, _flash * 0.3))


func _draw_decal(ci: CanvasItem, d: Dictionary) -> void:
	var a := clampf(float(d.life) / 3.0, 0.0, 1.0)
	match d.kind:
		"scorch":
			ellipse(ci, d.pos, d.size, d.size * 0.16, Color(0.05, 0.04, 0.04, 0.55 * a))
			ellipse(ci, d.pos, d.size * 0.6, d.size * 0.1, Color(0.02, 0.02, 0.02, 0.5 * a))
		"blood":
			ellipse(ci, d.pos, d.size, d.size * 0.35, Color(d.color, 0.85 * a))
		"bolt":
			var dir := Vector2.from_angle(d.angle)
			var tail: Vector2 = d.pos - dir * 18.0
			ci.draw_line(tail, d.pos, Color("#c9a46a", a), 2.0, true)
			ci.draw_line(tail, tail + dir.rotated(2.6) * 5.0, Color("#e8e0c8", a), 1.5, true)
			ci.draw_line(tail, tail + dir.rotated(-2.6) * 5.0, Color("#e8e0c8", a), 1.5, true)


func _draw_pickup(ci: CanvasItem, w: World.Pickup) -> void:
	var usable: bool = w.usable()
	var alpha := 1.0
	var life := World.PICKUP_LIFE if usable else 2.5
	if w.age > life - 3.0:
		alpha = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * 18.0))
	if usable and w.on_ground:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0 + w.pos.x)
		ellipse(ci, w.pos + Vector2(0, 5), 18.0, 4.0, Color(1.0, 0.85, 0.4, 0.18 + 0.18 * pulse))
		ci.draw_circle(w.pos + Vector2(0, -2), 15.0 + pulse * 2.0, Color(1.0, 0.9, 0.5, 0.07 + 0.06 * pulse))
	Weapons.draw(ci, w.type, w.pos + Vector2(-6, 0).rotated(w.angle), w.angle, false, w.ammo, 1.0, alpha * (1.0 if usable or w.danger > 0.0 else 0.6))


func _draw_prop(ci: CanvasItem, p: World.Prop) -> void:
	var r: Rect2 = p.rect
	var wob := sin(_time * 70.0) * 0.06 * p.shake
	ci.draw_set_transform(r.get_center(), wob, Vector2.ONE)
	var local := Rect2(-r.size * 0.5, r.size)
	if p.kind == "crate":
		var wood: Color = [Color("#a8743f"), Color("#9c6a38"), Color("#b07c46"), Color("#a06e3a")][p.look]
		ci.draw_rect(local, wood)
		var inner := local.grow(-5.0)
		ci.draw_rect(Rect2(local.position, Vector2(local.size.x, 5)), wood.lightened(0.12))
		ci.draw_line(inner.position, inner.end, wood.darkened(0.35), 4.0)
		ci.draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), wood.darkened(0.35), 4.0)
		ci.draw_rect(inner, wood.darkened(0.3), false, 2.0)
		ci.draw_rect(local, Color("#3a2412"), false, 2.5)
		if p.hp < World.CRATE_HP:
			var k: float = 1.0 - p.hp / World.CRATE_HP
			ci.draw_line(Vector2(-6, -18), Vector2(2, -4) + Vector2(4, 6) * k, Color("#2a180a"), 1.8)
			if k > 0.4:
				ci.draw_line(Vector2(10, 18), Vector2(2, 6), Color("#2a180a"), 1.8)
	else:
		var lit: bool = p.fuse >= 0.0 or p.sky
		var body := Color("#c0392b")
		if lit and int(_time * 20.0) % 2 == 0:
			body = Color("#ff6b4a")
		ci.draw_rect(local, body)
		ci.draw_rect(Rect2(local.position, Vector2(7, local.size.y)), body.lightened(0.18))
		ci.draw_rect(Rect2(Vector2(local.end.x - 7, local.position.y), Vector2(7, local.size.y)), body.darkened(0.25))
		for y: float in [-14.0, 13.0]:
			ci.draw_rect(Rect2(local.position.x, y - 2.0, local.size.x, 4), Color("#7b1f17"))
		ci.draw_rect(Rect2(local.position.x - 1, local.position.y, local.size.x + 2, 4), Color("#d8d8d8"))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -8), Vector2(8, 6), Vector2(-8, 6)]), Color("#f2c230"))
		ci.draw_line(Vector2(0, -3), Vector2(0, 1), OUTLINE, 2.0)
		ci.draw_circle(Vector2(0, 3.6), 1.1, OUTLINE)
		ci.draw_rect(local, OUTLINE, false, 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if p.kind == "barrel" and (p.fuse >= 0.0 or p.sky):
		var top := Vector2(r.get_center().x, r.position.y)
		for k in 3:
			ci.draw_circle(top + Vector2(randf_range(-6, 6), -randf_range(2, 14)), randf_range(2, 5), Color(1.0, randf_range(0.5, 0.9), 0.2, 0.9))


func _draw_shot(ci: CanvasItem, s: World.Shot) -> void:
	var dir: Vector2 = s.vel.normalized()
	match s.kind:
		"bullet":
			var tail: Vector2 = s.pos - dir * minf(26.0, s.pos.distance_to(s.start))
			ci.draw_line(tail, s.pos, Color(1.0, 0.85, 0.4, 0.35), 4.5, true)
			ci.draw_line(tail, s.pos, Color("#fff6c8"), 2.0, true)
		"pellet":
			var tail: Vector2 = s.pos - dir * minf(14.0, s.pos.distance_to(s.start))
			ci.draw_line(tail, s.pos, Color("#ffe39a", clampf(s.life * 5.0, 0.2, 1.0)), 1.8, true)
		"bolt":
			var tail: Vector2 = s.pos - dir * 20.0
			ci.draw_line(tail, s.pos, Color("#c9a46a"), 2.2, true)
			ci.draw_colored_polygon(PackedVector2Array([s.pos + dir * 5.0, s.pos + dir.orthogonal() * 2.5, s.pos - dir.orthogonal() * 2.5]), Color("#9aa3b5"))
			ci.draw_line(tail, tail + dir.rotated(2.6) * 6.0, Color("#e8e0c8"), 1.5, true)
			ci.draw_line(tail, tail + dir.rotated(-2.6) * 6.0, Color("#e8e0c8"), 1.5, true)
		"grenade":
			Weapons.draw(ci, "grenade", s.pos, s.angle)
			var rate := 4.0 if s.fuse > 1.0 else (9.0 if s.fuse > 0.5 else 18.0)
			if sin(_time * rate * TAU) > 0.0:
				ci.draw_circle(s.pos + Vector2(0, -1), 2.2, Color("#ff3b30"))
			if s.fuse < 0.9:
				ci.draw_arc(s.pos, Weapons.EXPLOSION.radius * (1.0 - s.fuse / 0.9 * 0.4), 0.0, TAU, 48, Color(1.0, 0.3, 0.2, 0.25), 2.0, true)


func _draw_particle(ci: CanvasItem, p: World.Particle) -> void:
	var k: float = clampf(p.life / p.max_life, 0.0, 1.0)
	match p.kind:
		"spark":
			ci.draw_line(p.pos, p.pos - p.vel * 0.025, Color(p.color, k), p.size, true)
		"flash":
			var pts := PackedVector2Array()
			for i in 10:
				var a: float = p.angle + i * TAU / 10.0
				var rad: float = p.size * (1.0 if i % 2 == 0 else 0.4) * (0.6 + k * 0.6)
				if i == 0:
					rad *= 1.8
				pts.append(p.pos + Vector2.from_angle(a) * rad)
			ci.draw_colored_polygon(pts, Color(p.color, 0.95))
		"smoke":
			ci.draw_circle(p.pos, p.size * (1.0 + (1.0 - k) * 1.3), Color(p.color, p.color.a * k))
		"fire":
			var c := Color("#fff1a8").lerp(Color("#ff7b29"), 1.0 - k)
			if k < 0.4:
				c = Color("#ff7b29").lerp(Color("#5a2010"), 1.0 - k / 0.4)
			ci.draw_circle(p.pos, p.size * (0.5 + k * 0.6), Color(c, minf(1.0, k * 1.8)))
		"splinter", "debris", "shell":
			var size := Vector2(p.size, p.size * (0.35 if p.kind != "debris" else 0.8))
			ci.draw_set_transform(p.pos, p.angle, Vector2.ONE)
			ci.draw_rect(Rect2(-size * 0.5, size), Color(p.color, minf(1.0, k * 3.0)))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"blood", "drop":
			ci.draw_circle(p.pos, p.size, Color(p.color, minf(1.0, k * 2.5)))
		"dust":
			ci.draw_circle(p.pos, p.size * (1.0 + (1.0 - k)), Color(p.color, p.color.a * k))


# --- Fighters --------------------------------------------------------------------------------

func _draw_fighter(ci: CanvasItem, f: Stickman) -> void:
	var j := f.rig.j
	if j.is_empty():
		return
	var col := f.color
	if not f.alive:
		col = col.lerp(Color(0.45, 0.45, 0.48), 0.45)
	var far := col.darkened(0.32)
	var limbs_far := [["neck", "elbow_f", "hand_f"], ["hip", "knee_f", "foot_f"]]
	var limbs_body := [["hip", "neck"], ["hip", "knee_n", "foot_n"]]
	var arm_near := [["neck", "elbow_n", "hand_n"]]
	_chains(ci, j, limbs_far, OUTLINE, LIMB + 3.2)
	_chains(ci, j, limbs_far, far, LIMB)
	_chains(ci, j, limbs_body, OUTLINE, LIMB + 3.2)
	_chains(ci, j, limbs_body, col, LIMB)
	# Head with a headband whose tails stream behind.
	var head: Vector2 = j.head
	var neck: Vector2 = j.neck
	var up := (head - neck).normalized()
	var side := up.orthogonal() * (-1.0 if f.facing > 0 else 1.0)
	ci.draw_circle(head, Rig.HEAD_R + 1.7, OUTLINE)
	ci.draw_circle(head, Rig.HEAD_R, col)
	var band_c := head + up * 1.6
	var back := band_c - side * (Rig.HEAD_R - 0.5)
	ci.draw_line(band_c + side * Rig.HEAD_R * 0.95, back, Color("#16161c"), 2.6, true)
	var flutter := sin(_time * 14.0 + f.id) * 2.0
	var drift := Vector2(-f.facing * 9.0, -2.0) - f.vel * 0.012
	ci.draw_line(back, back + drift + Vector2(0, flutter), Color("#16161c"), 2.2, true)
	ci.draw_line(back, back + drift * 0.8 + Vector2(0, 4.0 - flutter), Color("#16161c"), 2.0, true)
	var eye := head + side * 3.6 - up * 0.6
	if f.alive:
		ci.draw_circle(eye, 1.3, OUTLINE)
	else:
		ci.draw_line(eye + Vector2(-1.8, -1.8), eye + Vector2(1.8, 1.8), OUTLINE, 1.4)
		ci.draw_line(eye + Vector2(-1.8, 1.8), eye + Vector2(1.8, -1.8), OUTLINE, 1.4)
	# Weapon, then the near arm holding it.
	if f.weapon != "" and not f.is_down():
		if f.weapon == "sword" and f.attack_kind == "sword" and f.rig.trail.size() > 1:
			var tr: Array = f.rig.trail
			for i in tr.size() - 1:
				var a := 1.0 - float(i) / tr.size()
				ci.draw_line(tr[i], tr[i + 1], Color(1, 1, 1, 0.55 * a), 7.0 * a, true)
		Weapons.draw(ci, f.weapon, f.rig.grip, f.rig.grip_angle, f.rig.grip_flip, f.ammo)
	_chains(ci, j, arm_near, OUTLINE, LIMB + 3.2)
	_chains(ci, j, arm_near, col, LIMB)
	if f.hurt_t > 0.15 and f.alive:
		ci.draw_circle(head, Rig.HEAD_R + 3.0, Color(1, 1, 1, (f.hurt_t - 0.15) * 4.0))


func _chains(ci: CanvasItem, j: Dictionary, chains: Array, color: Color, width: float) -> void:
	for chain: Array in chains:
		for i in chain.size() - 1:
			ci.draw_line(j[chain[i]], j[chain[i + 1]], color, width, true)
		for key: String in chain:
			ci.draw_circle(j[key], width * 0.5, color)


func _draw_tag(ci: CanvasItem, f: Stickman) -> void:
	var head := f.rig.head_pos()
	if f.is_down():
		head = f.rig.ragdoll.bounds().position + Vector2(f.rig.ragdoll.bounds().size.x * 0.5, 0)
	var at := head + Vector2(0, -20)
	if at.y < 14.0:
		# Off the top of the screen: an arrow at the edge.
		var x := clampf(head.x, 14.0, 1266.0)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, 6), Vector2(x - 8, 20), Vector2(x + 8, 20)]), f.color)
		return
	var w := 34.0
	var k := clampf(f.hp / Stickman.MAX_HP, 0.0, 1.0)
	ci.draw_rect(Rect2(at.x - w * 0.5 - 1, at.y - 1, w + 2, 6), Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(at.x - w * 0.5, at.y, w * k, 4), Color("#7bd66a").lerp(Color("#ef4a3c"), 1.0 - k))
	var tag: String = tags.get(f.id, "")
	if tag != "":
		UI.draw_text(ci, tag, at + Vector2(0, -4), 13, f.color, 4, UI.body_font())
