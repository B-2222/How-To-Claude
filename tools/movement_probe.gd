extends Node
## Headless movement probe: drives the real Player with synthetic input and
## checks the physics behaves the way the design claims.
##
## Test rig only. Lives in tools/ and is not part of any shipped scene.
## Run: godot --headless --path . tools/runtime_test.tscn

const SETTLE := 0.75
const RUNUP := 0.6
const STRAFE_SECONDS := 4.0
const TURN_RATES: Array[float] = [60.0, 120.0, 180.0, 240.0, 300.0, 380.0, 460.0]

var player: Player
var weapon: HitscanWeapon
var arena: Node3D

var _stage := 0
var _t := 0.0
var _busy := false
var _rate_index := 0
var _peak := 0.0
var _results: Array = []
var _failures := 0


func _ready() -> void:
	var main := get_parent().get_node("Main")
	player = main.get_node("Player") as Player
	weapon = player.get_node("Head/Shake/Camera/WeaponMount/Rifle") as HitscanWeapon
	arena = main.get_node("Arena") as Node3D


func _ok(text: String) -> void:
	print("ok    ", text)


func _fail(text: String) -> void:
	_failures += 1
	print("FAIL  ", text)


func _reset(position: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.look_yaw = 0.0
	player.look_pitch = 0.0


func _release_all() -> void:
	for action in ["jump", "move_left", "move_right", "move_forward", "move_back", "crouch", "sprint", "dive"]:
		Input.action_release(action)


func _advance(next: int) -> void:
	_stage = next
	_t = 0.0


func _physics_process(delta: float) -> void:
	if _busy:
		return
	_t += delta
	match _stage:
		0: _stage_settle()
		1: _stage_runup()
		2: _stage_strafe(delta)
		3: _stage_ground_cap()
		4: _stage_slide()
		5: _stage_dive()
		6: _stage_shooting()
		7: _stage_report()


# --- 0: does the player land and stop? -------------------------------------
func _stage_settle() -> void:
	if _t < SETTLE:
		return
	if player.is_on_floor():
		_ok("settles on the floor at y=%.2f, state=%s" % [player.global_position.y, player.state_name()])
	else:
		_fail("player did not settle on the floor (y=%.2f)" % player.global_position.y)
	if player.horizontal_speed() < 0.01:
		_ok("friction brings the player to a complete stop")
	else:
		_fail("player drifting at rest: %.3f m/s" % player.horizontal_speed())
	print("")
	print("--- bunny hop: strafe-left + turn left, %.0fs per turn rate ---" % STRAFE_SECONDS)
	_begin_strafe_trial()


# --- 1/2: air strafe speed gain across turn rates ---------------------------
func _begin_strafe_trial() -> void:
	_release_all()
	_reset(Vector3(0.0, 1.0, 0.0))
	_peak = 0.0
	Input.action_press("move_forward")
	_advance(1)


func _stage_runup() -> void:
	if _t < RUNUP:
		return
	Input.action_release("move_forward")
	Input.action_press("move_left")
	Input.action_press("jump")
	_advance(2)


func _stage_strafe(delta: float) -> void:
	# Increasing yaw is a LEFT turn. Paired with strafe-left it keeps wish_dir
	# near-perpendicular to velocity, which is the condition for maximum gain.
	player.look_yaw = wrapf(player.look_yaw + deg_to_rad(TURN_RATES[_rate_index]) * delta, -PI, PI)
	_peak = maxf(_peak, player.horizontal_speed())
	if _t < STRAFE_SECONDS:
		return
	_results.append([TURN_RATES[_rate_index], _peak])
	print("      turn %5.0f deg/s   peak %6.2f m/s" % [TURN_RATES[_rate_index], _peak])
	_rate_index += 1
	if _rate_index < TURN_RATES.size():
		_begin_strafe_trial()
		return
	_release_all()
	_reset(Vector3(0.0, 1.0, 0.0))
	print("")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	_advance(3)


# --- 3: holding W on the ground must NOT exceed sprint speed ----------------
func _stage_ground_cap() -> void:
	if _t < 2.0:
		return
	var speed := player.horizontal_speed()
	var expected := player.tuning.sprint_speed
	if absf(speed - expected) <= 0.25:
		_ok("ground sprint settles at %.2f m/s (sprint_speed %.2f)" % [speed, expected])
	else:
		_fail("ground sprint settled at %.2f m/s, expected %.2f" % [speed, expected])
	Input.action_press("crouch")
	_advance(4)


# --- 4: slide entry and slide-cancel ---------------------------------------
func _stage_slide() -> void:
	if _t < 0.35:
		return
	_busy = true
	if not player.is_sliding():
		_fail("slide never started at %.2f m/s (slide_min_speed %.2f)" % [player.horizontal_speed(), player.tuning.slide_min_speed])
	else:
		_ok("slide entered, boosted to %.2f m/s" % player.horizontal_speed())
		var before := player.horizontal_speed()
		Input.action_release("crouch")
		await get_tree().physics_frame
		await get_tree().physics_frame
		var after := player.horizontal_speed()
		if after > before * 0.9:
			_ok("slide-cancel keeps momentum: %.2f -> %.2f m/s" % [before, after])
		else:
			_fail("slide-cancel lost momentum: %.2f -> %.2f m/s" % [before, after])
	_release_all()
	print("")
	_busy = false
	_advance(5)


# --- 5: dive slow motion, and that it restores ------------------------------
func _stage_dive() -> void:
	_busy = true
	_release_all()
	_reset(Vector3(0.0, 1.0, 0.0))
	Input.action_press("move_forward")
	await get_tree().physics_frame
	Input.action_press("dive")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("dive")
	if player.is_diving():
		_ok("dive active, state=%s" % player.state_name())
	else:
		_fail("dive did not start")
	if is_equal_approx(Engine.time_scale, player.tuning.dive_time_scale):
		_ok("Engine.time_scale dropped to %.2f" % Engine.time_scale)
	else:
		_fail("dive did not set time scale (%.2f)" % Engine.time_scale)

	# Wait out the dive in REAL time. The tree timer ignores time scale, which is
	# also how the dive itself is timed.
	var clock := Time.get_ticks_msec()
	while player.is_diving() and Time.get_ticks_msec() - clock < 6000:
		await get_tree().physics_frame
	var elapsed := (Time.get_ticks_msec() - clock) / 1000.0
	if is_equal_approx(Engine.time_scale, 1.0):
		_ok("dive ended after %.2fs real time and restored time scale" % elapsed)
	else:
		_fail("time scale stuck at %.2f after the dive" % Engine.time_scale)
	if absf(elapsed - player.tuning.dive_duration) < 0.4:
		_ok("dive lasted %.2fs against a configured %.2fs" % [elapsed, player.tuning.dive_duration])
	else:
		_fail("dive lasted %.2fs, configured %.2fs" % [elapsed, player.tuning.dive_duration])
	_release_all()
	print("")
	_busy = false
	_advance(6)


# --- 6: hitscan actually damages a target, and spin tracking is sane --------
func _stage_shooting() -> void:
	_busy = true
	var target := arena.get_node("Targets/Target00") as Target
	_release_all()
	_reset(Vector3(target.global_position.x, target.global_position.y - 1.6, target.global_position.z + 12.0))
	# Remove spread so the test measures the trace, not the dice.
	weapon.stats.base_spread = 0.0
	weapon.stats.move_spread = 0.0
	weapon.stats.air_spread = 0.0
	weapon.stats.spread_per_shot = 0.0
	await get_tree().physics_frame

	var before := target.health
	var shots := 0
	for i in 3:
		weapon._cooldown = 0.0
		if weapon.try_fire():
			shots += 1
		await get_tree().physics_frame
	if shots != 3:
		_fail("weapon fired %d of 3 shots" % shots)
	elif not target.alive or target.health < before:
		_ok("3 shots at 12 m damaged the target (%.0f -> %.0f hp, alive=%s)" % [before, target.health, target.alive])
	else:
		_fail("3 shots landed no damage")

	if player.recoil_target.length() > 0.0:
		_ok("recoil accumulated %.2f degrees of pitch" % rad_to_deg(player.recoil_target.y))
	else:
		_fail("firing produced no recoil")

	player.yaw_tracker.clear()
	for i in 30:
		player.yaw_tracker.push(deg_to_rad(12.0))
	var spun := player.spin_degrees(1.5)
	if absf(spun - 360.0) < 1.0:
		_ok("yaw tracker scores a full rotation as %.0f degrees" % spun)
	else:
		_fail("yaw tracker reported %.1f degrees for a 360" % spun)
	player.yaw_tracker.clear()
	for i in 15:
		player.yaw_tracker.push(deg_to_rad(12.0))
	for i in 15:
		player.yaw_tracker.push(deg_to_rad(-12.0))
	var wobble := player.spin_degrees(1.5)
	if wobble < 1.0:
		_ok("a 180 out and back nets %.1f degrees, not a false 360" % wobble)
	else:
		_fail("wrist wobble scored %.1f degrees" % wobble)
	print("")
	_busy = false
	_advance(7)


func _stage_report() -> void:
	var best: Array = [0.0, 0.0]
	for row: Array in _results:
		if row[1] > best[1]:
			best = row
	print("best air-strafe result: %.2f m/s at %.0f deg/s  (walk %.1f, sprint %.1f)" % [
		best[1], best[0], player.tuning.walk_speed, player.tuning.sprint_speed])
	if best[1] >= player.tuning.sprint_speed * 1.5:
		_ok("air strafing builds real speed (%.2fx sprint)" % (best[1] / player.tuning.sprint_speed))
	else:
		_fail("air strafing did not build meaningful speed")
	print("")
	print("PROBE FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
