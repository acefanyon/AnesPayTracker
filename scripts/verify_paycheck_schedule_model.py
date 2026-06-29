#!/usr/bin/env python3
"""Static + oracle checks for the paycheck aggregation model slice.

This verifies the source contains the model/UI hooks for paycheck calendars and
encodes the TestFlight-corrected paycheck rule:
- store a known pay-period end date on Employer
- store the actual paycheck date for that same known period
- derive pay periods from the period-end anchor and paychecks from the separate paycheck anchor
- do not model timing as a pay-period delay stepper because real paychecks can land days after close
- provide reusable aggregation rows for base pay, on-call, custom bonuses, and streak bonuses
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "AnesPayTracker" / "Model" / "Models.swift"
ENGINE = ROOT / "AnesPayTracker" / "Engine" / "StreakEngine.swift"
SETUP = ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


@dataclass(frozen=True)
class PaycheckOracleCase:
    name: str
    pay_period_end_anchor: date
    paycheck_anchor: date
    service_date: date
    cadence_days: int
    expected_period_start: date
    expected_period_end: date
    expected_paycheck_date: date


def floor_div(numerator: int, denominator: int) -> int:
    return numerator // denominator


def ceil_div(numerator: int, denominator: int) -> int:
    return -((-numerator) // denominator)


def anchored_period(service_date: date, pay_period_end_anchor: date, cadence_days: int) -> tuple[date, date]:
    days_from_anchor = (service_date - pay_period_end_anchor).days
    offset = floor_div(days_from_anchor + cadence_days - 1, cadence_days)
    end = pay_period_end_anchor + timedelta(days=offset * cadence_days)
    start = end - timedelta(days=cadence_days - 1)
    if service_date < start:
        end -= timedelta(days=cadence_days)
        start = end - timedelta(days=cadence_days - 1)
    return start, end


def paycheck_date(service_date: date, pay_period_end_anchor: date, paycheck_anchor: date, cadence_days: int) -> date:
    _, period_end = anchored_period(service_date, pay_period_end_anchor, cadence_days)
    period_offset = (period_end - pay_period_end_anchor).days // cadence_days
    return paycheck_anchor + timedelta(days=period_offset * cadence_days)


ORACLE_CASES = [
    PaycheckOracleCase(
        name="Pay period ending Jun 20 is paid on separate Jun 26 paycheck",
        pay_period_end_anchor=date(2026, 6, 20),
        paycheck_anchor=date(2026, 6, 26),
        service_date=date(2026, 6, 7),
        cadence_days=14,
        expected_period_start=date(2026, 6, 7),
        expected_period_end=date(2026, 6, 20),
        expected_paycheck_date=date(2026, 6, 26),
    ),
    PaycheckOracleCase(
        name="Next pay period keeps the same day offset after close",
        pay_period_end_anchor=date(2026, 6, 20),
        paycheck_anchor=date(2026, 6, 26),
        service_date=date(2026, 6, 21),
        cadence_days=14,
        expected_period_start=date(2026, 6, 21),
        expected_period_end=date(2026, 7, 4),
        expected_paycheck_date=date(2026, 7, 10),
    ),
    PaycheckOracleCase(
        name="Dates before the anchor derive prior period and prior paycheck",
        pay_period_end_anchor=date(2026, 6, 20),
        paycheck_anchor=date(2026, 6, 26),
        service_date=date(2026, 6, 6),
        cadence_days=14,
        expected_period_start=date(2026, 5, 24),
        expected_period_end=date(2026, 6, 6),
        expected_paycheck_date=date(2026, 6, 12),
    ),
]


def run_oracle_cases() -> list[str]:
    failures: list[str] = []
    print("Paycheck schedule oracle:")
    for case in ORACLE_CASES:
        start, end = anchored_period(case.service_date, case.pay_period_end_anchor, case.cadence_days)
        check = paycheck_date(case.service_date, case.pay_period_end_anchor, case.paycheck_anchor, case.cadence_days)
        ok = (start, end, check) == (case.expected_period_start, case.expected_period_end, case.expected_paycheck_date)
        print(
            f"{'PASS' if ok else 'FAIL'}: {case.name} — "
            f"period {start.isoformat()}..{end.isoformat()} expected "
            f"{case.expected_period_start.isoformat()}..{case.expected_period_end.isoformat()}, "
            f"paycheck {check.isoformat()} expected {case.expected_paycheck_date.isoformat()}"
        )
        if not ok:
            failures.append(case.name)
    return failures


def main() -> int:
    models = MODELS.read_text()
    engine = ENGINE.read_text()
    setup = SETUP.read_text()
    failures = run_oracle_cases()

    require("var paycheckAnchorDate: Date?" in models, "Employer must store optional actual paycheck anchor date", failures)
    require("var payPeriodEndAnchorDate: Date?" in models, "Employer must store optional pay-period end anchor date separately from paycheck date", failures)
    require("struct PaycheckAggregationRow" in models, "Reusable paycheck aggregation row model is required", failures)
    require("func periodLengthDays(customDays:" in models, "Pay cadence must expose period length helpers", failures)

    require("paycheckDate(for serviceDate" in engine, "Engine must derive paycheck dates from service dates", failures)
    require("payPeriodEndAnchorDate" in engine, "Engine must derive work periods from the separate period-end anchor", failures)
    require("periodOffset" in engine and "paycheckAnchorDate" in engine, "Engine must map period offsets onto the actual paycheck anchor date", failures)
    require("paycheckAggregationWindow" in engine, "Engine must expose aggregation window + paycheck date", failures)
    require("paycheckAggregationRows(for shift" in engine, "Engine must expose reusable shift aggregation rows", failures)
    require("anchoredPayPeriodBounds" in engine, "Engine must derive periods from the paycheck anchor when available", failures)
    require("componentName: \"Base Pay\"" in engine, "Aggregation rows must include base pay", failures)
    require("componentName: \"On-Call Bonus\"" in engine, "Aggregation rows must include on-call pay", failures)
    require("bonus.payoutSchedule.payoutDate" in engine, "Aggregation rows must respect custom bonus payout schedules", failures)
    require("componentName: \"Streak Bonus\"" in engine, "Aggregation rows must include streak pay", failures)

    require("Use paycheck calendar anchors" in setup, "Employer setup must expose paycheck calendar toggle", failures)
    require("Known pay period end date" in setup, "Employer setup must ask for the period-end date", failures)
    require("Paycheck date for that period" in setup, "Employer setup must ask for the actual paycheck date for that period", failures)
    require("paycheckDelayPeriods" not in setup, "Employer setup must remove the pay-period delay stepper", failures)
    require("June 7–20" in setup and "June 26" in setup, "Setup copy must explain the corrected period-end to paycheck-date example", failures)

    if failures:
        print("\nPaycheck schedule model verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("\nPaycheck schedule model verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
