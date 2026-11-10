extends RefCounted

const SAVE_PATH := "user://circuit_leaderboard.cfg"
# Bump when the route or timing rules change. The ghost uses the same version.
const TRACK_ID := "circuit_v2"

static func record(car: String, seconds: float, laps: Array) -> Dictionary:
	var cfg := ConfigFile.new()
	var load_error := cfg.load(SAVE_PATH)
	var runs := _read_runs(cfg)
	var entry := {"car": car, "time": seconds, "laps": laps.duplicate()}
	var index := 0
	while index < runs.size() and seconds >= float(runs[index]["time"]):
		index += 1
	runs.insert(index, entry)
	if runs.size() > 10:
		runs.resize(10)
	cfg.set_value(TRACK_ID, "runs", runs)
	var saved := (load_error == OK or load_error == ERR_FILE_NOT_FOUND) and _save(cfg)
	if not saved:
		push_warning("Could not save circuit leaderboard to " + SAVE_PATH)
	return {"rank": index + 1 if index < 10 else 0, "saved": saved, "top": runs}

static func top() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return []
	return _read_runs(cfg).slice(0, 10)

static func _read_runs(cfg: ConfigFile) -> Array:
	var value: Variant = cfg.get_value(TRACK_ID, "runs", [])
	var runs: Array = value if value is Array else []
	return runs.filter(_valid_run)

static func _valid_run(run: Variant) -> bool:
	return run is Dictionary and run.get("car") is String and run.get("time") is float \
		and is_finite(run["time"]) and run["time"] > 0.0

static func _save(cfg: ConfigFile) -> bool:
	var temp_path := SAVE_PATH + ".tmp"
	if cfg.save(temp_path) != OK:
		return false
	var error := DirAccess.rename_absolute(temp_path, SAVE_PATH)
	if error != OK:
		DirAccess.remove_absolute(temp_path)
	return error == OK
