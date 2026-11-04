extends Control
## How to play: the controls for each device, what every weapon does, and a few tricks.

signal navigate(to: String)

const UI := preload("res://scripts/ui.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const Controls := preload("res://scripts/game/controls.gd")

const WEAPON_TEXT := {
	"fist": "Herkes yumrukla başlar. Üç vuruşluk kombonun sonuncusu rakibi savurur. Kutuları da yumrukla kırabilirsin.",
	"pistol": "10 mermi, hızlı ve isabetli. Kafaya gelen mermi daha çok acıtır.",
	"shotgun": "5 fişek, yakında yıkıcı, uzakta zayıf. Geri tepmesi seni de iter.",
	"crossbow": "4 ok, ağır hasar ve büyük itme. Ok süzülerek düşer, biraz yukarı nişan al.",
	"sword": "Sınırsız. Güçlü kesik atar ve doğru anda savurursan mermileri geri sektirir.",
	"grenade": "3 tane. Kavisli fırlatılır, sekerek 2 saniye sonra patlar.",
}


func _ready() -> void:
	size = UI.SIZE
	UI.canvas(self, func(c: Control) -> void: c.draw_rect(Rect2(-1400, -900, 4080, 2520), Color("#101118")))
	UI.heading(self, "NASIL OYNANIR", Rect2(0, 18, 1280, 70), 56)
	UI.card(self, Rect2(40, 96, 560, 540))
	UI.label(self, "KONTROLLER", Rect2(64, 108, 300, 30), 18, UI.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	var rows := [
		["", "Klavye 1", "Klavye 2", "Gamepad"],
		["Koş", "A / D", "← / →", "Sol çubuk"],
		["Zıpla", "W / Boşluk", "↑", "A"],
		["Eğil · in", "S", "↓", "Aşağı"],
		["Saldır · ateş", "Sol tık / F", "Enter", "X / RT"],
		["Fırlat", "Sağ tık / G", "Sağ Shift", "B"],
		["Nişan", "Fare", "Otomatik", "Sağ çubuk"],
		["Duraklat", "Esc / P", "Esc / P", "Start"],
	]
	var y := 146.0
	for r: Array in rows:
		var head: bool = r[0] == ""
		for k in 4:
			var x: float = 64.0 + [0.0, 140.0, 280.0, 410.0][k]
			UI.label(self, r[k], Rect2(x, y, 140, 28), 15 if not head else 14, (UI.MUTED if head or k == 0 else UI.INK), HORIZONTAL_ALIGNMENT_LEFT)
		y += 34.0
	UI.label(self, "İPUÇLARI", Rect2(64, 428, 300, 30), 18, UI.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	UI.para(self, "• Kırmızı varillere ateş et: patlar, yakındakileri savurur ve diğer varilleri de tutuşturur.\n"
			+ "• ↓ + zıpla ile ince platformlardan aşağı inersin.\n"
			+ "• Mermisi biten silahla ateş edersen onu rakibe fırlatırsın.\n"
			+ "• Eğilmek göğüs hizasındaki mermilerden korur. Klavyede silah öndeki rakibe, yoksa kutu ya da varile kendiliğinden yönelir.\n"
			+ "• Gökten yeni kutular düşer. 75 saniyeden sonra ani ölüm başlar.", Rect2(64, 462, 520, 170), 14, UI.INK)
	UI.card(self, Rect2(620, 96, 620, 540))
	UI.label(self, "SİLAHLAR", Rect2(644, 108, 300, 30), 18, UI.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	var icons := UI.canvas(self, _draw_icons)
	icons.queue_redraw()
	var wy := 146.0
	for t: String in ["fist", "pistol", "shotgun", "crossbow", "sword", "grenade"]:
		UI.label(self, Weapons.display_name(t), Rect2(740, wy, 200, 24), 17, UI.INK, HORIZONTAL_ALIGNMENT_LEFT)
		UI.para(self, WEAPON_TEXT[t], Rect2(740, wy + 24, 480, 50), 13, UI.MUTED)
		wy += 80.0
	UI.button(self, "GERİ", Rect2(560, 652, 160, 50), go_back, 18)


func _draw_icons(c: Control) -> void:
	var wy := 146.0
	for t: String in ["fist", "pistol", "shotgun", "crossbow", "sword", "grenade"]:
		var at := Vector2(688, wy + 30)
		c.draw_circle(at, 30.0, Color("#1d1f27"))
		if t == "fist":
			c.draw_circle(at, 9.0, Color("#0f0f14"))
			c.draw_circle(at, 7.0, Color("#e84545"))
		else:
			Weapons.draw(c, t, at + Vector2(-10 if t != "grenade" else 0, 2), 0.0, false, 1, 1.3 if t != "sword" else 1.0)
		wy += 80.0


func go_back() -> void:
	navigate.emit("menu")
