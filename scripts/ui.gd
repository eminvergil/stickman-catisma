extends RefCounted
## Shared look for every screen: colours, the theme, and small builders for labels, buttons,
## cards and segmented choices. Buttons made here play the click sound.

const ACCENT := Color("#ff9f1c")
const INK := Color("#f3efe6")
const MUTED := Color(0.95, 0.94, 0.9, 0.6)
const DANGER := Color("#ef4a3c")
const GOOD := Color("#7bd66a")
const PANEL := Color("#15161c")
const SIZE := Vector2(1280, 720)

static var _heading_font: SystemFont
static var _body_font: SystemFont


## Tall condensed font for titles and banners.
static func heading_font() -> Font:
	if _heading_font == null:
		_heading_font = SystemFont.new()
		_heading_font.font_names = PackedStringArray(["Impact", "Haettenschweiler", "Arial Narrow", "Arial Black", "DejaVu Sans Condensed"])
		_heading_font.font_weight = 900
	return _heading_font


static func body_font() -> Font:
	if _body_font == null:
		_body_font = SystemFont.new()
		_body_font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Segoe UI", "Roboto", "Ubuntu", "DejaVu Sans", "Arial"])
		_body_font.font_weight = 600
	return _body_font


static func build_theme() -> Theme:
	var th := Theme.new()
	th.default_font = body_font()
	th.default_font_size = 18
	var fills := {
		"normal": Color("#1d1f27"), "hover": Color("#2a2d38"), "pressed": Color("#b8650d"),
		"hover_pressed": Color("#cf7410"), "disabled": Color("#1d1f27", 0.45),
	}
	for state: String in fills:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fills[state]
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		sb.border_color = ACCENT if state.contains("pressed") or state == "hover" else Color("#4a4f60", 0.9)
		if state == "disabled":
			sb.border_color = Color("#4a4f60", 0.3)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 4
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		th.set_stylebox(state, "Button", sb)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		th.set_color(c, "Button", INK)
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		th.set_color(c, "Button", Color("#1a1206"))
	th.set_color("font_disabled_color", "Button", Color(INK, 0.35))
	th.set_color("font_color", "Label", INK)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))
	th.set_constant("outline_size", "Label", 3)

	var card := StyleBoxFlat.new()
	card.bg_color = Color(PANEL, 0.95)
	card.set_corner_radius_all(10)
	card.set_border_width_all(2)
	card.border_color = Color("#3b3f4d")
	card.shadow_color = Color(0, 0, 0, 0.5)
	card.shadow_size = 16
	th.set_stylebox("panel", "Panel", card)

	var track := StyleBoxFlat.new()
	track.bg_color = Color("#0d0e12")
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#d9760e")
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)

	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Color("#4a4f60", 0.8)
	scroll.set_corner_radius_all(4)
	th.set_stylebox("grabber", "VScrollBar", scroll)
	th.set_stylebox("grabber_highlight", "VScrollBar", scroll)
	th.set_stylebox("grabber_pressed", "VScrollBar", scroll)
	th.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return th


static func label(parent: Node, text: String, r: Rect2, fs: int, color := INK,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## A left-aligned, word-wrapped paragraph that starts at the top of `r`.
static func para(parent: Node, text: String, r: Rect2, fs: int, color := INK) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	l.custom_minimum_size = Vector2(r.size.x, 0)
	l.text = text
	l.position = r.position
	l.size = r.size
	parent.add_child(l)
	return l


## Big title in the heading font.
static func heading(parent: Node, text: String, r: Rect2, fs: int, color := ACCENT) -> Label:
	var l := label(parent, text, r, fs, color)
	l.add_theme_font_override("font", heading_font())
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color("#120c05"))
	return l


static func button(parent: Node, text: String, r: Rect2, action: Callable, fs := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(func() -> void: Sfx.play("click", -4))
	b.mouse_entered.connect(func() -> void: Sfx.play("hover", -14))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


static func card(parent: Node, r: Rect2) -> Panel:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	parent.add_child(p)
	return p


## A row of toggle buttons where exactly one is on; `on_pick` gets the chosen index.
static func choice(parent: Node, options: Array, r: Rect2, current: int, on_pick: Callable, fs := 18) -> Array[Button]:
	var group := ButtonGroup.new()
	var out: Array[Button] = []
	var w := (r.size.x - 8 * (options.size() - 1)) / options.size()
	for i in options.size():
		var b := button(parent, options[i], Rect2(r.position + Vector2(i * (w + 8), 0), Vector2(w, r.size.y)), on_pick.bind(i), fs)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == current
		out.append(b)
	return out


## Full-screen dimmer that swallows clicks; dialogs are built on top of it.
static func dimmer(parent: Node, alpha := 0.6) -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, alpha)
	d.position = Vector2(-2000, -2000)
	d.size = SIZE + Vector2(4000, 4000)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(d)
	return d


## A plain Control that draws with `fn(control)`; for layers that paint above children.
static func canvas(parent: Node, fn: Callable, r := Rect2(Vector2.ZERO, SIZE)) -> Control:
	var c := Control.new()
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: fn.call(c))
	parent.add_child(c)
	return c


## Text drawn straight onto a canvas, centred on `at` (x) with its baseline at `at.y`,
## outlined so it reads over anything.
static func draw_text(ci: CanvasItem, text: String, at: Vector2, fs: int, color: Color, outline := 8,
		font: Font = null, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var fnt := font if font else heading_font()
	var w := fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	if outline > 0:
		ci.draw_string_outline(fnt, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, color.a * 0.85))
	ci.draw_string(fnt, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


static func text_width(text: String, fs: int, font: Font = null) -> float:
	var fnt := font if font else heading_font()
	return fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
