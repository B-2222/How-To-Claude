class_name Impact
extends Node3D
## Bullet impact: a brief flash of light and an expanding unlit shell.

@export var lifetime := 0.16
@export var color := Color(1.0, 0.75, 0.4)

@onready var shell: MeshInstance3D = $Shell
@onready var light: OmniLight3D = $Light

func setup(normal: Vector3) -> void:
	if normal.length_squared() > 0.0001:
		# Orient the shell to the surface so it reads as a spark off the wall
		# rather than a ball floating in it.
		var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		look_at(global_position + normal, up)

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	shell.material_override = material

	scale = Vector3.ONE * 0.35
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, lifetime).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, lifetime)
	tween.parallel().tween_property(light, "light_energy", 0.0, lifetime * 0.6)
	tween.tween_callback(queue_free)
