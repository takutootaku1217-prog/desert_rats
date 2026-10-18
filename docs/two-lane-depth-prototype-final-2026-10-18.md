# Two-lane depth-strip prototype — final record

Date: 2026-10-18  
Workspace: `C:\Users\user\Documents\Codex\2026-10-18\task-3\desert_rats`  
Branch: `gpt/prototype-ground-two-lanes`

## Scope and switch

This is an opt-in prototype for the existing `south_oasis` harvest location only.
Start Godot with the user argument `two-lane-depth-prototype` to enable it. Normal
starts, every other region, roads, the moving-base map loop, and interior movement
keep their existing one-line coordinates.

The outdoor strip has exactly two readable resting lanes: back `Y=570` and front
`Y=625` (55 px apart). Characters may move diagonally between any two points in
this shallow strip; there is no crossing X, bridge, third lane, free planar
movement, terrain-obstacle system, or 3D movement.

At 1280x720, the NavigationBar begins at screen Y=650. The front anchor's feet
are therefore 19 px above it, rather than hidden by the HUD. Selection uses the
InputEvent coordinate after camera conversion, and a regression sends a real
Viewport mouse event through `_unhandled_input` (not `_pick_worker_at` directly).

The existing ramp remains the only route between outdoors and the base. Resources,
fauna, and ecological enemies generated at `south_oasis` use the two anchors.
Save/load normalizes WorldTrip-managed outdoor records for that active prototype
location without adding a save-schema field; interior crew positions and unrelated
test fixtures are preserved.

## Behaviour checked

- CharacterAI reserves a front-lane vein, moves continuously through depth,
  gathers, carries via the existing ramp, and unloads.
- Normal y-sort and feet shadows distinguish front/back. The existing position
  picker selects same-X workers by the clicked visible depth.
- A same-X opponent in the other lane is not hit before physical 2D distance is
  closed. Pursuit moves directly through the strip at the current X.
- A personal return crosses the strip, uses the ramp, and does not resume combat
  or gathering.
- Normal startup, roads, and other regions remain outside the strip even though
  the opt-in metadata exists in the running Main scene.
- Save/restore preserves a middle-of-band Y, a ramp-in-progress worker, and an
  indoor worker; it clamps old outside-Y WorldTrip records only at `south_oasis`
  and leaves a non-target region unchanged.

## Verification and evidence

Windows Godot `4.7.2.stable.official.ed1daf0bf`, isolated APPDATA:

```powershell
& '<Godot console exe>' --headless --path . --fixed-fps 60 `
  -s res://tools/test_two_lane_live_integration.gd -- two-lane-depth-prototype
```

Result: `DEPTH_ROLLOUT_OK`.

Run the explicit scope checks separately (the first one intentionally has no
prototype argument):

```powershell
& '<Godot console exe>' --headless --path . --fixed-fps 60 `
  -s res://tools/test_two_lane_scope_isolation.gd
& '<Godot console exe>' --headless --path . --fixed-fps 60 `
  -s res://tools/test_two_lane_scope_isolation.gd -- two-lane-depth-prototype
```

Both results: `TWO_LANE_SCOPE_OK`.

Focused isolated-APPDATA regression passed with `source_changed_during_run=false`:
`C:\Users\user\AppData\Local\Temp\desert-rats-two-lane-hud-scope-final\20261018T051855Z-0q2wzg64\results.json`
(`import`, both scope modes, live integration, legacy `save_game`, `world_flow`).
`world_map`, `world_boundaries`, `world_fauna`, `world_scenery`, and
`world_reencounter` were also run from the normal map in bounded batches.

The all-core command begins successfully but this host terminates its process at
about 30 seconds while `town_flow` starts, before Godot's own per-check timeout.
It is therefore **not** reported as a completed core result; rerun core from the
committed branch in a host without that session limit.

Renderer captures use the Intel Iris Xe OpenGL Compatibility renderer (not
headless; no OS-input video):

- `docs/two-lane-world-rollout-evidence-2026-10-18/one-line-baseline.png`
- `docs/two-lane-world-rollout-evidence-2026-10-18/two-lane-normal-map.png`
- `docs/two-lane-world-rollout-evidence-2026-10-18/live-depth-gather.png`
- `docs/two-lane-world-rollout-evidence-2026-10-18/live-depth-combat-approach.png`
- `docs/two-lane-world-rollout-evidence-2026-10-18/live-depth-return.png`

The one-line and two-lane comparison uses the same small set of workers and
resources; it adds no resources, rewards, or harvesting efficiency.

## Limits

This prototype intentionally does not establish a normal-map-wide rollout. A wider
rollout needs separate economy-timing, saved-world, UI-selection, obstacle, and
manual-input review. Rescue and checkpoint mechanics are outside this change.
