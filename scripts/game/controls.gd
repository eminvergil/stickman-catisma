extends Node
## Turns the keyboard, the mouse and gamepads into fighter input. Two people can share one
## keyboard ("k1" left side + mouse, "k2" arrows), and each gamepad is a device of its own.
##
## Key states are tracked from input events (not polled), so a tap shorter than a frame still
## registers and the right Shift can be told apart from the left one.

const SCHEMES := {
	"k1": {
		"left": [KEY_A], "right": [KEY_D], "up": [KEY_W, KEY_SPACE], "down": [KEY_S],
		"attack": [KEY_F], "throw": [KEY_G, KEY_E], "mouse": true,
	},
	"k2": {
		"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
		"attack": [KEY_ENTER, KEY_KP_ENTER, KEY_KP_1, KEY_PERIOD], "throw": [-KEY_SHIFT, KEY_KP_2, KEY_SLASH],
	},
}
const DEADZONE := 0.3

## Keys are stored as physical keycodes; a negative code means "the right-hand one".
var _held := {}
var _pressed := {}
var _mouse := {}
var _mouse_pressed := {}
var _pad_pressed := {}
var _prev := {}
## "k1" aims with the mouse only after the mouse has been used; pressing the keyboard attack
## or throw keys hands aiming back to the keyboard until the mouse moves again.
var mouse_active := false


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := int(k.physical_keycode if k.physical_keycode != 0 else k.keycode)
		var codes := [code]
		if k.location == KEY_LOCATION_RIGHT:
			codes.append(-code)
		for c in codes:
			_held[c] = k.pressed
			if k.pressed and not k.echo:
				_pressed[c] = true
		if k.pressed and (code in SCHEMES.k1.attack or code in SCHEMES.k1.throw):
			mouse_active = false
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		_mouse[m.button_index] = m.pressed
		if m.pressed:
			_mouse_pressed[m.button_index] = true
			mouse_active = true
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > 3.0:
			mouse_active = true
	elif event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		if b.pressed:
			_pad_pressed["%d:%d" % [b.device, b.button_index]] = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_held.clear()
		_mouse.clear()


func _any(keys: Array, table: Dictionary) -> bool:
	for k: int in keys:
		if table.get(k, false):
			return true
	return false


## Input for `scheme` this frame. `mouse_aim` is the aim vector for "k1" (zero for none).
## Presses are consumed: call once per frame and give the result's presses to one step only.
func read(scheme: String, mouse_aim := Vector2.ZERO) -> Dictionary:
	if scheme.begins_with("pad"):
		return _read_pad(int(scheme.substr(3)))
	var s: Dictionary = SCHEMES.get(scheme, SCHEMES.k1)
	var out := {
		"move": (1.0 if _any(s.right, _held) else 0.0) - (1.0 if _any(s.left, _held) else 0.0),
		"jump": _any(s.up, _pressed),
		"jump_held": _any(s.up, _held),
		"down": _any(s.down, _held),
		"attack": _any(s.attack, _pressed),
		"attack_held": _any(s.attack, _held),
		"throw": _any(s.throw, _pressed),
		"aim": Vector2.ZERO,
	}
	if s.get("mouse", false):
		out.attack = out.attack or _mouse_pressed.get(MOUSE_BUTTON_LEFT, false)
		out.attack_held = out.attack_held or _mouse.get(MOUSE_BUTTON_LEFT, false)
		out.throw = out.throw or _mouse_pressed.get(MOUSE_BUTTON_RIGHT, false)
		out.aim = mouse_aim
	for keys in [s.up, s.attack, s.throw]:
		for k: int in keys:
			_pressed.erase(k)
	if s.get("mouse", false):
		_mouse_pressed.clear()
	return out


func _read_pad(slot: int) -> Dictionary:
	var pads := Input.get_connected_joypads()
	var out := {"move": 0.0, "jump": false, "jump_held": false, "down": false, "attack": false,
			"attack_held": false, "throw": false, "aim": Vector2.ZERO}
	if slot >= pads.size():
		return out
	var dev: int = pads[slot]
	var lx := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	var move := 0.0 if absf(lx) < DEADZONE else lx
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT):
		move = -1.0
	elif Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT):
		move = 1.0
	out.move = clampf(move * 1.25, -1.0, 1.0)
	out.down = ly > 0.55 or Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN)
	out.jump_held = Input.is_joy_button_pressed(dev, JOY_BUTTON_A) or Input.is_joy_button_pressed(dev, JOY_BUTTON_LEFT_SHOULDER)
	var trig := Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	out.attack_held = Input.is_joy_button_pressed(dev, JOY_BUTTON_X) or Input.is_joy_button_pressed(dev, JOY_BUTTON_RIGHT_SHOULDER) or trig
	out.jump = _pad_take(dev, JOY_BUTTON_A) or _pad_take(dev, JOY_BUTTON_LEFT_SHOULDER)
	out.attack = _pad_take(dev, JOY_BUTTON_X) or _pad_take(dev, JOY_BUTTON_RIGHT_SHOULDER)
	var key := "trig%d" % dev
	if trig and not _prev.get(key, false):
		out.attack = true
	_prev[key] = trig
	out.throw = _pad_take(dev, JOY_BUTTON_B) or _pad_take(dev, JOY_BUTTON_Y)
	var aim := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
	if aim.length() > 0.4:
		out.aim = aim.normalized()
	return out


func _pad_take(dev: int, button: int) -> bool:
	var key := "%d:%d" % [dev, button]
	if _pad_pressed.get(key, false):
		_pad_pressed.erase(key)
		return true
	return false


## Whether START was pressed on any pad (opens the pause menu).
func pad_pause() -> bool:
	for dev in Input.get_connected_joypads():
		if _pad_take(dev, JOY_BUTTON_START):
			return true
	return false


static func key_name(code: int) -> String:
	if code < 0:
		return "Sağ " + key_name(-code)
	var label: int = code
	if DisplayServer.get_name() != "headless":
		label = DisplayServer.keyboard_get_label_from_physical(code)
	var s := OS.get_keycode_string(label if label != 0 else code)
	match s:
		"Space":
			return "Boşluk"
		"Enter":
			return "Enter"
		"Left":
			return "←"
		"Right":
			return "→"
		"Up":
			return "↑"
		"Down":
			return "↓"
		"Shift":
			return "Shift"
	return s


## "A / D" style text listing the keys for an action, for the help screen.
static func keys_text(scheme: String, action: String, limit := 2) -> String:
	var keys: Array = SCHEMES[scheme][action]
	var names := []
	for k: int in keys.slice(0, limit):
		names.append(key_name(k))
	return " / ".join(names)
