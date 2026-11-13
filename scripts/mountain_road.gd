extends "res://scripts/mountain/mountain_road_settings.gd"

# Genera da codice una strada di montagna: terreno, sede stradale, guardrail e collider.
# La linea centrale (centerline) puo' essere assegnata da fuori (futuro generatore
# procedurale); se e' vuota viene creata una salita di prova con tornanti.
# Convenzione: l'auto a rotazione zero guarda verso +Z, quindi il percorso parte verso +Z.

## Emesso una sola volta quando il veicolo (la sfera) attraversa il traguardo.
signal finish_reached(body: Node3D)

const CHECKPOINT_COUNT := 8

## Modello del tile traguardo delle mappe a tile: da qui si estrae solo l'arco.
const GATE_SCENE := preload("res://models/track-finish.glb")

const TrackSampler := preload("res://scripts/mountain/track_sampler.gd")
const BuildData := preload("res://scripts/mountain/track_build_data.gd")
const TrackLots := preload("res://scripts/mountain/track_lots.gd")
const TerrainBuilder := preload("res://scripts/mountain/terrain_builder.gd")
const RoadBuilder := preload("res://scripts/mountain/road_builder.gd")
const GuardrailBuilder := preload("res://scripts/mountain/guardrail_builder.gd")
const VegetationBuilder := preload("res://scripts/mountain/vegetation_builder.gd")
const NatureKitBuilder := preload("res://scripts/mountain/nature_kit_builder.gd")

var centerline: PackedVector3Array = PackedVector3Array()
## Posizione e orientamento (asse +Z = direzione di marcia) del primo e dell'ultimo punto,
## nello spazio locale di questo nodo.
var start_transform := Transform3D.IDENTITY
var finish_transform := Transform3D.IDENTITY
var _finished := false
var _next_checkpoint := 0


func build() -> void:
	var t0 := Time.get_ticks_msec()
	_finished = false
	_next_checkpoint = 0
	if path != null:
		centerline = TrackSampler.from_path(path, global_transform, step_length)
	if centerline.size() < 2:
		centerline = make_test_centerline()
	for c in get_children():
		c.queue_free()
	var last := centerline.size() - 1
	start_transform = Transform3D(basis_at(0), centerline[0])
	finish_transform = Transform3D(basis_at(last), centerline[last])
	var track := BuildData.new()
	track.centerline = centerline
	TrackLots.prepare(self, track)
	TerrainBuilder.build(self, track)
	RoadBuilder.build(self, track)
	TrackLots.build(self, track)
	GuardrailBuilder.build(self, track)
	_build_timing_gates()
	if enable_gates:
		_build_gates()
	if enable_vegetation:
		VegetationBuilder.build(self, track)
	if enable_nature_kit:
		NatureKitBuilder.build(self, track)
	print("[MountainRoad] %d campioni, costruita in %d ms" % [centerline.size(), Time.get_ticks_msec() - t0])
	TrackSampler.print_stats(centerline)


# The invisible gates enforce an ordered run through the course before the finish.
func _build_timing_gates() -> void:
	var finish_index := centerline.size() - 2
	for checkpoint in CHECKPOINT_COUNT:
		var index := roundi(float(finish_index) * (checkpoint + 1) / (CHECKPOINT_COUNT + 1))
		_add_timing_gate(index, checkpoint)
	_add_timing_gate(finish_index, CHECKPOINT_COUNT)


func _add_timing_gate(index: int, checkpoint: int) -> void:
	var area := Area3D.new()
	area.name = "FinishArea" if checkpoint == CHECKPOINT_COUNT else "Checkpoint%d" % (checkpoint + 1)
	area.collision_layer = 0
	area.collision_mask = 8
	var basis := basis_at(index)
	area.transform = Transform3D(basis, centerline[index] + Vector3(0.0, 1.25, 0.0))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(road_width + 0.5, 2.8, 1.25)
	cs.shape = box
	area.add_child(cs)
	area.body_entered.connect(_on_timing_gate_entered.bind(checkpoint, basis.z))
	add_child(area)


func _on_timing_gate_entered(body: Node3D, checkpoint: int, forward: Vector3) -> void:
	if _finished or checkpoint != _next_checkpoint or not (body is RigidBody3D):
		return
	if body.linear_velocity.dot(forward) <= 0.0:
		return
	_next_checkpoint += 1
	if checkpoint == CHECKPOINT_COUNT:
		_finished = true
		finish_reached.emit(body)


# Archi di partenza e arrivo: stessa posizione delle strisce (partenza campione 1, traguardo
# penultimo campione). Il modello e' largo 14 m con i piedi a +-5..7 m dall'asse, quindi
# sta fuori dai guardrail (che arrivano a ~3.7 m) e non serve nessun collider.
func _build_gates() -> void:
	var mesh := _make_gate_mesh()
	if mesh == null:
		return
	var n := centerline.size()
	_add_gate("StartGate", mini(1, n - 1), mesh)
	_add_gate("FinishGate", maxi(n - 2, 0), mesh)


func _add_gate(node_name: String, i: int, mesh: ArrayMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	var b := basis_at(i).scaled(Vector3.ONE * gate_scale)
	mi.transform = Transform3D(b, centerline[i] + Vector3(0.0, road_lift - asphalt_drop - gate_sink, 0.0))
	add_child(mi)


# track-finish.glb e' un tile intero (strada 10x10 m + arco). Qui si tengono solo i triangoli
# dell'arco, cosi' non compare il pezzo di strada piatta sopra la nostra strada in pendenza.
func _make_gate_mesh() -> ArrayMesh:
	var root := GATE_SCENE.instantiate()
	var src: MeshInstance3D = root as MeshInstance3D
	if src == null:
		var found := root.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			src = found[0] as MeshInstance3D
	if src == null or src.mesh == null or src.mesh.get_surface_count() == 0:
		push_warning("MountainRoad: nessuna mesh in track-finish.glb, archi non creati")
		root.free()
		return null
	var arrays := src.mesh.surface_get_arrays(0)
	var material := src.mesh.surface_get_material(0)
	root.free()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for t in range(0, idx.size() - 2, 3):
		if _is_gate_triangle(verts[idx[t]], verts[idx[t + 1]], verts[idx[t + 2]]):
			kept.append(idx[t])
			kept.append(idx[t + 1])
			kept.append(idx[t + 2])
	if kept.is_empty():
		push_warning("MountainRoad: filtro dell'arco senza triangoli, archi non creati")
		return null
	arrays[Mesh.ARRAY_INDEX] = kept
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


# L'arco occupa |z| <= 1.5 (il tile arriva a 5) e, nella fascia |x| <= 5, sta sopra 0.8 m
# (l'asfalto del tile e' sotto 0.1 m, i bordi a 0.75 m). I piedi sono a |x| > 5.
func _is_gate_triangle(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var max_z := maxf(absf(a.z), maxf(absf(b.z), absf(c.z)))
	if max_z > 1.6:
		return false
	var max_x := maxf(absf(a.x), maxf(absf(b.x), absf(c.x)))
	var max_y := maxf(a.y, maxf(b.y, c.y))
	return max_x > 5.05 or max_y > 0.8


func basis_at(i: int) -> Basis:
	return TrackSampler.basis_at(centerline, i)


func make_test_centerline() -> PackedVector3Array:
	return TrackSampler.make_test_centerline(self)
