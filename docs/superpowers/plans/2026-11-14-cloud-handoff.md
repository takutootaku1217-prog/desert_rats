# Safe Cloud Handoff Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans; implement the tasks and verify their evidence.

**Goal:** Save a bounded, exclusive and recoverable handoff through GitHub without extra credits or modifying game originals.

**Architecture:** An append-only Git coordination branch stores a compact ownership record. Fast-forward-only updates arbitrate concurrent claims; a worker supervisor records stop and checkpoint before transfer. Unknown usage blocks new work. Model-free probes exercise the protocol while provider authentication is unavailable.

**Tech Stack:** Python standard library, Git, existing provider CLIs and Godot runners.

**Progress note:** This is the pre-publication plan snapshot. Live results must be read from the coordination branch and the actual GitHub Actions run; unchecked later steps are not a claim of failure or success.

**Spec:** `docs/cloud-handoff/README.md`, implementing the user's 2026-11-14 requirements.

## Global Constraints

- Candidate SHA `fb3494915dd621d5feccc2ed2718bf3947bacd4c`, entry `cloud_snapshot/project.godot`.
- New branches/copies only; no deletion of originals, force push, secret publication, credit activation or permissions expansion.
- Only new allowlisted operational files are committed; existing game bytes remain unchanged.
- Fresh official remaining quota must exceed 10 percent for every applicable window; missing, stale, nonfinite, expired and warning/rejected evidence fails closed.
- No lock stealing on timeout; no transfer while previous worker might run; mock evidence cannot launch real models.

## Review Focus

- Two claimants with identical expected commit: at most one fast-forward accepted.
- Push accepted but acknowledgment lost: no launch or blind retry; retain held ownership and reconcile exact remote state.
- Dirty/unpushed game work and wrong source SHA: refuse to represent as the saved source.
- Missing/old/reset/NaN quota or any limited window: no new work.
- Worker interruption: save checkpoint, wait for actual termination, then allow successor; supervisor death with surviving child/process group remains blocked. A fixed probe does not prove general model process-tree supervision.
- Public artifacts: only compact sanitized metadata, no machine paths, raw auth output or credentials.

### Task 1: Preservation and baseline

- [x] Preserve previous dirty checkout and full Git refs in a verified bundle.
- [x] Create `cloud/handoff-safe-20261114` from exact candidate in separate worktree.
- [x] Verify manifest and bounded Godot startup/save/restart cases in an isolated copy (5 cases, 185 assertions; see runtime-evidence.json).

### Task 2: Coordination and usage gates

**Files:** Create `tools/cloud_handoff.py` and `tools/test_cloud_handoff.py`.

- [x] Write failing tests for quota boundaries, stale/unknown events, claim conflict, wrong owner/source, missing stop receipt and second process rejection.
- [x] Implement compact Git-backed state transitions using ordinary fast-forward pushes, never force or automatic takeover.
- [x] Implement only bounded model-free probe workers for unattended smoke testing; real model dispatch stays disabled until authentication/usage/provider checks are satisfied.
- [x] Run all coordination tests with real local bare Git remotes and task-owned subprocesses.

### Task 3: GitHub round trip and handoff

- [x] Update root entry instructions to prioritize this migration candidate over old main rules; preserve historical instructions.
- [ ] Commit and push only reviewed new-branch changes under existing GitHub authorization.
- [ ] Run producer and consumer probes in separate checkouts; verify remote state, source SHA, checkpoint and stop-before-start ordering.
- [ ] Try a read-only, no-model standard GitHub runner on new `cloud/handoff-ci-probe-20261114`; do not widen permissions if existing token/policy rejects it.
- [ ] Save a short sanitized result and document exact restart operations plus remaining authentication/scheduler limits.

### Task 4: Final verification

- [ ] Recheck original refs/copies, candidate file hashes, no deleted game files, no secret artifacts, and remote pushed SHA.
- [ ] Independent review and meaningful regression checks; keep failed logs outside the repository.
- [ ] Report simulated tests separately from real provider limit/scheduled execution and unverified GUI/full-game behavior.
