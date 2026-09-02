extends Node3D
## Scene root for the Phase 1 test range. Owns nothing but restart and cleanup.

func _ready() -> void:
	randomize()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart"):
		# Reset time scale first: reloading mid-dive would otherwise leave the
		# fresh scene running at 0.3x forever.
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
