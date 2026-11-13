# 単独追跡 v4 — 連続実ランタイム録画の検証記録

## 証跡の範囲

これは `single_worker_demo` の1人だけを追う**検証モード**である。
通常分業、マップ、成長、保存先、資源/積載/収納の正本は変更しない。録画コードは
既存 adapter の `session.tick()` を呼ばず、actor/cargo/depotを代入せず、画面と
same-session read-only snapshotを取得した。

v2は状態別静止pose、v3/v6は選別した静止PNGである。本書のv4だけが、実viewportの
連続MP4である。レビュー用PNGは後からMP4の指定frameを無加工で復号した確認用であり、
MP4を作る入力ではない。

## 正本と完全性

| 対象 | path | SHA-256 |
| --- | --- | --- |
| 連続MP4 | `prototypes/recovery_map_lab/evidence/canyon_single_worker_continuous_v4/canyon_single_worker_continuous_v4.mp4` | `842f935f464cc1fdd5e113a78c5421c341f9d31cf3f336048e33e43ea0015413` |
| 同session観測JSON | `prototypes/recovery_map_lab/results/route_connection_runtime/canyon_single_worker_continuous_v4.json` | `396471791d5fae93cbe220b711aef508cb56f7b1a674779551147fddcfb4d6df` |

`ffprobe -count_frames` の結果は H.264 / 1280×720 / `10/1` fps / 130 decoded frames /
13.000 seconds。packetは `0.000000` から `12.900000` まで0.100秒間隔で、音声streamはない。
`framemd5` で130 decoded image hashesが130種類であることも確認した。これは各画面が
ffmpegの補間・複製で作られたものではないことの補助証跡であり、収録方式はlive X11
viewport入力のみである。

JSONは134 sample、平均99.6691729ms（10.0331925Hz）、最大146ms。contractは
`ok=true`、`errors=[]`、`bridge_phase=3`、`state_phase=5`。一周のstorage eventは
frame 98 / session 9.8952567秒に `depot 0→3`、`carried=0`、`conservation_ok=true`。
`source_remaining 39→36` と一致する。

v4収録後に、capture sourceへ `validate_video_window()` と `validate_video_probe()` を追加した。
前者はcycleが動画時間外なら拒否し、後者はffprobeの実decoded frame数・duration・10fps・
1280×720・H.264/video-only streamを満たさないmovieを拒否する将来run保護である。focused
Godot testは未改変v4 JSONを13,000ms windowへ入力してpassし、同じfixtureの再出発を650msへ
ずらした場合は600ms movie windowからrejectする。実v4 MP4も同じffprobe contractをpassする。
v4 JSON自身に後付けでcontract結果を書き込んだわけではない。

## 連続動画内の確認点

| MP4 frame (0-origin) | 状態JSONの対応時刻 | 観察対象 |
| --- | --- | --- |
| 0 | 0.058s | 拠点から出発、手荷物0、depot0 |
| 27 | 2.713s | 橋入口へのアプローチ |
| 31 | 3.103s | 橋中央デッキ、`bridge_deck=true` |
| 38 | 3.809s | 橋出口、資源側へ進行 |
| 44 | 4.331s | 採掘中、足元 `[250,235]`固定、tool frameが進む |
| 50 | 5.023s | `carry_n=3`で荷物を持ち復路へ |
| 94 | 9.315s | 搬入口で荷下ろし待ち、`carry_n=3` |
| 97 | 9.735s | `carry_n=0`、HUD depot=3、次の出発 |

`review_frames/frame_*.png` は上記のMP4 frame indexをそのまま復号した1280×720 PNGである。
動画全体で、同じworkerの橋入口→デッキ→出口、採掘停止、荷物ありの復路、荷下ろし後の
消失とHUD増加、再出発を確認した。座標からpresentation誤差はすべて0.01px以下、unit scale、
visual jumpなしである。

## 録画設定と誤記

Godot 4.6.3のLinux X11 dummy `:99`、llvmpipe上で、`ffmpeg x11grab`を10fps/1280×720/
13秒/音声なし/H.264で起動した。AI生成、動画補間、time stretch、フレーム複製、crop、scaleは
使用していない。X11のMIT-SHM初期取得はこのdummy環境で非共有メモリcaptureへフォールバック
する警告を出したが、ffmpegはexit 0、上記のMP4を完全に復号できた。

v4 JSONの説明文字列だけが古い「12 fps」のままである。`target_hz:10.0`、`ffprobe`、packet
timing、frame countを実測値として採用し、元JSONは改変しない。この表記は後続capture sourceで
`TARGET_HZ`を展開する文に修正した。

## 限界と不採用の再試行

- v4はLinux実viewportの1周証跡で、Windows/Godot 4.7.2、実機マウス入力、音声は未確認。
- 人物素材は1人用の暫定・差し替え可能素材で、ユーザー候補の全員最終採用ではない。
- 同設定で文字列修正後に行ったv5再試行は、動画自体は10fps/130 framesだったが、独立した
  Godot観測ログが一度191msになったためcapture contractで不合格とした。v4証跡を上書きせず、
  その不合格runは配布対象に含めない。
