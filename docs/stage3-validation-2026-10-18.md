# 第3段階 検証記録 — 2026-10-18

## 対象と判断根拠

- 作業先: `C:\Users\user\Documents\Codex\2026-10-18\task-4`
- ブランチ: `gpt/rescue-return-loop`。`main` は変更しない。
- 開始 HEAD: `860b2f2385519b15706500ce71a22f90e9be9fa8`
- Notion は 2026-10-18 に `docs/Notion参照索引.md` を入口として確認した。採用済みの方向は「成功周回後、維持費を支払っても利益と進行が残る」。正確な価格・解除数値は未決定であり、今回のユーザー承認済み条件を優先した。

旧い 54/66 Cr・5人採用の測定は使わない。隠れた鉱山訪問、都市行動可能になる前の維持費記録、チェックポイント用の状態変更の混在を含んでいたためである。以下はそれらを分離し、同一 seed・通常ワールド・通常初期所持品だけで再測定した記録である。

## 実装

- 新規ゲームの既定人数は **4人**。同条件の5人との三出撃比較で、4人の終了現金が高かったためである。加入機能は追加していない。
- Continue / チェックポイント / v2保存は、保存スナップショットの 3--5 人を先に復元してから適用する。新規4人で古い3人セーブを開いても人数・識別・状態を正しく戻す。同一 run ID でも人数が違うバックアップは拒否する。
- 受領済み補給契約の素材は、通常の自動製作には使わせず、キュー済み製作予約より契約受領を優先する。契約中の同一素材の売却は拒否する。自動使用は有効のまま、標準下限は食料 12、燃料 8、修理キット 6。
- ミッション報酬を受領すると、採石場と通常ワールドの「次回訪問」補充を予約して保存する。現在地で瞬間再生はしない。次の通常地域到着時に、既存の資源・生物レコードだけを一度だけ回復する。受注取消は予約しない。

## 通常設定の三出撃収支

`tools/test_sortie_economy.gd` は seed 641、通常開始所持品（食料8、燃料2、修理キット2、Cr 0）から開始する。素材・所持金のテスト加算はない。通常の受注、地図移動、採取、報酬受領、都市売買、撤退救助、途中保存、チェックポイント再開を通す。

経路は準備の南部→都市、配達の往復、補給の往復、救助の往復の **7脚**。補給出撃は通常マップの木材契約6個を満たし、同じ通常鉱脈から鉄鉱石も採取して、作業台→精錬→運搬フレーム→通常の装備操作まで到達する。救助とチェックポイントは収支確定後の専用フィクスチャであり、収支には混ぜない。

| 人数 | 配達: 報酬後/維持費/差額 | 補給: 報酬後/維持費/差額 | 救助: 報酬後/維持費/差額 | 終了 Cr | 資産売却値 | 終了時の補給水準 | 初回強化 |
| --- | --- | --- | --- | ---: | ---: | --- | --- |
| 4 | 32 / 18 / +14 | 24 / 17 / +7 | 38 / 7 / +31 | **52** | 76 | 燃料100・食料12・修理6 | 作業台、運搬フレーム装備 |
| 5 | 32 / 17 / +15 | 24 / 25 / -1 | 38 / 8 / +30 | 44 | 68 | 燃料100・食料12・修理6 | 作業台、運搬フレーム装備 |

両ケースとも全員が生存・在隊し、三出撃後に通常の維持費を払って正の現金を残した。4人は 52 Cr、5人は 44 Cr なので、今回の seed 641・同一条件では4人を仮採用する。帰還ごとの現金差額、移動脚ごとの燃料/食料/修理カウンタ、部品状態、強化、全員の状態は各 `SORTIE_ECONOMY_JSON` に保存される。

訂正後の比較ログ（isolated APPDATA/LOCALAPPDATA）:

- `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-final-targeted\20261018T164037Z-xe_vunq2\sortie_economy_4.log`
- `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-final-targeted\20261018T164037Z-xe_vunq2\sortie_economy_5.log`

別保存したチェックポイントを1回再開した結果は 4人 47 Cr、5人 40 Cr。その後に凍結した収支スナップショットを戻すため、周回収支には含めない。

## 通常ワールド、保存、救助

- `test_world_reward_replenish.gd`: 都市で報酬を受けたあと、保存→Continueを挟み、次の通常地域到着で既存資源と死亡済み生物を一度だけ回復することを確認。受領直後の都市では回復せず、生存個体の重複もない。補給受注の取消は world/quarry の補充予約を増やさない。
- `test_save_roster_restore.gd`: 新規4人から過去3人の progress、checkpoint-only、v2 を復元。run ID が同一でも人数が異なるバックアップを拒否することを確認。
- `test_rescue_return.gd`: グループ撤退中、通常 AI を通る救助運搬者が救助を解除して `RETURN_BASE` になり、対象・予約が解放されることを確認。これは単なる状態代入ではない。
- `field_operations` と `first_cycle_flow` は3人兼任の既存フィクスチャとして別に維持する。通常ワールドの成功根拠を legacy 鉱山だけに置かない。

Focused regression は import を含む6件すべて成功した。

```text
rescue_return / save_roster_restore / world_reward_replenish /
sortie_economy_4 / sortie_economy_5: passed
結果: C:\Users\user\AppData\Local\Temp\desert-rats-stage3-final-targeted\20261018T164037Z-xe_vunq2\results.json
source_changed_during_run: false
```

`quarry` は公式ランナー経由で `--fixed-fps 60 -- legacy-world-test` を付与して実行するが、通常ワールド周回の代替根拠にはしない。

## 画像と画面入力

次の Compatibility renderer の既存 Viewport キャプチャは救助 UI の視覚証跡である。

- `docs/verification_assets/stage3-20261018/01-awaiting-rescue-timer.png`
- `docs/verification_assets/stage3-20261018/02-carrier-assigned-carrying.png`
- `docs/verification_assets/stage3-20261018/03-recovery-awaiting-explicit-resume.png`
- `docs/verification_assets/stage3-20261018/04-all-down-checkpoint-restart.png`

画面入力は別扱いである。この環境の Computer Use には Godot のネイティブ DEBUG ウィンドウが公開されず、OS レベルのクリック列は実行していない。スクリプト/Viewport 成功を画面入力成功とは主張しない。追加の画面検証には、Godot DEBUG ウィンドウを Computer Use が利用できるデスクトップ面へ表示してから、救助・Resume work・保存/Continue の操作を行う必要がある。

## 再現手順

```powershell
$godot = 'C:\Users\user\Documents\Codex\2026-09-29\gi\work\godot\Godot_v4.7.2-stable_win64_console.exe'
py tools\run_checks.py --godot $godot --check rescue_return --check save_roster_restore --check world_reward_replenish --check sortie_economy_4 --check sortie_economy_5
py tools\run_checks.py --godot $godot --check field_operations --check first_cycle_flow --check quarry
py tools\run_checks.py --godot $godot --suite core
```

## Claude への検証プロンプト

## Follow-up review corrections (2026-10-18)

This section overrides conflicting wording in the earlier validation record.

- **Roster wording corrected.** `test_save_roster_restore.gd` first captures a
  historical three-person snapshot, then explicitly opens a five-person
  *diagnostic* new-game fixture and restores it to three workers. It does not
  start from the four-person production default. Fresh player New Game remains
  four workers; the five-person fixture exists only to prove cross-roster
  recovery.
- **Backup recovery corrected.** A readable backup now restores when the
  separated primary is missing or damaged. A readable primary paired with a
  different run, or with a different crew count under the same run id, remains
  rejected. `test_save_ui.gd` covers the two UI recovery paths, while
  `test_save_roster_restore.gd` covers the same-run crew mismatch boundary.
- **Contract reservations corrected.** An accepted supply contract now wins
  over unstarted logical production orders, but `HAUL_TAKE` and queued transfer
  reservations remain unavailable. `test_town.gd` covers six physical wood
  against ten logical wood reservations, then the real haul and transfer cases.
- **Normal-world renewal narrowed.** Mission reward replenishment now touches
  only fixed gather points and fixed creatures. It does not unspend dynamic
  `ResourceNode` records such as historic carcasses. The two-cycle
  `test_world_carcass_replenish.gd` performs normal HUNT_ATTACK, carcass pickup,
  delivery reward, and revisit twice; only the fixed creature returns, historic
  carcasses remain spent, and drop totals do not grow on revisit.

### Re-measured normal three-sortie economy

Seed 641, normal starting stock/funds, ordinary order/travel/gather/reward/town
paths, and no material or credit grants were used. The harness now asserts at
every departure and return: fuel, food, repair kits, all base-part durability,
and no down/away crew. `elapsed_seconds_to_first_improvement` includes the
ordinary preparation wait (up to 420 simulated seconds) rather than starting
at the first mission.

| crew | final Cr | first improvement | total elapsed | final supplies | base durability | crew |
| ---: | ---: | ---: | ---: | --- | --- | --- |
| 4 | 52 | 308.8 s | 364.0 s | fuel 100, food 12, repair kits 6 | hull 96.63, drive 100, machine 98.95 | all present, none down |
| 5 | 44 | 445.0 s | 500.0 s | fuel 100, food 12, repair kits 6 | hull 95.07, drive 100, machine 99.72 | all present, none down |

The four-person default remains the provisional adopted setting for this
fixture. Per-sortie before-maintenance / maintenance / after-maintenance cash
is recorded in the JSON: 4-person `32/18/+14`, `24/17/+7`, `38/7/+31`; 5-person
`32/17/+15`, `24/25/-1`, `38/8/+30`.

Follow-up isolated evidence:

```text
C:\Users\user\AppData\Local\Temp\desert-rats-stage3-followup-targeted\20261018T173246Z-vwyg06or\results.json
  import, save_ui, town, world_reward_replenish, world_carcass_replenish: passed
  source_changed_during_run: false

C:\Users\user\AppData\Local\Temp\desert-rats-economy-scheduled\20261018T173334Z-peyvrvtn\results.json
  import, sortie_economy_4, sortie_economy_5: passed
  source_changed_during_run: false
```

### Updated Claude review prompt

```text
Review the newest gpt/rescue-return-loop HEAD of desert_rats. Fresh player New
Game defaults to four workers. Do not describe test_save_roster_restore as
four-to-three: it explicitly captures a historical 3-worker snapshot, opens a
diagnostic 5-worker fixture, then verifies Continue, checkpoint-only Restart,
and v2 migration reconstruct exactly 3 workers.

Run save_ui and verify that (1) a damaged or missing separated primary recovers
from a valid backup, (2) a same-run crew-count mismatch is rejected, and (3) a
readable primary from another run never falls back to that backup. Run town and
verify an accepted six-unit supply contract can claim six physical wood despite
ten unstarted logical wood reservations, while a real HAUL_TAKE reservation and
a queued transfer still prevent the claim.

Run world_reward_replenish and world_carcass_replenish on the normal map.
The latter must perform two real HUNT_ATTACK -> dynamic carcass pickup ->
delivery reward -> revisit cycles. Confirm only the fixed creature returns;
historic carcass rows remain spent and revisits add no hunt drops. Cancellation
must not schedule renewal and current-location arrival must not spawn instantly.
Keep legacy quarry validation distinct: use `--fixed-fps 60 -- legacy-world-test`.

Run sortie_economy_4 and sortie_economy_5. Both must use seed 641, normal stock
and funds, no grants, three ordinary sorties, a separate checkpoint fixture,
and seven recorded map legs. Check the departure/return maintenance assertions,
the JSON elapsed seconds to first improvement (including preparation), and the
four-worker result of 52 Cr versus five-worker 44 Cr. Finally run the complete
core suite from the reviewed commit and report source_changed_during_run
separately from native OS-level UI-input coverage.
```

```text
Review the newest gpt/rescue-return-loop HEAD of desert_rats. Treat the old 54/66 Cr, five-worker conclusion as superseded. New games now default to four workers; existing 3--5 worker saves must reconstruct their saved roster before Apply/Continue, including checkpoint-only and v2 saves, while a same-run backup with a mismatched crew size is rejected.

Run the focused checks and inspect their JSON/logs: rescue_return, save_roster_restore, world_reward_replenish, sortie_economy_4, and sortie_economy_5. Economy must use seed 641, normal stock/funds, no material or credit grants, exactly seven recorded map legs, normal orders/travel/gathering/mission reward/town paths, and a separate checkpoint fixture. Confirm the corrected measurement: four workers end at 52 Cr versus five at 44 Cr after three maintained sorties; both retain fuel100/food12/repair6, a workbench, an equipped haul frame, and no absent/down crew. Verify accepted supply cargo is protected from automatic craft and sale but can satisfy its own claim ahead of queued crafting.

For the normal world, verify a reward claim persists a pending renewal, has no immediate current-location spawn, restores only existing resource/dead-creature records on the next normal-region arrival once, does not duplicate living entities, and cancellation adds no renewal. Keep legacy quarry validation distinct (`--fixed-fps 60 -- legacy-world-test`). Verify group recall cancels an active rescue carrier via normal AI and returns it to base. Report OS-level screen clicks separately: the saved Viewport images are visual evidence, but native-window input was not available in this environment.
```

## 最終 full core

隔離 APPDATA/LOCALAPPDATA の Windows Godot 4.7.2 で **68 / 68 成功**。

- 結果: `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-final-core\20261018T164351Z-e3k7wmm9\results.json`
- `source_changed_during_run: false`
- 実行時 HEAD（前後）: `ca3b27f931cdd96eafc59bb59fb32bb86344744f`

公開したブランチ HEAD と GitHub の同一 SHA は、タスク完了時のハンドオフで報告する。
