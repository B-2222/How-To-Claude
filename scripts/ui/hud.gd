class_name HUD
extends Control
## Phase 1 HUD: the numbers you need to tune movement feel, plus a speed meter.
##
## The speed meter is not decoration. Bunny hopping is only satisfying if the
## player can SEE that a strafe worked, and a number alone is too slow to read
## mid-jump. The bar changes colour past sprint speed so gain is visible in
## peripheral vision while you are watching the crosshair.

@export var player_path: NodePath
@export var weapon_path: NodePath

@export_group("Speed meter")
@export var meter_size := Vector2(360.0, 12.0)
@export var meter_bottom_margin := 92.0
@export var slow_color := Color(0.55, 0.6, 0.7, 0.85)
@export var fast_color := Color(1.0, 0.72, 0.2, 0.95)
@export var peak_color := Color(1.0, 0.33, 0.5, 1.0)

var _player: Player
var _weapon: HitscanWeapon
var _peak_speed := 0.0

@onready var readout: Label = $Readout
@onready var help: Label = $Help


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = get_node_or_null(player_path) as Player
	_weapon = get_node_or_null(weapon_path) as HitscanWeapon
	help.visible = true


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"toggle_help"):
		help.visible = not help.visible
	if _player == null:
		return
	var speed := _player.horizontal_speed()
	_peak_speed = maxf(_peak_speed, speed)
	var lines := PackedStringArray()
	lines.append("%5.1f m/s   peak %5.1f" % [speed, _peak_speed])
	lines.append("state   %s" % _player.state_name())
	lines.append("spin    %4.0f deg / 1.5s" % _player.spin_degrees(1.5))
	if _weapon:
		lines.append("spread  %4.2f deg" % _weapon.current_spread)
	lines.append("dive    %s" % _dive_text())
	lines.append("fps     %d" % Engine.get_frames_per_second())
	readout.text = "\n".join(lines)
	queue_redraw()


func _dive_text() -> String:
	if _player.is_diving():
		return "ACTIVE"
	var ratio := _player.dive_cooldown_ratio()
	if ratio <= 0.0:
		return "READY"
	return "%0.1fs" % (ratio * _player.tuning.dive_cooldown)


func reset_peak() -> void:
	_peak_speed = 0.0


func _draw() -> void:
	if _player == null:
		return
	var origin := Vector2((size.x - meter_size.x) * 0.5, size.y - meter_bottom_margin)
	draw_rect(Rect2(origin - Vector2(2, 2), meter_size + Vector2(4, 4)), Color(0, 0, 0, 0.45))

	var reference := maxf(_player.tuning.max_air_speed, _player.tuning.sprint_speed * 2.0)
	var speed := _player.horizontal_speed()
	var fill := clampf(speed / reference, 0.0, 1.0)
	var walk_mark := clampf(_player.tuning.walk_speed / reference, 0.0, 1.0)
	var sprint_mark := clampf(_player.tuning.sprint_speed / reference, 0.0, 1.0)

	var color := slow_color
	if speed > _player.tuning.sprint_speed:
		var over := clampf((speed - _player.tuning.sprint_speed) / maxf(reference - _player.tuning.sprint_speed, 0.1), 0.0, 1.0)
		color = fast_color.lerp(peak_color, over)
	draw_rect(Rect2(origin, Vector2(meter_size.x * fill, meter_size.y)), color)

	# Reference ticks: anything right of the sprint tick was earned by strafing.
	for mark: float in [walk_mark, sprint_mark]:
		var x := origin.x + meter_size.x * mark
		draw_line(Vector2(x, origin.y - 3.0), Vector2(x, origin.y + meter_size.y + 3.0), Color(1, 1, 1, 0.5), 1.0)

	# Dive cooldown, directly under the speed meter.
	var dive_origin := origin + Vector2(0.0, meter_size.y + 8.0)
	var dive_ready := 1.0 - _player.dive_cooldown_ratio()
	draw_rect(Rect2(dive_origin, Vector2(meter_size.x, 4.0)), Color(0, 0, 0, 0.45))
	var dive_color := Color(0.35, 0.8, 1.0, 0.9) if dive_ready >= 1.0 else Color(0.35, 0.8, 1.0, 0.4)
	draw_rect(Rect2(dive_origin, Vector2(meter_size.x * dive_ready, 4.0)), dive_color)
