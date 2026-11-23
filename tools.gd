extends RefCounted
# axe / pickaxe / sword models, just boxes and cylinders stuck together
# handle goes up the Y axis, grip at 0,0,0, blade points +X
# tier 1 = stone, tier 2 = hardened (darker wood, blue-ish head)


static func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(col)
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, sides: int = 6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	cm.material = _mat(col)
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func build(kind: String, tier: int) -> Node3D:
	var root := Node3D.new()
	var wood := Color(0.52, 0.35, 0.19)
	var metal := Color(0.64, 0.65, 0.70)
	if tier >= 2:
		wood = Color(0.34, 0.22, 0.13)
		metal = Color(0.55, 0.82, 0.98)
	var dark := metal.darkened(0.3)
	var bright := metal.lightened(0.25)
	var lash := Color(0.78, 0.62, 0.36)

	if kind == "axe":
		_cyl(root, 0.022, 0.027, 0.85, Vector3(0.0, 0.27, 0.0), wood)
		_box(root, Vector3(0.10, 0.18, 0.075), Vector3(0.03, 0.62, 0.0), dark)
		_box(root, Vector3(0.05, 0.25, 0.03), Vector3(0.115, 0.62, 0.0), metal)
		_box(root, Vector3(0.02, 0.31, 0.02), Vector3(0.15, 0.62, 0.0), bright)
		_box(root, Vector3(0.065, 0.035, 0.065), Vector3(0.0, 0.53, 0.0), lash)
	elif kind == "pickaxe":
		_cyl(root, 0.022, 0.027, 0.85, Vector3(0.0, 0.27, 0.0), wood)
		_box(root, Vector3(0.09, 0.09, 0.09), Vector3(0.0, 0.66, 0.0), dark)
		# two curved arms, each ending in a pointed tip
		_box(root, Vector3(0.30, 0.05, 0.05), Vector3(0.17, 0.655, 0.0), metal, Vector3(0.0, 0.0, -0.25))
		_box(root, Vector3(0.30, 0.05, 0.05), Vector3(-0.17, 0.655, 0.0), metal, Vector3(0.0, 0.0, 0.25))
		_cyl(root, 0.0, 0.032, 0.12, Vector3(0.345, 0.61, 0.0), bright, Vector3(0.0, 0.0, -PI * 0.5 - 0.25), 5)
		_cyl(root, 0.0, 0.032, 0.12, Vector3(-0.345, 0.61, 0.0), bright, Vector3(0.0, 0.0, PI * 0.5 + 0.25), 5)
		_box(root, Vector3(0.065, 0.035, 0.065), Vector3(0.0, 0.58, 0.0), lash)
	elif kind == "sword":
		_cyl(root, 0.022, 0.022, 0.2, Vector3(0.0, -0.01, 0.0), wood)
		_box(root, Vector3(0.05, 0.05, 0.05), Vector3(0.0, -0.13, 0.0), dark)
		_box(root, Vector3(0.22, 0.035, 0.06), Vector3(0.0, 0.10, 0.0), dark)
		_box(root, Vector3(0.065, 0.70, 0.018), Vector3(0.0, 0.47, 0.0), metal)
		_box(root, Vector3(0.02, 0.62, 0.024), Vector3(0.0, 0.46, 0.0), bright)
		var tip := _cyl(root, 0.0, 0.046, 0.12, Vector3(0.0, 0.88, 0.0), metal, Vector3.ZERO, 4)
		tip.scale = Vector3(1.0, 1.0, 0.4)
	return root
