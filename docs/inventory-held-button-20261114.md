# 在庫UIの押下中の更新で押下が消える不具合（検証記録・引継ぎ）

- 基準: `c3635be29e5aa14d6ceb138e16968e73f7b54f31`。同じ作業枝 `claude/safe-gameplay-fixes-20261114` への追加commit。ゲーム入口は `cloud_snapshot/project.godot`。価格・ゲーム内容の変更なし。

## 不具合と修正
- 症状: 在庫UIは0.25秒ごとの `_refresh` で、束・在庫が変わると詳細を作り直す（`UIKit.clear`＝ノードを外して解放）。数量ボタンや［運搬］［廃棄…］を押している最中に在庫が変わると、押したボタンが消え、離したときのクリックが無かったことになった。
- 修正（`cloud_snapshot/ui/inventory_ui.gd`）: 既存の制作画面（CraftUI）と同じ方式。押下中の操作ボタンがあれば、周期の更新と非強制の更新を保留する（`_has_held_button`。トグルは対象外）。保留中は更新の時刻を戻さないので、離した次のフレームで更新が追いつく。強制更新（ボタン操作そのものの結果表示）は保留しない。

## 押下中に選択束が消える・減る場合の安全性
- 更新を保留するので、押下中は選択の実体（`ItemStack`）は古いまま残る。離したときの処理は、現在の在庫を毎回確認する既存の仕組みで守られている。
  - 運搬: `request_transfer` は `AutoCraftGuard.available`（現在の倉庫在庫から運搬予約・作業中の取り出しを引いた値）で頼める個数を決める。古い束の個数では決めない。
  - 廃棄: `warehouse_discard_snapshot` が現在の廃棄可能数で検査し、足りなければ空を返して確認画面を開かない。確定時も `discard_warehouse` が同じ検査を再度行う。
  - 数量ボタン: 古い選択の数量ピッカーの値を変えるだけで在庫に触れない。更新が追いついた後、選択が別の品目へ代わると数量は 1 に戻る（前回の修正）ので、別の品目へ転用されない。
- この安全性を、実テストで確認した（下記の stale 系）。

## 検証（Godot 4.7.2 公式ビルド、Linux・ヘッドレス）
- 版 `4.7.2.stable.official.ed1daf0bf`（実行ファイル SHA256 `8d106cbe…`）。別コピーのプロジェクト、専用の HOME / FLUID_TEST_HOME / APPDATA / LOCALAPPDATA / XDG_DATA_HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME。既存セーブ・既存clone・旧作業フォルダには触れていない。
- **入力方式: 実OSの入力ではなく、ビューポートへ送るポインタイベント（`push_input`）**。OS入力、実マウス、スマホのタッチ、Windowsは未検証。
- 新規 `tools/test_inventory_held_button.gd`（37チェック）: **RED（修正前）は 9件失敗**・exit 1、**GREEN（修正後）は 37/37**・exit 0。RED の内訳は、押下中に詳細が作り直される／離した数量ボタンが反応しない（数量・コールバック1回・表示）／外側で離したときの保留／［運搬］が1回も出ない／押下中に選択束が消えるケースでの作り直し／減ったケースで生の値が古いまま。
- 確認内容: 内側で離すとちょうど1回／外側で離すと取消／離した後に更新が追いつく／押下中に束が消えても運搬・廃棄・数量が別の品目へ転用されない／押下中に数量が減ると、運搬は現在の在庫（1個）までしか頼まず、廃棄は古い数量を拒否する／押下・取消・更新で在庫、予約、転送キュー、セーブ内容が変わらない。
- 前回のテストの強化: `test_inventory_other_tab_live.gd` に、数量ピッカーの実値と表示文字（3）の保持を追加（21チェック、すべて成功）。
- 関連: `inventory_selection` 23/23、`inventory_search` 23/23、`warehouse_rows` 8/8、`ui_modal_feedback`、`first_region_mine_arrival_gate`、`purpose_entry_flow`、`craft_material_routes` が成功（exit 0、SCRIPT ERROR 0、FAIL 行 0）。
- **全回帰**（`run_prototype_checks.py`、新テスト登録済み）: import＋106件＝**107件すべて exit 0**、後片付け成功、`ok` 976行（前回の918＋新規58）、`SCRIPT ERROR` 0。`FAIL` を含む行は1つで、`field_status_ui_v3_1` の座標出力（診断用の print。同テストは failures=0。前回までと同じ）。

## 変更ファイル
- `cloud_snapshot/ui/inventory_ui.gd`（修正）
- `cloud_snapshot/tools/test_inventory_held_button.gd`（新規）
- `cloud_snapshot/tools/test_inventory_other_tab_live.gd`（実値の検査を追加）
- `cloud_snapshot/tools/run_prototype_checks.py`（1行登録）
- `docs/inventory-held-button-20261114.md`（本記録）
- 旧 `PUBLIC_SOURCE_MANIFEST_v2.json` と旧証拠は変更していない。

## 未確認
- 実画面（GUI）の操作、実OS入力、スマホ実機のタッチ、Windows、音声。長時間・全seedの保証ではない。
