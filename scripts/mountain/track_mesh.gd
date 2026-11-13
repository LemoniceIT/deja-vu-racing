extends RefCounted

# Triangolo con la faccia visibile (e collidente) rivolta verso "facing".
# In Godot la faccia frontale e' quella con vertici in senso orario.
static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, facing: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.dot(facing) < 0.0:
		var tmp := b
		b = c
		c = tmp
		var tc := cb
		cb = cc
		cc = tc
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


# Quadrilatero con i 4 vertici in ordine ciclico lungo il perimetro.
static func quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, facing: Vector3, col: Color) -> void:
	triangle(st, p0, p1, p2, facing, col, col, col)
	triangle(st, p0, p2, p3, facing, col, col, col)


static func add_visual(road: Node3D, mesh: ArrayMesh, node_name: String) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	road.add_child(mi)


static func add_collider(road: Node3D, mesh: ArrayMesh, node_name: String, friction: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name + "Body"
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	body.physics_material_override = pm
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	road.add_child(body)


static func add_mesh_body(road: Node3D, mesh: ArrayMesh, node_name: String, friction: float) -> void:
	add_visual(road, mesh, node_name)
	add_collider(road, mesh, node_name, friction)
