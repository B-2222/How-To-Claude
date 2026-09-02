class_name HitscanWeapon
extends Node3D
## A hitscan weapon driven entirely by a [WeaponStats] resource.
##
## Lives under the camera as a view model. Shots are traced from the CAMERA,
## not from the muzzle, so what the crosshair covers is what you hit; the muzzle
## is only used as the visual origin of the tracer.

signal fired(shot: Dictionary)
signal hit_confirmed(shot: Dictionary)

@export var stats: WeaponStats
## Local position the model blends to when aiming, from its authored hip position.
@export var ads_position := Vector3(0.0, -0.075, -0.32)
@export var tracer_scene: PackedScene
@export var impact_scene: PackedScene

var current_spread := 0.0
var ads_blend := 0.0

var _player: Player
## Highest Node3D ancestor. Tracers and impacts are parented here rather than to
## current_scene, so effects land in world space even when the game is embedded
## in a test harness or a future level-select wrapper.
var _world: Node3D
var _hip_position := Vector3.ZERO
var _cooldown := 0.0
var _since_shot := 99.0
var _pattern_index := 0
var _bloom := 0.0

@onready var muzzle: Marker3D = $Model/Muzzle
@onready var flash: MeshInstance3D = $Model/Muzzle/Flash
@onready var flash_light: OmniLight3D = $Model/Muzzle/FlashLight
@onready var fire_audio: AudioStreamPlayer = $FireAudio


func _ready() -> void:
	if stats == null:
		stats = WeaponStats.new()
	_hip_position = position
	_player = _find_player()
	_world = _find_world()
	if _player:
		_player.recoil_snap = stats.recoil_snap
		_player.recoil_recovery = stats.recoil_recovery
	_set_flash_visible(false)


func _find_world() -> Node3D:
	var found: Node3D = null
	var node := get_parent()
	while node != null:
		if node is Node3D:
			found = node as Node3D
		node = node.get_parent()
	return found


func _find_player() -> Player:
	var node := get_parent()
	while node != null:
		if node is Player:
			return node as Player
		node = node.get_parent()
	return null


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_since_shot += delta
	if _since_shot > stats.pattern_reset_time:
		_pattern_index = 0
	_bloom = maxf(_bloom - stats.spread_recovery * delta, 0.0)

	_update_ads(delta)
	current_spread = spread_degrees()

	if _player == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if stats.automatic:
		if Input.is_action_pressed(&"fire"):
			try_fire()
	elif Input.is_action_just_pressed(&"fire"):
		try_fire()


func _update_ads(delta: float) -> void:
	var want := 1.0 if Input.is_action_pressed(&"ads") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else 0.0
	ads_blend = move_toward(ads_blend, want, delta / maxf(stats.ads_time, 0.01))
	# Ease the position so the gun settles into the sight instead of arriving
	# at constant speed.
	var eased := ads_blend * ads_blend * (3.0 - 2.0 * ads_blend)
	position = _hip_position.lerp(ads_position, eased)
	if _player:
		_player.ads_blend = eased
		_player.ads_fov = stats.ads_fov


## Current cone half-angle in degrees, taking movement, air time, bloom and ADS
## into account. The crosshair reads this directly, so the gap on screen is an
## honest picture of where a bullet can land.
func spread_degrees() -> float:
	if _player == null:
		return stats.base_spread
	var spread := stats.base_spread + _bloom
	var speed_ratio := clampf(_player.horizontal_speed() / maxf(_player.tuning.sprint_speed, 0.1), 0.0, 1.6)
	spread += stats.move_spread * speed_ratio
	if _player.is_airborne():
		spread += stats.air_spread
	spread *= lerpf(1.0, stats.ads_spread_multiplier, ads_blend)
	return minf(spread, stats.max_spread)


func try_fire() -> bool:
	if _cooldown > 0.0 or _player == null:
		return false
	_cooldown = 60.0 / maxf(stats.rounds_per_minute, 1.0)
	_since_shot = 0.0

	var camera := _player.camera
	var origin := camera.global_transform.origin
	var aim := -camera.global_transform.basis.z.normalized()
	var direction := _scatter(aim, spread_degrees())

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * stats.max_range)
	query.collide_with_areas = false
	query.exclude = [_player.get_rid()]
	var result := space.intersect_ray(query)

	var end_point: Vector3 = result.get("position", origin + direction * stats.max_range)

	# Bloom, recoil and shake are applied AFTER the trace, so the shot you took
	# is the one you aimed, and the kick lands on the next one.
	_bloom = minf(_bloom + stats.spread_per_shot, stats.max_spread)
	_apply_recoil()
	_player.shake.add_trauma(stats.screen_shake)
	_muzzle_flash()
	_spawn_tracer(muzzle.global_transform.origin, end_point)
	if fire_audio.stream:
		# Pitch tracks time scale, so a shot in a slow-motion dive sounds slowed.
		fire_audio.pitch_scale = clampf(Engine.time_scale, 0.25, 1.0) * randf_range(0.97, 1.03)
		fire_audio.play()

	var shot := {
		"origin": origin,
		"direction": direction,
		"end": end_point,
		"spread": current_spread,
		"hit": false,
		"collider": null,
		"distance": origin.distance_to(end_point),
	}

	if result:
		shot["hit"] = true
		shot["collider"] = result["collider"]
		shot["normal"] = result["normal"]
		_spawn_impact(end_point, result["normal"])
		var collider: Object = result["collider"]
		if collider is Target:
			(collider as Target).take_damage(stats.damage, end_point, _player)
			hit_confirmed.emit(shot)

	fired.emit(shot)
	return true


## Samples a direction uniformly inside a cone of half-angle [param degrees].
## The sqrt() on the radius matters: without it, samples bunch toward the centre
## and the weapon feels more accurate than the crosshair claims.
func _scatter(direction: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return direction
	var max_angle := deg_to_rad(degrees)
	var theta := randf() * TAU
	var radius := sqrt(randf()) * max_angle
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(direction).normalized()
	var offset := tan(radius)
	return (direction + right * offset * cos(theta) + up * offset * sin(theta)).normalized()


func _apply_recoil() -> void:
	var kick := Vector2.ZERO
	var pattern := stats.recoil_pattern
	if pattern.size() > 0:
		kick = pattern[mini(_pattern_index, pattern.size() - 1)]
	_pattern_index += 1
	kick.x += randf_range(-stats.recoil_random.x, stats.recoil_random.x)
	kick.y += randf_range(-stats.recoil_random.y, stats.recoil_random.y)
	# Pattern x is "right is positive" but camera yaw is "left is positive", so
	# the horizontal component is negated on the way in.
	_player.add_recoil(Vector2(deg_to_rad(-kick.x), deg_to_rad(kick.y)))


func _muzzle_flash() -> void:
	flash.rotation.z = randf() * TAU
	flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	_set_flash_visible(true)
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(0.035, true, true)
	timer.timeout.connect(_set_flash_visible.bind(false), CONNECT_ONE_SHOT)


func _set_flash_visible(value: bool) -> void:
	if is_instance_valid(flash):
		flash.visible = value
	if is_instance_valid(flash_light):
		flash_light.visible = value


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	if tracer_scene == null:
		return
	if _world == null:
		return
	var tracer := tracer_scene.instantiate()
	_world.add_child(tracer)
	if tracer.has_method("setup"):
		tracer.call("setup", from, to, stats.tracer_width, stats.tracer_lifetime)


func _spawn_impact(at: Vector3, normal: Vector3) -> void:
	if impact_scene == null:
		return
	if _world == null:
		return
	var impact := impact_scene.instantiate() as Node3D
	_world.add_child(impact)
	impact.global_position = at + normal * 0.02
	if impact.has_method("setup"):
		impact.call("setup", normal)
