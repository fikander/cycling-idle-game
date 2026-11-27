extends RefCounted
## Low-poly scenery meshes built from primitives, with colours baked into
## vertex colours so each prop type is a single mesh and draw call.

const C_TRUNK := Color("6b4a32")
const C_LEAF := Color("5fa84a")
const C_LEAF_LIGHT := Color("86c25a")
const C_PINE := Color("2f6b45")
const C_ROCK := Color("8a8f96")
const C_HAY := Color("e0bd5a")
const C_SNOW := Color("f4f6fa")
const C_PEAK := Color("7d8494")
const C_HILL := Color("6aa055")
const C_WALL := Color("efe3c8")
const C_ROOF := Color("c4553f")
const C_DOOR := Color("5a3c2a")

static var _meshes := {}


static func get_mesh(id: String) -> Mesh:
	if _meshes.is_empty():
		_build_all()
	return _meshes[id]


static func _build_all() -> void:
	_meshes.tree_round = _merge([
		[_cyl(0.18, 0.25, 1.6, 6), Transform3D(Basis(), Vector3(0, 0.8, 0)), C_TRUNK],
		[_sphere(1.3, 8, 5), Transform3D(Basis(), Vector3(0, 2.4, 0)), C_LEAF],
		[_sphere(0.9, 8, 5), Transform3D(Basis(), Vector3(0.6, 3.1, 0.3)), C_LEAF_LIGHT],
	])
	_meshes.tree_pine = _merge([
		[_cyl(0.15, 0.2, 1.2, 6), Transform3D(Basis(), Vector3(0, 0.6, 0)), C_TRUNK],
		[_cyl(0.0, 1.4, 2.0, 7), Transform3D(Basis(), Vector3(0, 2.0, 0)), C_PINE],
		[_cyl(0.0, 1.1, 1.8, 7), Transform3D(Basis(), Vector3(0, 3.0, 0)), C_PINE],
		[_cyl(0.0, 0.8, 1.5, 7), Transform3D(Basis(), Vector3(0, 3.9, 0)), C_PINE],
	])
	_meshes.bush = _merge([
		[_sphere(0.7, 7, 4), Transform3D(Basis().scaled(Vector3(1, 0.7, 1)), Vector3(0, 0.35, 0)), C_LEAF],
		[_sphere(0.5, 7, 4), Transform3D(Basis().scaled(Vector3(1, 0.8, 1)), Vector3(0.5, 0.35, 0.2)), C_LEAF_LIGHT],
	])
	_meshes.rock = _merge([
		[_sphere(0.8, 6, 3), Transform3D(Basis().scaled(Vector3(1.3, 0.7, 1.0)), Vector3(0, 0.2, 0)), C_ROCK],
	])
	_meshes.hay_bale = _merge([
		[_cyl(0.6, 0.6, 1.0, 10), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.6, 0)), C_HAY],
	])
	_meshes.peak = _merge([
		[_cyl(0.0, 1.0, 1.0, 9), Transform3D(Basis(), Vector3(0, 0.5, 0)), C_PEAK],
		[_cyl(0.0, 0.33, 0.34, 9), Transform3D(Basis(), Vector3(0, 0.84, 0)), C_SNOW],
	])
	_meshes.hill = _merge([
		[_sphere(1.0, 12, 6), Transform3D(Basis().scaled(Vector3(1, 0.45, 1)), Vector3.ZERO), C_HILL],
	])
	_meshes.shop = _merge([
		[_box(Vector3(5, 3, 4)), Transform3D(Basis(), Vector3(0, 1.5, 0)), C_WALL],
		[_prism(Vector3(5.6, 1.6, 4.6)), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 3.8, 0)), C_ROOF],
		[_box(Vector3(0.1, 1.9, 1.1)), Transform3D(Basis(), Vector3(-2.5, 0.95, 0)), C_DOOR],
		[_box(Vector3(0.1, 0.9, 1.0)), Transform3D(Basis(), Vector3(-2.5, 1.8, 1.4)), Color("9fd3e8")],
	])


static func _cyl(top: float, bottom: float, height: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segs
	m.rings = 1
	return m


static func _sphere(r: float, segs: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = rings
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


## Merges [mesh, transform, colour] parts into one vertex-coloured mesh.
static func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var arrays: Array = part[0].get_mesh_arrays()
		var xf: Transform3D = part[1]
		var col: Color = part[2]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		for i in idx:
			st.set_color(col)
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
	return st.commit()
