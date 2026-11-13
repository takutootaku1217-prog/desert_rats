# Normal Haul Frame Progression Verification — v11

**Status:** This cloud slice is complete as a normal-role verification and
handoff checkpoint. It is not a claim that the whole game, final worker art,
or vehicle-motion work is complete.

## What this proves

The existing game paths were exercised in this order, without adding an
economy, recipe, role, or fake session inventory:

1. A normal `harvest` / `carry` / `escort` C-quarry session returns actual
   iron ore, recalls, and commits once into the existing base inventory.
2. At A, the existing build, transfer, smelt, craft, and work-support APIs
   build a workbench, smelt that iron, craft one Haul Frame, and equip it.
3. A separate next C session is created in ordinary normal-role mode. It is
   not `single_worker_demo` and uses the immutable entry actor snapshot.

The repeatable fixture starts from an **existing-progress checkpoint** with
one hide from the ordinary hunting/carcass chain and five retained wood. C
does not produce hide, so this is deliberately not labelled a bare-new-game
or C-only recipe path. The first C return supplies the iron ore; smelting it
uses three existing tank-fuel units.

## Same-condition comparison

All three cases use independent deterministic Mains with the same seed
`104729`, prepared checkpoint, first-sortie residual source, normal role
contract, `outpost_enabled=false`, one dock, 0.2-second fixed ticks, and an
exact 20.0-second / 100-tick second sortie. The baseline must retain source;
the test rejects a window in which every case has already exhausted the mine.

| Measured case | Frame placement | Depot at 20.0s | Source remaining | Carrier relay wait | Result |
| --- | --- | ---: | ---: | ---: | --- |
| Baseline | none | 4 | 7 | 14.0s | comparison control |
| Harvester frame | `worker:0` / harvest | 9 | 0 | 8.2s | selected for this scenario |
| Carrier frame | `worker:1` / carry | 4 | 7 | 14.0s | no measured improvement |

The selected harvester placement is a **scenario-specific** result. It
recovers the finite residual source sooner (+5 depot stock in this window),
but the selected case exhausts that source while baseline and carrier do not.
It must not be described as an unlimited or universal throughput increase.
The carrier result is retained in the evidence rather than omitted: its
unchanged harvester bag left this particular route's measured outcome at zero
improvement.

Existing cost, not a new balance value:

- Workbench: 3 wood.
- Haul Frame: 2 wood, 1 hide, 1 iron.
- First-return iron smelting: 3 tank fuel.

## Visible normal-mode evidence

These are unmodified 1280×720 PNGs read from a live Linux X11 Godot viewport
after `RenderingServer.frame_post_draw`. The capture refuses every display
server other than X11. It drives deterministic session ticks for repeatability
and is still-image evidence only; it does not claim a real-time video or
generated/interpolated animation.

| State | Evidence | Observation |
| --- | --- | --- |
| Redeployed normal HUD | `normal_haul_frame_hud_departure.png` | HUD reads `採掘役`, `背負いフレーム`, and `便5` from `session.actors`. |
| Harvester loaded | `normal_haul_frame_harvester_loaded.png` | At session 5.0s, `worker:0` carries 4 while returning to relay; conservation is true. |
| Depot increased | `normal_haul_frame_depot_after_unload.png` | At session 8.0s, depot is 3 from 0 and cargo has been cleared; conservation is true. |

The standard quarter-view shows the existing transparent 48×48
`item_haul_frame.png` as a separate Sprite2D behind the selected v2 worker.
It is nearest-filtered, 1×, and placed on integer pixels. This is a temporary
equipment readout using an existing asset—not final worker art, an adopted
character design, or an animation replacement. The existing v3
single-worker verification presentation was not changed.

## Authority and regression boundaries

- `RecoveryRouteConnectionSession` and `Main` remain the only cargo, depot,
  routing, craft, and equipment authorities.
- The new normal HUD and support sprite read immutable entry actor snapshots;
  they do not read mutable horizontal workers or write session data.
- The focused progression test rechecks safe all-route closure/reopen,
  project-local save/load, full-storage rejection, recall, and one-time
  commit. The existing full bridge regression rechecks three normal A→C→A
  cycles, cancellation, capacity rejection, and fresh-process fixture restore.
- Normal user saves remain disabled throughout verification.

## Verification run on 2026-10-28 UTC

All below exited `0` under Linux Godot 4.6.3, with project-local
`XDG_DATA_HOME` and `XDG_CACHE_HOME` paths:

```text
godot4 --headless --path . -s res://tools/test_normal_haul_frame_progression.gd
godot4 --headless --path . -s res://tools/test_canyon_recovery_hub.gd
godot4 --headless --path . -s res://tools/test_a_recovery_bridge.gd
DISPLAY=:99 godot4 --path . -s res://tools/capture_normal_haul_frame_progression.gd
godot4 --headless --path . -s res://tools/test_normal_haul_frame_capture_contract.gd
godot4 --headless --path . -s res://tools/test_normal_haul_frame_capture_result.gd
```

The capture-result integrity test verifies the evidence JSON against all
three benchmark rows, the selected actor snapshot, checkpoint, recipe cost,
all three PNG dimensions, conservation, and the live capture entry's full
resource snapshot, three-role contract, dock count, and seed. OS-level mouse
clicking was not attempted; craft/equip and route operations use the existing
game APIs in the deterministic verification harness.

## Evidence hashes

```text
1d66e942010ae5ee745eb66d6c6ceee3687fae18cec0ff614e3828182ede1075  normal_haul_frame_progression.json
ced7ee051ba261af764ed493eb2933e3532b9ff0df1501db69a583d328431ad5  normal_haul_frame_render_capture_v11.json
c73c13860297d01542639351edc837c24ff954e83dc9c67f6b9e670e54624b16  normal_haul_frame_hud_departure.png
d925d0817d5c005351ccf2d8f76d80a8b041a882fdacce4e52748c842471debd  normal_haul_frame_harvester_loaded.png
095b29ae1a03b0940049f7afef69c6090b72fecfce4e06555db66998fb3360b2  normal_haul_frame_depot_after_unload.png
```

## Library handoff status

The versioned v11 ZIP is locally preserved and checksum-verified for the next
PC synchronization. The official update of the existing personal v10 Library
item was blocked during authentication before any byte transfer. A subsequent
read-only check still reported the existing item at version 9, so no v11
Library version is claimed. Do not retry through an alternate upload path;
resume the same versioned Library update only after its authorized helper can
authenticate.

## Deliberately deferred

- Windows / Godot 4.7.2, OS-level mouse input, audio, performance, and
  rendering-driver validation.
- A normal user save made after equipping the frame, followed by process
  restart, load, and C re-entry. `work_support` is a serialized worker field,
  but normal user saves were intentionally disabled for this cloud harness.
- Final all-direction worker art and natural walk/harvest/carry animation.
- New map, enemy, growth, economy, vehicle movement, or mobile-base art
  changes. The later six-room mobile-base structural work remains outside this
  checkpoint.
- The first upgrade's bare-new-game onboarding path: hide still needs the
  existing hunting/carcass progression before C recovery can supply iron.
