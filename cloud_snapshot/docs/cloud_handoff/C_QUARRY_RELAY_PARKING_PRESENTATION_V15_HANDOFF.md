# C採石場・中継停車表示整合 v15 — PC 引継ぎ

作成日: 2026-10-28。これは既存ゲームへの cumulative overlay であり、別ゲーム、
本編 `main`、GitHub、通常セーブの置換ではない。v14 は保全済みの戻り先で、v15.4 は
その上に二つの停車 pose と HUD/route 表示整合を加える。

## 起動

1. 基準 `recovery-route-bridge-1348700.zip` を確認・展開する。
2. v15 cumulative package を同じ root に展開し、`SHA256SUMS.txt` を照合する。
3. Windows / Godot 4.7.2 で `project/` を開き、ローカル `.godot/` を生成する。
   cloud の `.godot/` は含めない。
4. `res://scenes/recovery_route_bridge_launcher.tscn` を実行して、
   **中継停車 縦切りでA→C（検証）** を選ぶ。

## v15.4 の確認対象

- 入口で回収し、**整備**を終える。
- **中継停車**を押す。回収中は入口車体と入口 dock を保持し、貨物と全員の帰還後に
  同向きの既存車体だけが中継 dock `(865,455)` へ切り替わる。
- 中継後は採掘役→relay→運搬役→車体階段の動線と、HUD の手持ち／車内数値を確認する。
  入口 profile は24秒、中継 profile は14秒である。
- 満杯保持→容量更新、停車取消、主経路閉鎖／再開、検証保存→状態変更→検証読込を
  Windows の実入力で確認する。通常 `user://` 保存はこの検証 launcher で使用しない。

## 実証跡

- `project/prototypes/recovery_map_lab/evidence/canyon_parking_vertical_slice_v9/`
  - 1280×720 / 64.000秒 / 639 decoded frames / 639/64fps（約9.984fps）の実 X11 MP4
  - entry / reposition / relay / closed-bypass / first-delivery の HUD PNG
- `project/prototypes/recovery_map_lab/results/route_connection_runtime/canyon_parking_vertical_slice_capture_v9.json`
  - session、visual dock、車体 offset、閉鎖状態、保存則、ffprobe を対応付ける schema 6 結果

クラウドでは物理マウス注入器がないため、録画のボタン操作は同じ production callback
への `Button.pressed` である。Windows の物理入力・音声・性能の合格を意味しない。

## 変更の境界

- 車体前後レイヤー、portable dock crate、通常 crew の**表示投影**だけが
  settled `parking_slot` を読む。session の資源、貨物、collision、保存正本は変えない。
- `CargoYard` は固定環境物のまま。自由運転、3D、回転変形、方向別車体、走行アニメ、
  新資源、役割、保存 schema は追加していない。
- 縦切りで主経路が開いている間は未使用の入口→橋迂回帯を隠し、主経路閉鎖時だけ
  session の実 bypass を描く。relay 後の重なる編成許容帯では、移動役が最も近い
  source centreline を使うため表示が旧 endpoint に張り付いて飛ばない。

## 未検証・未完成

- Linux Godot 4.6.3/X11 の成功は Windows Godot 4.7.2 の合格ではない。
- 車両は同向きの二つの停車 pose で、走行・方向別・最終アニメではない。
- route の高密度美術、最終人物素材、実マウス、音声、性能は PC 工程で確認する。
- closed-bypass PNG は閉鎖時の dock→bypass の幾何を示す。閉鎖状態を維持したまま
  一回の荷下ろしを終える動画証跡は、この仕上げ範囲では未収録である。
- Library 書込みは既知の 401 を回避せず、今回も未転送。成果は cloud-local package
  としてのみ保全する。
