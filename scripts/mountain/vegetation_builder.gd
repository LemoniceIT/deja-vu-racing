extends RefCounted

const BuildData := preload("res://scripts/mountain/track_build_data.gd")
const Settings := preload("res://scripts/mountain/mountain_road_settings.gd")
const TerrainBuilder := preload("res://scripts/mountain/terrain_builder.gd")
const TrackLots := preload("res://scripts/mountain/track_lots.gd")


static func build(road: Settings, track: BuildData) -> void:
	if track.terrain_heights.is_empty() or track.centerline.size() < 2:
		return

	# Precarichiamo i mesh da MountainTreeMeshes
	var mesh_short := MountainTreeMeshes.get_mesh("tree_pine_short")
	var mesh_tall := MountainTreeMeshes.get_mesh("tree_pine_tall")
	var mesh_giant := MountainTreeMeshes.get_mesh("tree_pine_giant")
	var mesh_bush := MountainTreeMeshes.get_mesh("mound_bush")

	if mesh_short == null or mesh_tall == null:
		push_warning("MountainRoad: impossibile caricare i mesh degli alberi")
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = road.colormap_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9

	# Array di MultiMeshInstance3D per ciascuna categoria
	var tree_types: Array[Dictionary] = [
		{"name": "TreesTall", "mesh": mesh_tall, "transforms": []},
		{"name": "TreesShort", "mesh": mesh_short, "transforms": []},
		{"name": "TreesGiant", "mesh": mesh_giant, "transforms": []},
		{"name": "Bushes", "mesh": mesh_bush, "transforms": []}
	]

	var width := track.terrain_max.x - track.terrain_min.x
	var depth := track.terrain_max.y - track.terrain_min.y
	var area := width * depth
	var num_candidates := int(area * road.tree_density)

	# Coordinate 2D della centerline per controllo rapido vicinanza alla strada
	var road_xz := PackedVector2Array()
	for p in track.centerline:
		road_xz.append(Vector2(p.x, p.z))
	var min_road_d2 := road.min_tree_road_distance * road.min_tree_road_distance

	# Griglia spaziale per evitare sovrapposizioni tra alberi
	var grid_cell := road.min_tree_spacing
	track.vegetation_grid.clear()
	var placed_trees := track.vegetation_grid # key: Vector2i -> Array of Vector2

	var rng := RandomNumberGenerator.new()
	rng.seed = road.vegetation_seed

	# StaticBody per collisioni dei tronchi principali (vicini alla strada)
	var coll_body := StaticBody3D.new()
	coll_body.name = "VegetationColliders"
	var coll_margin := road.min_tree_road_distance + 15.0 # Mettiamo collider solo per alberi entro 15m dalla strada
	var coll_margin_d2 := coll_margin * coll_margin

	for _attempt in num_candidates:
		var x := rng.randf_range(track.terrain_min.x + 5.0, track.terrain_max.x - 5.0)
		var z := rng.randf_range(track.terrain_min.y + 5.0, track.terrain_max.y - 5.0)
		var p2 := Vector2(x, z)

		# 1. Distanza dalla strada
		var closest_d2 := INF
		for rp in road_xz:
			var d2 := p2.distance_squared_to(rp)
			if d2 < closest_d2:
				closest_d2 = d2
				if closest_d2 < min_road_d2:
					break
		if closest_d2 < min_road_d2:
			continue

		# 1b. Niente alberi sui piazzali
		if TrackLots.near_lot(road.lot_size, track, x, z, 3.0):
			continue

		# 2. Quota e pendenza del terreno
		var y := TerrainBuilder.sample_height(road.terrain_cell, track, x, z)
		if y <= 0.05: # sotto o a filo pavimento di base
			continue
		var slope := TerrainBuilder.sample_slope(road.terrain_cell, track, x, z)
		if slope > road.max_tree_slope: # roccia troppo ripida per alberi
			continue

		# 3. Spaziatura dagli altri alberi (griglia)
		var gx := int(floor(x / grid_cell))
		var gz := int(floor(z / grid_cell))
		var too_close := false
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var key := Vector2i(gx + dx, gz + dz)
				if placed_trees.has(key):
					for other: Vector2 in placed_trees[key]:
						if p2.distance_squared_to(other) < road.min_tree_spacing * road.min_tree_spacing:
							too_close = true
							break
				if too_close:
					break
			if too_close:
				break
		if too_close:
			continue

		var cell_key := Vector2i(gx, gz)
		if not placed_trees.has(cell_key):
			placed_trees[cell_key] = []
		placed_trees[cell_key].append(p2)

		# 4. Selezione tipo di vegetazione e scala/rotazione
		var rand_val := rng.randf()
		var type_idx: int
		var scale_y: float
		var scale_xz: float

		if rand_val < 0.40:
			# Pino alto
			type_idx = 0
			scale_y = rng.randf_range(0.85, 1.25)
			scale_xz = scale_y * rng.randf_range(0.9, 1.1)
		elif rand_val < 0.72:
			# Pino basso
			type_idx = 1
			scale_y = rng.randf_range(0.8, 1.2)
			scale_xz = scale_y * rng.randf_range(0.9, 1.1)
		elif rand_val < 0.88:
			# Pino gigante
			type_idx = 2
			scale_y = rng.randf_range(0.9, 1.3)
			scale_xz = scale_y * rng.randf_range(0.95, 1.05)
		else:
			# Cespuglio / vegetazione bassa
			type_idx = 3
			scale_y = rng.randf_range(0.7, 1.5)
			scale_xz = rng.randf_range(0.8, 1.6)

		var rot_y := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(scale_xz, scale_y, scale_xz))
		# Affondiamo leggermente il modello (0.1m) nel terreno per non avere tronchi volanti su pendenze
		var tree_pos := Vector3(x, y - 0.1, z)
		var xform := Transform3D(basis, tree_pos)
		tree_types[type_idx]["transforms"].append(xform)

		# Se l'albero e' un pino ed e' vicino alla strada, aggiungiamo collider cilindrico per il tronco
		if type_idx < 3 and closest_d2 <= coll_margin_d2:
			var trunk_h := 3.5 * scale_y
			var trunk_r := 0.25 * scale_xz
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.height = trunk_h
			cyl.radius = trunk_r
			cs.shape = cyl
			cs.position = Vector3(x, y + trunk_h * 0.5 - 0.1, z)
			coll_body.add_child(cs)

	# Creazione dei nodi MultiMeshInstance3D
	var veg_root := Node3D.new()
	veg_root.name = "Vegetation"

	for tinfo in tree_types:
		var xforms: Array = tinfo["transforms"]
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tinfo["mesh"]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = tinfo["name"]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		veg_root.add_child(mmi)

	if coll_body.get_child_count() > 0:
		veg_root.add_child(coll_body)

	road.add_child(veg_root)
