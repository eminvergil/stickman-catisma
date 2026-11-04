extends RefCounted
## The maps. Every map fits the 1280×720 view; whoever drops below it dies.
##
## "solids" are [x, y, w, h] blocks you can't pass; "oneways" are [x, y, w] platforms you can
## jump up through and drop down from (↓ + jump). Crates, barrels and spawns are [x, y] with
## x the centre and y the surface they stand on. Platforms are spaced at most ~115 px apart in
## height because a jump rises ~139 px.

const ORDER := ["fabrika", "catilar", "insaat", "kopru"]
const ONEWAY_THICK := 12.0

const LEVELS := {
	"fabrika": {
		"name": "Fabrika",
		"walls": true,
		"solids": [[0, 620, 500, 100], [780, 620, 500, 100], [300, 566, 70, 54], [910, 566, 70, 54]],
		"oneways": [[570, 515, 140], [110, 505, 220], [950, 505, 220], [430, 395, 420], [200, 285, 180], [900, 285, 180], [560, 280, 160]],
		"crates": [[200, 620], [1080, 620], [220, 505], [1060, 505], [640, 395], [340, 285], [940, 285]],
		"barrels": [[470, 620], [810, 620], [470, 395], [810, 395], [600, 280]],
		"spawns": [[80, 620], [1200, 620], [240, 285], [1040, 285]],
		"max_crates": 6,
	},
	"catilar": {
		"name": "Çatılar",
		"walls": false,
		"solids": [[0, 560, 360, 160], [470, 470, 340, 250], [920, 580, 360, 140], [240, 524, 64, 36], [1010, 540, 48, 40]],
		"oneways": [[50, 445, 170], [530, 355, 220], [1050, 465, 180], [600, 240, 80], [330, 340, 110], [840, 350, 110]],
		"crates": [[120, 445], [640, 470], [1150, 580], [640, 355], [1140, 465], [385, 340]],
		"barrels": [[60, 560], [520, 470], [790, 470], [1240, 580], [580, 355]],
		"spawns": [[100, 560], [1180, 580], [560, 470], [740, 470]],
		"max_crates": 6,
	},
	"insaat": {
		"name": "İnşaat",
		"walls": false,
		"solids": [[60, 640, 1160, 80], [590, 590, 100, 50], [250, 608, 56, 32], [980, 608, 56, 32]],
		"oneways": [[150, 525, 250], [880, 525, 250], [470, 410, 340], [60, 410, 140], [1080, 410, 140], [250, 295, 170], [860, 295, 170], [560, 295, 160], [580, 180, 120]],
		"crates": [[420, 640], [860, 640], [275, 525], [1005, 525], [640, 410], [330, 295], [950, 295], [640, 180]],
		"barrels": [[180, 640], [1100, 640], [520, 410], [760, 410], [640, 295]],
		"spawns": [[120, 640], [1160, 640], [130, 410], [1150, 410]],
		"max_crates": 7,
	},
	"kopru": {
		"name": "Köprü",
		"walls": true,
		"solids": [[-40, 520, 250, 200], [1070, 520, 250, 200], [210, 520, 355, 16], [715, 520, 355, 16]],
		"oneways": [[300, 405, 140], [840, 405, 140], [555, 330, 170], [110, 300, 140], [1030, 300, 140], [590, 610, 100]],
		"crates": [[100, 520], [1180, 520], [380, 520], [900, 520], [370, 405], [910, 405], [640, 330]],
		"barrels": [[520, 520], [760, 520], [180, 300], [1100, 300]],
		"spawns": [[60, 520], [1220, 520], [300, 520], [980, 520]],
		"max_crates": 6,
	},
}


static func get_level(id: String) -> Dictionary:
	return LEVELS.get(id, LEVELS.fabrika)


static func display_name(id: String) -> String:
	return get_level(id).name


## Solid rectangles of a level, including the invisible side walls on walled maps.
static func solids(id: String) -> Array[Rect2]:
	var lv := get_level(id)
	var out: Array[Rect2] = []
	for s: Array in lv.solids:
		out.append(Rect2(s[0], s[1], s[2], s[3]))
	if lv.walls:
		out.append(Rect2(-60, -600, 60, 1400))
		out.append(Rect2(1280, -600, 60, 1400))
	return out


static func oneways(id: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for s: Array in get_level(id).oneways:
		out.append(Rect2(s[0], s[1], s[2], ONEWAY_THICK))
	return out
