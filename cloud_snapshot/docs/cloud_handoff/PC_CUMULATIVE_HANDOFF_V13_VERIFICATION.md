# PC Cumulative Handoff v13 — Verification

Created: 2026-10-28 (cloud-local; not transferred)

## Package identity

- Cumulative archive: `canyon_recovery_hub_pc_cumulative_v13_20261028_final.zip`
- Required baseline root: `recovery-route-bridge-1348700/`
- Required baseline commit: `1348700c775822108df91ed48a21ea73bbd9792a`
- Required baseline ZIP SHA-256: `72dd15252606eeae67e8b55c8a4cbaf8bcc2fc9c72c366771b91457f5350c79d`
- Source layering captured by the cumulative overlay: `v10 -> v11 -> v12 -> sideview-motion-v2`.
- Final package contents: 265 hashed payload files plus `SHA256SUMS.txt`; the archive SHA-256 is supplied separately in the adjacent `canyon_recovery_hub_pc_cumulative_v13_20261028_final.zip.sha256` companion file because an archive cannot hash itself internally.

## Clean-restoration method

1. Extracted the supplied baseline ZIP into a new temporary directory.
2. Applied the normalized cumulative overlay into its `recovery-route-bridge-1348700/` root.
3. Before any Godot launch, compared every overlay file with its destination counterpart: **264 files, 0 mismatches** at the first staging pass. The final archive adds this verification document and an updated hash list; the final archive is separately integrity-checked before release.
4. Deliberately left the generated `.godot/` import/editor cache out of both the overlay and the final package.

## Godot initialization finding

Running a GDScript test directly in an entirely fresh copy initially failed to resolve global `class_name` symbols `SaveGame` and `GameData`. The source files and `project.godot` were byte-identical to the current worktree; the difference was that the live cloud project already had Godot's generated global-class cache under `.godot/`.

After one normal editor/import bootstrap in the disposable copy (`godot4 --headless --path . --editor --quit`), the same test passed. This is not fixed by shipping `.godot/`; opening the project normally in the Godot editor creates the needed cache. For reproducible headless verification, perform the one-time editor/import bootstrap first.

## Clean-copy headless checks

All of these ran against the restored temporary copy after the editor/import bootstrap, using isolated XDG directories:

| Check | Result |
| --- | --- |
| `tools/test_canyon_recovery_hub.gd` | PASS |
| `tools/test_a_recovery_bridge.gd` | PASS — three A→C→A cycles, closure/reopen, capacity, and project-local save/reload checks |
| `tools/test_normal_haul_frame_progression.gd` | PASS |
| `tools/test_normal_crew_motion_v12.gd` | PASS after bootstrap |
| `tools/test_mobile_base_motion_proof.gd` | PASS |
| `tools/test_mobile_base_motion_capture_result.gd` with `MOBILE_BASE_MOTION_PROOF_CAPTURE_TAG=v2` | PASS |

## Included side-view evidence

- Current independent proof: `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v2/sideview_mobile_base_motion_v2.mp4`.
- Supporting v2 stills and result JSON are included alongside it.
- The historical v1 video/stills/result are also retained under their original `..._v1` paths for provenance only; they do not supersede v2.

## Scope and remaining PC checks

- The side-view proof is an old-sideview-parts **independent** scene. It does not implement the new six-room concept, quarter-view art, live vehicle movement, or new gameplay behavior.
- Linux Godot 4.6.3 headless evidence is not a Windows Godot 4.7.2 result.
- Windows editor/import behavior, real mouse/keyboard input, audio, and performance remain to be checked on the PC.
- No Library upload/retry was performed; the archive remains cloud-local pending the PC handoff.
