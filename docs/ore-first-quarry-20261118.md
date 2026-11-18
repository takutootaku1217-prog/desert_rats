# Cの採掘地で、ピッケルを持つ採掘役は鉱床を優先する（検証記録・checkpoint）

- 基準: `a4325420dd0ce5dcc2265247f17e91efbde14f11`（`claude/core-loop-20261117`、前回の `docs/stone-pickaxe-ore-rule-20261118.md` の続き）。入口は `cloud_snapshot/project.godot`。
- **今回のNotionは未確認**（このセッションにNotionの接続なし）。
- 実装: OpenAI Codex（公式Claude Codeプラグイン経由、同じ作業コピー・書き込み可）。仕様・レビュー・全回帰・独立確認・記録: Claude。

## オーナーの指示（2026-11-18）
- Claudeの提案「ピッケルを持つ採掘役がCで鉱床を優先して掘る」に「いいよ、Codexにやってもらって」。

## 背景
前回の変更（鉱石はピッケルで）のあとも、Cの採掘地は掘れる資源のうち**最初に見つかったもの**を予約していた。資源の並びでは石が先にあるため、石のピッケルを持っていても先に石を掘り、積載の空きが少ないと鉄鉱石まで届かなかった。通しテストは、Cへ入る前に余った石を廃棄して空きを作っていた。

## 仕様（今回の判断）
- ピッケルを持つ（`can_collect_resource` が鉱床に対して真の）採掘役は、予約されておらず、残量があり、積載に鉄鉱石1個分の空きがある**鉱床を、石より先に**選ぶ。
- 鉱床が尽きた・ほかの仲間が予約している・鉄鉱石1個分（重さ8）の空きがない、のいずれかなら、従来どおり石を掘る（待機しない）。
- ピッケルがない採掘役は従来どおり石だけ。岩場・鉱床以外の種類の扱いと順番は変えない。
- 乱数は使わない（決定的）。v18の現地での道具交換でピッケルに持ち替えたら、次の予約から鉱床を優先する。
- 採掘量・作業時間・残量・積載・袋・再生・重さ・レシピ・ID・保存形式は変更なし。変えたのは「どれから掘るか」の順番だけ。

## 変更（`bridge/route_connection_session.gd` の `_reserve_resource`）
- 最初に見つかった掘れる資源を候補にし、それが岩場なら、そこで決めずに後ろの鉱床（掘れて積載に入るもの）を探す。見つかれば鉱床を、なければ最初の候補を予約する。
- 待機の理由（積載不足／鉱床にはピッケルが必要）の記録は前回の挙動のまま。

## テスト
- `tools/test_ore_tool_guide.gd`（44チェック）: 実際のA→B→Cの経路で、石のピッケルなら**最初の予約と最初の搬入が鉄鉱石**／空きが鉄鉱石1個に足りず石なら入るときは**石を掘る**（待機しない）／鉱床を掘り尽くしたら石に戻る／木製採掘具では従来どおり鉄鉱石なし・石を搬入／どの場合も帰還を確定できる。
- `tools/test_guided_first_lap.gd`（31チェック）: **一周目のCへ入る前の「余った石の廃棄」を外した**。Cに着いたときの積載の空きは104で、廃棄なしで最初の帰還で鉄鉱石3個を搬入（2回とも）。最初の搬入で倉庫の鉄鉱石が増えることを検査に加えた。チェック数が32→31なのは、廃棄の検査1件がなくなったため。
- 既存テストの「石と鉄鉱石の内訳」の検査で、順番の変更により直す必要があったものはなかった（Codexの報告）。

## 検証（Godot 4.7.2.stable.official.ed1daf0bf、Linux）
- Codexの個別実行（各実行で隔離ホーム）: 上の2本に加え、`recovery_frame_upgrade_cycle_v3` 50、市場系・`normal_haul_frame_progression`、`quarry_return_flow`、`mine_path_*`、`c_rescue_*`、`c_outpost_entry_v3` と3つの変種、`region_boss_*`、`canyon_field_tool_kit_v18`、`canyon_equipment_fixed_parking`、`first_region_mine_journey_runtime_gate`、`resource_regeneration_field`、`c_field_active_owners`、`c_field_save_ui`、`vehicle_hunt_survival_cycle`、`c_expired_recovery`、`next_step_guide`、`first_loop_guide` がすべて FAIL 0・`SCRIPT ERROR` 0・exit 0。
- `c_field_save_ui` の初回は、前提の保存ファイル（`c_field_active_owners` が作る）がなく1件失敗。正しい順に実行して成功（前回の記録と同じ既知の前提）。
- **既存の失敗（今回と無関係）**: `tools/test_canyon_parking_vertical_slice.gd` は、変更前（`a432542` をそのまま取り出したコピー）でも変更後でも、同じ5項目が失敗する（中継停車への移動・停め直し・中継のprofile表示）。Codexの報告をClaudeが別コピーで独立に再現し、失敗項目が一致することを確認した。全回帰（`run_prototype_checks.py`）には登録されていないテスト。
- 全回帰の結果は末尾の「全回帰」を参照。

## 残る課題
- 二周目は、Aの購買店で積載を整理する前の時点で、積載の空きが **2 / 360** まで減っていた（停車中の自動採取で木材・石が増えるため）。積載が少ないときの手引きはあるが、初期設定の「回収の優先」で木材・石が積載を埋めやすい点はそのまま（前回からの判断待ち）。
- 前回からの継続: 遺跡の調査隊の未使用の修理板が戻らない／倉庫の廃棄が注文用素材を保護しない／通常の周回で襲撃が起きない。
- 実OSの入力、Windows、実機は未検証。seed は1種。

## 変更ファイル
- 製品: `cloud_snapshot/bridge/route_connection_session.gd`
- テスト: `cloud_snapshot/tools/test_ore_tool_guide.gd`、`cloud_snapshot/tools/test_guided_first_lap.gd`
- 記録: `CLAUDE.md`（作業ログ1行、Codex）、`docs/ore-first-quarry-20261118.md`（本記録）

## 全回帰（今回の変更後のコードで実行）
- `run_prototype_checks.py`（約18分）: import＋123件＝**124件すべて exit 0**、後片付け成功、`SCRIPT ERROR` 0。`FAIL` を含む行は3つで、いずれも失敗ではない（`field_status_ui_v3_1` の座標の診断出力、`ui_modal_feedback` と `armor_install_cycle` の「FAILURES 0」の集計行）。
- 全回帰が作業コピーに書いた生成物（`prototypes/recovery_map_lab/results/route_connection_runtime/` の2件の変更と1件の新規）はコミットせず、証拠領域へ退避して元に戻した。
