# Normal Crew Motion v12 — Verification Handoff

**Status:** This is a bounded normal-role presentation checkpoint. It does
not claim final worker art, all-role animation, vehicle motion, Windows
validation, or completion of the game.

## Scope actually changed

`CanyonCrewViews` remains a read-only mirror of the existing
`RecoveryRouteConnectionSession`.

- All normal v2 poses now use measured visible-boot anchors: idle `(28,52)`,
  walk `(28,49)`, harvest `(32,55)`, and carry `(28,50)`. This removes the
  old pose-switch foot jump without changing route coordinates or cargo.
- Only an empty-handed normal `harvest` actor uses the existing replaceable v3
  four-frame walk bank at 9fps and four-frame harvest bank at 8fps.
- A normal carrying actor, normal `dock_wait`, carrier, and escort remain on
  v2. The v3 carry bank still lacks west-facing art; the v3 unload bank is
  composed for the single-worker service dock and was deliberately not
  applied to normal mode.
- No session, Main, save, route, resource, balance, mobile-base, or six-room
  source file changed.

The user-provided worker candidate images were not adopted. The v3 material
used here is the pre-existing, replaceable verification art.

## Direct runtime evidence

The before/after recordings are ordinary `normal_roles` sessions with seed
`104729`, the same entry resources, three existing roles, one dock,
`outpost_enabled=false`, and the gate closed. They are neither a
`single_worker_demo` nor the old deterministic 0.2-second still harness.

| Evidence | Renderer | Direct video | Runtime trace |
| --- | --- | --- | --- |
| `before/normal_crew_motion_before.mp4` | v11 static v2 | X11 H.264, 1280×720, 10fps, 120 frames, 12.000s | 119 post-draw samples; 11.870s session span; 330 Godot process frames |
| `after/normal_crew_motion_after.mp4` | v12 harvest v3 | X11 H.264, 1280×720, 10fps, 120 frames, 12.000s | 119 post-draw samples; 11.900s session span; 285 Godot process frames |

The 10fps value is only the observer/video cadence. The trace separately
shows that Godot processed more frames than the 119 observations, so it is
not represented as the gameplay update rate.

For the after trace, the observed walk frames are
`walk_east_1`, `walk_northwest_0..3`, and `walk_west_0..3`; the harvest
frames are `harvest_0..3`. The first observed walk is at 0.071s, harvest at
4.372s, loaded v2 carry at 5.135s, and a depot increase with an empty-handed
worker at 8.666s. Every sampled foot point matches the normal map projection
within 0.01px, at one display scale, and cargo visibility matches the
authoritative `carry_n` state while conservation remains true.

Both MP4s were independently decoded with `ffprobe` and `ffmpeg framemd5`.
Each has 120 decoded frame rows and no three-frame frozen run; the local
inspection observed 120 distinct whole-frame hashes per recording. This is
evidence of a live direct recording, not AI-generated or interpolated video.

The X11 capture console emitted a transient x11grab image-data warning during
the original run. The finalized files nonetheless independently decode to the
dimensions, duration, codec, frame count, and frame-digest contract above.

## Baseline provenance

The v2-before output was captured from an isolated temporary copy of the
current project after replacing only
`scenes/canyon/components/canyon_crew_views.gd` with that file extracted from
the verified v11 archive:

```text
canyon_recovery_hub_cloud_delta_v11_normal_haul_frame_20261028.zip
SHA-256 3357de7b4b7222348759b9d47ccedb5d5078ecdd929b0d231bf22bc979e5387c
entry project/scenes/canyon/components/canyon_crew_views.gd
entry SHA-256 82a38763f996a8a90c2d449a7166c17eda593d129e11149439f5a1d499df7af2
```

The live v12 project and its evidence were not overwritten during that
baseline capture. The before JSON carries this provenance as data, and the
runtime-contract test rejects a baseline without the same archive and entry
hashes.

To reproduce the comparison later, first checksum-verify v11, copy the
integrated project to an isolated temporary directory, extract only that v11
crew-view entry into the copy, run the tagged X11 capture there with
`NORMAL_CREW_CAPTURE_TAG=before`, then run the same tagged capture in the
current v12 project with `NORMAL_CREW_CAPTURE_TAG=after`. Do not use the tag
alone to claim a v2 baseline: the tag only chooses an output path; the
renderer source must be the verified v11 entry.

## Verification boundaries

The v12 tests check all normal session actors, not just `worker:0`:

- v3 is permitted only for an empty-handed harvest actor in walk or harvest;
  all carry, dock, carrier, escort, and other normal-role samples remain v2.
- Presentation refresh is compared against the complete serialized session
  dictionary, including actors, resources, relay, depot, dock, routes, events,
  and elapsed state. It must not write authority data.
- The capture source is statically checked from
  `V12_RUNTIME_RECORDING_NO_MANUAL_TICK_BEGIN` onward; any manual
  `field._process`, `session.tick`, or adapter tick would fail the contract.
- The runtime contract opens the locally preserved v11 ZIP, hashes its bytes,
  extracts the recorded crew-view entry with `unzip -p`, and hashes those
  bytes before accepting the static baseline provenance. A different local
  archive location must be passed through `V11_NORMAL_HAUL_FRAME_ARCHIVE`;
  no download or alternate transfer path is attempted.
- The v12 runtime contract validates both raw MP4s with `ffprobe` and
  `framemd5`, as well as the JSON trace and unmodified 1280×720 screenshots.

## Deferred / not validated

- Natural animated carry, dock unloading, carrier/escort animation, final
  worker-art adoption, and complete direction banks.
- Normal-role bridge traversal as a new animation proof. Existing bridge
  collision/projection regressions remain covered, but this focused recording
  used the normal closed-gate bypass state to observe the role loop.
- Windows / Godot 4.7.2, real mouse input, audio, performance, and rendering
  driver behavior. Linux Godot 4.6.3 X11 success is not a Windows result.
- New map/building/enemy/growth features and all mobile-base or six-room art.

## Synchronization order

This is a later overlay, not a full game archive. Apply in order:

1. verified v10 cumulative checkpoint;
2. verified v11 normal-haul-frame overlay;
3. this v12 normal-crew-motion overlay.

Do not apply v12 to the original 1348700 restoration alone. The v12 archive
contains only the files listed in its manifest, excludes `.godot`, personal
saves, Git metadata, and unrelated Linux-generated files, and does not touch
PC, GitHub, or the personal Library. The Library upload remains intentionally
unattempted after its earlier authentication block.
