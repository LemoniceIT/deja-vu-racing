extends RefCounted

const BuildData := preload("res://scripts/mountain/track_build_data.gd")
const Settings := preload("res://scripts/mountain/mountain_road_settings.gd")
const TrackLots := preload("res://scripts/mountain/track_lots.gd")
const TrackMesh := preload("res://scripts/mountain/track_mesh.gd")


static func build(road: Settings, track: BuildData) -> void:
	var n := track.centerline.size()
	var xz := PackedVector2Array()
	var ys := PackedFloat32Array()
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in track.centerline:
		xz.append(Vector2(p.x, p.z))
		ys.append(p.y)
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.z))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.z))
	min_p -= Vector2.ONE * road.terrain_margin
	max_p += Vector2.ONE * road.terrain_margin

	var nx := int(ceil((max_p.x - min_p.x) / road.terrain_cell)) + 1
	var nz := int(ceil((max_p.y - min_p.y) / road.terrain_cell)) + 1
	var edge := road.road_width * 0.5 + road.shoulder
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)

	for iz in nz:
		for ix in nx:
			var p := Vector2(min_p.x + ix * road.terrain_cell, min_p.y + iz * road.terrain_cell)
			var best_d2 := INF
			var best_y := 0.0
			for i in n:
				var d2 := p.distance_squared_to(xz[i])
				if d2 < best_d2:
					best_d2 = d2
					best_y = ys[i]
			var d := sqrt(best_d2)
			var road_h := best_y - road.bed_depth
			var h := road_h
			if d > edge:
				# fuori dalla sede: pendio che scende dalla strada, media pesata
				# tra i campioni vicini per evitare salti tra un ramo e l'altro
				var wsum := 0.0
				var hsum := 0.0
				for i in range(0, n, road.skirt_step):
					var di := p.distance_to(xz[i])
					var q := di * di + 1.0
					var w := 1.0 / (q * q)
					wsum += w
					hsum += w * (ys[i] - road.fall_slope * maxf(0.0, di - edge))
				var skirt := maxf(hsum / wsum, 0.0)
				h = lerpf(road_h, skirt, smoothstep(edge, edge + road.blend_width, d))
			var hh := maxf(h, 0.0) if d > edge else h
			for lot in track.lots:
				# piazzale piano; fuori dal bordo il terreno scende con fall_slope (come ai lati
				# della strada) invece di precipitare, poi si raccorda al terreno naturale
				var od := TrackLots.outside_distance(road.lot_size, lot, p.x, p.y)
				if od < road.blend_width * 3.0:
					var pad_h: float = lot["origin"].y - road.bed_depth
					var line := pad_h - road.fall_slope * od
					var outer := hh
					if hh < line:
						outer = lerpf(line, hh, smoothstep(0.0, road.blend_width * 3.0, od))
					hh = lerpf(pad_h, outer, smoothstep(0.0, road.blend_width, od))
			heights[iz * nx + ix] = hh

	# vertici e colori (erba -> roccia in base alla pendenza)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	cols.resize(nx * nz)
	track.terrain_min = min_p
	track.terrain_max = max_p
	track.terrain_columns = nx
	track.terrain_rows = nz
	track.terrain_heights = heights
	# variazione del colore dell'erba: chiazze grandi (~35 m) + dettaglio (~9 m)
	var noise_big := FastNoiseLite.new()
	noise_big.seed = road.vegetation_seed + 11
	noise_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_big.frequency = 0.03
	var noise_fine := FastNoiseLite.new()
	noise_fine.seed = road.vegetation_seed + 23
	noise_fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_fine.frequency = 0.11
	for iz in nz:
		for ix in nx:
			var ixl := maxi(ix - 1, 0)
			var ixr := mini(ix + 1, nx - 1)
			var izd := maxi(iz - 1, 0)
			var izu := mini(iz + 1, nz - 1)
			var gx := (heights[iz * nx + ixr] - heights[iz * nx + ixl]) / (road.terrain_cell * (ixr - ixl))
			var gz := (heights[izu * nx + ix] - heights[izd * nx + ix]) / (road.terrain_cell * (izu - izd))
			var rock := clampf((Vector2(gx, gz).length() - 0.45) / 0.5, 0.0, 1.0)
			verts[iz * nx + ix] = Vector3(min_p.x + ix * road.terrain_cell, heights[iz * nx + ix], min_p.y + iz * road.terrain_cell)
			var wx := min_p.x + ix * road.terrain_cell
			var wz := min_p.y + iz * road.terrain_cell
			var v := clampf(noise_big.get_noise_2d(wx, wz) * 0.75 + noise_fine.get_noise_2d(wx, wz) * 0.35, -1.0, 1.0)
			var grass := road.grass_color
			if v < 0.0:
				grass = road.grass_color.darkened(-v * road.grass_variation * 0.55)
			else:
				grass = road.grass_color.lerp(road.grass_dry_color, v * road.grass_variation * 0.8)
			var rock_c := road.rock_color
			if v < 0.0:
				rock_c = road.rock_color.darkened(-v * road.grass_variation * 0.4)
			else:
				rock_c = road.rock_color.lightened(v * road.grass_variation * 0.2)
			cols[iz * nx + ix] = grass.lerp(rock_c, rock)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz - 1:
		for ix in nx - 1:
			var i00 := iz * nx + ix
			var i10 := i00 + 1
			var i01 := i00 + nx
			var i11 := i01 + 1
			TrackMesh.triangle(st, verts[i00], verts[i10], verts[i01], Vector3.UP, cols[i00], cols[i10], cols[i01])
			TrackMesh.triangle(st, verts[i10], verts[i11], verts[i01], Vector3.UP, cols[i10], cols[i11], cols[i01])
	st.generate_normals()
	var terrain_mesh := st.commit()
	TrackMesh.add_collider(road, terrain_mesh, "Terrain", road.road_friction)
	# i colori del terreno sono in sRGB (gli altri vertex color della strada restano come prima)
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.vertex_color_is_srgb = true
	tmat.roughness = 0.95
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tmi := MeshInstance3D.new()
	tmi.name = "Terrain"
	tmi.mesh = terrain_mesh
	tmi.material_override = tmat
	road.add_child(tmi)


static func sample_height(cell: float, track: BuildData, x: float, z: float) -> float:
	if track.terrain_columns < 2 or track.terrain_rows < 2 or track.terrain_heights.is_empty():
		return 0.0
	var fx := (x - track.terrain_min.x) / cell
	var fz := (z - track.terrain_min.y) / cell
	var ix := clampi(int(floor(fx)), 0, track.terrain_columns - 2)
	var iz := clampi(int(floor(fz)), 0, track.terrain_rows - 2)
	var rx := clampf(fx - float(ix), 0.0, 1.0)
	var rz := clampf(fz - float(iz), 0.0, 1.0)
	var h00 := track.terrain_heights[iz * track.terrain_columns + ix]
	var h10 := track.terrain_heights[iz * track.terrain_columns + ix + 1]
	var h01 := track.terrain_heights[(iz + 1) * track.terrain_columns + ix]
	var h11 := track.terrain_heights[(iz + 1) * track.terrain_columns + ix + 1]
	var h0 := lerpf(h00, h10, rx)
	var h1 := lerpf(h01, h11, rx)
	return lerpf(h0, h1, rz)


static func sample_slope(cell: float, track: BuildData, x: float, z: float) -> float:
	if track.terrain_columns < 2 or track.terrain_rows < 2:
		return 0.0
	var delta := 1.0
	var hx1 := sample_height(cell, track, x + delta, z)
	var hx0 := sample_height(cell, track, x - delta, z)
	var hz1 := sample_height(cell, track, x, z + delta)
	var hz0 := sample_height(cell, track, x, z - delta)
	var gx := (hx1 - hx0) / (2.0 * delta)
	var gz := (hz1 - hz0) / (2.0 * delta)
	return Vector2(gx, gz).length()
