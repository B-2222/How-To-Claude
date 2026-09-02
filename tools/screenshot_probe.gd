extends Node
## Captures the arena from several vantage points and measures the result, so a
## renderer or lighting regression can be caught without a desktop.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1280x720 tools/screenshot_test.tscn
##
## Test rig only; not part of any shipped scene.

const SHOTS := [
	{"name": "spawn", "pos": Vector3(0.0, 0.0, 42.0), "yaw": 0.0, "pitch": -0.05},
	{"name": "hop_course", "pos": Vector3(-34.0, 6.0, 32.0), "yaw": 0.35, "pitch": -0.30},
	{"name": "platforms", "pos": Vector3(14.0, 4.0, 26.0), "yaw": -0.55, "pitch": -0.12},
	{"name": "tower", "pos": Vector3(38.0, 15.0, -30.0), "yaw": 2.6, "pitch": -0.35},
]

var player: Player
var _frames := 0


func _ready() -> void:
	player = get_parent().get_node("Main/Player") as Player


func _process(_delta: float) -> void:
	_frames += 1
	# Let shaders compile and the first frames settle before capturing.
	if _frames < 60:
		return
	set_process(false)
	_run()


func _run() -> void:
	for shot: Dictionary in SHOTS:
		player.global_position = shot["pos"]
		player.velocity = Vector3.ZERO
		player.look_yaw = shot["yaw"]
		player.look_pitch = shot["pitch"]
		for i in 3:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "user://shot_%s.png" % shot["name"]
		image.save_png(path)
		print("%-12s %s  %s" % [shot["name"], ProjectSettings.globalize_path(path), _describe(image)])
	get_tree().quit()


## Reports black rows at the bottom of the view and mean brightness. A healthy
## capture has zero black rows: the floor should reach the bottom of the screen.
func _describe(image: Image) -> String:
	var height := image.get_height()
	var column := int(image.get_width() * 0.15)
	var last_lit := -1
	for y in range(height - 1, -1, -1):
		var c := image.get_pixel(column, y)
		if c.r + c.g + c.b > 0.02:
			last_lit = y
			break
	var total := 0.0
	var samples := 0
	for y in range(0, height, 8):
		for x in range(0, image.get_width(), 8):
			var c := image.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
			samples += 1
	return "black rows=%d  mean brightness=%.3f" % [height - 1 - last_lit, total / samples]
