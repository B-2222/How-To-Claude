class_name YawTracker
extends RefCounted
## Rolling history of raw yaw input, so the scorer can ask
## "how far did the player spin in the last N seconds?".
##
## Three details matter and are easy to get wrong:
##
## 1. It samples MOUSE INPUT, not the camera transform. Recoil, screen shake and
##    view roll all move the camera, and none of them are the player spinning.
##
## 2. Deltas are SIGNED and summed. Whipping 180 degrees left then 180 right
##    nets zero, so only a genuine continuous rotation scores. Taking abs() per
##    sample instead would let a shake of the wrist count as a 720.
##
## 3. Timestamps use UNSCALED time. A slow-motion dive stretches engine delta by
##    ~3.3x; if the window used scaled time, a dive would silently widen the
##    spin window and hand out free 360s.

## Longest window we retain. Phase 2 asks for 1.5s; keeping more costs nothing
## and lets modifiers query different windows later.
const HISTORY_SECONDS := 3.0

var _times := PackedFloat32Array()
var _deltas := PackedFloat32Array()
var _clock := 0.0

## Feed unscaled seconds once per frame. Also evicts samples past the window.
func advance(real_delta: float) -> void:
	_clock += real_delta
	var cutoff := _clock - HISTORY_SECONDS
	var drop := 0
	while drop < _times.size() and _times[drop] < cutoff:
		drop += 1
	if drop > 0:
		_times = _times.slice(drop)
		_deltas = _deltas.slice(drop)

## Feed every yaw change from mouse look, in radians, sign included.
func push(delta_yaw_rad: float) -> void:
	_times.push_back(_clock)
	_deltas.push_back(delta_yaw_rad)

## Net rotation over the last `window` seconds, in degrees, always positive.
func degrees_in(window: float) -> float:
	var cutoff := _clock - window
	var total := 0.0
	for i in range(_times.size() - 1, -1, -1):
		if _times[i] < cutoff:
			break
		total += _deltas[i]
	return absf(rad_to_deg(total))

## Signed net rotation, for telling a left spin from a right spin.
func signed_degrees_in(window: float) -> float:
	var cutoff := _clock - window
	var total := 0.0
	for i in range(_times.size() - 1, -1, -1):
		if _times[i] < cutoff:
			break
		total += _deltas[i]
	return rad_to_deg(total)

func clear() -> void:
	_times.clear()
	_deltas.clear()
