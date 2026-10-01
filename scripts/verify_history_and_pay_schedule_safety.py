#!/usr/bin/env python3
"""Static checks for two history/pay-schedule safety fixes (2026-10-01).

1. Editing a saved shift must keep the rate it was saved with. Changing a
   site's rate in Settings must never reprice past shifts when they are edited.
2. Employers without a known pay-period end date get guessed pay periods, so
   the app must not present those dates as fact and must prompt for anchors.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ADD = (ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift").read_text()
MODELS = (ROOT / "AnesPayTracker" / "Model" / "Models.swift").read_text()
HOME = (ROOT / "AnesPayTracker" / "Views" / "Home" / "HomeView.swift").read_text()
PERIODS = (ROOT / "AnesPayTracker" / "Views" / "Review" / "PayPeriodView.swift").read_text()
WIZARD = (ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift").read_text()

save_body = ADD.split("private func saveShift()")[1].split("private func ")[0]
rate_read = save_body.find("let rate = effectiveRate")
site_write = save_body.find("shift.site = site")

checks = {
    "Saving must not copy the site's current rate onto an existing shift": (
        "shift.baseAmount = site.baseAmount" not in ADD and "shift.baseAmount = rate" in save_body
    ),
    "An edited shift keeps its saved rate unless its site or pay unit changes": (
        "existing.site?.id == site.id" in ADD
        and "existing.payUnit == site.payUnit" in ADD
        and "return existing.baseAmount" in ADD
    ),
    "The saved rate must be read before the shift's site/pay unit are overwritten": (
        rate_read != -1 and site_write != -1 and rate_read < site_write
    ),
    "The pay preview must use the same rate that will be saved": (
        "effectiveRate * (dayFraction.multiplier)" in ADD and "effectiveRate * Decimal(hoursWorked)" in ADD
    ),
    "Edit history should record rate changes": 'changes.append("rate ' in ADD,
    "Employer should define when pay periods are reliable": (
        "var hasReliablePayPeriods: Bool" in MODELS
        and "payCadence == .monthly || payPeriodEndAnchorDate != nil" in MODELS
    ),
    "Home must not show guessed work-period dates": "if employer.hasReliablePayPeriods {" in HOME,
    "Pay Periods must flag guessed dates": (
        "if !employer.hasReliablePayPeriods {" in PERIODS and "Pay period dates are estimated" in PERIODS
    ),
    "Setup should warn clearly when paycheck anchors are off": "the app has to guess your pay periods" in WIZARD,
}

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("History and pay-schedule safety verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("History and pay-schedule safety verifier passed.")
