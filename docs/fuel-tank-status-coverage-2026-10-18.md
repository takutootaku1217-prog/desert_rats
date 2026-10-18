# Fuel-tank status wording coverage

Date: 2026-10-18

The display derives its state from the existing `rear_engine_damage` value:

- `0`: `Fuel tank: normal`
- above `0` but below `REAR_ENGINE_LEAK_DAMAGE_THRESHOLD`: `Fuel tank: damaged`
- at or above that threshold: `Fuel tank: leaking`

This is not a new durability bar or a second damage value. Rear-only enemy hits,
the existing leak condition and rate, DRIVE repair, and save/load behavior are
unchanged. The status-panel line replaces the previous leak-only wording so the
normal, damaged, and leaking states are legible without adding a HUD gauge.

Windows Godot 4.7.2 with isolated APPDATA passed `trouble_loop`, `save_game`,
`save_ui`, and `clarity_ui`:

`C:\Users\user\AppData\Local\Temp\desert-rats-fuel-tank-status-targeted-2\20261018T032251Z-ztdfo_lu\results.json`

The test verifies the three displayed states and repair recovery. It is an
automated viewport/UI check, not an OS-input play session.
