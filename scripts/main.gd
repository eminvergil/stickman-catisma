extends Control
## App root: keeps the 1280×720 screens centred on any window shape and switches between them.
## Test helpers (after `--`): `--screen=menu|setup|game|help|settings|scores`, `--quick`
## (one human against three bots), `--bots` (four bots), `--wins=N`, `--map=N` (1-4), `--shot=PATH [--shot-delay=SEC]` saves a
## screenshot and quits.

const UI := preload("res://scripts/ui.gd")
const SCREENS := {
	"menu": preload("res://scripts/screens/menu_screen.gd"),
	"setup": preload("res://scripts/screens/setup_screen.gd"),
	"game": preload("res://scripts/game/game_screen.gd"),
	"help": preload("res://scripts/screens/help_screen.gd"),
	"settings": preload("res://scripts/screens/settings_screen.gd"),
	"scores": preload("res://scripts/screens/scores_screen.gd"),
}

var current: Control


func _ready() -> void:
	theme = UI.build_theme()
	resized.connect(_center)
	get_tree().root.min_size = Vector2i(640, 360)
	if DisplayServer.get_name() != "headless":
		get_window().title = "Stickman Çatışma"
	var start := "menu"
	var delay := 2.0
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--screen="):
			start = value
		elif arg == "--quick":
			Match.quick_setup()
		elif arg == "--bots":
			Match.quick_setup()
			Match.slots[0].type = "bot"
		elif arg.begins_with("--wins="):
			Match.force_wins = int(value)
		elif arg.begins_with("--map="):
			Match.map_choice = int(value)
		elif arg.begins_with("--shot-delay="):
			delay = float(value)
		elif arg.begins_with("--shot="):
			shot = value
	go(start)
	if shot != "":
		_shot(shot, delay)


func go(to: String) -> void:
	if current:
		current.queue_free()
		current = null
	current = SCREENS.get(to, SCREENS.menu).new()
	add_child(current)
	current.navigate.connect(go)
	_center()


func _center() -> void:
	if current:
		var k := minf(size.x / UI.SIZE.x, size.y / UI.SIZE.y)
		current.scale = Vector2(k, k)
		current.position = ((size - UI.SIZE * k) / 2).floor()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#08080b"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and current and current.has_method("go_back"):
		current.go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and current and current.has_method("go_back"):
		current.go_back()


func _shot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
