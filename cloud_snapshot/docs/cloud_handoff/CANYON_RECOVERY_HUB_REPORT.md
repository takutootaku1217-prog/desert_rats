# 峡谷の回収拠点 v2 — クラウド実装報告

## 範囲・起動

- 復元基準: `codex/recovery-map-scale-lab` / `1348700c775822108df91ed48a21ea73bbd9792a`。復元 ZIP は `.git` を含まないため、ここで履歴は作成していない。
- 対象 scene: `res://scenes/recovery_route_bridge_launcher.tscn`。通常の横視点 `main.tscn` と `RecoveryRouteConnectionSession` / `WorldTrip` / `BaseStorage` は正本のまま。
- 起動: project root で `run_recovery_route_bridge.bat`、または Godot で上記 scene を F6。A→B→C 到着後に固定 2D クォータービューの C 古い採石場へ入る。
- 操作は `撤退`、`迂回`、`全路`、`搬入口`、検証保存/読込、`帰還→横視点` を残した。上部タイトル帯・紹介ラベル・下部サムネイルは参考画像から実装していない。

## v2 の実装内容

- 左奥に青鉱石採掘場、中央左に実 session の `BYPASS→RESOURCE` 線へ一致する斜め橋、右手前に大型移動拠点と荷下ろし場、右奥に旧検問所を置いた。
- `CanyonCrewViews` が既存 session の actor を読むだけで、旧横向き Worker をこの fixed adapter の間だけ `visible=false` にして、人間クォータービュー代理 Sprite を足元基準で描く。退出時には親・位置・process mode・元の visibility を復元する。
- 状態は `idle` / `walk` / `harvest` / `carry` の独立 PNG に対応する。文字札は運搬中を優先し、なければ採取中の一人だけに絞った。個々の Sprite はまだ方向別フレームアニメではなく、状態別の静止ポーズである。
- 砂地は 16px の固定微細チップ・亀裂・小石で連続させ、主運搬路と橋の接続帯だけを描いた。実運搬路から離れて偽の分岐に見えた砂轍モジュール5枚は外し、崖は透明モジュールと局所的な谷影を使って旧大面積単色ウェッジを除去した。
- 主運搬路は session の既存screen-space線だけを中心に、72px/54pxの低コントラスト砂帯、反復8px rut dash、2px edge speckで仕上げた。橋の両アプローチも同じ規則で接続する。新しい装飾路・collision・人物・施設座標は追加していない。
- 橋は `route_bridge.png` を 0度・scale 1 で置き、入口・中間・上側出口を実 actor が通る `BYPASS→RESOURCE` に揃えた。表示側の `Occupancy` deck は同じ線上を通行可能にし、谷底だけを占有として残した。route/session の経路計算自体は変更していない。
- 操作 HUD は `266×108`、右下の cargo/repair yard は中心 `(1080,570)` へ移し、右端を切らない。v1 で黒い四角になった既存小物は、背景色 `#252C37` を alpha 化した v2 透過コピーへ差し替えた。

## 素材契約

| 区分 | 生成元→ゲーム内 PNG | 表示・契約 |
| --- | --- | --- |
| v2 crew | 1983×793 透明 sheet を pose ごとに crop → `crew_idle/walk/carry` 56×52、`crew_harvest` 64×56 | 人物実体はおよそ 32–40px。scale 1、Nearest、各 Sprite の下端を live actor の足元に合わせる。 |
| v2 sand（未採用） | 1774×887 → `sand_rut_module.png` 320×160 | 透明・scale 1・Nearestで試作したが、5枚とも実運搬路から外れて偽分岐に見えたため scene/配布差分から外した。 |
| v2 cliff | 1774×887 → `cliff_module.png` 360×180 | 透明・scale 1・Nearest。奥の採掘場/運搬路/検問所の岩壁。 |
| v2 route bridge | 1536×1024 → trim 1522×1007 → `route_bridge.png` 320×216 | 上左→下右向きで生成した素材を回転・反転せず `(415,385)` に等倍配置。接地点は session bypass→resource 線。 |
| v2 props | 既存 48×48 小物 → `v2/props/*.png` 48×48 | 不透明な `#252C37` 背景を透過化。alpha min 0 / max 1 を確認。 |
| v1 高密度部品を再利用 | quarry / mobile base rear+front / checkpoint / cargo yard | 独立透明 PNG、Nearest、scale 1。cargo yard は `(1080,570)`。 |

`assets/canyon_recovery/v2/diagonal_bridge.png` は試作であり scene から未参照、配布差分には含めない。ユーザー共有の後発候補（4方向待機/歩行、地形モジュール案、1方向4コマ）は大原画かつセル/足元契約が未確定のため、今回の v2 に勝手に採用していない。`CanyonCrewViews` の state-to-texture 契約は、最終選定素材へ差し替え可能である。

## 実 Godot 収録と確認

Linux Xorg dummy `:99` / Godot `4.6.3` / GL Compatibility (llvmpipe) で、headless ではない X11 viewport を実行して保存した。これは概念画像ではない。Windows / Godot 4.7.2 合格ではない。

証跡の正本は Godot が直接書き出した下記の個別 PNG と JSON である。`canyon_hud_runtime.png` と `canyon_hud_interaction_runtime.png` は通常プレイと同じ `RouteControls` 表示を残した操作UI証跡で、他の art-only PNG だけはカードを隠して地形確認用に分けた。合成 GIF やモンタージュは正本・配布差分に含めない。

- `prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_departure_runtime.png`
- `prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_harvest_runtime.png`
- `prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_carry_runtime.png`
- `prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_cargo_runtime.png`
- `prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_hud_runtime.png`
- `prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_hud_interaction_runtime.png`
- `prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_bridge_walk_01.png` … `_04.png`
- `prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_resolution_640x360_x2.png`
- `prototypes/recovery_map_lab/results/route_connection_runtime/canyon_hub_render_capture.json`

最終 JSON は同じ `worker:0` が entry → middle → upper deck → exit を通ったことを記録する。4点は全て `bridge_deck=true`、`walkable=true`、`state=to_resource`。HUD操作はX11で実描画した画面上の `Button.pressed` シグナルをプログラム試験で発火し、`迂回` toggle、`検証保存`、`検証読込`、`撤退` がすべて成功した。インストール済みかつサポートされたOSレベルのX11クリック注入器はこの環境に無いため、物理クリック成功とは主張しない。保存先は project-local fixture であり、通常 `user://` save は使用していない。

1280 native と `640×360→Nearest×2` の比較は、同じ native cargo frame を Godot `Image.resize(..., INTERPOLATE_NEAREST)` で一度縮小してから戻した**後処理比較**である。人物の細部・施設の細密クラスタ・小型操作文字が粗くなるため、1280×720 等倍を採用した。640 logical window の別実行でも、Windows 実機比較でもない。

## 回帰・操作検証

最終実行コマンド:

```text
python3 tools/run_checks.py --godot godot4 --check canyon_recovery_hub --check a_recovery_bridge --check a_recovery_outpost --output-dir /tmp/canyon_v2_final_verification_20261027
```

`import`、`canyon_recovery_hub`、`a_recovery_bridge`、`a_recovery_outpost` はすべて exit 0。runner の総合 status だけは復元 ZIP に `.git` が存在しないため environment verification として failed 表記になるが、Godot 診断の失敗ではない。

- `canyon_recovery_hub`: 透過小物、CrewView 数/状態、HUD bounds、`迂回` / `撤退` / `検証保存` / `検証読込` のButton callback、yard containment、bridge asset/occupancy、橋上 entry→exit の同一 worker 連続歩行、Worker 退出復元、採取→運搬→収納→一回だけ確定を確認。
- `a_recovery_bridge` / `a_recovery_outpost`: route closure、保存/復元、積載・容量拒否、負傷/HP0、撤退、収納二重計上防止、C→B→A 帰還を確認。

## 残る差異・明日の確認

- 参照より地形の描き込み密度と道沿いの小物数は少ない。地形は v1 より連続性を改善したが、最終アートの置換余地がある。
- 人物は暫定 v2 state pose で、walk は静止 `crew_walk` pose への切替のみ（frames/bob を持つ歩行アニメではない）。各poseの下端は live actor の足元へ固定した。後発の方向別/歩行原画は未採用で、最終採用時は 64px cell、足元 line、32–40px人物、透明、各方向/状態の契約を満たすよう切り出し・検証が必要。
- Windows / Godot 4.7.2、実機のマウス操作、音声は未確認。Linux/X11 の成功をそれらの合格とは扱わない。

## 配布物

- 検証 ZIP: `canyon_recovery_hub_cloud_delta_v2_20261027.zip`。アーカイブ内の対象ファイルは同梱 `SHA256SUMS.txt` で検証する（アーカイブ自身の SHA-256 は配布時に別途返す）。
- ユーザー提出済みの前版はローカルに `canyon_recovery_hub_cloud_delta_v2_20261027_pre_road_finish_841459a7.zip` として保全した（SHA-256 `841459a78022e1c9377d9c78bd885873f476ed02317d93a97e094bdc49e66be4`）。今回の道路仕上げ版と混同しない。
- 既存成果を更新した Library ID: `libfile_088b34694d08819197e7d0c0c97a37b6`。新規の第三者共有はしていない。
- 今回の連続証跡更新版は `canyon_recovery_hub_cloud_delta_v4_continuous_capture_20261028.zip` としてv3を保全したまま更新する。アーカイブ自身のSHA-256は配布時に返し、同梱 `SHA256SUMS.txt` はプロジェクト内容を検証する。

## v3 単独追跡検証 — 1人の可視作業ループ

### 範囲と通常仕様の保護

- これは `単独追跡でA→C（検証）` という明示的な**検証モード**であり、通常の `通常分業でA→C 古い採石場へ移動`、世界マップ、成長仕様、通常の役割割当を置換しない。
- `single_worker_demo` が真のときだけ `worker:0` を直接採掘→既存搬入口→既存拠点収納の1人担当にし、他の班員は session 上 `idle` のまま表示から隠す。通常 mode は `direct_depot_loop=false`、非隠しの従来分業のままである。
- 資源、手荷物、搬入口列、拠点在庫の正本は引き続き `RecoveryRouteConnectionSession` と既存 dock 更新だけである。CrewView、活動札、service apron は表示専用で、在庫を直接増減しない。
- 検証 mode は橋を通る経路を固定しており、HUD の迂回ボタンは `迂回: 固定` と無効表示になる。通常 mode の迂回トグルは変更しない。

### 可視化と素材

- 追跡員だけに、足元固定の4方向歩行、採掘道具、運搬箱、荷下ろしの個別 PNG frame を再生する。停止中の採掘では足元を動かさず道具だけを進め、`carry_n` がある間だけ荷物を描く。基地への直搬送表示は車体下を横切らない地上の service apron に投影するが、session の経路・collision は変更しない。
- `assets/canyon_recovery/v3/` の36 PNG はこの1人用の暫定・差し替え可能素材で、ユーザー共有の作業員候補を最終採用したものではない。全班員の最終人物デザイン／完全アニメではない。
- 1280×720 native、Nearest、整数座標を採用した。過去の 640×360→×2 比較は後処理だけで、別 viewport の実行比較ではない。

### 実行証跡（v6）

Linux X11 dummy `:99`、Godot `4.6.3` の実 viewport から、HUD を隠さず Godot 自身が直接保存した PNG と JSON を生成した。生成AI動画・合成動画ではない。証跡は `prototypes/recovery_map_lab/evidence/canyon_single_worker_runtime_v6/` と `prototypes/recovery_map_lab/results/route_connection_runtime/canyon_single_worker_capture_v6.json` に限定し、旧 v2–v5 単独追跡証跡は配布対象から外す。

- 同一 `worker:0` が3周を完了した。cycle 1 は `0→3`（9.906707秒）、cycle 2 は `3→6`（19.818118秒）、cycle 3 は `6→9`（29.632850秒）の拠点在庫で、各時点に `carried=0`、保存則 true。有限資源は `39→30`、拠点は `0→9`、手荷物は最終 `0`。
- 同じ capture の連続 PNG は、NW歩行4 frame、NW採掘3 tool frame、SE運搬4 frame、E荷下ろし3 frame を、単調増加する時刻と順序で JSON に記録する。静止連番なので滑らかさや橋全区間の遮蔽までは立証しない。
- `single_worker_bypass_bridge.png` は `foot_point=[430,399]`、`presentation_deck=true` の中央デッキ静止根拠である。橋全体の完全な見え方の保証ではない。
- capture は明示的な検証 session をプログラム設定した。OSレベルのクリック注入は試しておらず、実マウスクリック成功とは主張しない。通常 `user://` save は触れていない。

### 最新回帰結果と未検証

2026-10-28 の Linux / Godot `4.6.3` で、単独追跡の focused test は3周、保存読込、全路閉鎖→安全待機→再開、帰還、容量満杯拒否、通常分業不変を含めて exit 0。`tools/run_checks.py` の `import`、`canyon_recovery_hub`、`a_recovery_bridge`、`a_recovery_outpost` も各々 exit 0 だった。

runner 全体は supplied restoration archive に `.git` が無いため environment metadata verification を `failed` と表記するが、選択したGodot診断の失敗ではない。Windows / Godot 4.7.2、実機マウス操作、音声、最終人物アートの採用・全方向アニメ、橋全区間の連続可視性は未検証である。

## v4 連続実ランタイム証跡 — v3の静止証跡とは別物

- **v2** の crew は状態別静止 pose、**v3/v6** は暫定 frame を使うが選別した静止 PNG 証跡、**v4** は同じ `single_worker_demo` の実 Godot X11 viewport を連続録画した MP4 である。v2/v3の静止画像を動画化したものでも、生成AIで補間したものでもない。
- 採用した1周の正本は `prototypes/recovery_map_lab/evidence/canyon_single_worker_continuous_v4/canyon_single_worker_continuous_v4.mp4`。X11の1280×720画面を `ffmpeg x11grab` が直接10fpsで13秒録画し、H.264として保存した。`ffprobe -count_frames` は 1280×720、10/1fps、130 decoded frames、13.000秒を返した。130 frame の decoded MD5 はすべて異なる。音声なし、AI生成・補間・複製・crop・scale・速度変更なし。
- JSON正本は `prototypes/recovery_map_lab/results/route_connection_runtime/canyon_single_worker_continuous_v4.json`。同一 `worker:0` の同一session観測134件は平均99.669ms（10.033Hz）、最大146ms、bridge phase 3、state phase 5、保存則 true、契約 errors なし。cycle 1 は `depot 0→3`、`carried=0` で確定し、source は `39→36` となった。
- v4後に追加した `validate_video_window()` / `validate_video_probe()` は、同一の未改変v4 JSONを13,000ms動画windowに通してpassし、動画外へ荷下ろしをずらしたfixture、またはffprobe上で短縮・欠frameのmovieをrejectする。実v4 MP4もffprobe contractをpassするため、将来のcaptureが「動画終了後にだけcycleを完了」または途中終了movieを成功扱いすることを防ぐ。
- 動画の確認用に、MP4を**編集せず正確なframe indexで復号した**8枚を `.../review_frames/` に置いた。0番出発、27番橋アプローチ、31番中央デッキ、38番出口、44番足元固定の採掘、50番荷物ありの復路、94番荷下ろし待ち、97番荷物消失・HUD拠点3で再出発である。連続性の判定はこれらの選別PNGだけでなくMP4全体で行う。
- v4 JSON 内の `capture_method` / `video_note` に残る「12 fps」は、収録前の説明文字列の誤記である。`target_hz: 10.0`、MP4の `ffprobe` 10/1fps、130 frames が実測値であり、JSON本体は改変していない。詳細なhash、コマンド、状態対応、制限は `docs/cloud_handoff/CANYON_SINGLE_WORKER_CONTINUOUS_V4_VERIFICATION.md` を正とする。
- Linux Xorg dummy `:99` / Godot 4.6.3 / llvmpipe に限る。X11 MIT-SHM初期取得は非共有メモリへフォールバックして収録を継続した。Windows/Godot 4.7.2、実機マウス、音声は未確認。後続の同設定v5再試行は観測ログ最大191msで契約不合格とし、v4に上書きも混入もしていない。
