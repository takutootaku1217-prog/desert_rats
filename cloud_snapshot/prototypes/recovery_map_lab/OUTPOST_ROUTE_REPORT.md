# A地域 前哨地回収ルート試作 レポート

実装日: 2026-10-27
worktree / branch: `worktrees/recovery-map-scale-lab` / `codex/recovery-map-scale-lab`
今回の開始基準HEAD: `e71d6c5 Add A-region recovery route bridge prototype`

## 作れた範囲

既存の横視点 `WorldTrip` を使い、A→B→C→B→Aを移動します。Cだけで固定クォータービューのbridge sessionを開始し、既存の仲間・武器・有限GatherPoint・拠点在庫を接続します。

```text
A はじまりの街 → B 近郊の森 → C 古い採石場
                                  ↓
駐車基地 → relay → 閉鎖ゲート / 迂回路 / 遮蔽物 → 前哨地3体 → 既存C有限資源
                                  ↓
                        一度だけ本編の資源差分・cargoを確定
                                  ↓
                              C → B → A
```

- 前哨地は既存 `EventDB.ENEMIES["sand_stalker"]` の定義を使う固定3体です。入口、迂回入口、資源置場に配置し、ゲート閉鎖時は迂回路・遮蔽物を経由します。
- 護衛の攻撃力／射程は既存 `CharacterAI.ATTACK_DPS`、仲間のcombat skill、既存武器倍率・射程から求めます。敵の索敵、移動、攻撃周期、縄張りは既存の敵定数／定義を使います。
- 敵の一時状態はbridge sessionだけが所有します。固定画面では `Enemy` ノードを描画専用・process停止で投影し、本編の敵ドロップ・Director・WorldTrip台帳を並列実行しません。追加戦利品、新アイテム、新しい戦闘数値はありません。
- 既存 `CrewStatusDB.RAID_HIT_HP` / `RAID_HIT_STRESS` と `FieldOperations.RETREAT_HP` を使い、HP30以下では護衛が戦闘を打ち切り駐車基地へ戻ります。確定時にHP・疲労・ストレスを既存Workerへ戻し、既存の低HP帰還を開始します。
- `down` / HP0 の救助はこの小試作では横視点へ渡せないため、確定を安全に拒否します。これは実装済みの救助互換を意味しません。
- 前哨地を全対処して確定後、同じ起動中のMainインスタンスで再入場すると、bridgeだけの記録を再利用して3体を再出現させません。通常SaveGame / WorldTrip schemaには追加せず、終了後にこの撃破状態を永続化しません。戦闘中のcross-process復元はproject-local fixtureのsession全体を使います。

## 保存境界

通常 `SaveGame` はbridge / capture / testの開始時に無効化します。検証状態は次のworktree内だけです。

`prototypes/recovery_map_lab/results/route_connection_runtime/`

現地中の予約、手持ち、relay、入口列、敵HP、仲間HP／疲労／ストレスは `RecoveryRouteConnectionSession` が唯一の正本です。既存Workerの処理は停止し、状態はsessionから毎frame投影します。全班撤退でそれらが解消されてから、既存C有限資源の残量差分と駐車基地cargo、現地時間だけを既存正本へ一度だけ確定します。二度目の確定は`already_committed`となり、複製しません。

## 実行環境と実Viewport

- OS: Microsoft Windows 11 Pro 10.0.26200
- CPU: 13th Gen Intel Core i7-1355U
- RAM: 31.6 GB
- GPU / driver: Intel Iris Xe Graphics / 32.0.101.7088
- Godot: `4.7.2.stable.official.ed1daf0bf`
- Renderer: Compatibility, OpenGL 3.3
- capture seed: `104729`

通常レンダラーの同一runで保存したGodot viewportです。画像生成物ではありません。runtime metadata `outpost_render_capture.json` はgit ignoreの検証fixtureにあり、Windows DisplayServer、4枚のPNG保存error `0`、通常 `user://` 未使用、前哨地3/3→0/3、cargo 3、保存則OK、復路`travel`を記録します。

|段階|ローカル実Viewport|
|---|---|
|A→B横移動|[horizontal_travel_runtime.png](evidence/route_outpost/horizontal_travel_runtime.png)|
|前哨地対処|[outpost_combat_runtime.png](evidence/route_outpost/outpost_combat_runtime.png)|
|cargo搬入|[outpost_cargo_runtime.png](evidence/route_outpost/outpost_cargo_runtime.png)|
|C→B復路|[outpost_return_runtime.png](evidence/route_outpost/outpost_return_runtime.png)|

## 公式ライブラリ保存

最終4 PNGを個人スコープのChatGPT Pageの公式Libraryコンテナへ保存し、ページ読込で4参照・byte sizeを確認しました。下表のSHA-256はローカル最終PNGとアップロード応答の両方で一致しています。Windowsではローカルxattr関連付けが未対応のため、Library保存の成功とローカル関連付け未設定を区別します。

Page: [流動拠点サバイバル 前哨地回収ルート実機証跡](PRIVATE_REFERENCE_OMITTED)

|ローカルファイル|SHA-256|Pageの最終Library reference|
|---|---|---|
|`evidence/route_outpost/horizontal_travel_runtime.png`|`0193c0dd77f61d63a655fab6657c73798be0c95c96c54eaf5e95537b46e562bc`|`library-file:fde1_bGliZmlsZV9NYUJhSm9rd25IZHhUZnZTZ0lySGxn_FileDrive_d58605261fa48191af10d4507594b26f`|
|`evidence/route_outpost/outpost_combat_runtime.png`|`185c921232c779f5c4b8a23426f844a1ef583968f3bc7ef0a7aa1c3ab841ffd2`|`library-file:fde1_bGliZmlsZV9NY2NNQU8yUDlWaDFWNERtMXlqU0t3_FileDrive_d58605261fa48191af10d4507594b26f`|
|`evidence/route_outpost/outpost_cargo_runtime.png`|`a7072ae3b28ec25122360136a64f4e2ad8e06958aa5721e504fa6ca161725524`|`library-file:fde1_bGliZmlsZV85b1pyRTBkczdZYTNpTlBzSmh1RXBR_FileDrive_d58605261fa48191af10d4507594b26f`|
|`evidence/route_outpost/outpost_return_runtime.png`|`e522d7dd412c59bed60014079710f323758b42ab363a47eba402fae6611f41c3`|`library-file:fde1_bGliZmlsZV9qaEFfN3BhTkktaFNaNGpJZm9kSmd3_FileDrive_d58605261fa48191af10d4507594b26f`|

## 検証状況

実装前の既存本編回帰は次で実行済みです。

```powershell
python tools/verify_current.py --godot <Godot_v4.7.2_console.exe> --output-dir <QA_OUTPUT_ROOT>/recovery-route-outpost-preflight
```

結果ファイル: `<QA_OUTPUT_ROOT>/recovery-route-outpost-preflight\20261027T054632Z-current-release\summary.json`
結果: `godot_4_7_2 / harness / large_graphics / layout / core / first_region_map` はすべてpassed、source変更なし。

敵描画同期を含めた最終の既存本編回帰も実行済みです。

結果ファイル: `<QA_OUTPUT_ROOT>/recovery-route-outpost-final-full-visual-sync\20261027T080811Z-current-release\summary.json`
結果: `godot_4_7_2 / harness / large_graphics / layout / core / first_region_map` はすべてpassed。各suiteの`results.json`で `source_changed_during_run: false` を確認しました。これは既存本編の回帰であり、前哨地固有の振る舞いは下表のbridge suiteで別に確認しています。

|確認|状態|根拠|
|---|---|---|
|A→C→前哨地対処→回収→A|passed|`20261027T080625Z-4ov0a6z8` の `a_recovery_outpost`（13.594秒、source変更なし）|
|戦闘中保存→別Godotプロセス復元→撤退|passed|同じ `a_recovery_outpost` child process|
|HP30閾値での負傷撤退|passed|同じ `a_recovery_outpost`|
|同一run再入場で敵を再出現させない|passed|同じ `a_recovery_outpost`|
|HP0→down→確定拒否|passed|同じ `a_recovery_outpost` の明示的な安全境界テスト|
|既存本編の最終総合回帰|passed|`20261027T080811Z-current-release` の `verify_current.py`（harness / large_graphics / layout / core / first_region_map、source変更なし）|
|GUI保存→読込の実クリック|未確認|前面のセキュリティ確認を操作しないため `FrameArrived timed out: timed out waiting on channel`|
|通常`user://`保存|範囲外・未確認|bridgeは意図的に使用しない|

## 再実行

```powershell
python tools/test_run_checks.py
python tools/run_checks.py --godot <Godot_v4.7.2_console.exe> --suite route_connection --output-dir <repo外の結果フォルダ>
python tools/verify_current.py --godot <Godot_v4.7.2_console.exe> --output-dir <repo外の結果フォルダ>
```

GUI実行は[START_HERE.md](START_HERE.md)に従います。通常描画証跡の再作成は`tools/capture_a_recovery_outpost.gd`を`--headless`なしで起動します。headlessの同スクリプトは`ROUTE_OUTPOST_CAPTURE_SKIPPED_HEADLESS`だけを出し、PNG成功とは扱いません。
