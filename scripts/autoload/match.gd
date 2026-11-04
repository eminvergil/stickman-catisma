extends Node
## The match being played: who is in which slot, the rounds won so far and per-player totals.
## A slot is {"type": "human"|"bot"|"off", "device": "k1"|"k2"|"pad0"|"pad1", "diff": 0..2}.

const Levels := preload("res://scripts/game/levels.gd")

const COLORS := [Color("#e84545"), Color("#3d8bff"), Color("#3ccf6a"), Color("#f2c230")]
const COLOR_NAMES := ["KIRMIZI", "MAVİ", "YEŞİL", "SARI"]
const DIFF_NAMES := ["Kolay", "Normal", "Zor"]
const DEVICE_NAMES := {"k1": "Klavye 1", "k2": "Klavye 2", "pad0": "Gamepad 1", "pad1": "Gamepad 2"}
const DEFAULT_SLOTS := [
	{"type": "human", "device": "k1", "diff": 1},
	{"type": "bot", "device": "k2", "diff": 1},
	{"type": "bot", "device": "pad0", "diff": 1},
	{"type": "bot", "device": "pad1", "diff": 1},
]

var slots: Array = DEFAULT_SLOTS.duplicate(true)
var map_choice := 0  # 0 random, otherwise Levels.ORDER index + 1
var target_wins := 5
var round_no := 0
var wins: Array = [0, 0, 0, 0]
## Per slot: {"kills", "deaths", "damage", "crates", "barrels"}
var totals: Array = []
var last_level := ""
## Dev/test override for the rounds needed to win (0 = use the setting).
var force_wins := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	load_setup()


## Restores the set-up chosen last time on the "Oyun Kur" screen.
func load_setup() -> void:
	var saved: Array = Settings.get_value("slots")
	if saved.size() == 4:
		slots = saved.duplicate(true)
	map_choice = int(Settings.get_value("map"))
	target_wins = Settings.rounds_to_win()


func save_setup() -> void:
	Settings.set_value("slots", slots.duplicate(true))
	Settings.set_value("map", map_choice)


## One human on Klavye 1 against three normal bots on a random map.
func quick_setup() -> void:
	slots = DEFAULT_SLOTS.duplicate(true)
	map_choice = 0
	target_wins = Settings.rounds_to_win()


func active() -> Array:
	var out := []
	for i in slots.size():
		if slots[i].type != "off":
			out.append(i)
	return out


func is_human(slot: int) -> bool:
	return slots[slot].type == "human"


func player_name(slot: int) -> String:
	var s: Dictionary = slots[slot]
	if s.type == "human":
		return "Oyuncu %d" % (slot + 1)
	return "Bot %d" % (slot + 1)


func start_match() -> void:
	if force_wins > 0:
		target_wins = force_wins
	round_no = 0
	wins = [0, 0, 0, 0]
	totals = []
	for i in 4:
		totals.append({"kills": 0, "deaths": 0, "damage": 0, "crates": 0, "barrels": 0})
	last_level = ""


## Picks the level for the next round: the chosen one, or a random one that differs from the
## last round's.
func next_level() -> String:
	round_no += 1
	if map_choice > 0:
		last_level = Levels.ORDER[clampi(map_choice - 1, 0, Levels.ORDER.size() - 1)]
		return last_level
	var pool: Array = Levels.ORDER.duplicate()
	if pool.size() > 1:
		pool.erase(last_level)
	last_level = pool[_rng.randi() % pool.size()]
	return last_level


func match_winner() -> int:
	for i in wins.size():
		if wins[i] >= target_wins:
			return i
	return -1
