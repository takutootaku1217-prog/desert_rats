# Quarry mission-replenishment coverage

Date: 2026-10-18

This follow-up extends the isolated repeatable-subquest prototype with the
quarry. A successful `claim_supply`, `claim_delivery`, or `claim_recovery`
schedules its next arrival to restore the fixed `QuarryDB.POINTS` amounts and
clear their work progress. It never changes the active quarry visit.

The pending flag is saved. Older saves that predate the flag load with it set
to `false`. Because the claim ticket is consumed before the mission action,
duplicate reward clicks cannot schedule a second refresh. Accepting,
cancelling, partial delivery, or mission-only cargo still do nothing.

Windows Godot 4.7.2 with isolated APPDATA passed the focused checks:

- `town`, including inactive-quarry depletion, next-arrival restoration, and
  legacy-save normalization;
- `quarry`, `save_game`, and `town_flow`.

Result: `C:\Users\user\AppData\Local\Temp\desert-rats-quarry-replenish-town-2\20261018T030912Z-6ckdvgr5\results.json`

No OS-input or manual-video validation was available. This is test-harness
coverage of the normal arrival path, distinct from on-screen manual play.
