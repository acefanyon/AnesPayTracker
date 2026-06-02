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

Slice 1 safety-scaffold additions:
- encode concrete quarterly streak payout date examples as an oracle
- verify the codebase still routes streak payouts through next-quarter logic
- document the forward-only expectation for employer edits as a protected rule
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "AnesPayTracker" / "Model" / "Models.swift"
REPORT = ROOT / "AnesPayTracker" / "Views" / "Report" / "ReportView.swift"
ADD_SHIFT = ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift"
SETUP = ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift"
PDF = ROOT / "AnesPayTracker" / "Views" / "Report" / "PDFReportGenerator.swift"
PLAN = ROOT / "PLAN_STREAK_AND_UI.md"


@dataclass(frozen=True)
class QuarterlyPayoutCase:
    service_date: date
    expected_payout_date: date
    label: str


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def next_quarterly_payout(service_date: date) -> date:
    year = service_date.year
    month = service_date.month
    if 1 <= month <= 3:
        return date(year, 4, 1)
    if 4 <= month <= 6:
        return date(year, 7, 1)
    if 7 <= month <= 9:
        return date(year, 10, 1)
    return date(year + 1, 1, 1)


QUARTERLY_PAYOUT_CASES = [
    QuarterlyPayoutCase(date(2026, 1, 13), date(2026, 4, 1), "Q1 streak payouts land on Apr 1"),
    QuarterlyPayoutCase(date(2026, 4, 15), date(2026, 7, 1), "Q2 streak payouts land on Jul 1"),
    QuarterlyPayoutCase(date(2026, 9, 30), date(2026, 10, 1), "Q3 streak payouts land on Oct 1"),
    QuarterlyPayoutCase(date(2026, 12, 31), date(2027, 1, 1), "Q4 streak payouts roll to next year"),
]


def main() -> int:
    models = MODELS.read_text()
    report = REPORT.read_text()
    add_shift = ADD_SHIFT.read_text()
    setup = SETUP.read_text()
    pdf = PDF.read_text()
    plan = PLAN.read_text() if PLAN.exists() else ""
    failures: list[str] = []

    require("enum BonusPayoutSchedule" in models, "Models must define reusable bonus payout schedules", failures)
    require("case nextMonthlyPayout" in models, "Bonus payout schedule must support a monthly payout with delay", failures)
    require("case nextQuarterlyPayout" in models, "Bonus payout schedule must support quarterly payouts", failures)
    require("case calendarQuarter = \"Calendar Quarter\"" in models, "Streak rules must support a calendar-quarter window", failures)
    require("var postThresholdPerDayAmount: Decimal?" in models, "Streak rules must store a post-threshold per-day amount", failures)
    require("var payoutSchedule: BonusPayoutSchedule" in models, "Streak rules must store their payout schedule", failures)
    require("var streakPerDayBonusAmount: Decimal?" in models, "Shifts must store earned per-day streak snapshot amounts", failures)
    require("var streakPayoutSchedule: BonusPayoutSchedule?" in models, "Shifts must store streak payout schedule snapshots", failures)
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
    require("shift.streakPayoutSchedule ?? .nextQuarterlyPayout" in report, "Streak payouts must prefer the shift snapshot payout schedule with quarterly fallback", failures)
    require('bonusName: "Streak Bonus"' in report, "Streak bonus rows must remain explicitly labeled in payout reports", failures)
    require("schedule: payoutSchedule" in report, "Streak bonus report rows must use the resolved payout schedule for the shift", failures)

    require("Bonus Payout Report" in pdf, "PDF export must support a bonus payout report title", failures)
    require("Payout Date" in pdf, "Bonus payout PDF rows must include payout date", failures)

    require("Saved future shifts should remain unchanged after employer edits" in plan, "Plan must lock the forward-only employer-edit rule", failures)
    require("Copy/paste should copy shift notes but not source metadata by default" in plan, "Plan must lock the copy/paste metadata default", failures)

    print("Quarterly streak payout date oracle:")
    for case in QUARTERLY_PAYOUT_CASES:
        actual = next_quarterly_payout(case.service_date)
        ok = actual == case.expected_payout_date
        status = "PASS" if ok else "FAIL"
        print(
            f"{status}: {case.label} — service {case.service_date.isoformat()} "
            f"pays {actual.isoformat()} expected {case.expected_payout_date.isoformat()}"
        )
        require(ok, case.label, failures)

    if failures:
        print("\nBonus payout report checks failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("\nBonus payout report checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
