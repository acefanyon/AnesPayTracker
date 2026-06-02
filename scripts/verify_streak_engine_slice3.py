#!/usr/bin/env python3
"""Static verifier for Slice 3 streak-engine rewrite.

This is a lightweight TDD harness for the Swift streak engine.
It checks that the source was rewritten away from the old one-time trigger model
and toward the new configurable post-threshold per-shift earning model.

Required behavior:
- streak state is cleared comprehensively before recomputation
- per-shift streak earning is based on the rule's configurable requiredDays
- the threshold-reaching shift does not earn the bonus
- the next qualifying shift after threshold completion does earn the bonus
- quarter rules snapshot payout metadata onto the shift
- progress/history use earned shifts, not one-time trigger shifts only
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "AnesPayTracker" / "Engine" / "StreakEngine.swift"
STATUS = ROOT / "AnesPayTracker" / "Views" / "Review" / "StreakStatusView.swift"
REPORT = ROOT / "AnesPayTracker" / "Views" / "Report" / "ReportView.swift"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    engine = ENGINE.read_text()
    status = STATUS.read_text()
    report = REPORT.read_text()
    failures: list[str] = []

    # Old trigger model should be gone.
    require("alreadyTriggered" not in engine, "Old one-time trigger tracking should be removed", failures)
    require("let triggerShift =" not in engine, "Old trigger-shift award logic should be removed", failures)
    require("existing + rule.bonusAmount" not in engine, "Engine should no longer add a one-time fixed bonusAmount award", failures)

    # Recompute must clear all streak snapshots, not just amount/id.
    require("shift.streakQualifiedShiftCount = nil" in engine, "Recompute must clear qualified-shift-count snapshots", failures)
    require("shift.streakPerDayBonusAmount = nil" in engine, "Recompute must clear per-day streak snapshot amounts", failures)
    require("shift.streakPayoutSchedule = nil" in engine, "Recompute must clear streak payout schedule snapshots", failures)
    require("shift.streakQualifiedForPayout = false" in engine, "Recompute must clear qualified-for-payout flags", failures)

    # Dynamic requiredDays threshold logic.
    require("currentCount > rule.requiredDays" in engine, "Engine must award only on shifts after the configurable threshold is met", failures)
    require("rule.postThresholdPerDayAmount ?? rule.bonusAmount" in engine, "Engine must compute earned streak amount from configurable rule fields", failures)
    require("streakQualifiedShiftCount = currentCount" in engine, "Engine must snapshot quarter progress onto each shift", failures)
    require("streakPayoutSchedule = rule.payoutSchedule" in engine, "Engine must snapshot payout schedule from the active rule", failures)
    require("streakQualifiedForPayout = currentCount > rule.requiredDays" in engine, "Engine must mark only post-threshold shifts as payout-earning", failures)
    require("let windowEnd = calendar.endOfDay(for: date)" in engine, "Windowed streak logic must cap counting at the current shift day", failures)
    require("$0.date >= monthStart && $0.date < monthEnd && $0.date <= windowEnd" in engine, "Calendar-month windows must exclude future shifts", failures)
    require("$0.date >= quarterStart && $0.date < quarterEnd && $0.date <= windowEnd" in engine, "Calendar-quarter windows must exclude future shifts", failures)

    # UI/report integration should use earned shifts, not trigger-only naming.
    require("earnedShifts(for rule: StreakRule)" in status, "Streak status UI should expose earned shifts for a rule", failures)
    require("History (\\(earnedShifts.count) earned)" in status, "Streak history label should reflect earned shifts", failures)
    require("shift.streakPayoutSchedule ?? .nextQuarterlyPayout" in report, "Report rows should prefer shift snapshot payout schedule", failures)

    if failures:
        print("Slice 3 streak engine verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Slice 3 streak engine verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
