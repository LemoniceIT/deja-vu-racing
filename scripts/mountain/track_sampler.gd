extends RefCounted

const Settings := preload("res://scripts/mountain/mountain_road_settings.gd")


# Legge la curva del Path3D (solo a runtime) e la campiona ogni step_length metri.
static func from_path(path: Path3D, road_transform: Transform3D, step_length: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if path.curve == null or path.curve.point_count < 2:
		push_warning("MountainRoad: il Path3D ha meno di 2 punti, uso il percorso di prova")
		return out
	var c: Curve3D = path.curve.duplicate()
	c.bake_interval = step_length
	var to_local := road_transform.affine_inverse() * path.global_transform
	for p in c.get_baked_points():
		var q := to_local * p
		if out.is_empty() or q.distance_to(out[out.size() - 1]) > 0.5:
			out.append(q)
	return out


# Orientamento nel campione i: l'asse +Z locale guarda nella direzione di marcia
# (l'auto, a rotazione zero, guarda verso +Z).
static func basis_at(centerline: PackedVector3Array, i: int) -> Basis:
	var a := centerline[maxi(i - 1, 0)]
	var b := centerline[mini(i + 1, centerline.size() - 1)]
	return Basis(Vector3.UP, atan2(b.x - a.x, b.z - a.z))


static func print_stats(centerline: PackedVector3Array) -> void:
	var length := 0.0
	var max_grade := 0.0
	for i in range(1, centerline.size()):
		length += Vector2(centerline[i].x - centerline[i - 1].x, centerline[i].z - centerline[i - 1].z).length()
	for i in range(0, centerline.size() - 3):
		var run := Vector2(centerline[i + 3].x - centerline[i].x, centerline[i + 3].z - centerline[i].z).length()
		if run > 0.1:
			max_grade = maxf(max_grade, absf(centerline[i + 3].y - centerline[i].y) / run)
	print("[MountainRoad] percorso: %.2f km, dislivello %.0f m, pendenza max %.0f%%" % [
		length / 1000.0, centerline[centerline.size() - 1].y - centerline[0].y, max_grade * 100.0])


# Percorso di prova: tratto piano, poi salita con tornanti alternati.
static func make_test_centerline(road: Settings) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var steps_straight := int(road.straight_length / road.step_length)
	var steps_turn := int(PI * road.hairpin_radius / road.step_length)
	var segments: Array = []
	var turn_dir := 1.0
	for leg in road.hairpins + 1:
		segments.append([steps_straight, 0.0, road.straight_grade])
		if leg < road.hairpins:
			# curvatura esatta per fare 180 gradi in steps_turn passi
			segments.append([steps_turn, turn_dir * PI / (float(steps_turn) * road.step_length), road.turn_grade])
			turn_dir = -turn_dir
	var pos := Vector3.ZERO
	var heading := 0.0
	var grade := 0.0
	var done := 0
	var flat_steps := int(road.flat_start_length / road.step_length)
	pts.append(pos)
	for seg in segments:
		for i in int(seg[0]):
			heading += float(seg[1]) * road.step_length
			var target := float(seg[2]) if done >= flat_steps else 0.0
			grade = lerpf(grade, target, 0.08)
			pos += Vector3(sin(heading) * road.step_length, grade * road.step_length, cos(heading) * road.step_length)
			pts.append(pos)
			done += 1
	return pts


# Versore orizzontale perpendicolare alla direzione di marcia nel campione i.
static func side(centerline: PackedVector3Array, i: int) -> Vector3:
	var a := centerline[maxi(i - 1, 0)]
	var b := centerline[mini(i + 1, centerline.size() - 1)]
	var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return Vector3(-t.z, 0.0, t.x)
