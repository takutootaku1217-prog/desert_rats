# 所持品選択の安定化（検証記録・引継ぎ）

- 基準: `cloud/manual-collaboration-20261114` @ `c297a0ce175c97ddd385bd09e5ce4a8ea297edf4`。新規枝 `claude/inventory-selection-stability-20261114`。ゲーム入口は `cloud_snapshot/project.godot`（旧rootのprojectは未変更）。
- 範囲: 既存UIの安全性修正のみ。価格・商品・仕様の追加なし。

## 不具合と修正
- 原因: `InventoryUI._refresh` が `m.sync` 後に「番号」だけを保持していた。前にある束が消えると、同じ番号が別の束を指した（石を選択→木材を使い切る→鉄鉱石になる）。
- 修正（`cloud_snapshot/ui/inventory_ui.gd`、+21行）: 同期前に選択中の束の実体を記憶し、同期後に同じ実体を探して番号を更新する（実体の同一性で判定。分割された同種束でも取り違えない）。
- 選択した束自体が消えた場合の代替: 同じ品目の残り束の先頭、なければ元の位置の隣（末尾なら直前）、空なら選択なし。代替になったときは数量選択を1へ戻し、未確定の廃棄確認を取り消す（数量・廃棄確認を別の束へ転用しない）。

## 検証（Godot 4.7.2 公式ビルド、Linux・ヘッドレス）
- 版: `4.7.2.stable.official.ed1daf0bf`。実行ファイル SHA256 `8d106cbe…f71e`（取得元zipのSHA-512先頭は公開値と照合済み）。
- 隔離: 別コピーのプロジェクト、専用の HOME / FLUID_TEST_HOME / APPDATA / LOCALAPPDATA / XDG_DATA_HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME。既存セーブ・既存clone・旧作業フォルダには触れていない。
- RED（修正前）: 新規 `tools/test_inventory_selection.gd`（23チェック）は **9件失敗**・exit 1。再現した症状は、前の束が消えると選択が別の束（鉄鉱石）に移る／分割された同種束で別の束を選ぶ／代替時に数量・廃棄確認が残る／検索中・加工所タブでも同じ。
- GREEN（修正後）: 同テスト **23/23**・failures 0・exit 0。既存 `test_inventory_search.gd` **23/23**・exit 0。
- 回帰: `tools/run_prototype_checks.py`（新テスト登録済み）を全件実行。import＋104件＝**105件すべて exit 0**、後片付け成功、`ok` 918行（直前の基準895＋新規23）、`SCRIPT ERROR` 0。`FAIL` を含む行は1つで、`field_status_ui_v3_1` の座標出力（診断用の print。同テストは failures=0。以前の記録と同じ）。
- 検証内容: 前の束の消費／同種束の分割と挿入／選択束の消失と代替／空リスト／廃棄確認の取消と遅延確定／検索中／加工所タブ／在庫・予約・転送キュー・セーブ内容が選択処理で不変。
- 注意: この枝の `cloud_snapshot` には、分割・廃棄・保存の専用テストは含まれていない（別系統のツリーにあったもの）。関連の確認は新テストと、同梱の `warehouse_rows` / `ui_modal_feedback` / 検索テスト、全回帰で行った。

## 変更ファイル
- `cloud_snapshot/ui/inventory_ui.gd`（修正）
- `cloud_snapshot/tools/test_inventory_selection.gd`（新規）
- `cloud_snapshot/tools/run_prototype_checks.py`（テスト1行を登録）
- `docs/inventory-selection-stability-20261114.md`（本記録）
- `PUBLIC_SOURCE_MANIFEST_v2.json` と旧証拠は変更していない（意図した差分は上記のみ）。

## 未確認
- 実画面（GUI）の操作、Windows、スマホ実機、OS入力、音声。Notion参照は今回未確認。
- 全回帰は修正版の1回の結果。長時間・全seedの保証ではない。
