#!/usr/bin/env python3
"""Static verifier for Slice 6 copy/paste shift workflow."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ADD_SHIFT = ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift"
DETAIL = ROOT / "AnesPayTracker" / "Views" / "Review" / "ShiftDetailView.swift"
PLAN = ROOT / "PLAN_STREAK_AND_UI.md"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    add_shift = ADD_SHIFT.read_text()
    detail = DETAIL.read_text()
    plan = PLAN.read_text()
    failures: list[str] = []

    require("struct ShiftDraftSnapshot" in add_shift, "Snapshot type for copy/paste should exist", failures)
    require("final class ShiftDraftClipboard" in add_shift, "Clipboard singleton should exist", failures)
    require("func copy(from shift: Shift)" in add_shift, "Copy function should exist", failures)
    require("func clear()" in add_shift, "Clear function should exist", failures)
    require("var hasSnapshot: Bool" in add_shift, "Clipboard should expose hasSnapshot", failures)
    require("ShiftDraftClipboard.shared" in add_shift, "Clipboard should be accessed via shared", failures)
    require("editingShift == nil && ShiftDraftClipboard.shared.hasSnapshot" in add_shift, "Paste availability should depend on clipboard and not editing", failures)
    require("selectedSite = copiedSite" in add_shift, "Pasting should set the selected site", failures)
    require("dayFraction = copiedDayFraction" in add_shift, "Pasting should set the day fraction", failures)
    require("hoursWorked = copiedHours" in add_shift, "Pasting should set the hours worked", failures)
    require("isOnCall = snapshot.isOnCall" in add_shift, "Pasting should set the on-call flag", failures)
    require("onCallAmount = snapshot.onCallAmount ?? defaultOnCallAmount" in add_shift, "Pasting should set the on-call amount (with fallback)", failures)
    require("notes = snapshot.notes" in add_shift, "Pasting should set the notes", failures)
    require("customBonuses = copiedDraftBonuses(from: snapshot)" in add_shift, "Pasting should set custom bonuses", failures)
    require("showPasteHint = false" in add_shift, "Paste hint should be cleared after paste", failures)
    # Updated to match the current button in CustomBonusesSection
    require("customBonuses.append(DraftAppliedCustomBonus(" in add_shift, "Custom bonuses step should allow adding new bonuses", failures)
    require("use Paste Copied Shift" in detail, "Copy confirmation should teach the next-step paste flow", failures)
    require("### Slice 6 — Copy/paste shift workflow" in plan, "Plan should still contain Slice 6 documentation", failures)
    # Updated to accept the current plan status (we are now at slice 9)
    require(("Slices 1-7 are implemented locally and verified." in plan) or 
            ("Slices 1-8 are implemented locally and verified." in plan) or
            ("Slices 1-9 are implemented locally and verified." in plan), 
            "Plan execution status should reflect the current completed slices", failures)

    if failures:
        print("Slice 6 copy/paste verifier failed:")
        for message in failures:
            print(f"- {message}")
        return 1

    print("Slice 6 copy/paste verifier passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())