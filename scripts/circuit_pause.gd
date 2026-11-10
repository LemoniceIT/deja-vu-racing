extends Node3D

const PAUSE_MENU := preload("res://scripts/pause_menu.gd")
const RECORDS := preload("res://scripts/circuit_records.gd")
const PROGRESSION := preload("res://scripts/progression.gd")
const GHOST := preload("res://scripts/ghost_recorder.gd")
const GRAPHICS := preload("res://scripts/graphics_settings.gd")
const CATALOG := preload("res://scripts/vehicle_catalog.gd")
const UI_FONT := preload("res://assets/kenney_ui-pack-space-expansion/Font/Kenney Future Narrow.ttf")

const LAPS := 3
const CHECKPOINT_RADIUS := 7.0
const MIN_LAP_SECONDS := 8.0
const CHECKPOINTS := [
	Vector3(3.5, 0.0, 5.0),
	Vector3(40.0, 0.0, 5.0),
	Vector3(40.0, 0.0, -35.0),
	Vector3(-30.0, 0.0, -35.0),
	Vector3(-30.0, 0.0, 5.0)
]

var vehicle: VehicleSelectable
var time_s: float = 0.0
var lap_started: float = 0.0
var lap_times: Array = []
var next_gate: int = 1
var was_inside: bool = false
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
	add_child(pause)

	vehicle = get_node_or_null("Vehicle") as VehicleSelectable
	if vehicle == null:
		push_error("Circuit: VehicleSelectable not found")
		return

	_make_hud()
	_make_gates()
	_load_ghost.call_deferred()
	_start_countdown.call_deferred()

func _make_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TimeAttackHUD"
	canvas.layer = 12
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(22, 22)
	panel.custom_minimum_size = Vector2(430, 118)
	canvas.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var title := Label.new()
	title.text = "CIRCUIT TIME ATTACK  •  3 LAPS"
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	hud = Label.new()
	hud.add_theme_font_override("font", UI_FONT)
	hud.add_theme_font_size_override("font_size", 22)
	box.add_child(hud)

	ghost_status = Label.new()
	ghost_status.add_theme_font_override("font", UI_FONT)
	ghost_status.add_theme_font_size_override("font_size", 16)
	ghost_status.text = "GHOST: CHECKING..."
	box.add_child(ghost_status)
	_update_hud()

func _start_countdown() -> void:
	race_active = false
	var canvas := CanvasLayer.new()
	canvas.name = "TimeAttackCountdown"
	canvas.layer = 30
	add_child(canvas)

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
	time_s = 0.0
	lap_started = 0.0
	race_active = true

func _make_gates() -> void:
	for i in CHECKPOINTS.size():
		var marker := MeshInstance3D.new()
		marker.name = "CircuitGate%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = CHECKPOINT_RADIUS
		mesh.bottom_radius = CHECKPOINT_RADIUS
		mesh.height = 0.12
		marker.mesh = mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.9, 0.95, 0.58) if i == 0 else Color(1.0, 0.68, 0.08, 0.48)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = material
		marker.position = CHECKPOINTS[i] + Vector3.UP * 0.18
		add_child(marker)

func _load_ghost() -> void:
	var settings := GRAPHICS.load_settings()
	if not bool(settings.get("ghost", true)):
		ghost_status.text = "GHOST: OFF"
		return

	var best := GHOST.load_best("circuit", CATALOG.get_selected_id())
	var raw: Variant = best.get("frames", [])
	if raw is Array:
		ghost_data = raw

	if ghost_data.is_empty():
		ghost_status.text = "GHOST: NO RECORD YET - FINISH A TIME ATTACK"
		return

	_make_ghost()
	ghost_status.text = "GHOST: BEST RUN"

func _make_ghost() -> void:
	var source_model := vehicle.get_node_or_null("Container/Model") as Node3D
	if source_model == null:
		ghost_status.text = "GHOST: MODEL UNAVAILABLE"
		return

	ghost_visual = Node3D.new()
	ghost_visual.name = "BestRunGhost"
	add_child(ghost_visual)

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
	if finished or not race_active or vehicle == null or vehicle.sphere == null:
		return

	time_s += delta
	var position := vehicle.sphere.global_position
	var target: Vector3 = CHECKPOINTS[next_gate]
	var inside := Vector2(position.x - target.x, position.z - target.z).length() <= CHECKPOINT_RADIUS

	if inside and not was_inside:
		if next_gate == 0:
			if time_s - lap_started >= MIN_LAP_SECONDS:
				lap_times.append(time_s - lap_started)
				lap_started = time_s
				if lap_times.size() >= LAPS:
					_finish()
				else:
					next_gate = 1
		else:
			next_gate = (next_gate + 1) % CHECKPOINTS.size()

	was_inside = inside

	sample_accum += delta
	if sample_accum >= GHOST.SAMPLE_INTERVAL and frames.size() < GHOST.MAX_SAMPLES:
		sample_accum = 0.0
		frames.append({"t": time_s, "transform": vehicle.vehicle_model.global_transform})

	_update_ghost()
	_update_hud()

func _update_ghost() -> void:
	if ghost_visual == null or ghost_data.is_empty():
		return
	var index: int = clampi(int(time_s / GHOST.SAMPLE_INTERVAL), 0, ghost_data.size() - 1)
	var frame: Variant = ghost_data[index]
	if frame is Dictionary and frame.has("transform"):
		ghost_visual.global_transform = frame["transform"]

func _update_hud() -> void:
	if hud == null:
		return
	var current_lap: int = mini(lap_times.size() + 1, LAPS)
	hud.text = "LAP %d/%d     TIME %02d:%05.2f     CHECKPOINT %d/%d" % [
		current_lap,
		LAPS,
		int(time_s / 60.0),
		fmod(time_s, 60.0),
		next_gate,
		CHECKPOINTS.size() - 1
	]

func _finish() -> void:
	finished = true
	race_active = false

	var car := CATALOG.get_selected_id()
	var ranking := RECORDS.record(car, time_s, lap_times)
	var progression := PROGRESSION.record("circuit", car, time_s)
	GHOST.save_best("circuit", car, time_s, frames)

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
	ghost_note.text = "BEST RUN GHOST SAVED" if bool(GRAPHICS.load_settings().get("ghost", true)) else "GHOST DISABLED IN OPTIONS"
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
