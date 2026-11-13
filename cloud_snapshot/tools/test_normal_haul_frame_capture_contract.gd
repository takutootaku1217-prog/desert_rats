extends SceneTree
## Capture evidence contract for the normal-role haul-frame progression.
## This guards against accidentally reusing the opt-in single-worker recorder
## as evidence for the normal production loop.

const CAPTURE_SCRIPT := "res://tools/capture_normal_haul_frame_progression.gd"

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	var source := ""
	if FileAccess.file_exists(CAPTURE_SCRIPT):
		source = FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	_check(not source.is_empty(), "通常分業の背負いフレーム実Viewport capture scriptが存在する")
	_check(source.contains("DisplayServer.get_name() != \"X11\"") and source.contains("not session.is_single_worker_demo()"), "captureはX11以外と単独追跡modeを実画面証跡から除外する")
	_check(source.contains("HUD_URI") and source.contains("LOADED_URI") and source.contains("DEPOT_URI"), "captureは通常HUD・積載・収納増加の別々の実画面を保存する")
	_check(source.contains("RenderingServer.frame_post_draw") and source.contains("root.get_texture().get_image()"), "captureは同じ実描画frameをpost-drawで無加工PNGへ保存する")
	_check(source.contains("prepared_checkpoint") and source.contains("selection") and source.contains("normal_user_save_touched"), "capture結果は進行前提・実測選択・個人save非変更を記録する")
	_check(not source.contains("\"single_worker_demo\": true"), "captureは通常分業を単独追跡へ置換しない")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
