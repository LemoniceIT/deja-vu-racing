extends Node

const PAUSE_MENU := preload("res://scripts/pause_menu.gd")
const RECORDS := preload("res://scripts/circuit_records.gd")
const PROGRESSION := preload("res://scripts/progression.gd")
const GHOST := preload("res://scripts/ghost_recorder.gd")
const GRAPHICS := preload("res://scripts/graphics_settings.gd")
const CATALOG := preload("res://scripts/vehicle_catalog.gd")
const UI_FONT := preload("res://assets/kenney_ui-pack-space-expansion/Font/Kenney Future Narrow.ttf")

const LAPS := 3
const START_FINISH := Vector3(3.5, 0.0, 5.0)
const START_FINISH_RADIUS := 6.5
const REARM_RADIUS := 11.0
const MIN_LAP_SECONDS := 8.0

var vehicle: Node
var time_s: float = 0.0
var lap_started: float = 0.0
var lap_times: Array = []
var lap_armed: bool = false
var was_inside_start: bool = true
var finished: bool = false
var race_active: bool = false
var hud: Label
var ghost_status: Label
var ghost_visual: Node3D
var ghost_data: Array = []
var frames: Array = []
var sample_accum: float = 0.0

func _ready() -> void:
	var pause := PAUSE_MENU.new()
	pause.name = "PauseMenu"
	get_parent().add_child(pause)

	vehicle = get_parent().get_node_or_null("Vehicle")
	if vehicle == null:
		push_error("Circuit: VehicleSelectable not found")
		return

	vehicle.set("controls_locked", true)
	_make_hud()
	_make_start_finish_marker()
	_load_ghost.call_deferred()
	_start_countdown.call_deferred()

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

	for text_value in ["TIME ATTACK", "3", "2", "1", "GO!"]:
		label.text = text_value
		await get_tree().create_timer(0.75).timeout

	canvas.queue_free()
	vehicle.set("controls_locked", false)
	time_s = 0.0
	lap_started = 0.0
	race_active = true

func _make_start_finish_marker() -> void:
	var marker := MeshInstance3D.new()
	marker.name = "CircuitStartFinish"
	var mesh := CylinderMesh.new()
	mesh.top_radius = START_FINISH_RADIUS
	mesh.bottom_radius = START_FINISH_RADIUS
	mesh.height = 0.12
	marker.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.9, 0.95, 0.58)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	marker.position = START_FINISH + Vector3.UP * 0.18
	get_parent().add_child(marker)

func _load_ghost() -> void:
	var settings := GRAPHICS.load_settings()
	if not bool(settings.get("ghost", true)):
		ghost_status.text = "GHOST: OFF"
		return

	var best := GHOST.load_best("circuit_best_lap", CATALOG.get_selected_id())
	var raw: Variant = best.get("frames", [])
	if raw is Array:
		ghost_data = raw

	if ghost_data.is_empty():
		ghost_status.text = "GHOST: NO BEST LAP YET"
		return

	_make_ghost()
	ghost_status.text = "GHOST: BEST LAP"

func _make_ghost() -> void:
	var source_model := vehicle.get_node_or_null("Container/Model") as Node3D
	if source_model == null:
		ghost_status.text = "GHOST: MODEL UNAVAILABLE"
		return

	ghost_visual = Node3D.new()
	ghost_visual.name = "BestLapGhost"
	get_parent().add_child(ghost_visual)

	var model_copy := source_model.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
	if model_copy == null:
		ghost_status.text = "GHOST: MODEL COPY FAILED"
		return
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

func _physics_process(delta: float) -> void:
	if finished or not race_active or vehicle == null or vehicle.get("sphere") == null:
		return

	time_s += delta
	var sphere := vehicle.get("sphere") as RigidBody3D
	if sphere == null:
		return
	var position := sphere.global_position
	var start_distance := Vector2(position.x - START_FINISH.x, position.z - START_FINISH.z).length()
	var inside_start := start_distance <= START_FINISH_RADIUS

	# A lap is armed only after the car has clearly left the start/finish area.
	# This prevents spawn jitter or circling near the line from creating fake laps.
	if not lap_armed and start_distance >= REARM_RADIUS:
		lap_armed = true

	if lap_armed and inside_start and not was_inside_start and time_s - lap_started >= MIN_LAP_SECONDS:
		var completed_lap_time: float = time_s - lap_started
		lap_times.append(completed_lap_time)
		_commit_lap_ghost(completed_lap_time)
		lap_started = time_s
		lap_armed = false
		frames.clear()
		sample_accum = 0.0
		if lap_times.size() >= LAPS:
			_finish()

	was_inside_start = inside_start

	sample_accum += delta
	if sample_accum >= GHOST.SAMPLE_INTERVAL and frames.size() < GHOST.MAX_SAMPLES:
		sample_accum = 0.0
		frames.append({"t": time_s - lap_started, "transform": (vehicle.get("vehicle_model") as Node3D).global_transform})

	_update_ghost()
	_update_hud()

func _commit_lap_ghost(lap_time: float) -> void:
	if frames.is_empty():
		return
	var car := CATALOG.get_selected_id()
	var saved := GHOST.save_best("circuit_best_lap", car, lap_time, frames)
	if saved:
		ghost_data = frames.duplicate(true)
		if ghost_visual == null:
			_make_ghost()
		ghost_status.text = "GHOST: BEST LAP %.2f s" % lap_time

func _update_ghost() -> void:
	if ghost_visual == null or ghost_data.is_empty():
		return
	var lap_elapsed: float = maxf(time_s - lap_started, 0.0)
	var index: int = clampi(int(lap_elapsed / GHOST.SAMPLE_INTERVAL), 0, ghost_data.size() - 1)
	var frame: Variant = ghost_data[index]
	if frame is Dictionary and frame.has("transform"):
		ghost_visual.global_transform = frame["transform"]

func _update_hud() -> void:
	if hud == null:
		return
	var current_lap: int = mini(lap_times.size() + 1, LAPS)
	hud.text = "LAP %d/%d     TIME %02d:%05.2f" % [
		current_lap,
		LAPS,
		int(time_s / 60.0),
		fmod(time_s, 60.0)
	]

func _finish() -> void:
	finished = true
	race_active = false

	var car := CATALOG.get_selected_id()
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
	result.text = "%s  •  %02d:%05.2f  •  LOCAL RANK #%d" % [
		progression["medal"],
		int(time_s / 60.0),
		fmod(time_s, 60.0),
		int(ranking["rank"])
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
	ghost_note.text = "BEST LAP GHOST UPDATED" if bool(GRAPHICS.load_settings().get("ghost", true)) else "GHOST DISABLED IN OPTIONS"
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
