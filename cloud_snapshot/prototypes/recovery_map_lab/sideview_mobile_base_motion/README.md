# Sideview Mobile-Base Motion Proof v1

Target scene:
`res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_proof.tscn`

Run it independently from the project root:

```text
godot4 --path . --scene res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_proof.tscn
```

Or open that scene in Godot and use **F6**.  It does not replace the project
main scene and does not construct `Main`, a route session, a save, or the
quarter-view map.

This proof is intentionally one existing sideview orientation.  It uses the
existing `fortress_moving` components; it is not a final directional vehicle
asset or live map movement implementation.  See
`docs/cloud_handoff/SIDEVIEW_MOBILE_BASE_MOTION_PROOF_V2_VERIFICATION.md` for
the real X11 evidence and limits.
