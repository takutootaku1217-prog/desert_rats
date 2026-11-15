# Mechanical explosion, 2026-11-15

## Scope
- Base: `e2bb92444985b13919e31ddaae8435693bb8f571`.
- Visual-only original mechanical effect. No combat numbers, saves, random breakdowns or existing effects changed.
- The current game has no mechanical-destruction event. This provides a callable component and independent preview scene, NOT a new gameplay destruction mechanic or an automatically integrated combat effect.
- Source: supplied animated HTML (rolling pixel flame/smoke). Enhanced rotating nuts, threaded bolts, toothed gears, red armor fragments and a short secondary flash. No Nintendo image assets used.
- A 54-frame, 30 fps transparent atlas is **generated from code**, then played by Godot. It is not a runtime procedural Godot shader and not a scaled static image. Current atlas uses seed 7. HTML permits other seeds. HTML camera shake is preview-only; Godot component does not shake the camera.

## Run
```sh
godot --path cloud_snapshot res://scenes/mechanical_explosion_preview.tscn
```
Click/Space repeats. At most 8 active effects per parent, then oldest is retired. Contact origin follows the caller's local coordinates. Smoke rises; do not rotate the entire component. The default effect is 2x source pixel scale; showcase uses 4x. No sound added.

Call from a future confirmed mechanical-destruction event:
```gdscript
const MechanicalFX = preload("res://scripts/mechanical_explosion.gd")
MechanicalFX.spawn(fx_parent, local_ground_position, 2.0)
```
Do not call from normal animal kills merely to expose the effect. Add event-specific tests before connecting it.

## Regenerate
Needs Node.js and `@napi-rs/canvas` (external build tool only; not a Godot runtime dependency).
```sh
node cloud_snapshot/tools/vfx/export_mechanical.cjs
```
Default updates `cloud_snapshot/assets/effects/mechanical_explosion.png`. Intermediate frames and HTML preview go under `assets/effects/mechanical/` and must not be committed. Explicit output-directory argument writes all files including atlas there. HTML runs offline in a browser, with pause/seek/replay/layer switches and seeded variations.

## Verification
- Engine installed here: Godot **4.6.3**, Linux; not claimed as 4.7.2 or Windows.
- Red: component existence test failed before component implemented. Green: component checks pass (origin, first frame, frame advancement, negative delta, 8-instance bound, lifetime deletion).
- GUI: launched actual Godot preview via cloud desktop, pressed Space, observed orange fire, dark smoke, gear/armor flight and successful rendering with alpha on dark ground.
- Atlas: 2880x1080, 9x6 cells, 320x180 each. Transparent margins, changing frames, fully transparent tail. 1.8 second lifetime.
- Independent review found exporter default atlas path mismatch; fixed so regeneration updates runtime atlas.
- Existing bounded prototype suite: 119 existing cases plus import all exit 0 (120 results), with zero SCRIPT ERROR / ERROR lines or reported test failures. One existing diagnostic line named FAIL_MENU_RECT reports a failure-menu rectangle; the corresponding test explicitly ended failures=0. The new component test passed separately (7 checks) and is registered for future full runs. This is not certification of every legacy/missing suite or a Windows/multi-device performance test.
- Current design sources checked 2026-11-15: layered ground/flame/debris/smoke, rising smoke, visual/gameplay separation. Private source identifiers are intentionally not published.

## Handoff
No integration into main or other Claude working branch. To review, use this branch/change package against the base SHA above. Reconcile any newer Claude changes before merging. Future task: select actual mechanical destruction event and verify effect scale/occlusion there.
