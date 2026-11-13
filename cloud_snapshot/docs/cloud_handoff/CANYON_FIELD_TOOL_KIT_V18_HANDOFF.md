# C採石場・同一仲間の携行採掘具切替 v18 handoff

## 範囲と仮仕様

これは 1348700 基準へ直接重ねる C採石場・中継停車縦切り用の cumulative overlay です。保護済み v17 を含み、通常3人分業、有限資源、`地面 → 手持ち → 中継 → 車内 → 帰還確定` の正本を置き換えません。本編 `main.tscn`、通常 `user://`、PC、GitHub、Library は変更していません。

v18 は **同じ採掘役の装備中採掘具と携行中採掘具の切替** を追加します。v17 の護衛→採掘役への背負いフレーム引渡しとは別の機能です。

- 出発時、採掘役が `HAMMER` を装備し基地在庫に実在 `PICKAXE` がある場合だけ、`PICKAXE` 1本を session-owned の1枠 kit へ移す。遠隔生成はしない。
- 採掘役が空荷で、中継に到着し、資源予約・撤退・停め直し・容量停止が無い時だけ、`HAMMER ↔ PICKAXE` を予約して切替える。完了後も同じ安全境界で逆切替できる。別 actor、別 slot、重複品、`HANDCART` は拒否する。
- 現地中は actor snapshot だけが変わる。本編 Worker と BaseStorage は帰還確定時にだけ原子的に更新され、携行側に残る旧工具を倉庫へ返す。未確定 session を安全に破棄した場合は、出発時に stage した immutable `PICKAXE` だけを戻す。
- `HANDCART` は重い基地専用品で、現地 kit に入らない。HUD の `拠点:手押し車` は既存の帰還後交換予約を示す。
- 工具切替後の採掘時間は、既存 `GatherDB` の `vein` 評価比を bounded な相対補正として次回作業にだけ適用する。採取単位、有限量、carry limit、副産物は変えない。

対象工具、1枠、相対補正は変更可能な仮設定です。全仲間の一般 inventory、重量モデル刷新、手押し車の現地携行、武器・敵・救助・新設備、横視点の現地UIは非目標です。

## 主な変更

- `bridge/route_connection_session.gd`
  - schema 6（v2〜v6 を読込可能）。actor に `field_tool_kit`、immutable `entry_field_tool_kit`、採掘 rank/ability、予約レコードを保持する。
  - stage、同一 actor の安全境界交換・逆交換、取消、改竄拒否、commit、破棄cleanup を session authority に集約する。
  - Worker の現地中の直接変更を拒み、commit 後だけ tool/storage を更新する。
- `bridge/route_connection_adapter.gd`
  - 縦切り HUD に小型 `現地:採掘具` control と `装備 / 携行` 状態を追加する。予約中、交換済、戻し済を区別する。
  - `拠点:手押し車` として base-only の意味を明示する。通常HUDや Crew Detail を field inventory にしない。
- `bridge/route_connection_harness.gd`
  - stage 済み kit を別プロセス fixture へ混ぜないため、予約 kit を持つ cross-process resume を拒否する。
- `tools/test_canyon_field_tool_kit_v18.gd`、`tools/test_route_connection_suite_v18.py`、`tools/test_canyon_parking_vertical_ui.gd`、`tools/run_checks.py`
  - 所有権、改竄、予約/取消、逆切替、GatherDB 相対効果、commit、SaveGame capture/apply、撤退cleanup、HUD signal wiring、route-suite 登録を検査する。
- `tools/capture_canyon_field_tool_kit_v18.gd` と `prototypes/recovery_map_lab/evidence/canyon_field_tool_kit_v18_final/`
  - 実 X11/Godot viewport の予約・交換済 HUD PNG と、64秒・10fpsの無加工 MP4 を保存する。

## 実施済み cloud 検証

Godot 4.6.3 の隔離 XDG namespace で以下を実行した。`test_canyon_field_tool_kit_v18.gd` は、実在 Pickaxe の stage、同一採掘役だけの切替/逆切替、改竄拒否、相対採掘時間、commit、SaveGame capture/apply、撤退cleanup の回帰を通す。

```text
godot4 --headless --path . -s res://tools/test_canyon_field_tool_kit_v18.gd
godot4 --headless --path . -s res://tools/test_canyon_parking_vertical_ui.gd
godot4 --headless --path . -s res://tools/test_canyon_equipment_switch_v17.gd
godot4 --headless --path . -s res://tools/test_canyon_one_site_playable_loop_v16.gd
godot4 --headless --path . -s res://tools/test_normal_haul_frame_progression.gd
godot4 --headless --path . -s res://tools/test_canyon_recovery_hub.gd
python3 tools/test_route_connection_suite_v16.py
python3 tools/test_route_connection_suite_v17.py
python3 tools/test_route_connection_suite_v18.py
```

実証キャプチャは Linux/X11 の 1280×720 viewport、programmatic production button signal によるものです。`capture_result.json` は保存則成功、64.0秒/640 frame/10fps、無加工を記録します。物理マウスではありません。人物 sprite は工具ごとの見た目をまだ描き分けず、工具の証跡は HUD と session JSON です。

`tools/run_checks.py --suite route_connection` は supplied archive に `.git` が無いため、個別 Godot diagnostics が通っても environment metadata gate を failed にする場合があります。これはゲーム本体の合格や Windows 合格に読み替えません。

## PC 受入

1. 基準 `recovery-route-bridge-1348700.zip` の SHA-256
   `72dd15252606eeae67e8b55c8a4cbaf8bcc2fc9c72c366771b91457f5350c79d` を確認して展開する。
2. v10〜v17 を重ねず、今回の **v18 cumulative overlay だけ**を基準 root に重ねる。
3. root の `VERIFY_HANDOFF_HASHES.ps1` を実行するか `SHA256SUMS.txt` を照合し、Godot 4.7.2 で通常 import する。
4. launcher の **中継停車 縦切りでA→C（検証）**を実マウスで起動し、携行 tool 予約→安全境界交換→逆交換→帰還確定、予約取消、撤退、停め直し、満杯、保存読込、通常3人分業を確認する。

## 未確認・未完

- Windows/Godot 4.7.2、物理マウス、音声、性能、最終アート/HUD の読みやすさ。
- 工具を持った sprite の専用見た目、複数工具/複数予備枠、一般 inventory UI。
- 6部屋車体コンセプトの実装、車両自由走行、全方向の車体/人物アニメ、敵/戦闘。
- Library は既知の 401 を回避・再試行していない。成果はこの cloud workspace にのみ保全する。
