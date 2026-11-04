extends Control
## Lifetime stats for the people at this computer, kills by weapon and the latest matches.

signal navigate(to: String)

const UI := preload("res://scripts/ui.gd")
const Weapons := preload("res://scripts/game/weapons.gd")

var _confirm: Control


func _ready() -> void:
	size = UI.SIZE
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	UI.canvas(self, func(c: Control) -> void: c.draw_rect(Rect2(-1400, -900, 4080, 2520), Color("#101118")))
	UI.heading(self, "SKORLAR", Rect2(0, 22, 1280, 70), 58)
	var s := Scores.stats
	UI.card(self, Rect2(40, 104, 580, 530))
	UI.label(self, "GENEL", Rect2(64, 116, 300, 28), 18, UI.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	var matches := int(s.matches)
	var rate := "—" if matches == 0 else "%%%d" % int(round(100.0 * int(s.wins) / matches))
	var kd := "—" if int(s.deaths) == 0 else "%.2f" % (float(s.kills) / float(s.deaths))
	var tiles := [
		["Oynanan maç", str(matches)], ["Kazanılan maç", str(s.wins)], ["Kazanma oranı", rate],
		["Kazanılan tur", str(s.rounds)], ["Leş", str(s.kills)], ["Ölüm", str(s.deaths)],
		["Leş / ölüm", kd], ["Bir maçta en çok leş", str(s.best_kills)], ["Kafadan vuruş", str(s.headshots)],
		["Kırılan kutu", str(s.crates)], ["Patlatılan varil", str(s.barrels)], ["Sektirilen mermi", str(s.deflects)],
	]
	for i in tiles.size():
		var x := 64.0 + (i % 3) * 182.0
		var y := 152.0 + (i / 3) * 92.0
		var t: Array = tiles[i]
		UI.label(self, t[1], Rect2(x, y, 170, 44), 34, UI.INK, HORIZONTAL_ALIGNMENT_LEFT)
		UI.label(self, t[0], Rect2(x, y + 42, 170, 24), 13, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	UI.card(self, Rect2(640, 104, 600, 250))
	UI.label(self, "SİLAHA GÖRE LEŞ", Rect2(664, 116, 300, 28), 18, UI.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	var ks := [["Yumruk", "k_fist"], ["Tabanca", "k_pistol"], ["Pompalı", "k_shotgun"], ["Arbalet", "k_crossbow"], ["Kılıç", "k_sword"],
			["El bombası", "k_grenade"], ["Varil", "k_barrel"], ["Fırlatma", "k_thrown"], ["Düşürme", "k_fall"]]
	var top := 1
	for k: Array in ks:
		top = maxi(top, int(s[k[1]]))
	for i in ks.size():
		var x := 664.0 + (i % 3) * 190.0
		var y := 152.0 + (i / 3) * 62.0
		var k: Array = ks[i]
		UI.label(self, k[0], Rect2(x, y, 120, 24), 14, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		UI.label(self, str(s[k[1]]), Rect2(x + 120, y, 50, 24), 16, UI.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		var bar := ColorRect.new()
		bar.color = Color("#2a2d38")
		bar.position = Vector2(x, y + 28)
		bar.size = Vector2(170, 8)
		add_child(bar)
		var fill := ColorRect.new()
		fill.color = UI.ACCENT
		fill.position = Vector2(x, y + 28)
		fill.size = Vector2(170.0 * int(s[k[1]]) / top, 8)
		add_child(fill)
	UI.card(self, Rect2(640, 370, 600, 264))
	UI.label(self, "SON MAÇLAR", Rect2(664, 382, 300, 28), 18, UI.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	if Scores.recent.is_empty():
		UI.label(self, "Henüz maç yok. Hızlı oyunla başla!", Rect2(664, 470, 560, 30), 16, UI.MUTED)
	var y := 414.0
	for e: Dictionary in Scores.recent.slice(0, 7):
		var col: Color = Match.COLORS[clampi(int(e.get("color", 0)), 0, 3)]
		UI.label(self, str(e.get("date", "")), Rect2(664, y, 150, 26), 13, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		UI.label(self, "%s kazandı" % e.get("winner", "?"), Rect2(814, y, 190, 26), 15, col, HORIZONTAL_ALIGNMENT_LEFT)
		UI.label(self, "%d tur · %d leş" % [int(e.get("rounds", 0)), int(e.get("kills", 0))], Rect2(1004, y, 140, 26), 13, UI.INK, HORIZONTAL_ALIGNMENT_LEFT)
		UI.label(self, "✔" if e.get("human_won", false) else "", Rect2(1150, y, 60, 26), 16, UI.GOOD, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 30.0
	UI.button(self, "GERİ", Rect2(470, 652, 160, 50), go_back, 18)
	UI.button(self, "SIFIRLA", Rect2(650, 652, 160, 50), _ask_reset, 16)


func _ask_reset() -> void:
	_confirm = Control.new()
	_confirm.size = UI.SIZE
	add_child(_confirm)
	UI.dimmer(_confirm, 0.6)
	UI.card(_confirm, Rect2(400, 250, 480, 210))
	UI.label(_confirm, "Bütün skorlar silinsin mi?", Rect2(400, 280, 480, 40), 22)
	UI.label(_confirm, "Bu geri alınamaz.", Rect2(400, 320, 480, 28), 15, UI.MUTED)
	UI.button(_confirm, "VAZGEÇ", Rect2(440, 380, 190, 50), func() -> void:
		_confirm.queue_free()
		_confirm = null, 17)
	var yes := UI.button(_confirm, "SİL", Rect2(650, 380, 190, 50), func() -> void:
		Scores.reset()
		_confirm = null
		_build(), 17)
	yes.add_theme_color_override("font_color", UI.DANGER)


func go_back() -> void:
	if _confirm:
		_confirm.queue_free()
		_confirm = null
		return
	navigate.emit("menu")
