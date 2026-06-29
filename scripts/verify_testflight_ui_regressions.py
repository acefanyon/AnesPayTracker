#!/usr/bin/env python3
"""Static checks for TestFlight UI regressions found during real-device beta.

Covers:
- Calendar day numbers must not truncate into ellipsis/dots under large Dynamic Type.
- Add Shift should never present an effectively blank form when opened from calendar or FAB.
- Next beta upload should be visibly distinguishable from earlier 1.0 builds.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CALENDAR = ROOT / "AnesPayTracker" / "Views" / "Review" / "CalendarView.swift"
ADD_SHIFT = ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift"
PROJECT = ROOT / "AnesPayTracker.xcodeproj" / "project.pbxproj"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    calendar = CALENDAR.read_text()
    add_shift = ADD_SHIFT.read_text()
    project = PROJECT.read_text()
    failures: list[str] = []

    require(".minimumScaleFactor" in calendar, "Calendar day numbers need minimumScaleFactor to avoid ellipsis/dots", failures)
    require(".lineLimit(1)" in calendar, "Calendar day numbers need a one-line constraint", failures)
    require(".dynamicTypeSize" in calendar or "Font.system(size:" in calendar, "Calendar cells need controlled sizing for large Dynamic Type", failures)

    require("case addShift(Date)" in calendar and "case .addShift(let date)" in calendar, "Calendar add-shift sheet should carry its date directly to avoid blank sheet races", failures)

    require("selectDefaultSiteIfNeeded" in add_shift, "Add Shift should default to an available site instead of appearing blank", failures)
    require("No sites configured" in add_shift, "Add Shift needs a visible empty state if no sites are available", failures)

    require("MARKETING_VERSION = 1.1;" in project, "Next TestFlight-visible version should be 1.1", failures)
    require("CURRENT_PROJECT_VERSION = 3;" in project, "Next TestFlight build should increment to 3", failures)

    if failures:
        print("TestFlight UI regression verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("TestFlight UI regression verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
