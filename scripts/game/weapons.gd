extends RefCounted
## What each weapon does and how it looks. Weapons are drawn in their own space: the grip at
## the origin, the barrel or blade along +x and up along -y.

const ORDER := ["pistol", "shotgun", "crossbow", "sword", "grenade"]
const DEFS := {
	"pistol": {
		"name": "Tabanca", "kind": "gun", "ammo": 10, "rate": 0.24, "damage": 24.0, "knock": 170.0,
		"speed": 1800.0, "life": 0.9, "recoil": 5.0, "kick": 0.16, "reach": 0.9, "weight": 30,
		"muzzle": Vector2(17, -4.5), "fore": Vector2(1, 1.5), "prop": 30.0, "sound": "pistol",
	},
	"shotgun": {
		"name": "Pompalı", "kind": "gun", "ammo": 5, "rate": 0.85, "damage": 13.0, "knock": 120.0,
		"pellets": 7, "spread": 0.2, "speed": 1400.0, "life": 0.3, "recoil": 9.0, "kick": 0.3,
		"reach": 0.45, "self_push": 240.0, "weight": 20, "muzzle": Vector2(32, -4.2),
		"fore": Vector2(13, -1.5), "prop": 14.0, "sound": "shotgun",
	},
	"crossbow": {
		"name": "Arbalet", "kind": "gun", "ammo": 4, "rate": 1.0, "damage": 78.0, "knock": 430.0,
		"speed": 1250.0, "gravity": 420.0, "life": 1.6, "recoil": 4.0, "kick": 0.1, "reach": 0.6,
		"weight": 18, "muzzle": Vector2(20, -1.5), "fore": Vector2(9, 0.5), "prop": 40.0, "sound": "crossbow",
	},
	"sword": {
		"name": "Kılıç", "kind": "melee", "ammo": -1, "rate": 0.42, "damage": 44.0, "knock": 420.0,
		"weight": 20, "reach": 0.9, "prop": 40.0,
	},
	"grenade": {
		"name": "El Bombası", "kind": "throw", "ammo": 3, "rate": 0.65, "fuse": 2.0, "weight": 12,
		"reach": 0.8, "speed": 760.0,
	},
}
const FIST := {"damage": 9.0, "knock": 230.0, "prop": 8.0}
const FIST_FINISHER := {"damage": 15.0, "knock": 470.0, "prop": 12.0}
const THROWN := {"damage": 22.0, "knock": 330.0}
const EXPLOSION := {"radius": 125.0, "damage": 85.0, "knock": 950.0}

const STEEL := Color("#2b2e36")
const STEEL_HI := Color("#5b6070")
const WOOD := Color("#7a4b26")
const WOOD_DARK := Color("#4a2c14")
const BLADE := Color("#dfe5ee")
const GOLD := Color("#d9a63a")
const OUTLINE := Color("#121217")


static func def(type: String) -> Dictionary:
	return DEFS.get(type, {})


static func display_name(type: String) -> String:
	return DEFS[type].name if DEFS.has(type) else "Yumruk"


## Picks a crate's contents by the weights in DEFS.
static func random_type(rng: RandomNumberGenerator) -> String:
	var total := 0
	for t: String in ORDER:
		total += int(DEFS[t].weight)
	var roll := rng.randi() % total
	for t: String in ORDER:
		roll -= int(DEFS[t].weight)
		if roll < 0:
			return t
	return "pistol"


## Draws `type` with its grip at `at`, pointing along `angle`. `flip` mirrors it vertically so
## a weapon aimed to the left isn't upside down.
static func draw(ci: CanvasItem, type: String, at: Vector2, angle: float, flip := false, ammo := 1,
		scale := 1.0, alpha := 1.0) -> void:
	ci.draw_set_transform(at, angle, Vector2(scale, -scale if flip else scale))
	var m := Color(1, 1, 1, alpha)
	match type:
		"pistol":
			_poly(ci, [Vector2(-2, -2), Vector2(4, -2), Vector2(2, 7), Vector2(-4, 7)], STEEL * m)
			_poly(ci, [Vector2(-4, -8), Vector2(16, -8), Vector2(16, -2), Vector2(-4, -2)], STEEL * m)
			ci.draw_line(Vector2(-3, -7), Vector2(15, -7), STEEL_HI * m, 1.2, true)
			ci.draw_arc(Vector2(5, -1), 3.0, 0.0, PI, 8, OUTLINE * m, 1.2, true)
		"shotgun":
			_poly(ci, [Vector2(-17, -4), Vector2(-4, -6), Vector2(-4, 0), Vector2(-15, 4)], WOOD * m)
			_poly(ci, [Vector2(-4, -7), Vector2(7, -7), Vector2(7, -1), Vector2(-4, -1)], STEEL * m)
			_poly(ci, [Vector2(7, -6), Vector2(32, -6), Vector2(32, -2.6), Vector2(7, -2.6)], STEEL * m)
			_poly(ci, [Vector2(11, -2.8), Vector2(23, -2.8), Vector2(23, 0.8), Vector2(11, 0.8)], WOOD_DARK * m)
			ci.draw_line(Vector2(8, -5.4), Vector2(31, -5.4), STEEL_HI * m, 1.0, true)
		"crossbow":
			_poly(ci, [Vector2(-15, -3), Vector2(18, -3), Vector2(18, 1), Vector2(-13, 3)], WOOD * m)
			var top := Vector2(13, -15)
			var bottom := Vector2(13, 13)
			var nock := Vector2(1, -1) if ammo > 0 else Vector2(12, -1)
			ci.draw_polyline(PackedVector2Array([top, Vector2(18, -6), Vector2(19, -1), Vector2(18, 4), bottom]), WOOD_DARK * m, 2.6, true)
			ci.draw_polyline(PackedVector2Array([top, nock, bottom]), Color("#e8e0c8") * m, 1.0, true)
			if ammo > 0:
				ci.draw_line(Vector2(1, -2), Vector2(21, -2), Color("#c9a46a") * m, 1.6, true)
				_poly(ci, [Vector2(21, -4), Vector2(25, -2), Vector2(21, 0)], STEEL_HI * m)
		"sword":
			ci.draw_circle(Vector2(-8, 0), 2.4, GOLD * m)
			_poly(ci, [Vector2(-7, -1.7), Vector2(2, -1.7), Vector2(2, 1.7), Vector2(-7, 1.7)], WOOD_DARK * m)
			_poly(ci, [Vector2(2, -6.5), Vector2(4.8, -6.5), Vector2(4.8, 6.5), Vector2(2, 6.5)], GOLD * m)
			_poly(ci, [Vector2(4.8, -2.4), Vector2(37, -1.9), Vector2(42, 0), Vector2(37, 1.9), Vector2(4.8, 2.4)], BLADE * m)
			ci.draw_line(Vector2(6, -0.6), Vector2(38, -0.4), Color(1, 1, 1, 0.9 * alpha), 0.9, true)
		"grenade":
			ci.draw_circle(Vector2(0, 0), 6.2, OUTLINE * m)
			ci.draw_circle(Vector2(0, 0), 5.2, Color("#55682c") * m)
			ci.draw_line(Vector2(-5, 0), Vector2(5, 0), Color("#3c4a1e") * m, 1.0, true)
			ci.draw_line(Vector2(0, -5), Vector2(0, 5), Color("#3c4a1e") * m, 1.0, true)
			_poly(ci, [Vector2(-2, -8), Vector2(2, -8), Vector2(2, -5), Vector2(-2, -5)], STEEL_HI * m)
			ci.draw_line(Vector2(2, -7.5), Vector2(6, -3), STEEL_HI * m, 1.4, true)
			ci.draw_arc(Vector2(-3.5, -8.5), 2.2, 0.0, TAU, 10, GOLD * m, 1.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A filled polygon with a thin dark outline, so weapons read against any background.
static func _poly(ci: CanvasItem, pts: Array, color: Color) -> void:
	var p := PackedVector2Array(pts)
	ci.draw_colored_polygon(p, color)
	p.append(p[0])
	ci.draw_polyline(p, Color(OUTLINE, color.a), 1.0, true)


## The point where shots leave the barrel, for a weapon held at `grip` along `angle`.
static func muzzle(type: String, grip: Vector2, angle: float, flip: bool) -> Vector2:
	var m: Vector2 = DEFS[type].get("muzzle", Vector2(14, -3))
	if flip:
		m.y = -m.y
	return grip + m.rotated(angle)


## Where the supporting hand holds the weapon.
static func foregrip(type: String, grip: Vector2, angle: float, flip: bool) -> Vector2:
	var f: Vector2 = DEFS.get(type, {}).get("fore", Vector2(0, 2))
	if flip:
		f.y = -f.y
	return grip + f.rotated(angle)
