# A地域 回収ルート接続試作 — 実装・検証記録

実装日: 2026-10-27
worktree / branch: `worktrees/recovery-map-scale-lab` / `codex/recovery-map-scale-lab`
基準HEAD: `5ff50c44950d36bbb703e9998ea05858902221fb`

> 後続のC前哨地対処・回収・撤退を含む実装は [START_HERE.md](START_HERE.md) と [OUTPOST_ROUTE_REPORT.md](OUTPOST_ROUTE_REPORT.md) に分離して記録する。この文書の基準HEADは最初の接続試作時点の履歴である。

## 作れた範囲

既存の横視点 `main.tscn` を改変せず、worktree 内の新規 bridge が次をつなぐ。

```text
A はじまりの街 → B 近郊の森 → C 古い採石場（既存 WorldTrip）
                                      ↓
                    固定クォータービュー: 駐車基地 → 中継／保管 → ゲート/迂回 → 敵施設・資源
                                      ↓
                         C → B → A（既存 WorldTrip）
```

- `Main.workers` の実在 `Worker` を、採取・運搬・護衛の役割へ一時投影する。名前・武器・補助装備・道具は入場時と復元時の照合対象にする。既存Workerの処理は停止し、位置・手持ち・HP・疲労・ストレスはsessionから毎frame投影する。在庫・時間の正本確定だけを退出時に一度だけ行う。
- 資源は `WorldTrip.locations["region:c_quarry"]` の有限 GatherPoint 台帳から読む。labの仮在庫・仮actorは使わない。
- 現地では session が予約、手持ち、relay、搬入口列、ゲート、経過時間を唯一の正本として持つ。退出時だけ、有限資源の残量差分と `BaseStorage` への搬入を一回だけ確定する。
- 主経路閉鎖は迂回路へ再経路化し、全経路閉鎖は安全待機へ移る。人を恒久障害物にはせず、ゲート状態変化時だけ経路要求数を増やす。
- 搬入口は1口／2口を切替できる。通常の `user://` と `SaveGame.write()` は bridge で使わない。
- C固定画面では既存 `sand_stalker` 3体をsession内だけで対処し、既存の武器式・敵定義・HP30低HP撤退を使う。追加drop・新数値は作らない。詳細は [OUTPOST_ROUTE_REPORT.md](OUTPOST_ROUTE_REPORT.md) にある。

接続境界と正本の詳細は [CONNECTION_PLAN.md](CONNECTION_PLAN.md) に記録している。

## 起動と操作

Godot 4.7.2で、worktree root から次のどちらかで起動する。

```powershell
.\run_recovery_route_bridge.bat
```

または `scenes/recovery_route_bridge_launcher.tscn` をGodotで開き、F6を押す。`GODOT_472` 環境変数があればbatはその実行ファイルを使う。

1. 右上の **「A→C 古い採石場へ移動」** を押す。既存の横視点で A→B→C を通過する。
2. C到着時に固定クォータービューが開き、既存仲間が採取・運搬・護衛を始める。主経路、全経路、搬入口数をその画面のボタンで切替できる。
3. **「全班を駐車基地へ帰還」** で現地の予約・手持ち・relay・入口列を解消する。帰還可能になったら **「横視点へ戻り、C→Aを開始」** を押す。

GUIの検証保存→読込は次の2操作だけである。

1. 固定クォータービューで **「検証保存（通常 user:// は使わない）」** を押す。
2. 同じ固定クォータービューで **「検証読込（この固定画面へ復元）」** を押す。

保存先は `res://prototypes/recovery_map_lab/results/route_connection_runtime/gui_route_session.json` に固定し、パス脱出を拒否する。これは開発worktree内の検証fixtureであり、通常セーブやexport後の保存機能が成功したことを意味しない。

この2ボタンの**実クリック**は今回の自動診断対象ではない。一方で同じ保存／読込APIを使う「運搬中保存→新Godotプロセス復元」は下記の自動診断で実行済みである。

## 実Viewport証跡

Windows rendererで実行したGodot viewportをそのまま保存した。画像生成物ではない。

- [横視点 C到着画面](evidence/route_connection/horizontal_c_runtime.png)
- [固定クォータービュー画面](evidence/route_connection/quarter_view_runtime.png)
- [前哨地の横移動→対処→cargo→復路の実Viewport証跡](OUTPOST_ROUTE_REPORT.md#実行環境と実viewport)

`render_capture.json` は project-local runtime fixture（git ignore）にあり、Windows DisplayServer、両PNGの保存成功（error `0`）、通常 `user://` 未使用、資源保存則OKを記録する。

## 接続試験（実行済み）

実行環境: Windows 11 / Godot `4.7.2.stable.official.ed1daf0bf` / headless logic test、通常SaveGame無効。
実行コマンド:

```powershell
python tools/run_checks.py --godot <Godot_v4.7.2_console.exe> --check a_recovery_bridge --output-dir <repo外の結果フォルダ>
```

最終のクリーンrun結果: `import` 12.750秒、`a_recovery_bridge` 12.578秒、両方 passed。ランナーは `FAIL`／`SCRIPT ERROR`／成功marker欠落／fixture結果欠落を失敗として扱う。

|条件|結果|確認内容|
|---|---|---|
| 3連続 A→C→固定画面→A | passed | 各cycleで有限資源、relay、手持ち、入口列を解消し、本編在庫へ一回だけ確定。 |
| 復路途中の取消 | passed | C→Bの横視点移動を途中取消し、Cへ戻っても貨物・仲間数が増減しない。 |
| 主経路閉鎖 / 全閉鎖 | passed | 主経路は迂回、全閉鎖は安全待機。待機後のtickで経路要求数が増え続けない。 |
| 満載 | passed | `BaseStorage` 容量0のfixtureでは確定を拒否し、在庫・資源・cargoを変えない。空きを戻すと一回だけ確定。 |
| 運搬中保存→新Godotプロセス | passed | project-local JSONを別プロセスで読込み、仲間キー・名前・装備・数量・予約を照合後に帰還・搬入。 |
| 画面外 / 二重処理 | passed | 固定画面のsession tickはカメラ位置に依存せず、復元後も手持ち・数量を二重処理しない。 |

## 既存本編の回帰確認（実行済み）

bridge追加後、既存の診断ランナーで次の本編テストを実行した。これはbridge機能そのものの描画確認ではなく、既存のA地域・世界地図・通常保存の診断が今回の追加で壊れていないことを確認するための別runである。

|チェック|結果|wall time|
|---|---|---:|
| import | passed | 18.500秒 |
| first_region_map | passed | 29.016秒 |
| world_map | passed | 16.687秒 |
| save_game | passed | 18.015秒 |

このrunの集計は passed、`source_changed_during_run: false`。出力はリポジトリ外の一時結果フォルダにあり、通常プレイヤーの `user://` を使わないようランナー側で隔離した。これは通常セーブのGUI手操作を追加で検証したものではなく、既存のheadless診断結果である。

さらに、最終クリーンrunでは `a_recovery_bridge` に加えて既存 `quarry`（20.984秒）と `save_namespace`（1.547秒）も passed、`source_changed_during_run: false` だった。

## 未達・意図的に含めない範囲

- 通常 `user://` の保存／読込は未達のまま。OS権限・セキュリティ設定は変更していない。固定画面の検証保存／読込ボタンの実クリックも、前面のセキュリティ確認を操作しないため未確認である。
- 完成美術、4地域すべて、既存横視点本編への正式統合、mainへのマージ、pushはしていない。
- 敵施設はC前哨地の最小戦闘状態機械まで。既存の全戦闘AI・HP0救助・負傷／死亡バランスを固定画面へ完全移植したものではない。
- この結果は接続境界・物流・保存則の確認であり、完成版の人数上限や性能保証ではない。

## 変更境界

新規 bridge / launcher / test / evidence だけを追加した。既存 `scripts/main.gd`、`Worker`、`WorldTrip`、`BaseStorage`、`SaveGame`、親worktree、通常セーブは変更していない。
