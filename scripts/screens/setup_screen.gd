extends Control
## Match set-up: who plays each of the four colours (a person on which device, a bot of which
## difficulty, or nobody), the map, and how many rounds win the match.

signal navigate(to: String)

const UI := preload("res://scripts/ui.gd")
const Levels := preload("res://scripts/game/levels.gd")

const TYPES := ["off", "human", "bot"]
const TYPE_NAMES := ["Kapalı", "İnsan", "Bot"]
const DEVICES := ["k1", "k2", "pad0", "pad1"]

var _slot_layer: Control
var _warn: Label
var _start: Button
var _maps: Control


func _ready() -> void:
	size = UI.SIZE
	UI.canvas(self, func(c: Control) -> void: c.draw_rect(Rect2(-1400, -900, 4080, 2520), Color("#101118")))
	UI.heading(self, "OYUN KUR", Rect2(0, 22, 1280, 70), 58)
	_slot_layer = Control.new()
	add_child(_slot_layer)
	_build_slots()
	UI.label(self, "HARİTA", Rect2(60, 444, 200, 26), 16, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	var names := ["Rastgele"]
	for id: String in Levels.ORDER:
		names.append(Levels.display_name(id))
	UI.choice(self, names, Rect2(60, 474, 860, 44), Match.map_choice, func(i: int) -> void:
		Match.map_choice = i
		_maps.queue_redraw(), 17)
	_maps = UI.canvas(self, _draw_maps, Rect2(60, 524, 860, 100))
	UI.label(self, "KAZANMAK İÇİN TUR", Rect2(960, 444, 260, 26), 16, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	UI.choice(self, ["3", "5", "7"], Rect2(960, 474, 260, 44), int(Settings.get_value("wins")), func(i: int) -> void:
		Settings.set_value("wins", i)
		Match.target_wins = Settings.rounds_to_win(), 18)
	_warn = UI.label(self, "", Rect2(60, 636, 700, 24), 15, UI.DANGER, HORIZONTAL_ALIGNMENT_LEFT)
	UI.button(self, "GERİ", Rect2(60, 652, 160, 50), go_back, 18)
	_start = UI.button(self, "BAŞLA", Rect2(960, 640, 260, 62), _go, 26)
	_start.add_theme_color_override("font_color", UI.ACCENT)
	_validate()


func _build_slots() -> void:
	for c in _slot_layer.get_children():
		c.queue_free()
	for i in 4:
		var x := 60.0 + i * 296.0
		var s: Dictionary = Match.slots[i]
		var col: Color = Match.COLORS[i]
		UI.card(_slot_layer, Rect2(x, 104, 272, 320))
		var strip := ColorRect.new()
		strip.color = col if s.type != "off" else col.darkened(0.6)
		strip.position = Vector2(x, 104)
		strip.size = Vector2(272, 8)
		_slot_layer.add_child(strip)
		UI.heading(_slot_layer, Match.COLOR_NAMES[i], Rect2(x, 116, 272, 50), 38, col if s.type != "off" else Color(col, 0.35))
		var t := TYPES.find(s.type)
		UI.choice(_slot_layer, TYPE_NAMES, Rect2(x + 16, 178, 240, 40), t, func(k: int) -> void:
			Match.slots[i].type = TYPES[k]
			_build_slots.call_deferred()
			_validate.call_deferred(), 15)
		match s.type:
			"human":
				UI.label(_slot_layer, "KONTROL", Rect2(x + 16, 228, 240, 22), 13, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
				var dev := DEVICES.find(s.device)
				var names := []
				for d: String in DEVICES:
					names.append(Match.DEVICE_NAMES[d])
				for k in 4:
					var b := UI.button(_slot_layer, names[k], Rect2(x + 16 + (k % 2) * 124, 252 + (k / 2) * 46, 116, 40), func() -> void:
						Match.slots[i].device = DEVICES[k]
						_build_slots.call_deferred()
						_validate.call_deferred(), 14)
					b.toggle_mode = true
					b.button_pressed = k == dev
				UI.para(_slot_layer, _device_hint(s.device), Rect2(x + 16, 352, 240, 60), 13, UI.MUTED)
			"bot":
				UI.label(_slot_layer, "ZORLUK", Rect2(x + 16, 228, 240, 22), 13, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
				UI.choice(_slot_layer, Match.DIFF_NAMES, Rect2(x + 16, 252, 240, 40), int(s.diff), func(k: int) -> void:
					Match.slots[i].diff = k, 14)
				UI.para(_slot_layer, "Botlar kutuları kırar, silah toplar, varilleri patlatır ve el bombasından kaçar.", Rect2(x + 16, 306, 240, 90), 13, UI.MUTED)
			_:
				UI.para(_slot_layer, "Bu renk bu maçta yok.", Rect2(x + 16, 236, 240, 40), 14, UI.MUTED)


func _device_hint(dev: String) -> String:
	match dev:
		"k1":
			return "WASD + fare ile nişan (sol tık ateş, sağ tık fırlat). Fare yoksa F ateş, G fırlat."
		"k2":
			return "Ok tuşları, Enter ateş, sağ Shift fırlat."
		_:
			var n := Input.get_connected_joypads().size()
			var idx := 0 if dev == "pad0" else 1
			return "Sol çubuk, A zıpla, X ateş, B fırlat." + ("" if n > idx else "  (Bağlı değil)")


func _validate() -> void:
	var active := Match.active()
	var used := {}
	var msg := ""
	for i: int in active:
		var s: Dictionary = Match.slots[i]
		if s.type == "human":
			if used.has(s.device):
				msg = "İki oyuncu aynı kontrolü kullanıyor: %s" % Match.DEVICE_NAMES[s.device]
			used[s.device] = true
	if active.size() < 2:
		msg = "En az iki oyuncu gerekiyor."
	_warn.text = msg
	_start.disabled = msg != ""


func _go() -> void:
	_validate()
	if _start.disabled:
		return
	Match.target_wins = Settings.rounds_to_win()
	Match.save_setup()
	navigate.emit("game")


func go_back() -> void:
	Match.save_setup()
	navigate.emit("menu")


## Tiny maps of every level under the choice buttons.
func _draw_maps(c: Control) -> void:
	var w := (860.0 - 8.0 * 4) / 5.0
	for k in 5:
		var r := Rect2(k * (w + 8.0), 4, w, 92)
		var on := Match.map_choice == k
		c.draw_rect(r, Color("#0b0c11"))
		c.draw_rect(r, UI.ACCENT if on else Color("#3b3f4d"), false, 2.0)
		if k == 0:
			UI.draw_text(c, "?", r.get_center() + Vector2(0, 16), 44, Color(UI.INK, 0.5), 0)
			continue
		var id: String = Levels.ORDER[k - 1]
		var sx := r.size.x / 1280.0
		var sy := r.size.y / 720.0
		var to := func(rect: Rect2) -> Rect2:
			return Rect2(r.position + Vector2(rect.position.x * sx, rect.position.y * sy), rect.size * Vector2(sx, sy))
		for s in Levels.solids(id):
			var mr: Rect2 = to.call(s).intersection(r)
			if mr.has_area():
				c.draw_rect(mr, Color("#6c7182"))
		for o in Levels.oneways(id):
			c.draw_rect(to.call(o), Color("#b8a080"))
		var lv := Levels.get_level(id)
		for b: Array in lv.barrels:
			c.draw_rect(to.call(Rect2(b[0] - 15, b[1] - 44, 30, 44)), Color("#c0392b"))
		for cr: Array in lv.crates:
			c.draw_rect(to.call(Rect2(cr[0] - 19, cr[1] - 38, 38, 38)), Color("#a8743f"))
