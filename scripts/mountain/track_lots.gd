extends RefCounted

const BuildData := preload("res://scripts/mountain/track_build_data.gd")
const Settings := preload("res://scripts/mountain/mountain_road_settings.gd")
const TrackMesh := preload("res://scripts/mountain/track_mesh.gd")
const TrackSampler := preload("res://scripts/mountain/track_sampler.gd")


# Piazzali quadrati: il bordo vicino alla strada passa dal primo/ultimo campione e il piazzale
# si estende verso l'esterno (dietro la partenza, oltre il traguardo), centrato sull'asse.
static func prepare(road: Settings, track: BuildData) -> void:
	track.lots.clear()
	if not road.enable_lots:
		return
	var last := track.centerline.size() - 1
	for info in [["StartLot", 0, -1.0], ["FinishLot", last, 1.0]]:
		var dir: Vector3 = TrackSampler.basis_at(track.centerline, info[1]).z * float(info[2])
		track.lots.append({
			"name": info[0],
			"origin": track.centerline[info[1]],
			"dir": dir,
			"side": Vector3(-dir.z, 0.0, dir.x),
		})


# Distanza (in pianta) dal rettangolo del piazzale: 0 se il punto e' dentro.
static func outside_distance(size: float, lot: Dictionary, x: float, z: float) -> float:
	var o: Vector3 = lot["origin"]
	var dir: Vector3 = lot["dir"]
	var side: Vector3 = lot["side"]
	var dx := x - o.x
	var dz := z - o.z
	var u := dx * dir.x + dz * dir.z
	var v := dx * side.x + dz * side.z
	var qu := maxf(maxf(-u, u - size), 0.0)
	var qv := maxf(absf(v) - size * 0.5, 0.0)
	return sqrt(qu * qu + qv * qv)


static func near_lot(size: float, track: BuildData, x: float, z: float, margin: float) -> bool:
	for lot in track.lots:
		if outside_distance(size, lot, x, z) < margin:
			return true
	return false


# Punto del piazzale: u metri verso l'esterno dalla strada, v metri di lato, quota y.
static func _lot_point(lot: Dictionary, u: float, v: float, y: float) -> Vector3:
	var o: Vector3 = lot["origin"]
	var dir: Vector3 = lot["dir"]
	var side: Vector3 = lot["side"]
	return Vector3(o.x + dir.x * u + side.x * v, y, o.z + dir.z * u + side.z * v)


static func build(road: Settings, track: BuildData) -> void:
	for lot in track.lots:
		_build_lot(road, lot)


static func _build_lot(road: Settings, lot: Dictionary) -> void:
	var node_name: String = lot["name"]
	var dir: Vector3 = lot["dir"]
	var side: Vector3 = lot["side"]
	var y0: float = lot["origin"].y
	var yv := y0 + road.road_lift - road.asphalt_drop  # cemento visibile
	var yp := y0 + road.road_lift                 # superficie fisica, come la strada
	var h := road.lot_size * 0.5
	var down := Vector3(0.0, -road.lot_skirt, 0.0)

	var slab := SurfaceTool.new()
	slab.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c00 := _lot_point(lot, 0.0, -h, yv)
	var c10 := _lot_point(lot, road.lot_size, -h, yv)
	var c11 := _lot_point(lot, road.lot_size, h, yv)
	var c01 := _lot_point(lot, 0.0, h, yv)
	TrackMesh.quad(slab, c00, c10, c11, c01, Vector3.UP, road.lot_color)
	TrackMesh.quad(slab, c00, c10, c10 + down, c00 + down, -side, road.lot_color)
	TrackMesh.quad(slab, c01, c11, c11 + down, c01 + down, side, road.lot_color)
	TrackMesh.quad(slab, c10, c11, c11 + down, c10 + down, dir, road.lot_color)
	TrackMesh.quad(slab, c00, c01, c01 + down, c00 + down, -dir, road.lot_color)
	slab.generate_normals()
	TrackMesh.add_visual(road, slab.commit(), node_name)

	# stalli: file lungo i due lati e lungo il lato opposto alla strada
	var marks := SurfaceTool.new()
	marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ym := yv + 0.02
	var stall := 5.0
	var pitch := 3.0
	var margin := 4.0
	var rows := int(floor((road.lot_size - 2.0 * margin) / pitch))
	for sgn: float in [-1.0, 1.0]:
		for k in rows + 1:
			var u := margin + float(k) * pitch
			_lot_line(road, marks, lot, u, sgn * h, u, sgn * (h - stall), ym)
	var cols := int(floor((road.lot_size - 2.0 * (stall + 1.0)) / pitch))
	var v0 := -float(cols) * pitch * 0.5
	for k in cols + 1:
		var v := v0 + float(k) * pitch
		_lot_line(road, marks, lot, road.lot_size, v, road.lot_size - stall, v, ym)
	marks.generate_normals()
	TrackMesh.add_visual(road, marks.commit(), node_name + "Marks")

	# collider piatto alla quota fisica della strada (niente gradino all'ingresso)
	var flat := SurfaceTool.new()
	flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	TrackMesh.quad(flat, _lot_point(lot, 0.0, -h, yp), _lot_point(lot, road.lot_size, -h, yp),
		_lot_point(lot, road.lot_size, h, yp), _lot_point(lot, 0.0, h, yp), Vector3.UP, road.lot_color)
	flat.generate_normals()
	TrackMesh.add_collider(road, flat.commit(), node_name, road.road_friction)


static func _lot_line(road: Settings, st: SurfaceTool, lot: Dictionary, u0: float, v0: float, u1: float, v1: float, y: float) -> void:
	var a := _lot_point(lot, u0, v0, y)
	var b := _lot_point(lot, u1, v1, y)
	var d := (b - a).normalized()
	var m := Vector3(-d.z, 0.0, d.x) * 0.06
	TrackMesh.quad(st, a - m, b - m, b + m, a + m, Vector3.UP, road.lot_line_color)
