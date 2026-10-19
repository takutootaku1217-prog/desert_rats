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

### Final follow-up core and test-scope boundaries

This result supersedes the older `68 / 68` reference later in this document.
The isolated Windows Godot 4.7.2 core suite passed **69 / 69** from commit
`857dd52076d7a2af40355b04e346b3a68656d849` on
`gpt/rescue-return-loop`.

```text
C:\Users\user\AppData\Local\Temp\desert-rats-final-core-followup\20261018T174106Z-jvwdi0a_\results.json
  run HEAD: 857dd52076d7a2af40355b04e346b3a68656d849
  status: passed
  passed checks: 69 / 69
  source_changed_during_run: false
```

The economy maintenance reference is the post-preparation, post-normal-town
maintenance baseline. Every sortie departure and return is compared against
that common baseline for fuel, food, repair kits, and all base-part durability;
it is not a claim that a brand-new starting inventory is kept unchanged.

`test_world_carcass_replenish.gd` is a renewal/persistence regression, not a
combat-difficulty benchmark. It uses a fixed normal-map prey placement and
clamps that prey to 1 HP so the ordinary `HUNT_ATTACK` ->
`Main.on_creature_killed` -> carcass pickup path completes deterministically
inside the finite viewport. The test still uses the normal hunt, storage,
mission reward, and revisit paths, but does not measure typical live-combat
survival difficulty.

Native OS clicking remains unverified. The available Computer Use surface was
checked after the core run: it exposed no native app surfaces and only an empty
Edge browser surface, so there was no Godot DEBUG window to target with
Windows input automation. Script and Viewport results above are therefore not
represented as native click coverage. Minimal user check: launch the Godot
DEBUG window, load or start a run, click the rescue/Resume work and
Save/Continue controls once each, then report any visible mismatch or attach a
screenshot.

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

## 2026-10-19: independent Linux follow-up

This follow-up started from `828c5ec96c61674d4e0a4ef23e175d66f2064525`
on `gpt/rescue-return-loop`.  It uses a fresh clone and a per-run isolated
`HOME`/`XDG_*` directory; it does not read or modify a real player profile.
Godot 4.6.3 stable is the locally available comparison runtime.  The previous
Windows 4.7.2 result remains historical evidence only, not a result for this
follow-up.

### Corrected defects and regressions

* **Return reward renewal:** a reward reserved in `central_trade` no longer
  renews that same city when the player cancels/returns into it.  The
  reservation is consumed only by a later normal arrival in another region.
  `world_reward_replenish` spends the normal city resource and creature,
  saves/continues, returns to that city, and asserts both are still spent;
  it then verifies exactly one later normal renewal.
* **Damaged primary save:** when the separated progress primary is corrupt,
  recovery accepts a backup only when the existing same-run checkpoint proves
  both run id and crew count.  A legacy/foreign backup with no such authority
  is refused rather than becoming the source of truth.  `save_ui` creates a
  corrupt primary plus an actual foreign `.bak` and asserts the current
  snapshot is unchanged and the UI says it belongs to another run.
* **Rescue carrier cargo:** a carrier now unloads normal owned cargo when the
  carried crew member is delivered, before entering recovery wait.  This
  keeps the dedicated carried-person slot distinct from item ownership and
  removes the departure blocker without duplicating or consuming the items.
  `rescue_return` starts the carrier with two stone and one wood carry bonus,
  checks the exact storage delta, empty carrier/bonus, and an empty
  `ready_reason()` after delivery.
* **Migration confirmation visibility:** Save UI now uses a full-viewport
  panel and vertical `ScrollContainer`; the confirmation is revealed when it
  opens.  `save_ui` exercises v2 migration and asserts the panel and confirm
  control lie in the visible viewport/scroll rect.  This is renderer/script
  layout coverage, not a claim of native Linux mouse or compositor coverage.

Focused isolated run (Godot 4.6.3):

```text
/tmp/desert-rats-targeted-3/20261019T025431Z-6e6xk5g9/results.json
import, save_ui, rescue_return, world_reward_replenish,
world_carcass_replenish: passed
```

The same focused set also passed with the official Godot 4.7.2 Linux binary:

```text
/tmp/desert-rats-targeted-472/20261019T030430Z-szjtg76d/results.json
import, save_ui, rescue_return, world_reward_replenish,
world_carcass_replenish: passed
```

### Longer normal-settings economy observation (not a balance decision)

Each case uses the normal three-sortie scenario and its ordinary preparation,
then continues **1,400 simulated seconds**.  It has no material/credit grant
and requires at least two real eating actions.  This exceeds the roughly
19-minute hunger threshold from 100 to below 25; all six cases actually ate
8--12 times.  The columns after cash are observation-only: meals, food
inventory change, ending food, `REST_HERE` worker-seconds, and ending
refuel/repair action totals.

| seed | crew | first improvement s | 3-sortie s | cash | meals | food delta / end | REST_HERE | refuel / repair | result |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | --- |
| 641 | 4 | 308.8 | 364.0 | 52 | 8 | -8 / 4 | 477.8 | 4 / 17 | pass |
| 641 | 5 | 445.0 | 500.0 | 44 | 10 | -10 / 2 | 538.6 | 4 / 16 | pass |
| 642 | 4 | 434.0 | 486.4 | 58 | 8 | -7 / 4 | 540.0 | 4 / 16 | **maintenance fail on sortie 3** |
| 642 | 5 | 308.2 | 346.2 | 48 | 10 | -10 / 2 | 633.4 | 3 / 17 | pass |
| 643 | 4 | 491.0 | 544.8 | 50 | 12 | -8 / 0 | 457.2 | 5 / 17 | **maintenance and first-improvement fail** |
| 643 | 5 | 485.8 | 537.8 | 47 | 12 | -8 / 0 | 668.6 | 5 / 18 | **first-improvement fail** |

The failures above are retained assertions, not relaxed pass criteria.  In the
642/4 case the third return cannot meet the common repair/durability baseline;
643/4 additionally cannot meet it on the first return and does not craft the
first improvement; 643/5 does not craft that first improvement.  All six runs
remain non-game-over and cash is unchanged during the post-sortie observation.
Food delta differs in 642/4 because one cooked replacement is produced.  No
beds are built in any of the six standard cases (`built_beds = 0`, bed busy
time = 0); rest is `REST_HERE` (457.2--668.6 worker-seconds), so the proposed
three-bed contention explanation is not supported by this evidence.  Hunger
below the eating threshold is measured (25.8--224.8 worker-seconds) and urgent
hunger is zero.

Reproduce one case with:

```text
XDG_CONFIG_HOME=<isolated> XDG_DATA_HOME=<isolated> XDG_CACHE_HOME=<isolated> \
  godot --headless --path . --fixed-fps 60 -s res://tools/test_sortie_economy.gd -- \
  --crew-count 4 --seed 641 --observe-seconds 1400
```

The logs used for this report were `/tmp/desert-rats-survey-{641,642,643}-{4,5}.log`.
They show refuel/repair action counts, state-time causes, food consumption and
end inventories separately.  They do **not** justify changing default crew
count or bed capacity.  A balance decision is required before changing either:
the observed seed-sensitive maintenance/upgrade failures must first be given a
product target (for example, whether every normal seed must reach the first
upgrade by sortie 1--2 and whether post-preparation replenishment must be paid
from cash or gathered materials).

### Claude review prompt for this follow-up

```text
Review the newest gpt/rescue-return-loop HEAD of desert_rats.  Do not make a
product decision about starting crew count, bed capacity, or revival cost.
Run save_ui, rescue_return, world_reward_replenish and
world_carcass_replenish in an isolated profile.  Verify: a corrupt progress
primary rejects a foreign backup but accepts a checkpoint-proven same-run
backup; returning to the reward city does not respawn its spent resource or
creature; a delivered rescue carrier unloads its owned items exactly once and
can depart; and the migration confirmation is within the ScrollContainer
visible rect.  Distinguish that viewport/layout evidence from native OS mouse
input.

Run test_sortie_economy with seeds 641, 642 and 643 for crews 4 and 5 using
--observe-seconds 1400.  Do not weaken failures.  Report cash, food eaten and
inventory change, refuel/repair totals, REST_HERE/bed state time, and each
maintenance or first-improvement failure separately.  Confirm that normal
runs build zero beds, so the data does not establish a bed-capacity cause.
Finally run the core suite from the reviewed commit and report runtime version,
isolated-profile path, source_changed_during_run, and native-input coverage
separately.
```

## 2026-10-19: repeatable-loop cause analysis

### Scope: idle observation versus paid repetition

The earlier 1,400-second observation is explicitly a **no-income city idle
observation**: it begins after the three fixed missions, at `central_trade`,
with no accepted follow-up job, map travel, or mission claim. Normal autonomous
eating/resting/crafting/repair remains enabled, but there is no resource or
reward opportunity. It is food/wait evidence, not a profitability result.

The new `--repeat-deliveries 21` mode is separate. After the fixed three
missions it repeats normal paid delivery: accept, travel to `south_oasis`, wait
for normal gathering AI, return, claim the 32 Cr reward, then restore the same
fuel/food/repair/durability baseline. Every leg, maintenance purchase, meal,
state time, and market sale is recorded. When capacity would prevent a food
purchase, it sells only normal unreserved surplus using the existing city
market; this is recorded separately and is not a grant.

### Repeated normal work with real meals

All rows complete 21 paid deliveries and at least four actual meals. `Repeat
net` is after maintenance and includes the separately shown market sale
proceeds. Cash maintenance is actual city spending; fuel/part columns are
action counts.

| seed | crew | 3-mission cash | repeat net | end cash | meals | food buys | fuel / part repair | cash maintenance | sale proceeds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: |
| 641 | 4 | 52 | +555 | 607 | 4 | 0 | 21 / 27 | 179 | 62 |
| 641 | 5 | 44 | +541 | 585 | 5 | 1 | 21 / 28 | 189 | 58 |
| 642 | 4 | 58 | +558 | 616 | 4 | 0 | 21 / 19 | 170 | 56 |
| 642 | 5 | 48 | +569 | 617 | 5 | 1 | 21 / 28 | 177 | 74 |
| 643 | 4 | 50 | +515 | 565 | 4 | 4 | 21 / 29 | 205 | 48 |
| 643 | 5 | 47 | +541 | 588 | 5 | 5 | 21 / 28 | 197 | 66 |

Thus successful, income-producing normal repeats pay maintenance and remain
cash-positive in all six cohorts. This does not erase fixed three-mission
failures: it shows a player can keep earning when using the existing market to
make refill room. A full inventory can otherwise prevent food purchase despite
credits; the idle observation intentionally does not sell or travel and must
not be used to judge this loop.

This is **delivery-only** evidence.  The repeated legs do not re-run the fixed
supply or recovery contracts, so they do not establish that every mixed
delivery/supply/rescue rotation is stable.  Their supported conclusion is
limited to paid delivery income, its food/refill capacity boundary, and the
normal repair/refuel work that occurs during those delivery loops.

### Initial-upgrade cause, not inferred crafting wait

The haul frame requires wood 2, **hide 1**, and iron 1. The diagnostic now
records `ProductionPlan.order_reason()` every 0.2 seconds during the approved
first-upgrade wait, rather than labelling `IDLE` as manufacturing delay.

| seed | crew | wait | recorded reason | outcome |
| --- | ---: | ---: | --- | --- |
| 641 | 4 | 58.8 s | material shortage 58.6 s; transfer 0.2 s | completed |
| 641 | 5 | 209.4 s | material shortage 209.2 s; transfer 0.2 s | completed |
| 643 | 4 | 240.0 s | material shortage 240.0 s; hide absent | not completed |
| 643 | 5 | 240.0 s | material shortage 240.0 s; hide absent | not completed |

The earlier approximately 210/59-second difference is therefore not evidence
of slower five-worker manufacturing or bed contention. In seed 641 it is hide
availability. In seed 643 both cohorts retain an unstarted haul-frame order
because hide never arrives. Supply-phase `PROCESS` time is only 27.8/34.6
worker-seconds for 641 four/five and 23.6/18.8 for 643 four/five; IDLE and
REST vary by seed, not monotonically by crew. No standard run builds or uses a
bed.

The 642/4 and 643/4 immediate maintenance failures are also not a lost-item or
stuck-AI result: a worker owns a normal `REPAIR_TAKE` reservation, which
correctly blocks duplicate city service for that part.  The immediate fixed-leg
assertion remains deliberately unchanged.  A separate bounded
`--eventual-maintenance-probe` records the actual completion before allowing
normal city service to fill any remaining gap:

| case | reserved part | bounded wait | automatic result | city completion | result |
| --- | --- | ---: | --- | --- | --- |
| 642/4 recovery return | drive | 3.6 s | one action, kit 6→5, drive 74.98→99.98 | none | baseline restored |
| 643/4 delivery return | hull | 3.0 s | one action, kit 5→4, hull 55.01→79.81 | after recall, one 7 Cr hull service to 100 | baseline restored |

Thus each reservation completes once and consumes at most its one repair kit;
there is no duplicate material consumption.  In 643/4 the automatic threshold
is 75, so the one 25-point repair intentionally stops at 79.81 rather than
repeating to the higher preparation baseline.  Returning the idle crew to the
city and using the existing per-part cash service restores that baseline in
finite time.  This is a timing/state-boundary in the immediate assertion, not
a balance shortfall or an AI deadlock.  The town UI does not claim a global
"full repair": it presents a per-part repair quote and explicitly reports
`仲間がこの部位を修理予約中` for the reserved part, so no display change is
required from this evidence.

The probe is intentionally separate from the normal fixed-leg run, because
waiting advances the deterministic world/RNG.  Reproduce it without weakening
the standard assertions:

```text
godot --headless --path . --fixed-fps 60 -s res://tools/test_sortie_economy.gd -- \
  --crew-count 4 --seed 642 --eventual-maintenance-probe
godot --headless --path . --fixed-fps 60 -s res://tools/test_sortie_economy.gd -- \
  --crew-count 4 --seed 643 --eventual-maintenance-probe
```

### Save/rescue boundaries rechecked

The rescue regression now fills storage to exact capacity including the
carrier's 2 stone + 1 wood. Delivery verifies exact final counts, unchanged
total weight/capacity, empty carrier cargo, and no `wasted` item:

```text
/tmp/desert-rats-rescue-capacity/20261019T032849Z-tz1zsmj0/results.json
import, rescue_return: passed
```

Cargo is already part of `current_weight()` while carried, so `unload_owned()`
changes owner location rather than adding external loot. For B, there is an
intentional availability limit: without a readable primary or same-run
checkpoint, a legitimate standalone `.bak` cannot be distinguished from a
foreign run and is refused. Relaxing that safeguard needs a product decision
to accept cross-run-load risk.

### Decision boundary and Notion evidence

The adopted direction requires upgrades to create overall surplus rather than
only move a bottleneck, but leaves numerical costs, materials, capacity and
unlock conditions undecided ([adopted direction](https://app.notion.com/p/3f9ec2f2a3c181baaa0dd0e3363730aa?pvs=204)). The delivery/life-improvement
page is a proposal and also leaves rewards, mission conditions and balance
numbers undecided ([proposal](https://app.notion.com/p/3f8ec2f2a3c1817fbd31fa3c068f6bc3?pvs=204)).

No balance number was changed. The approved targets remain: successful normal
loops pay maintenance and profit; the first improvement should be a one-to-two
sortie expectation. The former is met by paid repetition; the latter is not
robust because seed 643 gets no required hide. Minimum product decision: either
guarantee hide by sortie 1--2, or make the first improvement not depend on
hide. The amount/drop placement or alternative recipe is a balance choice.
