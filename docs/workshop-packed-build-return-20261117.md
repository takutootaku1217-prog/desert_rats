# 作業場に置いた完成設備で設置注文が止まる問題（検証記録・checkpoint）

- 基準: `6f5ae926ca3a128ad97e7019a497127e2be7d737`（`codex/mechanical-explosion-20261115`）。作業枝 `claude/core-loop-20261117`（ローカルのみ。push・mergeなし）。入口は `cloud_snapshot/project.godot`。
- 出発点の根拠: 上の基準は `main`・`claude/*`・`codex/quarry-return-ready-20261115`・`cloud/migration`・`cloud/handoff-safe`・`cloud/manual-collaboration` をすべて含む（これらに基準に無いコミットは0件）。含まないのは `gpt/*` 5本（`cloud_snapshot/` 移行前の旧ルート版向け試作）、`cloud/handoff-ci-probe`（文書とCI設定のみ3件）、`cloud/handoff-state`（引継ぎ状態の記録専用）で、取り込んでいない。
- **今回のNotionは未確認**（このセッションにNotionの接続なし）。数値・価格・保存形式・新機能の変更なし。

## 不具合（実行で再現）
- 設置（`Main._next_build_recipe`）は**倉庫**にある製作物だけを使う。一方 `packed_in_transit` は**作業場**（`processor.stock`）の製作物も「準備中」と数えるため、再製作もしない。作業場から倉庫へ戻す接続がなく、設置注文が進まなくなる。
- 再現（通常の操作と同じAPI）: 作業台を建設 → 完成した収納ボックスを所持品の運搬で作業場へ移す（`request_transfer(...,"to_workshop")`、仲間が実際に運ぶ）→ 収納ボックスの設置を依頼（`request_build("cargo_rack")`）。ゲーム内240秒待っても `queue=["cargo_rack"] storage=0 workshop=1` のまま。プレイヤーが手動で倉庫へ戻せば回復するが、画面上は理由なく止まる。

## 修正
- `cloud_snapshot/scripts/main.gd` に `_reconcile_build_stock()` を追加し、既存の `_feed_crafts()`（`CraftDB.FEED_SECONDS` ごと）から呼ぶ。設置待ちの製作物について、倉庫・倉庫へ戻す依頼・運搬中・製作中の分で足りないときだけ、既存の `request_transfer(item, n, "to_storage")` で作業場の未予約分を倉庫へ戻す。
- 瞬間移動・再製作・数量の変更はしない。設置注文がなければ、作業場に置いた製作物は動かさない。

## 検証（Godot 4.7.2.stable.official.ed1daf0bf、Linux）
- 新規 `tools/test_workshop_packed_build_return.gd`（13チェック。実Main・実AI・運搬・加工・建設の待ち。fixtureは初期在庫の木材3と完成した収納ボックス1個のみ）。
  - **RED（修正前）: 4件失敗**（設置されない／運ばれない／箱が消費されない／注文が残る）。
  - **GREEN（修正後）: 13/13**、exit 0、`SCRIPT ERROR` 0。3回連続で成功。
  - 無効な実行1回: 最初のREDは、テスト側で設備IDを誤り（`storage_box`。正しくは `cargo_rack`）、無関係なエラーで失敗した。ログは `RED-invalid-wrong-facility-id.log` として残し、証拠に数えていない。
- Codex（OpenAI公式プラグイン経由、読み取り専用）の独立レビュー: ブロッキングな欠陥の指摘なし。「運搬の証明が返送の予約だけでも成立する」との指摘を受け、仲間が `XFER_MOVE`・`to_storage` で箱を実際に持っていることを要求する検査に直した（上の13/13はこの修正後）。
- 実描画（Xvfb、OpenGL/Mesa llvmpipe）: 修正後のコードで通常の入口から起動 → 新規開始 → ゲーム内240秒進行。`SCRIPT ERROR` 0、仲間の採取と倉庫への収納が進むことを画像で確認（240秒時点の積載: 修正後の実行で108、修正前の実行で96。開始時は24）。別コピーのプロジェクトと専用HOMEを使用。
- 全回帰（`run_prototype_checks.py`、新テスト登録済み、import＋121件）の結果は末尾の「全回帰」を参照。

## 未検証
- 実OSの入力（マウス・タッチ）、Windows、実機。GUIの所持品画面・建設画面からの同じ操作（今回はAPIの直接呼び出し）。
- 複数の設置注文と複数の箱、寝床（`BED_PACK`）での同じ経路、運搬の途中での保存・再開（運搬の依頼の保存形式は変更していない）。
- 通常の新規開始から地域突破までの全体一周。

## 仕様の判断が必要で、変更していないもの
1. 遺跡の調査隊に持たせた応急修理板が、未使用でも倉庫へ戻らない（`scripts/expedition.gd` の `_finish`）。Codexの調査でも「バグ寄りだが、採用仕様に返却の規則が明記されていない」。
2. 倉庫の廃棄が、街の売却では保護される未着手の製作注文用の素材を保護しない（`Main.warehouse_discard_available`）。
3. 通常の周回で襲撃が発生しない（`docs/checkpoint-20261114-next.md` の調査）。

## 変更ファイル
- `cloud_snapshot/scripts/main.gd`（修正）
- `cloud_snapshot/tools/test_workshop_packed_build_return.gd`（新規）、`cloud_snapshot/tools/run_prototype_checks.py`（1行登録）
- `docs/workshop-packed-build-return-20261117.md`（本記録）
- Godotのimportが生成した未追跡の `.gd.uid` は、新テストの分以外コミットしていない。

## 全回帰（修正後のコードで実行）
- `run_prototype_checks.py`（新テスト登録済み、約18分）: import＋121件＝**122件すべて exit 0**、後片付け成功、`ok` 4119行、`SCRIPT ERROR` 0。`FAIL` を含む行は3つで、いずれも失敗ではない（`field_status_ui_v3_1` の座標の診断出力、`ui_modal_feedback` と `armor_install_cycle` の「FAILURES 0」の集計行）。
- この全回帰で走った新テストは、運搬の検査を厳しくする前の版（13/13）。厳しくした後の版は単独で3回実行し、すべて13/13。
- 修正前の基準実行は、同じ作業コピーで修正を始めたため最初の40件（すべて exit 0）で打ち切った。修正前の全件の結果としては使っていない。
- 全回帰が作業コピーに書いた生成物（`prototypes/recovery_map_lab/results/route_connection_runtime/` の1件の変更と1件の新規）はコミットせず、証拠領域へ退避して元に戻した。
