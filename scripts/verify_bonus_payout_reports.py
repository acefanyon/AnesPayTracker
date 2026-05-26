#!/usr/bin/env python3
"""Static checks for asynchronous bonus payout reporting.

Product behavior:
- Shift earning totals can still show the amount earned on service date.
- Reports also need a separate bonus-payout view because bonus components may pay
  later than regular pay.
- Named non-streak bonuses can be paid on service date, next monthly payout, or
  next quarterly payout.
- Streak bonuses are treated as quarterly payouts by default.
- Report filters must support month, quarter, and custom payout ranges, and must
  continue to filter/break down by employer and site/location.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "AnesPayTracker" / "Model" / "Models.swift"
REPORT = ROOT / "AnesPayTracker" / "Views" / "Report" / "ReportView.swift"
ADD_SHIFT = ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift"
SETUP = ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift"
PDF = ROOT / "AnesPayTracker" / "Views" / "Report" / "PDFReportGenerator.swift"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    models = MODELS.read_text()
    report = REPORT.read_text()
    add_shift = ADD_SHIFT.read_text()
    setup = SETUP.read_text()
    pdf = PDF.read_text()
    failures: list[str] = []

    require("enum BonusPayoutSchedule" in models, "Models must define reusable bonus payout schedules", failures)
    require("case nextMonthlyPayout" in models, "Bonus payout schedule must support a monthly payout with delay", failures)
    require("case nextQuarterlyPayout" in models, "Bonus payout schedule must support quarterly payouts", failures)
    require("func payoutDate(for serviceDate: Date" in models, "Bonus payout schedule must compute payout dates from service dates", failures)
    for quarter in ["1...3", "4...6", "7...9", "10...12"]:
        require(quarter in models, f"Quarter payout logic must explicitly cover months {quarter}", failures)

    require("var payoutSchedule: BonusPayoutSchedule" in models, "CustomBonusType and AppliedCustomBonus must store payout schedule", failures)
    require("payoutSchedule: draft.payoutSchedule" in setup, "Employer custom bonus setup must save payout schedule defaults", failures)
    require("Picker(\"When paid\"" in setup, "Employer setup must expose a When paid picker for named bonuses", failures)
    require("Picker(\"When paid\"" in add_shift, "Add Shift one-time bonus UI must expose a When paid picker", failures)
    require("payoutSchedule: $0.payoutSchedule" in add_shift, "Shift saves must persist applied bonus payout schedule", failures)

    require("enum ReportMode" in report, "Reports must have a mode selector for earnings vs bonus payouts", failures)
    require("case bonusPayouts" in report, "Reports must include a Bonus Payouts mode", failures)
    require("enum BonusPayoutDateRange" in report, "Bonus payout reports must have separate payout date ranges", failures)
    require("case thisQuarter" in report and "case lastQuarter" in report, "Bonus payout range must support quarters", failures)
    require("bonusPayoutRows" in report, "ReportView must build bonus payout rows by payout date", failures)
    require("BonusPayoutSummaryCard" in report, "Reports must show a bonus payout summary card", failures)
    require("BonusPayoutBreakdownCard" in report, "Reports must show employer/site breakdowns", failures)
    require("shift.site?.employer?.id" in report and "shift.site?.id" in report, "Bonus payout rows must remain filterable by employer and site/location", failures)

    require("Bonus Payout Report" in pdf, "PDF export must support a bonus payout report title", failures)
    require("Payout Date" in pdf, "Bonus payout PDF rows must include payout date", failures)

    if failures:
        print("Bonus payout report checks failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Bonus payout report checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
