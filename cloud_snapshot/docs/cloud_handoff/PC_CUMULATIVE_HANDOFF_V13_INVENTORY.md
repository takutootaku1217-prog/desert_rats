# PC Cumulative Handoff v13 — Inventory

Created: 2026-10-28 (cloud-local; not transferred)

## Restore baseline

- Package root expected by the overlay: `recovery-route-bridge-1348700/`
- Baseline commit/provenance: `codex/recovery-map-scale-lab` / `1348700c775822108df91ed48a21ea73bbd9792a`
- Baseline archive: `recovery-route-bridge-1348700.zip`
- Baseline SHA-256: `72dd15252606eeae67e8b55c8a4cbaf8bcc2fc9c72c366771b91457f5350c79d`

## Cumulative source order

The final overlay is assembled from these already-verified source deltas in order, rather than requiring the recipient to apply four separate ZIP files:

1. v10 — `canyon_recovery_hub_cloud_delta_v10_three_cycle_capture_20261028.zip` — `42396ac8a45da31b8cb8fff6ebee21c2da4bbfcfaf3928676ca76d9e7f85979b`
2. v11 — `canyon_recovery_hub_cloud_delta_v11_normal_haul_frame_20261028.zip` — `3357de7b4b7222348759b9d47ccedb5d5078ecdd929b0d231bf22bc979e5387c`
3. v12 — `canyon_recovery_hub_cloud_delta_v12_normal_crew_motion_20261028.zip` — `736e627af5ba7e16b31455c6c950e868e9238723af126bc8db92a0531432855d`
4. Independent side-view motion proof v2 — `mobile_base_motion_proof_v2_cloud_delta_20261028_final.zip` — `e6e047d45277d057b2279ba6e56fdc52efba983ae0d71f8efce424b6654bbad5`

The first three source archives already use `project/...` paths. The motion-proof source archive uses paths relative to `project/`; the cumulative package normalizes those entries to `project/...`.

## Payload audit before packaging

- Unique normalized payload files from the four source deltas: **255**.
- A clean temporary reconstruction of those four layers matched the current project byte-for-byte: **255/255 files, 0 mismatches**.
- Earlier files that are intentionally superseded by later layers remain represented only by their final current bytes in the cumulative overlay.
- The cumulative handoff additionally preserves the five unchanged historical side-view v1 evidence files. They are clearly labeled `v1` and do not replace the current v2 proof.

## Required evidence mapping

- v10 continuous worker evidence: `project/prototypes/recovery_map_lab/evidence/canyon_single_worker_continuous_v10/`
- v11 haul-frame evidence: `project/prototypes/recovery_map_lab/evidence/normal_haul_frame_runtime_v11/`
- v12 normal-crew motion evidence: `project/prototypes/recovery_map_lab/evidence/normal_crew_motion_runtime_v12/`
- Side-view proof v2 video: `project/prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v2/sideview_mobile_base_motion_v2.mp4`
- Side-view proof v2 stills/result: sibling files in the same evidence directory and `project/prototypes/recovery_map_lab/results/sideview_mobile_base_motion_v2.json`
- Historical side-view v1 evidence (preserved only): `project/prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v1/` and `project/prototypes/recovery_map_lab/results/sideview_mobile_base_motion_v1.json`

## Explicit exclusions

The cumulative archive is allowlisted, not a broad project snapshot. It excludes `.git/`, `.godot/`, imported/editor/shader cache, `user://` and personal saves, credentials/authentication data, OS settings, temporary files, unrelated old results/fixtures, `.agents/`, `.superpowers/`, and release/build artifacts. Asset `.import` companions that are part of the approved delta remain included.

## Verification to run after construction

1. `unzip -t` on the cumulative archive.
2. Extract the baseline and the one overlay into a clean temporary directory.
3. Verify the cumulative `SHA256SUMS.txt` before starting Godot.
4. Run the existing headless normal-crew, side-view proof, side-view capture-result, canyon hub, haul-frame, and recovery-bridge checks in the restored copy.

## Scope retained in the handoff

The side-view motion proof is an independent scene using existing side-view source parts. It is not the new six-room concept, a quarter-view asset, a live vehicle/navigation implementation, or a gameplay integration. Linux Godot 4.6.3 evidence does not verify Windows Godot 4.7.2, real input, audio, or performance.
