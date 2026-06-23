extends RefCounted
class_name CombatTiming

## Uniform combat slowdown — preserves frame ratios, gives more time to read mixups.
const FIGHT_TIMING_SCALE := 1.35

const SECONDS_PER_FRAME := (1.0 / 60.0) * FIGHT_TIMING_SCALE


static func scale_time(seconds: float) -> float:
	return seconds * FIGHT_TIMING_SCALE


static func frames_to_seconds(frames: int) -> float:
	return float(frames) * SECONDS_PER_FRAME


static func seconds_to_frame(seconds: float) -> int:
	if SECONDS_PER_FRAME <= 0.0:
		return 0
	return int(seconds / SECONDS_PER_FRAME)


static func scaled_hitstun(seconds: float) -> float:
	if seconds < 0.0:
		return seconds
	return scale_time(seconds)
