extends Control
## Sound, screen and game options.

signal navigate(to: String)

const UI := preload("res://scripts/ui.gd")


func _ready() -> void:
	size = UI.SIZE
	UI.canvas(self, func(c: Control) -> void: c.draw_rect(Rect2(-1400, -900, 4080, 2520), Color("#101118")))
	UI.heading(self, "AYARLAR", Rect2(0, 22, 1280, 70), 58)
	UI.card(self, Rect2(240, 104, 800, 530))
	var y := 128.0
	y = _toggle_slider("Ses efektleri", "sound", "volume", y)
	y = _toggle_slider("Müzik", "music", "music_volume", y)
	y = _choice("Oyuncu 1 nişanı", ["Fare", "Klavye"], int(Settings.get_value("aim")), func(i: int) -> void: Settings.set_value("aim", i), y,
			"Klavyede silah öndeki rakibe kendiliğinden yönelir.")
	y = _choice("Ani ölüm", ["Açık", "Kapalı"], 0 if Settings.get_value("sudden_death") else 1, func(i: int) -> void: Settings.set_value("sudden_death", i == 0), y,
			"75 saniyeyi geçen turlarda gökten yanan variller yağar.")
	y = _choice("Ekran sarsıntısı", ["Açık", "Kapalı"], 0 if Settings.get_value("shake") else 1, func(i: int) -> void: Settings.set_value("shake", i == 0), y)
	y = _choice("Kan efekti", ["Açık", "Kapalı"], 0 if Settings.get_value("blood") else 1, func(i: int) -> void: Settings.set_value("blood", i == 0), y)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		y = _choice("Tam ekran", ["Açık", "Kapalı"], 0 if Settings.get_value("fullscreen") else 1, func(i: int) -> void: Settings.set_value("fullscreen", i == 0), y)
	UI.button(self, "GERİ", Rect2(560, 652, 160, 50), go_back, 18)


func _toggle_slider(text: String, key: String, vol_key: String, y: float) -> float:
	UI.label(self, text, Rect2(280, y, 260, 44), 19, UI.INK, HORIZONTAL_ALIGNMENT_LEFT)
	UI.choice(self, ["Açık", "Kapalı"], Rect2(560, y, 200, 42), 0 if Settings.get_value(key) else 1, func(i: int) -> void:
		Settings.set_value(key, i == 0)
		if i == 0 and key == "sound":
			Sfx.play("pickup"), 16)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = Settings.get_value(vol_key)
	s.position = Vector2(780, y + 12)
	s.size = Vector2(220, 20)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void: Settings.set_value(vol_key, int(v)))
	s.drag_ended.connect(func(_c: bool) -> void:
		if key == "sound":
			Sfx.play("punch"))
	add_child(s)
	return y + 62.0


func _choice(text: String, options: Array, current: int, on_pick: Callable, y: float, hint := "") -> float:
	UI.label(self, text, Rect2(280, y, 260, 44), 19, UI.INK, HORIZONTAL_ALIGNMENT_LEFT)
	UI.choice(self, options, Rect2(560, y, 200, 42), current, on_pick, 16)
	if hint != "":
		UI.para(self, hint, Rect2(780, y + 4, 230, 44), 13, UI.MUTED)
	return y + 62.0


func go_back() -> void:
	navigate.emit("menu")
