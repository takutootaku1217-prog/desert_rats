# Sideview Mobile-Base Motion Proof v1 — Verification

> Historical v1 evidence is preserved.  The current proof and review-corrected
> integer gun anchors are documented in
> `SIDEVIEW_MOBILE_BASE_MOTION_PROOF_V2_VERIFICATION.md`.

## Scope and status

This is a **separate sideview motion proof**, not a replacement vehicle, map
movement feature, or six-room implementation.  It is launched directly from
`prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_proof.tscn`.
`project.godot` still launches `scenes/main.tscn`.

The proof uses only the existing, verified `assets/fortress_moving` body,
wheel, shutter, crane, gun, and flag sources through `LargeVehicleLayout`.
It does not use the blocked Library concept image, the fixed quarter-view
`mobile_base` composition, or an invented second side.  It is explicitly one
verified sideview orientation.  The six logical slots are read-only contract
data (`u3,u1,u2,l3,l1,l2`), not a new interior or room-state system.

## Runtime evidence

The following are unmodified outputs of the standalone Godot X11 viewport at
1280×720.  The MP4 is direct `ffmpeg x11grab` at 10 fps, not generated,
interpolated, cropped, scaled, or speed-adjusted imagery.

| Evidence | Project path | SHA-256 |
| --- | --- | --- |
| parked PNG | `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v1/sideview_mobile_base_parked.png` | `97e2c4b3a356a6202cd3d40f97778acf1b1336b8094de6ea28fa328c58388d7d` |
| rolling PNG | `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v1/sideview_mobile_base_rolling.png` | `2561267ee788a1068540db17966389e05956094909801b78699eba2d8950ebc9` |
| stopped PNG | `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v1/sideview_mobile_base_stopped.png` | `4d5f4ac48b4ec23f25b5181ab06257f40f5ca43fd4ffff2409849f9a51457fab` |
| 7-second MP4 | `prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v1/sideview_mobile_base_motion_v1.mp4` | `5209f91d407884dbc91f0c52dda7c24b4175c9e0a6d523c4a05cc5a1f7e729bf` |
| capture state/metadata | `prototypes/recovery_map_lab/results/sideview_mobile_base_motion_v1.json` | `996f36d4096fd578dd9e602b17dea1dc91cd6c3ee579cf34ca1e0ee2c68b905a` |

Independent `ffprobe` readback reports H.264 video-only, 1280×720, 10/1 fps,
70 decoded frames, and 7.000 seconds.  Direct `ffmpeg -f framemd5` decoding
found 70 rows with 70 distinct frame hashes.  The direct recorder printed one
X11 dummy-display image-event warning, but it exited successfully and the
independent decoded-frame checks above pass; it is not hidden or treated as a
Windows result.

## What is visible and what drives it

The proof cycle is 1.5 s parked → 3.0 s rolling at 42 display px/s → 1.5 s
parked.  The sideview vehicle remains framed, consistent with the existing
sideview language; its road stripes/ballast scroll by the same signed distance
that turns all six wheels.  Thus the wheels cannot appear to move while the
ground is static.

- Parked capture: distance `0`, wheel angle `0`, sprung offset `0`.
- Rolling capture: distance `21.486542`, wheel angle `0.38368825`, sprung
  offset `+2 px`.
- Stopped capture: distance `126`, wheel angle `2.25`, sprung offset `0`.

Wheel centers stay ground-anchored.  Only the body, shutter, crane, guns, and
flag get the bounded `-2..+2 px` sprung offset.  The crane/guns/shutter remain
whole static parts because the supplied images do not establish safe
articulated/crane/garage behavior.  The flag uses integer-bounded strips with
its pole edge fixed.  Exhaust puffs, rolling dust, and a restrained lamp glow
are procedural proof effects; no separate smoke or light asset is claimed.

Read-only review of direct video frames confirmed the parked/rolling/stopped
titles, road travel, wheel rotation, and no whole-body drifting off the frame.
The small effects are intentionally subtle at full-frame scale.  Raw rotation
of the supplied high-resolution wheel is not a pre-baked rotation atlas, so
nearest filtering cannot mathematically promise zero edge shimmer; no severe
flash was seen in the reviewed direct frames, but a final production guarantee
requires approved directional/rotation-frame art.

## Delta, filtering, and test results

`MobileBaseMotionModel` derives distance, wheel angle, road scroll,
flag/light time, exhaust index, and sprung offset from elapsed delta time.
Its focused test advances the same ten-second sequence at 30 Hz and 60 Hz and
confirms equal travel/wheel phase plus matching flag/light/exhaust/suspension
state.  The renderer forces `TEXTURE_FILTER_NEAREST`; its art origin, wheels,
road marks, flag source/destination strip boundaries, and procedural effects
are integer-snapped.  The existing body source region preserves its documented
fractional display aspect rather than distorting it just to force an integer
rectangle.

Commands run on Linux Godot 4.6.3:

```text
godot4 --headless --path . --script tools/test_mobile_base_motion_proof.gd
godot4 --headless --path . --script tools/test_mobile_base_motion_capture_result.gd
godot4 --headless --path . --script tools/test_normal_crew_motion_v12.gd
DISPLAY=:99 godot4 --path . --script tools/capture_mobile_base_motion_proof.gd
```

All three tests exit 0.  The first focused test was intentionally RED before
the model/scene existed (two missing-file assertions), then GREEN.  Capture
integrity independently checks all three PNG dimensions, phase snapshots,
video dimensions/rate/frame count, and decoded unique frames.  The normal
crew regression passed unchanged, including C-quarry travel, normal roles,
read-only crew presentation, cargo/session conservation, and safe v2 fallbacks.

The X11 run used Linux Godot 4.6.3, a dummy `:99` display, Mesa llvmpipe, and
dummy audio fallback.  It is **not** Windows/Godot 4.7.2, real mouse/audio,
or performance validation.

## Non-interference check

The following original gameplay files still exactly match the supplied
baseline manifest, demonstrating that this proof is additive:

| Baseline file | SHA-256 |
| --- | --- |
| `project.godot` | `7c44a0dc363cf2f04ea9f6aa2aeaeaf6642f05e64129766d234abf0858ae9156` |
| `data/large_vehicle_layout.gd` | `2a15f3ccaa36e55970ff37a3a155883d3550d044d8dffd22e902d0f642e049bb` |
| `data/rooms.gd` | `d74f788b722906168984b93321778635a65f15dee3da8eddaf0f84e553c62abe` |
| `scripts/base.gd` | `3da860023ea6691399ca079260b8fef5294b55c698e9b5b81c2ddb9f40a0480a` |
| `scripts/base_exterior.gd` | `ea3b3b4500ff15e19e5aab1aff82ffd95fed3c4c73ad4351eb807fbbab105bed` |
| `scenes/main.tscn` | `633fe2b0ca545a5750e3b2c552c966ccdb6a94fe6d5cc00ac8a921eedb8af991` |

No PC, Library retry, GitHub, main branch, personal save, room assignment,
vehicle loadout, route, navigation, or game session was touched.  Library
upload remains deliberately pending until the known authentication failure is
explicitly resolved.

## Remaining work outside this proof

- Approved left/right/front/rear/quarter-view body and component art, with
  per-view wheel/occlusion/exhaust/light anchors.
- A pre-baked rotation atlas or new wheel animation source if raw nearest
  rotation shimmer is unacceptable.
- Final room-to-exterior art agreement after the separate six-room concept is
  available through an authorized path.
- Windows/Godot 4.7.2 launch, real input, audio, native performance, and any
  integration of this isolated proof into live vehicle/map movement.
