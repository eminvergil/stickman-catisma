extends Node
## Headless walk through the screens and a whole match:
##   godot --headless --path . res://tests/test_ui.tscn
## Saved settings and scores are restored afterwards.

const Main := preload("res://scripts/main.gd")

var failures := 0
var checks := 0
var main: Control
var _settings_backup := {}
var _scores_backup := {}


func _ready() -> void:
	_backup()
	main = Main.new()
	main.size = Vector2(1280, 720)
	add_child(main)
	await get_tree().process_frame
	await _menu()
	await _setup()
	await _match()
	await _screens()
	_restore()
	print("%d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("  FAIL: ", msg)


func _backup() -> void:
	for key: String in Settings.DEFAULTS:
		_settings_backup[key] = Settings.get_value(key)
	_scores_backup = {"stats": Scores.stats.duplicate(), "recent": Scores.recent.duplicate(true)}


func _restore() -> void:
	for key: String in _settings_backup:
		Settings.set_value(key, _settings_backup[key])
	Scores.stats = _scores_backup.stats
	Scores.recent = _scores_backup.recent
	Scores.save()


func find_button(root: Node, text: String) -> Button:
	for c in root.get_children():
		if c is Button and (c as Button).text == text:
			return c
		var deeper := find_button(c, text)
		if deeper:
			return deeper
	return null


func press(text: String) -> bool:
	var b := find_button(main.current, text)
	check(b != null, "button '%s' exists on %s" % [text, main.current.get_script().resource_path.get_file()])
	if b and not b.disabled:
		b.pressed.emit()
		return true
	return false


func frames(n: int, delta := 1.0 / 60.0) -> void:
	for i in n:
		main.current._process(delta)


func _menu() -> void:
	check(main.current.has_signal("navigate"), "main starts on a screen")
	check(main.current.get_script().resource_path.ends_with("menu_screen.gd"), "starts on the menu")
	var demo = main.current.get_child(0)
	check(demo.get("world") != null, "the menu runs a demo match behind it")
	for i in 600:
		demo._process(1.0 / 60.0)
	check(demo.world.fighters.size() == 4, "demo has four bots")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the menu keeps the cursor")


func _setup() -> void:
	press("OYUN KUR")
	await get_tree().process_frame
	check(main.current.get_script().resource_path.ends_with("setup_screen.gd"), "Oyun Kur opens the set-up")
	var saved := Match.slots.duplicate(true)
	# Two people on the same keyboard side can't start.
	Match.slots = [{"type": "human", "device": "k1", "diff": 1}, {"type": "human", "device": "k1", "diff": 1},
			{"type": "off", "device": "pad0", "diff": 1}, {"type": "off", "device": "pad1", "diff": 1}]
	main.current._validate()
	check(main.current._start.disabled, "two players on one device can't start")
	Match.slots[1].device = "k2"
	main.current._validate()
	check(not main.current._start.disabled, "different devices can start")
	Match.slots = [{"type": "human", "device": "k1", "diff": 1}, {"type": "off", "device": "k2", "diff": 1},
			{"type": "off", "device": "pad0", "diff": 1}, {"type": "off", "device": "pad1", "diff": 1}]
	main.current._validate()
	check(main.current._start.disabled, "one player alone can't start")
	Match.slots = saved
	main.current._build_slots()
	main.current._validate()
	press("GERİ")
	await get_tree().process_frame
	check(main.current.get_script().resource_path.ends_with("menu_screen.gd"), "back to the menu")


func _match() -> void:
	# Four bots, first to one round, so the match plays itself to the end.
	Match.slots = [{"type": "bot", "device": "k1", "diff": 2}, {"type": "bot", "device": "k2", "diff": 2},
			{"type": "bot", "device": "pad0", "diff": 1}, {"type": "bot", "device": "pad1", "diff": 1}]
	Settings.set_value("wins", 0)
	Match.target_wins = 1
	var before := int(Scores.stats.matches)
	main.go("game")
	await get_tree().process_frame
	var game = main.current
	Match.target_wins = 1
	check(game.world != null and game.world.fighters.size() == 4, "a round starts with four fighters")
	frames(130)
	check(game.world.state == "fight", "the countdown ends")
	game.go_back()
	check(game._paused and game._pause_layer != null, "Esc pauses")
	var t: float = game.world.time
	frames(30)
	check(game.world.time == t, "nothing moves while paused")
	game.go_back()
	check(not game._paused, "Esc again resumes")
	var n := 0
	while game._end_layer == null and n < 60 * 240:
		frames(10)
		n += 10
	check(game._end_layer != null, "the match ends with a winner (%d frames)" % n)
	check(Match.match_winner() >= 0, "someone won the match")
	check(int(Scores.stats.matches) == before + 1, "the match is recorded")
	check(Scores.recent.size() > 0 and Scores.recent[0].has("winner"), "it shows in recent matches")
	var kills := 0
	for i in 4:
		kills += int(Match.totals[i].kills)
	check(kills >= 1, "kills were counted (%d)" % kills)
	press("RÖVANŞ")
	await get_tree().process_frame
	check(main.current.get_script().resource_path.ends_with("game_screen.gd") and main.current != game, "rematch starts a new match")
	check(Match.round_no == 1 and Match.wins == [0, 0, 0, 0], "rematch resets the score")
	main.current.go_back()
	press("ANA MENÜ")
	await get_tree().process_frame
	check(main.current.get_script().resource_path.ends_with("menu_screen.gd"), "pause menu returns to the menu")


func _screens() -> void:
	for pair in [["NASIL OYNANIR", "help_screen.gd"], ["SKORLAR", "scores_screen.gd"], ["AYARLAR", "settings_screen.gd"]]:
		press(pair[0])
		await get_tree().process_frame
		check(main.current.get_script().resource_path.ends_with(pair[1]), "%s opens" % pair[0])
		main.current.go_back()
		await get_tree().process_frame
		check(main.current.get_script().resource_path.ends_with("menu_screen.gd"), "and goes back")
	# Settings toggles stick.
	press("AYARLAR")
	await get_tree().process_frame
	var was: bool = Settings.get_value("shake")
	var buttons := []
	_collect(main.current, buttons)
	Settings.set_value("shake", not was)
	check(Settings.get_value("shake") == (not was), "a setting can be changed")
	main.current.go_back()
	await get_tree().process_frame


func _collect(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Button:
			out.append(c)
		_collect(c, out)
