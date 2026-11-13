# 単独追跡 v10 — 3周連続実ランタイム証跡と停止時ハンドオフ

## この版の位置付け

`single_worker_demo` の **検証モード**だけを対象にした、Linux の実 Godot
viewport 録画である。通常分業、world/map、資源・手荷物・搬入口・拠点在庫の
正本、通常 `user://` save は変更していない。ユーザーの停止指示を受け、v10
成功証跡の照合と保全で区切った。新しい機能、再録画、再設計は行っていない。

v2 は状態別静止 pose、v3/v6 は選別した静止 PNG、v4 は1周の連続動画である。
**v10 は3周を一つの実 viewport MP4 に収録した版**であり、生成 AI、補間、
フレーム複製、crop、scale、速度変更で作った動画ではない。

## 正本と完全性

| 対象 | project 内 path | SHA-256 |
| --- | --- | --- |
| 実 viewport MP4 | `prototypes/recovery_map_lab/evidence/canyon_single_worker_continuous_v10/canyon_single_worker_continuous_v10.mp4` | `9df645c0724a56e8db59bdab54f17cd6816bff55faacae4f99ce44d41ae71260` |
| 同session観測 JSON | `prototypes/recovery_map_lab/results/route_connection_runtime/canyon_single_worker_continuous_v10.json` | `134f9939e4488dd5b44739dc2e5d568549c3af04a2a52ec26c00e76953c9a091` |

直接の `ffprobe` は H.264 video-only / 1280×720 / 10fps / 360 decoded frames /
36.000秒 / 2,662,552 bytes を返した。独立に MP4 を decode した 360 個の
`framemd5` は JSON 保存順列と一致し、360 frame はすべて異なり、連続同一 frame
の最長は1、PTS は0.100秒間隔だった。音声 stream はない。

録画は Linux Godot 4.6.3 / X11 dummy display / llvmpipe で、ready になった
1280×720 viewport を `ffmpeg x11grab` が直接 10fps で収録した。収録前の
静止 pre-roll は実測214ms、記録者の session-before/after assertion は不変。
これは保存済み JSON の assertion であり、後から独立に再計算できる snapshot
は残していない。

## 映像と状態の照合

通常 HUD は動画全編で表示される。read-only 映像レビューでは、カット／パン、
橋上の明白な投影ワープ、旧版の前景岩を横切る橋渡りは見つからなかった。黄色
helmet・青服の同一 worker と、積載時の青い鉱石を3周とも追える。全景では採掘
道具の振りは小さく、拡大すると姿勢／腕の変化として読める程度である。

| 周回 | 往路橋 | 採取/積載 | 復路橋 | 荷下ろしと HUD |
| --- | --- | --- | --- | --- |
| 1 | f028–040 / 2.7–3.9秒 | f045–052 / 4.4–5.1秒、f053 で積載 | f057–069 / 5.6–6.8秒 | f099 / 9.8秒は積載・拠点0、f100 / 9.9秒は非積載・拠点3 |
| 2 | f128–140 / 12.7–13.9秒 | 積載復路へ | f155–167 / 15.4–16.6秒 | f197 / 19.6秒は積載・拠点3、f198 / 19.7秒は非積載・拠点6 |
| 3 | f226–238 / 22.5–23.7秒 | 積載復路へ | f253–265 / 25.2–26.4秒 | f295 / 29.4秒は積載・拠点6、f296 / 29.5秒は非積載・拠点9 |

JSON の1秒安全余白内で確定した収納は、frame 99 / 10.025秒の `0→3`、frame 197 /
19.835秒の `3→6`、frame 296 / 29.733秒の `6→9` のちょうど3回である。4回目は
frame 394 / 39.548秒で動画外なので、この動画の証拠として数えない。394 全 sample
で `source + carried + depot = 39`、`conservation_ok=true`、source 増加も depot
減少もなく、HUD の resource/depot 文字列は状態値と一致した。

strict calibrated bridge witness は各周について、空荷の近側→床板→遠側、積載後の
遠側→床板→近側を記録した。contract は `ok=true`、`bridge_phase=3`、
`return_bridge_phase=3`、`state_phase=5`、平均 99.977ms / 10.002fps、最大145ms、
errorなしで通過している。

収納直後に session/HUD が `to_resource` / 歩行へ戻る一方、1・2周目だけ sprite
metadata が1 sample（約100ms）`idle_west_0` のままになる。これは dock で state が
切り替わり、次 tick から座標が動くための停止 frame で、frame 凍結や保存則の不一致
ではない。3周目は直ちに walk へ遷移した。

## 回帰結果

- fresh focused test: Linux Godot 4.6.3 で
  `godot4 --headless --path . --fixed-fps 60 -s res://tools/test_canyon_recovery_hub.gd`
  を専用 XDG scratch directory で実行し、`== 結果: すべて成功 ==` / exit 0。
  この `--fixed-fps 60` は決定的な**テスト専用**で、v10 の実録画起動には使っていない。
- import、`canyon_recovery_hub`、`a_recovery_bridge`、`a_recovery_outpost` は各 exit 0。
  `tools/run_checks.py` の総合 exit 1 は配布元 ZIP に `.git` がなく、environment metadata
  verification だけが失敗するためで、Godot診断の失敗ではない。
- focused test は、3周保存則、保存読込、全路閉鎖→安全停止→再開、撤退、容量満杯拒否、
  通常分業 isolation を対象にする。OSレベルの実マウスクリックは未実施であり、
  Button signal のプログラム試験と区別する。

## 保全した不採用 run

v8/v9 は成功証跡に混ぜず、ローカルにそのまま残した。

| run | MP4 SHA-256 | JSON SHA-256 | 不採用理由 |
| --- | --- | --- | --- |
| v8 | `9b0bc2121ad5b7fca2a9054c45a68ed7d36fb8489846b742f32eb7810f551628` | `c3eba15e6152c071c390a18373f6dff600e881eeefc696bced7653f6a473f71e` | service-apron sample を橋入口と誤分類し strict contract が reject |
| v9 | `f9dccb96aefe0c4c33ffffe8a1476ebea67206b78712c7c6f46590e05e24224e` | `f91a95d4d604ac6ea5e966b7fc4b0c716fac2a505cefac14643b65579c8a8170` | 録画を誤って `--fixed-fps 60` で起動し、session が動画時間に追随せず安全 window 外で reject |

これらの原本は archive には含めず、混同を防ぐ。根拠と再開条件は
`docs/superpowers/ledgers/2026-10-28-canyon-three-cycle-continuous-capture.md`
に残す。

## 再開手順と未確認事項

1. `CLOUD_CHANGESET_MANIFEST_V10.json` と archive root の `SHA256SUMS.txt` を照合して
   baseline `1348700c775822108df91ed48a21ea73bbd9792a` への overlay として展開する。
   ZIP は `.git` を復元しない。
2. project root で focused test、続けて selected Godot checks を再実行する。新しい
   capture が必要なら v10 を上書きせず、固有の v11 identity を使う。
3. Windows / Godot 4.7.2 で起動、実マウス、音声、性能、1280 native の見え方を確認する。
4. 人物は v3 の1人用・差し替え可能な暫定素材であり、ユーザー共有の候補を全員の
   最終採用にしたものではない。最終人物 art、全方向 animation、全景での採掘道具の
   強い可読性は未完である。

PC、GitHub、main、公開先、通常 save には触れていない。
