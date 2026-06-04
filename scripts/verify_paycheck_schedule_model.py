#!/usr/bin/env python3
"""Static + oracle checks for the paycheck aggregation model slice.

This verifies the source contains the model/UI hooks for paycheck anchors and
encodes the clarified delayed-paycheck rule:
- store one real paycheck anchor date on Employer
- store a paycheck delay count, defaulting to 1 period
- derive pay periods/paychecks from the anchor instead of hardcoding Jan 1
- expose the anchor + delay in employer setup/review
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
    anchor: date
    service_date: date
    cadence_days: int
    delay_periods: int
    expected_period_start: date
    expected_period_end: date
    expected_paycheck_date: date


def floor_div(numerator: int, denominator: int) -> int:
    return numerator // denominator


def ceil_div(numerator: int, denominator: int) -> int:
    return -((-numerator) // denominator)


def anchored_period(service_date: date, anchor: date, cadence_days: int) -> tuple[date, date]:
    days_from_anchor = (service_date - anchor).days
    offset = floor_div(days_from_anchor + cadence_days - 1, cadence_days)
    end = anchor + timedelta(days=offset * cadence_days)
    start = end - timedelta(days=cadence_days - 1)
    if service_date < start:
        end -= timedelta(days=cadence_days)
        start = end - timedelta(days=cadence_days - 1)
    return start, end


def paycheck_date(service_date: date, anchor: date, cadence_days: int, delay_periods: int) -> date:
    _, end = anchored_period(service_date, anchor, cadence_days)
    reference = end + timedelta(days=cadence_days * delay_periods)
    offset = ceil_div((reference - anchor).days, cadence_days)
    return anchor + timedelta(days=offset * cadence_days)


ORACLE_CASES = [
    PaycheckOracleCase(
        name="Period A work is paid on Period B closing paycheck",
        anchor=date(2026, 1, 16),
        service_date=date(2026, 1, 5),
        cadence_days=14,
        delay_periods=1,
        expected_period_start=date(2026, 1, 3),
        expected_period_end=date(2026, 1, 16),
        expected_paycheck_date=date(2026, 1, 30),
    ),
    PaycheckOracleCase(
        name="Same-period payment is supported with zero delay",
        anchor=date(2026, 1, 16),
        service_date=date(2026, 1, 5),
        cadence_days=14,
        delay_periods=0,
        expected_period_start=date(2026, 1, 3),
        expected_period_end=date(2026, 1, 16),
        expected_paycheck_date=date(2026, 1, 16),
    ),
    PaycheckOracleCase(
        name="Dates before the anchor derive prior periods correctly",
        anchor=date(2026, 1, 16),
        service_date=date(2025, 12, 31),
        cadence_days=14,
        delay_periods=1,
        expected_period_start=date(2025, 12, 20),
        expected_period_end=date(2026, 1, 2),
        expected_paycheck_date=date(2026, 1, 16),
    ),
]


def run_oracle_cases() -> list[str]:
    failures: list[str] = []
    print("Paycheck schedule oracle:")
    for case in ORACLE_CASES:
        start, end = anchored_period(case.service_date, case.anchor, case.cadence_days)
        check = paycheck_date(case.service_date, case.anchor, case.cadence_days, case.delay_periods)
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

    require("var paycheckAnchorDate: Date?" in models, "Employer must store optional paycheck anchor date", failures)
    require("var paycheckDelayPeriods: Int = 1" in models, "Employer must default paycheck delay to one pay period", failures)
    require("struct PaycheckAggregationRow" in models, "Reusable paycheck aggregation row model is required", failures)
    require("func periodLengthDays(customDays:" in models, "Pay cadence must expose period length helpers", failures)

    require("paycheckDate(for serviceDate" in engine, "Engine must derive paycheck dates from service dates", failures)
    require("paycheckAggregationWindow" in engine, "Engine must expose aggregation window + paycheck date", failures)
    require("paycheckAggregationRows(for shift" in engine, "Engine must expose reusable shift aggregation rows", failures)
    require("anchoredPayPeriodBounds" in engine, "Engine must derive periods from the paycheck anchor when available", failures)
    require("componentName: \"Base Pay\"" in engine, "Aggregation rows must include base pay", failures)
    require("componentName: \"On-Call Bonus\"" in engine, "Aggregation rows must include on-call pay", failures)
    require("bonus.payoutSchedule.payoutDate" in engine, "Aggregation rows must respect custom bonus payout schedules", failures)
    require("componentName: \"Streak Bonus\"" in engine, "Aggregation rows must include streak pay", failures)

    require("Use paycheck anchor date" in setup, "Employer setup must expose paycheck anchor toggle", failures)
    require("Known paycheck date" in setup, "Employer setup must expose anchor date picker", failures)
    require("paycheckDelayPeriods" in setup, "Employer setup must expose/save paycheck delay periods", failures)
    require("Period A is paid on the paycheck associated with Period B" in setup, "Setup copy must explain the clarified delayed paycheck rule", failures)

    if failures:
        print("\nPaycheck schedule model verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("\nPaycheck schedule model verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
