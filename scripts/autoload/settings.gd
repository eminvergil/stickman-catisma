extends Node
## Player settings, saved to user://settings.cfg. Emits `changed(key)` whenever one is set.

signal changed(key: String)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"sound": true,
	"volume": 80,
	"music": true,
	"music_volume": 45,
	"shake": true,
	"blood": true,
	"fullscreen": false,
	"aim": 0,  # how player 1 on "Klavye 1" aims: 0 mouse, 1 keyboard (auto aim)
	"sudden_death": true,
	# The last match set-up, so "Oyun Kur" opens where the player left it.
	"slots": [],
	"map": 0,  # 0 = random, otherwise Levels.ORDER index + 1
	"wins": 1,  # rounds to win a match: 0 = 3, 1 = 5, 2 = 7
}

var _values := DEFAULTS.duplicate(true)


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in DEFAULTS:
			_values[key] = cfg.get_value("settings", key, DEFAULTS[key])
	if get_value("fullscreen"):
		_apply_window()


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	var cfg := ConfigFile.new()
	for k: String in _values:
		cfg.set_value("settings", k, _values[k])
	cfg.save(PATH)
	if key == "fullscreen":
		_apply_window()
	changed.emit(key)


func rounds_to_win() -> int:
	return [3, 5, 7][clampi(int(get_value("wins")), 0, 2)]


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
