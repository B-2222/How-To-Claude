class_name PlayerAudio
extends Node
## Movement sound, kept off player.gd so that file stays about physics.
##
## Every one-shot has its pitch multiplied by Engine.time_scale, so the whole
## soundscape drops into slow motion with the dive rather than the world going
## quiet and floaty while the audio stays normal speed.

@export var player_path: NodePath = ^".."
## Below this landing speed, landing is silent. Otherwise every hop chirps.
@export var land_threshold := 4.0

var _player: Player

@onready var jump_player: AudioStreamPlayer = $Jump
@onready var land_player: AudioStreamPlayer = $Land
@onready var slide_player: AudioStreamPlayer = $Slide
@onready var dive_player: AudioStreamPlayer = $Dive


func _ready() -> void:
	_player = get_node_or_null(player_path) as Player
	if _player == null:
		return
	_player.jumped.connect(_on_jumped)
	_player.landed.connect(_on_landed)
	_player.dive_started.connect(_on_dive_started)
	_player.state_changed.connect(_on_state_changed)


func _play(stream_player: AudioStreamPlayer, pitch := 1.0, volume_db := 0.0) -> void:
	if stream_player.stream == null:
		return
	stream_player.pitch_scale = clampf(Engine.time_scale, 0.25, 1.0) * pitch
	stream_player.volume_db = volume_db
	stream_player.play()


func _on_jumped() -> void:
	_play(jump_player, randf_range(0.95, 1.06), -8.0)


func _on_landed(impact_speed: float) -> void:
	if impact_speed < land_threshold:
		return
	# Louder and lower the harder you hit, so a big drop reads as a big drop.
	var weight := clampf(impact_speed / 22.0, 0.0, 1.0)
	_play(land_player, lerpf(1.12, 0.82, weight), lerpf(-14.0, -2.0, weight))


func _on_dive_started() -> void:
	_play(dive_player, 1.0, -6.0)


func _on_state_changed(_from: Player.State, to: Player.State) -> void:
	if to == Player.State.SLIDE:
		_play(slide_player, randf_range(0.95, 1.05), -9.0)
	elif slide_player.playing:
		slide_player.stop()
