# C採石場・一地点回収ループ v16 handoff

## これは何か

v15.4 の累積検証コピーへ重ねる、**C採石場一地点の検証用 overlay** です。
固定カメラのクォータービューで、既存の通常3人分業が
`地面 → 手持ち → 中継 → 車内 → 帰還確定` を保ちながら、主路閉鎖の迂回、
満載保持と容量回復後の再開、整備後の中継停車を行うことを明示します。

本編 `main.tscn`、通常 `user://` セーブ、PC、GitHub、Library は変更していません。
bridge launcher から起動する検証用の経路です。通常分業を一人追跡へ置き換えません。

## v16 で加えたもの

- `bridge/route_connection_session.gd`
  - 副作用のない `vertical_slice_brief()`。容量停止、全路閉鎖、停め直し、帰還、帰還確定可、枯渇、
    主路閉鎖の迂回、整備、中継停車、通常回収を優先順で説明します。
  - 副作用のない `resource_ledger_by_item()`。項目ごとに `initial / ground / carried /
    relay / depot / accounted / conservation_ok` を返します。予約中の資源は地面扱いです。
- `bridge/route_connection_adapter.gd`
  - 縦切り HUD に地面・中継・手持ち・車内、容量停止理由、次の判断を表示します。
  - 主路ボタンは `主路: 開放` / `主路: 閉鎖→迂回`、全路閉鎖は安全待機として区別します。
  - 中継→入口の停め直しは `入口へ回収中` と表示し、全路閉鎖時は帰還も経路再開後と表示します。
    `ready_to_exit` では回収中と混同せず `帰還確定可` を表示します。
  - 入口→中継の片道目安 `24→14秒` と、既存背負いフレーム候補 `3→5`
    （木2・皮1・鉄1）を候補情報として示します。材料がC採石場だけで揃うとは主張しません。
- `tools/test_canyon_one_site_playable_loop_v16.gd`
  - 同じ session 内で、迂回、満載保持、容量回復後の再採取、整備→中継停車、
    一度だけの帰還確定を検査します。
- `tools/test_route_connection_suite_v16.py` と `tools/run_checks.py`
  - 新規 witness と既存の駐車/HUD/背負いフレーム診断を route-connection suite に登録します。
  - C採石場 fixture に不適切な `legacy-world-test` を与えない限定例外を追加します。
  - runner は実行前にその登録と例外を自己検証するため、将来の編集で v16 witness を黙って外しません。

## 実行した Linux 証跡

Godot 4.6.3 headless、専用 `/tmp` XDG test namespace で、次の v16 acceptance は exit 0 でした。

```text
godot4 --headless --path . -s res://tools/test_canyon_one_site_playable_loop_v16.gd
== 結果: すべて成功 ==
```

この witness は次を個別に確認します。

1. 入口では中継整備と `24→14秒` の効果を正本 profile から読む。
2. 主路閉鎖で実 actor が `bypass` を使い、収納と項目別保存則を維持する。
3. 満載時は新規採取を止め、入りきらない貨物を保持する。
4. 容量を回復して refresh した後、保持貨物の荷下ろしだけでなく新しい採取→収納を再開する。
5. 整備→全員帰還→中継停車は地面資源を残し、片道14秒を有効にする。
6. 帰還確定は本編倉庫へ一度だけ書込み、二重 commit を拒否する。
7. brief/項目別台帳の読出しは session、倉庫、検証保存の有効状態を変更しない。

基準 `1348700` に v16 cumulative overlay を重ねた清潔なコピーで、まず
`godot4 --headless --editor --import` を実行して global-class cache を作成した後、次が exit 0 でした。

- `test_canyon_one_site_playable_loop_v16.gd`
- `test_canyon_parking_vertical_slice.gd`
- `test_canyon_parking_vertical_ui.gd`
- `test_canyon_recovery_hub.gd`
- `test_normal_haul_frame_progression.gd`
- `test_a_recovery_bridge.gd`
- `test_normal_crew_motion_v12.gd`
- `test_canyon_parking_vertical_v9_capture_result.gd`（v9先行映像の整合のみ）
- `test_route_connection_suite_v16.py`

同じ清潔なコピーで `tools/run_checks.py --suite route_connection` も実行し、`import` と
`a_recovery_bridge`、`a_recovery_outpost`、`canyon_recovery_hub`、
`canyon_one_site_playable_loop_v16`、`canyon_parking_vertical_slice`、
`canyon_parking_vertical_ui`、`normal_haul_frame_progression` の8 records はすべて pass でした。
ただし supplied archive には `.git` が無く、runner の archive-integrity gate が `git rev-parse`
exit 128 で report 全体を FAILED とします。これはゲーム不合格を pass と読み替えないための環境上の制約です。

## 視覚・入力の限界

この cloud 環境は `DISPLAY`、Xvfb、xvfb-run を持たないため、v16 の実 viewport screenshot / video と
物理マウス操作を新規に取得できませんでした。headless test を viewport 証跡として偽装していません。

復元直後に script を直接起動すると Godot の global-class cache がまだ無く parse error になるため、
上記の通り正規 `--editor --import` を先に実行しています。これは package に cache を同梱する理由にはせず、
PCでも通常の Godot import を先に行う前提です。

同梱済みの `prototypes/recovery_map_lab/evidence/canyon_parking_vertical_slice_v9/` の PNG/MP4 は
**v9 の先行 visual evidence** であり、v16 の HUD 文言や今回の ledger を示すものではありません。

Windows/Godot 4.7.2、物理マウス、音声、性能、最終アート可読性（10–13px の縦切り HUD）は未検証です。

## PC での受入手順

1. 基準 archive `recovery-route-bridge-1348700.zip` に、v16 cumulative overlay を一度だけ重ねる。
   v10〜v15 を個別に重ねない。
2. package root の `SHA256SUMS.txt` を照合する。
3. Godot 4.7.2 で `project/scenes/recovery_route_bridge_launcher.tscn` を開き、
   **中継停車 縦切りでA→C（検証）** を選ぶ。
4. 実マウスで順に、主路閉鎖→迂回表示、全路閉鎖→安全待機→再開、整備→停め直し、
   容量更新→保持貨物荷下ろし→再開、帰還を確認する。
5. 物理操作、Windows挙動、音声、描画密度の結果をこの cloud headless 証跡とは別に記録する。

## 意図的に残した範囲外

- 本編 `main.tscn` への統合、通常保存、実車両の自由走行、方向別車体アニメ。
- 新規敵、ランダム故障、燃料漏れ、耐久、通貨、集積所詳細、大規模戦闘。
- 鉱床枯渇後の別鉱床への自動移動。指定鉱床は残貨物を運んで待機します。
- 物理マウス、Windows 4.7.2、音声、性能、v16 viewport capture の cloud 合格宣言。
