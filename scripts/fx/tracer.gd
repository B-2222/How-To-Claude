class_name Tracer
extends MeshInstance3D
## A one-shot bullet streak.
##
## A stretched unlit box beats a particle system here: it is one draw call, it
## lands exactly on the line the trace took, and it can be spawned every frame
## of a 600 RPM burst without a hitch.

@export var color := Color(1.0, 0.82, 0.45, 0.9)

func setup(from: Vector3, to: Vector3, width: float, lifetime: float) -> void:
	var distance := from.distance_to(to)
	if distance < 0.05:
		queue_free()
		return
	global_position = (from + to) * 0.5
	# look_at points -Z at the target, which is the axis a BoxMesh's depth runs
	# along, so the box can just be scaled on Z to reach.
	var direction := (to - from) / distance
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	look_at(to, up)
	scale = Vector3(width, width, distance)

	# Per-instance material: tracers fade independently, so they cannot share.
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material

	# Tweens run on scaled time, so tracers stretch out during a slow-motion
	# dive. That is the intent: the dive should look like a replay.
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, lifetime)
	tween.parallel().tween_property(self, "scale:x", width * 0.2, lifetime)
	tween.parallel().tween_property(self, "scale:y", width * 0.2, lifetime)
	tween.tween_callback(queue_free)
