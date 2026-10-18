# Rescue / return loop work log — 2026-10-18

- Checkout: `C:\Users\user\Documents\Codex\2026-10-18\task-4`
- Branch: `gpt/rescue-return-loop` (created from `5e2d87e85af2aa866d8037acadda46111aa588a0`); main was not merged.
- Notion: the requested final page could not be retrieved in this environment. The approved user instruction was used as the source of truth.
- Implemented: explicit rescue carrier reservation, 90-second non-carried timer, pause while carried, cancellation when carrier goes down, no natural revival/no automatic cargo storage, carrier slot independent of normal cargo, 70% carry speed or 90% with the existing crafted haul frame, treatment then explicit resume, city-only 48 Cr revival (two 24 Cr supply rewards), all-down checkpoint prompt, and save snapshot/restore fields.
- UI: crew details exposes explicit rescue assignment, recovery resume, and city revival action; all-down prompt exposes checkpoint restart.
- Added `tools/test_rescue_return.gd`; verified manual designation, duplicate rejection, full carrier, timer pause, carrier interruption, recovery wait/resume, expiry, insufficient-funds rejection, snapshot restore, and all-down prompt.
- Existing `tools/test_crew_status.gd` was updated for the adopted no-natural-revive/cargo-retention behavior.
- Verification before final core: Godot parser clean; `test_rescue_return.gd`, `test_crew_status.gd`, `test_save_game.gd`, and `test_production_recovery.gd -- legacy-world-test` passed. A first host core run was interrupted after five passing checks. A later scheduled run exposed the obsolete production expectation that downed workers auto-store cargo; it was updated to assert retained personal cargo and the temporary task was deleted. Final core must be run from the final commit in isolated APPDATA/LOCALAPPDATA and must report `source_changed_during_run: false`.
