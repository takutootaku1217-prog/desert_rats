class_name SaveGame
extends RefCounted
## 仮のセーブ・ロード（JSON）。個体・倉庫・進行速度を保存する。
## ヘッドレス実行（動作確認）ではプレイヤーのセーブを壊さないよう、既定では無効。

const VERSION := 1


## true にすると、セーブを読み書きしない（画面確認ツールなどが、遊んでいるセーブに影響されないように）
static var disabled := false


static func enabled() -> bool:
	return not disabled and DisplayServer.get_name() != "headless"


static func exists(path: String = Balance.SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## game の状態を path に書く。成功で true。
static func write(game, path: String = Balance.SAVE_PATH) -> bool:
	var crew: Array = []
	for w in game.workers:
		crew.append(w.to_dict())
	var data := {
		"version": VERSION,
		"crew": crew,
		"inventory": game.storage.inventory.counts,
		"scroll_speed": game.scroll_speed,
		"rooms": game.room_layout,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("セーブできません: %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data))
	return true


## 読み込む。ファイルがない・壊れているときは空の Dictionary。
static func read(path: String = Balance.SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("crew") or parsed["crew"].is_empty():
		push_warning("セーブデータを読めません: " + path)
		return {}
	return parsed


static func delete(path: String = Balance.SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
