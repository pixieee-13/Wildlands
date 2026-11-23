extends Node3D
# the player. walks on the terrain height directly (no physics engine, way faster on phones)
# also has inventory, gathering, tools, crafting, swing animations and the sound effects
# character body is the Quaternius mannequin

const ToolModels = preload("res://tools.gd")

const CHAR_PATH := "res://assets/character/UAL1_Standard.glb"
const EYE_H := 1.7
const WALK_SPEED := 3.6
const RUN_SPEED := 7.8
const JUMP_V := 8.6
const GRAVITY := 22.0
const RADIUS := 0.4
const LOOK_SENS := 0.005

# ---- survival tuning
const REACH := 2.4            # how far from the surface of a tree/rock you can hit it
const GATHER_REACH := 2.0
const HIT_AT := 0.52          # fraction of the swing where the hit lands
const DMG := [0.0, 1.0, 1.8]            # per tool tier: 0 = none, 1 = stone, 2 = hardened
const SWING_T := [0.0, 0.62, 0.46]      # seconds per swing, per tier
const GATHER_T := 0.7
const KIND_TOOL := {"tree": "axe", "rock": "pickaxe", "bush": "sword"}
const KIND_VERB := {"tree": "Chop tree", "rock": "Mine rock", "bush": "Cut bush"}
const TOOL_NAME := {"axe": "Axe", "pickaxe": "Pickaxe", "sword": "Sword"}
const SLOT_KINDS := ["hand", "axe", "pickaxe", "sword"]
const SWING_ANIM := {
	"axe": "Sword_Attack",
	"pickaxe": "Punch_Cross",
	"sword": "Sword_Attack",
	"gather": "PickUp_Table",
}
const ITEM_NAME := {"wood": "Wood", "stick": "Stick", "stone": "Stone"}
const ITEM_COL := {
	"wood": Color(0.78, 0.55, 0.3),
	"stick": Color(0.85, 0.7, 0.4),
	"stone": Color(0.75, 0.78, 0.85),
}

const RECIPES := [
	{"name": "Stone Axe", "tool": "axe", "tier": 1, "cost": {"stick": 3, "stone": 2}, "note": "Chops trees"},
	{"name": "Stone Pickaxe", "tool": "pickaxe", "tier": 1, "cost": {"stick": 3, "stone": 3}, "note": "Mines rocks"},
	{"name": "Stone Sword", "tool": "sword", "tier": 1, "cost": {"stick": 1, "stone": 2, "wood": 2}, "note": "Cuts bushes"},
	{"name": "Hardened Axe", "tool": "axe", "tier": 2, "cost": {"wood": 4, "stick": 2, "stone": 2}, "note": "Upgrade: chops much faster"},
	{"name": "Hardened Pickaxe", "tool": "pickaxe", "tier": 2, "cost": {"wood": 4, "stick": 2, "stone": 4}, "note": "Upgrade: mines much faster"},
	{"name": "Hardened Sword", "tool": "sword", "tier": 2, "cost": {"wood": 4, "stick": 2, "stone": 3}, "note": "Upgrade: faster slashes"},
]

# First-person viewmodel poses: [position, Vector3(pitch, base yaw, roll)] in camera space.
const VM_POSES := {
	"axe": {
		"rest": [Vector3(0.34, -0.36, -0.62), Vector3(-0.5, 0.5, 0.3)],
		"wind": [Vector3(0.30, -0.04, -0.36), Vector3(0.65, 0.5, 0.15)],
		"hit": [Vector3(0.10, -0.40, -0.80), Vector3(-1.5, 0.5, 0.1)],
	},
	"pickaxe": {
		"rest": [Vector3(0.34, -0.36, -0.62), Vector3(-0.5, 0.45, 0.3)],
		"wind": [Vector3(0.30, 0.03, -0.34), Vector3(0.85, 0.45, 0.1)],
		"hit": [Vector3(0.08, -0.44, -0.82), Vector3(-1.55, 0.45, 0.05)],
	},
	"sword": {
		"rest": [Vector3(0.36, -0.32, -0.60), Vector3(-0.35, 0.3, 0.25)],
		"wind": [Vector3(0.55, -0.12, -0.42), Vector3(-0.55, 0.3, -1.1)],
		"hit": [Vector3(-0.18, -0.34, -0.74), Vector3(-1.0, 0.3, 1.2)],
	},
}

var world
var ui

var yaw := 0.0
var pitch := 0.0
var vel_y := 0.0
var hvel := Vector3.ZERO
var on_ground := true
var first_person := true
var jump_prev := false
var air_time := 0.0
var land_timer := 0.0
var bob_t := 0.0

var model_root: Node3D
var head: Node3D
var cam: Camera3D
var anim: AnimationPlayer
var mesh_list: Array = []
var cur_anim := ""

# ---- survival state
var inv := {"wood": 0, "stick": 0, "stone": 0}
var tier := {"axe": 0, "pickaxe": 0, "sword": 0}
var equipped := "hand"
var recipes: Array = RECIPES

var swing_t := -1.0
var swing_dur := 0.6
var swing_kind := ""
var swing_target := -1
var swing_hit_done := false
var mouse_act := false
var hint_cd := 0.0
var shake_t := 0.0
var kick_pitch := 0.0
var dip := 0.0

var vm_root: Node3D
var vm_nodes := {}
var hand_root: Node3D
var hand_nodes := {}
var sounds := {}


func setup(w, u) -> void:
	world = w
	ui = u
	ui.toggle_view.connect(_toggle_view)
	ui.equip_slot.connect(_equip_slot)
	ui.craft_request.connect(craft)
	ui.craft_toggled.connect(_on_craft_toggled)
	world.sfx.connect(_on_world_sfx)
	ui.bind(self, world)
	position = world.spawn_pos
	yaw = world.spawn_yaw
	_build_sounds()
	_build_body()
	_build_camera()
	_set_view(true)
	_refresh_tool_models()
	ui.toast("Collect sticks and stones from the ground, then open CRAFT!", Color(1, 1, 0.8), 6.0)


func _build_body() -> void:
	model_root = Node3D.new()
	add_child(model_root)
	var ps := load(CHAR_PATH) as PackedScene
	if ps == null:
		push_warning("Character model not found: " + CHAR_PATH)
		return
	var inst := ps.instantiate() as Node3D
	# glTF characters face +Z, Godot's forward is -Z
	inst.rotation.y = PI
	model_root.add_child(inst)
	anim = _find_anim(inst)
	_collect_meshes(inst)
	if anim != null:
		for a_name in anim.get_animation_list():
			if String(a_name).ends_with("Loop"):
				var a := anim.get_animation(a_name)
				a.loop_mode = Animation.LOOP_LINEAR
		_play("Idle_Loop", 0.0)
	# right hand socket: tools held in third person
	var skel := _find_skel(inst)
	if skel != null and skel.find_bone("hand_r") >= 0:
		var att := BoneAttachment3D.new()
		skel.add_child(att)
		att.bone_name = "hand_r"
		hand_root = Node3D.new()
		# bone +Y points along the fingers, +Z towards the thumb: the tool's handle (+Y)
		# runs across the fist (hand +Z) and its blade (+X) points along the fingers.
		hand_root.basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
		hand_root.position = Vector3(-0.015, 0.07, 0.0)
		att.add_child(hand_root)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		mesh_list.append(n)
	for c in n.get_children():
		_collect_meshes(c)


func _build_camera() -> void:
	head = Node3D.new()
	head.position = Vector3(0.0, EYE_H, 0.0)
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.05
	cam.far = 700.0
	head.add_child(cam)
	cam.current = true
	# first-person "held item" lives on the camera
	vm_root = Node3D.new()
	cam.add_child(vm_root)


func _set_view(fp: bool) -> void:
	first_person = fp
	# Full-body first person: the camera sits just in front of the face, so you
	# see your own arms/legs/body animating while you walk, run and jump.
	for m in mesh_list:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fp:
		cam.position = Vector3(0.0, 0.0, -0.17)
	else:
		cam.position = Vector3(0.0, 0.3, 3.4)
	ui.show_crosshair = fp


func _toggle_view() -> void:
	_set_view(not first_person)


# ------------------------------------------------------------------ tool models

func _refresh_tool_models() -> void:
	for k in vm_nodes.keys():
		(vm_nodes[k] as Node).queue_free()
	for k in hand_nodes.keys():
		(hand_nodes[k] as Node).queue_free()
	vm_nodes.clear()
	hand_nodes.clear()
	for kind in ["axe", "pickaxe", "sword"]:
		var t: int = tier[kind]
		if t <= 0:
			continue
		var a: Node3D = ToolModels.build(kind, t)
		vm_root.add_child(a)
		vm_nodes[kind] = a
		if hand_root != null:
			var b: Node3D = ToolModels.build(kind, t)
			hand_root.add_child(b)
			hand_nodes[kind] = b


# ------------------------------------------------------------------ sounds (synthesized)

func _make_snd(f0: float, f1: float, dur: float, noise: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * float(rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var rn := RandomNumberGenerator.new()
	rn.seed = 11
	for i in range(n):
		var t := float(i) / float(n)
		ph += TAU * lerpf(f0, f1, t) / float(rate)
		var env := pow(1.0 - t, 2.5) * minf(1.0, float(i) / 80.0)
		var s := (sin(ph) * (1.0 - noise) + rn.randf_range(-1.0, 1.0) * noise) * env * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _build_sounds() -> void:
	sounds["chop"] = _make_snd(120.0, 55.0, 0.17, 0.5, 0.95)
	sounds["clink"] = _make_snd(1500.0, 650.0, 0.13, 0.3, 0.6)
	sounds["whoosh"] = _make_snd(0.0, 0.0, 0.16, 1.0, 0.18)
	sounds["pickup"] = _make_snd(620.0, 1050.0, 0.09, 0.0, 0.5)
	sounds["craft"] = _make_snd(520.0, 980.0, 0.28, 0.0, 0.55)
	sounds["crash"] = _make_snd(75.0, 32.0, 0.8, 0.65, 1.0)
	sounds["rockbreak"] = _make_snd(260.0, 90.0, 0.35, 0.75, 0.9)
	sounds["leaf"] = _make_snd(0.0, 0.0, 0.14, 1.0, 0.3)
	sounds["no"] = _make_snd(210.0, 150.0, 0.14, 0.0, 0.4)


func _sfx(snd: String, pos: Vector3 = Vector3.INF) -> void:
	if not sounds.has(snd):
		return
	if pos == Vector3.INF:
		var p := AudioStreamPlayer.new()
		p.stream = sounds[snd]
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = sounds[snd]
		p3.unit_size = 14.0
		world.add_child(p3)
		p3.global_position = pos
		p3.finished.connect(p3.queue_free)
		p3.play()


func _on_world_sfx(snd: String, pos: Vector3) -> void:
	_sfx(snd, pos)


# ------------------------------------------------------------------ inventory / crafting

func _toast(text: String, col: Color = Color(1, 1, 1)) -> void:
	ui.toast(text, col, 2.4)


func _give(drops: Dictionary) -> void:
	for item in drops.keys():
		var n: int = drops[item]
		if n <= 0:
			continue
		inv[item] = int(inv[item]) + n
		ui.item_toast(String(item), n)


func can_craft(idx: int) -> String:
	var r: Dictionary = RECIPES[idx]
	var kind: String = r["tool"]
	var t: int = r["tier"]
	if int(tier[kind]) >= t:
		return "Owned"
	if int(tier[kind]) < t - 1:
		return "Needs Stone %s" % TOOL_NAME[kind]
	var cost: Dictionary = r["cost"]
	for item in cost.keys():
		if int(inv[item]) < int(cost[item]):
			return "Missing materials"
	return ""


func craft(idx: int) -> void:
	var why := can_craft(idx)
	if why != "":
		if why != "Owned":
			_toast(why, Color(1, 0.6, 0.5))
			_sfx("no")
		return
	var r: Dictionary = RECIPES[idx]
	var cost: Dictionary = r["cost"]
	for item in cost.keys():
		inv[item] = int(inv[item]) - int(cost[item])
	var kind: String = r["tool"]
	tier[kind] = int(r["tier"])
	_refresh_tool_models()
	equipped = kind
	_toast("Crafted %s!" % r["name"], Color(0.7, 1.0, 0.6))
	_sfx("craft")


func _equip(kind: String) -> void:
	if kind != "hand" and int(tier[kind]) <= 0:
		return
	equipped = kind


func _equip_slot(slot: int) -> void:
	if slot < 0 or slot >= SLOT_KINDS.size():
		return
	var kind: String = SLOT_KINDS[slot]
	if kind != "hand" and int(tier[kind]) <= 0:
		_toast("Craft a %s first (CRAFT button)" % TOOL_NAME[kind], Color(1, 0.8, 0.6))
		return
	_equip(kind)


func _on_craft_toggled(open: bool) -> void:
	if OS.has_feature("mobile"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ input (desktop testing)

func _unhandled_input(event: InputEvent) -> void:
	# Desktop only: click to capture mouse (then click = act), WASD, Shift, Space, V,
	# 1-4 equip, C craft, M map zoom, E act.
	if OS.has_feature("mobile"):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				else:
					mouse_act = true
			else:
				mouse_act = false
		elif mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE:
			if ui.craft_open:
				ui.set_craft_open(false)
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif k.keycode == KEY_V:
			_toggle_view()
		elif k.keycode == KEY_C:
			ui.set_craft_open(not ui.craft_open)
		elif k.keycode == KEY_M:
			ui.cycle_map()
		elif k.keycode >= KEY_1 and k.keycode <= KEY_9:
			var n: int = k.keycode - KEY_1
			if ui.craft_open:
				if n < RECIPES.size():
					craft(n)
			else:
				_equip_slot(n)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.0025
		pitch = clampf(pitch - mm.relative.y * 0.0025, -1.45, 1.45)


func _play(anim_name: String, blend: float = 0.2, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	anim.speed_scale = speed
	if cur_anim != anim_name:
		cur_anim = anim_name
		anim.play(anim_name, blend)


func _ok(a: Vector3, b: Vector3) -> bool:
	var gt: float = world.height_at(b.x, b.z)
	if gt < world.water_y - 1.1:
		return false
	if b.y + 0.05 < gt:
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		if gt - b.y > dist * 1.35 + 0.04:
			return false
	# rocks: you can step onto low ones, taller ones need a jump
	var gr: float = world.ground_at(b.x, b.z)
	if gr > gt + 0.01 and gr - b.y > 0.45:
		return false
	return true


# ------------------------------------------------------------------ actions: gather / chop / mine / slash

func _facing() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


## What would ACT do right now? {"id", "mode": harvest|gather|locked|none, "need": tool}
func _scan() -> Dictionary:
	var f := _facing()
	var owned_kinds: Array = []
	var locked_kinds: Array = []
	for k in KIND_TOOL.keys():
		if int(tier[KIND_TOOL[k]]) > 0:
			owned_kinds.append(k)
		else:
			locked_kinds.append(k)
	var id: int = world.find_target(position, f, REACH, owned_kinds, 0.35)
	if id >= 0:
		var kind: String = world.ents[id]["kind"]
		return {"id": id, "mode": "harvest", "need": KIND_TOOL[kind]}
	id = world.find_target(position, f, GATHER_REACH, ["pickup"], -1.0)
	if id >= 0:
		return {"id": id, "mode": "gather", "need": ""}
	id = world.find_target(position, f, REACH, locked_kinds, 0.35)
	if id >= 0:
		var kind2: String = world.ents[id]["kind"]
		return {"id": id, "mode": "locked", "need": KIND_TOOL[kind2]}
	return {"id": -1, "mode": "none", "need": ""}


func _update_prompt() -> void:
	var s := _scan()
	var mode: String = s["mode"]
	ui.prompt = ""
	ui.target_frac = -1.0
	if mode == "none":
		return
	var e: Dictionary = world.ents[int(s["id"])]
	var kind: String = e["kind"]
	if mode == "harvest":
		ui.prompt = KIND_VERB[kind]
		if float(e["hp"]) < float(e["max_hp"]):
			ui.target_frac = float(e["hp"]) / float(e["max_hp"])
	elif mode == "gather":
		ui.prompt = "Pick up %s" % ITEM_NAME[e["item"]]
	elif mode == "locked":
		ui.prompt = "Need a %s to %s" % [TOOL_NAME[s["need"]], String(KIND_VERB[kind]).to_lower()]


func _try_act() -> void:
	if swing_t >= 0.0 or not on_ground:
		return
	var s := _scan()
	var mode: String = s["mode"]
	if mode == "harvest":
		var need: String = s["need"]
		if equipped != need:
			_equip(need)
		_start_swing(need, int(s["id"]))
	elif mode == "gather":
		_start_swing("gather", int(s["id"]))
	elif mode == "locked":
		if hint_cd <= 0.0:
			hint_cd = 2.5
			var need2: String = s["need"]
			_toast("You need a %s for that - open CRAFT" % TOOL_NAME[need2], Color(1, 0.8, 0.6))
			_sfx("no")
	elif equipped != "hand":
		_start_swing(equipped, -1)


func _start_swing(kind: String, target: int) -> void:
	swing_kind = kind
	swing_target = target
	swing_hit_done = false
	swing_t = 0.0
	if kind == "gather":
		swing_dur = GATHER_T
	else:
		swing_dur = SWING_T[int(tier[kind])]
		_sfx("whoosh")
	# turn towards the target (visible in third person)
	if not first_person:
		model_root.rotation.y = yaw
		if target >= 0:
			var e: Dictionary = world.ents[target]
			model_root.rotation.y = atan2(-(float(e["x"]) - position.x), -(float(e["z"]) - position.z))
	# body animation, stretched to the swing time
	var an: String = SWING_ANIM[kind]
	if anim != null and anim.has_animation(an):
		var alen := anim.get_animation(an).length
		anim.speed_scale = alen / swing_dur
		cur_anim = an
		anim.play(an, 0.06)


func _update_swing(delta: float) -> void:
	if swing_t < 0.0:
		return
	swing_t += delta
	var p := swing_t / swing_dur
	if not swing_hit_done and p >= HIT_AT:
		swing_hit_done = true
		_do_hit()
	if swing_kind == "gather":
		dip = 0.38 * sin(PI * clampf(p, 0.0, 1.0))
	if p >= 1.0:
		swing_t = -1.0
		cur_anim = ""
		dip = 0.0


func _do_hit() -> void:
	if swing_target < 0:
		return
	var e: Dictionary = world.ents[swing_target]
	if not e["alive"]:
		return
	var dx: float = float(e["x"]) - position.x
	var dz: float = float(e["z"]) - position.z
	var dist := sqrt(dx * dx + dz * dz) - float(e["r"])
	if swing_kind == "gather":
		if dist > GATHER_REACH + 0.6:
			return
		_give(world.collect_pickup(swing_target))
		_sfx("pickup")
		return
	if dist > REACH + 0.7:
		return
	var kind: String = e["kind"]
	var dmg: float = DMG[int(tier[swing_kind])]
	var res: Dictionary = world.hit_entity(swing_target, dmg, position)
	_give(res["drops"])
	shake_t = 0.2
	kick_pitch = 0.035
	if kind == "tree":
		_sfx("chop", Vector3(float(e["x"]), position.y + 1.0, float(e["z"])))
	elif kind == "rock":
		_sfx("clink", Vector3(float(e["x"]), position.y + 1.0, float(e["z"])))
	else:
		_sfx("leaf", Vector3(float(e["x"]), position.y + 0.5, float(e["z"])))


# ------------------------------------------------------------------ viewmodel

func _vm_pose(kind: String, p: float) -> Array:
	var tbl: Dictionary = VM_POSES[kind]
	var rest: Array = tbl["rest"]
	if p < 0.0:
		return rest
	var wind: Array = tbl["wind"]
	var hit: Array = tbl["hit"]
	var a: Array = rest
	var b: Array = wind
	var t := 0.0
	if p < 0.38:
		a = rest
		b = wind
		t = 1.0 - pow(1.0 - p / 0.38, 2.0)
	elif p < 0.55:
		a = wind
		b = hit
		t = pow((p - 0.38) / 0.17, 2.0)
	else:
		a = hit
		b = rest
		var u := clampf((p - 0.55) / 0.45, 0.0, 1.0)
		t = u * u * (3.0 - 2.0 * u)
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var ea: Vector3 = a[1]
	var eb: Vector3 = b[1]
	return [pa.lerp(pb, t), ea.lerp(eb, t)]


func _update_viewmodel(hspeed: float) -> void:
	var holding := equipped != "hand" and vm_nodes.has(equipped)
	vm_root.visible = first_person and holding
	for k in vm_nodes.keys():
		(vm_nodes[k] as Node3D).visible = (k == equipped)
	if hand_root != null:
		hand_root.visible = (not first_person) and holding
		for k in hand_nodes.keys():
			(hand_nodes[k] as Node3D).visible = (k == equipped)
	if not (first_person and holding):
		return
	var p := -1.0
	if swing_t >= 0.0 and swing_kind != "gather":
		p = swing_t / swing_dur
	var pose := _vm_pose(equipped, p)
	var pos: Vector3 = pose[0]
	var eul: Vector3 = pose[1]
	if p < 0.0:
		var k2 := clampf(hspeed / RUN_SPEED, 0.0, 1.0)
		pos += Vector3(sin(bob_t * 0.5) * 0.015 * k2, -absf(sin(bob_t)) * 0.02 * k2 + sin(float(Time.get_ticks_msec()) * 0.0016) * 0.004, 0.0)
	if swing_t >= 0.0 and swing_kind == "gather":
		pos.y -= 0.5 * sin(PI * clampf(swing_t / swing_dur, 0.0, 1.0))
	vm_root.position = pos
	# base yaw first (turns the blade), then lean/roll in camera space
	vm_root.basis = Basis.from_euler(Vector3(eul.x, 0.0, eul.z)) * Basis(Vector3.UP, eul.y)


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if world == null:
		return
	delta = minf(delta, 0.05)
	hint_cd = maxf(0.0, hint_cd - delta)

	# ---- look ----
	var ld: Vector2 = ui.consume_look()
	yaw -= ld.x * LOOK_SENS
	pitch = clampf(pitch - ld.y * LOOK_SENS, -1.45, 1.45)

	# ---- input ----
	var inp: Vector2 = ui.joy_vec
	var kx := 0.0
	var kz := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		kz -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		kz += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		kx -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		kx += 1.0
	if kx != 0.0 or kz != 0.0:
		inp = Vector2(kx, kz).normalized()
	var running: bool = ui.run_on or Input.is_physical_key_pressed(KEY_SHIFT)
	var jump_req: bool = ui.jump_held or Input.is_physical_key_pressed(KEY_SPACE)
	var jump_pressed := jump_req and not jump_prev
	jump_prev = jump_req

	# ---- actions ----
	var act_req: bool = ui.act_held or mouse_act or Input.is_physical_key_pressed(KEY_E)
	if act_req and not ui.craft_open:
		_try_act()
	_update_swing(delta)
	_update_prompt()

	# ---- horizontal movement ----
	var dir := Basis(Vector3.UP, yaw) * Vector3(inp.x, 0.0, inp.y)
	var mag := minf(1.0, inp.length() * 1.1)
	var spd := RUN_SPEED if running else WALK_SPEED
	if swing_t >= 0.0:
		spd *= 0.35
	var gnow: float = world.ground_at(position.x, position.z)
	if gnow < world.water_y - 0.25:
		spd *= 0.6
	var target := dir.normalized() * spd * mag
	var accel := 45.0 if on_ground else 10.0
	hvel = hvel.move_toward(target, accel * delta)

	var pos := position
	var np := pos + hvel * delta
	if not _ok(pos, np):
		var nx := Vector3(np.x, pos.y, pos.z)
		var nz := Vector3(pos.x, pos.y, np.z)
		if _ok(pos, nx):
			np = nx
		elif _ok(pos, nz):
			np = nz
		else:
			np = pos
			hvel = Vector3.ZERO
	np = world.push_out(np, RADIUS)
	var lim: float = world.half_size - 6.0
	np.x = clampf(np.x, -lim, lim)
	np.z = clampf(np.z, -lim, lim)

	# ---- vertical movement ----
	var g: float = world.ground_at(np.x, np.z)
	if on_ground:
		if jump_pressed:
			vel_y = JUMP_V
			on_ground = false
			air_time = 0.0
			np.y = pos.y + vel_y * delta
		elif np.y - g < 0.5:
			np.y = g
		else:
			on_ground = false
			vel_y = 0.0
			air_time = 0.3
	else:
		air_time += delta
		vel_y -= GRAVITY * delta
		np.y += vel_y * delta
		if np.y <= g and vel_y <= 0.0:
			np.y = g
			if air_time > 0.35:
				land_timer = 0.2
			on_ground = true
			vel_y = 0.0
	position = np
	land_timer = maxf(0.0, land_timer - delta)

	# ---- camera / body ----
	var hspeed := Vector2(hvel.x, hvel.z).length()
	bob_t += hspeed * delta * 1.7
	var bob := 0.0
	if first_person and on_ground:
		bob = sin(bob_t) * 0.035 * clampf(hspeed / RUN_SPEED, 0.0, 1.0)
	kick_pitch = lerpf(kick_pitch, 0.0, 1.0 - exp(-14.0 * delta))
	shake_t = maxf(0.0, shake_t - delta)
	var jitter := Vector3.ZERO
	if shake_t > 0.0:
		jitter = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.03 * (shake_t / 0.2)
	head.position = Vector3(0.0, EYE_H + bob, 0.0) + jitter
	head.rotation = Vector3(pitch + kick_pitch - dip, yaw, 0.0)

	if first_person:
		model_root.rotation.y = yaw
	elif swing_t < 0.0 and hspeed > 0.5:
		model_root.rotation.y = lerp_angle(model_root.rotation.y, atan2(-hvel.x, -hvel.z), minf(1.0, 12.0 * delta))

	if not first_person:
		var gp := cam.global_position
		var floor_y: float = world.height_at(gp.x, gp.z) + 0.35
		if gp.y < floor_y:
			cam.global_position = Vector3(gp.x, floor_y, gp.z)

	_update_viewmodel(hspeed)

	# ---- animation ----
	if swing_t >= 0.0:
		return
	if not on_ground:
		if air_time < 0.25 and vel_y > 0.0:
			_play("Jump_Start", 0.1)
		else:
			_play("Jump_Loop", 0.15)
	elif land_timer > 0.0:
		_play("Jump_Land", 0.05)
	elif hspeed < 0.4:
		_play("Idle_Loop", 0.2)
	elif running and hspeed > 5.0:
		_play("Sprint_Loop", 0.2, clampf(hspeed / 7.0, 0.8, 1.3))
	elif hspeed > 2.8:
		_play("Jog_Fwd_Loop", 0.2, clampf(hspeed / 4.0, 0.75, 1.3))
	else:
		_play("Walk_Loop", 0.2, clampf(hspeed / 1.7, 0.6, 1.5))
