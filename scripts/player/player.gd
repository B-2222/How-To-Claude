class_name Player
extends CharacterBody3D
##
## First-person controller: Source-style ground/air acceleration, bunny hopping,
## sliding with slide-cancel, and a slow-motion dive.
##
## The whole thing runs on two functions, [method _apply_friction] and
## [method _accelerate], lifted in shape from Quake/Source. Everything else
## (slide, dive, stance, camera feel) decides which numbers those two get.
##
## Read [MovementTuning] alongside this file; it holds every tunable value.

enum State {
	GROUND,
	AIR,
	SLIDE,
	DIVE,
}

signal state_changed(from_state: State, to_state: State)
signal landed(impact_speed: float)
signal jumped()
signal dive_started()
signal dive_ended()

@export var tuning: MovementTuning
@export var mouse_sensitivity := 0.0022
@export var invert_look := false

# --- Read by the weapon, the HUD, and (from Phase 2) the scorer -------------
var state := State.AIR
## World-space horizontal unit vector the player is asking to move along.
var wish_dir := Vector3.ZERO
var wish_speed := 0.0
var look_yaw := 0.0
var look_pitch := 0.0
## Rolling yaw history for spin detection. Phase 2 scores off this.
var yaw_tracker := YawTracker.new()
## Set by the weapon each frame: 0 = hip, 1 = fully aimed down sights.
var ads_blend := 0.0
var ads_fov := 55.0

# --- Recoil ----------------------------------------------------------------
# Two values, not one. `recoil_target` is where the kick wants the camera;
# `recoil_current` chases it quickly while the target itself decays slowly.
# A single spring gives you either a snappy kick or a slow settle, never both.
# x = yaw (radians, + is left), y = pitch (radians, + is up).
var recoil_current := Vector2.ZERO
var recoil_target := Vector2.ZERO
var recoil_snap := 22.0
var recoil_recovery := 5.5

# --- Internal timers. All fed UNSCALED delta, so a slow-motion dive does not
# also slow its own cooldown. ------------------------------------------------
var _jump_buffer := 0.0
var _coyote := 0.0
var _slide_cooldown := 0.0
var _dive_cooldown := 0.0
var _dive_time_left := 0.0
var _slide_time := 0.0

var _move_input := Vector2.ZERO
var _crouch_held := false
var _crouching := false
var _view_roll := 0.0
var _bob_t := 0.0
var _bob_offset := Vector2.ZERO
var _land_dip := 0.0
var _fov_base := 90.0
var _mouse_captured := false
var _last_impact_speed := 0.0

@onready var collider: CollisionShape3D = $Collider
@onready var head: Node3D = $Head
@onready var shake: CameraShake = $Head/Shake
@onready var camera: Camera3D = $Head/Shake/Camera
@onready var weapon_mount: Node3D = $Head/Shake/Camera/WeaponMount
@onready var ceiling_check: RayCast3D = $CeilingCheck


func _ready() -> void:
	if tuning == null:
		tuning = MovementTuning.new()
	# The capsule shape is a sub-resource of player.tscn and would otherwise be
	# shared by every instance; we resize it every frame for crouch, so it has
	# to be ours alone.
	collider.shape = collider.shape.duplicate()
	_fov_base = camera.fov
	floor_max_angle = deg_to_rad(tuning.floor_max_angle_deg)
	floor_snap_length = tuning.floor_snap_length
	floor_stop_on_slope = false
	slide_on_ceiling = true
	# Measured from the ray's own origin, not from the feet, or it would report a
	# blocked ceiling a third of a metre higher than the player really is.
	ceiling_check.target_position = Vector3(
		0.0, tuning.stand_height + 0.06 - ceiling_check.position.y, 0.0)
	Engine.time_scale = 1.0
	capture_mouse()


func _exit_tree() -> void:
	# Never leave the engine in slow motion because a dive was interrupted by a
	# scene reload.
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mouse_captured = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		var motion := event as InputEventMouseMotion
		var d_yaw := -motion.relative.x * mouse_sensitivity
		var d_pitch := -motion.relative.y * mouse_sensitivity
		if invert_look:
			d_pitch = -d_pitch
		look_yaw = wrapf(look_yaw + d_yaw, -PI, PI)
		look_pitch = clampf(look_pitch + d_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		# Feed the tracker raw input, before recoil and shake touch the camera.
		yaw_tracker.push(d_yaw)
	elif event.is_action_pressed(&"ui_cancel"):
		release_mouse()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not _mouse_captured:
		capture_mouse()


func _read_input() -> void:
	if _mouse_captured:
		_move_input = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
		_crouch_held = Input.is_action_pressed(&"crouch")
		# Auto-hop: holding jump keeps the buffer topped up, so landing
		# immediately re-jumps. Without it, bunny hopping is a frame-timing
		# test; with it, it is a strafe-and-mouse test.
		if Input.is_action_just_pressed(&"jump") \
				or (tuning.auto_hop and Input.is_action_pressed(&"jump")):
			_jump_buffer = tuning.jump_buffer
		if Input.is_action_just_pressed(&"dive"):
			_try_dive()
	else:
		_move_input = Vector2.ZERO
		_crouch_held = false

	# Build the wish vector from look_yaw directly rather than from this node's
	# basis. The basis is only written in _process, so on frames where physics
	# runs twice it would be one step stale, which shows up as strafe jumps
	# feeling mushy at high frame rates.
	var input := _move_input
	if input.length_squared() > 1.0:
		input = input.normalized()
	var forward := Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))
	var right := Vector3(cos(look_yaw), 0.0, -sin(look_yaw))
	var wish := right * input.x + forward * input.y
	wish_dir = wish.normalized() if wish.length_squared() > 0.000001 else Vector3.ZERO
	wish_speed = wish.length() * _target_speed()


func _target_speed() -> float:
	if _crouching and state == State.GROUND:
		return tuning.crouch_speed
	if Input.is_action_pressed(&"sprint") and _move_input.y > 0.0:
		return tuning.sprint_speed
	return tuning.walk_speed


# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var real_delta := _unscaled(delta)

	_tick_timers(real_delta)
	_read_input()
	_update_slide_state()
	_update_dive_state(real_delta)

	# Decided BEFORE friction: on the tick you jump, friction must not run, or
	# every hop shaves speed off and bunny hopping cannot build momentum.
	var will_jump := _jump_buffer > 0.0 and (is_on_floor() or _coyote > 0.0)

	match state:
		State.SLIDE:
			_move_slide(delta)
		State.DIVE:
			_move_air(delta, tuning.dive_air_control)
		_:
			if is_on_floor():
				_move_ground(delta, will_jump)
			else:
				_move_air(delta, 1.0)

	velocity.y -= tuning.gravity * delta
	if will_jump:
		_do_jump()
	if not is_on_floor():
		_clamp_air_speed()

	var was_on_floor := is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()

	if is_on_floor():
		_coyote = tuning.coyote_time
		if not was_on_floor:
			_on_land(-fall_speed)
		elif state == State.AIR:
			_set_state(State.GROUND)
	else:
		_coyote = maxf(_coyote - real_delta, 0.0)
		if state == State.GROUND:
			_set_state(State.AIR)


## Source `Friction`. A flat proportional drop, except that below [member
## MovementTuning.stop_speed] the drop is computed as if you were moving AT
## stop_speed. That floor is the whole trick: without it, friction is purely
## multiplicative and you asymptotically drift forever instead of stopping.
func _apply_friction(delta: float, coefficient: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.05:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var control := maxf(speed, tuning.stop_speed)
	var new_speed := maxf(speed - control * coefficient * delta, 0.0)
	var scale := new_speed / speed
	velocity.x *= scale
	velocity.z *= scale


## Source `Accelerate`, the single most important function in the file.
##
## The gain is limited by how much speed you ALREADY have along [param dir],
## not by your total speed. Hold W and your projection onto wish_dir is your
## full speed, so add_speed hits zero and you cap out at run speed. Point
## wish_dir 90 degrees off your velocity and the projection is ~0, so you get
## the full per-tick gain while barely losing speed to the turn. That asymmetry
## is strafe jumping, surfing and air control, all of it.
func _accelerate(dir: Vector3, target_speed: float, accel: float, delta: float) -> void:
	if dir == Vector3.ZERO or target_speed <= 0.0:
		return
	var current := velocity.x * dir.x + velocity.z * dir.z
	var add_speed := target_speed - current
	if add_speed <= 0.0:
		return
	var accel_speed := minf(accel * target_speed * delta, add_speed)
	velocity.x += dir.x * accel_speed
	velocity.z += dir.z * accel_speed


func _move_ground(delta: float, will_jump: bool) -> void:
	if not will_jump:
		_apply_friction(delta, tuning.friction)
	_accelerate(wish_dir, wish_speed, tuning.ground_accel, delta)


## Air movement is [method _accelerate] with the target speed clamped to a very
## small number ([member MovementTuning.air_speed_cap], under a metre per
## second). Because the clamp applies to the PROJECTION of your velocity, a
## player holding A while sweeping the mouse left keeps that projection near
## zero and therefore keeps earning the full per-tick gain, indefinitely.
##
## TICK RATE: raw Source maths gives you `cap` metres per TICK, so running at
## 240 Hz would literally make you twice as fast as at 120 Hz. Normalising the
## cap by (delta * 60) makes gain-per-second identical at any tick rate. This is
## exact only while air_accel is high enough that the min() above always picks
## add_speed, which is why air_accel defaults to 150 rather than Source's 10.
func _move_air(delta: float, control_scale: float) -> void:
	var cap := tuning.air_speed_cap
	if tuning.tickrate_normalised_air_cap:
		cap *= delta * 60.0
	_accelerate(wish_dir, minf(wish_speed, cap), tuning.air_accel * control_scale, delta)


func _clamp_air_speed() -> void:
	if tuning.max_air_speed <= 0.0:
		return
	var horizontal := Vector2(velocity.x, velocity.z)
	var speed := horizontal.length()
	if speed > tuning.max_air_speed:
		horizontal = horizontal * (tuning.max_air_speed / speed)
		velocity.x = horizontal.x
		velocity.z = horizontal.y


func _do_jump() -> void:
	_jump_buffer = 0.0
	_coyote = 0.0
	if state == State.SLIDE:
		# Slide-hopping: leave the slide without touching horizontal velocity,
		# so the slide's entry boost is carried straight into the air.
		_exit_slide(true)
	velocity.y = tuning.jump_velocity
	_set_state(State.AIR)
	jumped.emit()


func _on_land(impact_speed: float) -> void:
	_last_impact_speed = impact_speed
	_land_dip = clampf(impact_speed / 16.0, 0.0, 1.0) * tuning.land_dip
	if state == State.DIVE:
		_end_dive()
	elif state != State.SLIDE:
		_set_state(State.GROUND)
	# Landing with crouch already held rolls straight into a slide, which is how
	# a dive chains into a slide chains into a hop.
	if _crouch_held:
		_try_slide()
	landed.emit(impact_speed)


# ---------------------------------------------------------------------------
# Slide
# ---------------------------------------------------------------------------

func _update_slide_state() -> void:
	if state == State.SLIDE:
		if not _crouch_held:
			# Slide-cancel. Keeps every bit of horizontal speed and gets a much
			# shorter cooldown than letting the slide die, so cancelling is the
			# strictly better play if you can time it.
			_exit_slide(true)
		elif not is_on_floor():
			_set_state(State.AIR)
		return
	if _crouch_held and state == State.GROUND:
		_try_slide()


func _try_slide() -> bool:
	if _slide_cooldown > 0.0 or not is_on_floor() or state == State.DIVE:
		return false
	var horizontal := Vector2(velocity.x, velocity.z)
	var speed := horizontal.length()
	if speed < tuning.slide_min_speed:
		return false
	var dir := horizontal / speed
	var boost := maxf(speed, tuning.slide_entry_speed)
	velocity.x = dir.x * boost
	velocity.z = dir.y * boost
	_slide_time = 0.0
	_set_state(State.SLIDE)
	return true


func _move_slide(delta: float) -> void:
	_slide_time += delta
	_apply_friction(delta, tuning.slide_friction)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()

	# Steering rotates the velocity vector instead of adding to it, so a slide
	# can be bent but never used to gain speed by turning.
	if speed > 0.1 and wish_dir != Vector3.ZERO:
		var current := horizontal / speed
		if current.dot(wish_dir) > -0.98:
			var steered := current.slerp(wish_dir, clampf(tuning.slide_steer * delta, 0.0, 1.0)).normalized()
			velocity.x = steered.x * speed
			velocity.z = steered.z * speed

	# Downhill slopes accelerate the slide, which makes the vertical arena in
	# Phase 5 worth learning.
	if is_on_floor():
		var normal := get_floor_normal()
		var downhill := Vector3(normal.x, 0.0, normal.z)
		if downhill.length_squared() > 0.0001:
			velocity.x += downhill.x * tuning.slide_slope_accel * delta
			velocity.z += downhill.z * tuning.slide_slope_accel * delta

	if speed < tuning.slide_exit_speed or _slide_time > tuning.slide_max_time:
		_exit_slide(false)


func _exit_slide(cancelled: bool) -> void:
	if state != State.SLIDE:
		return
	_slide_cooldown = tuning.slide_cancel_cooldown if cancelled else tuning.slide_cooldown
	_set_state(State.GROUND if is_on_floor() else State.AIR)


# ---------------------------------------------------------------------------
# Dive
# ---------------------------------------------------------------------------

func _try_dive() -> void:
	if _dive_cooldown > 0.0 or state == State.DIVE:
		return
	var dir := wish_dir
	if dir == Vector3.ZERO:
		dir = Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))
	var speed := maxf(Vector2(velocity.x, velocity.z).length(), tuning.dive_min_speed)
	speed *= tuning.dive_forward_boost
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = tuning.dive_up_velocity
	_dive_time_left = tuning.dive_duration
	_dive_cooldown = tuning.dive_cooldown
	_set_state(State.DIVE)
	Engine.time_scale = tuning.dive_time_scale
	dive_started.emit()


func _update_dive_state(real_delta: float) -> void:
	if state != State.DIVE:
		return
	# Counted in unscaled seconds so "1.5 seconds of slow motion" means 1.5
	# seconds on the player's clock, not 1.5 slowed seconds (which would be 5).
	_dive_time_left -= real_delta
	if _dive_time_left <= 0.0:
		_end_dive()


func _end_dive() -> void:
	if state != State.DIVE:
		return
	Engine.time_scale = 1.0
	_dive_time_left = 0.0
	_set_state(State.GROUND if is_on_floor() else State.AIR)
	dive_ended.emit()


# ---------------------------------------------------------------------------
# Stance, camera feel
# ---------------------------------------------------------------------------

func _tick_timers(real_delta: float) -> void:
	_jump_buffer = maxf(_jump_buffer - real_delta, 0.0)
	_slide_cooldown = maxf(_slide_cooldown - real_delta, 0.0)
	_dive_cooldown = maxf(_dive_cooldown - real_delta, 0.0)


func _process(delta: float) -> void:
	var real_delta := _unscaled(delta)
	yaw_tracker.advance(real_delta)

	recoil_current = recoil_current.lerp(recoil_target, 1.0 - exp(-recoil_snap * delta))
	recoil_target = recoil_target.lerp(Vector2.ZERO, 1.0 - exp(-recoil_recovery * delta))

	_update_stance(delta)
	_update_view(delta)


func _update_stance(delta: float) -> void:
	var want_crouch := _crouch_held or state == State.SLIDE or state == State.DIVE
	# Refuse to stand back up under a low ceiling.
	if not want_crouch and _crouching:
		ceiling_check.force_raycast_update()
		if ceiling_check.is_colliding():
			want_crouch = true
	_crouching = want_crouch

	var capsule := collider.shape as CapsuleShape3D
	var target_height := tuning.crouch_height if _crouching else tuning.stand_height
	capsule.height = lerpf(capsule.height, target_height, 1.0 - exp(-tuning.stance_speed * delta))
	# Capsule origin is its centre, so keep the feet planted as it shrinks.
	collider.position.y = capsule.height * 0.5

	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-9.0 * delta))
	head.position = Vector3(
		_bob_offset.x,
		capsule.height - tuning.head_offset - _land_dip + _bob_offset.y,
		0.0)


func _update_view(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()

	# View bob, scaled by speed and killed in the air.
	if state == State.GROUND and is_on_floor() and speed > 0.5:
		_bob_t += delta * speed * tuning.bob_rate
		var strength := tuning.bob_amount * clampf(speed / tuning.sprint_speed, 0.0, 1.2)
		_bob_offset = Vector2(cos(_bob_t) * strength * 1.4, absf(sin(_bob_t)) * -strength)
	else:
		_bob_offset = _bob_offset.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta))

	# Roll into strafes, and harder into slides. Roll is the cheapest way to
	# make lateral movement legible in first person.
	var target_roll := -_move_input.x * deg_to_rad(tuning.strafe_roll_deg)
	if state == State.SLIDE:
		var lateral := signf(-_move_input.x) if absf(_move_input.x) > 0.1 else 1.0
		target_roll = lateral * deg_to_rad(tuning.slide_roll_deg)
	_view_roll = lerpf(_view_roll, target_roll, 1.0 - exp(-tuning.roll_speed * delta))

	# Godot's default Euler order is YXZ, i.e. yaw then pitch then roll, which is
	# exactly the order a first-person camera wants. So yaw can live on the body
	# and pitch/roll on the head with no gimbal surprises.
	rotation.y = look_yaw
	head.rotation = Vector3(look_pitch + recoil_current.y, recoil_current.x, _view_roll)

	# FOV widens above sprint speed. This is what actually sells a bunny hop:
	# the number on the HUD says you are fast, the FOV makes you feel it.
	var over_speed := maxf(speed - tuning.sprint_speed, 0.0)
	var target_fov := _fov_base + minf(over_speed * tuning.fov_per_speed, tuning.fov_max_gain)
	if state == State.DIVE:
		target_fov += tuning.dive_fov_gain
	target_fov = lerpf(target_fov, ads_fov, ads_blend)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-tuning.fov_blend_speed * delta))


# ---------------------------------------------------------------------------
# Public helpers, used by the weapon, HUD and (Phase 2) the scorer
# ---------------------------------------------------------------------------

func add_recoil(kick_radians: Vector2) -> void:
	recoil_target += kick_radians


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_airborne() -> bool:
	return not is_on_floor()


func is_sliding() -> bool:
	return state == State.SLIDE


func is_diving() -> bool:
	return state == State.DIVE


## Net yaw rotation in degrees over the last [param window] real seconds.
func spin_degrees(window := 1.5) -> float:
	return yaw_tracker.degrees_in(window)


func dive_cooldown_ratio() -> float:
	if tuning.dive_cooldown <= 0.0:
		return 0.0
	return clampf(_dive_cooldown / tuning.dive_cooldown, 0.0, 1.0)


func state_name() -> String:
	match state:
		State.GROUND: return "GROUND"
		State.AIR: return "AIR"
		State.SLIDE: return "SLIDE"
		State.DIVE: return "DIVE"
	return "?"


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var previous := state
	state = new_state
	state_changed.emit(previous, new_state)


## Converts an engine delta back into real seconds. Engine.time_scale is 0.3
## during a dive, so anything that should tick in wall-clock time (cooldowns,
## the dive timer, the spin window) has to be fed this instead of delta.
func _unscaled(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.0001)
