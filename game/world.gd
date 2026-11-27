extends Node3D
## The 3D world: an endless road built in chunks around the rider from the
## simulation's terrain, with biome landscapes, scenery, shops, sky and
## a day-night cycle.
##
## Coordinates: x runs along the route (metres, minus a floating origin so
## numbers stay small over 4,000 km), y is height, z is sideways.

const Materials := preload("res://game/materials.gd")
const Props := preload("res://game/props.gd")

const CHUNK_M := 200.0
const ROW_STEP_M := 4.0
const AHEAD_M := 1400.0
const BEHIND_M := 300.0
const REBASE_M := 2000.0
const ROAD_HALF := 3.5
const LANE_Z := 1.6
const SIDE_COLS := [3.5, 4.6, 7.0, 11.0, 17.0, 26.0, 38.0, 55.0, 80.0, 115.0, 165.0, 240.0]

## How each biome looks. Numbers are visual only; the simulation's terrain
## decides the road's height.
const VIS := {
	"fields": {
		"side_amp": 6.0, "valley": 0.0,
		"ground": [Color("6fae45"), Color("86bb4c"), Color("d1ab3e"), Color("9c7a45")],
		"patch_m": Vector2(70, 45),
		"props": {"tree_round": 0.25, "bush": 0.3, "hay_bale": 0.35, "rock": 0.1}, "density": 70,
		"far": ""},
	"hills": {
		"side_amp": 30.0, "valley": 0.04,
		"ground": [Color("58a043"), Color("6cae4a"), Color("4d8f3d")],
		"patch_m": Vector2(50, 50),
		"props": {"tree_round": 0.6, "bush": 0.3, "rock": 0.1}, "density": 130,
		"far": "hill"},
	"coast": {
		"side_amp": 7.0, "valley": 0.0,
		"ground": [Color("8cbc58"), Color("a3c766")],
		"patch_m": Vector2(60, 40),
		"props": {"bush": 0.6, "rock": 0.4}, "density": 45,
		"far": "", "sea": true},
	"mountains": {
		"side_amp": 55.0, "valley": 0.22,
		"ground": [Color("5d8f48"), Color("4f7f42")],
		"patch_m": Vector2(80, 60),
		"props": {"tree_pine": 0.75, "rock": 0.25}, "density": 120,
		"far": "peak"},
}

const C_ROAD := Color("3a3d45")
const C_SHOULDER := Color("b9a47a")
const C_LINE := Color("f2efe4")
const C_SAND := Color("eadba8")
const C_ROCKFACE := Color("8b8d93")
const C_SNOW := Color("f2f4f8")

var sim
var terrain
var origin_m := 0.0
var _chunks := {}  # chunk index -> Node3D
var _side_noise := FastNoiseLite.new()

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var _sky_top := Gradient.new()
var _sky_horizon := Gradient.new()
var _sun_color := Gradient.new()


func setup(rider_sim) -> void:
	sim = rider_sim
	terrain = sim.terrain
	_side_noise.seed = int(sim.t.terrain.seed) + 99
	_side_noise.frequency = 1.0
	_side_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_setup_environment()
	origin_m = floor(sim.distance_km * 1000.0 / REBASE_M) * REBASE_M


# ---------------------------------------------------------------- road geometry

## Sideways offset of the road centre. Gentle curves so the view changes.
func lateral(m: float) -> float:
	return 30.0 * sin(m / 520.0) + 14.0 * sin(m / 211.0 + 1.7)


func road_height(m: float) -> float:
	return terrain.elevation_m(m / 1000.0)


## World position on the road at route distance m (metres), in the rider's lane.
func road_point(m: float, lane := LANE_Z) -> Vector3:
	var y := road_height(m) + 0.05
	if absf(lane) > ROAD_HALF:
		y = ground_height(m, lane, biome_mix(m))
	return Vector3(m - origin_m, y, lateral(m) + lane)


func road_forward(m: float) -> Vector3:
	return (road_point(m + 2.0) - road_point(m - 2.0)).normalized()


## Mix of biome looks at a distance: [[vis, weight], ...].
func biome_mix(m: float) -> Array:
	var km := m / 1000.0
	var cfg: Dictionary = terrain.cfg
	var seg_len: float = cfg.segment_km
	var seg := int(floor(km / seg_len))
	var into := km - seg * seg_len
	var half: float = cfg.blend_km * 0.5
	var here: Dictionary = VIS[terrain.biomes[terrain.biome_index_for_segment(seg)].id]
	if into < half and seg > 0:
		var prev: Dictionary = VIS[terrain.biomes[terrain.biome_index_for_segment(seg - 1)].id]
		var t: float = 0.5 + into / cfg.blend_km
		return [[prev, 1.0 - t], [here, t]]
	if into > seg_len - half:
		var nxt: Dictionary = VIS[terrain.biomes[terrain.biome_index_for_segment(seg + 1)].id]
		var t2: float = (into - (seg_len - half)) / cfg.blend_km
		return [[here, 1.0 - t2], [nxt, t2]]
	return [[here, 1.0]]


func _sea_weight(mix: Array) -> float:
	var w := 0.0
	for e in mix:
		if e[0].get("sea", false):
			w += e[1]
	return w


## Ground height d metres to the side of the road centre.
func ground_height(m: float, d: float, mix: Array) -> float:
	var base := road_height(m)
	var a := absf(d)
	if a <= ROAD_HALF + 1.2:
		return base - 0.08
	var w_side := smoothstep(6.0, 70.0, a)
	var n := _side_noise.get_noise_2d(m * 0.005, d * 0.006) * 0.5 + 0.5
	var h := 0.0
	for e in mix:
		var vis: Dictionary = e[0]
		h += e[1] * (vis.side_amp * n * w_side + vis.valley * maxf(0.0, a - 12.0))
	if d > 0.0:
		h -= _sea_weight(mix) * smoothstep(18.0, 75.0, d) * 22.0
	return base + h


func _ground_color(m: float, d: float, h: float, mix: Array) -> Color:
	var a := absf(d)
	if a < ROAD_HALF + 1.2:
		return C_SHOULDER
	var base := road_height(m)
	var col := Color(0, 0, 0)
	for e in mix:
		var vis: Dictionary = e[0]
		var pal: Array = vis.ground
		var cell: Vector2 = vis.patch_m
		var hsh := absi(hash([int(floor(m / cell.x)), int(floor(d / cell.y))]))
		col += pal[hsh % pal.size()] * e[1]
	var rel := h - base
	if rel > 45.0:
		col = col.lerp(C_ROCKFACE, smoothstep(45.0, 70.0, rel))
	if rel > 95.0:
		col = col.lerp(C_SNOW, smoothstep(95.0, 115.0, rel))
	if d > 0.0 and _sea_weight(mix) > 0.3 and rel < -6.0:
		col = col.lerp(C_SAND, smoothstep(-6.0, -10.0, rel))
	return col


# ---------------------------------------------------------------- chunks

func update_view(rider_m: float) -> void:
	if rider_m - origin_m > REBASE_M:
		var shift: float = floor((rider_m - origin_m) / REBASE_M) * REBASE_M
		origin_m += shift
		for c in _chunks.values():
			c.position.x -= shift
	var first := int(floor((rider_m - BEHIND_M) / CHUNK_M))
	var last := int(floor((rider_m + AHEAD_M) / CHUNK_M))
	for i in _chunks.keys():
		if i < first or i > last:
			_chunks[i].queue_free()
			_chunks.erase(i)
	# Build at most two chunks per frame to avoid hitches.
	var built := 0
	for i in range(first, last + 1):
		if i < 0 or _chunks.has(i):
			continue
		_chunks[i] = _build_chunk(i)
		built += 1
		if built >= 2:
			break


func _build_chunk(index: int) -> Node3D:
	var m0 := index * CHUNK_M
	var node := Node3D.new()
	node.name = "Chunk%d" % index
	node.position.x = m0 - origin_m
	add_child(node)
	var rows := int(CHUNK_M / ROW_STEP_M)
	var mixes := []
	for r in rows + 1:
		mixes.append(biome_mix(m0 + r * ROW_STEP_M))

	node.add_child(_ground_mesh(m0, rows, mixes, -1.0))
	node.add_child(_ground_mesh(m0, rows, mixes, 1.0))
	node.add_child(_road_mesh(m0, rows))
	var sea := _sea_mesh(m0, rows, mixes)
	if sea:
		node.add_child(sea)
	_scatter_props(node, index, m0, mixes)
	_far_scenery(node, index, m0, mixes[rows / 2])
	_place_shops(node, m0)
	return node


func _ground_mesh(m0: float, rows: int, mixes: Array, side: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := SIDE_COLS.size()
	for r in rows + 1:
		var m := m0 + r * ROW_STEP_M
		var lat := lateral(m)
		for c in cols:
			var d: float = SIDE_COLS[c] * side
			var h := ground_height(m, d, mixes[r])
			st.set_color(_ground_color(m, d, h, mixes[r]))
			st.add_vertex(Vector3(m - m0, h, lat + d))
	for r in rows:
		for c in cols - 1:
			var i0 := r * cols + c
			var i1 := i0 + 1
			var i2 := i0 + cols
			var i3 := i2 + 1
			# Godot treats clockwise triangles (seen from the front) as front faces.
			if side > 0.0:
				st.add_index(i0); st.add_index(i2); st.add_index(i1)
				st.add_index(i1); st.add_index(i2); st.add_index(i3)
			else:
				st.add_index(i0); st.add_index(i1); st.add_index(i2)
				st.add_index(i1); st.add_index(i3); st.add_index(i2)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Materials.toon_vertex()
	return mi


func _road_mesh(m0: float, rows: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var strips := [[-ROAD_HALF, ROAD_HALF, C_ROAD, 0.0],
		[-3.25, -3.1, C_LINE, 0.01], [3.1, 3.25, C_LINE, 0.01]]
	for s in strips:
		for r in rows:
			var ma := m0 + r * ROW_STEP_M
			var mb := ma + ROW_STEP_M
			_quad(st, m0, ma, mb, s[0], s[1], s[3], s[2])
	# Dashed centre line.
	var dash := 0.0
	while dash < CHUNK_M:
		_quad(st, m0, m0 + dash, m0 + dash + 4.0, -0.08, 0.08, 0.01, C_LINE)
		dash += 12.0
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Materials.toon_vertex()
	return mi


func _quad(st: SurfaceTool, m0: float, ma: float, mb: float, za: float, zb: float, lift: float, col: Color) -> void:
	var ya := road_height(ma) + lift
	var yb := road_height(mb) + lift
	var la := lateral(ma)
	var lb := lateral(mb)
	var p0 := Vector3(ma - m0, ya, la + za)
	var p1 := Vector3(ma - m0, ya, la + zb)
	var p2 := Vector3(mb - m0, yb, lb + za)
	var p3 := Vector3(mb - m0, yb, lb + zb)
	st.set_color(col)
	for p in [p0, p2, p1, p1, p2, p3]:
		st.add_vertex(p)


func _sea_mesh(m0: float, rows: int, mixes: Array) -> MeshInstance3D:
	var any := false
	for mix in mixes:
		if _sea_weight(mix) > 0.3:
			any = true
	if not any:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for r in rows:
		var ma := m0 + r * ROW_STEP_M
		var mb := ma + ROW_STEP_M
		var ya := road_height(ma) - 9.0
		var yb := road_height(mb) - 9.0
		var la := lateral(ma)
		var lb := lateral(mb)
		var pts := [Vector3(ma - m0, ya, la + 30.0), Vector3(mb - m0, yb, lb + 30.0),
			Vector3(ma - m0, ya, la + 900.0), Vector3(mb - m0, yb, lb + 900.0)]
		for i in [0, 1, 2, 2, 1, 3]:
			st.add_vertex(pts[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Materials.water()
	return mi


func _scatter_props(node: Node3D, index: int, m0: float, mixes: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(sim.t.terrain.seed), "props", index])
	var placed := {}  # prop id -> Array[Transform3D]
	var mix: Array = mixes[mixes.size() / 2]
	var density := 0.0
	for e in mix:
		density += e[0].density * e[1]
	for n in int(density):
		var m := m0 + rng.randf() * CHUNK_M
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var d := side * lerpf(8.0, 160.0, pow(rng.randf(), 1.6))
		var row_mix: Array = mixes[clampi(int((m - m0) / ROW_STEP_M), 0, mixes.size() - 1)]
		if d > 20.0 and _sea_weight(row_mix) > 0.3:
			continue
		var vis: Dictionary = row_mix[0][0] if row_mix.size() == 1 or row_mix[0][1] > rng.randf() else row_mix[1][0]
		var id := _pick(vis.props, rng.randf())
		var y := ground_height(m, d, row_mix)
		var s := rng.randf_range(0.7, 1.4)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(m - m0, y - 0.1, lateral(m) + d))
		if not placed.has(id):
			placed[id] = []
		placed[id].append(xf)
	for id in placed:
		node.add_child(_multimesh(Props.get_mesh(id), placed[id], 0.04))


func _pick(weights: Dictionary, x: float) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var acc := 0.0
	for k in weights:
		acc += weights[k] / total
		if x <= acc:
			return k
	return weights.keys()[-1]


func _multimesh(mesh: Mesh, xforms: Array, outline: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Materials.toon_vertex(outline)
	return mmi


func _far_scenery(node: Node3D, index: int, m0: float, mix: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(sim.t.terrain.seed), "far", index])
	var xforms := {}
	for e in mix:
		var kind: String = e[0].far
		if kind == "" or rng.randf() > e[1]:
			continue
		for n in 2:
			var side := -1.0 if n == 0 else 1.0
			if side > 0.0 and _sea_weight(mix) > 0.3:
				continue
			var m := m0 + rng.randf() * CHUNK_M
			var d := side * rng.randf_range(320.0, 650.0)
			var base := road_height(m) - 30.0
			var xf: Transform3D
			if kind == "peak":
				var r := rng.randf_range(160.0, 320.0)
				xf = Transform3D(Basis().scaled(Vector3(r, rng.randf_range(300.0, 650.0), r)), Vector3(m - m0, base, lateral(m) + d))
			else:
				var r2 := rng.randf_range(120.0, 240.0)
				xf = Transform3D(Basis().scaled(Vector3(r2, r2, r2)), Vector3(m - m0, base, lateral(m) + d))
			if not xforms.has(kind):
				xforms[kind] = []
			xforms[kind].append(xf)
	for kind in xforms:
		node.add_child(_multimesh(Props.get_mesh(kind), xforms[kind], 0.0))


func _place_shops(node: Node3D, m0: float) -> void:
	var km: float = terrain.next_shop_after(m0 / 1000.0 - 0.0001)
	while km * 1000.0 < m0 + CHUNK_M:
		var m := km * 1000.0
		var shop := MeshInstance3D.new()
		shop.mesh = Props.get_mesh("shop")
		shop.material_override = Materials.toon_vertex(0.05)
		shop.position = Vector3(m - m0, road_height(m) - 0.1, lateral(m) + 12.0)
		node.add_child(shop)
		var sign := Label3D.new()
		sign.text = "SHOP"
		sign.font_size = 160
		sign.outline_size = 24
		sign.modulate = Color("ffe9a8")
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.position = shop.position + Vector3(0, 6.2, 0)
		node.add_child(sign)
		km = terrain.next_shop_after(km)


# ---------------------------------------------------------------- sky and light

func _setup_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 350.0
	env.fog_depth_end = 1350.0
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	# One shadow split close to the rider: shadows matter for the rider and
	# nearby props, and a single split avoids visible seams on the ground.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 3.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color("8fa6d9")
	moon.light_energy = 0.35
	moon.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	add_child(moon)

	# Colours through the day, keyed by hour / 24.
	_set_gradient(_sky_top, [[0.0, "0b1030"], [0.2, "141c48"], [0.26, "4a6fb0"], [0.38, "3f8fe0"],
		[0.7, "3f8fe0"], [0.79, "4a5aa0"], [0.86, "1a2050"], [1.0, "0b1030"]])
	_set_gradient(_sky_horizon, [[0.0, "1a2040"], [0.2, "2a3060"], [0.25, "f0a070"], [0.33, "bfe0f5"],
		[0.72, "bfe0f5"], [0.785, "f5906a"], [0.84, "35305a"], [1.0, "1a2040"]])
	_set_gradient(_sun_color, [[0.0, "000000"], [0.24, "000000"], [0.27, "ffb27a"], [0.35, "fff4e0"],
		[0.7, "fff4e0"], [0.78, "ff9a60"], [0.81, "000000"], [1.0, "000000"]])


func _set_gradient(g: Gradient, stops: Array) -> void:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(Color(s[1]))
	g.offsets = offsets
	g.colors = colors


func set_time_of_day(hour: float) -> void:
	var x := fposmod(hour, 24.0) / 24.0
	var top := _sky_top.sample(x)
	var horizon := _sky_horizon.sample(x)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = top.darkened(0.3)
	env.fog_light_color = horizon
	var sun_col := _sun_color.sample(x)
	var day := clampf(sun_col.v, 0.0, 1.0)
	# Sun rises at 6, sets at 19 (summer-ish), highest around 12:30.
	var t := clampf((hour - 6.0) / 13.0, 0.0, 1.0)
	var alt := sin(t * PI) * deg_to_rad(62.0) + deg_to_rad(2.0)
	sun.rotation = Vector3(-alt, deg_to_rad(lerpf(-110.0, 110.0, t)), 0.0)
	sun.light_color = sun_col
	sun.light_energy = 0.85 * day
	sun.visible = day > 0.02
	moon.visible = day < 0.6
	moon.light_energy = 0.35 * (1.0 - day)
	env.ambient_light_color = top.lerp(horizon, 0.5)
	env.ambient_light_energy = lerpf(0.3, 0.32, day)
