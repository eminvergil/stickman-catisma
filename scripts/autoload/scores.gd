extends Node
## Lifetime stats for the people at this computer (every human slot counts) and the most recent
## matches, saved to user://scores.cfg.

const PATH := "user://scores.cfg"
const KEEP := 10
const EMPTY := {
	"matches": 0, "wins": 0, "rounds": 0, "kills": 0, "deaths": 0, "best_kills": 0,
	"crates": 0, "barrels": 0, "headshots": 0, "deflects": 0,
	"k_fist": 0, "k_pistol": 0, "k_shotgun": 0, "k_crossbow": 0, "k_sword": 0, "k_grenade": 0,
	"k_barrel": 0, "k_thrown": 0, "k_fall": 0,
}

var stats := EMPTY.duplicate()
## Newest first: {"date", "winner", "color", "human_won", "kills", "rounds", "players"}
var recent: Array = []


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in EMPTY:
			stats[key] = cfg.get_value("stats", key, 0)
		recent = cfg.get_value("recent", "matches", [])


func add(key: String, amount := 1) -> void:
	if stats.has(key):
		stats[key] = int(stats[key]) + amount


## Kill counts per weapon live under "k_<weapon>".
func add_kill(weapon: String) -> void:
	add("kills")
	add("k_" + weapon)


func record_match(entry: Dictionary) -> void:
	add("matches")
	if entry.get("human_won", false):
		add("wins")
	stats.best_kills = maxi(int(stats.best_kills), int(entry.get("kills", 0)))
	var now := Time.get_datetime_dict_from_system()
	var e := entry.duplicate()
	e["date"] = "%02d.%02d.%d %02d:%02d" % [now.day, now.month, now.year, now.hour, now.minute]
	recent.push_front(e)
	recent = recent.slice(0, KEEP)
	save()


func reset() -> void:
	stats = EMPTY.duplicate()
	recent = []
	save()


func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in stats:
		cfg.set_value("stats", key, stats[key])
	cfg.set_value("recent", "matches", recent)
	cfg.save(PATH)
