extends RefCounted

const ROOT := "user://ghost_"
const SAMPLE_INTERVAL := 0.10
const MAX_SAMPLES := 12000

static func _path(track: String, car: String) -> String:
	return ROOT + track.validate_filename() + "_" + car.validate_filename() + ".dat"

static func load_best(track: String, car: String) -> Dictionary:
	var file := FileAccess.open(_path(track, car), FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = file.get_var()
	if value is Dictionary and _valid_replay(value.get("time"), value.get("frames")):
		return value
	return {}

static func save_best(track: String, car: String, time_s: float, frames: Array) -> bool:
	if not _valid_replay(time_s, frames):
		return false
	var old := load_best(track, car)
	if not old.is_empty() and float(old.get("time", INF)) <= time_s:
		return false
	var path := _path(track, car)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	var stored := file.store_var({"time": time_s, "frames": frames})
	file.close()
	if stored and DirAccess.rename_absolute(temp_path, path) == OK:
		return true
	DirAccess.remove_absolute(temp_path)
	return false

static func _valid_replay(time_s: Variant, frames: Variant) -> bool:
	if not time_s is float or not is_finite(time_s) or time_s <= 0.0:
		return false
	if not frames is Array or frames.size() < 2 or frames.size() > MAX_SAMPLES:
		return false
	var previous := -1.0
	for frame: Variant in frames:
		if not frame is Dictionary:
			return false
		var elapsed: Variant = frame.get("t")
		var pose: Variant = frame.get("transform")
		if not elapsed is float or not is_finite(elapsed) or elapsed < 0.0 or elapsed <= previous:
			return false
		if not pose is Transform3D or not pose.is_finite():
			return false
		previous = elapsed
	return frames.front()["t"] == 0.0 and is_equal_approx(previous, time_s)
