# 停車中の自動採取（木材・石）は積載の25%を空けておく（検証記録・checkpoint）

- 基準: `3e6deedf31c12289f974685a0a41aaa0f88d5a79`（`claude/core-loop-20261117`、`docs/ore-first-quarry-20261118.md` の続き）。入口は `cloud_snapshot/project.godot`。
- **今回のNotionは未確認**（このセッションにNotionの接続なし）。
- 実装: OpenAI Codex（公式Claude Codeプラグイン経由、同じ作業コピー・書き込み可）。仕様・レビュー・全回帰・実描画・記録: Claude。

## オーナーの指示（2026-11-18）
- Claudeの提案「二周目に積載が木材と石で埋まりやすい問題（例: 回収の優先の初期値）」に「いいよ、Codexにやってもらって」。方向はClaudeに一任。

## 背景
停車中、仲間は木材・石を積載が満杯になるまで自動で採り続けていた。通しテストでは二周目の出発前に積載の空きが **2 / 360** になり、鉄鉱石や獲物を入れる余地がなかった。「回収の優先」の★は採る順番にしか効かず、★0以外は満杯まで採るため、★の初期値を下げても解決しない（Claudeがコードで確認）。

## 仕様（今回の判断）
- 新しい調整用の定数 `CargoDB.AUTO_GATHER_RESERVE_RATIO = 0.25`（暫定値）。
- **自動の**木材・石の採取は、積載の空きが最大積載の25%を下回るところまでは採らない（採取先を選ぶときと、袋の大きさを決めるときの両方）。空きの計算は既存と同じ（今の重さ・加工の予約・ほかの仲間の採取予約）なので、2人が同時に線を越えることはない。
- **例外**（25%を使ってよい）: 建設の材料の不足分、製作注文の材料の不足分、プレイヤーの回収依頼（目標まで）、プレイヤーがその素材を個別に頼んだ仲間。
- 鉄鉱石・狩猟・獲物・落とし物・遠征の戦利品・運搬・Cの採掘地・Cからの持ち帰りは制限しない。
- 止まったときは、ほかの仕事をするか待機する（新しい待ち状態は作らない）。すでに予約した袋・運んでいる袋は減らさない。
- 見える化: 方針画面の「回収の優先」に「木材・石の自動採取は空き25%を確保（建設・注文・依頼の不足分は例外）」の1行。採取地点の案内にも「積載の空きを残すため自動採取を止めています」を出す（案内が切れないよう描画幅を調整）。
- 積載がほぼ満杯のときの手引き（10%未満）はそのまま。保存形式は変更なし。

## テスト
- 新規 `tools/test_auto_gather_reserve.gd`（35チェック。実AI・実際の採取地点）: 自動採取は空き **90 / 360** で止まり満杯にならない／建設に足りない木材は25%を超えて集めて足りたら止まる／石の回収依頼は目標まで集める／石のピッケルで鉄鉱石は本来の上限まで掘る／予約済みの袋（木材3個）は一度だけ全量届き重量が12増える／保存して読み込んでも同じ動き／積載がほぼ満杯の手引き（10%未満で出る・実際の対処を示す・読んでも保存内容は同じ・空きができれば消える。撮影用に積載を直接埋めた準備で確認）。
- `tools/test_guided_first_lap.gd`（27チェック）: 二周目の出発前の空きは **2 / 360（変更前）→ 80 / 360（変更後、2回とも）**。積載がほぼ満杯の手引きは出ない。**Aの購買店での余剰の売却と、木材・石の★0は不要になったので外した**（その検査が減ったためチェック数が32→27）。鉄鉱石3個の搬入・精錬3回・収納ボックスの設置・再出発と到着は2回とも成功。

## 検証（Godot 4.7.2.stable.official.ed1daf0bf、Linux）
- Codexの個別実行（各実行で隔離ホーム）: 上の2本に加え、`ore_tool_guide`、`next_step_guide`、`first_loop_guide`、`canyon_field_tool_kit_v18`、`greenway_salvage`、`survival_loop_clarity`、`vehicle_hunt`、`vehicle_hunt_survival_cycle`、`survival_save_cycle`→`survival_save_restart`、`transfer_save_cycle`→`transfer_save_restart`、市場系2本、`normal_haul_frame_progression`、`recovery_frame_upgrade_cycle_v3`、`workshop_packed_build_return` がすべて FAIL 0・`SCRIPT ERROR` 0・exit 0。
- **リポジトリ直下の旧版 `tools/`（`cloud_snapshot/` ではない旧ルートのゲーム用）にある5本**（`cargo_accounting`・`cargo_reservations`・`consumption_loop`・`tool_progression`・`tool_flow`）は、全回帰（`cloud_snapshot/tools/run_prototype_checks.py`）の対象外。Codexが一時コピーで変更前後を比べた結果:
  - `cargo_accounting`（3件失敗・`SCRIPT ERROR` 3）と `consumption_loop`（1件失敗）は**変更前から同じ失敗**。
  - `cargo_reservations`（2件）と `tool_progression`（1件）は**今回の変更で失敗が増えた**。どちらも「自動採取で石を満杯近くまで採る」前提の検査で、検査対象の石を個別の依頼にすると元の検査はすべて通る。旧ルートのテスト本体は変更していない。
  - `tool_flow` は変更前後とも最後まで到達。
- Claudeのレビュー: 差分を確認。Cの採掘地の地点（`quarry_id` を持つ地点）は対象外、建設・注文の不足分だけ25%を超えて集める計算になっている。
- 実描画（Xvfb、OpenGL/Mesa llvmpipe、別コピーと専用HOME）: 方針画面の「回収の優先」に説明の1行が枠内で表示されることを画像で確認。新規開始してAで停車したまま約25分（ゲーム内）進めても空きは 268 / 360 までしか減らず（Aの資源は有限）、自然なプレイで25%の線に届く場面の実描画は撮れていない（線で止まる動きは上の2本のテストで確認）。
- 全回帰の結果は末尾の「全回帰」を参照。

## 残る課題
- 25% は暫定値（360の積載で90）。荷台を増やすと最大積載に比例して増える。
- 旧ルートの `tools/` の2本（上記）は、今回の仕様では検査の前提が古くなった。旧ルートのゲームをどう扱うかは未決定なので、テストは変更していない。
- 前回からの継続: 遺跡の調査隊の未使用の修理板が戻らない／倉庫の廃棄が注文用素材を保護しない／通常の周回で襲撃が起きない。
- 実OSの入力、Windows、実機は未検証。seed は1種。

## 変更ファイル
- 製品: `cloud_snapshot/data/cargo.gd`、`cloud_snapshot/scripts/main.gd`、`cloud_snapshot/scripts/character_ai.gd`、`cloud_snapshot/scripts/gather_point.gd`、`cloud_snapshot/ui/policy_ui.gd`
- テスト: `cloud_snapshot/tools/test_auto_gather_reserve.gd`（新規、＋`.uid`）、`cloud_snapshot/tools/test_guided_first_lap.gd`、`cloud_snapshot/tools/run_prototype_checks.py`（1行登録）
- 記録: `CLAUDE.md`（作業ログ1行、Codex）、`docs/auto-gather-reserve-20261118.md`（本記録）

## 全回帰（今回の変更後のコードで実行）
- `run_prototype_checks.py`（新テスト登録済み、約18分）: import＋124件＝**125件すべて exit 0**、後片付け成功、`SCRIPT ERROR` 0。`FAIL` を含む行は3つで、いずれも失敗ではない（`field_status_ui_v3_1` の座標の診断出力、`ui_modal_feedback` と `armor_install_cycle` の「FAILURES 0」の集計行）。
- 全回帰が作業コピーに書いた生成物（`prototypes/recovery_map_lab/results/route_connection_runtime/` の2件の変更と1件の新規）はコミットせず、証拠領域へ退避して元に戻した。
