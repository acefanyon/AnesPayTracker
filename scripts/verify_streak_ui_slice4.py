#!/usr/bin/env python3
"""Static verifier for Slice 4 streak UI clarification work."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATUS = ROOT / "AnesPayTracker" / "Views" / "Review" / "StreakStatusView.swift"
DETAIL = ROOT / "AnesPayTracker" / "Views" / "Review" / "ShiftDetailView.swift"
PAY_PERIOD = ROOT / "AnesPayTracker" / "Views" / "Review" / "PayPeriodView.swift"
ENGINE = ROOT / "AnesPayTracker" / "Engine" / "StreakEngine.swift"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    status = STATUS.read_text()
    detail = DETAIL.read_text()
    pay_period = PAY_PERIOD.read_text()
    engine = ENGINE.read_text()
    failures: list[str] = []

    require("now earning" in engine, "Progress text should explain when the user is now earning the streak bonus", failures)
    require("next qualifying shift earns" in engine, "Progress text should explain threshold-met but not-yet-earning state", failures)
    require("earnedBonusDays" in engine, "Progress model should expose earned bonus day counts", failures)

    require("StatusChip" in status, "Streak status UI should show visual state chips", failures)
    require("Earning now" in status, "Streak status UI should label active earning state", failures)
    require("Threshold met" in status, "Streak status UI should label threshold-met state", failures)
    require("Paid at next quarterly payout" in status or "Paid at next monthly payout" in status, "Streak status UI should explain payout timing", failures)
    require("Quarter resets after" in status, "Streak status UI should explain the quarter reset deadline", failures)

    require("This shift is earning a deferred streak bonus" in detail, "Shift detail header should call out deferred streak bonus earnings", failures)
    require("Earned on this shift, paid" in detail, "Shift pay breakdown should explain deferred streak payout timing", failures)
    require("Streak Status" in detail, "Shift detail metadata should explain the shift's streak status", failures)

    require("🎯 Deferred Streak" in pay_period, "Pay period totals should label streak amounts as deferred", failures)
    require("Paid with shift:" in pay_period, "Pay period shift rows should explain immediate pay", failures)
    require("Quarterly streak:" in pay_period, "Pay period shift rows should explain deferred streak payouts", failures)

    if failures:
        print("Slice 4 streak UI verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Slice 4 streak UI verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
