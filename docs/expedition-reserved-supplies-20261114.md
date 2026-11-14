# 遠征が他の仲間の予約済み物資を持ち出す問題（検証記録・checkpoint）

- 基準: `ac7fa9604a6b1cd356af671eb6f91c0c74afc76a`。作業枝 `claude/safe-gameplay-fixes-20261114` への追加commit。ゲーム入口は `cloud_snapshot/project.godot`。採用根拠: 小津さんの第4工程の指示。遺跡数値・価格・新機能の変更なし。

## 不具合（実行で再現）
- `Expedition.block_reason` は食料・修理板を**物理的な個数**だけで判定し、`start` が倉庫から取り出していた。一方、倉庫の廃棄は食事・修理・運搬の予約を保護している。
- 再現（実AIで予約を作成。注入ではない）: 駆動部を損傷させ、修理担当が最後の修理板を取りに向かう（`REPAIR_TAKE`）→ 遺跡を提示 → 別の隊員が修理板を持って出発できてしまう（板が消費され、元の修理担当が板を取れず失敗する）。食料も同様（空腹の仲間が `EAT_TAKE`）。作業場への運搬の依頼（`to_workshop`）が取り置いた食料も持ち出せた。

## 修正
- 既存の `AutoCraftGuard.available`（実予約を引いた利用可能数）を再利用。`claimant` に**隊員の配列**を渡せるようにした（`cloud_snapshot/scripts/auto_craft_guard.gd`。単独の指定は従来どおり）。出発する隊員自身の予約は出発（`stop_work`）で解放されるので数えない。
- `cloud_snapshot/scripts/expedition.gd` の `block_reason` が、食料（人数分）と修理板（任意）を利用可能数で判定する。持ち出せないときは「他の仲間・運搬の予約分は持ち出せない」旨の理由で出発不可にする。`start` は変更なし（判定を通った分だけ取り出す）。

## 検証（Godot 4.7.2 公式ビルド、Linux・ヘッドレス）
- 版 `4.7.2.stable.official.ed1daf0bf`（実行ファイル SHA256 `8d106cbe…`）。別コピーのプロジェクト、専用の HOME / FLUID_TEST_HOME / APPDATA / LOCALAPPDATA / XDG_DATA_HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME。既存セーブ・既存clone・旧作業フォルダには触れていない。
- 新規 `tools/test_expedition_reserved_supplies.gd`（22チェック）: **RED（修正前）は 13件失敗**（予約された最後の板・食料でも出発可、運搬予約の食料も持ち出し可。一部は出発してしまった後の連鎖失敗）、**GREEN（修正後）は 22/22**・exit 0。初回の1回は、テスト側の型推論エラーで起動せず、直して再実行。
- 確認内容: 他担当の予約しかなければ、明確な理由で出発不可・在庫、予約、隊員、遠征の状態、セーブ内容が不変／余剰が十分なら必要な個数だけ消費（板1・食料1）し、他の修理担当の予約と状態は維持／予約が解除されれば出発可／隊員自身の予約は出発で解放され二重に消費されない（板の個数は負にならない）／運搬の依頼の取消後は出発可。
- 関連（各 exit 0）: `inventory_split_vanish` 48/48、`inventory_held_button` 37/37、`inventory_other_tab_live` 21/21、`inventory_selection` 23/23、`inventory_search` 23/23、`depot_expedition` 11/11。
- **全回帰**（`run_prototype_checks.py`、新テスト登録済み。実PID 4175、約12分）: import＋108件＝**109件すべて exit 0**、後片付け成功、`ok` 1046行、`SCRIPT ERROR` 0。`FAIL` を含む行は1つで、`field_status_ui_v3_1` の座標出力（診断用の print。同テストは failures=0。前回までと同じ）。この全回帰は、今回の修正後のコードで実行した。
- **入力方式**: 本テストは入力を使わず、実AIの状態と遠征APIを直接呼ぶ。実OS入力、スマホ実機、Windows、実画面（GUI）の遠征編成は未検証。

## 未完了・次の担当
- 取消・保存再開の個別テストは、新テストでは「出発判定の不変（セーブ内容の一致）」までで、遠征中の保存・再開の追加確認はしていない（既存の回帰は全回帰で成功）。
- 次担当: 小津さん（独立レビュー）。この作業はここで停止。追加課金なし・自動交代なし。

## 変更ファイル
- `cloud_snapshot/scripts/auto_craft_guard.gd`、`cloud_snapshot/scripts/expedition.gd`（修正）
- `cloud_snapshot/tools/test_expedition_reserved_supplies.gd`（新規）、`cloud_snapshot/tools/run_prototype_checks.py`（1行登録）
- `docs/expedition-reserved-supplies-20261114.md`（本記録）
- 旧 `PUBLIC_SOURCE_MANIFEST_v2.json` と旧証拠は変更していない。
