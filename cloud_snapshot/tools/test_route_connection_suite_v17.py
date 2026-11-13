#!/usr/bin/env python3
"""Keep the route-connection verification suite aligned with the v17 slice."""

from __future__ import annotations

import sys

import run_checks
from run_checks import CHECKS, SUITES


REQUIRED = (
    "canyon_one_site_playable_loop_v16",
    "canyon_parking_vertical_slice",
    "canyon_parking_vertical_ui",
    "normal_haul_frame_progression",
    "canyon_equipment_switch_v17",
)


def main() -> int:
    validator = getattr(run_checks, "validate_route_connection_v17_configuration", None)
    if not callable(validator):
        print("FAIL route_connection v17 runner does not expose its configuration self-check")
        return 1
    configuration_errors = validator()
    if configuration_errors:
        print(f"FAIL route_connection v17 configuration={configuration_errors}")
        return 1
    selected = SUITES["route_connection"]
    missing = [name for name in REQUIRED if name not in selected]
    unknown = [name for name in REQUIRED if name not in CHECKS]
    first_region_exemptions = getattr(run_checks, "FIRST_REGION_A_ROUTE_CONNECTION_CHECKS", ())
    wrongly_legacy = [name for name in REQUIRED if name not in first_region_exemptions]
    if missing or unknown or wrongly_legacy:
        print(f"FAIL route_connection v17 coverage missing={missing} unknown={unknown} legacy_world_test={wrongly_legacy}")
        return 1
    print("== route_connection v17 suite: passed ==")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
