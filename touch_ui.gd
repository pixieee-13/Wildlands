extends Control
# touch controls + HUD, everything is drawn in code (no textures)
# left = joystick, right = drag to look, ACT = swing/pick up, RUN/JUMP/CAM buttons,
# CRAFT opens crafting, hotbar at the bottom, tap minimap to zoom

signal toggle_view
signal equip_slot(slot: int)
signal craft_request(idx: int)
signal craft_toggled(open: bool)

const JOY_R := 100.0
const DEAD := 0.12
const JUMP_R := 72.0
const RUN_R := 54.0
const CAM_R := 34.0
const ACT_R := 66.0
const CRAFT_R := 34.0
const SLOT := 76.0
const SLOT_GAP := 10.0
const MAP_PX := 190.0
const MAP_VIEWS := [150.0, 320.0, 512.0]

const SLOT_KINDS := ["hand", "axe", "pickaxe", "sword"]
const ACT_LABEL := {"hand": "GRAB", "axe": "CHOP", "pickaxe": "MINE", "sword": "SLASH"}
const ITEM_NAME := {"wood": "Wood", "stick": "Stick", "stone": "Stone"}
const ITEM_COL := {
	"wood": Color(0.78, 0.55, 0.3),
	"stick": Color(0.85, 0.7, 0.4),
	"stone": Color(0.75, 0.78, 0.85),
}
const ITEMS := ["wood", "stick", "stone"]

var joy_vec := Vector2.ZERO
var jump_held := false
var run_on := false
var act_held := false
var show_crosshair := true
var look_accum := Vector2.ZERO

var craft_open := false
var map_mode := 0
var prompt := ""
var target_frac := -1.0
var toasts: Array = []

var player = null
var world = null

var loading := true
var load_value := 0.0
var load_text := "Starting..."
var hint_t := 0.0

var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_cur := Vector2.ZERO
var _joy_active := false
var _look_id := -1
var _jump_id := -1
var _act_id := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p, w) -> void:
	player = p
	world = w


func set_progress(v: float, text: String) -> void:
	load_value = v
	load_text = text


func hide_loading() -> void:
	loading = false
	hint_t = 0.0


func consume_look() -> Vector2:
	var l := look_accum
	look_accum = Vector2.ZERO
	return l


func set_craft_open(open: bool) -> void:
	if craft_open == open:
		return
	craft_open = open
	if open:
		# stop any held input so nothing keeps running under the panel
		joy_vec = Vector2.ZERO
		act_held = false
		jump_held = false
	craft_toggled.emit(open)


func cycle_map() -> void:
	map_mode = (map_mode + 1) % 3


func toast(text: String, col: Color = Color(1, 1, 1), life: float = 2.4) -> void:
	toasts.append({"text": text, "col": col, "t": 0.0, "life": life, "key": "", "n": 0})
	while toasts.size() > 5:
		toasts.pop_front()


## "+3 Wood" style toast that merges quick repeated pickups of the same item.
func item_toast(item: String, n: int) -> void:
	for tt in toasts:
		if tt["key"] == item and float(tt["t"]) < 1.0:
			tt["n"] = int(tt["n"]) + n
			tt["text"] = "+%d %s" % [int(tt["n"]), ITEM_NAME[item]]
			tt["t"] = 0.0
			return
	toasts.append({"text": "+%d %s" % [n, ITEM_NAME[item]], "col": ITEM_COL[item], "t": 0.0, "life": 2.0, "key": item, "n": n})
	while toasts.size() > 5:
		toasts.pop_front()


func _process(delta: float) -> void:
	if not loading:
		hint_t += delta
	for i in range(toasts.size() - 1, -1, -1):
		var tt: Dictionary = toasts[i]
		tt["t"] = float(tt["t"]) + delta
		if float(tt["t"]) > float(tt["life"]):
			toasts.remove_at(i)
	queue_redraw()


func _sz() -> Vector2:
	return get_viewport_rect().size


func _jump_c() -> Vector2:
	var s := _sz()
	return Vector2(s.x - 150.0, s.y - 165.0)


func _run_c() -> Vector2:
	var s := _sz()
	return Vector2(s.x - 305.0, s.y - 95.0)


func _act_c() -> Vector2:
	var s := _sz()
	return Vector2(s.x - 300.0, s.y - 235.0)


func _cam_c() -> Vector2:
	var s := _sz()
	return Vector2(s.x - 70.0, 70.0)


func _craft_c() -> Vector2:
	var s := _sz()
	return Vector2(s.x - 70.0, 150.0)


func _joy_default() -> Vector2:
	var s := _sz()
	return Vector2(190.0, s.y - 175.0)


func _map_rect() -> Rect2:
	var s := _sz()
	if map_mode == 2:
		var m := minf(s.y - 80.0, s.x - 80.0)
		return Rect2((s.x - m) * 0.5, (s.y - m) * 0.5, m, m)
	return Rect2(16.0, 16.0, MAP_PX, MAP_PX)


func _slot_rect(i: int) -> Rect2:
	var s := _sz()
	var total := 4.0 * SLOT + 3.0 * SLOT_GAP
	return Rect2((s.x - total) * 0.5 + float(i) * (SLOT + SLOT_GAP), s.y - SLOT - 18.0, SLOT, SLOT)


func _panel_rect() -> Rect2:
	var s := _sz()
	var w := minf(s.x - 60.0, 860.0)
	var h := minf(s.y - 30.0, 590.0)
	return Rect2((s.x - w) * 0.5, (s.y - h) * 0.5, w, h)


func _row_rect(i: int) -> Rect2:
	var r := _panel_rect()
	var step := minf(72.0, (r.size.y - 150.0) / 6.0)
	return Rect2(r.position.x + 20.0, r.position.y + 72.0 + float(i) * step, r.size.x - 40.0, step - 6.0)


func _close_c() -> Vector2:
	var r := _panel_rect()
	return Vector2(r.end.x - 38.0, r.position.y + 38.0)


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if loading:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position, d.relative)
	elif event is InputEventMouseButton:
		# desktop only (touch-emulated mouse events are ignored: touches are handled above)
		var mb := event as InputEventMouseButton
		if mb.device == -1 or OS.has_feature("mobile"):
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _mouse_click(mb.position):
				get_viewport().set_input_as_handled()


func _mouse_click(p: Vector2) -> bool:
	if craft_open:
		_panel_tap(p)
		return true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return false
	if _map_rect().has_point(p):
		cycle_map()
		return true
	for i in range(4):
		if _slot_rect(i).has_point(p):
			equip_slot.emit(i)
			return true
	if p.distance_to(_craft_c()) < CRAFT_R * 1.5:
		set_craft_open(true)
		return true
	return false


func _panel_tap(p: Vector2) -> void:
	var r := _panel_rect()
	if p.distance_to(_close_c()) < 36.0 or not r.has_point(p):
		set_craft_open(false)
		return
	if player == null:
		return
	for i in range(player.recipes.size()):
		if _row_rect(i).has_point(p):
			craft_request.emit(i)
			return


func _press(id: int, p: Vector2) -> void:
	var s := _sz()
	if craft_open:
		_panel_tap(p)
		return
	if _map_rect().has_point(p):
		cycle_map()
		return
	for i in range(4):
		if _slot_rect(i).has_point(p):
			equip_slot.emit(i)
			return
	if p.distance_to(_craft_c()) < CRAFT_R * 1.5:
		set_craft_open(true)
		return
	if p.distance_to(_act_c()) < ACT_R * 1.25:
		_act_id = id
		act_held = true
		return
	if p.distance_to(_jump_c()) < JUMP_R * 1.25:
		_jump_id = id
		jump_held = true
		return
	if p.distance_to(_run_c()) < RUN_R * 1.25:
		run_on = not run_on
		return
	if p.distance_to(_cam_c()) < CAM_R * 1.5:
		toggle_view.emit()
		return
	if p.x < s.x * 0.45 and p.y > s.y * 0.2 and _joy_id == -1:
		_joy_id = id
		_joy_origin = p
		_joy_cur = p
		_joy_active = true
		joy_vec = Vector2.ZERO
		return
	if _look_id == -1:
		_look_id = id


func _release(id: int) -> void:
	if id == _joy_id:
		_joy_id = -1
		_joy_active = false
		joy_vec = Vector2.ZERO
	elif id == _look_id:
		_look_id = -1
	elif id == _jump_id:
		_jump_id = -1
		jump_held = false
	elif id == _act_id:
		_act_id = -1
		act_held = false


func _drag(id: int, p: Vector2, rel: Vector2) -> void:
	if id == _joy_id:
		_joy_cur = p
		var v := (p - _joy_origin) / JOY_R
		var l := v.length()
		if l > 1.0:
			v = v / l
			l = 1.0
		if l < DEAD:
			joy_vec = Vector2.ZERO
		else:
			joy_vec = v.normalized() * ((l - DEAD) / (1.0 - DEAD))
	elif id == _look_id:
		look_accum += rel


# ------------------------------------------------------------------ drawing helpers

func _shadow_text(font: Font, pos: Vector2, text: String, align: int, width: float, size: int, col: Color) -> void:
	draw_string(font, pos + Vector2(2, 2), text, align, width, size, Color(0, 0, 0, col.a * 0.7))
	draw_string(font, pos, text, align, width, size, col)


func _tier_col(t: int) -> Color:
	if t >= 2:
		return Color(0.5, 0.85, 1.0)
	return Color(0.66, 0.69, 0.75)


func _draw_tool_icon(kind: String, c: Vector2, sz: float, t: int, a: float) -> void:
	var metal := _tier_col(t)
	metal.a = a
	var wood := Color(0.62, 0.42, 0.22, a)
	if kind == "axe":
		draw_line(c + Vector2(-0.30, 0.42) * sz, c + Vector2(0.18, -0.38) * sz, wood, sz * 0.09)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.0, -0.46) * sz, c + Vector2(0.44, -0.34) * sz,
			c + Vector2(0.36, 0.0) * sz, c + Vector2(0.10, -0.12) * sz]), metal)
	elif kind == "pickaxe":
		draw_line(c + Vector2(-0.30, 0.42) * sz, c + Vector2(0.2, -0.30) * sz, wood, sz * 0.09)
		draw_polyline(PackedVector2Array([
			c + Vector2(-0.22, -0.38) * sz, c + Vector2(0.08, -0.5) * sz, c + Vector2(0.42, -0.30) * sz]), metal, sz * 0.12)
	elif kind == "sword":
		draw_line(c + Vector2(-0.22, 0.22) * sz, c + Vector2(0.40, -0.40) * sz, metal, sz * 0.12)
		draw_line(c + Vector2(-0.40, 0.0) * sz, c + Vector2(0.0, 0.40) * sz, Color(0.5, 0.35, 0.2, a), sz * 0.08)
		draw_line(c + Vector2(-0.22, 0.22) * sz, c + Vector2(-0.40, 0.40) * sz, wood, sz * 0.09)
	else:
		# hand: palm + fingers
		var hc := Color(0.93, 0.76, 0.6, a)
		draw_circle(c + Vector2(0.0, 0.1) * sz, sz * 0.26, hc)
		for k in range(4):
			var fx := (float(k) - 1.5) * 0.15
			draw_line(c + Vector2(fx, 0.0) * sz, c + Vector2(fx, -0.34) * sz, hc, sz * 0.1)


func _draw_item_icon(item: String, c: Vector2, sz: float) -> void:
	if item == "wood":
		draw_rect(Rect2(c - Vector2(0.45, 0.22) * sz, Vector2(0.9, 0.44) * sz), Color(0.55, 0.36, 0.18))
		draw_circle(c + Vector2(0.45, 0.0) * sz, 0.22 * sz, Color(0.82, 0.64, 0.4))
	elif item == "stick":
		draw_line(c + Vector2(-0.42, 0.32) * sz, c + Vector2(0.42, -0.32) * sz, Color(0.72, 0.5, 0.28), sz * 0.16)
	else:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-0.42, 0.30) * sz, c + Vector2(-0.26, -0.30) * sz, c + Vector2(0.20, -0.40) * sz,
			c + Vector2(0.46, 0.10) * sz, c + Vector2(0.26, 0.36) * sz]), Color(0.72, 0.74, 0.8))


func _draw_map(font: Font) -> void:
	if world == null or world.minimap_tex == null or player == null:
		return
	var r := _map_rect()
	var tex: Texture2D = world.minimap_tex
	var res := float(tex.get_width())
	var map_size: float = world.half_size * 2.0
	var view: float = MAP_VIEWS[map_mode]
	var src_w := clampf(view / map_size * res, 8.0, res)
	var px: float = (player.position.x + world.half_size) / map_size * res
	var pz: float = (player.position.z + world.half_size) / map_size * res
	var cx := clampf(px, src_w * 0.5, res - src_w * 0.5)
	var cz := clampf(pz, src_w * 0.5, res - src_w * 0.5)
	var src := Rect2(cx - src_w * 0.5, cz - src_w * 0.5, src_w, src_w)
	draw_rect(r.grow(4.0), Color(0, 0, 0, 0.55))
	draw_texture_rect_region(tex, r, src)
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)

	# player arrow (map up = north = -Z)
	var mp := r.position + Vector2((px - src.position.x) / src_w, (pz - src.position.y) / src_w) * r.size
	var f := Vector2(-sin(player.yaw), -cos(player.yaw))
	var side := Vector2(-f.y, f.x)
	var tip := mp + f * 11.0
	var l := mp - f * 7.0 + side * 7.0
	var rr := mp - f * 7.0 - side * 7.0
	draw_colored_polygon(PackedVector2Array([tip, l, mp - f * 3.0, rr]), Color(1.0, 0.95, 0.3))
	draw_polyline(PackedVector2Array([tip, l, mp - f * 3.0, rr, tip]), Color(0, 0, 0, 0.8), 1.5)

	_shadow_text(font, r.position + Vector2(r.size.x * 0.5 - 6.0, 20.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	var bname: String = world.biome_name_at(player.position.x, player.position.z)
	_shadow_text(font, Vector2(r.position.x, r.end.y + 24.0), bname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
	if map_mode == 2:
		_shadow_text(font, Vector2(r.position.x, r.end.y + 48.0), "Tap the map to shrink it", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))


func _draw_inventory(font: Font) -> void:
	var iy := 266.0
	if map_mode == 2:
		return
	for item in ITEMS:
		draw_rect(Rect2(16.0, iy - 24.0, 150.0, 34.0), Color(0, 0, 0, 0.4))
		_draw_item_icon(item, Vector2(40.0, iy - 7.0), 22.0)
		var n: int = player.inv[item]
		draw_string(font, Vector2(66.0, iy + 2.0), "%s  %d" % [ITEM_NAME[item], n], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
		iy += 40.0


func _draw_hotbar(font: Font) -> void:
	for i in range(4):
		var r := _slot_rect(i)
		var kind: String = SLOT_KINDS[i]
		var t := 0
		if kind != "hand":
			t = int(player.tier[kind])
		var owned := kind == "hand" or t > 0
		var sel: bool = player.equipped == kind
		draw_rect(r, Color(0, 0, 0, 0.5))
		if sel:
			draw_rect(r, Color(1.0, 0.9, 0.4, 0.22))
		draw_rect(r, Color(1.0, 0.9, 0.4, 0.95) if sel else Color(1, 1, 1, 0.35), false, 3.0 if sel else 2.0)
		_draw_tool_icon(kind, r.position + r.size * 0.5 + Vector2(0, -2), SLOT * 0.7, t, 1.0 if owned else 0.25)
		draw_string(font, r.position + Vector2(6, 18), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))
		if not owned:
			draw_string(font, r.position + Vector2(0, SLOT - 6), "locked", HORIZONTAL_ALIGNMENT_CENTER, SLOT, 14, Color(1, 1, 1, 0.5))
		elif t >= 2:
			draw_string(font, r.position + Vector2(0, SLOT - 6), "hardened", HORIZONTAL_ALIGNMENT_CENTER, SLOT, 14, Color(0.6, 0.9, 1.0, 0.9))


func _draw_buttons(font: Font) -> void:
	# Joystick
	var jo := _joy_origin if _joy_active else _joy_default()
	var ja := 0.32 if _joy_active else 0.14
	draw_circle(jo, JOY_R, Color(1, 1, 1, ja * 0.35))
	draw_arc(jo, JOY_R, 0.0, TAU, 48, Color(1, 1, 1, ja * 1.5), 3.0)
	var knob := jo
	if _joy_active:
		knob = jo + joy_vec * JOY_R
	draw_circle(knob, 42.0, Color(1, 1, 1, ja * 1.4))

	# Jump
	var jc := _jump_c()
	var jf := 0.30 if jump_held else 0.12
	draw_circle(jc, JUMP_R, Color(1, 1, 1, jf))
	draw_arc(jc, JUMP_R, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
	draw_string(font, Vector2(jc.x - JUMP_R, jc.y + 9.0), "JUMP", HORIZONTAL_ALIGNMENT_CENTER, JUMP_R * 2.0, 26, Color(1, 1, 1, 0.9))

	# Run (toggle)
	var rc := _run_c()
	var rcol := Color(0.35, 0.85, 1.0, 0.55) if run_on else Color(1, 1, 1, 0.12)
	draw_circle(rc, RUN_R, rcol)
	draw_arc(rc, RUN_R, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
	draw_string(font, Vector2(rc.x - RUN_R, rc.y + 8.0), "RUN", HORIZONTAL_ALIGNMENT_CENTER, RUN_R * 2.0, 22, Color(1, 1, 1, 0.95))

	# Act (swing / grab)
	var ac := _act_c()
	var afill := Color(1.0, 0.75, 0.25, 0.5) if act_held else Color(1.0, 0.75, 0.25, 0.22)
	draw_circle(ac, ACT_R, afill)
	draw_arc(ac, ACT_R, 0.0, TAU, 48, Color(1.0, 0.85, 0.4, 0.8), 3.5)
	var alabel: String = ACT_LABEL[player.equipped]
	draw_string(font, Vector2(ac.x - ACT_R, ac.y + 9.0), alabel, HORIZONTAL_ALIGNMENT_CENTER, ACT_R * 2.0, 24, Color(1, 1, 1, 0.95))

	# Camera switch
	var cc := _cam_c()
	draw_circle(cc, CAM_R, Color(1, 1, 1, 0.12))
	draw_arc(cc, CAM_R, 0.0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)
	draw_string(font, Vector2(cc.x - CAM_R, cc.y + 6.0), "CAM", HORIZONTAL_ALIGNMENT_CENTER, CAM_R * 2.0, 17, Color(1, 1, 1, 0.8))

	# Craft
	var kc := _craft_c()
	draw_circle(kc, CRAFT_R, Color(0.5, 0.9, 0.4, 0.22))
	draw_arc(kc, CRAFT_R, 0.0, TAU, 32, Color(0.7, 1.0, 0.6, 0.8), 2.5)
	draw_string(font, Vector2(kc.x - CRAFT_R, kc.y + 5.0), "CRAFT", HORIZONTAL_ALIGNMENT_CENTER, CRAFT_R * 2.0, 14, Color(1, 1, 1, 0.95))


func _draw_craft(font: Font) -> void:
	var s := _sz()
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.55))
	var r := _panel_rect()
	draw_rect(r, Color(0.08, 0.11, 0.09, 0.97))
	draw_rect(r, Color(0.6, 0.85, 0.5, 0.85), false, 3.0)
	draw_string(font, r.position + Vector2(24.0, 50.0), "CRAFTING", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.85, 1.0, 0.75))
	# close button
	var cb := _close_c()
	draw_circle(cb, 24.0, Color(1, 1, 1, 0.14))
	draw_line(cb + Vector2(-9, -9), cb + Vector2(9, 9), Color(1, 1, 1, 0.9), 3.0)
	draw_line(cb + Vector2(-9, 9), cb + Vector2(9, -9), Color(1, 1, 1, 0.9), 3.0)

	var recs: Array = player.recipes
	for i in range(recs.size()):
		var rr := _row_rect(i)
		var rec: Dictionary = recs[i]
		var why: String = player.can_craft(i)
		var ok := why == ""
		var owned := why == "Owned"
		var bg := Color(0.16, 0.16, 0.17, 0.95)
		if ok:
			bg = Color(0.18, 0.42, 0.2, 0.95)
		elif owned:
			bg = Color(0.17, 0.2, 0.3, 0.95)
		draw_rect(rr, bg)
		draw_rect(rr, Color(1, 1, 1, 0.18), false, 2.0)
		var kind: String = rec["tool"]
		var rt: int = rec["tier"]
		var icon_a := 1.0 if (ok or owned) else 0.55
		_draw_tool_icon(kind, rr.position + Vector2(rr.size.y * 0.5 + 6.0, rr.size.y * 0.5), rr.size.y * 0.75, rt, icon_a)
		var tx := rr.position.x + rr.size.y + 18.0
		draw_string(font, Vector2(tx, rr.position.y + rr.size.y * 0.5 - 2.0), String(rec["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.98))
		draw_string(font, Vector2(tx, rr.position.y + rr.size.y * 0.5 + 20.0), String(rec["note"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.6))
		# material costs: have / need
		var cost: Dictionary = rec["cost"]
		var cx := rr.position.x + rr.size.x * 0.44
		var cy := rr.position.y + rr.size.y * 0.5
		for item in ITEMS:
			if not cost.has(item):
				continue
			var need: int = cost[item]
			var have: int = player.inv[item]
			_draw_item_icon(item, Vector2(cx + 12.0, cy), 24.0)
			var ccol := Color(0.6, 1.0, 0.6) if have >= need else Color(1.0, 0.55, 0.5)
			draw_string(font, Vector2(cx + 34.0, cy + 8.0), "%d/%d" % [have, need], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, ccol)
			cx += 90.0
		# status on the right
		var label := "TAP TO CRAFT" if ok else why
		var lcol := Color(0.8, 1.0, 0.7) if ok else Color(1, 1, 1, 0.5)
		draw_string(font, Vector2(rr.end.x - 170.0, cy + 7.0), label, HORIZONTAL_ALIGNMENT_RIGHT, 160.0, 17, lcol)

	# footer: what you carry + hint
	var fy := r.end.y - 30.0
	var fx := r.position.x + 24.0
	for item in ITEMS:
		_draw_item_icon(item, Vector2(fx + 12.0, fy - 6.0), 24.0)
		var n: int = player.inv[item]
		draw_string(font, Vector2(fx + 34.0, fy + 1.0), "%s %d" % [ITEM_NAME[item], n], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
		fx += 140.0
	draw_string(font, Vector2(r.end.x - 24.0 - 330.0, fy + 1.0), "Upgrades replace your stone tool", HORIZONTAL_ALIGNMENT_RIGHT, 330.0, 15, Color(1, 1, 1, 0.5))


func _draw() -> void:
	var s := _sz()
	var font := ThemeDB.fallback_font

	if loading:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.09, 0.07, 1.0))
		draw_string(font, Vector2(0.0, s.y * 0.42), "WILD LANDS", HORIZONTAL_ALIGNMENT_CENTER, s.x, 64, Color(0.85, 1.0, 0.75))
		var bw := minf(s.x * 0.5, 600.0)
		var bx := (s.x - bw) * 0.5
		var by := s.y * 0.55
		draw_rect(Rect2(bx, by, bw, 14.0), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(bx, by, bw * clampf(load_value, 0.0, 1.0), 14.0), Color(0.6, 1.0, 0.5))
		draw_string(font, Vector2(0.0, by + 52.0), load_text, HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, Color(1, 1, 1, 0.8))
		return

	if player == null:
		return

	if map_mode != 2:
		_draw_map(font)
	_draw_inventory(font)
	_draw_hotbar(font)
	_draw_buttons(font)

	if show_crosshair:
		draw_circle(s * 0.5, 2.5, Color(1, 1, 1, 0.7))

	# what ACT would do right now
	if prompt != "":
		_shadow_text(font, Vector2(0.0, s.y * 0.62), prompt, HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, Color(1, 1, 1, 0.95))
	if target_frac >= 0.0:
		var bw2 := 120.0
		var bx2 := s.x * 0.5 - bw2 * 0.5
		var by2 := s.y * 0.62 + 14.0
		draw_rect(Rect2(bx2 - 2.0, by2 - 2.0, bw2 + 4.0, 12.0), Color(0, 0, 0, 0.55))
		var fc := Color(0.5, 0.95, 0.4).lerp(Color(1.0, 0.35, 0.25), 1.0 - target_frac)
		draw_rect(Rect2(bx2, by2, bw2 * clampf(target_frac, 0.0, 1.0), 8.0), fc)

	# toasts
	var ty := 70.0
	for tt in toasts:
		var life: float = tt["life"]
		var age: float = tt["t"]
		var a := clampf((life - age) / 0.5, 0.0, 1.0) * clampf(age / 0.08, 0.0, 1.0)
		var col: Color = tt["col"]
		col.a = a
		_shadow_text(font, Vector2(0.0, ty), String(tt["text"]), HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, col)
		ty += 34.0

	if hint_t < 12.0:
		var ha := clampf(1.0 - (hint_t - 9.0) / 3.0, 0.0, 1.0)
		draw_string(font, Vector2(0.0, s.y - 112.0), "Left: move   Right: drag to look   ACT: grab / chop / mine   CRAFT: make tools", HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, Color(1, 1, 1, 0.85 * ha))

	if map_mode == 2:
		_draw_map(font)

	if craft_open:
		_draw_craft(font)
