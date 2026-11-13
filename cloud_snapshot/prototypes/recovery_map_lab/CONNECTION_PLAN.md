# A地域 回収ルート接続試作 — 最小接続計画

記録日: 2026-10-27
対象: `codex/recovery-map-scale-lab` worktree 内だけの検証用 bridge

## 読み取った既存の正本と入口

| 対象 | 実在する正本 | bridge が使う入口 |
|---|---|---|
| 仲間・装備・手持ち | `Main.workers` の `Worker`。`weapon`、`work_support`、`tools`、`carrying`、`carry_n` | `worker:<index>` をこの接続 run 内だけの照合キーにし、名前・装備も照合する。新しい本編IDは作らない。 |
| 拠点在庫 | `BaseStorage.inventory` | 現地では直接更新せず、退出時に一回だけ `store_owned()` へ確定する。 |
| 時間 | `Director.elapsed` | 横視点を停止している現地時間を session に保持し、退出時に一回だけ加算する。 |
| A地域・有限資源 | `WorldTrip` / `data/world_map.gd`。入口は `a_start`、対象地は `c_quarry` | A→B→C と C→B→A は既存 `WorldTrip.request()` を使う。`region:c_quarry` の有限 GatherPoint 台帳を元にする。 |
| 通常保存 | `SaveGame` と通常 `user://` | bridge は呼ばない。`res://prototypes/recovery_map_lab/results/route_connection_runtime/` のみを検証状態の置場にする。 |

## 引き渡し境界

1. 横視点で既存 `WorldTrip` により A→B→C へ移動する。
2. C到着時、bridge が既存 `Worker` ノードを一時的に固定クォータービューへ投影する。そこで採取・護衛・中継・ゲート閉鎖時の迂回・搬入口列を session 台帳だけで処理する。横視点側はこの間停止するため、同じ仕事や時間を二重更新しない。
3. 現地の全予約、手持ち、relay、搬入口列が解消されてから、session が有限資源差分・拠点搬入・経過時間を一回だけ正本へ反映する。成功後だけ C→B→A の既存横移動を再開する。

## 権威と重複防止

- **現地中の正本**は `bridge/route_connection_session.gd` の `RecoveryRouteConnectionSession` 一つだけ。資源残量、仲間の役割・位置・手持ち、予約、relay、搬入口待ち、ゲート、進行、経過時間を持つ。
- **前哨地の正本**も同sessionだけである。既存 `sand_stalker` 定義を使う3体のHP・生死・標的・攻撃周期を持つが、本編の `Enemy` ノードは描画投影だけでprocess停止する。これにより本編の敵drop・WorldTrip・Directorが固定画面と二重に更新されない。
- `Worker` の見た目上の手持ちは session の投影であり、現地中に `BaseStorage` へ搬入しない。
- 終了時は `committed` marker と元台帳の残量照合を使う。一度確定済みの session は再確定しない。照合不一致なら安全に拒否し、数量を補充しない。
- HP・疲労・ストレス・手持ちは、既存Workerの処理を停止したままsessionから毎frame投影する。在庫差分と現地時間の正本確定だけは退出時に一度だけ行う。HP30以下の既存低HP撤退は本編へ引継ぐ。`down` / HP0の救助はこの最小範囲では横視点に引渡せないため確定を拒否する。
- 同じMainインスタンスの再入場だけは、確定済み前哨地状態をbridgeのprocess-local記録から復元し、撃破済み3体を再出現させない。通常SaveGame / WorldTrip schemaを増やさないため、アプリ終了後の撃破状態永続化は対象外。戦闘中sessionのcross-process復元はproject-local fixtureが担う。
- lab の `RecoveryMapLab.base_stock` や synthetic actor はこの接続に使用しない。

## 既存説明との関係

lab README の「本編未接続」は以前の完全分離範囲を表す。今回の最新指示は同一 worktree 内だけの接続 adapter を明示的に許可しているため、standalone lab を残したまま bridge mode を追加する。本来の primary worktree、通常 `user://`、既存 `SaveGame.write()` は変更・使用しない。
