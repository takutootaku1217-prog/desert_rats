# Vehicle exterior / interior validation prototype (2026-10-20)

- Isolated checkout: `C:\\Users\\user\\Documents\\Codex\\2026-10-20\\task-4\\vehicle_visual_prototype`
- Branch: `prototype/vehicle-visual-validation`
- Base commit: `932c4403174c2ddecc378a03d026e4d241531331`
- Main and the source checkout were not modified; no push was performed.

## Scope implemented

The large chassis exterior now reads as a three-deck heavy landship rather than
three plain rectangles: it has a stepped ochre/rust hull, dark outlines,
warm room windows, floor separators, rivets, structural ribs, pipes, optional
side armor plates, a lower-right garage bay with a small buggy, a separate
roof main turret, and three separate secondary turrets.  The turret barrels
have an idle recoil motion driven by the existing redraw clock.

The existing prototype's functional connections remain deliberately intact:

- `O` / `I` uses the existing exterior/interior switch.
- Existing workers are still real Worker instances and continue to be governed
  by the current interior/AI code; the exterior hides only workers that are
  physically inside the hull.
- Existing chassis, armor, main cannon, three-gun secondary battery, ammo,
  test enemy, and firing UI continue to be owned by `VehicleLoadout` /
  `Main.fire_vehicle_weapon`; this visual task does not add a fake combat
  path or new buggy gameplay.
- Existing body movement and wheel animation remain owned by `MobileBase`;
  the upper shell follows its existing `body_offset()`.

## Coordinate / part contract

The new shell is anchored to the existing `GameData.HULL_POS + body_offset()`
world-space origin. Its upper silhouette is `712 x 184` px, three floor
bands are 56 px apart, and each weapon mount is independently drawn above that
same origin. This keeps the shell synchronized with the existing hull, wheels,
interior/exterior transition, and vehicle firing data without changing any
worker or room coordinates.

## Isolated save

The project name is now `砂漠の移動拠点 外観検証`, so Godot resolves
`user://` to a separate directory. The existing prototype save was copied
without overwriting its source:

- source: `%APPDATA%\\Godot\\app_userdata\\砂漠の移動拠点 プロトタイプ\\save.json`
- validation copy: `%APPDATA%\\Godot\\app_userdata\\砂漠の移動拠点 外観検証\\save.json`
- SHA-256 at copy time: `D9C1507FD5B66904E825BC561803F11…` (identical)

## Reference-image and verification blockers

The supplied Library reference `libfile_27b888795c7c8191a4d75fb30c1b000e`
was prepared twice with the consumer-local workspace destination. Both signed
materialization attempts failed with `download failed`; the requested JPEG
does not exist locally. Its actual pixels were therefore not inspected, and
this prototype must not be described as reference-matched art.

Image generation is available and was used to create a transparent, original
vehicle asset concept following the requested textual envelope (three decks,
ochre/rust exterior, warm windows, roof cannon, garage/buggy, no text/UI).
This execution surface returned only an image payload and exposed no local
project file path, so no generated raster has been committed or referenced by
the game yet. The next asset pass needs a materialized reference plus
project-local PNG outputs for: (1) exterior hull, (2) main turret and barrel,
(3) secondary turret, (4) wheel/running gear, (5) garage buggy.

The Windows Godot executable was not present on PATH or in the checked local
install locations. The harness import check consequently recorded
`MISSING_EXECUTABLE` rather than a game result:
`C:\\Users\\user\\AppData\\Local\\Temp\\vehicle-visual-harness\\20261020T143247Z-2kctza54\\results.json`.
The required computer-use guidance resource also returned
`skill environment is not available for this callback`; no native window
automation or screenshot claim is made.

## Verification update

Existing harness evidence identified the installed Godot 4.7.2 console binary:
`C:\\Users\\user\\Downloads\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64_console.exe`.
Using it, this isolated checkout passed the full selected core harness on
2026-10-20; results are at
`C:\\Users\\user\\AppData\\Local\\Temp\\vehicle-visual-core\\20261020T143651Z-uvvzt41x\\results.json`.
It also completed a four-second headless scene startup using the validation
user-data folder. This is compatibility evidence, not a visual screenshot.

After the original JPEG failure, distinct transparent candidate exterior and
interior assets were supplied by the parent task: exterior
`libfile_e045a803a8208191b509967f59d3fa50`, interior
`libfile_7ea6ffaee3588191b38ef5f59120ff4e`. Each was prepared through the
official Library materialization route and each single download failed with
`library file transfer failed: download failed`. They are not local and their
pixels remain uninspected; the failed transfers are not being retried.

## Exterior revision

Following the later exterior-art direction, the code prototype now treats the
large shell as thick armor: the former repeated warm windows are covered by
large riveted armor panels, with only three small recessed amber armored
vision slits. This prevents the exterior from reading as a bedroom/workshop
cutaway. The existing garage and separate weapon mounts remain functional
visual parts. Focused `import`, `manual_combat`, and `combat_orders` checks
passed after this change; see
`C:\\Users\\user\\AppData\\Local\\Temp\\vehicle-visual-armor\\20261020T144954Z-ddc3tmws\\results.json`.

## Adopted art direction update (awaiting local pixels)

The user selected the assault-mobile-fortress concept
`libfile_b6707d88a96881918eec8f6e296af1d5`
(`call_850ef205b8e74aafa63bb34cd927de4c.png`) as the new appearance target.
Once its actual local pixels are available, the exterior should be redesigned
as a side-view 2D interpretation of its giant main cannon, forward-projecting
sloped heavy armor, stepped silhouette, white/black/red armor scheme, and
small blue emissive details. The source is an angled concept image; it must
not be pasted or perspective-squashed into the game. This supersedes ochre
box-like exterior art as the finish target, but authorizes no uninspected art
change. The current code prototype remains preserved pending a user-provided
local PNG path.

## User-provided reference confirmation

The user supplied a local copy named `大型拠点` in Downloads. It was confirmed
as a readable PNG and inspected at **1672 x 941 px**, RGB. The actual pixels
show a factory-lit, angled assault fortress concept: four large wheels, a
forward-projecting armored nose, stacked armor decks, oversized roof cannon,
secondary roof weapons, off-white and charcoal armor, red diagonal markings,
and sparse cyan-blue lights. The factory background, floor reflections, and
flag are reference-only and are not game assets.

The local reference copy is intentionally held outside this Godot project at
`C:\\Users\\user\\Documents\\Codex\\2026-10-20\\task-4\\reference\\user_provided_assault_fortress.png`
so it cannot be accidentally imported or displayed in-game.
