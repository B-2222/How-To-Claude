# Trickshot Range

An arena trickshot shooter in Godot 4.3 / GDScript. Points come from *how* you
hit a target, not from hitting it.

**Status: Phase 1 complete.** Movement and shooting feel only. No scoring yet.

---

## Playing it

**In a browser:** <https://b-2222.github.io/How-To-Claude/>. GitHub Pages serves
this repository's root branch, so `index.html` is a small landing page and
`web/index.html` is the game itself. Click the canvas to lock the mouse, press
Escape to release it.

**On desktop:** open the folder in Godot 4.3 or newer and press F5.
`scenes/main.tscn` is the main scene.

### Controls

| Input | Action |
| --- | --- |
| WASD | Move |
| Shift | Sprint |
| Space | Jump. **Hold** it to auto-hop on landing |
| C or Ctrl | Crouch, or slide if you are moving fast enough |
| Release it mid-slide | Slide-cancel |
| Q | Slow-motion dive |
| Left mouse | Fire |
| Right mouse | Aim down sights |
| F3 | Toggle the help overlay |
| Backspace | Restart the scene |
| Esc | Release the mouse |

In a browser, use **C** rather than Ctrl. Ctrl+W closes the tab and no page can
intercept it, so Ctrl plus a strafe is a trap. Both keys work everywhere.

### How to actually build speed

Jump, then in the air hold **one** strafe key and turn the mouse the same way,
smoothly and continuously. Do not hold W. Around 240 to 380 degrees per second
of turn is the sweet spot; too slow or too fast and you gain nothing. Hold Space
the whole time so you re-jump the instant you land.

The speed meter at the bottom of the screen has two tick marks: walk speed and
sprint speed. Everything to the right of the second tick was earned by strafing.

---

## Architecture

```
scripts/
  player/
    player.gd            CharacterBody3D controller. Ground/air accel, slide, dive.
    movement_tuning.gd   Resource. Every feel number lives here, nothing in player.gd.
    yaw_tracker.gd       Rolling yaw history. Phase 2 scores spins off this.
    camera_shake.gd      Noise-driven trauma shake, sits between head and camera.
    player_audio.gd      Listens to player signals. Keeps audio out of the controller.
  weapons/
    weapon_stats.gd      Resource. Damage, spread, recoil pattern, ADS.
    hitscan_weapon.gd    Traces from the camera, drives recoil/bloom/tracer/shake.
  targets/target.gd      Health, hit flash, respawn. Emits `destroyed` for Phase 2.
  fx/                    Tracer and impact, both self-freeing one-shots.
  ui/                    Crosshair, hitmarker, HUD.
  main.gd                Scene root. Restart only.
scenes/                  One .tscn per thing above.
resources/
  movement/*.tres        Three movement feel presets (see below).
  weapons/*.tres         Weapon stat blocks.
shaders/greybox_grid.gdshader
tools/                   Arena generator, sound generator, headless tests.
```

### Principles this follows, and why

**All feel is data.** `player.gd` contains no tuning constants; they are all in
`MovementTuning`, a Resource. You can swap presets on the Player node or drag
sliders in the inspector while the game runs. `HitscanWeapon` is the same with
`WeaponStats`. This is not tidiness for its own sake: Phase 3 attachments work by
producing a modified copy of a `WeaponStats`, so the weapon script never has to
learn what an attachment is.

**The arena is generated from a block list.** `tools/build_flat_range.py` emits
`scenes/arenas/flat_range.tscn`. Targets need to be *exactly* 30, 60 and 100 m
away for the Phase 2 distance tiers to mean anything, and hand-placing them in
the editor will not give you that. The output is a normal scene you can still
open and edit; re-running the generator overwrites it.

**Spin tracking samples input, not the camera.** Recoil, screen shake and view
roll all move the camera and none of them are the player spinning. `YawTracker`
takes raw mouse deltas, sums them **signed** so a wrist flick out and back nets
zero, and timestamps them with **unscaled** time so a slow-motion dive cannot
inflate the window.

**Anything on a clock uses unscaled time.** A dive sets `Engine.time_scale` to
0.3, which scales the delta handed to `_process` and `_physics_process`. Cooldowns,
the dive duration and the spin window are all fed `delta / Engine.time_scale`, so
"1.5 seconds of slow motion" means 1.5 seconds on your clock, not five.

### The movement maths

Two functions do the work, both lifted in shape from Quake and Source.

`_apply_friction` drops speed proportionally, except below `stop_speed`, where it
computes the drop *as if* you were moving at `stop_speed`. That floor is what
makes you actually stop instead of asymptotically drifting.

`_accelerate` limits your gain by how much speed you **already have along the
direction you are asking for**, not by your total speed. Hold W and your
projection onto the wish direction is your whole speed, so you cap out at run
speed. Point the wish direction 90 degrees off your velocity and the projection
is near zero, so you get the full per-tick gain while losing almost nothing to
the turn. That asymmetry is strafe jumping, surfing and air control, all of it.

Air movement is the same function with the target speed clamped to
`air_speed_cap`, well under one metre per second. Speed gain per second works out
at roughly `cap^2 * ticks / (2 * speed)`, which is why it scales with the *square*
of the cap and tapers off as you get faster.

**Tick rate is part of that formula.** Raw Source maths gives you `cap` metres per
tick, so a 240 Hz player would literally be twice as fast as a 120 Hz one.
`tickrate_normalised_air_cap` divides the cap by `tickrate / 60` to fix that. The
correction is exact only while `air_accel` is high enough that the clamp inside
`_accelerate` always resolves to the remaining headroom, which is why `air_accel`
defaults to 150 rather than Source's 10.

---

## Movement presets

Swap these on the Player node's `tuning` property.

| Preset | What it is |
| --- | --- |
| `default.tres` | Auto-hop on, jump buffer and coyote time, tick-normalised air cap, speed capped at 30 m/s. |
| `source_strict.tres` | No auto-hop, no jump buffer, no coyote time, no speed cap, tick-rate-dependent air cap. Authentic, and much harder. |
| `forgiving.tres` | Larger air cap, longer buffers, easier slide entry, shorter dive cooldown. |

---

## Design decisions with real trade-offs

These are choices where the alternative is defensible. Each is one value away
from being flipped.

**Auto-hop (`auto_hop`, default on).** With it, holding Space re-jumps the frame
you land and bunny hopping becomes a mouse-and-strafe skill. Without it, hopping
is a frame-timing test on top of that. Timing is a real skill and some players
love it, but it is a *different* skill from the aiming this game scores, and it
gates the movement behind something that has nothing to do with trickshots. On by
default; `source_strict.tres` turns it off.

**Tick-rate normalisation (`tickrate_normalised_air_cap`, default on).** Off is
authentic, and it means a player on a 240 Hz machine builds speed twice as fast
as one at 120 Hz. That is fine for a solo movement game and unacceptable once
there are leaderboards, which Phase 5 adds.

**Air speed cap of 1.4.** A clean strafe run gains about 3 m/s in the first
second, tapering to the 30 m/s ceiling after roughly 13 seconds of unbroken
hopping. Source and CS sit nearer 1.1, Quake-likes sit higher. Lower it for a
tighter skill ceiling, raise it for a faster game.

**Hard speed cap of 30 m/s.** True Quake has no cap. A cap keeps runs readable
and keeps Phase 2's distance tiers meaningful. Set `max_air_speed` to 0 to remove
it.

**Airborne hip-fire is genuinely bad** (`air_spread` 1.8 degrees, plus up to 2.4
from movement). An airborne no-scope at 30 m is a real gamble. That is deliberate:
Phase 2 pays a multiplier for exactly that shot, and it should not be free. Aiming
down sights multiplies total spread by 0.18, so the airborne *aimed* shot stays
practical.

**The crosshair gap is the real bullet cone**, projected through the camera FOV
into pixels. Most shooters animate a crosshair loosely. Making it honest means
"wait for it to close" is a true statement, which matters when the game is asking
you to shoot mid-air.

---

## The web build

Godot 4.3 has no Forward+ backend for the browser, so the web build runs the
Compatibility renderer on WebGL 2. Feature-tag overrides in `project.godot` keep
the desktop build on Forward+; only the browser drops down.

It is exported with **thread support off**. Threaded Godot web builds need
`SharedArrayBuffer`, which needs the COOP and COEP cross-origin isolation
headers, which GitHub Pages cannot set. A single-threaded build needs neither
and works on any static host.

To rebuild it, install the 4.3 export templates once, then:

```
godot --headless --path . --export-release "Web" web/index.html
```

Commit the result and push; GitHub Pages serves the branch directly, so the new
build is live once its Pages run finishes.

There is deliberately no CI build step. Exporting needs the Godot editor binary
plus the ~1 GB export template package, and fetching both on every push costs far
more than committing a 35 MB export. There is also deliberately no Pages
*workflow*: this repository already had the branch-based Pages builder enabled,
and two deployers racing over one site is worse than either alone.

To test the export locally, serve it over HTTP rather than opening the file
directly, because browsers block `fetch` on `file://`:

```
npx http-server web -p 8099
```

### Compatibility renderer differences

- **Directional shadows are switched off in the browser.** Under Compatibility
  the nearest few metres of ground render fully shadowed. It is not a bias
  problem: sweeping shadow bias, normal bias, split count and shadow distance
  moves the boundary by under 1% of the screen, and it reproduces with a stock
  `StandardMaterial3D`, so it is not the greybox shader either. Turning the
  shadow pass off is the only thing that clears it, and a greybox loses little.
  `Main.disable_shadows_on_compatibility` turns the workaround off.
- **SSAO is disabled**, because it is a Forward+ feature.
- MSAA and shadow filtering are lowered by `.web` overrides in `project.godot`.

## Known limitations at Phase 1

- The view model is a child of the main camera, so it clips into walls when you
  press against them. The standard fix is a second camera on a separate render
  layer. Deferred: it is a cosmetic problem and the gun is a greybox.
- Sounds in `audio/` are synthesised placeholders from `tools/make_sounds.py`.
  They exist so movement can be tuned with audio in the loop. Replace them.
- The uncrouch ceiling check is a single ray up the capsule's centre line, so a
  ledge overhanging only the edge of the capsule will not block standing.
- Labels use Godot's default proportional font, so the HUD readout columns do not
  align perfectly.
- The Forward+ desktop path could not be verified in the environment this was
  built in: it has software OpenGL but no software Vulkan, so every screenshot
  here is from the Compatibility renderer. Desktop is the better-tested Godot
  path, but it is unverified here.

---

## Tests

Both are headless and need no display.

```
godot --headless --path . --script tools/validate.gd   # loads every script, resource and scene
godot --headless --path . tools/runtime_test.tscn      # drives the player and checks the physics
```

`validate.gd` parses every script, loads every resource, instantiates every scene
and checks the input map matches what the code asks for.

`runtime_test.tscn` runs the real player with synthetic input and asserts the
behaviour the design claims: that friction brings you to a full stop, that holding
W on the ground cannot exceed sprint speed, that air strafing *does* exceed it,
that a slide-cancel keeps momentum, that a dive lasts 1.5 real seconds and
restores the time scale, that hitscan damages a target, and that a 180 out and
back does not register as a spin. It also sweeps turn rates and prints the speed
curve, which is the fastest way to see whether a tuning change helped:

```
turn    60 deg/s   peak  10.22 m/s
turn   120 deg/s   peak  12.53 m/s
turn   180 deg/s   peak  14.36 m/s
turn   240 deg/s   peak  15.65 m/s
turn   300 deg/s   peak  16.41 m/s
turn   380 deg/s   peak  16.10 m/s
turn   460 deg/s   peak  13.34 m/s
```

There is also a rendering probe. It needs a display but not a GPU, and writes
screenshots plus a numeric report to `user://`, so a lighting or renderer
regression can be measured rather than eyeballed:

```
xvfb-run -a godot --path . --rendering-method gl_compatibility \
  --rendering-driver opengl3 --resolution 1280x720 tools/screenshot_test.tscn
```

It prints `black rows` per shot, which counts unlit rows at the bottom of the
view. A healthy capture reads zero; the shadow bug above showed up as 29%.

Under `--headless` Godot's dummy renderer logs `Parameter "m" is null` for every
mesh with a `material_override`. It is renderer noise, not a project error, and
it does not happen in a real run.

---

## Roadmap

- **Phase 1 (done)** Movement and shooting feel.
- **Phase 2** Trickshot scoring. Modifiers as data in a scoring autoload, stacked
  multiplicatively, with a shot log and a slow-motion freeze on big shots.
- **Phase 3** Weapon modification. Attachments as `.tres` Resources with real
  stat conflicts, four base weapons, and a build multiplier for awkward setups.
- **Phase 4** The wager system. Stake banked run score on a timed challenge
  modifier; clear a target quota to get it back multiplied.
- **Phase 5** Progression, three arenas, local leaderboards, daily seeded run,
  and audio that tracks the combo meter.
