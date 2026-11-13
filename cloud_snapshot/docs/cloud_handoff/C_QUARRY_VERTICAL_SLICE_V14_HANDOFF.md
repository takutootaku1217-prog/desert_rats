# C採石場・中継停車縦切り v14 — PC引継ぎ

作成日: 2026-10-28。これはクラウド隔離コピーで組んだ、既存ゲームへの
累積 overlay です。GitHub、main、個人セーブ、PC は変更していません。

## 復元順

1. `recovery-route-bridge-1348700.zip` を検証して展開する。
   - 基準 commit: `1348700c775822108df91ed48a21ea73bbd9792a`
   - 基準 SHA-256:
     `72dd15252606eeae67e8b55c8a4cbaf8bcc2fc9c72c366771b91457f5350c79d`
2. `canyon_recovery_hub_pc_cumulative_v14_vertical_slice_20261028.zip` を
   同じ root へ展開する。これは v13 累積、v13 受入差分、今回の縦切りを
   合成した一つの overlay で、先行する小差分を個別に重ねる必要はない。
3. `SHA256SUMS.txt` と package の SHA-256 を検証し、Windows の Godot 4.7.2
   で `project/` を開いてローカル `.godot/` cache を作る。

## 起動と操作

`res://scenes/recovery_route_bridge_launcher.tscn` を実行し、右上の
**中継停車 縦切りでA→C（検証）** を押す。現地で **整備** を完了してから
**中継停車** を選ぶ。通常分業と単独追跡の入口は別のままである。

今回の操作・保存則は、入口24秒／中継14秒、運搬中貨物の回収、満載時の
保持、容量回復後の一度だけの収納、撤退優先、停車取消、経路閉鎖／再開、
project-local 検証保存／読込を対象にする。

## 実証跡

- `project/prototypes/recovery_map_lab/evidence/canyon_parking_vertical_slice_v4/`
- `project/prototypes/recovery_map_lab/results/route_connection_runtime/canyon_parking_vertical_slice_capture_v4.json`

v4 は実X11 1280×720、64.0秒、10fps、640 decoded frames。ボタン入力は
cloud に物理クリック注入器がないため `Button.pressed` による本番 callback
経路であり、Windows の物理マウス入力の合格証拠ではない。

## 最初のPC検証

1. 実マウスで縦切り開始、整備、中継停車、停車取消、撤退を押す。
2. 満載保持、容量更新、経路閉鎖／再開、検証保存→状態変更→検証読込を
   繰り返し、資源・手荷物・車内在庫が二重計上されないことを確認する。
3. Windows/Godot 4.7.2 の import、音声、性能、表示、実入力を別途確認する。

## 未完成の範囲

- クォータービューの中継停車は仮マーカー/HUDで、既存車体を移動させない。
  車両の方向別2D走行アニメや最終素材は未実装。
- Linux Godot 4.6.3 の結果は Windows 合格ではない。
- この成果物は cloud-local に保全したのみで、Library書込みは既知の401を
  回避せず未転送である。
