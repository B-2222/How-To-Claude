class_name Hitmarker
extends Control
## Four diagonal ticks that pop on a confirmed hit and shrink as they fade.

@export var weapon_path: NodePath
@export var inner := 5.0
@export var outer := 12.0
@export var thickness := 2.0
@export var duration := 0.22
@export var hit_color := Color(1.0, 1.0, 1.0, 1.0)
@export var kill_color := Color(1.0, 0.42, 0.25, 1.0)

var _life := 0.0
var _color := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var weapon := get_node_or_null(weapon_path) as HitscanWeapon
	if weapon:
		weapon.hit_confirmed.connect(_on_hit)


func _on_hit(_shot: Dictionary) -> void:
	pop(false)


## [param killed] switches to the louder colour. Phase 2 calls this with true
## once a hit actually finishes a target.
func pop(killed: bool) -> void:
	_life = 1.0
	_color = kill_color if killed else hit_color
	queue_redraw()


func _process(delta: float) -> void:
	if _life <= 0.0:
		return
	_life = maxf(_life - delta / duration, 0.0)
	queue_redraw()


func _draw() -> void:
	if _life <= 0.0:
		return
	var centre := size * 0.5
	# Ticks start pushed out and snap inward: the motion is what the eye reads,
	# more than the shape.
	var spread := 1.0 + _life * 0.55
	var color := Color(_color.r, _color.g, _color.b, _color.a * _life)
	for diagonal: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var unit := diagonal.normalized()
		draw_line(centre + unit * inner * spread, centre + unit * outer * spread, Color(0, 0, 0, color.a * 0.5), thickness + 2.0)
	for diagonal: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var unit := diagonal.normalized()
		draw_line(centre + unit * inner * spread, centre + unit * outer * spread, color, thickness)
