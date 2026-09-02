extends Node3D
## Scene root for the Phase 1 test range. Owns nothing but restart and cleanup.

@onready var world_environment: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	randomize()
	_apply_renderer_limits()


## The web build runs the Compatibility renderer, which cannot do everything the
## Forward+ desktop build can. Adjusting one environment here beats maintaining a
## second copy of the whole look.
##
## Directional shadows are turned OFF rather than retuned. Under Compatibility
## the nearest ~3.5 m of ground renders fully shadowed, and it is not a bias
## problem: sweeping bias, normal bias, split counts and shadow distance moves
## the boundary by less than 1% of the screen, and it reproduces with a stock
## StandardMaterial3D, so it is not the greybox shader either. Disabling the
## shadow pass is the only thing that clears it. A greybox loses little.
@export var disable_shadows_on_compatibility := true

func _apply_renderer_limits() -> void:
	# Compatibility runs on OpenGL and has no RenderingDevice; Forward+ does.
	var compatibility := RenderingServer.get_rendering_device() == null
	if not compatibility:
		return
	var environment := world_environment.environment
	if environment:
		# SSAO is a Forward+ feature; leaving it on just logs a warning.
		environment.ssao_enabled = false
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun and disable_shadows_on_compatibility:
		sun.shadow_enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart"):
		# Reset time scale first: reloading mid-dive would otherwise leave the
		# fresh scene running at 0.3x forever.
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
