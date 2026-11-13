# C採石場・装備切替 v17 handoff

## 範囲

これは 1348700 基準へ直接重ねる **C採石場・中継停車縦切り専用の cumulative overlay**です。v16.2 は保護された開発前版であり、PC 復元時に別途重ねる対象ではありません。
通常3人分業、有限資源、`地面 → 手持ち → 中継 → 車内 → 帰還確定` の正本を置き換えません。
本編 `main.tscn`、通常 `user://`、PC、GitHub、Library は変更していません。

今回の仮仕様は、将来の装備カテゴリを固定するものではありません。

- 携行済みの **背負いフレーム** は、現地で護衛役から採掘役へ中継引渡しできる。
  session 内だけで所有者と便数を変え、帰還確定まで本編 Worker / 基地在庫を変更しない。
- 基地保管の **手押し車** は現地生成しない。運搬役への交換を予約し、全員と貨物が帰還して
  `commit_to_game()` の既存確定条件を満たした時だけ、基地で原子的に入れ替える。
- 停め直しは両方の未確定装備指示を取消す。通常撤退は手押し車予約を保持するが、帰還中に
  装備を変えたり自動再出発したりしない。満載中は新しい予約を拒否する。

## 変更点

- `bridge/route_connection_session.gd`
  - schema 5。v2〜v4 は空の装備指示として読込互換を保ち、旧 actor に欠ける entry 装備 snapshot を安全に補完する。
  - 現地フレーム引渡しと、帰還手押し車予約を JSON-safe に保存する。
  - 帰還確定前に entry 装備数と session actor 装備数を照合し、合法なフレーム所有者移動だけを
    Main へ反映する。予約済み手押し車はその直後にだけ確定する。
- `scripts/main.gd`
  - `swap_work_support()` は既存補助を返して指定補助を同じ確定点で装備する小さな API。
    `unequip → equip` の中間状態を作らず、在庫と装備の総数を保つ。
- `bridge/route_connection_adapter.gd`
  - 縦切り HUD に `現地:フレーム`、`帰還:手押し車`、`装備取消` の production 操作を追加。
    理由・予約は既存 detail / notice 行へ非モーダルに表示する。
  - 448×218 の HUD を保つため、縦切り時は5列×3行の短いボタン配置を使う。
- `tools/test_canyon_equipment_switch_v17.gd`
  - 実 session tick を通じた現地引渡し、予約・取消・保存復元、停め直し/撤退優先、帰還確定、
    SaveGame snapshot、次回 C session の手押し車便8を確認する。
- `tools/test_canyon_parking_vertical_ui.gd`
  - production button signal が session API を呼ぶこと、予約が非モーダルに表示されること、
    1280×720 内の HUD レイアウトを確認する。これは物理マウス操作の証明ではない。

## Linux headless 証跡

Godot 4.6.3、専用 `/tmp` XDG namespace で以下を実行した。

```text
godot4 --headless --path . -s res://tools/test_canyon_equipment_switch_v17.gd
godot4 --headless --path . -s res://tools/test_canyon_parking_vertical_ui.gd
godot4 --headless --path . -s res://tools/test_canyon_one_site_playable_loop_v16.gd
godot4 --headless --path . -s res://tools/test_normal_haul_frame_progression.gd
python3 tools/test_route_connection_suite_v16.py
python3 tools/test_route_connection_suite_v17.py
```

個別 headless 実行は v17 の現地/基地2経路、v16 の資源保存・満載・停車、既存背負いフレーム進行、
UI signal wiring を確認する。実マウス、Windows、音声、性能、最終アート可読性は確認しない。

`tools/run_checks.py --suite route_connection` は supplied archive に `.git` が無いと、個別 Godot
checks が通っても archive-integrity metadata gate を FAILED にする。その環境制約はゲームの合格に
読み替えない。

### 最終 cloud 検査記録（2026-10-29）

- `tools/run_checks.py --suite route_connection` は import と 8 個の Godot 診断をすべて通した。
  最終 status は supplied archive に `.git` が無いことだけによる `environment_verification` 失敗で、
  `source_changed_during_run` は false だった。この metadata gate は未解消として残す。
- 1348700 基準 ZIP に v17 overlay だけを重ねた新規 `/tmp` 復元で、`SHA256SUMS.txt` の 977 行、
  Godot import、v17 装備切替、縦切り HUD、v16 一地点ループ、v16/v17 route-suite guard を確認した。
- これは Linux / Godot 4.6.3 headless の証跡であり、PC 実機の操作・見た目・音声・性能を代替しない。

## PC 受入

1. 基準 `recovery-route-bridge-1348700.zip`（SHA-256:
   `72dd15252606eeae67e8b55c8a4cbaf8bcc2fc9c72c366771b91457f5350c79d`）を展開する。
2. v16.2 ではなく、今回の **v17 cumulative overlay だけ**を基準 root に重ねる。
   v10〜v16.2 を個別に重ねない。
3. `SHA256SUMS.txt` を照合し、Godot 4.7.2 で `project/` を通常 import する。
4. `project/scenes/recovery_route_bridge_launcher.tscn` を開き、
   **中継停車 縦切りでA→C（検証）**を選ぶ。
5. 実マウスで、現地フレーム→中継引渡し、帰還手押し車予約→撤退→帰還確定、
   予約→停め直し取消、満載保持、容量回復、保存読込を確認する。

## 未完・未確認

- 物理マウス、Windows/Godot 4.7.2、音声、性能、画面上の最終読取りやすさ。
- 採掘道具の現地キット、全装備カテゴリ、救助の全面 UI、敵/戦闘の追加、一般インベントリ刷新。
- 現地車両の自由走行、方向別車体・人物の最終アニメ、最終美術。
- Library は既知の 401 を回避・再試行していない。この成果はクラウド内にのみ保全する。
