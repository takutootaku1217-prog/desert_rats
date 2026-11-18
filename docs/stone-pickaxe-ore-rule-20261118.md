# 鉱石はピッケルで（石のハンマー → 石のピッケル）と、Cへ行く前の案内（検証記録・checkpoint）

- 基準: `9c11a5852d9cfa0242d9a6206a2a41b16fbc1808`（`claude/core-loop-20261117`）。入口は `cloud_snapshot/project.godot`。
- **今回のNotionは未確認**（このセッションにNotionの接続なし）。
- 実装: OpenAI Codex（公式Claude Codeプラグイン経由、同じ作業コピー・書き込み可）。仕様・レビュー・全回帰・実描画・記録: Claude。

## オーナーの指示（2026-11-18）
- 「ハンマーじゃなくてツルハシにして。ARKみたいな感じ。鉱石はツルハシで。実装はCodexに」
- その後「名前はピッケルでいいよ」。

## 仕様（今回の判断）
1. 鉄鉱石を掘れる最初の道具を、石のハンマーから **石のピッケル** に置き換える。内部ID（`Item.HAMMER`、レシピ `tool_hammer`）、レシピ（石2＋木材1、作業台）、性能は**そのまま**（保存互換）。
2. 上位の **鉄製ピッケル・高性能ピッケル** は名前もそのまま。木製採掘具は石だけを掘る道具として名前もそのまま（「ピッケル」と呼ばないので、「鉱石はピッケルで」と矛盾しない）。
3. **鉱石（鉱床）はピッケル（石のピッケル以上）でだけ掘れる。** 横視点の採取はもともとこの規則（木製採掘具・素手は鉱床の採取量0）。**Cの採掘地はこの規則を使っていなかった**（後述）ので、同じ規則にそろえた。
4. 手引きに、木製採掘具の次・Cへ行く前の段階 `ore_tool`「「石のピッケル」を作って装備しよう」を追加。
5. 新しいアイコン `assets/resources/item_stone_pick.png`（48×48、石の刃・木の柄。Codexがスクリプトで描いたオリジナル）。作業台で組み立てる仲間の手持ちの絵は、従来の `item_hammer.png` を直接描いてハンマーのまま。

## 見つかって直した不具合（Cの採掘地）
- `bridge/route_connection_session.gd` の `_reserve_resource` は、仲間の道具を見ずに「残っている資源の先頭」を予約していた。そのため、木製採掘具（あるいは素手）でも、手前の石を掘り終えると鉄鉱石を掘れていた。
- 修正: `can_collect_resource(actor, resource)` を追加し、岩場・鉱床は横視点と同じ `GatherDB.evaluate(...).eff >= GatherDB.MIN_EFF` で判定。掘れない資源は飛ばして次を探す。掘れる資源がないときは待機し、現地の記録に「鉱床にはピッケル（石のピッケル以上）が必要」を残し、現地のHUD（`route_connection_adapter.gd`）にも同じ理由を出す。採掘量・作業時間・残量・積載・再生・保存形式・v18の現地での道具交換は変更なし。

## テストの準備を変えたもの（製品の挙動ではなく、テストの前提）
Cでピッケルなしに鉄鉱石を掘る前提だった既存テストに、採掘役の**装備**だけを足した（9本）。検査（鉱石の搬入・取引・積載）は緩めていない。
- `test_recovery_town_market_cycle` / `test_full_survival_market_cycle` / `test_normal_haul_frame_progression`: 採掘役に石のピッケル。
- `test_mine_path_clearance`: 石1個分の積載予算を検査するため、採掘役に木製採掘具。
- `test_mine_path_ui`: 積載警告の表示データに木製採掘具と資源の種類を設定し、鉱床の装備不足の表示も検査。
- `test_recovery_frame_upgrade_cycle_v3`（Claudeが全回帰で検出して追加）: Cへ入る前に採掘役へ石のピッケルを持たせた。木材・皮・鉱石は従来どおりプレイで入手したものだけを数える。
- `test_guided_first_lap`: 手引きの `ore_tool` に従って石のピッケルを作って装備。**一周目のCへ入る前に、余った石を倉庫から廃棄する操作を加えた**（下の「残る課題」1）。二周目のハンマー製作は不要になったので削除。

## 追加したテスト
- `tools/test_ore_tool_guide.gd`（24チェック）: 木製採掘具だけなら次の一手が `ore_tool`／依頼中は再依頼を求めない／装備後は `visit_c`／名前と必要装備の文言／読んでも保存内容が同一。実際のA→B→Cの経路でCに入り、**木製採掘具では鉄鉱石を予約も搬入もしない**、**石のピッケルなら鉄鉱石を搬入する**、どちらも帰還を確定できる。

## 検証（Godot 4.7.2.stable.official.ed1daf0bf、Linux）
- Codexの個別実行（各実行で隔離ホーム。報告の要約）: `ore_tool_guide` 24/24、`guided_first_lap` 32/32（2回）、`next_step_guide` 114、`first_loop_guide` 78、`inventory_search` 23、C系（`c_rescue_*`、`c_outpost_entry_v3` と3つの変種、`quarry_return_flow`、`mine_path_*`、`region_boss_*`、`canyon_*`、`first_region_mine_journey_runtime_gate`、`resource_regeneration_field`、市場系、`normal_haul_frame_progression`）すべて FAIL 0・`SCRIPT ERROR` 0・exit 0。
- Codexの途中の失敗（記録として）: `c_outpost_entry_v3 -- normal-director` の初回はHUD変更中の未定義参照で `SCRIPT ERROR` 多数 → 参照を直して成功。装備を足す前の市場系・`mine_path_*`・`normal_haul_frame_progression` は失敗（上の「テストの準備」で対応）。
- Claudeのレビュー: 差分を確認。理由の記録は、採掘役が資源の場所に着いて予約を試みたときだけ書かれ（毎フレームではない）、記録は最大30行。
- 実描画（Xvfb、OpenGL/Mesa llvmpipe、別コピーと専用HOME）: 新規開始 → 作業台と木製採掘具を作った**自然な状態**で、手引きが `ore_tool` を示し、作成画面に「石のピッケル」が新しいアイコンで並ぶことを画像で確認。
- 全回帰の結果は末尾の「全回帰」を参照。

## 既存の失敗（今回の変更とは無関係）
- `tools/test_canyon_parking_vertical_ui.gd` は**変更前のHEADでも16件失敗**する（Codexが変更前後で同じ項目を確認）。全回帰（`run_prototype_checks.py`）には登録されていないテスト。

## 残る課題・判断が必要なもの
1. **Cでは石から先に掘るため、一周目に積載が石で埋まって鉄鉱石まで届かないことがある。** 通しテストは、Cへ入る前に余った石を廃棄して空きを作っている（積載が少ないときの手引きはすでにある）。ピッケルを持った採掘役は鉱床を優先する、などの変更は採掘の順番の仕様にかかわるため、今回は入れていない。
2. 前回からの継続: 遺跡の調査隊の未使用の修理板が戻らない／倉庫の廃棄が注文用素材を保護しない／通常の周回で襲撃が起きない／初期の「回収の優先」で積載が埋まりやすい。

## 未検証
- 実OSの入力（マウス・タッチ）、Windows、実機。CのHUDに出る装備不足の表示の実描画。seed は1種。

## 変更ファイル
- 製品: `bridge/route_connection_session.gd`、`bridge/route_connection_adapter.gd`、`data/gathering.gd`、`data/world_map.gd`、`scripts/game_data.gd`、`scripts/character.gd`、`scripts/production_plan.gd`、`ui/first_loop_guide.gd`、`ui/policy_ui.gd`、`ui/quarry_ui.gd`、`assets/resources/item_stone_pick.png`（＋`.import`）
- テスト: `tools/test_ore_tool_guide.gd`（新規、＋`.uid`）、`tools/run_prototype_checks.py`（1行登録）、上の「テストの準備」の9本と `test_canyon_field_tool_kit_v18`・`test_first_loop_guide`・`test_inventory_search`・`test_next_step_guide`
- 記録: `CLAUDE.md`（作業ログ2行、Codex）、`docs/stone-pickaxe-ore-rule-20261118.md`（本記録）

## 全回帰（今回の変更後のコードで実行）
- `run_prototype_checks.py`（新テスト登録済み、約18分）: import＋123件＝124件中 **123件 exit 0、1件失敗**（`recovery_frame_upgrade_cycle_v3`：Cで最初の鉱石を掘れずに失敗）。`SCRIPT ERROR` 0、後片付け成功。
- 失敗の原因は、このテストもピッケルなしでCの鉄鉱石を掘る前提だったこと（Codexの確認一覧に入っていなかった）。上の「テストの準備」と同じ方針で、Cへ入る前に採掘役へ石のピッケルを持たせた。修正後は単独で **2回とも 50件 ok・失敗0・`SCRIPT ERROR` 0・exit 0**。
- 変更したのはこのテストファイル1つだけなので、全回帰は再実行していない（製品コードは全回帰のときと同じ）。
- 全回帰が作業コピーに書いた生成物（`prototypes/recovery_map_lab/results/route_connection_runtime/` の1件の変更と1件の新規）はコミットせず、証拠領域へ退避して元に戻した。
