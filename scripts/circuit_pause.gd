extends Node

const PAUSE_MENU := preload("res://scripts/pause_menu.gd")
const RECORDS := preload("res://scripts/circuit_records.gd")
const PROGRESSION := preload("res://scripts/progression.gd")
const GHOST := preload("res://scripts/ghost_recorder.gd")
const GRAPHICS := preload("res://scripts/graphics_settings.gd")
const UI_FONT := preload("res://assets/kenney_ui-pack-space-expansion/Font/Kenney Future Narrow.ttf")

const LAPS := 3
const GATE_HALF_WIDTH := 3.0
# GridMap cells in driving order. Each shared edge is a timing gate.
# Gate 0 is just ahead of the starting position and doubles as the finish.
const ROUTE := [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3),
	Vector2i(1, 2), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 0), Vector2i(2, -1),
	Vector2i(3, -1), Vector2i(3, -2), Vector2i(2, -2), Vector2i(2, -3), Vector2i(3, -3),
	Vector2i(3, -4), Vector2i(2, -4), Vector2i(2, -5), Vector2i(3, -5), Vector2i(3, -6),
	Vector2i(3, -7), Vector2i(2, -7), Vector2i(2, -8), Vector2i(1, -8), Vector2i(1, -7),
	Vector2i(0, -7), Vector2i(-1, -7), Vector2i(-2, -7), Vector2i(-2, -8), Vector2i(-2, -9),
	Vector2i(-3, -9), Vector2i(-4, -9), Vector2i(-5, -9), Vector2i(-6, -9), Vector2i(-6, -8),
	Vector2i(-5, -8), Vector2i(-5, -7), Vector2i(-4, -7), Vector2i(-3, -7), Vector2i(-3, -6),
	Vector2i(-4, -6), Vector2i(-5, -6), Vector2i(-6, -6), Vector2i(-7, -6), Vector2i(-7, -5),
	Vector2i(-7, -4), Vector2i(-6, -4), Vector2i(-6, -3), Vector2i(-6, -2), Vector2i(-6, -1),
	Vector2i(-6, 0), Vector2i(-6, 1), Vector2i(-6, 2), Vector2i(-5, 2), Vector2i(-4, 2),
	Vector2i(-3, 2), Vector2i(-2, 2), Vector2i(-2, 1), Vector2i(-2, 0), Vector2i(-2, -1),
	Vector2i(-3, -1), Vector2i(-3, -2), Vector2i(-3, -3), Vector2i(-2, -3), Vector2i(-1, -3),
	Vector2i(0, -3), Vector2i(0, -2), Vector2i(0, -1),
]

var vehicle: VehicleSelectable
var time_s: float = 0.0
var lap_started: float = 0.0
var lap_times: Array = []
var timing_started := false
var next_gate := 0
var gate_centers := PackedVector2Array()
var gate_forwards := PackedVector2Array()
var previous_position: Vector2
var race_active: bool = false
var hud: Label
var ghost_status: Label
var ghost_enabled := true
var ghost_time := INF
var ghost_visual: Node3D
var ghost_data: Array = []
var ghost_frame := 0
var frames: Array = []

func _ready() -> void:
	_initialize.call_deferred()

func _initialize() -> void:
	var pause := PAUSE_MENU.new()
	pause.name = "PauseMenu"
	get_parent().add_child(pause)

	vehicle = get_parent().get_node_or_null("Vehicle") as VehicleSelectable
	if vehicle == null:
		push_error("Circuit: VehicleSelectable not found")
		return

	process_physics_priority = 1
	vehicle.controls_locked = true
	_build_gates(get_parent().get_node("GridMap"))
	_make_hud()
	_make_start_finish_marker()
	_load_ghost()
	_start_countdown()

func _make_hud() -> void:
	hud = get_parent().get_node_or_null("HUD/TimeAttackPanel/VBox/Status") as Label
	ghost_status = get_parent().get_node_or_null("HUD/TimeAttackPanel/VBox/GhostStatus") as Label
	if hud == null or ghost_status == null:
		push_error("Circuit: static Time Attack HUD nodes are missing from main.tscn")
		return
	_update_hud()

func _start_countdown() -> void:
	race_active = false
	var canvas := CanvasLayer.new()
	canvas.name = "TimeAttackCountdown"
	canvas.layer = 30
	get_parent().add_child(canvas)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var label := Label.new()
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 70)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(label)

	for text_value in ["TIME ATTACK", "3", "2", "1"]:
		label.text = text_value
		await get_tree().create_timer(0.75, false).timeout

	label.text = "GO!"
	vehicle.controls_locked = false
	previous_position = _vehicle_position()
	race_active = true
	await get_tree().create_timer(0.75, false).timeout
	canvas.queue_free()

func _build_gates(grid: GridMap) -> void:
	for index in ROUTE.size():
		var cell: Vector2i = ROUTE[index]
		var following: Vector2i = ROUTE[(index + 1) % ROUTE.size()]
		var a := grid.to_global(grid.map_to_local(Vector3i(cell.x, 0, cell.y)))
		var b := grid.to_global(grid.map_to_local(Vector3i(following.x, 0, following.y)))
		var center := (a + b) * 0.5
		gate_centers.append(Vector2(center.x, center.z))
		gate_forwards.append(Vector2(b.x - a.x, b.z - a.z).normalized())

func _make_start_finish_marker() -> void:
	var marker := MeshInstance3D.new()
	marker.name = "CircuitStartFinish"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(GATE_HALF_WIDTH * 2.0, 0.04, 0.22)
	marker.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.9, 0.95, 0.58)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	marker.position = Vector3(gate_centers[0].x, 0.06, gate_centers[0].y)
	get_parent().add_child(marker)

func _load_ghost() -> void:
	ghost_enabled = bool(GRAPHICS.load_settings().get("ghost", true))
	if ghost_status == null:
		return
	if not ghost_enabled:
		ghost_status.text = "GHOST: OFF"
		return

	var best := GHOST.load_best(RECORDS.TRACK_ID, vehicle.selected_vehicle_id)
	ghost_data = best.get("frames", [])
	ghost_time = best.get("time", INF)

	if ghost_data.is_empty():
		ghost_status.text = "GHOST: NO BEST LAP YET"
		return

	if _make_ghost():
		ghost_status.text = "GHOST: BEST LAP %.2f s" % ghost_time

func _make_ghost() -> bool:
	var model_copy := vehicle.vehicle_model.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
	if model_copy == null:
		ghost_status.text = "GHOST: MODEL COPY FAILED"
		return false

	ghost_visual = Node3D.new()
	ghost_visual.name = "BestLapGhost"
	ghost_visual.hide()
	get_parent().add_child(ghost_visual)
	model_copy.transform = Transform3D.IDENTITY
	ghost_visual.add_child(model_copy)

	for item in model_copy.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := item as MeshInstance3D
		if mesh_instance == null:
			continue
		var ghost_mat := StandardMaterial3D.new()
		ghost_mat.albedo_color = Color(0.12, 0.88, 1.0, 0.34)
		ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost_mat.no_depth_test = false
		mesh_instance.material_override = ghost_mat
	return true

func _physics_process(delta: float) -> void:
	if not race_active:
		return

	var position := _vehicle_position()
	var from := previous_position
	previous_position = position
	if timing_started:
		time_s += delta
	var crossing := _gate_crossing(next_gate % gate_centers.size(), from, position)
	if crossing >= 0.0:
		var after_crossing := delta * (1.0 - crossing)
		if not timing_started:
			timing_started = true
			time_s = after_crossing
			_begin_lap(0.0)
		elif next_gate == gate_centers.size():
			var finish_time := time_s - after_crossing
			var lap_time := finish_time - lap_started
			lap_times.append(lap_time)
			_commit_lap_ghost(lap_time)
			if lap_times.size() == LAPS:
				time_s = finish_time
				_update_hud()
				_finish()
				return
			_begin_lap(finish_time)
		else:
			next_gate += 1
	elif next_gate > 1 and _gate_crossing(next_gate - 1, position, from) >= 0.0:
		# Undo the most recent checkpoint when the car backs through it.
		next_gate -= 1

	if timing_started and frames.size() < GHOST.MAX_SAMPLES - 1:
		var elapsed := time_s - lap_started
		if elapsed - float(frames.back()["t"]) >= GHOST.SAMPLE_INTERVAL:
			_add_ghost_sample(elapsed)

	_update_ghost()
	_update_hud()

func _vehicle_position() -> Vector2:
	var position := vehicle.sphere.global_position
	return Vector2(position.x, position.z)

func _gate_crossing(index: int, from: Vector2, to: Vector2) -> float:
	var forward := gate_forwards[index]
	var relative_from := from - gate_centers[index]
	var relative_to := to - gate_centers[index]
	var before := relative_from.dot(forward)
	var after := relative_to.dot(forward)
	if before > 0.0 or after <= 0.0:
		return -1.0
	var fraction := -before / (after - before)
	var lateral := relative_from.lerp(relative_to, fraction).cross(forward)
	return fraction if absf(lateral) <= GATE_HALF_WIDTH else -1.0

func _begin_lap(start_time: float) -> void:
	next_gate = 1
	lap_started = start_time
	ghost_frame = 0
	frames.clear()
	_add_ghost_sample(0.0)

func _add_ghost_sample(elapsed: float) -> void:
	frames.append({"t": elapsed, "transform": vehicle.vehicle_model.global_transform})

func _commit_lap_ghost(lap_time: float) -> void:
	if frames.size() >= GHOST.MAX_SAMPLES - 1:
		return
	if lap_time > float(frames.back()["t"]):
		_add_ghost_sample(lap_time)
	if not GHOST.save_best(RECORDS.TRACK_ID, vehicle.selected_vehicle_id, lap_time, frames):
		return
	ghost_time = lap_time
	if ghost_enabled and ghost_status != null and (ghost_visual != null or _make_ghost()):
		ghost_data = frames.duplicate()
		ghost_status.text = "GHOST: BEST LAP %.2f s" % lap_time

func _update_ghost() -> void:
	if ghost_visual == null or ghost_data.is_empty() or not timing_started:
		return
	var elapsed := time_s - lap_started
	ghost_visual.visible = elapsed <= ghost_time
	if not ghost_visual.visible:
		return
	while ghost_frame + 1 < ghost_data.size() - 1 and float(ghost_data[ghost_frame + 1]["t"]) < elapsed:
		ghost_frame += 1
	var a: Dictionary = ghost_data[ghost_frame]
	var b: Dictionary = ghost_data[ghost_frame + 1]
	var weight := clampf(inverse_lerp(float(a["t"]), float(b["t"]), elapsed), 0.0, 1.0)
	var start_transform: Transform3D = a["transform"]
	ghost_visual.global_transform = start_transform.interpolate_with(b["transform"], weight)

func _update_hud() -> void:
	if hud == null:
		return
	if not timing_started:
		hud.text = "CROSS THE START LINE"
		return
	var current_lap: int = mini(lap_times.size() + 1, LAPS)
	hud.text = "LAP %d/%d     TIME %02d:%05.2f     CP %d/%d" % [
		current_lap,
		LAPS,
		int(time_s / 60.0),
		fmod(time_s, 60.0),
		next_gate - 1,
		gate_centers.size() - 1,
	]

func _finish() -> void:
	race_active = false
	vehicle.controls_locked = true

	if ghost_visual != null:
		ghost_visual.hide()
	var car := vehicle.selected_vehicle_id
	var ranking := RECORDS.record(car, time_s, lap_times)
	var progression := PROGRESSION.record("circuit", car, time_s)

	var canvas := CanvasLayer.new()
	canvas.layer = 30
	add_child(canvas)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(dim)

	var panel := CenterContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "TIME ATTACK COMPLETE"
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 38)
	box.add_child(title)

	var result := Label.new()
	var rank := int(ranking["rank"])
	var rank_text := "LOCAL RANK #%d" % rank if rank > 0 else "OUTSIDE LOCAL TOP 10"
	if not ranking["saved"]:
		rank_text = "LOCAL RECORD NOT SAVED"
	result.text = "%s  •  %02d:%05.2f  •  %s" % [
		progression["medal"],
		int(time_s / 60.0),
		fmod(time_s, 60.0),
		rank_text,
	]
	result.add_theme_font_override("font", UI_FONT)
	result.add_theme_font_size_override("font_size", 24)
	box.add_child(result)

	for i in lap_times.size():
		var row := Label.new()
		row.text = "LAP %d: %.2f s" % [i + 1, float(lap_times[i])]
		row.add_theme_font_override("font", UI_FONT)
		row.add_theme_font_size_override("font_size", 20)
		box.add_child(row)

	var ghost_note := Label.new()
	ghost_note.text = ghost_status.text if ghost_status != null else ""
	ghost_note.add_theme_font_override("font", UI_FONT)
	box.add_child(ghost_note)

	var restart := Button.new()
	restart.text = "RESTART"
	restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	box.add_child(restart)

	var menu := Button.new()
	menu.text = "MAIN MENU"
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	box.add_child(menu)
