# 未使用の修理板の持ち帰り・注文用素材の廃棄保護・襲撃が起きない理由（検証記録・checkpoint）

- 基準: `fc97a15f76529b82c0a466cec4e80ce38bad7127`（`claude/core-loop-20261117`）。入口は `cloud_snapshot/project.godot`。
- **今回のNotionは未確認**（このセッションにNotionの接続なし）。
- 実装・検証・記録: Claude（オーナーの指示で、この回はCodexを使わずClaudeが実装。最初にCodexへ依頼したが、作業開始直後に止め、作業コピーに変更が残っていないことを確認してから着手した）。
- オーナーの指示（2026-11-18）: 「確認や質問で作業を止めずにやって」「Claudeがすすめてね Codexではなくて」。`docs/checkpoint-20261114-next.md` の「仕様の判断が必要で、変更していないもの」3点を扱った。

## 1. 遺跡の調査隊に持たせた応急修理板が、使わずに帰っても戻らない（修正）
- 原因: `scripts/expedition.gd` の `start()` が倉庫から修理板を1枚取り出し、`BaseStorage.expedition_weight()` は遠征中もそれを所有物として重さに数えていた。一方、帰還の `_finish()` は未使用の板を戻さないため、帰還の瞬間に所有物が消えていた（修正前のテストで、帰還の前後で積載の重さが 5 → 1 に減ることを確認）。UIは「1枚持たせる」と説明しており、仕様違反と判断した（Codexの以前の調査も「バグ寄り」）。
- 修正: `_finish()` で、持たせた板が未使用なら（踏破・撤退どちらでも）**戦利品より先に**1枚だけ倉庫へ戻す（`store_owned`、所有物の移動として）。遠征の記録に「使わなかった応急修理板を持ち帰った」を残す。使った板は従来どおり消費。戦利品より先に戻すので、積載が戦利品で埋まっても板は失われない。保存形式は変更なし（旗は既存の `kit`／`kit_used` のまま）。
- 新規 `tools/test_expedition_kit_return.gd`（19チェック）: 未使用の板が一度だけ戻る／帰還の前後で重さが正確（遠征中の重さ＋戦利品＝帰還後）／結果画面で待っても再び戻らない／板を使った場合は戻らない／撤退でも戻る／遠征中に保存→読み込み→帰還で一度だけ戻る／帰還後の保存を読み込み直しても増えない。**修正前のコードでは7件失敗、修正後は19/19。** 結果を決めるため、停止中の出発・関門の並び・乱数の種はテストが設定する（ラベル付きの準備）。帰還の処理そのものは製品の `tick → _resolve_step → _finish`。
- `tools/test_expedition_party_restart.gd`: 「倉庫の増減＝戦利品」の厳密な照合に、未使用の板が1枚戻る分を明示的に加えた（検査は緩めていない。戦利品がちょうど一度だけ反映されることは引き続き検査）。

## 2. 倉庫の廃棄で、製作注文・建設の依頼に使う素材まで捨てられる（修正）
- 原因: `Main.warehouse_discard_available` は運搬中の建設材料・運搬の依頼・AIの取りに行く予約は守るが、未着手の製作注文と建設の依頼に取ってある分（`ProductionPlan.held_for_orders`）を守っていなかった。街の売却（`TownEconomy.available`）は守っている。所持品の「使用可能」の表示も同じ値なので、実際より多く見えていた。
- 修正: 新しい関数 `Main.warehouse_discard_limit(item)` ＝ 未予約の数（既存の `warehouse_discard_available`）から `ProductionPlan.held_for_orders` の分も引いた数。**倉庫からの廃棄（確認の作成・実行時の再確認・所持品の廃棄ボタン）と所持品の「予約／使用可能」の表示だけ**がこれを使う。建設の依頼は運搬が始まると依頼の待ちから外れる（`claim_build`）ので、運搬中の建設材料と二重には数えない。
- **範囲を絞った理由（最初の実装の失敗から）**: 最初は既存の `warehouse_discard_available` 自体に注文・依頼の分を足したが、全回帰で `next_step_guide` が8件失敗した。この関数は道の開通の支払い・NPCの給油所・装甲の装着・手引きの材料表示でも「未予約の数」として使われており、作業台の建設を依頼した状態での道の支払いまで変わってしまったため。廃棄以外の挙動は今回の対象ではないので、既存の関数は元に戻し、廃棄と表示だけに新しい関数を使う形にした（失敗した回のログは証拠領域に保存）。
- 新規 `tools/test_discard_order_protection.gd`（15チェック）: 石のピッケルの注文（材料不足で未着手）がある間は、その石2個は廃棄できず予約として表示され、余り1個だけ捨てられる／街の売却と廃棄で使える数が一致／確認を開いた後に注文が入ると古い確認は失敗し何も失われない／注文を取り消すと捨てられる／作業台の建設の依頼（木材3）も同じく守られ、街の売却と一致／依頼を取り消すと戻る。**修正前のコードでは9件失敗（最初の実装で取得）、範囲を絞った最終版で15/15。** 道の支払いなどが使う未予約の数が建設の依頼で変わらないことも検査に加えた。

## 3. 通常の周回で襲撃が起きない（調査のみ。意図した仕様のため変更なし）
- `scripts/director.gd` の `_pick()`（291行目付近）で、**地図モード（`game.world.active`）では「襲撃（attack）」の出来事を候補から外している**（採掘地の避難中も外す）。地図を使う通常の第1地域は常にこの状態なので、時間抽選の襲撃は起きない。
- これは `docs/第1循環と屋外判断_検証記録_2026-10-14.md` で決めた仕様: 「通常地図では時間抽選の襲撃と資源・生物補充の好機を発生させず、地域台帳の有限枠を使用する」。危険は、砂原・鉱山の決まった場所にいるサソリ（赤脚の追跡サソリは屋外の仲間を、灰殻の穿孔サソリは仲間と車体を攻撃）で表現している。
- したがって `docs/checkpoint-20261114-next.md` の「通常の周回で襲撃が0回」は不具合ではない。旧街道モード（`legacy-world-test`）の診断では従来どおり襲撃が起きる。

## 検証（Godot 4.7.2.stable.official.ed1daf0bf、Linux・ヘッドレス）
- 上の2本の新テストは、修正前のコード（`HEAD` の同じファイルに一時的に戻して実行）で失敗し、修正後に成功することを確認した。
- 全回帰の結果は末尾の「全回帰」を参照。
- 実描画（Xvfb、OpenGL/Mesa llvmpipe、別コピーと専用HOME）: 遠征の結果画面の記録欄に「使わなかった応急修理板を持ち帰った」が出ることを画像で確認（撮影用に、在庫・遺跡・関門の並びをテストで設定）。
- 実OSの入力、Windows、実機は未確認。

## 変更ファイル
- 製品: `cloud_snapshot/scripts/expedition.gd`（未使用の板を戻す）、`cloud_snapshot/scripts/main.gd`（`warehouse_discard_limit` を追加し、廃棄と所持品の行で使う）、`cloud_snapshot/ui/inventory_ui.gd`（廃棄ボタンの上限）
- テスト: `cloud_snapshot/tools/test_expedition_kit_return.gd`・`test_discard_order_protection.gd`（新規、＋`.uid`）、`cloud_snapshot/tools/test_expedition_party_restart.gd`、`cloud_snapshot/tools/run_prototype_checks.py`（2行登録）
- 記録: `docs/kit-return-discard-orders-20261118.md`（本記録）、`CLAUDE.md`（作業ログ1行）

## 全回帰（最終版のコードで実行）
- 1回目（最初の実装）: import＋126件中 `next_step_guide` だけ失敗（8件。上の「範囲を絞った理由」）。ログは証拠領域に `full-after-kit-discard-FIRST-next_step_guide-failed` として保存。
- 2回目（範囲を絞った最終版）: `run_prototype_checks.py`（新テスト2本登録済み、約20分）: import＋126件＝**127件すべて exit 0**、後片付け成功、`SCRIPT ERROR` 0。`FAIL` を含む行は3つで、いずれも失敗ではない（`field_status_ui_v3_1` の座標の診断出力、`ui_modal_feedback` と `armor_install_cycle` の「FAILURES 0」の集計行）。
- 全回帰が作業コピーに書いた生成物（`prototypes/recovery_map_lab/results/route_connection_runtime/`）はコミットせず、証拠領域へ退避して元に戻した。
