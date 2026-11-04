extends Control
## A match: steps the world at a fixed 120 Hz, feeds it the players' controls and the bots'
## choices, and draws the HUD, round banners, the pause menu and the end-of-match board.
## With `demo` set it is the menu's backdrop instead: bots only, silent, endless rounds.

signal navigate(to: String)

const UI := preload("res://scripts/ui.gd")
const World := preload("res://scripts/game/world.gd")
const WorldView := preload("res://scripts/game/world_view.gd")
const Controls := preload("res://scripts/game/controls.gd")
const AI := preload("res://scripts/game/ai.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const Levels := preload("res://scripts/game/levels.gd")
const Stickman := preload("res://scripts/game/stickman.gd")

const WEAPON_KEYS := {"fist": "fist", "pistol": "pistol", "shotgun": "shotgun", "crossbow": "crossbow",
		"sword": "sword", "grenade": "grenade", "barrel": "barrel", "thrown": "thrown", "fall": "fall"}

var demo := false
var world: World
var view: WorldView
var controls: Controls
var bots := {}
var _hud: Control
var _acc := 0.0
var _paused := false
var _pause_layer: Control
var _end_layer: Control
var _feed: Array = []
var _banner := {"text": "", "sub": "", "t": 9.0, "color": UI.INK, "len": 2.0}
var _hp := {}
var _round_done := false
var _over_sound := false
var _slots: Array = []


func _ready() -> void:
	size = UI.SIZE
	clip_contents = false
	view = WorldView.new()
	add_child(view)
	controls = Controls.new()
	add_child(controls)
	_hud = UI.canvas(self, _draw_hud)
	if demo:
		view.show_tags = false
		_slots = [{"type": "bot", "diff": 1}, {"type": "bot", "diff": 2}, {"type": "bot", "diff": 1}, {"type": "bot", "diff": 2}]
	else:
		_slots = Match.slots
		Match.start_match()
	_new_round()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.set_music_dim(false)


func _active() -> Array:
	var out := []
	for i in _slots.size():
		if _slots[i].type != "off":
			out.append(i)
	return out


func _new_round() -> void:
	var level: String = Levels.ORDER[randi() % Levels.ORDER.size()] if demo else Match.next_level()
	world = World.new()
	var players := []
	for i: int in _active():
		players.append({"id": i, "color": Match.COLORS[i]})
	world.setup(level, players)
	world.blood = Settings.get_value("blood")
	world.sudden_death = Settings.get_value("sudden_death") or demo
	view.set_world(world)
	bots = {}
	view.tags = {}
	for i: int in _active():
		if _slots[i].type == "bot":
			var b := AI.new()
			b.setup(i, int(_slots[i].diff), randi())
			bots[i] = b
			view.tags[i] = "B%d" % (i + 1)
		else:
			view.tags[i] = "P%d" % (i + 1)
		_hp[i] = 100.0
	_round_done = false
	_over_sound = false
	_acc = 0.0
	if not demo:
		_show_banner("TUR %d" % Match.round_no, Levels.display_name(level), UI.INK, World.COUNTDOWN)
		Sfx.play("beep")


func _show_banner(text: String, sub: String, color: Color, length := 2.0) -> void:
	_banner = {"text": text, "sub": sub, "t": 0.0, "color": color, "len": length}


# --- Frame loop ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not demo and controls.pad_pause() and _end_layer == null:
		_toggle_pause()
	_banner.t += delta
	for e: Dictionary in _feed:
		e.t += delta
	_feed = _feed.filter(func(e: Dictionary) -> bool: return e.t < 5.0)
	if _paused:
		_hud.queue_redraw()
		return
	var human_inputs := {}
	var mouse := view.get_local_mouse_position()
	var p1 := -1
	for i: int in _active():
		if _slots[i].type == "human":
			var dev: String = _slots[i].device
			var aim := Vector2.ZERO
			var f := world.fighter(i)
			if dev == "k1" and int(Settings.get_value("aim")) == 0 and controls.mouse_active and f and f.alive:
				aim = mouse - f.center()
				p1 = i
			human_inputs[i] = controls.read(dev, aim)
	_acc += minf(delta, 0.05)
	var first := true
	while _acc >= World.DT:
		_acc -= World.DT
		var inputs := {}
		for i: int in human_inputs:
			var inp: Dictionary = human_inputs[i]
			if not first:
				inp = inp.duplicate()
				inp.jump = false
				inp.attack = false
				inp.throw = false
			inputs[i] = inp
		for i: int in bots:
			inputs[i] = bots[i].think(world, World.DT)
		world.step(inputs)
		first = false
	_handle_events()
	for i: int in _hp:
		var f := world.fighter(i)
		if f:
			_hp[i] = lerpf(_hp[i], maxf(f.hp, 0.0), 1.0 - exp(-10.0 * delta))
	var show_cross := p1 >= 0 and _end_layer == null and world.fighter(p1).alive
	view.crosshair = mouse if show_cross else Vector2(-9999, 0)
	view.crosshair_color = Match.COLORS[p1] if p1 >= 0 else Color.WHITE
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if show_cross else Input.MOUSE_MODE_VISIBLE
	if world.finished and not _round_done:
		_round_done = true
		_end_round()
	_hud.queue_redraw()


func _handle_events() -> void:
	for e: Dictionary in world.events:
		match e.type:
			"sound":
				if not demo:
					Sfx.play(e.name, e.get("db", 0.0))
			"shake":
				if not demo:
					view.add_shake(e.amount)
			"explosion":
				view.flash(0.6 if not demo else 0.2)
			"go":
				if not demo:
					_show_banner("KAPIŞ!", "", UI.ACCENT, 0.9)
					Sfx.play("go")
			"sudden":
				if not demo:
					_show_banner("ANİ ÖLÜM!", "Gökten yanan variller yağıyor", UI.DANGER, 2.2)
			"kill":
				_on_kill(e)
			"crate":
				if not demo and int(e.by) >= 0 and Match.is_human(e.by):
					Scores.add("crates")
			"round_over":
				if not demo:
					var w: int = e.winner
					if w >= 0:
						_show_banner("%s TURU ALDI!" % Match.COLOR_NAMES[w], Match.player_name(w), Match.COLORS[w], 3.0)
						if not _over_sound:
							Sfx.play("round")
					else:
						_show_banner("BERABERE!", "Bu turu kimse almadı", UI.MUTED, 3.0)
						Sfx.play("draw")
					_over_sound = true
	world.events.clear()


func _on_kill(e: Dictionary) -> void:
	var killer: int = e.killer
	var victim: int = e.victim
	_feed.push_front({"killer": killer, "victim": victim, "weapon": e.weapon, "head": e.get("head", false), "t": 0.0})
	_feed = _feed.slice(0, 5)
	if demo:
		return
	Match.totals[victim].deaths += 1
	if killer >= 0:
		Match.totals[killer].kills += 1
	if Match.is_human(victim):
		Scores.add("deaths")
	if killer >= 0 and killer != victim and Match.is_human(killer):
		Scores.add_kill(WEAPON_KEYS.get(e.weapon, "fist"))
		if e.get("head", false):
			Scores.add("headshots")


func _end_round() -> void:
	if demo:
		_new_round()
		return
	var w := world.winner
	if w >= 0:
		Match.wins[w] += 1
		if Match.is_human(w):
			Scores.add("rounds")
	for i: int in world.stats:
		var s: Dictionary = world.stats[i]
		Match.totals[i].damage += int(s.damage)
		Match.totals[i].crates += int(s.crates)
		Match.totals[i].barrels += int(s.barrels)
		if Match.is_human(i):
			Scores.add("barrels", int(s.barrels))
			Scores.add("deflects", int(s.deflects))
	Scores.save()
	if Match.match_winner() >= 0:
		_show_end()
	else:
		_new_round()


# --- Pause and end of match ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if demo:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P and _end_layer == null:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func go_back() -> void:
	if demo:
		return
	if _end_layer:
		navigate.emit("menu")
	else:
		_toggle_pause()


func _toggle_pause() -> void:
	_paused = not _paused
	Sfx.set_music_dim(_paused)
	if _pause_layer:
		_pause_layer.queue_free()
		_pause_layer = null
	if not _paused:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_layer = Control.new()
	_pause_layer.size = UI.SIZE
	add_child(_pause_layer)
	UI.dimmer(_pause_layer, 0.55)
	UI.card(_pause_layer, Rect2(440, 170, 400, 400))
	UI.heading(_pause_layer, "DURAKLATILDI", Rect2(440, 190, 400, 60), 46)
	UI.label(_pause_layer, "Tur %d · %s" % [Match.round_no, Levels.display_name(world.level_id)], Rect2(440, 248, 400, 28), 16, UI.MUTED)
	UI.button(_pause_layer, "DEVAM ET", Rect2(500, 292, 280, 50), _toggle_pause, 20)
	UI.button(_pause_layer, "MAÇI YENİDEN BAŞLAT", Rect2(500, 352, 280, 50), func() -> void: navigate.emit("game"), 18)
	var sound := UI.button(_pause_layer, "", Rect2(500, 412, 135, 44), func() -> void: pass, 16)
	var music := UI.button(_pause_layer, "", Rect2(645, 412, 135, 44), func() -> void: pass, 16)
	var refresh := func() -> void:
		sound.text = "Ses: " + ("Açık" if Settings.get_value("sound") else "Kapalı")
		music.text = "Müzik: " + ("Açık" if Settings.get_value("music") else "Kapalı")
	refresh.call()
	sound.pressed.connect(func() -> void:
		Settings.set_value("sound", not Settings.get_value("sound"))
		refresh.call())
	music.pressed.connect(func() -> void:
		Settings.set_value("music", not Settings.get_value("music"))
		refresh.call())
	UI.button(_pause_layer, "ANA MENÜ", Rect2(500, 494, 280, 50), func() -> void: navigate.emit("menu"), 18)


func _show_end() -> void:
	var winner := Match.match_winner()
	Sfx.play("victory")
	var human_kills := 0
	for i: int in _active():
		if Match.is_human(i):
			human_kills += int(Match.totals[i].kills)
	Scores.record_match({
		"winner": Match.player_name(winner), "color": winner, "human_won": Match.is_human(winner),
		"kills": human_kills, "rounds": Match.round_no, "players": _active().size(),
	})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_end_layer = Control.new()
	_end_layer.size = UI.SIZE
	add_child(_end_layer)
	UI.dimmer(_end_layer, 0.5)
	UI.card(_end_layer, Rect2(250, 110, 780, 500))
	UI.label(_end_layer, "MAÇI KAZANAN", Rect2(250, 128, 780, 30), 18, UI.MUTED)
	UI.heading(_end_layer, Match.COLOR_NAMES[winner], Rect2(250, 154, 780, 80), 72, Match.COLORS[winner])
	UI.label(_end_layer, "%s · %d tur" % [Match.player_name(winner), Match.round_no], Rect2(250, 232, 780, 26), 17, UI.INK)
	var cols := [["Oyuncu", 300.0, HORIZONTAL_ALIGNMENT_LEFT], ["Tur", 540.0, HORIZONTAL_ALIGNMENT_CENTER], ["Leş", 630.0, HORIZONTAL_ALIGNMENT_CENTER],
			["Ölüm", 720.0, HORIZONTAL_ALIGNMENT_CENTER], ["Hasar", 810.0, HORIZONTAL_ALIGNMENT_CENTER], ["Kutu", 900.0, HORIZONTAL_ALIGNMENT_CENTER]]
	for c: Array in cols:
		UI.label(_end_layer, c[0], Rect2(c[1] - (0.0 if c[2] == HORIZONTAL_ALIGNMENT_LEFT else 45.0), 278, 90 if c[2] != HORIZONTAL_ALIGNMENT_LEFT else 200, 24), 15, UI.MUTED, c[2])
	var order := _active()
	order.sort_custom(func(a: int, b: int) -> bool: return Match.wins[a] > Match.wins[b] or (Match.wins[a] == Match.wins[b] and Match.totals[a].kills > Match.totals[b].kills))
	var y := 308.0
	for i: int in order:
		var t: Dictionary = Match.totals[i]
		var row := Color(Match.COLORS[i], 0.14)
		var bg := ColorRect.new()
		bg.color = row
		bg.position = Vector2(286, y - 2)
		bg.size = Vector2(708, 40)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_end_layer.add_child(bg)
		UI.label(_end_layer, "%s  %s" % [Match.COLOR_NAMES[i], Match.player_name(i)], Rect2(300, y, 240, 36), 18, Match.COLORS[i], HORIZONTAL_ALIGNMENT_LEFT)
		var vals := [Match.wins[i], t.kills, t.deaths, t.damage, t.crates]
		for k in vals.size():
			UI.label(_end_layer, str(vals[k]), Rect2(cols[k + 1][1] - 45.0, y, 90, 36), 20, UI.INK)
		y += 46.0
	UI.button(_end_layer, "RÖVANŞ", Rect2(300, 536, 220, 54), func() -> void: navigate.emit("game"), 20)
	UI.button(_end_layer, "OYUN KUR", Rect2(530, 536, 220, 54), func() -> void: navigate.emit("setup"), 18)
	UI.button(_end_layer, "ANA MENÜ", Rect2(760, 536, 220, 54), func() -> void: navigate.emit("menu"), 18)


# --- HUD -------------------------------------------------------------------------------------

func _draw_hud(c: Control) -> void:
	if world == null or demo:
		return
	var ids := _active()
	var card_w := 232.0
	var gap := 12.0
	var x0 := (UI.SIZE.x - (card_w * ids.size() + gap * (ids.size() - 1))) * 0.5
	for k in ids.size():
		var i: int = ids[k]
		_draw_card(c, Rect2(x0 + k * (card_w + gap), 8, card_w, 52), i)
	# Sudden death clock.
	if world.state == "fight" and world.sudden_death:
		if world.sudden:
			if int(world.time * 3.0) % 2 == 0:
				UI.draw_text(c, "ANİ ÖLÜM", Vector2(640, 84), 20, UI.DANGER, 5)
		else:
			var left := maxi(0, int(ceil(World.SUDDEN_DEATH - world.state_t)))
			if left <= 30:
				UI.draw_text(c, "Ani ölüme %d sn" % left, Vector2(640, 82), 16, Color(UI.INK, 0.75), 4, UI.body_font())
	# Kill feed.
	var fy := 92.0
	for e: Dictionary in _feed:
		var a := clampf(5.0 - float(e.t), 0.0, 1.0)
		_draw_feed_line(c, e, Vector2(1266, fy), a)
		fy += 26.0
	# Round banner.
	var bt: float = _banner.t
	var blen: float = _banner.len
	if bt < blen and _banner.text != "":
		var a := clampf(minf(bt * 6.0, (blen - bt) * 3.0), 0.0, 1.0)
		var pop := 1.0 + maxf(0.0, 0.25 - bt) * 1.2
		var col: Color = _banner.color
		UI.draw_text(c, _banner.text, Vector2(640, 330), int(76 * pop), Color(col, a), 14)
		if _banner.sub != "":
			UI.draw_text(c, _banner.sub, Vector2(640, 372), 22, Color(UI.INK, a * 0.9), 6, UI.body_font())


func _draw_card(c: Control, r: Rect2, i: int) -> void:
	var f := world.fighter(i)
	var col: Color = Match.COLORS[i]
	var dead := f == null or not f.alive
	c.draw_rect(r, Color(0.06, 0.065, 0.085, 0.82))
	c.draw_rect(Rect2(r.position, Vector2(6, r.size.y)), col if not dead else col.darkened(0.5))
	c.draw_rect(r, Color(col, 0.55 if not dead else 0.2), false, 2.0)
	var name := Match.player_name(i)
	UI.draw_text(c, name, r.position + Vector2(16, 20), 15, col if not dead else Color(col, 0.5), 3, UI.body_font(), HORIZONTAL_ALIGNMENT_LEFT)
	# Rounds won.
	for k in Match.target_wins:
		var p := r.position + Vector2(r.size.x - 12.0 - (Match.target_wins - 1 - k) * 12.0, 14)
		c.draw_circle(p, 4.5, Color(0, 0, 0, 0.6))
		if k < Match.wins[i]:
			c.draw_circle(p, 3.6, UI.ACCENT)
		else:
			c.draw_arc(p, 3.6, 0.0, TAU, 12, Color(UI.INK, 0.35), 1.2, true)
	# Health.
	var hp_r := Rect2(r.position + Vector2(16, 30), Vector2(130, 10))
	c.draw_rect(hp_r, Color(0, 0, 0, 0.55))
	var k: float = clampf(float(_hp.get(i, 0.0)) / Stickman.MAX_HP, 0.0, 1.0)
	c.draw_rect(Rect2(hp_r.position, Vector2(hp_r.size.x * k, hp_r.size.y)), UI.GOOD.lerp(UI.DANGER, 1.0 - k))
	if dead:
		UI.draw_text(c, "ELENDİ", hp_r.get_center() + Vector2(0, 5), 13, UI.DANGER, 3, UI.body_font())
	# Weapon and ammo.
	if f and f.alive:
		var wp := r.position + Vector2(176, 36)
		if f.weapon == "":
			UI.draw_text(c, "Yumruk", wp + Vector2(10, 4), 13, Color(UI.INK, 0.6), 3, UI.body_font())
		else:
			Weapons.draw(c, f.weapon, wp + Vector2(-6, 0), 0.0, false, f.ammo, 0.9)
			if f.weapon != "sword":
				UI.draw_text(c, "%d" % f.ammo, wp + Vector2(38, 6), 15, UI.INK if f.ammo > 0 else UI.DANGER, 3, UI.body_font())


func _draw_feed_line(c: Control, e: Dictionary, right: Vector2, a: float) -> void:
	var victim: int = e.victim
	var killer: int = e.killer
	var fnt := UI.body_font()
	var vname: String = Match.COLOR_NAMES[victim]
	var x := right.x
	var vw := UI.text_width(vname, 15, fnt)
	c.draw_rect(Rect2(x - 270, right.y - 16, 276, 23), Color(0, 0, 0, 0.45 * a))
	UI.draw_text(c, vname, Vector2(x - vw, right.y), 15, Color(Match.COLORS[victim], a), 3, fnt, HORIZONTAL_ALIGNMENT_LEFT)
	x -= vw + 8.0
	var weapon: String = e.weapon
	var icon_w := 40.0
	if weapon in Weapons.DEFS:
		Weapons.draw(c, weapon, Vector2(x - icon_w + 10, right.y - 5), 0.0, false, 1, 0.75, a)
	else:
		var label: String = {"fist": "yumruk", "barrel": "varil", "thrown": "fırlatma", "fall": "düştü"}.get(weapon, weapon)
		icon_w = UI.text_width(label, 13, fnt) + 4.0
		UI.draw_text(c, label, Vector2(x - icon_w, right.y), 13, Color(UI.ACCENT, a), 3, fnt, HORIZONTAL_ALIGNMENT_LEFT)
	x -= icon_w + 8.0
	if e.head:
		UI.draw_text(c, "KAFA", Vector2(x - 34, right.y), 12, Color(UI.DANGER, a), 3, fnt, HORIZONTAL_ALIGNMENT_LEFT)
		x -= 40.0
	if killer >= 0 and killer != victim:
		var kname: String = Match.COLOR_NAMES[killer]
		var kw := UI.text_width(kname, 15, fnt)
		UI.draw_text(c, kname, Vector2(x - kw, right.y), 15, Color(Match.COLORS[killer], a), 3, fnt, HORIZONTAL_ALIGNMENT_LEFT)
