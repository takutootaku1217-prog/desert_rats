# v13 Acceptance Baseline

Created 2026-10-28 in a cloud-only isolated copy. This is not a replacement
project, Git branch, PC copy, personal save, or published artifact.

## Source basis

- Upstream baseline commit: `1348700c775822108df91ed48a21ea73bbd9792a`
- Supplied baseline archive SHA-256:
  `72dd15252606eeae67e8b55c8a4cbaf8bcc2fc9c72c366771b91457f5350c79d`
- Required predecessor: `canyon_recovery_hub_pc_cumulative_v13_20261028_final.zip`
- Required predecessor SHA-256:
  `c48b32bed9d029facda48812e97ad3523d45be66dadbef5b5398ea8811cbc35f`

The v13 archive is an overlay over the 1348700 package, not a stand-alone game
tree. This acceptance work therefore produces a **v13-plus delta**, never a
delta against 1348700 alone.

## Isolation and tooling

- Project-local verification fixtures only; normal `user://` saving disabled.
- Godot 4.6.3 Linux/X11 used for cloud evidence. The target PC is Windows with
  Godot 4.7.2 and must be checked separately.
- `.godot/`, editor caches, credentials, and personal saves are excluded from
  handoff packaging.
- X11 rendering and ffmpeg recording are available. No installed, supported
  OS-level X11 mouse injector is available; raw XTest/libXtst was not used.

## Review boundary

The accepted review is limited to the existing verification Save/Load controls
and quarter-view actor ordering. It does not add a Cancel UI, new combat,
variable roster behavior, a generic Y-sort, vehicle gameplay, or normal-save
migration.
