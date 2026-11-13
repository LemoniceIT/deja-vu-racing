extends RefCounted

const BuildData := preload("res://scripts/mountain/track_build_data.gd")
const Settings := preload("res://scripts/mountain/mountain_road_settings.gd")
const TrackMesh := preload("res://scripts/mountain/track_mesh.gd")
const TrackSampler := preload("res://scripts/mountain/track_sampler.gd")

const ROAD_STRIPS := 16


static func build(road: Settings, track: BuildData) -> void:
	var hw := road.road_width * 0.5
	var n := track.centerline.size()
	# The collision surface follows the asphalt mesh at a fixed height offset.
	var vis := Vector3(0.0, road.road_lift - road.asphalt_drop, 0.0)
	var collision_offset := Vector3.UP * road.asphalt_drop
	var l := PackedVector3Array()
	var r := PackedVector3Array()
	for i in n:
		var s := TrackSampler.side(track.centerline, i)
		l.append(track.centerline[i] + vis - s * hw)
		r.append(track.centerline[i] + vis + s * hw)
	var down := Vector3(0.0, -0.5, 0.0)

	var asphalt := SurfaceTool.new()
	asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var marks := SurfaceTool.new()
	marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collision := SurfaceTool.new()
	collision.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		var s := TrackSampler.side(track.centerline, i)
		# A sloped bend twists between cross sections. Use narrow strips so
		# the diagonal between two triangles does not create a ridge across the lane.
		for strip in ROAD_STRIPS:
			var low := float(strip) / ROAD_STRIPS
			var high := float(strip + 1) / ROAD_STRIPS
			var a0 := l[i].lerp(r[i], low)
			var a1 := l[i + 1].lerp(r[i + 1], low)
			var b1 := l[i + 1].lerp(r[i + 1], high)
			var b0 := l[i].lerp(r[i], high)
			TrackMesh.quad(asphalt, a0, a1, b1, b0, Vector3.UP, road.asphalt_color)
			TrackMesh.quad(collision, a0 + collision_offset, a1 + collision_offset,
				b1 + collision_offset, b0 + collision_offset, Vector3.UP, road.asphalt_color)
		TrackMesh.quad(asphalt, l[i], l[i + 1], l[i + 1] + down, l[i] + down, -s, road.asphalt_color)
		TrackMesh.quad(asphalt, r[i], r[i + 1], r[i + 1] + down, r[i] + down, s, road.asphalt_color)
		# Amber center line and white edge lines to mark the narrow pass.
		var lift := Vector3(0.0, 0.02, 0.0)
		var a := track.centerline[i] + vis + lift
		var b := track.centerline[i + 1] + vis + lift
		var next_side := TrackSampler.side(track.centerline, i + 1)
		_road_line(road, marks, a, b, s, next_side, 0.0, 0.08, Color(0.94, 0.64, 0.25))
		_road_line(road, marks, a, b, s, next_side, hw - 0.16, 0.045, road.line_color)
		_road_line(road, marks, a, b, s, next_side, -hw + 0.16, 0.045, road.line_color)
	# partenza: striscia verde; traguardo: scacchiera
	_checker(road, track, marks, mini(1, n - 1), 0.8, 1, 1, Color(0.2, 0.75, 0.3), Color(0.2, 0.75, 0.3), 0.02)
	_checker(road, track, marks, maxi(n - 2, 0), 2.0, 8, 2, Color.WHITE, Color(0.08, 0.08, 0.08), 0.025)
	asphalt.generate_normals()
	marks.generate_normals()
	TrackMesh.add_visual(road, asphalt.commit(), "Road")
	TrackMesh.add_visual(road, marks.commit(), "RoadMarks")
	TrackMesh.add_collider(road, collision.commit(), "Road", road.road_friction)


static func _road_line(road: Settings, st: SurfaceTool, a: Vector3, b: Vector3, side: Vector3, next_side: Vector3, offset: float, half_width: float, color: Color) -> void:
	var low := offset - half_width
	var high := offset + half_width
	TrackMesh.quad(st, a + side * low, b + next_side * low, b + next_side * high, a + side * high, Vector3.UP, color)


# Griglia di celle (cols x rows) sulla carreggiata, centrata nel campione i e lunga "length" metri.
static func _checker(road: Settings, track: BuildData, st: SurfaceTool, i: int, length: float, cols: int, rows: int, col_a: Color, col_b: Color, lift: float) -> void:
	var c0 := track.centerline[i] + Vector3(0.0, road.road_lift - road.asphalt_drop + lift, 0.0)
	var t := (track.centerline[mini(i + 1, track.centerline.size() - 1)] - track.centerline[maxi(i - 1, 0)]).normalized()
	var s := TrackSampler.side(track.centerline, i)
	var hw := road.road_width * 0.5
	for r in rows:
		var a0 := -length * 0.5 + length * float(r) / float(rows)
		var a1 := -length * 0.5 + length * float(r + 1) / float(rows)
		for k in cols:
			var l0 := -hw + road.road_width * float(k) / float(cols)
			var l1 := -hw + road.road_width * float(k + 1) / float(cols)
			var col := col_a if (r + k) % 2 == 0 else col_b
			TrackMesh.quad(st, c0 + t * a0 + s * l0, c0 + t * a1 + s * l0, c0 + t * a1 + s * l1, c0 + t * a0 + s * l1, Vector3.UP, col)
