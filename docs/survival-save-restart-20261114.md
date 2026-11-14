# 通常生存時計を進めた循環の保存・再開QA（第6工程の記録・checkpoint）

- 基準: `69a2b5ec2363f09ec6757b2c19d96ad474c822a8`。作業枝 `claude/safe-gameplay-fixes-20261114`。入口は `cloud_snapshot/project.godot`。**製品コードの変更なし**（欠陥は再現しなかった）。数値・経済・天候・敵の仕様は変更していない。

## 追加したもの（既存の検証枠を再利用。新しいrunnerは作っていない）
- `tools/survival_save_common.gd`: 共通の部品（テストではない）。既存 `test_vehicle_hunt_survival_cycle` と同じ刻み（`main._process` と生物・敵・仲間の `_process`）、同じ標準の設定（通常のディレクター、速度60、食料の補充目標）、同じ市場の操作を使う。`SURVIVAL_SEED` 環境変数でseedを変えられる（既定は既存テストと同じ 104729）。
- `tools/test_survival_save_cycle.gd`（保存側、7チェック）: 通常のディレクターで1周（森へ出発→自然な狩猟→200秒滞在→c_quarry・d_yard経由で街へ帰還→売却・購入・給油）し、街で安全に停車した後に**実セーブ**を書く。台帳（食料・肉・皮・骨・燃料・修理板・通貨・燃料・損傷・`total_eaten`・`total_hunted`・ディレクター時間・仲間ごとの空腹・修理予約・世界の地域/状態・遠征/`away`）を横に保存。
- `tools/test_survival_save_restart.gd`（再開側、18チェック）: **別のGodotプロセス**でセーブを読み込み・適用し、台帳が**完全に一致**することを確認。続けて通常の刻みで、次の出発→自然な狩猟→滞在→帰還→市場を進め、街で自然な空腹の食事が起きるまで待つ。その後の台帳照合: 通貨は自然な売買だけで変化／食料の収支（所有＋食べた＝開始＋2×調理＋購入）／肉の調理／狩猟数と撃破数の一致／`total_eaten` は観測した食事の回数ちょうど／燃料は走行で減る／在庫は負にならない／損傷は0〜100／予約は整合。
- ランナーに、保存側→再開側の順で登録（`survival_save_cycle`、`survival_save_restart`）。

## 実測値（Godot 4.7.2 公式ビルド、Linux・ヘッドレス）
- 版 `4.7.2.stable.official.ed1daf0bf`（実行ファイル SHA256 `8d106cbe…`）。別コピーのプロジェクト、専用の HOME / FLUID_TEST_HOME / APPDATA / LOCALAPPDATA / XDG_DATA_HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME。既存セーブ・既存clone・旧作業フォルダには触れていない。
- seed 104729 / 7 / 20261114 の3つで、保存側 7/7・再開側 18/18 がすべて成功。例（seed 104729）: 保存側は約311秒進行（ディレクター時間は街の外で+311秒）、自然な狩猟4回（肉4）、売却16 Cr・購入3 Cr、燃料100まで給油。再開側は約914秒進行（走行で燃料 100.0→97.8、ディレクター時間 +314秒、街で600秒待って自然な食事3回）、狩猟4回（肉4、調理4、食べた3）、通貨は −3 Cr（燃料給油）で台帳と一致。seed 7 も同じ形（食事3回）、seed 20261114 は約806秒（食事3回、支出8 Cr）。
- 関連（各 exit 0、SCRIPT ERROR 0、FAIL 行 0）: 既存の `vehicle_hunt_survival_cycle`、`field_survival_clock_v3`、前回の `expedition_party_cycle` 8 / `expedition_party_restart` 14 / `recovery_town_market_cycle` / `recovery_town_market_restart` 22。
- **全回帰は実行していない**（製品コードの変更がないため）。過去の全回帰の結果は、今回の証拠としては使っていない。

## fixture/入力と限界
- **fixture/API入力:** seed、速度、食料の補充目標、仲間が採取しない設定（既存の生存テストと同じ）。**注入していないもの:** 食料・肉・通貨・燃料の補充、撃破、世界時計の停止。入力は実OSではなく、API・ステップ呼び出し。別プロセスでの再開は、別のGodotプロセスの起動で行っている。
- **街での待機の扱い:** 街（安全停車）ではディレクターの世界時計は止まるが、空腹は進む（既存の生存テストと同じ前提）。そこで待って自然な食事を観測している。これは**長期の生存・収支の保証ではない**。
- この3seedの継続では、攻撃・ゲームオーバーは起きていない（自然な結果）。攻撃を受けた後の保存・再開、長時間の複数周、天候・敵の組合せ、遠征と生存周の同時進行は、今回の範囲外。実画面（GUI）、Windows、実機は未確認。
- 次担当: 小津さん（独立レビュー）。この作業はここで停止。追加課金なし・自動交代なし。

## 変更ファイル
- `cloud_snapshot/tools/survival_save_common.gd`、`test_survival_save_cycle.gd`、`test_survival_save_restart.gd`（新規）、`run_prototype_checks.py`（登録）、本記録。旧 `PUBLIC_SOURCE_MANIFEST_v2.json` と旧証拠は変更していない。
