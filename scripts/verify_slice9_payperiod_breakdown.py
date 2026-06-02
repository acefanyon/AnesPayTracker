#!/usr/bin/env python3
"""Static verifier for Slice 9 pay-period component breakdown."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
PAY_PERIOD_VIEW = ROOT / "AnesPayTracker" / "Views" / "Review" / "PayPeriodView.swift"
COMPONENTS_DIR = ROOT / "AnesPayTracker" / "Views" / "Components"
PLAN = ROOT / "PLAN_STREAK_AND_UI.md"


def main() -> int:
    pay_period = PAY_PERIOD_VIEW.read_text()
    failures: list[str] = []

    # Check that PayBreakdownCard component exists (we created it in Components)
    breakdown_card_path = COMPONENTS_DIR / "PayBreakdownCard.swift"
    if not breakdown_card_path.exists():
        failures.append("Missing PayBreakdownCard.swift component")

    # Check that PayPeriodView uses PayBreakdownCard in the shift list
    if "PayBreakdownCard(shift: shift)" not in pay_period:
        failures.append("PayPeriodView does not contain PayBreakdownCard(shift: shift)")

    # Optionally, ensure we are not still using PayPeriodShiftRow in the shift list
    # We'll do a simple check: between "// Shift list" and the next closing brace at same indentation,
    # there should be no PayPeriodShiftRow.
    # For simplicity, we can just check that the string "PayPeriodShiftRow(shift: shift)" does not appear
    # after the "// Shift list" comment.
    # Find the index of "// Shift list"
    try:
        idx = pay_period.index("// Shift list")
        # Look ahead 2000 characters (should be enough to cover the shift list)
        after_comment = pay_period[idx:idx+2000]
        if "PayPeriodShiftRow(shift: shift)" in after_comment:
            failures.append("PayPeriodView shift list still contains PayPeriodShiftRow (should be replaced)")
    except ValueError:
        pass  # comment not found, ignore

    if failures:
        print("Slice 9 pay-period breakdown verifier failed:")
        for f in failures:
            print(f"- {f}")
        return 1

    print("Slice 9 pay-period breakdown verifier passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())