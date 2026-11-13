# 回収ルート・マップ規模ラボ

`流動拠点サバイバル` 本編とは別に置く、回収ルートと人数規模を比較するための Godot 4 試作です。ここにあるものは実験台であり、本編の仕様、セーブ、入力、Autoload、シーン、ゲームバランスを変更するものではありません。

> A地域の既存横移動とC地点の固定クォータービューを接続する、worktree限定の前哨地回収試作は [START_HERE.md](START_HERE.md) から起動できます。実機証跡・制約・回帰結果は [OUTPOST_ROUTE_REPORT.md](OUTPOST_ROUTE_REPORT.md) を参照してください。これはこのラボのS/M/L比較とは別の小さな接続検証です。

## 現在の状態

実行可能なGodotシーン、自己検査、JSON/CSV計測器、Windows GUIで保存した実Viewportスクリーンショットを含みます。代表3条件（S-05-E00／M-30-E20／L-50-E20）は、非headlessの新規Godotプロセスで描画込み30秒計測とViewport PNG保存まで実行しました。敵あり本命4条件は、headlessの10秒準備＋120秒×3を完了しています。`REPORT.md` は、実行済みと未実行を分けて記録します。描画込みの12条件性能比較、敵ありの描画込み120秒反復、録画、長期安定性は未完です。

作業開始時には、依頼で指定された添付 `START_HERE.md` と `TEST_PLAN.md` は親作業フォルダおよび既存ゲーム内で確認できませんでした。親作業フォルダには `START_HERE_GAME.txt` があり、試験条件はユーザー依頼本文に記載された「試験計画｜広さ・人数・敵・経路・搬入口を分けて比較する」を正として実装・報告します。今回のbridge用の開始手順はこのディレクトリの [START_HERE.md](START_HERE.md) として追加しています。

## 分離と保存先

- 試作の配置先: `prototypes/recovery_map_lab/`
- Git作業先: 専用worktree、ブランチ `codex/recovery-map-scale-lab`
- 作業開始時の基準HEAD: `3832b38b38b3f42669d635e5a9246f4175011e0e`
- アプリ名: `流動拠点サバイバル — 回収ルート比較ラボ`
- Godot保存名前空間: `config/use_custom_user_dir=true`、`config/custom_user_dir_name="recovery-map-scale-lab"`
- 実験状態の保存名: 上記専用 `user://` 内の `recovery_map_lab_state.json`

本試作は既存ゲームを参照・変更せず、既存の通常セーブを読込・書込しません。既存素材や共有GDScriptを必要とする実装は採らず、このディレクトリ内の小さな独立実装にします。

## 起動

PowerShellでこのディレクトリへ移動して、既存のGodot 4.7.2を指定します。

```powershell
& '<GODOT_4_7_2_EXECUTABLE>' --path .
```

基準の操作確認は `S / 5人 / 敵0 / 通常操作 / seed 104729` を選び、**「実験を生成して開始」→「回収開始」**です。

## 実験する基本ループ

安全地帯の移動拠点から、遠い敵施設の資源置場へ回収班が向かい、資源を予約して回収し、護衛を伴って搬入口へ戻り、順番待ちの後に在庫へ搬入します。

同じ地形には、通常の主経路、閉鎖できるゲート、ゲート閉鎖時の迂回路を少なくとも一組置きます。全経路を閉鎖する検査では、到達不能を明示して安全な待機へ移行し、毎フレームの無限再探索はしません。

ゲームプレイ乱数と装飾乱数は分離しています。基準seedは `104729` で、自己検査が同じプリセットとseedの生成データ一致を確認します。

## マッププリセット

通常の画角は1280×720、ズーム1.0を基準とします。S/M/Lで人物、建物、ゲート、移動速度を拡大・縮小しません。

| プリセット | world範囲 | 画面分の目安 | 比較目的 |
|---|---:|---:|---|
| S | 3840×1440 | 3×2 | 一周、操作、入口混雑、保存確認 |
| M | 7680×2160 | 6×3 | 複数班と中継・分岐の確認 |
| L | 15360×2880 | 12×4 | 長い帰還路と画面外シミュレーションの確認 |

生成はランダムな大陸ではなく、以下の固定部品を連結する方式です。

`安全地帯・移動拠点 → 中継／集積地点 → 接続区間群 → 峡谷・分岐・ゲート → 敵施設外周 → 資源置場`

S/M/Lは主要地点と分岐構造を共通にし、接続区間の数または長さだけを増やします。生成後には主要地点の接続、スポーン、迂回路の到達可能性を検査し、不合格時は理由を記録します。

## 人数、役割、敵

味方の一人あたりの速度、積載、作業時間、索敵・攻撃条件は人数・マップ規模にかかわらず固定します。役割配分は次の通りです。

| 味方総数 | 戦闘班 | 護衛班 | 回収班 |
|---:|---:|---:|---:|
| 5 | 2 | 1 | 2 |
| 10 | 3 | 3 | 4 |
| 30 | 10 | 8 | 12 |
| 50 | 16 | 14 | 20 |

回収班は資源予約、短い作業、運搬、入口待機、搬入を行います。護衛班は対応する回収班の周囲を守り、無制限には追跡しません。戦闘班は巡回・近距離の接近・攻撃・HP 25以下での拠点退避を行い、敵は索敵・接近・攻撃の後に対象を失うと持ち場へ戻ります。これは簡易AIで、地形に沿う戦術移動・遮蔽物・隊形は未実装です。敵数は味方数と独立に `0 / 20 / 50` を選べるようにし、HUDとログでは味方・敵・合計稼働人数を分けます。

## 経路探索と混雑の扱い

経路探索には **AStar2Dだけ**を用います。固定の主要地点と接続路に地形・崖・建物・ゲートの通行可否を持たせ、仕事開始、ゲート状態変更、保存読込など必要な時点だけ広域経路を更新します。

この選択は、固定seedの再現性、ゲートによる通行可否の明示的な切替、生成後の接続検査に向いているためです。描画部品と経路グラフは分離します。人物を恒久的な経路障害物として毎フレームグラフへ書き込まず、狭路での並びと搬入口の混雑は、役割別スロット、隊列、FIFO予約で扱います。

搬入口は1口と2口を切替可能にし、入口待ち時間、最大待機人数、搬入量を別々に記録します。ゲート閉鎖による経路変更と、局所的な混雑回避を同じ仕組みとみなさないことが重要です。

## 表示と操作

画面は固定角度の斜め見下ろし2Dです。仮素材でも床、崖、屋根と側面を持つ建物、扉、資源、車両、役割別の人物、荷物の有無、向きを識別できます。描画順は足元を基準にしています。

起動設定画面では、マップ（S/M/L）、味方（5/10/30/50）、敵（0/20/50）、seed、通常操作または人数固定負荷試験を選べます。ゲーム中のUI操作は次の通りです。

- `回収開始`、`全班帰還` の班単位指示
- `ゲート開閉`、`搬入口 1 / 2`、`計測開始 / 終了`、`実験保存 / 読込`
- `拠点へ移動`、`班へ移動`、WASD／矢印キーによる自由スクロール、ホイールまたはQ/Eによる段階ズーム
- 簡易全体地図、切替式の詳細計測HUD

キーは `R`回収開始、`G`ゲート、`H`拠点、`J`回収班、`O`全体表示、`T`詳細、`F9`画面保存です。全体表示は検証用であり、本編の常時索敵仕様ではありません。

## 計測

フレーム計測はFPS表示だけに依存せず、実時間のフレーム開始間隔をメモリに蓄積し、run終了時にCSVとJSONへまとめて出力します。実装済みの主要指標は次の通りです。

- 平均FPS、フレーム時間の中央値・p95・p99・最大値
- 33.3ms、50ms、100msを超えたフレーム数と、その時のイベント
- 味方、敵、可視人物、弾／エフェクト、ノード数、可能な範囲のPerformance値
- 経路探索要求数／秒、生成時間、経路データ同期時間
- 実経路長、無積載片道、積載帰還、往復、搬入量／分、入口・狭路待ち
- 資源残量＋所持量＋集積量＋拠点在庫の保存則

比較runは、通常画角、固定カメラ経路、同一renderer／解像度／VSync設定を記録します。headless実行はロジック確認用であり、Windowsの描画込みFPS保証には使いません。録画を行う場合は計測runとは別にします。

## CLIとバッチ実行

起動UIと同じ条件を次の形式で指定できます。

```powershell
& '<GODOT_4_7_2_EXECUTABLE>' --headless --path . -- --benchmark --map S --allies 5 --enemies 0 --seed 104729 --warmup 5 --duration 30 --output results\S-05-E00
```

引数は `--map`、`--allies`、`--enemies`、`--entrances`、`--seed`、`--mode`、`--benchmark`、`--warmup`、`--duration`、`--output` です。`--benchmark` は人数固定負荷試験を明示します。`run_benchmarks.ps1` は12件の敵なし一次試験と、優先する敵あり条件を再実行できます。

`tools/run_benchmarks.ps1 -GodotPath <console-exe> -Headless` はロジック用の12件を実行します。描画性能比較をする場合は `-Headless` を外し、録画とは別runにします。実行済みの条件だけを `REPORT.md` に実測値として記載します。

代表条件をGodot自身の通常描画とViewport PNGで再確認する例です。`--headless` を付けず、`--capture` を併用します。`--benchmark` は計測完了後に終了します。

```powershell
& '<GODOT_4_7_2_EXECUTABLE>' --path . -- --benchmark --map L --allies 50 --enemies 20 --seed 104729 --warmup 5 --duration 30 --output results\rerun_render_L50E20 --capture rerun_render_L50E20
```

このコマンドの`run.json`が非ゼロの`draw_calls`を含み、`evidence/screenshots/`にPNGができた場合だけ、通常描画の証跡として扱います。既存DEBUGウィンドウのComputer Use画面取得とは別経路です。

## 検証と再実行

自己検査 `tools/self_test.gd` はS/M/L接続、複数seed、ゲート迂回／全閉鎖、5→50→5再生成、予約、資源保存則、戦闘班の接近／攻撃／退避を32項目で確認します。

```powershell
& '<GODOT_4_7_2_EXECUTABLE>' --headless --path . -s res://tools/self_test.gd
& '<GODOT_4_7_2_EXECUTABLE>' --headless --path . -s res://tools/state_roundtrip_project_test.gd
& '<GODOT_4_7_2_EXECUTABLE>' --headless --path . -s res://tools/return_completion_test.gd
& '<GODOT_4_7_2_EXECUTABLE>' --headless --path . -s res://tools/state_roundtrip_process_save.gd
& '<GODOT_4_7_2_EXECUTABLE>' --headless --path . -s res://tools/state_roundtrip_process_load.gd
& '<GODOT_4_7_2_EXECUTABLE>' --headless --path . -s res://tools/multi_cycle_resume_test.gd
pwsh -NoProfile -File .\tools\audit_enemy_benchmark_runs.ps1
```

`state_roundtrip_project_test.gd` は `results/state_roundtrip/` 内だけに限定した検証用保存先で、保存元を破棄して新しいLabへ読込します。パス脱出を拒否し、人物、荷物、予約、ゲート、入口列、帰還命令、保存則と入口列の解消を確認します。通常の専用 `user://recovery_map_lab_state.json` は変更しません。

`state_roundtrip_process_save.gd` と `state_roundtrip_process_load.gd` は、検証専用のプロジェクト内パスだけを使い、Writer終了後に別Godotプロセスで読込します。人物ID／役割／位置／HP／cargo、予約、ゲート、入口待機、job、帰還状態、保存則を照合し、読込後に帰還列が排出されるまで確認します。通常の専用`user://`は触りません。

`multi_cycle_resume_test.gd` はS-05-E00の実回収ループを在庫16（4回搬入）まで進め、稼働中の隔離保存を新規Labへ読込して在庫24まで追加搬入し、最後に全班帰還を確認します。同一プロセス内のfresh-instance検証であり、別プロセスの保存境界試験とは区別します。

`audit_enemy_benchmark_runs.ps1` は、敵あり本命4条件×3の raw run をマニフェストから再監査します。親runディレクトリ直下に時刻付きrawディレクトリが1個だけあること、`run.json`／`events.csv`／`summary.csv`、exit code、seed、10秒準備＋120秒、固定人口、イベント、保存則を確認します。120秒時点の全班帰還は要件にせず、結果として表示します。

この実行環境では通常の専用`user://`への書込みが `FileAccess.open failed: 12` でblockedでした。`tools/user_save_diagnosis.gd` は既存ファイルを上書きせず、対象・親パス・エラーだけを `results/save_boundary_20261027/user_save_diagnosis.json` に残します。意図的にblocked時は終了コード1です。GUI上の通常保存→読込は未実行です。ユーザー環境では、ラボGUIの「保存」後に「読込」を一度押すだけで確認でき、失敗してもOS権限やセキュリティ設定を変えないでください。通常操作で一周を確認したのはSのみで、M/Lは生成と実Viewport撮影までです。

実Viewport画像は `evidence/screenshots/`、自己検査は `results/self_test.json`、各条件CSV/JSONは `results/` にあります。実機測定、画面確認、録画は、完了したものだけ `REPORT.md` と `results/`、`evidence/` に記録します。

## 固定条件

- Godot: `4.7.2.stable.official.ed1daf0bf`
- Renderer: `gl_compatibility`
- 解像度: 1280×720
- VSync: off、FPS上限: なし（`project.godot`に明示）
- 基準seed: `104729`
