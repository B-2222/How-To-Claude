class_name Target
extends StaticBody3D
## A shootable target.
##
## Phase 2 reads [signal destroyed] to score the shot, which is why the signal
## carries the hit position and shooter rather than just firing bare.

signal damaged(amount: float, at: Vector3)
signal destroyed(target: Target, at: Vector3, by: Node)

@export var max_health := 100.0
## Seconds before the target comes back. 0 = stays dead.
@export var respawn_time := 2.5
@export var idle_color := Color(0.95, 0.32, 0.22)
@export var hit_color := Color(1.0, 0.95, 0.7)

var health := 0.0
var alive := true

var _material: StandardMaterial3D
var _flash := 0.0

@onready var mesh: MeshInstance3D = $Mesh
@onready var collider: CollisionShape3D = $Collider


func _ready() -> void:
	health = max_health
	# Unique material per target so one target flashing does not flash them all.
	_material = StandardMaterial3D.new()
	_material.albedo_color = idle_color
	_material.emission_enabled = true
	_material.emission = idle_color
	_material.emission_energy_multiplier = 0.4
	_material.roughness = 0.55
	mesh.material_override = _material


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_material.albedo_color = idle_color.lerp(hit_color, _flash)
	_material.emission = idle_color.lerp(hit_color, _flash)
	_material.emission_energy_multiplier = lerpf(0.4, 3.5, _flash)


func take_damage(amount: float, at: Vector3, by: Node) -> void:
	if not alive:
		return
	health -= amount
	_flash = 1.0
	damaged.emit(amount, at)
	if health <= 0.0:
		_die(at, by)


func _die(at: Vector3, by: Node) -> void:
	alive = false
	visible = false
	collider.set_deferred(&"disabled", true)
	destroyed.emit(self, at, by)
	if respawn_time > 0.0:
		# Respawn on an unscaled timer: dying during a slow-motion dive should
		# not also freeze the range.
		var timer := get_tree().create_timer(respawn_time, true, false, true)
		timer.timeout.connect(respawn)


func respawn() -> void:
	health = max_health
	alive = true
	visible = true
	_flash = 0.0
	_material.albedo_color = idle_color
	_material.emission = idle_color
	_material.emission_energy_multiplier = 0.4
	collider.set_deferred(&"disabled", false)
