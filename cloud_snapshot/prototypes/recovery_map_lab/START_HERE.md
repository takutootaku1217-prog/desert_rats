# A地域 前哨地回収ルート試作 開始手順

これは `codex/recovery-map-scale-lab` worktree 専用の実験入口です。本編の `main`、親worktree、通常セーブ、既存ゲーム設定には変更を加えません。

この試作は、既存の横視点の **A はじまりの街 → B 近郊の森 → C 古い採石場** と、C地点だけの固定クォータービューをつなぎます。Cでは既存仲間・装備・有限資源を投影し、前哨地の既存 `sand_stalker` 3体を対処してから、回収・relay・搬入口・復路を確認します。

## 起動

Godot 4.7.2で、worktree rootから次を実行します。

```powershell
.\run_recovery_route_bridge.bat
```

Godotエディタでは `scenes/recovery_route_bridge_launcher.tscn` を開き、F6でも起動できます。`GODOT_472` 環境変数があればbatがその実行ファイルを使用します。

## 一周の操作

1. 右上の **A→C 古い採石場へ移動** を押します。既存 `WorldTrip` で A→B→C を移動します。
2. C到着後の固定クォータービューで、護衛が前哨地の3体を対処します。閉鎖した主経路は迂回路と遮蔽物を通ります。
3. 前哨地が対処済みになると回収役が既存C有限資源を回収し、relayと駐車基地cargoへ運びます。
4. **全班を駐車基地へ撤退・帰還** を押します。予約・手持ち・relay・搬入口列が解消されると、**横視点へ戻り、C→Aを開始** が有効になります。
5. C→B→Aの既存横移動が完了すれば一周です。

## 検証保存と読込

固定画面で、次の順に押します。

1. **検証保存（通常 user:// は使わない）**
2. **検証読込（この固定画面へ復元）**

保存先は `prototypes/recovery_map_lab/results/route_connection_runtime/gui_route_session.json` に固定されています。これはworktree内の検証fixtureだけであり、通常 `user://` セーブやexport版セーブの確認ではありません。

この環境では2026-10-27にComputer Useで実クリックを試みましたが、前面の `ファイルを開く - セキュリティ警告 がアクセス許可を要求しています` を操作しない方針のため、Godot画面のフレーム取得が `FrameArrived timed out: timed out waiting on channel` となりました。よってボタンの実クリックは**未確認**です。保存／復元APIを使う戦闘中の別Godotプロセス復元は自動テストで確認します。

## 実行済みの実機証跡

Windows通常レンダラーのGodot viewportから、画像生成を使わずに保存しました。

- [横移動](evidence/route_outpost/horizontal_travel_runtime.png)
- [前哨地対処](evidence/route_outpost/outpost_combat_runtime.png)
- [cargo 搬入](evidence/route_outpost/outpost_cargo_runtime.png)
- [復路](evidence/route_outpost/outpost_return_runtime.png)

詳細な状態値、ライブラリ保存先、テスト結果、未達は [OUTPOST_ROUTE_REPORT.md](OUTPOST_ROUTE_REPORT.md) を参照してください。接続の正本と確定境界は [CONNECTION_PLAN.md](CONNECTION_PLAN.md) に記録しています。

## 再実行

```powershell
python tools/run_checks.py --godot <Godot_v4.7.2_console.exe> --suite route_connection --output-dir <repo外の結果フォルダ>
& <Godot_v4.7.2_console.exe> --path . -s res://tools/capture_a_recovery_outpost.gd
```

2つ目のコマンドは `--headless` を付けません。headlessの場合は構成確認だけを行い、`ROUTE_OUTPOST_CAPTURE_SKIPPED_HEADLESS` と記録してPNG成功とは扱いません。

## 範囲外

- 固定画面に本編の `Enemy` / `CharacterAI` を並列実行すること、敵ドロップ、新アイテム、屋内施設／ダンジョンは含みません。
- HP 0 / `down` の本編救助への引渡しは未実装で、最小前哨地sessionは安全に確定を拒否します。HP30以下の既存低HP撤退は実装・テスト対象です。
- 撃破済み前哨地は、同じ起動中の横移動runで再入場した場合だけ再出現しません。通常セーブのschemaを広げないため、終了後の永続化はこの試作の対象外です。
