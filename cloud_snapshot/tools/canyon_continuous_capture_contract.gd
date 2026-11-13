extends RefCounted
## Validation shared by the continuous direct-viewport recorder and its test.
## It deliberately knows nothing about route authority: it only refuses weak
## visual evidence after the existing session has produced it.

const MIN_CAPTURE_FPS := 10.0
const MAX_CAPTURE_FPS := 15.0
# ffprobe and decoded frame digests detect missing/frozen movie frames. This
# bound permits an individual post-draw observer scheduling hitch up to 200 ms
# at 10 Hz; the independent 10–15 Hz mean requirement remains authoritative.
const MAX_INTERVAL_FACTOR := 2.0
const MAX_PRESENTATION_ERROR := 0.01
const MAX_SPEED_RATIO_ERROR := 0.10
const MAX_VISUAL_STEP := 48.0

func validate_preconditions(display_server: String, output_writable: bool, single_demo_ready: bool) -> Dictionary:
	var errors: Array[String] = []
	if display_server.to_lower() == "headless":
		errors.append("headless")
	if not output_writable:
		errors.append("output")
	if not single_demo_ready:
		errors.append("single-worker-demo")
	return {"ok": errors.is_empty(), "errors": errors}

func validate(samples: Array, cycle_log: Array, target_hz := 12.0, require_visual_bridge := false) -> Dictionary:
	var errors: Array[String] = []
	var intervals: Array[float] = []
	var previous_msec := -1
	var previous_elapsed := -INF
	var prior_state := ""
	var phase := 0
	var bridge_phase := 0
	var return_bridge_phase := 0
	var saw_harvest_stationary := false
	for index in range(samples.size()):
		var sample: Dictionary = samples[index] if samples[index] is Dictionary else {}
		if int(sample.get("frame_number", -1)) != index + 1:
			errors.append("frame-number-%d" % (index + 1))
		var capture_msec := int(sample.get("capture_msec", -1))
		var elapsed := float(sample.get("session_elapsed", -1.0))
		if capture_msec < 0 or elapsed < 0.0:
			errors.append("timestamp-%d" % (index + 1))
		if previous_msec >= 0:
			var interval := float(capture_msec - previous_msec)
			if interval <= 0.0:
				errors.append("non-monotonic-wall-%d" % (index + 1))
			else:
				intervals.append(interval)
		if elapsed + 0.0001 < previous_elapsed:
			errors.append("non-monotonic-session-%d" % (index + 1))
		previous_msec = capture_msec
		previous_elapsed = elapsed
		if not bool(sample.get("conservation_ok", false)):
			errors.append("conservation-%d" % (index + 1))
		if float(sample.get("presentation_error", INF)) > MAX_PRESENTATION_ERROR:
			errors.append("presentation-%d" % (index + 1))
		var source_delta := float(sample.get("source_delta", 0.0))
		var foot_delta := float(sample.get("foot_delta", 0.0))
		if foot_delta > maxf(MAX_VISUAL_STEP, source_delta * 1.5 + 12.0):
			errors.append("visual-jump-%d" % (index + 1))
		if not _is_unit_scale(sample.get("scale", [])):
			errors.append("scale-%d" % (index + 1))
		var speed_ratio := float(sample.get("speed_ratio", -1.0))
		if speed_ratio >= 0.0 and absf(speed_ratio - 1.0) > MAX_SPEED_RATIO_ERROR:
			errors.append("speed-ratio-%d" % (index + 1))
		var state := str(sample.get("state", ""))
		var carried := int(sample.get("carried", 0))
		var depot := int(sample.get("depot", 0))
		if state == "to_resource" and phase == 0:
			phase = 1
		elif state == "harvesting":
			if phase < 1:
				errors.append("harvest-order-%d" % (index + 1))
			phase = max(phase, 2)
			saw_harvest_stationary = saw_harvest_stationary or bool(sample.get("foot_stationary", false))
		elif state == "to_base" and carried > 0:
			if phase < 2:
				errors.append("carry-order-%d" % (index + 1))
			phase = max(phase, 3)
		elif state == "dock_wait" and carried > 0:
			if phase < 3:
				errors.append("unload-order-%d" % (index + 1))
			phase = max(phase, 4)
		elif state == "to_resource" and phase >= 4 and carried == 0 and depot > 0:
			phase = 5
		var bridge_progress := float(sample.get("bridge_progress", -1.0))
		if state == "to_resource" and bridge_progress >= 0.0:
			if bridge_progress <= 0.20:
				if not _bridge_witness_matches(sample, "approach_near", require_visual_bridge):
					errors.append("bridge-entry-ground-%d" % (index + 1))
				bridge_phase = max(bridge_phase, 1)
			elif bridge_progress >= 0.40 and bridge_progress <= 0.60:
				if bridge_phase < 1:
					errors.append("bridge-deck-order-%d" % (index + 1))
				if not _bridge_witness_matches(sample, "deck", require_visual_bridge):
					errors.append("bridge-deck-ground-%d" % (index + 1))
				bridge_phase = max(bridge_phase, 2)
			elif bridge_progress >= 0.80:
				if bridge_phase < 2:
					errors.append("bridge-exit-order-%d" % (index + 1))
				if not _bridge_witness_matches(sample, "approach_far", require_visual_bridge):
					errors.append("bridge-exit-ground-%d" % (index + 1))
				bridge_phase = max(bridge_phase, 3)
		elif state == "to_base" and carried > 0 and bridge_progress >= 0.0:
			if bridge_progress >= 0.80:
				if not _bridge_witness_matches(sample, "approach_far", require_visual_bridge):
					errors.append("return-bridge-exit-ground-%d" % (index + 1))
				return_bridge_phase = max(return_bridge_phase, 1)
			elif bridge_progress >= 0.40 and bridge_progress <= 0.60:
				if return_bridge_phase < 1:
					errors.append("return-bridge-deck-order-%d" % (index + 1))
				if not _bridge_witness_matches(sample, "deck", require_visual_bridge):
					errors.append("return-bridge-deck-ground-%d" % (index + 1))
				return_bridge_phase = max(return_bridge_phase, 2)
			elif bridge_progress <= 0.20:
				if return_bridge_phase < 2:
					errors.append("return-bridge-entry-order-%d" % (index + 1))
				if not _bridge_witness_matches(sample, "approach_near", require_visual_bridge):
					errors.append("return-bridge-entry-ground-%d" % (index + 1))
				return_bridge_phase = max(return_bridge_phase, 3)
		prior_state = state
	if samples.size() < 2:
		errors.append("too-few-samples")
	if not saw_harvest_stationary:
		errors.append("harvest-foot")
	if phase < 5:
		errors.append("state-cycle")
	if bridge_phase < 3:
		errors.append("bridge-cycle")
	if require_visual_bridge and return_bridge_phase < 3:
		errors.append("return-bridge-cycle")
	if cycle_log.is_empty():
		errors.append("no-depot-cycle")
	for cycle in cycle_log:
		var entry: Dictionary = cycle if cycle is Dictionary else {}
		if int(entry.get("depot_after", 0)) <= int(entry.get("depot_before", 0)) or int(entry.get("carried", -1)) != 0 or not bool(entry.get("conservation_ok", false)):
			errors.append("depot-cycle-%d" % int(entry.get("cycle", -1)))
	var mean_interval := 0.0
	var max_interval := 0.0
	if not intervals.is_empty():
		for interval in intervals:
			mean_interval += interval
			max_interval = maxf(max_interval, interval)
		mean_interval /= float(intervals.size())
	var actual_fps := 1000.0 / mean_interval if mean_interval > 0.0 else 0.0
	var target_interval := 1000.0 / maxf(target_hz, 0.001)
	if actual_fps < MIN_CAPTURE_FPS or actual_fps > MAX_CAPTURE_FPS:
		errors.append("capture-fps")
	if max_interval > target_interval * MAX_INTERVAL_FACTOR:
		errors.append("capture-gap")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"sample_count": samples.size(),
		"average_interval_msec": mean_interval,
		"max_interval_msec": max_interval,
		"actual_fps": actual_fps,
		"state_phase": phase,
		"bridge_phase": bridge_phase,
		"return_bridge_phase": return_bridge_phase,
		"require_visual_bridge": require_visual_bridge,
	}

## The direct X11 movie and the Godot post-draw observer have different clocks.
## This verifies that the work sequence represented by the state observer is
## actually present before the movie stops; it intentionally does not require a
## one-to-one metadata record for every encoded video frame.
func validate_video_window(samples: Array, cycle_log: Array, video_duration_msec: int, expected_cycles := 1, safe_margin_msec := 0, require_visual_bridge := false) -> Dictionary:
	var errors: Array[String] = []
	if video_duration_msec <= 0:
		errors.append("video-duration")
	if expected_cycles <= 0:
		errors.append("video-expected-cycles")
	if safe_margin_msec < 0 or safe_margin_msec * 2 >= video_duration_msec:
		errors.append("video-safe-margin")
	var samples_by_frame := {}
	var in_window: Array[Dictionary] = []
	var previous_frame := 0
	var previous_msec := -1
	for index in range(samples.size()):
		var sample: Dictionary = samples[index] if samples[index] is Dictionary else {}
		var frame_number := int(sample.get("frame_number", -1))
		var video_elapsed_msec := int(sample.get("video_elapsed_msec", -1))
		if frame_number <= previous_frame or video_elapsed_msec <= previous_msec:
			errors.append("video-timestamp-%d" % (index + 1))
			continue
		previous_frame = frame_number
		previous_msec = video_elapsed_msec
		# Process creation and X11 sampling do not share an exact origin. A
		# strict caller reserves both edges so required events are well inside
		# encoded frames, including the final PTS before nominal duration.
		if video_elapsed_msec < safe_margin_msec or video_elapsed_msec > video_duration_msec - safe_margin_msec:
			continue
		samples_by_frame[frame_number] = sample
		in_window.append(sample)
	if cycle_log.size() < expected_cycles:
		errors.append("video-cycle-count")
	var previous_deposit_frame := 0
	var previous_depot := -1
	var completed_cycles := 0
	for cycle_index in range(mini(cycle_log.size(), maxi(expected_cycles, 0))):
		var entry: Dictionary = cycle_log[cycle_index] if cycle_log[cycle_index] is Dictionary else {}
		var cycle_number := cycle_index + 1
		var cycle_frame := int(entry.get("frame_number", -1))
		var depot_before := int(entry.get("depot_before", -1))
		var depot_after := int(entry.get("depot_after", -1))
		if int(entry.get("cycle", -1)) != cycle_number or cycle_frame <= previous_deposit_frame or (previous_depot >= 0 and depot_before != previous_depot):
			errors.append("video-cycle-order-%d" % cycle_number)
		if not samples_by_frame.has(cycle_frame):
			errors.append("video-cycle-outside-%d" % cycle_number)
			continue
		var cycle_sample: Dictionary = samples_by_frame[cycle_frame]
		var phase := 0
		var return_bridge_phase := 0
		var dock_cargo := -1
		var restarted := false
		var next_deposit_frame := int((cycle_log[cycle_index + 1] as Dictionary).get("frame_number", -1)) if cycle_index + 1 < cycle_log.size() and cycle_log[cycle_index + 1] is Dictionary else 2147483647
		for sample in in_window:
			var frame_number := int(sample.get("frame_number", -1))
			var state := str(sample.get("state", ""))
			var carried := int(sample.get("carried", -1))
			var depot := int(sample.get("depot", -1))
			if frame_number >= cycle_frame and frame_number < next_deposit_frame and state == "to_resource" and carried == 0 and depot == depot_after:
				restarted = true
			if frame_number <= previous_deposit_frame or frame_number >= cycle_frame:
				continue
			var progress := float(sample.get("bridge_progress", -1.0))
			if depot != depot_before or not bool(sample.get("conservation_ok", false)):
				errors.append("video-cycle-conservation-%d" % cycle_number)
			if state == "to_resource" and carried == 0 and progress >= 0.0:
				if phase == 0 and progress <= 0.20:
					if not _bridge_witness_matches(sample, "approach_near", require_visual_bridge):
						errors.append("video-bridge-entry-ground-%d-%d" % [cycle_number, frame_number])
					phase = 1
				elif phase == 1 and progress >= 0.40 and progress <= 0.60:
					if not _bridge_witness_matches(sample, "deck", require_visual_bridge):
						errors.append("video-bridge-deck-ground-%d-%d" % [cycle_number, frame_number])
					phase = 2
				elif phase == 2 and progress >= 0.80:
					if not _bridge_witness_matches(sample, "approach_far", require_visual_bridge):
						errors.append("video-bridge-exit-ground-%d-%d" % [cycle_number, frame_number])
					phase = 3
			elif phase == 3 and state == "harvesting" and bool(sample.get("foot_stationary", false)):
				phase = 4
			elif phase >= 4 and state == "to_base" and carried > 0:
				if progress >= 0.80:
					if not _bridge_witness_matches(sample, "approach_far", require_visual_bridge):
						errors.append("video-return-bridge-exit-ground-%d-%d" % [cycle_number, frame_number])
					return_bridge_phase = max(return_bridge_phase, 1)
				elif progress >= 0.40 and progress <= 0.60:
					if return_bridge_phase < 1:
						errors.append("video-return-bridge-deck-order-%d-%d" % [cycle_number, frame_number])
					if not _bridge_witness_matches(sample, "deck", require_visual_bridge):
						errors.append("video-return-bridge-deck-ground-%d-%d" % [cycle_number, frame_number])
					return_bridge_phase = max(return_bridge_phase, 2)
				elif progress >= 0.0 and progress <= 0.20:
					if return_bridge_phase < 2:
						errors.append("video-return-bridge-entry-order-%d-%d" % [cycle_number, frame_number])
					if not _bridge_witness_matches(sample, "approach_near", require_visual_bridge):
						errors.append("video-return-bridge-entry-ground-%d-%d" % [cycle_number, frame_number])
					return_bridge_phase = max(return_bridge_phase, 3)
				phase = max(phase, 5)
			elif phase == 5 and state == "dock_wait" and carried > 0:
				phase = 6
				dock_cargo = carried
		if phase != 6:
			errors.append("video-cycle-sequence-%d" % cycle_number)
		if require_visual_bridge and return_bridge_phase < 3:
			errors.append("video-return-bridge-cycle-%d" % cycle_number)
		if not restarted:
			errors.append("video-cycle-restart-%d" % cycle_number)
		if depot_before < 0 or depot_after <= depot_before or depot_after - depot_before != dock_cargo or int(entry.get("carried", -1)) != 0 or not bool(entry.get("conservation_ok", false)) or not bool(cycle_sample.get("conservation_ok", false)) or int(cycle_sample.get("carried", -1)) != 0 or int(cycle_sample.get("depot", -1)) != depot_after:
			errors.append("video-cycle-state-%d" % cycle_number)
		# Old v4 traces predate HUD snapshots. New multi-cycle evidence must
		# supply the actual displayed text at every deposit in both witnesses.
		if expected_cycles > 1 or cycle_sample.has("status_text") or cycle_sample.has("detail_text"):
			if not _deposit_hud_matches(cycle_sample) or str(entry.get("status_text", "")) != str(cycle_sample.get("status_text", "")) or str(entry.get("detail_text", "")) != str(cycle_sample.get("detail_text", "")):
				errors.append("video-cycle-hud-%d" % cycle_number)
		previous_deposit_frame = cycle_frame
		previous_depot = depot_after
		if phase == 6 and restarted and (not require_visual_bridge or return_bridge_phase >= 3):
			completed_cycles += 1
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"video_sample_count": samples_by_frame.size(),
		"expected_cycles": expected_cycles,
		"completed_cycles": completed_cycles,
		"safe_margin_msec": safe_margin_msec,
		"require_visual_bridge": require_visual_bridge,
	}

func _bridge_witness_matches(sample: Dictionary, expected_region: String, require_visual_bridge: bool) -> bool:
	if not require_visual_bridge:
		return true
	if not bool(sample.get("bridge_path", false)):
		return false
	if require_visual_bridge and str(sample.get("bridge_region", "")) != expected_region:
		return false
	if expected_region == "deck" and not bool(sample.get("bridge_deck", false)):
		return false
	return true

## framemd5 includes comments and may be accompanied by non-row diagnostics.
## Accept only complete frame rows, preserving their decoded order.
func parse_frame_digest_rows(raw: String) -> Array:
	var row := RegEx.new()
	row.compile("^\\s*\\d+,\\s*-?\\d+,\\s*-?\\d+,\\s*\\d+,\\s*\\d+,\\s*([0-9a-fA-F]{32})\\s*$")
	var digests: Array = []
	for line in raw.split("\n"):
		var matched := row.search(line)
		if matched != null:
			digests.append(matched.get_string(1).to_lower())
	return digests

func _deposit_hud_matches(sample: Dictionary) -> bool:
	var status := RegEx.new()
	status.compile("鉱\\s+(\\d+)\\s+中継\\s+(\\d+)\\s+拠点\\s+(\\d+)")
	var status_match := status.search(str(sample.get("status_text", "")))
	var detail := RegEx.new()
	detail.compile("単独追跡 .+ / 手(\\d+) / 拠点(\\d+)")
	var detail_match := detail.search(str(sample.get("detail_text", "")))
	if status_match == null or detail_match == null:
		return false
	return int(status_match.get_string(1)) == int(sample.get("source_remaining", -1)) and int(status_match.get_string(3)) == int(sample.get("depot", -1)) and int(detail_match.get_string(1)) == 0 and int(detail_match.get_string(2)) == int(sample.get("depot", -1))

## Exact decoded-frame equality detects output freezes only. It does not
## establish whether a moving worker is readable in the full-map viewport.
func validate_frame_digest_sequence(frame_digests: Array, expected_frames: int) -> Dictionary:
	var errors: Array[String] = []
	if expected_frames <= 0 or frame_digests.size() != expected_frames:
		errors.append("frame-digest-count")
	var previous := ""
	var run := 0
	var longest_run := 0
	for index in range(frame_digests.size()):
		var digest := str(frame_digests[index]).strip_edges() if frame_digests[index] is String else ""
		if digest.is_empty():
			errors.append("frame-digest-empty-%d" % (index + 1))
		run = run + 1 if digest == previous else 1
		longest_run = maxi(longest_run, run)
		previous = digest
	if longest_run > 2:
		errors.append("frame-digest-frozen-run")
	return {"ok": errors.is_empty(), "errors": errors, "expected_frames": expected_frames, "decoded_frames": frame_digests.size(), "longest_identical_run": longest_run, "note": "Decoded equality audit only; worker readability requires visual review."}

## Probe the finalized movie separately from the observer trace.  A stopped
## encoder and a nonempty file are not sufficient: the decodable movie must
## still have the requested duration, frame count, size, and video-only stream.
func validate_video_probe(probe: Dictionary, target_hz: float, expected_duration_msec: int, expected_width := 1280, expected_height := 720) -> Dictionary:
	var errors: Array[String] = []
	var streams_variant = probe.get("streams", [])
	var streams: Array = streams_variant if streams_variant is Array else []
	if streams.size() != 1 or not (streams[0] is Dictionary):
		errors.append("video-probe-stream-count")
		return {"ok": false, "errors": errors}
	var stream: Dictionary = streams[0]
	if str(stream.get("codec_type", "")) != "video":
		errors.append("video-probe-type")
	if str(stream.get("codec_name", "")) != "h264":
		errors.append("video-probe-codec")
	if int(stream.get("width", -1)) != expected_width or int(stream.get("height", -1)) != expected_height:
		errors.append("video-probe-size")
	var actual_hz := _parse_rate(stream.get("avg_frame_rate", ""))
	if actual_hz <= 0.0 or absf(actual_hz - target_hz) > 0.001:
		errors.append("video-probe-rate")
	var expected_frames := int(round(target_hz * float(expected_duration_msec) / 1000.0))
	var decoded_frames := int(stream.get("nb_read_frames", -1))
	if decoded_frames != expected_frames:
		errors.append("video-probe-frames")
	var format_variant = probe.get("format", {})
	var format: Dictionary = format_variant if format_variant is Dictionary else {}
	var duration_seconds := float(format.get("duration", -1.0))
	var expected_seconds := float(expected_duration_msec) / 1000.0
	if duration_seconds <= 0.0 or absf(duration_seconds - expected_seconds) > 0.05:
		errors.append("video-probe-duration")
	if int(format.get("size", 0)) < 1024:
		errors.append("video-probe-size-empty")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"codec": str(stream.get("codec_name", "")),
		"width": int(stream.get("width", -1)),
		"height": int(stream.get("height", -1)),
		"actual_hz": actual_hz,
		"decoded_frames": decoded_frames,
		"duration_seconds": duration_seconds,
	}

func _parse_rate(value: Variant) -> float:
	var raw := str(value)
	var parts := raw.split("/", false)
	if parts.size() == 2:
		var numerator := float(parts[0])
		var denominator := float(parts[1])
		return numerator / denominator if absf(denominator) > 0.000001 else -1.0
	return float(raw)

func _is_unit_scale(value: Variant) -> bool:
	if value is Vector2:
		var vector: Vector2 = value as Vector2
		return is_equal_approx(vector.x, 1.0) and is_equal_approx(vector.y, 1.0)
	if value is Array and (value as Array).size() == 2:
		var parts: Array = value as Array
		return is_equal_approx(float(parts[0]), 1.0) and is_equal_approx(float(parts[1]), 1.0)
	return false
