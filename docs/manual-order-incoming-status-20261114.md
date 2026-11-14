# 手動製作注文の「搬入中」が製作画面で全0になる件（2026-11-14）

基準: `fa2fc94f2310dd955377ce56481943a8796c6d86`（`claude/safe-gameplay-fixes-20261114`、入口 `cloud_snapshot/project.godot`）

## 症状（再現済み）
倉庫の材料で頼んだ通常の手動注文（`Main.request_order`、製作画面の［制作］と同じ入口）を、実AIが運搬で引受けると、
注文は `production_orders` から `processor.incoming` へ移る。`Processor.manual_status` は incoming を数えていなかったため、
仲間が材料を取りに行く間（HAUL_TAKE）と運んでいる間（HAUL_MOVE）、製作画面の内訳が
「未投入 0 / 投入済・未着手 0 / 加工中 0」になり、注文が消えたように見えた。

## 修正（表示の集計だけ）
- `scripts/processor.gd` `manual_status`: `incoming` のうち `manual` かつ建設でない、同じレシピIDの件数を、別枠 `incoming` として数える。
- `ui/craft_ui.gd`: 内訳に「材料確保・搬入中 N回」を追加。
- 到着すると `orders` へ移るので、同じ1回は「搬入中」と「投入済・加工中」のどちらか一方にだけ出る。
- 自動補充（`manual` なし）、建設（`build` あり）、別品目は数えない。
- 製作・取消の処理、在庫、予約、セーブ形式は変更していない（`manual_status` は読み取りだけ）。

## テスト `tools/test_manual_order_incoming_status.gd`（ランナー登録済み）
- 修正前: 26件中5件失敗（搬入中の合計0、画面の文言なし、など）。修正後: 26件すべて成功。
- 範囲: 通常の main シーン、`request_order` で注文、引受け・搬入・加工は実AIの通常 tick（time_scale 6 で早送り）。
- fixture: 作業台を `base.add_facility` で追加、倉庫へ木材4個を追加（開始時は木材0・作業台なしのため）。対象は「木製採掘具」1回。
- 検査: 引受け後に incoming に1件（AIの reserve による）／搬入中1・他0／画面の BatchStatus に「搬入中 1回」／
  到着後は搬入中0で投入済または加工中が1／引受けから完成まで毎フレーム合計が常に1／
  読み取り前後で倉庫・作業場の在庫、予約、注文、`SaveGame.capture` が同一／HAUL_TAKE 中の取消は従来どおり（取消数1、木材が戻る）。
- 補正（レビュー指摘）: 完成は「制限時間内に完成品が出力トレイまたは倉庫に実際に出た」ことと「加工中0」を必須にした（時間切れでは合格しない）。
  建設の除外は `manual=true` かつ `build` ありの行で検査する（`not build` の条件を単独で確認）。補正後は28件すべて成功（1seed）。
- incoming への直接の追加は、自動補充と建設を「数えない」ことの検査にだけ使用（成功の根拠にしていない）。

## 関連回帰（Godot 4.7.2 公式、別コピー、HOME・XDG・FLUID_TEST_HOME などを隔離）
craft_material_routes / recovery_frame_upgrade_cycle_v3 / first_loop_guide / purpose_entry_flow /
normal_haul_frame_progression / survival_bed_build_flow / transfer_save_cycle・restart / survival_save_cycle・restart /
inventory_search / inventory_selection の12本、すべて exit 0・FAIL 0。

## 未検証・範囲外
- 全回帰は今回実行していない（上の12本と新テストだけ）。
- 実OS入力、GUI描画、Windows、実機は未検証。seed は1種（104729）。
- HAUL_MOVE（運搬中）の取消は従来どおり「運搬中は保持」で、今回は挙動を変えておらず、検査もしていない。
- 2枠加工（parallel_bench）がある状態、複数回注文（n>1）の搬入中は未検査。
- `manual_status` を読む他の箇所（`ui/first_loop_guide.gd`、`scripts/world_trip.gd`）は既存のキーだけを使うため変更なし。
  それらの案内が搬入中をどう扱うべきかは未確認（変更していない）。
