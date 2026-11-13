extends SceneTree
## The capture verifier must accept an actual 1280x720 direct-X11 recording
## when X11 scheduling yields a narrowly sub-nominal direct capture rate.

const CaptureScript = preload("res://tools/capture_canyon_parking_vertical_slice.gd")

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	var capture = CaptureScript.new()
	var probe: Dictionary = capture._probe_video()
	capture.free()
	_check(bool(probe.get("ok", false)), "64秒の実X11動画は約9.9〜10fps・1280x720として受理")
	_check(int(probe.get("decoded_frame_count", 0)) >= 633, "動画probeは直接デコードした十分な連続フレーム数を返す")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
