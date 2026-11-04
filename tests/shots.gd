extends Node
## Dev tool: stages fighters in poses and situations and saves close-up contact sheets, so the
## animation can be checked frame by frame. Opens a window (needs a renderer):
##   godot --path . res://tests/shots.tscn -- /tmp/shots [poses|scenes]

const World := preload("res://scripts/game/world.gd")
const WorldView := preload("res://scripts/game/world_view.gd")
const UI := preload("res://scripts/ui.gd")

var dir := "user://shots"
var view: WorldView
var world: World


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		dir = args[0]
	var group := args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1280, 720)
	view = WorldView.new()
	add_child(view)
	if group == "" or group == "poses":
		await _poses()
	if group == "" or group == "scenes":
		await _scenes()
	get_tree().quit()


func _fresh(level := "catilar") -> World:
	world = World.new()
	world.setup(level, [{"id": 0, "color": Color("#e84545")}, {"id": 1, "color": Color("#3d8bff")}], 5)
	world.state = "fight"
	world.sudden_death = false
	world.props.clear()
	view.set_world(world)
	view.tags = {0: "P1", 1: "B2"}
	var b := world.fighter(1)
	b.pos = Vector2(1200, 580)
	return world


func _grab(center: Vector2, zoom: float, w := 260, h := 250) -> Image:
	view.scale = Vector2(zoom, zoom)
	view.origin = Vector2(640, 360) - center * zoom
	for i in 3:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	return img.get_region(Rect2i(640 - w / 2, 360 - h / 2, w, h))


func _sheet(name: String, frames: Array, labels: Array, cols := 4) -> void:
	var fw: int = frames[0].get_width()
	var fh: int = frames[0].get_height()
	var rows := ceili(frames.size() / float(cols))
	var sheet := Image.create(fw * cols + (cols + 1) * 6, (fh + 6) * rows + 6, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#101118"))
	for i in frames.size():
		var img: Image = frames[i]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, fw, fh), Vector2i(6 + (i % cols) * (fw + 6), 6 + (i / cols) * (fh + 6)))
	sheet.save_png("%s/%s.png" % [dir, name])
	print("saved ", name, " ", labels)


func _step(n: int, inp := {}) -> void:
	for i in n:
		world.step({0: inp})


func _poses() -> void:
	var frames := []
	var labels := []
	var f
	# Idle guard, crouch.
	_fresh()
	f = world.fighter(0)
	f.pos = Vector2(640, 470)
	_step(60)
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("idle")
	_step(30, {"down": true})
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("crouch")
	# Running: four phases of the stride.
	_fresh()
	f = world.fighter(0)
	f.pos = Vector2(490, 470)
	_step(40, {"move": 1.0})
	for k in 4:
		_step(5, {"move": 1.0})
		frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("run %d" % k)
		f.pos.x = 600.0
	# Walking slowly (half stick).
	_fresh()
	f = world.fighter(0)
	f.pos = Vector2(500, 470)
	_step(40, {"move": 0.35})
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("walk")
	# Jump up and falling.
	_step(30)
	world.step({0: {"jump": true, "jump_held": true}})
	_step(8, {"jump_held": true})
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("jump up")
	_step(22, {"jump_held": true})
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("falling")
	# Punch combo at full extension.
	_fresh()
	f = world.fighter(0)
	f.pos = Vector2(640, 470)
	_step(40)
	for k in 3:
		world.step({0: {"attack": true}})
		_step(int([7, 7, 10][k]))
		frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("punch %d" % k)
		_step(26 - int([7, 7, 10][k]))
	# Guns.
	for w in ["pistol", "shotgun", "crossbow"]:
		_fresh()
		f = world.fighter(0)
		f.pos = Vector2(640, 470)
		f.weapon = w
		f.ammo = 5
		_step(40, {"aim": Vector2(1, 0)})
		frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append(w)
	_step(20, {"aim": Vector2(1, -1)})
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("aim up")
	_step(20, {"aim": Vector2(1, 0.8), "move": -1.0})
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("backpedal aim down")
	# Sword idle and swing.
	_fresh()
	f = world.fighter(0)
	f.pos = Vector2(640, 470)
	f.weapon = "sword"
	f.ammo = -1
	_step(40)
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("sword")
	world.step({0: {"attack": true}})
	_step(10)
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("swing")
	_step(8)
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("swing end")
	# Grenade wind-up.
	_fresh()
	f = world.fighter(0)
	f.pos = Vector2(640, 470)
	f.weapon = "grenade"
	f.ammo = 3
	_step(40)
	world.step({0: {"attack": true}})
	_step(12)
	frames.append(await _grab(f.pos - Vector2(0, 44), 2.4)); labels.append("grenade windup")
	# A ragdoll that has come to rest.
	_fresh("insaat")
	f = world.fighter(0)
	f.pos = Vector2(640, 470)
	_step(20)
	f.pos = Vector2(400, 640)
	_step(10)
	world.hit_fighter(f, 300.0, Vector2(-300, -500), 1, "pistol", f.center(), false)
	_step(300)
	frames.append(await _grab(f.rig.ragdoll.center() - Vector2(0, 10), 2.4)); labels.append("dead")
	_sheet("poses", frames, labels)


func _scenes() -> void:
	for id in ["fabrika", "catilar", "insaat", "kopru"]:
		world = World.new()
		var players := []
		for i in 4:
			players.append({"id": i, "color": [Color("#e84545"), Color("#3d8bff"), Color("#3ccf6a"), Color("#f2c230")][i]})
		world.setup(id, players, 9)
		world.state = "fight"
		view.set_world(world)
		view.tags = {0: "P1", 1: "B2", 2: "B3", 3: "B4"}
		_step(30)
		view.scale = Vector2.ONE
		view.origin = Vector2.ZERO
		for i in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/level_%s.png" % [dir, id])
