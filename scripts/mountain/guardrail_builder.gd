extends RefCounted

const BuildData := preload("res://scripts/mountain/track_build_data.gd")
const Settings := preload("res://scripts/mountain/mountain_road_settings.gd")
const TrackMesh := preload("res://scripts/mountain/track_mesh.gd")
const TrackSampler := preload("res://scripts/mountain/track_sampler.gd")


static func build(road: Settings, track: BuildData) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # ombreggiatura piatta
	var n := track.centerline.size()
	var in_off := road.road_width * 0.5 + road.rail_offset
	var out_off := in_off + road.rail_thickness
	for sgn: float in [-1.0, 1.0]:
		var prof: Array = []
		for i in n:
			var c := track.centerline[i]
			var s := TrackSampler.side(track.centerline, i) * sgn
			var lo := c.y - 0.3
			var hi := c.y + road.rail_height
			var cin := c + s * in_off
			var cout := c + s * out_off
			prof.append([
				Vector3(cin.x, lo, cin.z), Vector3(cin.x, hi, cin.z),
				Vector3(cout.x, hi, cout.z), Vector3(cout.x, lo, cout.z)])
		for i in n - 1:
			var p: Array = prof[i]
			var q: Array = prof[i + 1]
			var s_out := TrackSampler.side(track.centerline, i) * sgn
			TrackMesh.quad(st, p[0], p[1], q[1], q[0], -s_out, road.rail_color)
			TrackMesh.quad(st, p[1], p[2], q[2], q[1], Vector3.UP, road.rail_color)
			TrackMesh.quad(st, p[2], p[3], q[3], q[2], s_out, road.rail_color)
	st.generate_normals()
	if road.enable_guardrails:
		# muro invisibile (stesso collider di prima) + guardrail solo visivo
		TrackMesh.add_collider(road, st.commit(), "Rails", road.rail_friction)
		_build_guardrail_visual(road, track)
	else:
		TrackMesh.add_mesh_body(road, st.commit(), "Rails", road.rail_friction)


# --- Guardrail ----------------------------------------------------------------------
# Barra a "W" su pali, al posto del muro pieno. Solo visivo: il muro (invisibile) resta
# il collider, quindi la fisica e le prestazioni di guida non cambiano.
static func _build_guardrail_visual(road: Settings, track: BuildData) -> void:
	var beam := SurfaceTool.new()
	beam.begin(Mesh.PRIMITIVE_TRIANGLES)
	beam.set_smooth_group(-1)
	var posts := SurfaceTool.new()
	posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	posts.set_smooth_group(-1)
	var refl := SurfaceTool.new()
	refl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := track.centerline.size()
	var base := road.road_width * 0.5 + road.rail_offset  # faccia della barra rivolta alla strada
	# profilo a W: x = distanza verso l'esterno, y = quota sopra la strada
	var prof: Array[Vector2] = [
		Vector2(0.0, 0.35), Vector2(0.07, 0.46), Vector2(0.0, 0.57),
		Vector2(0.07, 0.68), Vector2(0.0, 0.80)]
	var back_u := 0.10
	var top_h := prof[prof.size() - 1].y
	var bot_h := prof[0].y
	var dark := road.rail_color.darkened(0.25)
	var post_n := 0
	for sgn: float in [-1.0, 1.0]:
		var refl_col := Color(1.0, 0.95, 0.8) if sgn < 0.0 else Color(1.0, 0.55, 0.1)
		for i in n - 1:
			var s0 := TrackSampler.side(track.centerline, i) * sgn
			var s1 := TrackSampler.side(track.centerline, i + 1) * sgn
			var c0 := track.centerline[i]
			var c1 := track.centerline[i + 1]
			for k in prof.size() - 1:
				var a := prof[k]
				var b := prof[k + 1]
				# normale del segmento di profilo, rivolta verso la strada (u negativo)
				var nu := -(b.y - a.y)
				var nh := b.x - a.x
				var facing := s0 * nu + Vector3.UP * nh
				TrackMesh.quad(beam,
					c0 + s0 * (base + a.x) + Vector3.UP * a.y,
					c1 + s1 * (base + a.x) + Vector3.UP * a.y,
					c1 + s1 * (base + b.x) + Vector3.UP * b.y,
					c0 + s0 * (base + b.x) + Vector3.UP * b.y,
					facing, road.rail_color)
			# bordo superiore, inferiore e retro
			TrackMesh.quad(beam,
				c0 + s0 * (base + 0.0) + Vector3.UP * top_h, c1 + s1 * (base + 0.0) + Vector3.UP * top_h,
				c1 + s1 * (base + back_u) + Vector3.UP * top_h, c0 + s0 * (base + back_u) + Vector3.UP * top_h,
				Vector3.UP, road.rail_color.lightened(0.1))
			TrackMesh.quad(beam,
				c0 + s0 * (base + 0.0) + Vector3.UP * bot_h, c1 + s1 * (base + 0.0) + Vector3.UP * bot_h,
				c1 + s1 * (base + back_u) + Vector3.UP * bot_h, c0 + s0 * (base + back_u) + Vector3.UP * bot_h,
				Vector3.DOWN, dark)
			TrackMesh.quad(beam,
				c0 + s0 * (base + back_u) + Vector3.UP * bot_h, c1 + s1 * (base + back_u) + Vector3.UP * bot_h,
				c1 + s1 * (base + back_u) + Vector3.UP * top_h, c0 + s0 * (base + back_u) + Vector3.UP * top_h,
				s0, dark)
			if i % road.guard_post_every == 0:
				var t := Vector3(TrackSampler.side(track.centerline, i).z, 0.0, -TrackSampler.side(track.centerline, i).x)  # direzione di marcia
				var foot := c0 + s0 * (base + back_u + 0.07) + Vector3(0.0, -0.6, 0.0)
				_add_box(posts, foot, t, s0, 0.12, 0.12, 0.6 + 0.86, road.post_color)
				if post_n % road.guard_reflector_every == 0:
					# catarifrangente sulla faccia anteriore, a meta' del tratto piu' esterno
					var f := c0 + s0 * (base - 0.012) + Vector3.UP * 0.57
					var ht := t * 0.09
					var hv := Vector3.UP * 0.045
					TrackMesh.quad(refl, f - ht - hv, f + ht - hv, f + ht + hv, f - ht + hv, -s0, refl_col)
				post_n += 1
	beam.generate_normals()
	posts.generate_normals()
	refl.generate_normals()
	TrackMesh.add_visual(road, beam.commit(), "GuardrailBeam")
	TrackMesh.add_visual(road, posts.commit(), "GuardrailPosts")
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.7, 0.35)
	rm.emission_energy_multiplier = road.reflector_glow
	var rmi := MeshInstance3D.new()
	rmi.name = "GuardrailReflectors"
	rmi.mesh = refl.commit()
	rmi.material_override = rm
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	road.add_child(rmi)


# Parallelepipedo con la base centrata in "bottom", lati lungo t (size_t) e s (size_s).
static func _add_box(st: SurfaceTool, bottom: Vector3, t: Vector3, s: Vector3, size_t: float, size_s: float, height: float, col: Color) -> void:
	var ht := t * size_t * 0.5
	var hs := s * size_s * 0.5
	var up := Vector3(0.0, height, 0.0)
	var c00 := bottom - ht - hs
	var c10 := bottom + ht - hs
	var c11 := bottom + ht + hs
	var c01 := bottom - ht + hs
	TrackMesh.quad(st, c00 + up, c10 + up, c11 + up, c01 + up, Vector3.UP, col)
	TrackMesh.quad(st, c00, c10, c10 + up, c00 + up, -s, col)
	TrackMesh.quad(st, c01, c11, c11 + up, c01 + up, s, col)
	TrackMesh.quad(st, c10, c11, c11 + up, c10 + up, t, col)
	TrackMesh.quad(st, c00, c01, c01 + up, c00 + up, -t, col)
