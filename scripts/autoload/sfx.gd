extends Node
## Sound effects and a music loop, all synthesized at startup so the project needs no audio
## files. The music renders on a worker thread.

const RATE := 22050
const BPM := 118.0
const A1 := 55.0
const C2 := 65.41
const D2 := 73.42
const E2 := 82.41
const F2 := 87.31
const G2 := 98.0
const A3 := 220.0
const C4 := 261.63
const D4 := 293.66
const E4 := 329.63
const G4 := 392.0
const A4 := 440.0
const C5 := 523.25
const E5 := 659.25
const G5 := 783.99
## One bass root per bar: Am Am F G | Am Am Dm E.
const ROOTS := [A1, A1, F2, G2, A1, A1, D2, E2]
const LEAD := [A4, C5, E5, D4 * 2.0, C5, A4, G4, E4]

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()
var _music := AudioStreamPlayer.new()
var _music_task := -1
var _last_played := {}


func _ready() -> void:
	for i in 24:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	add_child(_music)
	_build()
	Settings.changed.connect(_on_setting_changed)
	if DisplayServer.get_name() != "headless":
		_music_task = WorkerThreadPool.add_task(_build_music)


func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)


## `vary` randomizes the pitch a little so repeated sounds don't feel mechanical. The same
## sound started again within 30 ms is skipped, so a shotgun's seven pellets don't stack.
func play(sound: String, volume_db := 0.0, vary := 0.06) -> void:
	if not Settings.get_value("sound") or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -1000)) < 30:
		return
	_last_played[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = 1.0 + _rng.randf_range(-vary, vary)
	p.volume_db = volume_db + linear_to_db(maxf(0.001, Settings.get_value("volume") / 100.0))
	p.play()


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


## Ducks the music while the game is paused.
func set_music_dim(dim: bool) -> void:
	if _music.stream:
		_music.volume_db = _music_db() - (12.0 if dim else 0.0)


func _music_db() -> float:
	return linear_to_db(maxf(0.001, Settings.get_value("music_volume") / 100.0 * 0.55))


func _on_setting_changed(key: String) -> void:
	if key == "music" or key == "music_volume":
		_update_music()


func _update_music() -> void:
	if _music.stream == null:
		return
	_music.volume_db = _music_db()
	if Settings.get_value("music") and not _music.playing:
		_music.play()
	elif not Settings.get_value("music") and _music.playing:
		_music.stop()


func _on_music_ready(wav: AudioStreamWAV) -> void:
	_music_task = -1
	_music.stream = wav
	_update_music()


# Each tone: [frequency, start, duration, amplitude, wave?, end_frequency?]
# For "noise" the frequency is the low-pass amount (0..1, lower = darker); "metal" stacks
# inharmonic partials like a struck bar.
func _build() -> void:
	_streams["click"] = _render([[1300.0, 0.0, 0.035, 0.16]])
	_streams["hover"] = _render([[900.0, 0.0, 0.03, 0.06, "tri", 1100.0]])
	_streams["swing"] = _render([[0.22, 0.0, 0.11, 0.2, "noise"], [0.5, 0.02, 0.06, 0.08, "noise"]])
	_streams["punch"] = _render([[160.0, 0.0, 0.09, 0.55, "sine", 60.0], [0.6, 0.0, 0.04, 0.4, "noise"], [0.2, 0.01, 0.08, 0.25, "noise"]])
	_streams["punch_h"] = _render([[130.0, 0.0, 0.15, 0.65, "sine", 42.0], [0.8, 0.0, 0.05, 0.5, "noise"], [0.18, 0.0, 0.14, 0.35, "noise"]])
	_streams["pistol"] = _render([[0.92, 0.0, 0.11, 0.55, "noise"], [0.3, 0.0, 0.2, 0.4, "noise"], [190.0, 0.0, 0.08, 0.4, "sine", 60.0]])
	_streams["shotgun"] = _render([
		[0.85, 0.0, 0.2, 0.7, "noise"], [0.14, 0.0, 0.5, 0.6, "noise"], [110.0, 0.0, 0.28, 0.6, "sine", 32.0],
		[1500.0, 0.42, 0.03, 0.12, "square"], [800.0, 0.52, 0.04, 0.14, "square"], [0.7, 0.42, 0.04, 0.12, "noise"],
	])
	_streams["crossbow"] = _render([[200.0, 0.0, 0.32, 0.32, "tri", 172.0], [400.0, 0.0, 0.18, 0.12, "saw", 350.0], [0.5, 0.0, 0.08, 0.25, "noise"]])
	_streams["bolt_hit"] = _render([[0.4, 0.0, 0.06, 0.45, "noise"], [230.0, 0.0, 0.11, 0.35, "sine", 110.0], [600.0, 0.0, 0.08, 0.06, "tri", 500.0]])
	_streams["sword"] = _render([[0.12, 0.0, 0.18, 0.32, "noise"], [0.45, 0.03, 0.1, 0.16, "noise"], [1800.0, 0.0, 0.1, 0.03, "sine", 2600.0]])
	_streams["slice"] = _render([[0.9, 0.0, 0.07, 0.38, "noise"], [2600.0, 0.0, 0.12, 0.06, "sine", 1700.0], [150.0, 0.0, 0.1, 0.4, "sine", 60.0]])
	_streams["clang"] = _render([[1250.0, 0.0, 0.5, 0.2, "metal"], [0.95, 0.0, 0.03, 0.3, "noise"]])
	_streams["ricochet"] = _render([[2400.0, 0.0, 0.25, 0.1, "sine", 1300.0], [0.9, 0.0, 0.02, 0.25, "noise"]])
	_streams["empty"] = _render([[2000.0, 0.0, 0.02, 0.2, "square"], [1400.0, 0.04, 0.02, 0.15, "square"]])
	_streams["throw"] = _render([[0.3, 0.0, 0.16, 0.25, "noise"], [0.6, 0.04, 0.08, 0.1, "noise"]])
	_streams["bounce"] = _render([[1700.0, 0.0, 0.07, 0.12, "sine", 1450.0], [0.8, 0.0, 0.02, 0.18, "noise"]])
	_streams["pin"] = _render([[2300.0, 0.0, 0.14, 0.08], [3400.0, 0.0, 0.1, 0.05], [0.9, 0.0, 0.015, 0.15, "noise"]])
	_streams["boom"] = _render([[95.0, 0.0, 1.0, 0.75, "sine", 24.0], [0.05, 0.0, 1.3, 0.95, "noise"], [0.5, 0.0, 0.3, 0.55, "noise"], [0.2, 0.05, 0.6, 0.4, "noise"]])
	_streams["crate_hit"] = _render([[0.35, 0.0, 0.05, 0.45, "noise"], [260.0, 0.0, 0.08, 0.32, "tri", 170.0]])
	_streams["crate_break"] = _render([
		[0.7, 0.0, 0.04, 0.5, "noise"], [0.5, 0.03, 0.05, 0.45, "noise"], [0.65, 0.07, 0.06, 0.35, "noise"],
		[210.0, 0.0, 0.15, 0.35, "tri", 90.0], [0.18, 0.0, 0.3, 0.3, "noise"],
	])
	_streams["barrel_hit"] = _render([[170.0, 0.0, 0.5, 0.22, "metal"], [0.6, 0.0, 0.03, 0.2, "noise"]])
	_streams["fuse"] = _render([[0.95, 0.0, 0.3, 0.14, "noise"], [0.7, 0.0, 0.3, 0.06, "noise"]])
	_streams["pickup"] = _render([[500.0, 0.0, 0.07, 0.2, "tri", 900.0], [900.0, 0.06, 0.09, 0.18, "tri", 1350.0]])
	_streams["jump"] = _render([[0.3, 0.0, 0.07, 0.12, "noise"], [300.0, 0.0, 0.06, 0.05, "tri", 460.0]])
	_streams["land"] = _render([[0.2, 0.0, 0.06, 0.2, "noise"], [90.0, 0.0, 0.06, 0.16, "sine", 50.0]])
	_streams["drop"] = _render([[0.25, 0.0, 0.14, 0.4, "noise"], [110.0, 0.0, 0.12, 0.35, "sine", 55.0]])
	_streams["hurt"] = _render([[0.5, 0.0, 0.06, 0.3, "noise"], [320.0, 0.0, 0.1, 0.1, "saw", 210.0]])
	_streams["death"] = _render([[230.0, 0.0, 0.35, 0.2, "saw", 85.0], [0.2, 0.0, 0.3, 0.32, "noise"], [70.0, 0.0, 0.3, 0.35, "sine", 35.0]])
	_streams["fall"] = _render([[1100.0, 0.0, 0.75, 0.1, "sine", 180.0]])
	_streams["splash"] = _render([[0.3, 0.0, 0.6, 0.5, "noise"], [0.85, 0.0, 0.25, 0.3, "noise"], [0.15, 0.1, 0.5, 0.3, "noise"]])
	_streams["beep"] = _render([[880.0, 0.0, 0.12, 0.17, "square"]])
	_streams["go"] = _render([[1320.0, 0.0, 0.4, 0.17, "square"], [660.0, 0.0, 0.4, 0.14, "saw"]])
	_streams["alarm"] = _render([[650.0, 0.0, 0.26, 0.14, "square", 1000.0], [650.0, 0.32, 0.26, 0.14, "square", 1000.0], [650.0, 0.64, 0.26, 0.14, "square", 1000.0]])
	_streams["round"] = _render([[C4, 0.0, 0.16, 0.16, "saw"], [E4, 0.12, 0.16, 0.16, "saw"], [G4, 0.24, 0.16, 0.16, "saw"], [C5, 0.36, 0.6, 0.18, "saw"], [C2 * 2.0, 0.36, 0.6, 0.2, "sine"]])
	_streams["draw"] = _render([[G4, 0.0, 0.25, 0.15, "saw"], [E4, 0.2, 0.25, 0.15, "saw"], [C4, 0.4, 0.6, 0.15, "saw"]])
	_streams["victory"] = _render([
		[C4, 0.0, 0.18, 0.16, "saw"], [E4, 0.15, 0.18, 0.16, "saw"], [G4, 0.3, 0.18, 0.16, "saw"],
		[C5, 0.45, 0.3, 0.18, "saw"], [G4, 0.72, 0.15, 0.15, "saw"], [C5, 0.87, 1.0, 0.2, "saw"],
		[E5, 0.87, 1.0, 0.12, "saw"], [G5, 0.87, 1.0, 0.08, "tri"], [C2, 0.87, 1.0, 0.3, "sine"],
	])


func _render(tones: Array) -> AudioStreamWAV:
	var length := 0.0
	for t: Array in tones:
		length = maxf(length, t[1] + t[2])
	var buf := PackedFloat32Array()
	buf.resize(int(length * RATE) + 1)
	for t: Array in tones:
		_add_tone(buf, t, false, _rng)
	return _to_wav(buf, false)


## Mixes one tone into `buf`. With `wrap`, samples past the end continue at the start so a
## looping buffer has no seam.
func _add_tone(buf: PackedFloat32Array, t: Array, wrap: bool, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var freq: float = t[0]
	var start := int(t[1] * RATE)
	var dur := int(t[2] * RATE)
	var amp: float = t[3]
	var wave: String = t[4] if t.size() > 4 else "sine"
	var end_freq: float = t[5] if t.size() > 5 else freq
	var attack := 0.002 * RATE
	var phase := 0.0
	var lp := 0.0
	for i in dur:
		var j := start + i
		if j >= n:
			if not wrap:
				break
			j %= n
		var x := float(i) / dur
		phase += TAU * lerpf(freq, end_freq, x) / RATE
		var s: float
		var env := minf(1.0, i / attack) * (1.0 - x) * (1.0 - x)
		match wave:
			"tri":
				s = 2.0 / PI * asin(sin(phase))
			"saw":
				s = (fmod(phase, TAU) / TAU) * 2.0 - 1.0
				s *= 0.6
			"square":
				s = 0.5 if sin(phase) >= 0.0 else -0.5
			"noise":
				lp += (rng.randf_range(-1.0, 1.0) - lp) * freq
				s = lp * clampf(1.6 / sqrt(maxf(freq, 0.01)), 1.0, 5.0)
			"metal":
				s = sin(phase) * 0.6 + sin(phase * 2.76) * 0.3 * (1.0 - x) + sin(phase * 5.4) * 0.2 * (1.0 - x) * (1.0 - x)
				env = minf(1.0, i / attack) * exp(-x * 5.0)
			"pad":
				s = (fmod(phase, TAU) / TAU) * 2.0 - 1.0
				s = s * 0.35 + sin(phase * 0.5) * 0.3
				env = minf(1.0, x * 5.0) * minf(1.0, (1.0 - x) * 4.0)
			"pluck":
				s = (fmod(phase, TAU) / TAU) * 2.0 - 1.0
				s *= 0.5
				env = minf(1.0, i / attack) * exp(-x * 4.0)
			_:
				s = sin(phase) + 0.2 * sin(phase * 2.0)
		buf[j] += s * amp * env


func _to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


## A bouncy minor-key loop: kick and snare with off-beat hats, a plucked bass line and a short
## lead hook that answers in the second half.
func _build_music() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var beat := 60.0 / BPM
	var bars := ROOTS.size()
	var buf := PackedFloat32Array()
	buf.resize(int(bars * 4 * beat * RATE))
	for bar in bars:
		var t0 := bar * 4 * beat
		var root: float = ROOTS[bar]
		_add_tone(buf, [root * 4.0, t0, beat * 4.0, 0.035, "pad"], true, rng)
		_add_tone(buf, [root * 6.0, t0, beat * 4.0, 0.025, "pad"], true, rng)
		for k in 4:
			var tb := t0 + k * beat
			_add_tone(buf, [140.0, tb, 0.18, 0.5, "sine", 40.0], true, rng)
			if k == 2 and bar % 2 == 1:
				_add_tone(buf, [140.0, tb + beat * 0.5, 0.15, 0.35, "sine", 40.0], true, rng)
			if k % 2 == 1:
				_add_tone(buf, [0.7, tb, 0.16, 0.26, "noise"], true, rng)
				_add_tone(buf, [200.0, tb, 0.08, 0.12, "tri", 160.0], true, rng)
		for k in 8:
			_add_tone(buf, [0.97, t0 + k * beat * 0.5 + beat * 0.25, 0.035, 0.08, "noise"], true, rng)
		var pattern := [1.0, 0.0, 1.0, 2.0, 0.0, 1.0, 1.5, 1.0]
		for k in 8:
			var mul: float = pattern[k]
			if mul > 0.0:
				_add_tone(buf, [root * 2.0 * mul, t0 + k * beat * 0.5, beat * 0.45, 0.16, "pluck"], true, rng)
		if bar >= 4:
			for k in 4:
				var note: float = LEAD[(bar * 3 + k) % LEAD.size()]
				if rng.randf() < 0.75:
					_add_tone(buf, [note, t0 + k * beat + (beat * 0.5 if k % 2 == 1 else 0.0), beat * 0.4, 0.05, "square"], true, rng)
	_on_music_ready.call_deferred(_to_wav(buf, true))
