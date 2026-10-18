# Stage 3 validation record — 2026-10-18

## Scope and decision record

- Checkout: `C:\Users\user\Documents\Codex\2026-10-18\task-4`
- Branch: `gpt/rescue-return-loop`; `main` was not changed.
- Starting HEAD: `860b2f2385519b15706500ce71a22f90e9be9fa8`; after fetch it was 19 commits ahead of and 0 behind `origin/main`.
- The original checkout, user saves, stash, and existing untracked `.appdata-test/` are outside this work.

Notion was checked on 2026-10-18 through `docs/Notion参照索引.md`. The adopted direction is that a successful loop pays maintenance and still leaves profit/progression; exact prices and unlock values remain undecided. An exploratory Notion proposal was not treated as adopted. The current user-approved initial crew, three-sortie loop, and replenishment conditions supersede earlier material.

## Implementation

- New games start with five workers. Existing saves retain their saved roster size (3--5), so no worker is silently inserted into an in-progress run.
- Added `tools/test_sortie_economy.gd`: seed 641, normal initial stock/funds, and only player-facing orders, travel, gathering, missions/rewards, town trading, recall, rescue, save, and checkpoint APIs.
- `run_checks.py` runs separate 4-worker and 5-worker economy processes in core. They are explicitly normal-world tests, never a legacy quarry fixture.
- The default-map probe follows `DEFAULT_INITIAL_WORKERS`. `first_cycle_flow` and `field_operations` are explicit 3-worker small-crew fixtures rather than accidental dependencies on the new-game default.

Automatic-use verification required no product change. `ProductionPlan.defaults()` keeps food 12, fuel 8, and repair kits 6; `ProductionPlan.held_for_orders` plus `AutoCraftGuard` preserve materials required by manual orders/builds. Automatic tool use is enabled by default. The economy harness asserts each setting.

## 4-worker / 5-worker measurements

Same seed 641, same normal start: food 8, fuel 2, repair kits 2, and Cr 0. Every row covers delivery, supply, and recovery once, including maintenance, reward claim, deferred mine replenishment, rescue, mid-sortie save/continue, and checkpoint restart.

| Crew | Delivery Cr | Supply Cr | Recovery Cr | Food used | Repair actions | End fuel | Net Cr after maintenance | Live crew | First improvement |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 4 | +32 | +13 | +14 | 4 | 10 | 100 | **54** | 4 | haul frame |
| 5 | +32 | +11 | +30 | 0 | 7 | 82 | **66** | 5 | haul frame |

Checkpoint-restart Cr is 54 / 66 after the one saved maintenance purchase (checkpoint Cr 59 / 73). Both cohorts remain profitable; 5 workers is provisionally adopted because the same scenario leaves 66 Cr instead of 54.

The original JSON is emitted as `SORTIE_ECONOMY_JSON` in:

- `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-targeted-final\20261018T150459Z-lwc_9_7t\sortie_economy_4.log`
- `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-targeted-final\20261018T150459Z-lwc_9_7t\sortie_economy_5.log`

## Replenishment, rescue, and normal world

The economy harness proves that a cancelled mission schedules no replenishment; a claimed reward schedules no immediate respawn; the following mine visit alone replenishes resources/fauna; and no living entities are duplicated. It also proves normal recovery action, explicit rescue carrier and resume, mid-sortie `SaveGame.apply`, city checkpoint, and checkpoint restart.

Final selected normal-world run:

```text
py tools\run_checks.py --godot <Godot 4.7.2 console> --check world_reencounter --check first_cycle_flow --check quarry
# import / world_reencounter / first_cycle_flow / quarry: passed
```

`quarry` was executed by the official runner with `--fixed-fps 60 -- legacy-world-test`; it is not the evidence for normal-world success. Separately, with isolated APPDATA/LOCALAPPDATA, `probe_default_map.gd --seed=641 --scenario=stay --seconds=60` passed with a normal five-worker start, default supply targets, normal gathering/auto-production, and zero violations. `field_operations` and `first_cycle_flow` separately passed as the explicit three-worker cross-role regression.

## Visual evidence vs. input evidence

Real Godot 4.7.2 Compatibility-renderer Viewport captures were generated and the third image was visually inspected. It shows five workers and recovery waiting for the explicit `Resume work` action.

- `docs/verification_assets/stage3-20261018/01-awaiting-rescue-timer.png`
- `docs/verification_assets/stage3-20261018/02-carrier-assigned-carrying.png`
- `docs/verification_assets/stage3-20261018/03-recovery-awaiting-explicit-resume.png`
- `docs/verification_assets/stage3-20261018/04-all-down-checkpoint-restart.png`

Screen-input automation is deliberately reported separately: Godot launched with isolated APPDATA, but this host exposed no Windows automation target (window handle 0), so no click/input sequence was performed. The script and Viewport results above are not claimed as OS-level input verification.

## Harness corrections

The following were harness conditions, not game defects: ordinary ore needs the normal wood pick and hammer orders; delivery/recovery needs normal town selling to free cargo capacity; one SceneTree cannot recreate the 4/5 cohorts reliably, so they run in separate processes; the runner initially assigned legacy-world-test to the economy checks and was corrected; and the old save-disabled town fixture implicitly expected three workers. Save-disabled fixtures retain three workers while a real new-game path uses five.

Reproduce with isolated APPDATA/LOCALAPPDATA:

```text
py tools\run_checks.py --godot <Godot 4.7.2 console> --check sortie_economy_4 --check sortie_economy_5
py tools\run_checks.py --godot <Godot 4.7.2 console> --check field_operations --check first_cycle_flow
py tools\run_checks.py --suite core --godot <Godot 4.7.2 console>
```

Final core run passed **66/66** with no failure:

- Result: `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-core-clean\20261018T152157Z-h85q230s\results.json`
- `source_changed_during_run: false`
- Game source HEAD before/after the run: `860b2f2385519b15706500ce71a22f90e9be9fa8`

The commit SHA and remote-SHA match are appended after commit/push.

## Claude validation prompt

```text
Review the newest gpt/rescue-return-loop HEAD of desert_rats. New games begin with five workers while existing 3--5 worker saves retain their own size. Inspect tools/test_sortie_economy.gd: it runs 4 and 5 workers with seed 641 and normal stock/funds, no material/Cr grants, using only orders, movement, gathering, mission/reward, and town paths. Confirm three sorties leave 54 Cr (4 workers) and 66 Cr (5 workers) after maintenance; the first hauling improvement is reached; reward claim alone schedules the next mine visit's resources/fauna replenishment; cancellation schedules none; there is no instant respawn or duplicated living entity. Verify rescue carrier assignment, explicit resume, mid-sortie save/continue, checkpoint restart, explicit three-worker cross-role fixtures, and ProductionPlan targets (food 12, fuel 8, repair kits 6) with manual-order material protection. Use run_checks core/normal-world logs, this document, and the Viewport images. Report OS-level screen clicking separately as unverified on this host.
```
