# 在庫詳細の「反対側の置き場の数量」のライブ更新（検証記録）

- 基準: `dad7c2dc23690392345066d123377a76b5b68ccb`。新規枝 `claude/safe-gameplay-fixes-20261114`。ゲーム入口は `cloud_snapshot/project.godot`。価格・ゲーム内容の変更なし。

## 不具合と修正
- 症状: 詳細の「倉庫 ×n / 作業場 ×n」は、詳細を作る時に1回だけ文字が決まっていた。`_signature` は表示中タブの束しか見ないため、倉庫タブで木材を選んでいる間に作業場の木材が消費・追加されても、作業場の数量が古いまま残った（逆向きも同じ）。同じ側の変更は束の数量が変わるので反映されていた。
- 修正（`cloud_snapshot/ui/inventory_ui.gd`）: 2つのラベルの参照を保持し、毎回の更新（`_update_dynamic`）で文言だけを更新する。詳細は作り直さない（シグネチャに足して再構築すると、開いている分割入力などが閉じるため採用しない）。選択、数量、検索、分割欄、廃棄確認、ラベルの強調色はそのまま。

## 検証（Godot 4.7.2 公式ビルド、Linux・ヘッドレス）
- 版 `4.7.2.stable.official.ed1daf0bf`（実行ファイル SHA256 `8d106cbe…`）。別コピーのプロジェクト、専用の HOME / FLUID_TEST_HOME / APPDATA / LOCALAPPDATA / XDG_DATA_HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME。既存セーブ・既存clone・旧作業フォルダには触れていない。
- RED（修正前）: 新規 `tools/test_inventory_other_tab_live.gd`（20チェック）は **8件失敗**・exit 1。倉庫タブ→作業場の消費/追加/ゼロ、作業場タブ→倉庫の消費/追加/ゼロ、分割・確認が開いている間の更新、検索中の更新が古いままだった。（初回の1回は、テスト側の型推論エラーで起動せず。直して再実行した）
- GREEN（修正後）: 同テスト **20/20**・failures 0・exit 0。
- 回帰（修正後、各 exit 0・SCRIPT ERROR 0・FAIL 行 0）: 前回の `inventory_selection` 23/23、`inventory_search` 23/23、`warehouse_rows` 8/8、`ui_modal_feedback`、`first_region_mine_arrival_gate`、`purpose_entry_flow`。
- 内容: 両タブで反対側の在庫変化が通常の更新で反映／詳細のノード（数量欄・分割欄）が同一／分割入力の値・数量・選択・廃棄確認のスナップショット維持／検索語の維持／更新で在庫・予約・転送キュー・セーブ内容が変わらない。
- **全回帰（run_prototype_checks.py の全件）は今回は実行していない**（指示により省略）。ランナーへの登録は1行の追加で、構文確認のみ。前回の全回帰（105件 exit 0）はこの修正の前の版。

## 変更ファイル
- `cloud_snapshot/ui/inventory_ui.gd`（修正）
- `cloud_snapshot/tools/test_inventory_other_tab_live.gd`（新規）
- `cloud_snapshot/tools/run_prototype_checks.py`（1行登録）
- `docs/inventory-other-tab-live-20261114.md`（本記録）
- 旧 `PUBLIC_SOURCE_MANIFEST_v2.json` と旧証拠は変更していない。

## 未確認
- 実画面（GUI）の操作、Windows、スマホ実機、OS入力、音声。全回帰の再実行。
