# Rescue / return loop work log — 2026-10-18

- Checkout: `C:\Users\user\Documents\Codex\2026-10-18\task-4`
- Branch: `gpt/rescue-return-loop` (created from `5e2d87e85af2aa866d8037acadda46111aa588a0`); main was not merged.
- Notion: the requested final page could not be retrieved in this environment. The approved user instruction was used as the source of truth.
- Implemented: explicit rescue carrier reservation, 90-second non-carried timer, pause while carried, cancellation when carrier goes down, no natural revival/no automatic cargo storage, carrier slot independent of normal cargo, 70% carry speed or 90% with the existing crafted haul frame, treatment then explicit resume, city-only 48 Cr revival (two 24 Cr supply rewards), all-down checkpoint prompt, and save snapshot/restore fields.
- UI: crew details exposes explicit rescue assignment, recovery resume, and city revival action; all-down prompt exposes checkpoint restart.
- Added `tools/test_rescue_return.gd`; verified manual designation, duplicate rejection, full carrier, timer pause, carrier interruption, recovery wait/resume, expiry, insufficient-funds rejection, snapshot restore, and all-down prompt.
- Existing `tools/test_crew_status.gd` was updated for the adopted no-natural-revive/cargo-retention behavior.
- Follow-up review (2026-10-18): an assigned-but-not-yet-picked-up timer continues to count; cancelling a deck-side rescue now clears the rescue target and enters `RETURN_BASE`, so personal/group withdrawal cannot strand a carrier in `RESCUE_MOVE`/`RESCUE_CARRY`. The dedicated rescue regression covers that real interruption.
- Follow-up review (2026-10-18): `HAUL_MOVE.carrying` is only a lead-item marker. Rescue interruption clears that marker before converting the full recipe into personal cargo, preventing duplicate material accounting. `test_production_recovery.gd -- legacy-world-test` now uses a real wood+iron `HAUL_MOVE`, save/applies the interrupted cargo, and returns it through rescue to prove exact-once ownership.
- Follow-up review (2026-10-18): `test_rescue_return.gd` now captures a genuine carried rescue rather than injecting rescue data into a pre-down snapshot; it verifies remaining time, carrier reservation, both AI states, and multi-item personal cargo after `SaveGame.apply`.
- Existing `test_weapon.gd` was reconciled with the adopted no-natural-revive rule without dropping combat coverage: it first proves no natural recovery, then recovers the armed worker through an explicit rescue carrier before retaining its original weapon/combat checks.
- Automatic HP30% withdrawal is scoped to an active rescue carrier, as required for rescue interruption; ordinary low-HP workers retain their established rest behavior. The rescue regression covers that automatic cancellation, while crew/life fixture resets now clear rescue-only AI fields between cases.
- Verification before final core: Godot parser clean; `test_rescue_return.gd`, `test_crew_status.gd`, `test_save_game.gd`, `test_production_recovery.gd -- legacy-world-test`, `test_haul_support.gd -- legacy-world-test`, and `test_weapon.gd -- legacy-world-test` passed. Final core must be run from the final commit in isolated APPDATA/LOCALAPPDATA and must report `source_changed_during_run: false`.
- Follow-up finalization (2026-10-18): HP at or below 30% now requests withdrawal for every outdoor worker (gathering, hunting, recovery, transfer, manual combat, and rescue); deck-side low-HP rest remains unchanged. Group recall has a per-worker persisted exclusion in crew details. Excluded workers retain their assigned task or explicit rescue carrier role, while their own return order and the HP30 outdoor safety rule still take priority. `test_rescue_return.gd` covers each distinction and is now included in the core suite; `test_crew_detail.gd` covers the visible control. Godot Viewport captures were recorded with the Windows 4.7.2 compatibility renderer at `C:\Users\user\AppData\Local\Temp\desert-rats-rescue-ui-evidence` (awaiting timer, carried rescue, explicit recovery resume, all-down checkpoint restart).
- Final UI language pass (2026-10-18): localized the rescue status, assignment/recovery controls, group-recall control, and all-down checkpoint prompt. The worker action line now prioritizes rescue, transport, and recovery-wait states over ordinary automatic-work text. The targeted crew-detail/rescue regressions and four real-viewport captures are rerun after this display-only change.

- Stage 3 follow-up (2026-10-18): compared 4 and 5 workers through the normal three-sortie loop at seed 641 without material or credit grants. Both retain a net result after maintenance (54 / 66 Cr), so new games now start with five workers while existing 3--5 worker saves retain their saved size. Added `tools/test_sortie_economy.gd`, normal-map replenishment/rescue/save assertions, explicit three-worker fixtures for small-crew regressions, and Windows compatibility-renderer rescue captures in `docs/verification_assets/stage3-20261018/`. The complete validation record, remaining UI-input limitation, final core status, and pushed SHA are in `docs/stage3-validation-2026-10-18.md`.

- Final verification (2026-10-18): isolated Windows Godot 4.7.2 core passed 66/66 with `source_changed_during_run: false`. Result: `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-core-clean\20261018T152157Z-h85q230s\results.json`.

- Stage 3 measurement correction (2026-10-18): the prior 54/66 Cr evidence was withdrawn because its harness mixed hidden mine trips, a pre-city maintenance snapshot, and a checkpoint mutation with economics. The replacement `test_sortie_economy.gd` records only seven visible normal-map legs, waits for normal ore collection and normal city eligibility, keeps checkpoint restart separate, and records every return's cash, consumables, parts, upgrade, and crew state. Focused isolated regression passed for rescue return, historical roster restore, normal-world reward replenishment, and both 4/5-worker economy cohorts at `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-final-targeted\20261018T164037Z-xe_vunq2\results.json` with `source_changed_during_run: false`. Corrected result: 4 workers end at 52 Cr and 5 workers at 44 Cr, both after maintenance; new games therefore default to four workers. Contract materials are protected from automatic craft/sale while their own claim can outrank a queued craft reservation. Normal-world renewal and old-save roster tests are now core checks. The complete corrected evidence, images, reproduction commands, and remaining OS-input limitation are in `docs/stage3-validation-2026-10-18.md`.

- Final stage 3 core (2026-10-18): isolated Windows Godot 4.7.2 core passed 68/68 from `ca3b27f931cdd96eafc59bb59fb32bb86344744f`, with `source_changed_during_run: false`. Result: `C:\Users\user\AppData\Local\Temp\desert-rats-stage3-final-core\20261018T164351Z-e3k7wmm9\results.json`. The temporary Task Scheduler job used for the long run was removed afterwards.

- Publication (2026-10-18): the validated implementation was committed and pushed on `gpt/rescue-return-loop`; the final branch/remote SHA match is reported in the task handoff. Protected user-local `.appdata-test/` remains untracked and untouched.

- Follow-up review correction (2026-10-18): `test_save_roster_restore.gd` is
  explicitly a historic 3-worker snapshot -> diagnostic 5-worker scene ->
  restored 3-worker scene regression. It is not evidence that the production
  New Game path starts at four before restoring three; the actual fresh default
  remains four. SaveUI now accepts a valid backup when its primary is missing or
  damaged, while preserving readable-primary different-run and crew-mismatch
  rejection. `test_save_ui.gd` covers UI recovery and
  `test_save_roster_restore.gd` covers the crew-mismatch boundary.

- Follow-up review correction (2026-10-18): supply contracts now outrank only
  unstarted logical orders; concrete `HAUL_TAKE` and queued transfer claims
  remain protected. Normal-world reward renewal no longer revives dynamic
  resource rows. `test_town.gd`, `test_world_reward_replenish.gd`, and the new
  two-cycle real-hunt `test_world_carcass_replenish.gd` passed in isolated
  APPDATA/LOCALAPPDATA. The carcass test proves historic corpses stay spent and
  cannot add drops after each revisit.

- Economy re-measurement (2026-10-18): the 4/5-worker seed-641 three-sortie
  tests passed with maintenance assertions at every departure and return. Four
  workers ended at 52 Cr, reached the first hauling/storage improvement at
  308.8 simulated seconds, and completed at 364.0 seconds; five workers ended
  at 44 Cr, reached it at 445.0 seconds, and completed at 500.0 seconds. Both
  retained fuel 100, food 12, repair kits 6, non-depleted base parts, and no
  down/away crew. Evidence:
  `C:\Users\user\AppData\Local\Temp\desert-rats-economy-scheduled\20261018T173334Z-peyvrvtn\results.json`
  (`source_changed_during_run: false`). A final complete core run remains due
  from the final follow-up commit.

- Independent Linux follow-up (2026-10-19): fixed four non-design regressions
  on `gpt/rescue-return-loop`: return-to-reward-city renewal is deferred until
  a different normal arrival; corrupt separated progress refuses an unproven
  foreign backup; a completed rescue carrier unloads its normal owned cargo
  before recovery wait; and the save migration confirmation is scrollable and
  revealed within the viewport.  Added strict regression coverage in
  `test_world_reward_replenish.gd`, `test_save_ui.gd`, and
  `test_rescue_return.gd`; focused isolated Godot 4.6.3 run passed.  Extended
  the ordinary economy fixture with an optional 1,400-second real-meal
  observation and recorded seeds 641--643 for 4/5 workers.  Several existing
  maintenance/first-improvement assertions fail on 642/4, 643/4 and 643/5;
  they were not weakened.  All six runs have 8--12 meals and zero built/used
  beds, so no crew-count/bed-capacity product change was made.  Full details,
  commands, limitations and Claude handoff prompt are in
  `docs/stage3-validation-2026-10-18.md`.
