# v13-plus Acceptance — GUI Save/Load and Quarter-View Depth

Created: 2026-10-28, cloud-local and not transferred.

## What changed

Only acceptance tooling, captured evidence, result JSON, and documentation were
added on top of v13. No production scene, gameplay, save schema, horizontal
view, worker roster, or depth-order source file changed.

| Area | Result |
| --- | --- |
| GUI save/load | X11 viewport captured. Existing visible Button connections were exercised with programmatic `Button.pressed` signals, explicitly **not** presented as physical mouse clicks. Missing fixture rejection, save, two visible state changes, load, and repeat load passed. |
| GUI negative/cancel path | No Cancel control exists. Missing project-fixture load is the available rejection path. No new Cancel UI was added. |
| Fresh-process restoration | Existing `tools/test_a_recovery_bridge.gd` passed its project-local save → newly launched Godot process restore coverage. This is API/process evidence, not a physical GUI click. |
| Quarter-view depth | X11 frames show the existing verification worker at bridge entry, deck, exit, and service dock. Current visible hierarchy is `rear/deck z2 < CanyonCrewViews z4 < vehicle/checkpoint/cargo front z5`. The native projected Worker layer is hidden. |
| Old fixed-front concern | Not reproduced for current building/rock/bridge scope. No generic Y-sort or production ordering change was applied. |
| Decorative rocks | Valid routes avoid their foreground footprints. No artificial rock-crossing was used as a false witness. |

## Evidence

- GUI frames: `prototypes/recovery_map_lab/evidence/v13_gui_save_load_acceptance/`
- GUI result: `prototypes/recovery_map_lab/results/route_connection_runtime/v13_gui_save_load_acceptance.json`
- Depth frames: `prototypes/recovery_map_lab/evidence/v13_quarterview_occlusion_acceptance/quarterview_{entry,deck,exit,dock}.png`
- Depth video: `.../quarterview_bridge_observation.mp4` — direct X11 capture, 1280×720 H.264, 10 fps, 140 frames, 14.000 seconds; no interpolation or copied frame generation.
- Depth result: `prototypes/recovery_map_lab/results/route_connection_runtime/v13_quarterview_occlusion_acceptance.json`

## Regression evidence

All passed in this isolated Linux Godot 4.6.3 copy:

- `tools/test_canyon_recovery_hub.gd`
- `tools/test_a_recovery_bridge.gd`
- `tools/test_normal_crew_motion_v12.gd`
- `tools/test_normal_crew_motion_runtime_contract_v12.gd`
- `tools/test_v13_gui_save_load_capture_result.gd`
- `tools/test_v13_quarterview_occlusion_acceptance.gd`

## Handoff validation

- The acceptance overlay was clean-applied over a fresh `1348700 → v13`
  restoration using deliberate overwrite only for the overlay files.
- All 24 overlay payload hashes passed; archive integrity also passed.
- The current archive SHA-256 is recorded by its adjacent `.sha256` companion
  file. The archive is cloud-local and was not uploaded to Library.
- A fresh review found no Critical or Important packaging issues. Minor
  provenance note: the GUI result JSON preserves the original cloud-local
  absolute fixture path as evidence. It is never read as a PC save location.

## Still required on PC

Linux/X11 success is not Windows acceptance. On the PC with Godot 4.7.2, verify
real mouse/keyboard Save and Load interaction, actual Cancel behavior if a
Cancel UI is later introduced, audio, performance, display/import behavior,
and normal gameplay input. No Library upload/retry was attempted; this delta
remains cloud-local.
