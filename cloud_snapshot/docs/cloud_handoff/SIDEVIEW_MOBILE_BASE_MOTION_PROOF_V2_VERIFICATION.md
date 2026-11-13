# Sideview Mobile-Base Motion Proof v2 — Verification

## Current proof boundary

This is the current, additive **independent sideview motion proof**.  Target
scene: `res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_proof.tscn`.
Run it with:

```text
godot4 --path . --scene res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_proof.tscn
```

It does not replace `scenes/main.tscn`, construct `Main`, touch a route,
session, save, room assignment, vehicle loadout, or the quarter-view map.
It uses only the existing `fortress_moving` sideview body, wheel, shutter,
crane, gun, and flag source parts via `LargeVehicleLayout`.

Coverage is deliberately **one verified sideview orientation** only.  No
right/front/rear/quarter asset, mirrored side, 3D transform, free map vehicle,
or six-room interior art is claimed.  The logical slots
`u3,u1,u2,l3,l1,l2` are read-only contract data only.  The blocked Library
concept image was not retrieved or used.

## v2 correction over preserved v1

v1 evidence remains intact.  v2 fixes its one review finding: the primary and
secondary whole-gun draw origins are now rounded to integer display pixels
before nearest-filtered rendering.  Gun source **sizes** retain their approved
fractional aspect ratio; only their origins are snapped.  The focused test
proves both gun origins are integer values.

The post-capture integrity test also now verifies every contiguous parked span
keeps its wheel angle fixed, every sample has `road_scroll_x == -distance`,
and every wheel angle equals `fposmod(distance / 56, TAU)`.  It directly
decodes a rolling MP4 frame and verifies the proof title/body/road signature,
so a different X11 desktop cannot satisfy frame-count/hash checks alone.

## Actual v2 runtime evidence

These files are direct, unmodified Linux X11 Godot viewport outputs.  The MP4
is direct `ffmpeg x11grab` at 10 fps; there is no AI frame generation,
interpolation, crop, scale, duplicate insertion, or speed change.

| Evidence | Project path | SHA-256 |
| --- | --- | --- |
| parked PNG | `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v2/sideview_mobile_base_parked.png` | `2d56986c342e5fc9621a0c9703e34e834cd2887c55fa02cfd5901681b8a1f785` |
| rolling PNG | `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v2/sideview_mobile_base_rolling.png` | `cf4944c92d8c70c883349400297e1660c322ff870730635f37e09daeb246cdd4` |
| stopped PNG | `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v2/sideview_mobile_base_stopped.png` | `385178be4efc3bd72da13b6181ef801f4a0dab73eabe87d2f05c27bc90bcdfc8` |
| 7-second MP4 | `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v2/sideview_mobile_base_motion_v2.mp4` | `96a087580c277523a3370b2e284e004cff9e334f5f6fef5068d3e4c35938d8af` |
| capture JSON | `prototypes/recovery_map_lab/results/sideview_mobile_base_motion_v2.json` | `2fddbab220b8847fd3d6bc1422a620a70dc64fba517ab0703189af6ba3059cc2` |

Independent readback: H.264 video-only, 1280×720, 10/1 fps, 70 decoded
frames, 7.000 seconds; direct framemd5 decoding finds 70 rows and 70 distinct
hashes.  The explicit capture metadata records Linux, Godot
`4.6.3-stable (official)`, X11, and that Windows/Godot 4.7.2, real input,
audio, and performance remain unverified.  The dummy X11 recorder emitted one
nonfatal image-event warning; the resulting movie independently decodes and
passes the content-signature/integrity checks.

The captured proof is 1.5 s parked → 3.0 s rolling at 42 px/s → 1.5 s
parked.  The vehicle remains framed; road stripes and ballast move from the
same signed distance that drives all six wheel angles.  Thus it does not show
a stationary road with spinning wheels.  Captured phases:

| View | Phase | Distance | Wheel angle | Sprung offset |
| --- | --- | ---: | ---: | ---: |
| parked | parked | 0 | 0 | 0 px |
| rolling | rolling | 21.114655 | 0.377047 | +2 px |
| stopped | parked | 126 | 2.25 | 0 px |

Wheel centers remain ground-anchored.  Only the body, shutter, crane, guns,
and flag receive the bounded `-2..+2 px` sprung offset.  Crane, guns, and
shutter remain static whole parts because the supplied art establishes no safe
crane articulation, gun traverse, or garage state.  Flag fabric waves with a
fixed pole edge and integer strip boundaries.  Exhaust, rolling dust, and
lamp glow are small procedural proof effects rather than claimed new assets.

Raw rotation of the supplied high-resolution wheel has no pre-baked rotation
atlas.  Nearest filtering and integer origins remove avoidable placement blur,
but cannot mathematically guarantee zero wheel-edge shimmer at all angles.
Read-only review of direct rolling/stopped frames found no severe flash; a
production guarantee needs approved rotation-frame art.

## Verification

Fresh Linux Godot 4.6.3 commands:

```text
godot4 --headless --path . --script tools/test_mobile_base_motion_proof.gd
MOBILE_BASE_MOTION_PROOF_CAPTURE_TAG=v2 godot4 --headless --path . --script tools/test_mobile_base_motion_capture_result.gd
godot4 --headless --path . --script tools/test_normal_crew_motion_v12.gd
DISPLAY=:99 godot4 --path . --script tools/capture_mobile_base_motion_proof.gd
```

The focused proof test, v2 post-capture test, and unchanged normal-crew
regression exit 0.  The focused test includes the analytical 30 Hz/60 Hz
comparison: equal travel/wheel phase after six seconds and equal
flag/light/exhaust/suspension state after ten seconds.  This proves
delta-based motion equivalence, not a Windows performance result.

## Non-interference

The baseline manifest hashes still match for the original gameplay entry and
vehicle/room source: `project.godot`, `data/large_vehicle_layout.gd`,
`data/rooms.gd`, `scripts/base.gd`, `scripts/base_exterior.gd`, and
`scenes/main.tscn`.  The proof is composed only of new prototype, test,
capture, evidence, and documentation files.  No PC, GitHub/main, Library
retry, user save, normal game scene, or external publish action occurred.

Remaining outside this proof: approved directional/quarter vehicle art and
anchors, a rotation atlas if raw wheel shimmer is unacceptable,
room-to-exterior art integration, live map movement/navigation, and all
Windows/Godot 4.7.2 real-input/audio/performance testing.
