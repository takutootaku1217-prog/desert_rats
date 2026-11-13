# Start Here — v13-plus Acceptance Delta

This is a **small overlay on v13**, not an independently restorable project.
Do not apply it directly to the old 1348700 baseline by itself.

## Required order

1. Verify and restore `recovery-route-bridge-1348700.zip` (baseline commit
   `1348700c775822108df91ed48a21ea73bbd9792a`).
2. Apply `canyon_recovery_hub_pc_cumulative_v13_20261028_final.zip` to that
   restored root. Verify the required v13 archive SHA-256:
   `c48b32bed9d029facda48812e97ad3523d45be66dadbef5b5398ea8811cbc35f`.
3. Extract this acceptance delta over the same v13 root, allowing only this
   delta's listed files to overwrite while preserving the `project/` path.
   Verify this delta's `SHA256SUMS.txt` before launch.
4. Open `project/` once with the target Godot editor so it creates its local
   `.godot/` import/global-class cache. Do not copy a cloud `.godot/` folder.

## First PC checks (Windows / Godot 4.7.2)

- Run the canyon verification scene normally and click **検証保存**, change the
  two displayed route/dock settings, click **検証読込**, repeat it, and confirm
  actual mouse/keyboard behavior. The cloud test used Button signals and is
  not a physical-mouse acceptance.
- Verify the bridge worker's entry/deck/exit and service dock visually at the
  PC's native renderer, then test audio, performance, and display/import.
- Keep normal `user://` saves separate from the project-local verification
  fixture. This delta does not add a Cancel UI; if one is introduced later,
  test it as a new feature.

## Commands after editor import (optional diagnostics)

From the `project/` directory:

```powershell
godot --headless --path . --script tools/test_v13_gui_save_load_capture_result.gd
godot --headless --path . --script tools/test_v13_quarterview_occlusion_acceptance.gd
godot --headless --path . --script tools/test_canyon_recovery_hub.gd
godot --headless --path . --script tools/test_a_recovery_bridge.gd
```

The first two validate captured Linux/X11 artifacts and structural contracts;
they do not substitute for the interactive Windows checks above.

## Scope

This overlay contains only acceptance scripts, X11 capture evidence, JSON
results, and documents. It makes no production code correction because the
current building/rock/bridge ordering concern did not reproduce.
