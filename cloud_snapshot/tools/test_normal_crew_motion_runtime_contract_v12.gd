extends SceneTree
## Validates direct normal-role runtime evidence. It deliberately rejects the
## deterministic 0.2-second still harness used by the v11 progression proof.

const BEFORE_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/normal_crew_motion_runtime_v12_before.json"
const AFTER_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/normal_crew_motion_runtime_v12_after.json"
const CAPTURE_SOURCE_URI := "res://tools/capture_normal_crew_motion_runtime_v12.gd"
const V11_ARCHIVE_SHA256 := "3357de7b4b7222348759b9d47ccedb5d5078ecdd929b0d231bf22bc979e5387c"
const V11_CREW_VIEWS_SHA256 := "82a38763f996a8a90c2d449a7166c17eda593d129e11149439f5a1d499df7af2"
const VIDEO_DURATION_SECONDS := 12.0
const VIDEO_FRAME_COUNT := 120

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _read(uri: String) -> Dictionary:
	if not FileAccess.file_exists(uri):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(uri))
	return parsed as Dictionary if parsed is Dictionary else {}

func _run() -> void:
	var before := _read(BEFORE_URI)
	var after := _read(AFTER_URI)
	_check(not before.is_empty(), "normal runtime: v2 baseline observation exists")
	_check(not after.is_empty(), "normal runtime: v12 observation exists")
	if before.is_empty() or after.is_empty():
		print("== Result: %d failures ==" % fails)
		quit(1)
		return
	for row in [before, after]:
		_check(str(row.get("display_server", "")) == "X11" and str(row.get("mode", "")) == "normal_roles" and not bool(row.get("single_worker_demo", true)), "normal runtime: evidence is X11 ordinary harvest/carry/escort")
		_check(str(row.get("runtime_driver", "")) == "inherited_adapter_process" and int(row.get("manual_adapter_ticks", -1)) == 0, "normal runtime: adapter runs through inherited Godot process, not manual ticks")
		_check(int(row.get("observation_fps", 0)) == 10 and int(row.get("video_capture_fps", 0)) == 10, "normal runtime: 10fps is labeled as observation/video rate")
		var samples: Array = row.get("samples", [])
		var timing: Dictionary = row.get("timing", {})
		_check(samples.size() >= 50 and float(timing.get("session_elapsed_span", 0.0)) >= 6.0 and float(timing.get("wall_elapsed_seconds", 0.0)) >= 6.0, "normal runtime: trace has real wall/session duration")
		_check(int(timing.get("engine_process_frame_span", 0)) > samples.size(), "normal runtime: Godot process frames exceed 10fps observation samples")
		_check(_screenshots_are_1280x720(row), "normal runtime: post-draw evidence is unmodified 1280x720")
	_check(_same_entry(before, after), "normal runtime: before/after use the same seed, roles, resources, gate, and dock")
	_check(_baseline_provenance_is_bound_to_v11(before), "normal runtime: static baseline is bound to the verified v11 archive and crew-view hash")
	_check(_v11_archive_and_entry_are_verified(before), "normal runtime: baseline provenance hashes the actual v11 ZIP and its extracted crew-view entry")
	_check(_capture_source_has_no_manual_tick_after_runtime_marker(), "normal runtime: capture source has no manual field/session tick after inherited runtime begins")
	_check(str(before.get("presentation_revision", "")) == "v2_static" and str(after.get("presentation_revision", "")) == "v12_harvest_v3", "normal runtime: comparison distinguishes static v2 from bounded v3 harvest motion")
	var before_frames := _frame_sets(before)
	var after_frames := _frame_sets(after)
	_check(before_frames.walk.size() <= 1 and before_frames.harvest.size() <= 1, "normal runtime: baseline records static normal v2 walk/harvest poses")
	_check(after_frames.walk.size() >= 2 and after_frames.harvest.size() >= 2, "normal runtime: v12 harvest role records multiple real walk/harvest frames")
	var after_timing: Dictionary = after.get("timing", {})
	_check(float(after_timing.get("max_foot_error", INF)) <= 0.01 and int(after_timing.get("scale_variant_count", 0)) == 1, "normal runtime: v12 feet stay on map points and scale stays fixed")
	_check(_cargo_and_depot_agree(after), "normal runtime: cargo visibility follows session and depot increase clears cargo without breaking conservation")
	_check(_after_motion_scope_is_bounded(after), "normal runtime: v3 appears only for empty-handed harvest walk/harvest; observed carry remains v2")
	_check(_video_probe_is_complete(before) and _video_probe_is_complete(after), "normal runtime: both direct videos decode as 1280x720 H.264, 10fps, 120-frame, 12-second captures")
	_check(_decoded_videos_are_continuous(before) and _decoded_videos_are_continuous(after), "normal runtime: decoded videos contain 120 frames without a three-frame frozen run")
	print("== Result: %s ==" % ("PASS" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)

func _same_entry(before: Dictionary, after: Dictionary) -> bool:
	return before.get("entry", {}) == after.get("entry", {})

func _baseline_provenance_is_bound_to_v11(before: Dictionary) -> bool:
	var provenance: Dictionary = before.get("renderer_provenance", {})
	var archive: Dictionary = provenance.get("archive", {})
	return str(provenance.get("kind", "")) == "isolated-current-project-copy-with-v11-crew-view-overlay" and str(archive.get("sha256", "")) == V11_ARCHIVE_SHA256 and str(archive.get("entry", "")) == "project/scenes/canyon/components/canyon_crew_views.gd" and str(archive.get("entry_sha256", "")) == V11_CREW_VIEWS_SHA256

func _v11_archive_and_entry_are_verified(before: Dictionary) -> bool:
	# Do not trust the evidence JSON to attest itself. Verify the locally
	# preserved v11 ZIP bytes, then hash the exact entry used by the isolated
	# baseline capture without writing a temporary copy of that entry.
	if not _baseline_provenance_is_bound_to_v11(before):
		return false
	var provenance: Dictionary = before.get("renderer_provenance", {})
	var archive: Dictionary = provenance.get("archive", {})
	var archive_path := _v11_archive_path(str(archive.get("filename", "")))
	if archive_path.is_empty() or not FileAccess.file_exists(archive_path):
		return false
	var archive_hash := _sha256_bytes(FileAccess.get_file_as_bytes(archive_path))
	if archive_hash != V11_ARCHIVE_SHA256:
		return false
	var extracted: Array = []
	var args := PackedStringArray(["-p", archive_path, str(archive.get("entry", ""))])
	var unzip_exit := OS.execute("unzip", args, extracted, true)
	if unzip_exit != 0:
		return false
	var source := ""
	for chunk in extracted:
		source += str(chunk)
	var entry_hash := _sha256_bytes(source.to_utf8_buffer())
	return entry_hash == V11_CREW_VIEWS_SHA256

func _v11_archive_path(filename: String) -> String:
	var configured := OS.get_environment("V11_NORMAL_HAUL_FRAME_ARCHIVE").strip_edges()
	if not configured.is_empty():
		return configured
	# The cloud handoff stores the archive above the restored project. Walk only
	# local parents (never a URL or alternate download path); a consumer with a
	# different local layout passes the explicit environment variable above.
	var cursor := ProjectSettings.globalize_path("res://").simplify_path()
	for unused in 6:
		var candidate := cursor.path_join(filename)
		if FileAccess.file_exists(candidate):
			return candidate
		var parent := cursor.get_base_dir()
		if parent == cursor:
			break
		cursor = parent
	return ""

func _sha256_bytes(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash.update(bytes)
	return hash.finish().hex_encode()

func _capture_source_has_no_manual_tick_after_runtime_marker() -> bool:
	if not FileAccess.file_exists(CAPTURE_SOURCE_URI):
		return false
	var source := FileAccess.get_file_as_string(CAPTURE_SOURCE_URI)
	var marker := "V12_RUNTIME_RECORDING_NO_MANUAL_TICK_BEGIN"
	var marker_index := source.find(marker)
	if marker_index < 0:
		return false
	var runtime_source := source.substr(marker_index + marker.length())
	return runtime_source.find("field._process(") < 0 and runtime_source.find(".session.tick(") < 0 and runtime_source.find("adapter._process(") < 0 and runtime_source.find("field.session.call(\"tick\"") < 0 and runtime_source.find("field.session.call('tick'") < 0

func _frame_sets(row: Dictionary) -> Dictionary:
	var result := {"walk": {}, "harvest": {}}
	for sample in row.get("samples", []):
		var presentation: Dictionary = sample.get("presentation", {})
		var kind := str(presentation.get("visual_kind", ""))
		if result.has(kind):
			result[kind][str(presentation.get("frame_name", ""))] = true
	return result

func _cargo_and_depot_agree(row: Dictionary) -> bool:
	var had_cargo := false
	var cleared_after_depot := false
	var last_depot := -1
	for sample in row.get("samples", []):
		var actor: Dictionary = sample.get("actor", {})
		var presentation: Dictionary = sample.get("presentation", {})
		var summary: Dictionary = sample.get("summary", {})
		var carried := int(actor.get("carry_n", 0)) > 0
		if bool(presentation.get("cargo_visible", false)) != carried or not bool(summary.get("conservation_ok", false)):
			return false
		var depot := int(summary.get("depot", 0))
		if last_depot >= 0 and depot > last_depot and not carried:
			cleared_after_depot = true
		had_cargo = had_cargo or carried
		last_depot = depot
	return had_cargo and cleared_after_depot

func _after_motion_scope_is_bounded(row: Dictionary) -> bool:
	var saw_v3 := false
	var saw_v2_carry := false
	for sample in row.get("samples", []):
		var actor: Dictionary = sample.get("actor", {})
		var presentation: Dictionary = sample.get("presentation", {})
		var asset := str(presentation.get("motion_asset", ""))
		var kind := str(presentation.get("visual_kind", ""))
		var carrying := int(actor.get("carry_n", 0)) > 0
		if asset == "v3":
			if carrying or kind not in ["walk", "harvest"]:
				return false
			saw_v3 = true
		if kind == "carry":
			if asset != "v2":
				return false
			saw_v2_carry = true
	return saw_v3 and saw_v2_carry

func _video_probe_is_complete(row: Dictionary) -> bool:
	var uri := str(row.get("video", ""))
	if uri.is_empty() or not FileAccess.file_exists(uri):
		return false
	var output: Array = []
	var args := PackedStringArray(["-v", "error", "-count_frames", "-show_entries", "stream=codec_type,codec_name,width,height,avg_frame_rate,nb_read_frames:format=duration,size", "-of", "json", ProjectSettings.globalize_path(uri)])
	if OS.execute("ffprobe", args, output, true) != 0:
		return false
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return false
	var streams: Array = parsed.get("streams", [])
	var format: Dictionary = parsed.get("format", {})
	if streams.is_empty() or not streams[0] is Dictionary:
		return false
	var stream: Dictionary = streams[0]
	return str(stream.get("codec_type", "")) == "video" and str(stream.get("codec_name", "")) == "h264" and int(stream.get("width", 0)) == 1280 and int(stream.get("height", 0)) == 720 and str(stream.get("avg_frame_rate", "")) == "10/1" and int(stream.get("nb_read_frames", 0)) == VIDEO_FRAME_COUNT and absf(float(format.get("duration", 0.0)) - VIDEO_DURATION_SECONDS) <= 0.05 and int(format.get("size", 0)) > 1024

func _decoded_videos_are_continuous(row: Dictionary) -> bool:
	var uri := str(row.get("video", ""))
	if uri.is_empty() or not FileAccess.file_exists(uri):
		return false
	var output: Array = []
	var args := PackedStringArray(["-hide_banner", "-loglevel", "error", "-i", ProjectSettings.globalize_path(uri), "-map", "0:v:0", "-an", "-f", "framemd5", "-"])
	if OS.execute("ffmpeg", args, output, true) != 0:
		return false
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	var digests: Array[String] = []
	var row_pattern := RegEx.new()
	row_pattern.compile("^\\s*\\d+,\\s*-?\\d+,\\s*-?\\d+,\\s*\\d+,\\s*\\d+,\\s*([0-9a-fA-F]{32})\\s*$")
	for line in raw.split("\n", false):
		var match := row_pattern.search(line)
		if match != null:
			digests.append(match.get_string(1).to_lower())
	if digests.size() != VIDEO_FRAME_COUNT:
		return false
	var run_length := 1
	for index in range(1, digests.size()):
		if digests[index] == digests[index - 1]:
			run_length += 1
			if run_length >= 3:
				return false
		else:
			run_length = 1
	return true

func _screenshots_are_1280x720(row: Dictionary) -> bool:
	var screenshots: Dictionary = row.get("screenshots", {})
	for key in ["walk", "harvest", "carry", "depot"]:
		var uri := str(screenshots.get(key, ""))
		if uri.is_empty() or not FileAccess.file_exists(uri):
			return false
		var image := Image.load_from_file(uri)
		if image == null or image.get_width() != 1280 or image.get_height() != 720:
			return false
	return true
