class_name CameraShake
extends Node3D
## Trauma-based screen shake sitting between the head and the camera.
##
## Shake is driven by sampling continuous noise rather than by picking a random
## offset each frame. Random-per-frame shake reads as a buzz; noise reads as a
## physical jolt because consecutive frames are correlated.
##
## Trauma decays linearly but is applied SQUARED, so a big hit falls off sharply
## and a small one barely registers. That keeps a long burst from turning into
## permanent nausea.

@export var decay := 4.2
@export var max_offset := Vector3(0.055, 0.055, 0.03)
@export var max_roll_deg := 3.2
## Higher = faster, sharper shake.
@export var frequency := 26.0

var trauma := 0.0

var _noise := FastNoiseLite.new()
var _t := 0.0

func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.6
	_noise.seed = randi()

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta * frequency
	if trauma <= 0.0:
		# Settle rather than snap, or the last frame of a burst pops.
		var k := 1.0 - exp(-18.0 * delta)
		position = position.lerp(Vector3.ZERO, k)
		rotation.z = lerpf(rotation.z, 0.0, k)
		return
	trauma = maxf(trauma - decay * delta, 0.0)
	var s := trauma * trauma
	position = Vector3(
		max_offset.x * s * _sample(0.0),
		max_offset.y * s * _sample(100.0),
		max_offset.z * s * _sample(200.0))
	rotation.z = deg_to_rad(max_roll_deg) * s * _sample(300.0)

func _sample(row: float) -> float:
	return _noise.get_noise_2d(row, _t)
