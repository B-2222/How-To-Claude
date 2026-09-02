extends SceneTree
## Headless smoke test: parse every script, load every resource, instantiate
## every scene, and confirm the input map matches what the code asks for.
## Run: godot --headless --path . --script tools/validate.gd

var failures := 0

func _fail(message: String) -> void:
	failures += 1
	print("FAIL  ", message)

func _ok(message: String) -> void:
	print("ok    ", message)

func _init() -> void:
	_check_scripts()
	_check_resources()
	_check_actions()
	_check_scenes()
	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)

func _walk(dir_path: String, suffix: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_walk(full, suffix, out)
		elif name.ends_with(suffix):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

func _check_scripts() -> void:
	var files: Array = []
	_walk("res://scripts", ".gd", files)
	for path: String in files:
		var script := load(path)
		if script == null:
			_fail("script failed to load: " + path)
		else:
			_ok("script " + path)

func _check_resources() -> void:
	var files: Array = []
	_walk("res://resources", ".tres", files)
	for path: String in files:
		var res := load(path)
		if res == null:
			_fail("resource failed to load: " + path)
		else:
			_ok("resource %s (%s)" % [path, res.get_class()])
	var tuning := load("res://resources/movement/default.tres")
	if not (tuning is MovementTuning):
		_fail("default.tres did not resolve to MovementTuning")
	else:
		# Compare against the text on disk rather than a hardcoded number, so
		# retuning the preset never silently breaks or falsely passes this test.
		var written := _read_float("res://resources/movement/default.tres", "air_speed_cap")
		if is_nan(written):
			_fail("could not find air_speed_cap in default.tres")
		elif not is_equal_approx(tuning.air_speed_cap, written):
			_fail("default.tres air_speed_cap is %s on disk but %s once loaded" % [written, tuning.air_speed_cap])
		else:
			_ok("MovementTuning round-trips (air_speed_cap = %s)" % written)
	var stats := load("res://resources/weapons/mk1_rifle.tres")
	if not (stats is WeaponStats):
		_fail("mk1_rifle.tres did not resolve to WeaponStats")
	elif stats.recoil_pattern.size() != 18:
		_fail("recoil pattern length is %d, expected 18" % stats.recoil_pattern.size())
	else:
		_ok("WeaponStats recoil pattern has %d entries" % stats.recoil_pattern.size())

## Reads "key = value" out of a .tres as text, for round-trip checks.
func _read_float(path: String, key: String) -> float:
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n"):
		if line.begins_with(key + " = "):
			return line.substr((key + " = ").length()).to_float()
	return NAN


func _check_actions() -> void:
	var required := ["move_forward", "move_back", "move_left", "move_right",
		"jump", "sprint", "crouch", "dive", "fire", "ads", "reload",
		"restart", "toggle_help", "ui_cancel"]
	for action: String in required:
		if InputMap.has_action(action):
			_ok("action " + action)
		else:
			_fail("missing input action: " + action)

func _check_scenes() -> void:
	var files: Array = []
	_walk("res://scenes", ".tscn", files)
	for path: String in files:
		var packed := load(path) as PackedScene
		if packed == null:
			_fail("scene failed to load: " + path)
			continue
		var instance := packed.instantiate()
		if instance == null:
			_fail("scene failed to instantiate: " + path)
			continue
		_ok("scene %s (%d nodes)" % [path, _count(instance)])
		instance.free()

func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
