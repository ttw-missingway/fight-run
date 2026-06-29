extends RefCounted
class_name CombatTiming

## Central conversions between frames and seconds under the uniform combat
## slowdown, so all timing scales consistently from one tunable factor.

#region Constants

## Uniform combat slowdown — preserves frame ratios, gives more time to read mixups.
const FIGHT_TIMING_SCALE := 1.35

const SECONDS_PER_FRAME := (1.0 / 60.0) * FIGHT_TIMING_SCALE

#endregion


#region Public API

## Applies the combat slowdown to a raw duration in seconds.
static func scale_time(seconds: float) -> float:
	return seconds * FIGHT_TIMING_SCALE


## Converts a frame count to scaled seconds.
static func frames_to_seconds(frames: int) -> float:
	return float(frames) * SECONDS_PER_FRAME


## Converts scaled seconds back to a whole frame count.
static func seconds_to_frame(seconds: float) -> int:
	if SECONDS_PER_FRAME <= 0.0:
		return 0
	return int(seconds / SECONDS_PER_FRAME)


## Scales a hitstun duration, passing negative sentinels through unchanged.
static func scaled_hitstun(seconds: float) -> float:
	if seconds < 0.0:
		return seconds
	return scale_time(seconds)

#endregion
