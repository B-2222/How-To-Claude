class_name MovementTuning
extends Resource
## Every number that decides how the player feels to control.
##
## Kept in a Resource so feel can be tuned live in the inspector while playing,
## and so alternate feels (strict Source, forgiving arcade) can ship as .tres
## presets that are swapped on the Player node without touching code.
##
## UNITS: 1 unit = 1 metre, 1 second = 1 second. Source engine cvars are in
## inches per second (1 m = 39.37 u), so these do not match sv_* values
## numerically even though the maths is the same shape.

@export_group("Ground speed")
## Base run speed with no modifiers.
@export var walk_speed := 7.2
## Held-sprint speed. Deliberately close to walk_speed: sprint is a small top-up,
## because the real speed in this game comes from bunny hopping, not from a key.
@export var sprint_speed := 9.4
@export var crouch_speed := 3.6
## How hard the player is pulled toward wish_speed on the ground. High values
## feel instant/arcadey, low values feel icy.
@export var ground_accel := 14.0
## Ground friction coefficient (Source sv_friction).
@export var friction := 6.2
## Friction floor. Below this speed friction is computed as if you were moving
## at stop_speed, which is what makes you actually stop instead of creeping.
@export var stop_speed := 2.2

@export_group("Air control")
## Source sv_airaccelerate. Kept high on purpose so the min() in _air_accelerate
## always resolves to add_speed, which is what makes the tick-rate normalisation
## below exact rather than approximate.
@export var air_accel := 150.0
## THE bunny hop number: the most speed you may gain per physics tick along your
## wish direction while airborne, before tick normalisation.
##
## Speed gain per second works out at roughly (cap^2 * ticks) / (2 * speed), so
## it scales with the SQUARE of this value and falls off as you get faster.
## 1.4 puts a clean strafe run at about +3 m/s in the first second, tapering to
## the max_air_speed ceiling after ~13 s of unbroken hopping. Source/CS sits
## nearer 1.1; Quake-likes sit higher.
@export var air_speed_cap := 1.4
## Divide air_speed_cap by (tick rate / 60) so speed gain per SECOND is identical
## at 60 Hz and 240 Hz. Turn off for raw Source behaviour where a higher tick
## rate literally makes you faster.
@export var tickrate_normalised_air_cap := true
## Hard ceiling on horizontal air speed. 0 = uncapped (true Quake). ~4x walk
## speed keeps runs readable without feeling like a wall.
@export var max_air_speed := 30.0
@export var gravity := 21.0
@export var jump_velocity := 6.4

@export_group("Jump forgiveness")
## Holding jump auto-hops on landing. Without this, bunny hopping is a timing
## test; with it, it is a mouse-and-strafe test. See README trade-offs.
@export var auto_hop := true
## Pressing jump this long before landing still jumps.
@export var jump_buffer := 0.12
## Jumping this long after walking off a ledge still jumps.
@export var coyote_time := 0.10

@export_group("Stance")
@export var stand_height := 1.8
@export var crouch_height := 1.05
## Metres from the top of the capsule down to the eye.
@export var head_offset := 0.2
## How fast the capsule and camera blend between stances.
@export var stance_speed := 14.0

@export_group("Slide")
## Minimum horizontal speed required to start a slide.
@export var slide_min_speed := 6.0
## Speed the slide snaps you to on entry (if you were slower). The small boost
## is what makes slide-into-shot worth doing.
@export var slide_entry_speed := 12.0
## Much lower than ground friction, so a slide carries. At 0.45 a 12 m/s slide
## still has ~6.5 m/s left after a full 1.4 s, which is what makes sliding into
## a shot a real option rather than a way to stop moving.
@export var slide_friction := 0.45
## Radians per second you may bend the slide direction. Low = committed.
@export var slide_steer := 2.4
## Slide ends naturally below this speed.
@export var slide_exit_speed := 4.0
@export var slide_max_time := 1.4
## Cooldown after a slide runs out on its own.
@export var slide_cooldown := 0.45
## Cooldown after a slide-CANCEL. Shorter, so cancelling is the skilled option.
@export var slide_cancel_cooldown := 0.18
## Extra acceleration applied along a downhill slope while sliding.
@export var slide_slope_accel := 14.0

@export_group("Dive")
@export var dive_time_scale := 0.3
## Real seconds (not slowed seconds) the dive lasts.
@export var dive_duration := 1.5
@export var dive_cooldown := 6.0
@export var dive_up_velocity := 5.2
## Multiplies your current speed into the leap.
@export var dive_forward_boost := 1.25
## Floor on the leap so a standing dive still goes somewhere.
@export var dive_min_speed := 8.0
## Air acceleration is scaled by this during a dive. Below 1 the dive is a
## commitment; at 1 you can steer out of your own mistake.
@export var dive_air_control := 0.55

@export_group("Camera feel")
@export var strafe_roll_deg := 1.4
@export var slide_roll_deg := 6.0
@export var roll_speed := 9.0
## Dip on landing, scaled by impact speed.
@export var land_dip := 0.18
@export var bob_rate := 1.1
@export var bob_amount := 0.035
## Degrees of FOV gained per m/s above sprint speed. Sells the bunny hop.
@export var fov_per_speed := 1.1
@export var fov_max_gain := 22.0
@export var dive_fov_gain := 10.0
@export var fov_blend_speed := 7.0

@export_group("Collision")
@export var floor_max_angle_deg := 47.0
@export var floor_snap_length := 0.25
