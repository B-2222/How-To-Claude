class_name Crosshair
extends Control
## Four-line expanding crosshair.
##
## The gap is not a decorative animation. It is the weapon's real cone
## half-angle projected into screen pixels through the camera's FOV, so the gap
## literally bounds where a bullet can land. That makes "wait for the crosshair
## to close" a true statement rather than a vibe, which is the whole reason to
## have an expanding crosshair at all.

@export var weapon_path: NodePath
@export var camera_path: NodePath
@export var line_length := 8.0
@export var thickness := 2.0
@export var min_gap := 3.0
@export var idle_color := Color(0.94, 0.96, 1.0, 0.9)
@export var hit_color := Color(1.0, 0.35, 0.25, 1.0)
@export var outline_color := Color(0.0, 0.0, 0.0, 0.55)

var _weapon: HitscanWeapon
var _camera: Camera3D
var _gap := 4.0
var _hit_flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon = get_node_or_null(weapon_path) as HitscanWeapon
	_camera = get_node_or_null(camera_path) as Camera3D
	if _weapon:
		_weapon.hit_confirmed.connect(func(_shot: Dictionary) -> void: _hit_flash = 1.0)


func _process(delta: float) -> void:
	_hit_flash = maxf(_hit_flash - delta * 4.0, 0.0)
	var target_gap := min_gap
	if _weapon and _camera:
		# Godot's Camera3D.fov is the VERTICAL field of view under the default
		# keep-height mode, so the projection uses viewport height.
		var half_fov := deg_to_rad(_camera.fov * 0.5)
		var pixels := (tan(deg_to_rad(_weapon.current_spread)) / tan(half_fov)) * (size.y * 0.5)
		target_gap = min_gap + pixels
	# Smoothed so bloom reads as an expansion rather than a stutter.
	_gap = lerpf(_gap, target_gap, 1.0 - exp(-18.0 * delta))
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var color := idle_color.lerp(hit_color, _hit_flash)
	var offsets := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for direction: Vector2 in offsets:
		var from := centre + direction * _gap
		var to := from + direction * line_length
		# Dark underlay first, so the crosshair stays readable on a light wall.
		draw_line(from, to, outline_color, thickness + 2.0)
	for direction: Vector2 in offsets:
		var from := centre + direction * _gap
		var to := from + direction * line_length
		draw_line(from, to, color, thickness)
	draw_rect(Rect2(centre - Vector2.ONE, Vector2(2.0, 2.0)), color)
