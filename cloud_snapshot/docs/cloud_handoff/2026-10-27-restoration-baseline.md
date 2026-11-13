# Cloud restoration baseline — 2026-10-27

## Authority and source

- User-authorized continuation of the existing 流動拠点サバイバル work. This is not a replacement game or a change to the old workspace main.
- Restored from Library package recovery-route-bridge-1348700.zip. Source archive SHA-256 was verified as 72dd15252606eeae67e8b55c8a4cbaf8bcc2fc9c72c366771b91457f5350c79d.
- Package manifest verification passed before any local change: 532 files, baseline branch codex/recovery-map-scale-lab, baseline commit 1348700c775822108df91ed48a21ea73bbd9792a.
- The archive intentionally has no .git. No history is synthesized, no GitHub push/main update/publication is authorized, and all later files are local cloud deltas from this verified archive.

## Local environment observed

- Project settings: Godot feature target 4.7, GL Compatibility renderer, 1280×720 viewport, nearest texture filtering.
- Installed cloud executable: Godot 4.6.3.stable.official.7d41c59c4; this is not a Windows 4.7.2 verification.
- ImageMagick is available. Although Xvfb is absent, an Xorg dummy driver was used to provide a temporary 1280×720 display; the documented bridge launcher drew a real existing game frame and X11 capture succeeded. This is Linux/llvmpipe evidence only.
- Baseline diagnostics successfully ran import, a_recovery_bridge, and a_recovery_outpost on Godot 4.6.3. The wrapper reports failure only because this deliberately history-free archive has no .git metadata.

## Reference-image status

The specified Library reference JPEG was prepared through the official Library materialization route, then retried once to the explicit local destination after a failed transfer. Both signed-transfer materializations failed with the helper's download failed result; no further retry is permitted for this request. It is therefore not available for pixel-level inspection in this cloud run.

The written placement instructions describe required scene content, but they do not substitute for the reference image. Parent instruction after this failure explicitly blocks art implementation and material creation until the actual JPEG pixels reach this consumer environment through a supported official handoff.

Parent then supplied a fresh official Library ZIP delivery, canyon-reference-delivery.zip (library file libfile_6220c61a82e48191ba8e1d752eb8baea; expected ZIP SHA-256 40db094ecbed6a23907eb86bfa0815f599a3c3c18ab635f56419d8fa0feefd2d). Its official prepare-materialize response also had workspace_path null and the unmodified returned transfer failed through the same official helper with download failed. The explicit destination did not exist afterward, so no ZIP hash, inner SHA256SUMS, or reference pixels were checked. No retry, URL guess, or alternate access route was used.

The user subsequently attached two reference images directly to the active task. Their actual pixels were inspected in the conversation and replaced the unavailable Library JPEG as the permitted art baseline. The cloud implementation records their derived palette, composition, scale, and exclusions in `CANYON_RECOVERY_HUB_REPORT.md`; their title strips, labels, and explanation panels were not copied into the game.

## Delta recording

At completion, docs/cloud_handoff/CLOUD_CHANGESET_MANIFEST.json will enumerate only cloud-created/changed files and their SHA-256 values. The original MANIFEST.json remains the immutable restored-baseline record.
