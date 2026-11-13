extends RefCounted

const BuildData := preload("res://scripts/mountain/track_build_data.gd")
const Settings := preload("res://scripts/mountain/mountain_road_settings.gd")
const TerrainBuilder := preload("res://scripts/mountain/terrain_builder.gd")
const TrackLots := preload("res://scripts/mountain/track_lots.gd")
const TrackSampler := preload("res://scripts/mountain/track_sampler.gd")


# --- Kenney Nature Kit ----------------------------------------------------------------
# Modelli del kit (cartella GLTF). Hanno materiali a tinta unita incorporati e sono piccoli
# (un pino ~1.5 m, una roccia 0.3-1 m): vengono ingranditi con i parametri *_scale.
const NK_TREES: Array[String] = [
	"tree_pineTallA", "tree_pineTallB", "tree_pineTallC", "tree_pineTallD",
	"tree_pineDefaultA", "tree_pineDefaultB", "tree_pineRoundA", "tree_pineRoundB",
	"tree_pineRoundC", "tree_pineSmallA", "tree_pineSmallB"]
const NK_ROCKS: Array[String] = [
	"rock_largeA", "rock_largeB", "rock_largeC", "rock_largeD", "rock_tallA", "rock_tallB",
	"rock_tallC", "rock_tallD", "stone_largeA", "stone_largeB", "stone_tallA", "stone_tallB"]
const NK_SMALL_ROCKS: Array[String] = [
	"rock_smallA", "rock_smallB", "rock_smallC", "rock_smallD", "rock_smallE", "rock_smallFlatA",
	"stone_smallA", "stone_smallB", "stone_smallC", "stone_smallFlatA"]
const NK_BUSHES: Array[String] = [
	"plant_bush", "plant_bushLarge", "plant_bushSmall", "plant_bushTriangle", "plant_bushLargeTriangle"]
const NK_GRASS: Array[String] = [
	"grass", "grass_large", "grass_leafs", "grass_leafsLarge", "plant_flatShort", "plant_flatTall"]
const NK_FLOWERS: Array[String] = [
	"flower_purpleA", "flower_purpleB", "flower_redA", "flower_redB", "flower_yellowA", "flower_yellowB"]
const NK_DEBRIS: Array[String] = ["log", "log_large", "stump_old", "stump_round"]


static func _nk_mesh(road: Settings, track: BuildData, model: String) -> Mesh:
	if track.nature_cache.has(model):
		return track.nature_cache[model]
	var res := load("%s/%s.glb" % [road.nature_kit_dir, model])
	var mesh: Mesh = null
	if res is PackedScene:
		var root: Node = (res as PackedScene).instantiate()
		var found := root.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			mesh = (found[0] as MeshInstance3D).mesh
			if road.nk_recolor and mesh != null:
				mesh = mesh.duplicate() as Mesh
				for si in mesh.get_surface_count():
					var old_mat := mesh.surface_get_material(si)
					var old_name := old_mat.resource_name if old_mat != null else ""
					mesh.surface_set_material(si, _nk_material(road, track, old_name, old_mat, model))
		root.free()
	if mesh == null:
		push_warning("MountainRoad: modello Nature Kit non trovato: %s/%s.glb" % [road.nature_kit_dir, model])
	track.nature_cache[model] = mesh
	return mesh


# Palette da montagna per i materiali del kit (per nome del materiale originale).
static func _nk_material(road: Settings, track: BuildData, mat_name: String, old_mat: Material, model: String) -> Material:
	var key := mat_name + ("@rock" if model.begins_with("rock_") else "")
	if track.nature_cache.has("mat:" + key):
		return track.nature_cache["mat:" + key]
	var col := Color(0.4, 0.4, 0.4)
	match mat_name:
		"leafsDark": col = Color(0.11, 0.29, 0.15)
		"leafsGreen": col = Color(0.20, 0.42, 0.18)
		"leafsFall": col = Color(0.72, 0.38, 0.14)
		"grass": col = Color(0.30, 0.50, 0.22)
		"woodBark", "woodBarkDark", "woodDark", "wood": col = Color(0.33, 0.23, 0.15)
		"woodInner": col = Color(0.70, 0.55, 0.38)
		"woodBirch": col = Color(0.84, 0.82, 0.76)
		"dirt": col = road.rock_color if model.begins_with("rock_") else Color(0.42, 0.32, 0.22)
		"dirtDark": col = road.rock_color.darkened(0.2)
		"stone": col = Color(0.55, 0.55, 0.54)
		"stoneDark": col = Color(0.42, 0.42, 0.41)
		"colorRed", "colorRedDark": col = Color(0.78, 0.14, 0.14)
		"colorYellow": col = Color(0.95, 0.80, 0.20)
		"colorPurple": col = Color(0.55, 0.40, 0.80)
		"colorTan": col = Color(0.78, 0.64, 0.44)
		"colorWhite", "_defaultMat": col = Color(0.90, 0.88, 0.80)
		_:
			if old_mat is BaseMaterial3D:
				col = (old_mat as BaseMaterial3D).albedo_color
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = col
	m.roughness = 0.9
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	track.nature_cache["mat:" + key] = m
	return m


# Un punto (x, z) e' utilizzabile se e' lontano dalla strada e dai piazzali e non troppo
# ripido. (Il terreno e' piano a quota 0 appena fuori dalla strada: li si puo' piantare.)
static func _nk_valid(road: Settings, track: BuildData, p2: Vector2, road_xz: PackedVector2Array, clearance: float, max_slope: float) -> bool:
	if TrackLots.near_lot(road.lot_size, track, p2.x, p2.y, 3.0):
		return false
	var c2 := clearance * clearance
	for rp in road_xz:
		if p2.distance_squared_to(rp) < c2:
			return false
	return TerrainBuilder.sample_slope(road.terrain_cell, track, p2.x, p2.y) <= max_slope


# Aggiunge un'istanza (rotazione casuale, affondata nel terreno) al gruppo del suo modello.
# collider: "" nessuno, "box" per le rocce, "trunk" per gli alberi.
static func _nk_add(road: Settings, track: BuildData, rng: RandomNumberGenerator, buckets: Dictionary, colliders: StaticBody3D, model: String,
		p2: Vector2, scale_range: Vector2, shadows: bool, collider: String, near_road: bool) -> void:
	var mesh := _nk_mesh(road, track, model)
	if mesh == null:
		return
	var sc := rng.randf_range(scale_range.x, scale_range.y)
	var rot := rng.randf_range(0.0, TAU)
	var y := TerrainBuilder.sample_height(road.terrain_cell, track, p2.x, p2.y) - 0.05 * sc
	var basis := Basis(Vector3.UP, rot).scaled(Vector3.ONE * sc)
	if not buckets.has(model):
		buckets[model] = {"xf": [], "shadows": shadows}
	buckets[model]["xf"].append(Transform3D(basis, Vector3(p2.x, y, p2.y)))
	if not near_road or collider == "":
		return
	var cs := CollisionShape3D.new()
	if collider == "box":
		var bb := mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = Vector3(bb.size.x * sc * 0.85, bb.size.y * sc, bb.size.z * sc * 0.85)
		cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, rot), Vector3(p2.x, y + bb.size.y * sc * 0.5, p2.y))
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.3 * sc / 4.0
		cyl.height = 4.0 * sc / 4.0
		cs.shape = cyl
		cs.position = Vector3(p2.x, y + cyl.height * 0.5, p2.y)
	colliders.add_child(cs)


static func build(road: Settings, track: BuildData) -> void:
	if track.terrain_heights.is_empty() or track.centerline.size() < 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = road.nature_seed
	var n := track.centerline.size()
	var road_xz := PackedVector2Array()
	for p in track.centerline:
		road_xz.append(Vector2(p.x, p.z))
	var rail_out := road.road_width * 0.5 + road.rail_offset + road.rail_thickness
	var buckets := {}
	var colliders := StaticBody3D.new()
	colliders.name = "NatureKitColliders"
	var near2 := 15.0 * 15.0  # collider solo per quello che sta vicino alla strada
	var rock_count := 0
	var hairpin_samples := 0

	# 1) rocce nell'interno dei tornanti
	if road.enable_rocks:
		var k := maxi(1, int(round(road.hairpin_window * 0.5 / road.step_length)))
		var min_turn := road.hairpin_window / maxf(road.hairpin_max_radius, 1.0)  # radianti
		for i in range(k, n - k):
			var t_in := TrackSampler.basis_at(track.centerline, i - k).z
			var t_out := TrackSampler.basis_at(track.centerline, i + k).z
			var turn := t_in.signed_angle_to(t_out, Vector3.UP)  # > 0 = curva a sinistra
			if absf(turn) < min_turn:
				continue
			hairpin_samples += 1
			# TrackSampler.side(track.centerline) e' il lato destro: l'interno e' dalla parte verso cui si gira
			var inner := -TrackSampler.side(track.centerline, i) if turn > 0.0 else TrackSampler.side(track.centerline, i)
			for _a in 2:
				if rng.randf() > road.rock_chance * road.nature_density:
					continue
				var d := rail_out + 1.2 + rng.randf() * 7.0
				var pos := track.centerline[i] + inner * d
				var p2 := Vector2(pos.x, pos.z)
				if not _nk_valid(road, track, p2, road_xz, road.nk_min_road_distance, 1.2):
					continue
				var pool := NK_ROCKS if rng.randf() < 0.7 else NK_SMALL_ROCKS
				var scale_range := road.rock_scale if pool == NK_ROCKS else road.rock_scale * 0.8
				var near := _min_d2(p2, road_xz) < near2
				_nk_add(road, track, rng, buckets, colliders, pool[rng.randi() % pool.size()], p2, scale_range, true, "box", near)
				rock_count += 1

	# 2) fascia di alberi ai lati della strada + vegetazione bassa
	for i in range(0, n, 2):
		var side := TrackSampler.side(track.centerline, i)
		var tan := Vector3(side.z, 0.0, -side.x)
		for sgn: float in [-1.0, 1.0]:
			if rng.randf() < road.nk_tree_chance * road.nature_density:
				var d := rail_out + 3.0 + rng.randf() * road.nk_tree_band
				var pos := track.centerline[i] + side * sgn * d + tan * rng.randf_range(-2.0, 2.0)
				var p2 := Vector2(pos.x, pos.z)
				if _nk_valid(road, track, p2, road_xz, road.nk_min_road_distance, road.max_tree_slope) and _nk_spacing_ok(road, track, p2):
					_nk_register(road, track, p2)
					var near := _min_d2(p2, road_xz) < near2
					_nk_add(road, track, rng, buckets, colliders, NK_TREES[rng.randi() % NK_TREES.size()], p2, road.nk_tree_scale, true, "trunk", near)
			var count := int(road.plant_per_sample * road.nature_density)
			if rng.randf() < road.plant_per_sample * road.nature_density - float(count):
				count += 1
			for _b in count:
				var d2 := rail_out + 0.8 + rng.randf() * road.plant_band
				var pos2 := track.centerline[i] + side * sgn * d2 + tan * rng.randf_range(-2.0, 2.0)
				var q2 := Vector2(pos2.x, pos2.z)
				if not _nk_valid(road, track, q2, road_xz, rail_out + 0.8, 1.2):
					continue
				var roll := rng.randf()
				if roll < 0.35:
					_nk_add(road, track, rng, buckets, colliders, NK_BUSHES[rng.randi() % NK_BUSHES.size()], q2, Vector2(3.5, 6.0), false, "", false)
				elif roll < 0.8:
					_nk_add(road, track, rng, buckets, colliders, NK_GRASS[rng.randi() % NK_GRASS.size()], q2, Vector2(3.0, 5.0), false, "", false)
				elif roll < 0.92:
					_nk_add(road, track, rng, buckets, colliders, NK_FLOWERS[rng.randi() % NK_FLOWERS.size()], q2, Vector2(3.0, 5.0), false, "", false)
				elif roll < 0.97:
					_nk_add(road, track, rng, buckets, colliders, NK_SMALL_ROCKS[rng.randi() % NK_SMALL_ROCKS.size()], q2, Vector2(2.5, 4.5), false, "", false)
				else:
					_nk_add(road, track, rng, buckets, colliders, NK_DEBRIS[rng.randi() % NK_DEBRIS.size()], q2, Vector2(3.0, 4.5), false, "", false)

	# 3) un MultiMesh per modello (materiali originali del kit)
	var root := Node3D.new()
	root.name = "NatureKit"
	var total := 0
	for model: String in buckets:
		var xf: Array = buckets[model]["xf"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _nk_mesh(road, track, model)
		mm.instance_count = xf.size()
		for j in xf.size():
			mm.set_instance_transform(j, xf[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "NK_" + model
		mmi.multimesh = mm
		if not buckets[model]["shadows"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 140.0
		root.add_child(mmi)
		total += xf.size()
	if colliders.get_child_count() > 0:
		root.add_child(colliders)
	road.add_child(root)
	print("[MountainRoad] Nature Kit: %d istanze, %d rocce in %d campioni di tornante, %d collider" % [
		total, rock_count, hairpin_samples, colliders.get_child_count()])


static func _min_d2(p2: Vector2, road_xz: PackedVector2Array) -> float:
	var best := INF
	for rp in road_xz:
		best = minf(best, p2.distance_squared_to(rp))
	return best


# Spaziatura tra alberi: usa la stessa griglia della vegetazione originale.
static func _nk_spacing_ok(road: Settings, track: BuildData, p2: Vector2) -> bool:
	var gx := int(floor(p2.x / road.min_tree_spacing))
	var gz := int(floor(p2.y / road.min_tree_spacing))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(gx + dx, gz + dz)
			if track.vegetation_grid.has(key):
				for other: Vector2 in track.vegetation_grid[key]:
					if p2.distance_squared_to(other) < road.nk_tree_spacing * road.nk_tree_spacing:
						return false
	return true


static func _nk_register(road: Settings, track: BuildData, p2: Vector2) -> void:
	var key := Vector2i(int(floor(p2.x / road.min_tree_spacing)), int(floor(p2.y / road.min_tree_spacing)))
	if not track.vegetation_grid.has(key):
		track.vegetation_grid[key] = []
	track.vegetation_grid[key].append(p2)
