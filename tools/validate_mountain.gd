extends SceneTree

# Bot di collaudo (opzionale): percorre la discesa Mountain e salva il risultato
# e stampa un riepilogo. Si lancia senza finestra:
#   Godot --headless --path <progetto> --fixed-fps 60 --script res://tools/validate_mountain.gd
#   Add -- night to run the same course under the night scene.
#   Add -- force-timeout to exercise the failure path.
#   Use an isolated user-data directory to keep bot times out of your leaderboard.

var scene: Node
var t := 0.0
var best_idx := 0
var max_y := 0.0
var max_off := 0.0
var min_real := 99.0
var samples := 0
var sum_real := 0.0
var out_time := -1.0
var finish_time := -1.0
var connected := false
var reporting := false
const DEFAULT_TIMEOUT := 90.0
var timeout := DEFAULT_TIMEOUT

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "force-timeout" in args:
		timeout = 0.1
	var path := "res://scenes/test_mountain_night.tscn" if "night" in args else "res://scenes/test_mountain.tscn"
	var track := load(path) as PackedScene
	if track == null:
		printerr("Mountain validation failed: could not load ", path)
		quit(1)
		return
	scene = track.instantiate()
	scene.log_interval = DEFAULT_TIMEOUT
	root.add_child(scene)
	Input.action_press("forward")

func _physics_process(delta: float) -> bool:
	if reporting:
		return false
	t += delta
	var v = scene.vehicle
	var road = scene.road
	if v == null or road == null:
		if t >= timeout:
			printerr("Mountain validation failed: track or vehicle did not initialize")
			reporting = true
			quit(1)
		return false
	if not connected:
		connected = true
		road.finish_reached.connect(_on_finish_reached)
	var pos: Vector3 = v.sphere.global_position
	var cl: PackedVector3Array = road.centerline
	# indice del campione piu' vicino
	var bi := best_idx
	var bd := INF
	for i in range(maxi(best_idx - 5, 0), mini(best_idx + 40, cl.size())):
		var d := Vector2(pos.x - cl[i].x, pos.z - cl[i].z).length()
		if d < bd:
			bd = d
			bi = i
	best_idx = maxi(best_idx, bi)
	max_off = maxf(max_off, bd)
	max_y = maxf(max_y, pos.y)
	if t > 3.0:
		var rs: float = v.sphere.linear_velocity.length()
		samples += 1
		sum_real += rs
		min_real = minf(min_real, rs)
	# Steer the travel direction towards the road, even when the body is sideways.
	var tgt := cl[mini(bi + 5, cl.size() - 1)]
	var f: Vector3 = v.sphere.linear_velocity
	if f.length_squared() < 1.0:
		f = v.vehicle_model.global_basis.z
	f.y = 0.0
	var to := Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
	var ang := f.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	Input.action_release("left")
	Input.action_release("right")
	var s := clampf(absf(ang) * 2.0, 0.0, 1.0)
	if ang < -0.02:
		Input.action_press("right", s)
	elif ang > 0.02:
		Input.action_press("left", s)
	if pos.y < -3.0 and out_time < 0.0:
		out_time = t
	if t >= timeout or out_time >= 0.0:
		reporting = true
		_report_and_quit.call_deferred("fell off course" if out_time >= 0.0 else "timeout")
	return false


func _on_finish_reached(_body: Node3D) -> void:
	if reporting:
		return
	finish_time = t
	reporting = true
	var reason := ""
	if out_time >= 0.0 or scene.vehicle.sphere.global_position.y < -3.0:
		reason = "fell off course"
	elif finish_time >= timeout:
		reason = "timeout"
	_report_and_quit.call_deferred(reason)


func _report_and_quit(reason: String) -> void:
	var last: int = scene.road.centerline.size() - 1
	var summary_visible := scene.get_node_or_null("RaceSummary") != null
	if reason.is_empty() and not summary_visible:
		reason = "race summary missing"
	var passed := reason.is_empty()
	print("=== RISULTATO ===")
	print("riepilogo a schermo: %s | collisioni: %d | secondi per barra: %s" % [summary_visible, scene.impacts, str(scene.bar_time)])
	print("traguardo: %s | tempo %.1f s | progresso %d/%d campioni (%.0f%%) | quota max %.1f m | scostamento max dal centro %.1f m | v reale media %.1f min %.1f | caduto: %s" % [
		("RAGGIUNTO a %.1f s" % finish_time) if finish_time >= 0.0 else "NO", t, best_idx, last, 100.0 * best_idx / last, max_y, max_off, sum_real / maxf(samples, 1), min_real if samples > 0 else 0.0, str(out_time >= 0.0)])
	print("Mountain validation passed" if passed else "Mountain validation failed: " + reason)
	scene.queue_free()
	await process_frame
	quit(0 if passed else 1)
