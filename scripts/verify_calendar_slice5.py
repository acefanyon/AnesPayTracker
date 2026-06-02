#!/usr/bin/env python3
"""Static verifier for Slice 5 calendar tap-to-add flow."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CALENDAR = ROOT / "AnesPayTracker" / "Views" / "Review" / "CalendarView.swift"
ADD_SHIFT = ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    calendar = CALENDAR.read_text()
    add_shift = ADD_SHIFT.read_text()
    failures: list[str] = []

    require("@State private var selectedDate: Date?" in calendar, "Calendar should track a selected date for tap flows", failures)
    require("@State private var activeSheet: CalendarSheet?" in calendar, "Calendar should route taps through a sheet state", failures)
    require("handleDayTap(date)" in calendar, "Calendar day cells should route taps through a shared handler", failures)
    require("activeSheet = shiftsOn(date: date).isEmpty ? .addShift : .daySheet" in calendar, "Calendar tap handler should open Add Shift for empty days and a day sheet for occupied days", failures)
    require("AddShiftView(initialDate: selectedDate)" in calendar, "Empty-day taps should open Add Shift prefilled to the selected date", failures)
    require("struct CalendarDaySheet: View" in calendar, "Occupied days should open a dedicated day sheet", failures)
    require("ShiftDetailView(shift: shift)" in calendar, "Day sheet should support tap-through into shift detail", failures)
    require("AddShiftView(initialDate: date)" in calendar, "Day sheet Add Shift action should reuse the tapped date", failures)
    require("let onTapDay: () -> Void" in calendar, "Calendar day cell should expose a day-tap callback", failures)

    require("var initialDate: Date? = nil" in add_shift, "Add Shift should accept an injected initial date", failures)
    require("applyInitialDateIfNeeded()" in add_shift, "Add Shift should apply injected dates on appear", failures)
    require("guard editingShift == nil, let initialDate else { return }" in add_shift, "Injected dates should not override edit mode", failures)
    require("date = initialDate" in add_shift, "Injected dates should prefill the form date", failures)

    if failures:
        print("Slice 5 calendar verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Slice 5 calendar verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
