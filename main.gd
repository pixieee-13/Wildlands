extends Node3D
# main script. sets up sky + sun, makes the world, then spawns the player

# 0 = Low (older phones), 1 = Medium (default), 2 = High (strong phones / PC)
const QUALITY_LEVEL := 1

# Shadows are the most expensive effect on phones. Turn on only on strong devices.
const SHADOWS := false

const WorldGen = preload("res://world.gd")
const PlayerCtl = preload("res://player.gd")
const TouchUI = preload("res://touch_ui.gd")

var world
var player
var ui
var cloud_layer: Node3D


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = TouchUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)

	_build_environment()
	_build_clouds()

	await get_tree().process_frame
	await get_tree().process_frame

	world = WorldGen.new()
	world.quality = QUALITY_LEVEL
	add_child(world)
	world.progress.connect(ui.set_progress)
	await world.generate()

	player = PlayerCtl.new()
	add_child(player)
	player.setup(world, ui)
	ui.hide_loading()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.13, 0.33, 0.78)
	sky_mat.sky_horizon_color = Color(0.66, 0.82, 0.95)
	sky_mat.ground_horizon_color = Color(0.66, 0.82, 0.95)
	sky_mat.ground_bottom_color = Color(0.25, 0.38, 0.46)
	sky_mat.sky_curve = 0.13
	sky_mat.sun_angle_max = 28.0
	sky_mat.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.82, 0.95)
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.12
	env.fog_sun_scatter = 0.2

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.07

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, -40.0, 0.0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = SHADOWS
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 100.0
	add_child(sun)


## Low-poly clouds that slowly drift around the island.
func _build_clouds() -> void:
	cloud_layer = Node3D.new()
	add_child(cloud_layer)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.92, 0.95, 1.0)
	mat.emission_energy_multiplier = 0.45
	mat.roughness = 1.0
	mat.disable_fog = true
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 7
	sm.rings = 4
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in range(14):
		var cloud := Node3D.new()
		var ang := r.randf() * TAU
		var dist := r.randf_range(60.0, 420.0)
		cloud.position = Vector3(cos(ang) * dist, r.randf_range(95.0, 150.0), sin(ang) * dist)
		cloud.rotation.y = r.randf() * TAU
		var parts := r.randi_range(3, 5)
		for k in range(parts):
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			mi.material_override = mat
			mi.position = Vector3((float(k) - float(parts) * 0.5) * 15.0, r.randf_range(-2.0, 4.0), r.randf_range(-7.0, 7.0))
			mi.scale = Vector3(r.randf_range(14.0, 24.0), r.randf_range(6.0, 10.0), r.randf_range(10.0, 15.0))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(mi)
		cloud_layer.add_child(cloud)


func _process(delta: float) -> void:
	if cloud_layer != null:
		cloud_layer.rotation.y += delta * 0.012
