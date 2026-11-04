extends Control
## Title screen. Four bots fight a real match behind the menu.

signal navigate(to: String)

const UI := preload("res://scripts/ui.gd")
const GameScreen := preload("res://scripts/game/game_screen.gd")

var _demo: Control


func _ready() -> void:
	size = UI.SIZE
	_demo = GameScreen.new()
	_demo.demo = true
	add_child(_demo)
	var shade := UI.canvas(self, _draw_shade)
	shade.queue_redraw()
	UI.heading(self, "STICKMAN", Rect2(70, 70, 560, 110), 104, UI.INK)
	UI.heading(self, "ÇATIŞMA", Rect2(70, 162, 560, 100), 92, UI.ACCENT)
	UI.label(self, "Kutuyu kır, silahı kap, ayakta kalan son kişi ol.", Rect2(70, 262, 560, 30), 18, UI.MUTED)
	var items := [
		["HIZLI OYUN", _quick], ["OYUN KUR", func() -> void: navigate.emit("setup")],
		["NASIL OYNANIR", func() -> void: navigate.emit("help")], ["SKORLAR", func() -> void: navigate.emit("scores")],
		["AYARLAR", func() -> void: navigate.emit("settings")],
	]
	if not OS.has_feature("web"):
		items.append(["ÇIKIŞ", func() -> void: get_tree().quit()])
	var y := 320.0
	for it: Array in items:
		var b := UI.button(self, it[0], Rect2(180, y, 340, 48), it[1], 20)
		if it[0] == "HIZLI OYUN":
			b.add_theme_color_override("font_color", UI.ACCENT)
		y += 56.0
	UI.label(self, "v%s" % ProjectSettings.get_setting("application/config/version", "1.0.0"), Rect2(1080, 684, 180, 24), 14, Color(UI.INK, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_shade(c: Control) -> void:
	var pts := PackedVector2Array([Vector2(-1400, -900), Vector2(760, -900), Vector2(760, 1620), Vector2(-1400, 1620)])
	c.draw_polygon(pts, PackedColorArray([Color(0, 0, 0, 0.78), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.78)]))
	c.draw_rect(Rect2(-1400, -900, 1980, 2520), Color(0, 0, 0, 0.18))


func _quick() -> void:
	Match.quick_setup()
	navigate.emit("game")


func go_back() -> void:
	pass
