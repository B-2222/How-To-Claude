class_name WeaponStats
extends Resource
## Everything a weapon does, as data.
##
## Phase 3 turns attachments into Resources that produce a MODIFIED copy of one
## of these, so the weapon script never learns what an attachment is. Keep all
## behaviour-affecting numbers here and none of them in HitscanWeapon.

@export var display_name := "MK1 Rifle"

@export_group("Firing")
@export var damage := 34.0
@export var rounds_per_minute := 460.0
@export var automatic := true
## Metres. Beyond this the shot simply misses.
@export var max_range := 300.0

@export_group("Spread (degrees, half-angle of the cone)")
@export var base_spread := 0.12
## Multiplies total spread when fully aimed down sights.
@export var ads_spread_multiplier := 0.18
## Added at full sprint speed, scaled linearly by current speed.
@export var move_spread := 1.5
## Added flat while airborne. Airborne shots SHOULD be hard; Phase 2 pays you
## for landing them anyway.
@export var air_spread := 1.8
## Bloom added per shot, recovered at spread_recovery per second.
@export var spread_per_shot := 0.34
@export var max_spread := 5.5
@export var spread_recovery := 4.0

@export_group("Recoil")
## Per-shot camera kick in DEGREES: x = horizontal (+ right), y = vertical
## (+ up). Authored as a learnable pattern, the way a CS or Valorant spray is.
## Shots past the end of the array repeat the last entry.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array()
## Random jitter added on top, so the pattern is learnable but not a solved
## puzzle. x = horizontal, y = vertical, both +/-.
@export var recoil_random := Vector2(0.12, 0.10)
## Seconds of not firing before the pattern resets to shot 1.
@export var pattern_reset_time := 0.4
## How fast the camera reaches the kick. Higher = snappier.
@export var recoil_snap := 22.0
## How fast the kick decays back toward centre.
@export var recoil_recovery := 5.5

@export_group("Aim down sights")
@export var ads_time := 0.20
@export var ads_fov := 55.0

@export_group("Feel")
@export var screen_shake := 0.22
@export var tracer_width := 0.035
@export var tracer_lifetime := 0.09
