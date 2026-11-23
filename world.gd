extends Node3D
# the whole island, made in code. 7 biomes, flat shaded low poly so it runs ok on phones
# meadow, forest, jungle, dark forest, desert, taiga, snow mountains

signal progress(value: float, text: String)
# sound requests from the world (tree crash, rock break), player plays them
signal sfx(sound_name: String, pos: Vector3)

enum Biome { MEADOW, FOREST, JUNGLE, DARK, DESERT, TAIGA, SNOW }

const SEED := 20260617
const MAP_SIZE := 512.0
const CELL := 4.0
const N := 128
const W := 129
const CHUNK_CELLS := 32
const CHUNKS := 4
const OBST_CELL := 8.0

const MEADOW_C := Vector2(0.0, 20.0)
const FOREST_C := Vector2(130.0, -20.0)
const JUNGLE_C := Vector2(110.0, 130.0)
const DARK_C := Vector2(-150.0, 60.0)
const DESERT_C := Vector2(-70.0, 150.0)
const TAIGA_C := Vector2(30.0, -150.0)
const SNOW_C := Vector2(-120.0, -110.0)
const BIOME_CENTERS := [MEADOW_C, FOREST_C, JUNGLE_C, DARK_C, DESERT_C, TAIGA_C, SNOW_C]

# sRGB ground colours per biome (converted to linear when painted)
const BIOME_COLORS := [
	Color(0.50, 0.76, 0.22), # meadow
	Color(0.27, 0.54, 0.17), # forest
	Color(0.16, 0.50, 0.15), # jungle
	Color(0.21, 0.31, 0.15), # dark
	Color(0.88, 0.73, 0.42), # desert
	Color(0.33, 0.47, 0.27), # taiga
	Color(0.92, 0.95, 0.98), # snow
]
const SAND_C := Color(0.88, 0.80, 0.56)
const SEABED_C := Color(0.66, 0.60, 0.42)
const SNOW_COL := Color(0.94, 0.96, 1.0)
const DIRT_C := Color(0.50, 0.38, 0.24)
const ROCK_C := Color(0.45, 0.43, 0.41)

# Density per biome (index = Biome): MEADOW, FOREST, JUNGLE, DARK, DESERT, TAIGA, SNOW
const TREE_DENS := [0.16, 0.85, 0.95, 0.55, 0.10, 0.70, 0.14]
const BUSH_DENS := [0.18, 0.50, 0.70, 0.25, 0.0, 0.12, 0.0]
const GRASS_DENS := [0.95, 0.50, 0.70, 0.35, 0.0, 0.30, 0.0]
const FLOWER_DENS := [0.40, 0.06, 0.12, 0.0, 0.0, 0.03, 0.0]
const MUSH_DENS := [0.01, 0.07, 0.05, 0.25, 0.0, 0.06, 0.0]
const ROCK_DENS := [0.12, 0.10, 0.10, 0.16, 0.35, 0.30, 0.50]
# Loose items lying on the ground (pick them up by hand)
const STICK_DENS := [0.07, 0.18, 0.16, 0.16, 0.01, 0.16, 0.0]
const STONE_DENS := [0.07, 0.07, 0.06, 0.09, 0.11, 0.11, 0.13]

const BIOME_NAMES := ["Meadow", "Forest", "Jungle", "Dark Forest", "Desert", "Taiga", "Snow Mountains"]
const MM_RES := 256

# Harvesting
const TREE_FALL_TIME := 1.35
const TREE_VANISH_DELAY := 10.0

# Quality presets: [tree range, bush/rock range, flower/mushroom range, grass range, density multiplier]
const QUALITY := [
	[170.0, 110.0, 50.0, 35.0, 0.7],
	[240.0, 150.0, 70.0, 50.0, 1.0],
	[330.0, 200.0, 90.0, 65.0, 1.3],
]

const ICO_F := [
	[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
	[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
	[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
	[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
]

const TERRAIN_SHADER := """
shader_type spatial;

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d1 = texture(detail_tex, wpos.xz * 0.035).r;
	float d2 = texture(detail_tex, wpos.xz * 0.42).r;
	ALBEDO = COLOR.rgb * (0.68 + 0.55 * (d1 * 0.55 + d2 * 0.45));
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float map_size = 512.0;
uniform float water_y = 0.0;
uniform float tex_k = 0.99;
uniform float tex_off = 0.004;
uniform vec3 shallow_color : source_color = vec3(0.20, 0.68, 0.64);
uniform vec3 deep_color : source_color = vec3(0.02, 0.18, 0.32);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 huv = (wpos.xz / map_size + 0.5) * tex_k + tex_off;
	float depth = max(water_y - texture(height_tex, huv).r, 0.0);
	float shore = 1.0 - smoothstep(0.0, 0.6, depth);
	float wave = 0.5 + 0.5 * sin(TIME * 1.6 + wpos.x * 0.8 + wpos.z * 0.6);
	float foam = shore * smoothstep(0.45, 0.9, wave);
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 6.0, depth));
	ALBEDO = mix(col, vec3(0.95), foam);
	ALPHA = clamp(mix(0.35, 0.93, smoothstep(0.0, 3.0, depth)) + foam, 0.0, 1.0);
	ROUGHNESS = 0.15;
	SPECULAR = 0.5;
}
"""

var quality := 1
var density_mul := 1.0
var water_y := 0.0
var half_size := MAP_SIZE * 0.5

var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var biome1 := PackedByteArray()
var biome2 := PackedByteArray()
var blend := PackedFloat32Array()
var path_mask := PackedFloat32Array()

var obstacles := {}
var rocks := {}
# Harvestable things (trees, rocks, bushes, ground pickups). They live inside
# MultiMeshes for speed; an entity is "detached" into its own node when touched.
var ents: Array = []
var ent_grid := {}
var inst_ent := {}
var minimap_tex: ImageTexture
var meshes := {}
var inst := {}
var rng := RandomNumberGenerator.new()
var detail_tex: ImageTexture
var prop_mat: StandardMaterial3D

var hub := MEADOW_C
var spawn_pos := Vector3.ZERO
var spawn_yaw := 0.0

var n_shape: FastNoiseLite
var n_hills: FastNoiseLite
var n_ridge: FastNoiseLite
var n_lake: FastNoiseLite
var n_warp: FastNoiseLite
var n_dune: FastNoiseLite
var n_patch: FastNoiseLite
var n_forest: FastNoiseLite
var n_flower: FastNoiseLite

# mesh builder state
var _mv := PackedVector3Array()
var _mn := PackedVector3Array()
var _mc := PackedColorArray()
var _mrng := RandomNumberGenerator.new()
var _snow_cap := false
var _ao_h := 5.0
var _ico: Array = []


# ------------------------------------------------------------------ main flow

func generate() -> void:
	var q: Array = QUALITY[quality]
	density_mul = q[4]
	rng.seed = SEED

	heights.resize(W * W)
	normals.resize(W * W)
	colors.resize(W * W)
	biome1.resize(W * W)
	biome2.resize(W * W)
	blend.resize(W * W)
	path_mask.resize(W * W)

	_make_noises()
	await _yield(0.0, "Shaping the land...")
	await _gen_terrain_data()
	_compute_normals()
	_find_spawn()
	_build_paths()
	await _yield(0.3, "Painting biomes...")
	await _paint()
	_make_textures()
	await _yield(0.42, "Making low-poly models...")
	_build_meshes(q)
	await _scatter_trees()
	await _scatter_bushes()
	await _scatter_grass()
	await _scatter_flowers()
	await _scatter_mushrooms()
	await _scatter_rocks()
	await _scatter_pickups()
	_scatter_starter()
	await _build_terrain()
	await _build_multimeshes()
	await _build_minimap()
	await _yield(0.97, "Filling the lakes...")
	_build_water()
	progress.emit(1.0, "Ready")


func _yield(v: float, text: String) -> void:
	progress.emit(v, text)
	await get_tree().process_frame


# ------------------------------------------------------------------ noise

func _noise(off: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = SEED + off
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	return n


func _make_noises() -> void:
	n_shape = _noise(1, 0.008, 3)
	n_hills = _noise(2, 0.007, 4)
	n_ridge = _noise(3, 0.011, 3)
	n_lake = _noise(4, 0.011, 2)
	n_warp = _noise(5, 0.012, 2)
	n_dune = _noise(6, 0.030, 2)
	n_patch = _noise(7, 0.045, 2)
	n_forest = _noise(8, 0.020, 3)
	n_flower = _noise(9, 0.070, 2)


# ------------------------------------------------------------------ terrain data

func _gen_terrain_data() -> void:
	for j in range(W):
		if j % 8 == 0:
			await _yield(0.02 + 0.26 * float(j) / float(W), "Raising mountains and digging lakes...")
		var z := j * CELL - half_size
		for i in range(W):
			var x := i * CELL - half_size
			var k := j * W + i
			heights[k] = _gen_height(x, z)
			_gen_biome(x, z, k)


func _gen_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var nx := x / half_size
	var nz := z / half_size
	var d := sqrt(nx * nx + nz * nz)
	var shape := n_shape.get_noise_2d(x, z)
	var mask := 1.0 - smoothstep(0.60, 1.0, d + shape * 0.12)

	var hills := n_hills.get_noise_2d(x, z) * 0.5 + 0.5
	var w_des := 1.0 - smoothstep(25.0, 85.0, p.distance_to(DESERT_C))
	var w_dark := 1.0 - smoothstep(25.0, 90.0, p.distance_to(DARK_C))
	var h_land := 5.0 + hills * (9.0 - 5.0 * w_des - 5.0 * w_dark)
	h_land += w_des * n_dune.get_noise_2d(x, z) * 3.0

	var md := p.distance_to(SNOW_C) + n_shape.get_noise_2d(x + 700.0, z - 300.0) * 30.0
	var mw := 1.0 - smoothstep(50.0, 150.0, md)
	var ridge := 1.0 - absf(n_ridge.get_noise_2d(x, z))
	h_land += mw * (12.0 + ridge * ridge * 40.0)

	var tw := 1.0 - smoothstep(20.0, 80.0, p.distance_to(TAIGA_C))
	h_land += tw * hills * 8.0

	var h := (h_land + 12.0) * mask - 12.0

	var lk := n_lake.get_noise_2d(x, z) * 0.5 + 0.5
	var thr := 0.63 - 0.08 * w_dark
	var lake := smoothstep(thr, thr + 0.09, lk) * (1.0 - smoothstep(10.0, 18.0, h_land)) * smoothstep(0.7, 0.9, mask)
	h = lerpf(h, -3.0, lake)
	return h


func _gen_biome(x: float, z: float, k: int) -> void:
	var wx := x + n_warp.get_noise_2d(x, z) * 40.0
	var wz := z + n_warp.get_noise_2d(z + 311.0, x - 173.0) * 40.0
	var best := 1.0e9
	var second := 1.0e9
	var bi := 0
	var si := 0
	for b in range(7):
		var c: Vector2 = BIOME_CENTERS[b]
		var dx := wx - c.x
		var dz := wz - c.y
		var d := sqrt(dx * dx + dz * dz)
		if d < best:
			second = best
			si = bi
			best = d
			bi = b
		elif d < second:
			second = d
			si = b
	biome1[k] = bi
	biome2[k] = si
	blend[k] = 0.5 * (1.0 - smoothstep(0.0, 26.0, second - best))


func _compute_normals() -> void:
	for j in range(W):
		var jd := maxi(j - 1, 0)
		var ju := mini(j + 1, N)
		for i in range(W):
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, N)
			var hl := heights[j * W + il]
			var hr := heights[j * W + ir]
			var hu := heights[jd * W + i]
			var hd := heights[ju * W + i]
			normals[j * W + i] = Vector3(hl - hr, 2.0 * CELL, hu - hd).normalized()


func _idx(x: float, z: float) -> int:
	var ix := clampi(int(round((x + half_size) / CELL)), 0, N)
	var iz := clampi(int(round((z + half_size) / CELL)), 0, N)
	return iz * W + ix


func _pick(i: int) -> int:
	if rng.randf() < blend[i]:
		return biome2[i]
	return biome1[i]


## Height of the terrain surface, matching the rendered triangles exactly.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + half_size) / CELL, 0.0, float(N) - 0.001)
	var fz := clampf((z + half_size) / CELL, 0.0, float(N) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var i := iz * W + ix
	var ha := heights[i]
	var hb := heights[i + 1]
	var hc := heights[i + W]
	var hd := heights[i + W + 1]
	if tx + tz <= 1.0:
		return ha + (hb - ha) * tx + (hc - ha) * tz
	return hd + (hc - hd) * (1.0 - tx) + (hb - hd) * (1.0 - tz)


func _find_spawn() -> void:
	var best := MEADOW_C
	var found := false
	for rr in range(0, 100, 4):
		for a in range(0, 360, 20):
			var p := MEADOW_C + Vector2(float(rr), 0.0).rotated(deg_to_rad(float(a)))
			var i := _idx(p.x, p.y)
			if heights[i] > 2.0 and heights[i] < 14.0 and normals[i].y > 0.93:
				best = p
				found = true
				break
		if found:
			break
	hub = best
	spawn_pos = Vector3(best.x, maxf(height_at(best.x, best.y), 1.0), best.y)
	var dir := FOREST_C - hub
	spawn_yaw = atan2(-dir.x, -dir.y)


# ------------------------------------------------------------------ dirt paths (colour only)

func _build_paths() -> void:
	var targets := [FOREST_C, JUNGLE_C, DESERT_C, DARK_C, TAIGA_C, SNOW_C]
	var s := 0
	for t in targets:
		var tv: Vector2 = t
		var dir := tv - hub
		var length := dir.length()
		var perp := Vector2(-dir.y, dir.x).normalized()
		var steps := int(length / 2.5)
		var phase := float(s) * 1.7
		s += 1
		for si in range(steps + 1):
			var u := float(si) / float(steps)
			var wob := sin(u * 7.0 + phase) * 11.0 * sin(u * PI)
			var p := hub + dir * u + perp * wob
			var i := _idx(p.x, p.y)
			if heights[i] < 0.6 or normals[i].y < 0.72:
				continue
			_mark_path(p)


func _mark_path(p: Vector2) -> void:
	var cx := int(round((p.x + half_size) / CELL))
	var cz := int(round((p.y + half_size) / CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var gx := cx + dx
			var gz := cz + dz
			if gx < 0 or gz < 0 or gx > N or gz > N:
				continue
			var vx := gx * CELL - half_size
			var vz := gz * CELL - half_size
			var dist := Vector2(vx - p.x, vz - p.y).length()
			var wgt := 1.0 - smoothstep(1.5, 4.5, dist)
			var k := gz * W + gx
			path_mask[k] = maxf(path_mask[k], wgt)


# ------------------------------------------------------------------ painting & terrain mesh

func _paint() -> void:
	var lin: Array = []
	for c in BIOME_COLORS:
		var cc: Color = c
		lin.append(cc.srgb_to_linear())
	var sand_l := SAND_C.srgb_to_linear()
	var seabed_l := SEABED_C.srgb_to_linear()
	var snow_l := SNOW_COL.srgb_to_linear()
	var dirt_l := DIRT_C.srgb_to_linear()
	var rock_l := ROCK_C.srgb_to_linear()

	for j in range(W):
		if j % 16 == 0:
			await _yield(0.3 + 0.1 * float(j) / float(W), "Painting biomes...")
		var z := j * CELL - half_size
		for i in range(W):
			var k := j * W + i
			var x := i * CELL - half_size
			var h := heights[k]
			var nrm := normals[k]
			var b1: int = biome1[k]
			var ca: Color = lin[b1]
			var cb: Color = lin[biome2[k]]
			var c := ca.lerp(cb, blend[k])

			var pv := n_patch.get_noise_2d(x, z)
			c = Color(c.r * (1.0 + pv * 0.18), c.g * (1.0 + pv * 0.14), c.b * (1.0 + pv * 0.14), 1.0)

			if b1 != Biome.DESERT:
				var sand := 1.0 - smoothstep(0.4, 2.6, h + pv * 0.4)
				c = c.lerp(sand_l, sand)
			var wet := 1.0 - smoothstep(-0.4, 0.5, h)
			c = c.lerp(seabed_l, wet)
			if h < 0.0:
				var dk := 0.55 + 0.45 * smoothstep(-6.0, 0.0, h)
				c = Color(c.r * dk, c.g * dk, c.b * dk, 1.0)
			var snow_alt := smoothstep(30.0, 42.0, h + pv * 5.0)
			c = c.lerp(snow_l, snow_alt)
			c = c.lerp(dirt_l, path_mask[k] * 0.9)
			var rock := 1.0 - smoothstep(0.60, 0.82, nrm.y)
			c = c.lerp(rock_l, rock * 0.9)
			colors[k] = c


func _build_terrain() -> void:
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("detail_tex", detail_tex)
	for cz in range(CHUNKS):
		await _yield(0.86 + 0.04 * float(cz) / float(CHUNKS), "Building terrain...")
		for cx in range(CHUNKS):
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(cx, cz)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)


func _make_textures() -> void:
	var dn := FastNoiseLite.new()
	dn.seed = SEED + 20
	dn.frequency = 0.03
	dn.fractal_type = FastNoiseLite.FRACTAL_FBM
	dn.fractal_octaves = 4
	var img := dn.get_seamless_image(256, 256)
	img.generate_mipmaps()
	detail_tex = ImageTexture.create_from_image(img)


## Flat-shaded (non-indexed) chunk: every triangle has its own normal, vertex colours blend smoothly.
func _chunk_mesh(cx: int, cz: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var x0 := cx * CHUNK_CELLS
	var z0 := cz * CHUNK_CELLS
	for j in range(CHUNK_CELLS):
		for i in range(CHUNK_CELLS):
			var gi := x0 + i
			var gj := z0 + j
			var ka := gj * W + gi
			var kb := ka + 1
			var kc := ka + W
			var kd := kc + 1
			var pa := Vector3(gi * CELL - half_size, heights[ka], gj * CELL - half_size)
			var pb := Vector3(pa.x + CELL, heights[kb], pa.z)
			var pc := Vector3(pa.x, heights[kc], pa.z + CELL)
			var pd := Vector3(pa.x + CELL, heights[kd], pa.z + CELL)
			# clockwise seen from above = front face in Godot
			var n1 := -((pb - pa).cross(pc - pa).normalized())
			var n2 := -((pd - pb).cross(pc - pb).normalized())
			verts.append(pa)
			verts.append(pb)
			verts.append(pc)
			verts.append(pb)
			verts.append(pd)
			verts.append(pc)
			norms.append(n1)
			norms.append(n1)
			norms.append(n1)
			norms.append(n2)
			norms.append(n2)
			norms.append(n2)
			cols.append(colors[ka])
			cols.append(colors[kb])
			cols.append(colors[kc])
			cols.append(colors[kb])
			cols.append(colors[kd])
			cols.append(colors[kc])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


# ------------------------------------------------------------------ low-poly mesh builder

func _mb_begin(ao_h: float = 5.0) -> void:
	_ao_h = ao_h
	_mv = PackedVector3Array()
	_mn = PackedVector3Array()
	_mc = PackedColorArray()
	_snow_cap = false


func _mb_end() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _mv
	arrays[Mesh.ARRAY_NORMAL] = _mn
	arrays[Mesh.ARRAY_COLOR] = _mc
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func _mk(key: String, range_end: float, cs: float) -> void:
	meshes[key] = {"mesh": _mb_end(), "range": range_end, "cs": cs}


## Adds one flat-shaded triangle of a convex-ish solid. `center` is a point inside the solid,
## used to make sure the triangle faces outward. Vertex colours get a soft height gradient
## (darker near the ground) so props look painted, not flat.
func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, center: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	var cen := (a + b + c) / 3.0
	if n.dot(cen - center) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var on := (-n).normalized()
	var cc := col
	if _snow_cap and on.y > 0.55:
		cc = Color(0.95, 0.97, 1.0)
	var m := _mrng.randf_range(0.92, 1.06) * (0.9 + 0.14 * clampf(on.y, -0.2, 1.0))
	_mv.append(a)
	_mv.append(b)
	_mv.append(c)
	_mc.append(_shade(cc, a.y, m))
	_mc.append(_shade(cc, b.y, m))
	_mc.append(_shade(cc, c.y, m))
	for k in range(3):
		_mn.append(on)


func _shade(col: Color, y: float, m: float) -> Color:
	var ao := lerpf(0.6, 1.0, clampf(y / _ao_h, 0.0, 1.0))
	var f := ao * m
	return Color(col.r * f, col.g * f, col.b * f, 1.0).srgb_to_linear()


## Tapered cylinder from p0 to p1 (no caps). r1 = 0 makes a cone.
func _limb(p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
	var d := (p1 - p0).normalized()
	var ref := Vector3.UP
	if absf(d.y) > 0.9:
		ref = Vector3.RIGHT
	var u := d.cross(ref).normalized()
	var v := d.cross(u).normalized()
	var center := (p0 + p1) * 0.5
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var o0 := u * cos(a0) + v * sin(a0)
		var o1 := u * cos(a1) + v * sin(a1)
		var b0 := p0 + o0 * r0
		var b1 := p0 + o1 * r0
		var t0 := p1 + o0 * r1
		var t1 := p1 + o1 * r1
		_tri(b0, b1, t1, col, center)
		if r1 > 0.001:
			_tri(b0, t1, t0, col, center)


## Jittered low-poly ball (icosahedron, 20 triangles).
func _blob(c: Vector3, rx: float, ry: float, rz: float, col: Color, jit: float) -> void:
	var pts: Array = []
	for u in _ico:
		var uu: Vector3 = u
		var j := 1.0 + _mrng.randf_range(-jit, jit)
		pts.append(c + Vector3(uu.x * rx, uu.y * ry, uu.z * rz) * j)
	for f in ICO_F:
		var fa: Array = f
		_tri(pts[fa[0]], pts[fa[1]], pts[fa[2]], col, c)


## Double-sided grass blade: base verts a,b and tip c.
func _blade(a: Vector3, b: Vector3, c: Vector3, c_base: Color, c_tip: Color) -> void:
	var lb := c_base.srgb_to_linear()
	var lt := c_tip.srgb_to_linear()
	for side in range(2):
		if side == 0:
			_mv.append(a)
			_mv.append(b)
			_mv.append(c)
		else:
			_mv.append(a)
			_mv.append(c)
			_mv.append(b)
		for k in range(3):
			_mn.append(Vector3.UP)
		_mc.append(lb)
		if side == 0:
			_mc.append(lb)
			_mc.append(lt)
		else:
			_mc.append(lt)
			_mc.append(lb)


func _build_meshes(q: Array) -> void:
	var tree_r: float = q[0]
	var bush_r: float = q[1]
	var small_r: float = q[2]
	var grass_r: float = q[3]
	var t := (1.0 + sqrt(5.0)) * 0.5
	_ico = [
		Vector3(-1, t, 0).normalized(), Vector3(1, t, 0).normalized(),
		Vector3(-1, -t, 0).normalized(), Vector3(1, -t, 0).normalized(),
		Vector3(0, -1, t).normalized(), Vector3(0, 1, t).normalized(),
		Vector3(0, -1, -t).normalized(), Vector3(0, 1, -t).normalized(),
		Vector3(t, 0, -1).normalized(), Vector3(t, 0, 1).normalized(),
		Vector3(-t, 0, -1).normalized(), Vector3(-t, 0, 1).normalized(),
	]
	_mrng.seed = SEED + 99

	prop_mat = StandardMaterial3D.new()
	prop_mat.vertex_color_use_as_albedo = true
	prop_mat.roughness = 1.0
	prop_mat.metallic_specular = 0.1

	var trunk := Color(0.40, 0.28, 0.17)

	# --- round trees (oak / meadow / jungle / dark forest)
	var palettes := {
		"oak": [Color(0.30, 0.58, 0.20), 3, 1.0],
		"meadow": [Color(0.48, 0.72, 0.25), 2, 0.95],
		"jungle": [Color(0.12, 0.52, 0.25), 3, 1.25],
		"dark": [Color(0.20, 0.35, 0.21), 2, 1.0],
	}
	for pname in palettes.keys():
		var info: Array = palettes[pname]
		var lc: Color = info[0]
		var cnt: int = info[1]
		var big: float = info[2]
		for v in range(cnt):
			_mb_begin()
			_limb(Vector3(0.0, -0.6, 0.0), Vector3(0.0, 2.4 * big, 0.0), 0.30 * big, 0.18 * big, 5, trunk)
			_blob(Vector3(0.0, 3.5 * big, 0.0), 1.8 * big, 1.5 * big, 1.8 * big, lc, 0.18)
			for k in range(3):
				var ang := _mrng.randf() * TAU
				var oc := Vector3(cos(ang) * big, (2.7 + _mrng.randf() * 0.6) * big, sin(ang) * big)
				_blob(oc, 1.1 * big, 0.95 * big, 1.1 * big, lc.darkened(0.1), 0.2)
			_mk("%s_%d" % [pname, v + 1], tree_r, 128.0)

	# --- pines and snowy pines
	for snowy in range(2):
		var count := 3 if snowy == 0 else 2
		for v in range(count):
			_mb_begin()
			var s := 0.9 + 0.17 * float(v)
			_limb(Vector3(0.0, -0.6, 0.0), Vector3(0.0, 1.5 * s, 0.0), 0.26 * s, 0.18 * s, 5, trunk)
			for ci in range(4):
				var by := (0.9 + 1.15 * float(ci)) * s
				var r := (1.8 - 0.4 * float(ci)) * s
				var h := (2.4 - 0.2 * float(ci)) * s
				var col := Color(0.14 + 0.02 * float(ci), 0.38 + 0.03 * float(ci), 0.22, 1.0)
				if snowy == 1 and ci % 2 == 1:
					col = Color(0.85, 0.92, 0.95)
				_limb(Vector3(0.0, by, 0.0), Vector3(0.0, by + h, 0.0), r, 0.0, 7, col)
			if snowy == 0:
				_mk("pine_%d" % (v + 1), tree_r, 128.0)
			else:
				_mk("snowpine_%d" % (v + 1), tree_r, 128.0)

	# --- dead trees
	var bark := Color(0.46, 0.39, 0.33)
	for v in range(2):
		_mb_begin()
		var f := 1.0 + 0.2 * float(v)
		_limb(Vector3(0.0, -0.6, 0.0), Vector3(0.1, 3.8 * f, 0.0), 0.28, 0.08, 5, bark)
		_limb(Vector3(0.05, 2.4 * f, 0.0), Vector3(1.3, 3.7 * f, 0.3), 0.13, 0.04, 4, bark)
		_limb(Vector3(0.0, 3.0 * f, 0.0), Vector3(-1.1, 4.3 * f, -0.4), 0.11, 0.04, 4, bark)
		_limb(Vector3(0.1, 3.5 * f, 0.0), Vector3(0.4, 4.9 * f, 0.7), 0.09, 0.03, 4, bark)
		_mk("dead_%d" % (v + 1), tree_r, 128.0)

	# --- cacti
	var cg := Color(0.30, 0.56, 0.28)
	for v in range(2):
		_mb_begin()
		var f := 1.0 + 0.25 * float(v)
		_limb(Vector3(0.0, -0.5, 0.0), Vector3(0.0, 2.6 * f, 0.0), 0.36, 0.30, 6, cg)
		_limb(Vector3(0.3, 1.2 * f, 0.0), Vector3(1.0, 1.3 * f, 0.0), 0.2, 0.2, 5, cg)
		_limb(Vector3(1.0, 1.3 * f, 0.0), Vector3(1.0, 2.2 * f, 0.0), 0.2, 0.17, 5, cg)
		_limb(Vector3(-0.3, 1.7 * f, 0.0), Vector3(-0.9, 1.8 * f, 0.0), 0.18, 0.18, 5, cg)
		_limb(Vector3(-0.9, 1.8 * f, 0.0), Vector3(-0.9, 2.5 * f, 0.0), 0.18, 0.15, 5, cg)
		_mk("cactus_%d" % (v + 1), tree_r, 128.0)

	# --- bushes
	for v in range(2):
		_mb_begin(1.6)
		_blob(Vector3(0.0, 0.55, 0.0), 1.0, 0.75, 1.0, Color(0.28, 0.55, 0.2), 0.2)
		_blob(Vector3(0.7, 0.4, 0.3), 0.7, 0.55, 0.7, Color(0.25, 0.5, 0.18), 0.2)
		_mk("bush_%d" % (v + 1), bush_r, 96.0)
	_mb_begin(1.6)
	_blob(Vector3(0.0, 0.55, 0.0), 1.0, 0.75, 1.0, Color(0.18, 0.32, 0.18), 0.2)
	_blob(Vector3(-0.7, 0.4, 0.3), 0.7, 0.55, 0.7, Color(0.16, 0.3, 0.16), 0.2)
	_mk("bush_dark_1", bush_r, 96.0)

	# --- rocks
	for kind in range(3):
		var rname := "rock"
		var rcol := Color(0.52, 0.52, 0.54)
		var count := 3
		if kind == 1:
			rname = "rockdesert"
			rcol = Color(0.78, 0.62, 0.42)
			count = 2
		elif kind == 2:
			rname = "rocksnow"
			rcol = Color(0.55, 0.56, 0.60)
			count = 2
		for v in range(count):
			_mb_begin(2.0)
			_snow_cap = (kind == 2)
			_blob(Vector3(0.0, 0.45, 0.0), 1.2, 0.9, 1.0, rcol, 0.28)
			_blob(Vector3(0.9, 0.25, 0.4), 0.6, 0.45, 0.55, rcol.darkened(0.1), 0.25)
			_mk("%s_%d" % [rname, v + 1], bush_r + 20.0, 96.0)
	_snow_cap = false

	# --- flower patches
	var fcols := [Color(0.95, 0.45, 0.65), Color(1.0, 0.85, 0.25), Color(0.96, 0.96, 0.96), Color(0.68, 0.42, 0.92)]
	for v in range(4):
		_mb_begin(0.8)
		var fc: Color = fcols[v]
		for k in range(3):
			var ang := TAU * float(k) / 3.0 + _mrng.randf()
			var base := Vector3(cos(ang) * 0.35, 0.0, sin(ang) * 0.35)
			var hgt := 0.45 + _mrng.randf() * 0.2
			_limb(base + Vector3(0.0, -0.1, 0.0), base + Vector3(0.0, hgt, 0.0), 0.025, 0.02, 3, Color(0.25, 0.5, 0.2))
			_blob(base + Vector3(0.0, hgt + 0.04, 0.0), 0.13, 0.09, 0.13, fc, 0.15)
		_mk("flower_%d" % (v + 1), small_r, 48.0)

	# --- mushroom
	_mb_begin(0.5)
	_limb(Vector3(0.0, -0.1, 0.0), Vector3(0.0, 0.25, 0.0), 0.06, 0.05, 4, Color(0.92, 0.9, 0.82))
	_blob(Vector3(0.0, 0.3, 0.0), 0.22, 0.13, 0.22, Color(0.85, 0.2, 0.2), 0.08)
	_mk("mush_1", small_r, 48.0)

	# --- tree stump (left behind when a tree is felled)
	_mb_begin(1.0)
	_limb(Vector3(0.0, -0.4, 0.0), Vector3(0.0, 0.45, 0.0), 0.36, 0.28, 7, trunk)
	for si in range(7):
		var sa0 := TAU * float(si) / 7.0
		var sa1 := TAU * float(si + 1) / 7.0
		_tri(Vector3(0.0, 0.45, 0.0), Vector3(cos(sa0) * 0.28, 0.45, sin(sa0) * 0.28), Vector3(cos(sa1) * 0.28, 0.45, sin(sa1) * 0.28), Color(0.74, 0.57, 0.36), Vector3(0.0, 0.0, 0.0))
	_mk("stump", small_r, 48.0)

	# --- ground pickups: a loose stone and a stick (a bit brighter so they are easy to spot)
	_mb_begin(1.0)
	_blob(Vector3(0.0, 0.12, 0.0), 0.2, 0.13, 0.17, Color(0.66, 0.67, 0.72), 0.22)
	_blob(Vector3(0.2, 0.07, 0.1), 0.1, 0.07, 0.09, Color(0.58, 0.59, 0.64), 0.2)
	_mk("pk_stone", small_r, 48.0)
	_mb_begin(1.0)
	_limb(Vector3(-0.5, 0.05, 0.0), Vector3(0.5, 0.08, 0.1), 0.038, 0.032, 4, Color(0.62, 0.43, 0.22))
	_limb(Vector3(-0.2, 0.05, -0.16), Vector3(0.3, 0.07, -0.3), 0.028, 0.022, 4, Color(0.55, 0.38, 0.2))
	_mk("pk_stick", small_r, 48.0)

	# --- grass tufts
	for gv in range(2):
		_mb_begin(1.0)
		var c_base := Color(0.22, 0.45, 0.15)
		var c_tip := Color(0.58, 0.80, 0.32)
		if gv == 1:
			c_base = Color(0.12, 0.28, 0.12)
			c_tip = Color(0.30, 0.52, 0.22)
		for k in range(4):
			var ang := TAU * float(k) / 4.0 + _mrng.randf() * 0.6
			var dirv := Vector3(cos(ang), 0.0, sin(ang))
			var tang := Vector3(-dirv.z, 0.0, dirv.x)
			var root := dirv * 0.1
			var hgt := 0.55 + _mrng.randf() * 0.3
			_blade(root - tang * 0.07, root + tang * 0.07, root + dirv * 0.18 + Vector3(0.0, hgt, 0.0), c_base, c_tip)
		_mk("grass_%d" % (gv + 1), grass_r, 48.0)


# ------------------------------------------------------------------ placement helpers

func _xf(x: float, y: float, z: float, s: float, yaw: float) -> Transform3D:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
	return Transform3D(b, Vector3(x, y, z))


func _add_inst(key: String, t: Transform3D, ent_id: int = -1) -> void:
	if not meshes.has(key):
		return
	var info: Dictionary = meshes[key]
	var cs: float = info["cs"]
	var cid := int(floor((t.origin.x + half_size) / cs)) + 1000 * int(floor((t.origin.z + half_size) / cs))
	if not inst.has(key):
		inst[key] = {}
		inst_ent[key] = {}
	var d: Dictionary = inst[key]
	var ed: Dictionary = inst_ent[key]
	if not d.has(cid):
		d[cid] = []
		ed[cid] = []
	var arr: Array = d[cid]
	arr.append(t)
	var ea: Array = ed[cid]
	ea.append(ent_id)


func _add_obstacle(x: float, z: float, r: float) -> void:
	var key := int(floor((x + 400.0) / OBST_CELL)) * 4096 + int(floor((z + 400.0) / OBST_CELL))
	if not obstacles.has(key):
		obstacles[key] = []
	var a: Array = obstacles[key]
	a.append(x)
	a.append(z)
	a.append(r)


## Pushes a point out of trees/rocks (circle colliders). Used by the player.
func push_out(p: Vector3, r: float) -> Vector3:
	var cx := int(floor((p.x + 400.0) / OBST_CELL))
	var cz := int(floor((p.z + 400.0) / OBST_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := (cx + dx) * 4096 + (cz + dz)
			if not obstacles.has(key):
				continue
			var arr: Array = obstacles[key]
			for i in range(0, arr.size(), 3):
				var ox: float = p.x - float(arr[i])
				var oz: float = p.z - float(arr[i + 1])
				var rr: float = r + float(arr[i + 2])
				var d2 := ox * ox + oz * oz
				if d2 < rr * rr and d2 > 0.000001:
					var d := sqrt(d2)
					var k := (rr - d) / d
					p.x += ox * k
					p.z += oz * k
	return p


## Climbable boulders: each rock is an ellipsoid dome the player can stand on.
func _add_rock(x: float, z: float, terrain_y: float, sc: float) -> void:
	var key := int(floor((x + 400.0) / OBST_CELL)) * 4096 + int(floor((z + 400.0) / OBST_CELL))
	if not rocks.has(key):
		rocks[key] = []
	var a: Array = rocks[key]
	a.append(x)
	a.append(z)
	a.append(1.05 * sc)
	a.append(terrain_y + 0.2 * sc)
	a.append(0.8 * sc)


## Terrain height, or the top of a rock if the point is on one.
func ground_at(x: float, z: float) -> float:
	var g := height_at(x, z)
	var cx := int(floor((x + 400.0) / OBST_CELL))
	var cz := int(floor((z + 400.0) / OBST_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := (cx + dx) * 4096 + (cz + dz)
			if not rocks.has(key):
				continue
			var arr: Array = rocks[key]
			for i in range(0, arr.size(), 5):
				var ox: float = x - float(arr[i])
				var oz: float = z - float(arr[i + 1])
				var rx: float = arr[i + 2]
				var d2 := ox * ox + oz * oz
				if d2 < rx * rx:
					var y: float = float(arr[i + 3]) + float(arr[i + 4]) * sqrt(1.0 - d2 / (rx * rx))
					if y > g:
						g = y
	return g


## Soft contact shadow baked into the terrain colours (no real shadows needed).
func _ao_spot(x: float, z: float, r: float, strength: float) -> void:
	var cx := int(round((x + half_size) / CELL))
	var cz := int(round((z + half_size) / CELL))
	var rc := int(ceil(r / CELL)) + 1
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var gx := cx + dx
			var gz := cz + dz
			if gx < 0 or gz < 0 or gx > N or gz > N:
				continue
			var d := Vector2(gx * CELL - half_size - x, gz * CELL - half_size - z).length()
			if d >= r:
				continue
			var f := 1.0 - d / r
			var m := 1.0 - strength * f
			var k := gz * W + gx
			var c := colors[k]
			colors[k] = Color(c.r * m, c.g * m, c.b * m, 1.0)



func _trunk_radius(key: String) -> float:
	if key.begins_with("cactus"):
		return 0.55
	if key.begins_with("pine") or key.begins_with("snowpine"):
		return 0.4
	return 0.45


# ------------------------------------------------------------------ scatter

func _scatter_trees() -> void:
	var sp := 4.6
	var n := int(MAP_SIZE / sp)
	for gz in range(n):
		if gz % 14 == 0:
			await _yield(0.58 + 0.08 * float(gz) / float(n), "Growing forests...")
		for gx in range(n):
			var x := -half_size + (float(gx) + rng.randf()) * sp
			var z := -half_size + (float(gz) + rng.randf()) * sp
			var i := _idx(x, z)
			var h := height_at(x, z)
			if h < 1.1 or normals[i].y < 0.8 or path_mask[i] > 0.08:
				continue
			var b := _pick(i)
			var d: float = float(TREE_DENS[b]) * density_mul
			if d <= 0.0:
				continue
			var vm := n_forest.get_noise_2d(x, z) * 0.5 + 0.5
			if b == Biome.MEADOW:
				d = (0.02 + 0.75 * smoothstep(0.6, 0.78, vm)) * density_mul
			else:
				d *= clampf(0.3 + vm * 1.4, 0.0, 1.7)
			var treeline := 48.0
			if b == Biome.TAIGA or b == Biome.SNOW:
				treeline = 32.0
			if h > treeline or rng.randf() > d:
				continue

			var r := rng.randf()
			var key := ""
			var sc := 1.0
			if b == Biome.MEADOW:
				key = "meadow_%d" % (1 + rng.randi() % 2)
				sc = rng.randf_range(0.9, 1.4)
			elif b == Biome.FOREST:
				key = "oak_%d" % (1 + rng.randi() % 3)
				sc = rng.randf_range(0.9, 1.5)
			elif b == Biome.JUNGLE:
				key = "jungle_%d" % (1 + rng.randi() % 3)
				sc = rng.randf_range(1.0, 1.6)
			elif b == Biome.DARK:
				if r < 0.45:
					key = "dead_%d" % (1 + rng.randi() % 2)
					sc = rng.randf_range(0.9, 1.3)
				else:
					key = "dark_%d" % (1 + rng.randi() % 2)
					sc = rng.randf_range(0.9, 1.4)
			elif b == Biome.DESERT:
				if r < 0.7:
					key = "cactus_%d" % (1 + rng.randi() % 2)
					sc = rng.randf_range(0.8, 1.4)
				else:
					key = "dead_%d" % (1 + rng.randi() % 2)
					sc = rng.randf_range(0.8, 1.1)
			elif b == Biome.TAIGA:
				key = "pine_%d" % (1 + rng.randi() % 3)
				sc = rng.randf_range(1.0, 1.7)
			else:
				key = "snowpine_%d" % (1 + rng.randi() % 2)
				sc = rng.randf_range(1.0, 1.6)

			_place_tree(key, x, z, h, sc)


func _scatter_bushes() -> void:
	var sp := 6.5
	var n := int(MAP_SIZE / sp)
	for gz in range(n):
		if gz % 20 == 0:
			await _yield(0.66 + 0.03 * float(gz) / float(n), "Planting bushes...")
		for gx in range(n):
			var x := -half_size + (float(gx) + rng.randf()) * sp
			var z := -half_size + (float(gz) + rng.randf()) * sp
			var i := _idx(x, z)
			var h := height_at(x, z)
			if h < 1.2 or h > 40.0 or normals[i].y < 0.8 or path_mask[i] > 0.08:
				continue
			var b := _pick(i)
			var d: float = float(BUSH_DENS[b]) * density_mul
			if d <= 0.0 or rng.randf() > d:
				continue
			var key := "bush_%d" % (1 + rng.randi() % 2)
			if b == Biome.DARK:
				key = "bush_dark_1"
			var bsc := rng.randf_range(0.9, 1.6)
			var bxf := _xf(x, h - 0.05, z, bsc, rng.randf() * TAU)
			var beid := _reg_ent("bush", key, x, z, bxf, bsc, 0.0)
			_add_inst(key, bxf, beid)
			_ao_spot(x, z, 2.4, 0.2)


func _scatter_grass() -> void:
	var sp := 2.4
	var n := int(MAP_SIZE / sp)
	for gz in range(n):
		if gz % 14 == 0:
			await _yield(0.69 + 0.1 * float(gz) / float(n), "Growing grass...")
		for gx in range(n):
			var x := -half_size + (float(gx) + rng.randf()) * sp
			var z := -half_size + (float(gz) + rng.randf()) * sp
			var i := _idx(x, z)
			var h := height_at(x, z)
			if h < 0.9 or h > 36.0 or normals[i].y < 0.8 or path_mask[i] > 0.1:
				continue
			var b := _pick(i)
			var d: float = float(GRASS_DENS[b]) * density_mul
			if d <= 0.0:
				continue
			d *= 0.55 + 0.9 * (n_patch.get_noise_2d(x, z) * 0.5 + 0.5)
			if rng.randf() > d:
				continue
			var key := "grass_1"
			if b == Biome.DARK or b == Biome.TAIGA or b == Biome.JUNGLE:
				key = "grass_2"
			_add_inst(key, _xf(x, h - 0.02, z, rng.randf_range(0.8, 1.5), rng.randf() * TAU))


func _scatter_flowers() -> void:
	var sp := 3.0
	var n := int(MAP_SIZE / sp)
	for gz in range(n):
		if gz % 20 == 0:
			await _yield(0.79 + 0.03 * float(gz) / float(n), "Sprinkling flowers...")
		for gx in range(n):
			var x := -half_size + (float(gx) + rng.randf()) * sp
			var z := -half_size + (float(gz) + rng.randf()) * sp
			var i := _idx(x, z)
			var h := height_at(x, z)
			if h < 1.0 or h > 30.0 or normals[i].y < 0.8 or path_mask[i] > 0.1:
				continue
			var b := _pick(i)
			var d: float = float(FLOWER_DENS[b]) * density_mul
			if d <= 0.0:
				continue
			var patch := smoothstep(0.52, 0.72, n_flower.get_noise_2d(x, z) * 0.5 + 0.5)
			d *= patch * 2.4
			if rng.randf() > d:
				continue
			var key := "flower_%d" % (1 + rng.randi() % 4)
			_add_inst(key, _xf(x, h - 0.02, z, rng.randf_range(0.9, 1.5), rng.randf() * TAU))


func _scatter_mushrooms() -> void:
	var sp := 5.0
	var n := int(MAP_SIZE / sp)
	for gz in range(n):
		if gz % 25 == 0:
			await _yield(0.82 + 0.02 * float(gz) / float(n), "Hiding mushrooms...")
		for gx in range(n):
			var x := -half_size + (float(gx) + rng.randf()) * sp
			var z := -half_size + (float(gz) + rng.randf()) * sp
			var i := _idx(x, z)
			var h := height_at(x, z)
			if h < 1.2 or h > 30.0 or normals[i].y < 0.8 or path_mask[i] > 0.1:
				continue
			var b := _pick(i)
			var d: float = float(MUSH_DENS[b]) * density_mul
			if d <= 0.0 or rng.randf() > d:
				continue
			var count := 1 + rng.randi() % 3
			for m in range(count):
				var ox := x + rng.randf_range(-0.8, 0.8)
				var oz := z + rng.randf_range(-0.8, 0.8)
				_add_inst("mush_1", _xf(ox, height_at(ox, oz) - 0.02, oz, rng.randf_range(0.9, 1.8), rng.randf() * TAU))


func _scatter_rocks() -> void:
	var sp := 11.0
	var n := int(MAP_SIZE / sp)
	for gz in range(n):
		if gz % 10 == 0:
			await _yield(0.84 + 0.03 * float(gz) / float(n), "Placing rocks...")
		for gx in range(n):
			var x := -half_size + (float(gx) + rng.randf()) * sp
			var z := -half_size + (float(gz) + rng.randf()) * sp
			var i := _idx(x, z)
			var h := height_at(x, z)
			if h < 1.0 or path_mask[i] > 0.1:
				continue
			var b := _pick(i)
			var d: float = float(ROCK_DENS[b]) * density_mul
			if normals[i].y < 0.8:
				d *= 3.0
			if d <= 0.0 or rng.randf() > d:
				continue
			var cluster := 1
			if b == Biome.DESERT or b == Biome.SNOW or b == Biome.TAIGA:
				cluster = 1 + rng.randi() % 3
			for c in range(cluster):
				var ox := x
				var oz := z
				var sc := rng.randf_range(0.7, 1.8)
				if b == Biome.SNOW:
					sc = rng.randf_range(1.0, 2.6)
				if c > 0:
					ox += rng.randf_range(-4.0, 4.0)
					oz += rng.randf_range(-4.0, 4.0)
					sc *= 0.6
				var ri := _idx(ox, oz)
				if heights[ri] < 0.8:
					continue
				var key := "rock_%d" % (1 + rng.randi() % 3)
				if b == Biome.DESERT:
					key = "rockdesert_%d" % (1 + rng.randi() % 2)
				elif b == Biome.SNOW:
					key = "rocksnow_%d" % (1 + rng.randi() % 2)
				_place_rock(key, ox, oz, sc)


# ------------------------------------------------------------------ harvestable entities
# Trees, rocks, bushes and loose sticks/stones are registered as entities. They are
# still drawn by the fast MultiMeshes, until the player touches one: then it is
# "detached" into its own node so it can shake, fall, shrink or vanish.

func _ek(x: float, z: float) -> int:
	return int(floor((x + 400.0) / OBST_CELL)) * 4096 + int(floor((z + 400.0) / OBST_CELL))


func _reg_ent(kind: String, key: String, x: float, z: float, xf: Transform3D, sc: float, r: float) -> int:
	var hp := 0.0
	var rad := r
	if kind == "tree":
		hp = roundf(4.0 + sc * 1.6)
		if key.begins_with("dead"):
			hp = maxf(3.0, hp - 2.0)
	elif kind == "rock":
		hp = 3.0 + floorf(sc * 1.6)
		rad = 0.9 * sc
	elif kind == "bush":
		hp = 1.0
		rad = 0.7 * sc
	var e := {
		"kind": kind, "key": key, "x": x, "z": z, "y": xf.origin.y, "xf": xf,
		"sc": sc, "r": rad, "hp": hp, "max_hp": hp, "alive": true,
		"node": null, "mm": null, "idx": -1, "tw": null, "item": "",
	}
	var id := ents.size()
	ents.append(e)
	var ck := _ek(x, z)
	if not ent_grid.has(ck):
		ent_grid[ck] = []
	var lst: Array = ent_grid[ck]
	lst.append(id)
	return id


func _place_tree(key: String, x: float, z: float, h: float, sc: float) -> void:
	var xf := _xf(x, h - 0.05, z, sc, rng.randf() * TAU)
	var eid := -1
	if not key.begins_with("cactus"):
		eid = _reg_ent("tree", key, x, z, xf, sc, _trunk_radius(key) * sc)
	_add_inst(key, xf, eid)
	_add_obstacle(x, z, _trunk_radius(key) * sc)
	_ao_spot(x, z, 3.8 * sc, 0.30)


func _place_rock(key: String, ox: float, oz: float, sc: float) -> void:
	var gy := height_at(ox, oz)
	var xf := _xf(ox, gy - 0.25 * sc, oz, sc, rng.randf() * TAU)
	var eid := _reg_ent("rock", key, ox, oz, xf, sc, 0.0)
	_add_inst(key, xf, eid)
	_add_rock(ox, oz, gy, sc)
	_ao_spot(ox, oz, 2.8 * sc, 0.32)


func _place_pickup(item: String, x: float, z: float) -> void:
	var key := "pk_stick"
	if item == "stone":
		key = "pk_stone"
	var sc := rng.randf_range(1.2, 1.8)
	var xf := _xf(x, height_at(x, z) - 0.01, z, sc, rng.randf() * TAU)
	var eid := _reg_ent("pickup", key, x, z, xf, sc, 0.0)
	var e: Dictionary = ents[eid]
	e["item"] = item
	_add_inst(key, xf, eid)


func _scatter_pickups() -> void:
	var sp := 3.6
	var n := int(MAP_SIZE / sp)
	for gz in range(n):
		if gz % 20 == 0:
			await _yield(0.87, "Scattering sticks and stones...")
		for gx in range(n):
			var x := -half_size + (float(gx) + rng.randf()) * sp
			var z := -half_size + (float(gz) + rng.randf()) * sp
			var i := _idx(x, z)
			var h := height_at(x, z)
			if h < 1.2 or h > 44.0 or normals[i].y < 0.78 or path_mask[i] > 0.1:
				continue
			var b := _pick(i)
			if rng.randf() < float(STICK_DENS[b]) * density_mul:
				_place_pickup("stick", x, z)
			elif rng.randf() < float(STONE_DENS[b]) * density_mul:
				_place_pickup("stone", x, z)


## A little "starter camp" around the spawn point so a new player can craft a first axe
## right away: loose sticks and stones, a few trees and a couple of rocks.
func _scatter_starter() -> void:
	var r2 := RandomNumberGenerator.new()
	r2.seed = SEED + 5
	var hubv := Vector2(spawn_pos.x, spawn_pos.z)
	var todo: Array = ["tree", "tree", "tree", "rock", "rock"]
	for k in range(10):
		todo.append("stick")
	for k in range(9):
		todo.append("stone")
	for what in todo:
		var dmin := 3.0
		var dmax := 14.0
		if what == "tree":
			dmin = 9.0
			dmax = 20.0
		elif what == "rock":
			dmin = 8.0
			dmax = 18.0
		for attempt in range(40):
			var ang := r2.randf() * TAU
			var dist := r2.randf_range(dmin, dmax)
			var p := hubv + Vector2(cos(ang), sin(ang)) * dist
			var i := _idx(p.x, p.y)
			var h := height_at(p.x, p.y)
			if h < 1.4 or normals[i].y < 0.9 or path_mask[i] > 0.1:
				continue
			if what == "tree":
				_place_tree("meadow_%d" % (1 + r2.randi() % 2), p.x, p.y, h, r2.randf_range(1.0, 1.3))
			elif what == "rock":
				_place_rock("rock_%d" % (1 + r2.randi() % 3), p.x, p.y, r2.randf_range(0.9, 1.4))
			else:
				_place_pickup(what, p.x, p.y)
			break


func _remove_obstacle(x: float, z: float) -> void:
	var key := _ek(x, z)
	if not obstacles.has(key):
		return
	var arr: Array = obstacles[key]
	for i in range(0, arr.size(), 3):
		if absf(float(arr[i]) - x) < 0.001 and absf(float(arr[i + 1]) - z) < 0.001:
			arr.remove_at(i + 2)
			arr.remove_at(i + 1)
			arr.remove_at(i)
			return


func _remove_rock(x: float, z: float) -> void:
	var key := _ek(x, z)
	if not rocks.has(key):
		return
	var arr: Array = rocks[key]
	for i in range(0, arr.size(), 5):
		if absf(float(arr[i]) - x) < 0.001 and absf(float(arr[i + 1]) - z) < 0.001:
			for k in range(4, -1, -1):
				arr.remove_at(i + k)
			return


func biome_name_at(x: float, z: float) -> String:
	return BIOME_NAMES[biome1[_idx(x, z)]]


## Nearest living entity of one of `kinds` in front of the player (fwd is a unit vector in
## the XZ plane). `reach` is measured to the surface of the thing, `cone` is the minimum
## dot product with the facing direction (use -1 for "any direction").
func find_target(p: Vector3, fwd: Vector2, reach: float, kinds: Array, cone: float) -> int:
	var best := -1
	var best_score := 1.0e9
	var cx := int(floor((p.x + 400.0) / OBST_CELL))
	var cz := int(floor((p.z + 400.0) / OBST_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := (cx + dx) * 4096 + (cz + dz)
			if not ent_grid.has(key):
				continue
			var lst: Array = ent_grid[key]
			for eid in lst:
				var e: Dictionary = ents[eid]
				if not e["alive"]:
					continue
				if not kinds.has(e["kind"]):
					continue
				var ox: float = float(e["x"]) - p.x
				var oz: float = float(e["z"]) - p.z
				var d := sqrt(ox * ox + oz * oz)
				var edge := d - float(e["r"])
				if edge > reach:
					continue
				var facing := 1.0
				if d > 0.001:
					facing = (ox * fwd.x + oz * fwd.y) / d
				if d > 1.2 and facing < cone:
					continue
				var score := edge - facing * 1.5
				if score < best_score:
					best_score = score
					best = eid
	return best


func _hide_mm(e: Dictionary) -> void:
	var mm: Variant = e["mm"]
	var idx: int = e["idx"]
	if mm != null and idx >= 0:
		var hidden := Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0.0, -300.0, 0.0))
		(mm as MultiMesh).set_instance_transform(idx, hidden)


## Moves an entity out of its MultiMesh into a standalone node (a pivot at its base).
func _detach(e: Dictionary) -> Node3D:
	var existing: Variant = e["node"]
	if existing != null:
		return existing as Node3D
	var info: Dictionary = meshes[e["key"]]
	var xf: Transform3D = e["xf"]
	var pivot := Node3D.new()
	pivot.position = xf.origin
	var mi := MeshInstance3D.new()
	mi.mesh = info["mesh"]
	mi.material_override = prop_mat
	mi.basis = xf.basis
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	add_child(pivot)
	_hide_mm(e)
	e["node"] = pivot
	return pivot


func _kill_tween(e: Dictionary) -> void:
	var old: Variant = e["tw"]
	if old != null:
		(old as Tween).kill()
	e["tw"] = null


func _leaf_color(key: String) -> Color:
	if key.begins_with("dead"):
		return Color(0.46, 0.39, 0.33)
	if key.begins_with("snowpine"):
		return Color(0.85, 0.92, 0.95)
	if key.begins_with("pine"):
		return Color(0.14, 0.38, 0.22)
	if key.begins_with("jungle"):
		return Color(0.12, 0.52, 0.25)
	if key.begins_with("meadow"):
		return Color(0.48, 0.72, 0.25)
	if key.begins_with("dark"):
		return Color(0.20, 0.35, 0.21)
	return Color(0.30, 0.58, 0.20)


## Applies one hit. Returns {"broke": bool, "drops": {item: count}}.
func hit_entity(eid: int, dmg: float, from: Vector3) -> Dictionary:
	var e: Dictionary = ents[eid]
	var res := {"broke": false, "drops": {}}
	if not e["alive"]:
		return res
	var kind: String = e["kind"]
	if kind == "tree":
		_hit_tree(e, dmg, from, res)
	elif kind == "rock":
		_hit_rock(e, dmg, from, res)
	elif kind == "bush":
		_hit_bush(e, res)
	return res


func collect_pickup(eid: int) -> Dictionary:
	var e: Dictionary = ents[eid]
	var drops := {}
	if not e["alive"]:
		return drops
	e["alive"] = false
	_hide_mm(e)
	var item: String = e["item"]
	drops[item] = 1
	if item == "stick" and randf() < 0.4:
		drops[item] = 2
	var ex: float = e["x"]
	var ey: float = e["y"]
	var ez: float = e["z"]
	var col := Color(0.6, 0.45, 0.28)
	if item == "stone":
		col = Color(0.65, 0.66, 0.7)
	_burst(Vector3(ex, ey + 0.2, ez), col, 5, 1.8, 0.05, 0.4, 6.0)
	return drops


# ---- trees

func _hit_tree(e: Dictionary, dmg: float, from: Vector3, res: Dictionary) -> void:
	var pivot := _detach(e)
	var ex: float = e["x"]
	var ez: float = e["z"]
	var ey: float = e["y"]
	var dirv := Vector2(ex - from.x, ez - from.z)
	if dirv.length() < 0.01:
		dirv = Vector2(1.0, 0.0)
	dirv = dirv.normalized()
	e["hp"] = float(e["hp"]) - dmg
	# wood chips fly from the spot where the axe bites (the side facing the player)
	_burst(Vector3(ex - dirv.x * 0.45, ey + 1.2, ez - dirv.y * 0.45), Color(0.74, 0.54, 0.32), 9, 3.5, 0.09, 0.55)
	var drops: Dictionary = res["drops"]
	if randf() < 0.35:
		drops["stick"] = 1
	if float(e["hp"]) > 0.0:
		_kill_tween(e)
		var axis := Vector3(dirv.y, 0.0, -dirv.x)
		var tw := create_tween()
		e["tw"] = tw
		tw.tween_method(_shake_step.bind(pivot, axis), 0.0, 1.0, 0.4)
	else:
		_fell_tree(e, pivot, dirv, res)


func _shake_step(t: float, pivot: Node3D, axis: Vector3) -> void:
	if is_instance_valid(pivot):
		pivot.basis = Basis(axis, sin(t * 30.0) * 0.05 * (1.0 - t))


func _fell_tree(e: Dictionary, pivot: Node3D, dirv: Vector2, res: Dictionary) -> void:
	e["alive"] = false
	res["broke"] = true
	_kill_tween(e)
	var ex: float = e["x"]
	var ez: float = e["z"]
	var sc: float = e["sc"]
	_remove_obstacle(ex, ez)
	pivot.basis = Basis()

	var drops: Dictionary = res["drops"]
	drops["wood"] = 3 + int(sc * 2.0)
	drops["stick"] = int(drops.get("stick", 0)) + 1 + randi() % 2

	# a stump stays behind
	var st := MeshInstance3D.new()
	var sinfo: Dictionary = meshes["stump"]
	st.mesh = sinfo["mesh"]
	st.material_override = prop_mat
	st.position = Vector3(ex, height_at(ex, ez), ez)
	st.scale = Vector3.ONE * sc * 0.9
	st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(st)
	_add_obstacle(ex, ez, 0.32 * sc)

	# fall away from the player, bounce once, lie there, then shrink away
	var axis := Vector3(dirv.y, 0.0, -dirv.x)
	var tw := create_tween()
	e["tw"] = tw
	tw.tween_method(_fall_step.bind(e, pivot, axis), 0.0, 1.0, TREE_FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_tree_landed.bind(e, dirv))
	tw.tween_method(_bounce_step.bind(pivot, axis), 0.0, 1.0, 0.24)
	tw.tween_interval(TREE_VANISH_DELAY)
	tw.tween_callback(_vanish_node.bind(pivot))


func _fall_step(t: float, e: Dictionary, pivot: Node3D, axis: Vector3) -> void:
	if not is_instance_valid(pivot):
		return
	var sc: float = e["sc"]
	pivot.basis = Basis(axis, t * 1.5)
	pivot.position.y = float(e["y"]) + 0.3 * sc * t


func _bounce_step(t: float, pivot: Node3D, axis: Vector3) -> void:
	if is_instance_valid(pivot):
		pivot.basis = Basis(axis, 1.5 - 0.1 * sin(PI * t))


func _tree_landed(e: Dictionary, dirv: Vector2) -> void:
	var sc: float = e["sc"]
	var key: String = e["key"]
	var ex: float = e["x"]
	var ez: float = e["z"]
	var tip := Vector3(ex + dirv.x * 3.4 * sc, height_at(ex + dirv.x * 3.4 * sc, ez + dirv.y * 3.4 * sc) + 0.6, ez + dirv.y * 3.4 * sc)
	_burst(tip, _leaf_color(key), 24, 4.5, 0.16, 1.1, 9.0)
	_burst(tip, Color(0.76, 0.7, 0.6), 10, 2.6, 0.26, 0.9, 2.0)
	sfx.emit("crash", tip)


func _vanish_node(pivot: Node3D) -> void:
	if not is_instance_valid(pivot):
		return
	var mi := pivot.get_child(0) as Node3D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.02, 0.02, 0.02), 1.5).set_ease(Tween.EASE_IN)
	tw.tween_property(pivot, "position:y", pivot.position.y - 1.0, 1.5)
	tw.chain().tween_callback(pivot.queue_free)


# ---- rocks

func _hit_rock(e: Dictionary, dmg: float, from: Vector3, res: Dictionary) -> void:
	var pivot := _detach(e)
	var sc: float = e["sc"]
	var ex: float = e["x"]
	var ez: float = e["z"]
	var ey: float = e["y"]
	var dirv := Vector2(from.x - ex, from.z - ez)
	if dirv.length() < 0.01:
		dirv = Vector2(1.0, 0.0)
	dirv = dirv.normalized()
	e["hp"] = float(e["hp"]) - dmg
	_burst(Vector3(ex + dirv.x * 0.9 * sc, ey + 0.7 * sc, ez + dirv.y * 0.9 * sc), Color(0.72, 0.72, 0.78), 8, 4.0, 0.07, 0.45)
	var drops: Dictionary = res["drops"]
	drops["stone"] = 1
	if float(e["hp"]) > 0.0:
		# the rock visibly shrinks as it gets chipped away
		var frac := clampf(float(e["hp"]) / float(e["max_hp"]), 0.0, 1.0)
		var f := lerpf(0.55, 1.0, frac)
		pivot.scale = Vector3.ONE * f * 1.07
		_kill_tween(e)
		var tw := create_tween()
		e["tw"] = tw
		tw.tween_property(pivot, "scale", Vector3.ONE * f, 0.14)
	else:
		e["alive"] = false
		res["broke"] = true
		_kill_tween(e)
		_remove_rock(ex, ez)
		drops["stone"] = 3 + int(sc * 1.5)
		_burst(Vector3(ex, ey + 0.8 * sc, ez), Color(0.62, 0.62, 0.67), 22, 5.0, 0.13, 0.85)
		sfx.emit("rockbreak", Vector3(ex, ey + 0.5, ez))
		var tw2 := create_tween()
		tw2.tween_property(pivot, "scale", Vector3(0.05, 0.05, 0.05), 0.2).set_ease(Tween.EASE_IN)
		tw2.tween_callback(pivot.queue_free)


# ---- bushes

func _hit_bush(e: Dictionary, res: Dictionary) -> void:
	var pivot := _detach(e)
	e["alive"] = false
	res["broke"] = true
	var ex: float = e["x"]
	var ez: float = e["z"]
	var ey: float = e["y"]
	var drops: Dictionary = res["drops"]
	drops["stick"] = 1 + randi() % 2
	_burst(Vector3(ex, ey + 0.7, ez), Color(0.32, 0.58, 0.22), 14, 3.5, 0.12, 0.7, 10.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pivot, "scale", Vector3(0.05, 0.05, 0.05), 0.28).set_ease(Tween.EASE_IN)
	tw.tween_property(pivot, "rotation:y", 0.8, 0.28)
	tw.chain().tween_callback(pivot.queue_free)


# ---- particles

func _burst(pos: Vector3, col: Color, amount: int, spd: float, size: float, life: float, grav: float = 14.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = spd * 0.5
	p.initial_velocity_max = spd
	p.gravity = Vector3(0.0, -grav, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	bm.material = m
	p.mesh = bm
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)


# ------------------------------------------------------------------ minimap

## Top-down colour map of the whole island (2 m per pixel) with simple hill shading.
func _build_minimap() -> void:
	var img := Image.create(MM_RES, MM_RES, false, Image.FORMAT_RGB8)
	var step := MAP_SIZE / float(MM_RES)
	var light := Vector3(-0.5, 0.8, -0.35).normalized()
	for py in range(MM_RES):
		if py % 32 == 0:
			await _yield(0.955 + 0.015 * float(py) / float(MM_RES), "Drawing the map...")
		var z := -half_size + (float(py) + 0.5) * step
		for px in range(MM_RES):
			var x := -half_size + (float(px) + 0.5) * step
			var h := height_at(x, z)
			var c := Color(0, 0, 0)
			if h < -0.15:
				var dd := clampf(-h / 8.0, 0.0, 1.0)
				c = Color(0.35, 0.72, 0.78).lerp(Color(0.05, 0.2, 0.4), dd)
			else:
				var i := _idx(x, z)
				c = colors[i].linear_to_srgb()
				var sh := clampf(1.0 + 1.6 * (normals[i].dot(light) - 0.8), 0.6, 1.4)
				c = Color(clampf(c.r * sh, 0.0, 1.0), clampf(c.g * sh, 0.0, 1.0), clampf(c.b * sh, 0.0, 1.0))
			img.set_pixel(px, py, c)
	minimap_tex = ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ multimeshes

func _build_multimeshes() -> void:
	var keys := inst.keys()
	var ki := 0
	for key in keys:
		ki += 1
		if ki % 4 == 0:
			await _yield(0.88 + 0.09 * float(ki) / float(keys.size()), "Placing nature...")
		var info: Dictionary = meshes[key]
		var per_chunk: Dictionary = inst[key]
		var cs: float = info["cs"]
		var is_big: bool = cs > 90.0
		for cid in per_chunk.keys():
			var arr: Array = per_chunk[cid]
			var ea: Array = []
			if inst_ent.has(key):
				var ed: Dictionary = inst_ent[key]
				if ed.has(cid):
					ea = ed[cid]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = info["mesh"]
			mm.instance_count = arr.size()
			for ii in range(arr.size()):
				mm.set_instance_transform(ii, arr[ii])
				var eid: int = -1
				if ii < ea.size():
					eid = ea[ii]
				if eid >= 0:
					var ent: Dictionary = ents[eid]
					ent["mm"] = mm
					ent["idx"] = ii
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = prop_mat
			mmi.visibility_range_end = float(info["range"]) + cs * 0.5
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
	inst.clear()
	inst_ent.clear()


# ------------------------------------------------------------------ water

func _build_water() -> void:
	var himg := Image.create_from_data(W, W, false, Image.FORMAT_RF, heights.to_byte_array())
	himg.convert(Image.FORMAT_RH)
	var htex := ImageTexture.create_from_image(himg)

	var sh := Shader.new()
	sh.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("height_tex", htex)
	mat.set_shader_parameter("map_size", MAP_SIZE)
	mat.set_shader_parameter("water_y", water_y)
	mat.set_shader_parameter("tex_k", float(N) / float(W))
	mat.set_shader_parameter("tex_off", 0.5 / float(W))

	var pm := PlaneMesh.new()
	pm.size = Vector2(6000.0, 6000.0)
	var water := MeshInstance3D.new()
	water.mesh = pm
	water.material_override = mat
	water.position = Vector3(0.0, water_y, 0.0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	# Deep ocean floor so the horizon never shows the sky through the water
	var fm := PlaneMesh.new()
	fm.size = Vector2(7000.0, 7000.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.02, 0.10, 0.18)
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = fm
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0.0, -14.0, 0.0)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mi)
