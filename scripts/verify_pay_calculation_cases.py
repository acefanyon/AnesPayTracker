#!/usr/bin/env python3
"""Repeatable pay-calculation safety checks for AnesPayTracker.

This is a lightweight oracle for the current app formulas in
AnesPayTracker/Model/Models.swift:

basePay =
  perDay:  baseAmount * dayFraction.multiplier
  perHour: baseAmount * hoursWorked

totalPay = basePay + splash + bonusSplash + customBonuses + streakBonus

It intentionally avoids SwiftData/Xcode test-target wiring for now so the
calculation cases can run from the command line before deeper pay-model and
reconciliation changes.

Slice 1 safety-scaffold additions:
- encode the upcoming quarter-based streak business rule as an oracle
- verify that partial days still count as full streak-threshold days
- verify quarter rollover resets streak progress and earnings
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal


DAY_FRACTIONS = {
    "quarter": Decimal("0.25"),
    "half": Decimal("0.5"),
    "threeQuarter": Decimal("0.75"),
    "full": Decimal("1"),
}


@dataclass(frozen=True)
class CustomBonus:
    name: str
    amount: Decimal
    quantity: Decimal

    @property
    def total(self) -> Decimal:
        return self.amount * self.quantity


@dataclass(frozen=True)
class Case:
    name: str
    pay_unit: str
    base_amount: Decimal
    day_fraction: str = "full"
    hours_worked: Decimal = Decimal("0")
    splash: Decimal = Decimal("0")
    bonus_splash: Decimal = Decimal("0")
    streak_bonus: Decimal = Decimal("0")
    custom_bonuses: list[CustomBonus] = field(default_factory=list)
    expected_base: Decimal = Decimal("0")
    expected_total: Decimal = Decimal("0")


@dataclass(frozen=True)
class QuarterShift:
    service_date: date
    day_fraction: str
    expected_progress_day_count: int
    expected_streak_bonus: Decimal


@dataclass(frozen=True)
class QuarterRule:
    required_days: int
    per_day_bonus: Decimal


@dataclass(frozen=True)
class QuarterScenario:
    name: str
    rule: QuarterRule
    shifts: list[QuarterShift]


def calculate(case: Case) -> tuple[Decimal, Decimal]:
    if case.pay_unit == "perDay":
        base = case.base_amount * DAY_FRACTIONS[case.day_fraction]
    elif case.pay_unit == "perHour":
        base = case.base_amount * case.hours_worked
    else:
        raise ValueError(f"Unknown pay unit: {case.pay_unit}")

    custom_total = sum((bonus.total for bonus in case.custom_bonuses), Decimal("0"))
    total = base + case.splash + case.bonus_splash + custom_total + case.streak_bonus
    return base, total


def quarter_key(value: date) -> tuple[int, int]:
    return value.year, ((value.month - 1) // 3) + 1


def calculate_quarter_streak_progress(
    shifts: list[QuarterShift],
    rule: QuarterRule,
) -> list[tuple[int, Decimal]]:
    """Return [(progress_day_count, streak_bonus_for_shift), ...].

    Business rule encoded here:
    - every qualifying saved shift counts as one full streak day, even partial days
    - the threshold-reaching shift does not earn the post-threshold bonus
    - the first bonus-earning shift is the next shift after threshold completion
    - counters reset on quarter rollover
    """

    per_quarter_counts: dict[tuple[int, int], int] = {}
    results: list[tuple[int, Decimal]] = []

    for shift in sorted(shifts, key=lambda item: item.service_date):
        key = quarter_key(shift.service_date)
        prior_count = per_quarter_counts.get(key, 0)
        current_count = prior_count + 1
        streak_bonus = rule.per_day_bonus if current_count > rule.required_days else Decimal("0")
        per_quarter_counts[key] = current_count
        results.append((current_count, streak_bonus))

    return results


def money(value: Decimal) -> str:
    return f"${value.quantize(Decimal('0.01'))}"


CASES = [
    Case(
        name="full-day per-day base pay",
        pay_unit="perDay",
        base_amount=Decimal("1000"),
        day_fraction="full",
        expected_base=Decimal("1000"),
        expected_total=Decimal("1000"),
    ),
    Case(
        name="half-day per-day base pay",
        pay_unit="perDay",
        base_amount=Decimal("1000"),
        day_fraction="half",
        expected_base=Decimal("500"),
        expected_total=Decimal("500"),
    ),
    Case(
        name="quarter-day per-day base pay",
        pay_unit="perDay",
        base_amount=Decimal("1000"),
        day_fraction="quarter",
        expected_base=Decimal("250"),
        expected_total=Decimal("250"),
    ),
    Case(
        name="three-quarter per-day base pay",
        pay_unit="perDay",
        base_amount=Decimal("1000"),
        day_fraction="threeQuarter",
        expected_base=Decimal("750"),
        expected_total=Decimal("750"),
    ),
    Case(
        name="hourly base pay",
        pay_unit="perHour",
        base_amount=Decimal("150"),
        hours_worked=Decimal("8"),
        expected_base=Decimal("1200"),
        expected_total=Decimal("1200"),
    ),
    Case(
        name="per-day base plus splash and bonus splash",
        pay_unit="perDay",
        base_amount=Decimal("1000"),
        day_fraction="full",
        splash=Decimal("100"),
        bonus_splash=Decimal("200"),
        expected_base=Decimal("1000"),
        expected_total=Decimal("1300"),
    ),
    Case(
        name="custom flat/per-day bonus included",
        pay_unit="perDay",
        base_amount=Decimal("1000"),
        day_fraction="full",
        custom_bonuses=[CustomBonus("Holiday", Decimal("250"), Decimal("1"))],
        expected_base=Decimal("1000"),
        expected_total=Decimal("1250"),
    ),
    Case(
        name="custom per-hour bonus included",
        pay_unit="perHour",
        base_amount=Decimal("150"),
        hours_worked=Decimal("8"),
        custom_bonuses=[CustomBonus("Call Back", Decimal("25"), Decimal("8"))],
        expected_base=Decimal("1200"),
        expected_total=Decimal("1400"),
    ),
    Case(
        name="base, splash, custom bonuses, and streak bonus combine once",
        pay_unit="perDay",
        base_amount=Decimal("1000"),
        day_fraction="half",
        splash=Decimal("100"),
        bonus_splash=Decimal("50"),
        custom_bonuses=[
            CustomBonus("Holiday", Decimal("250"), Decimal("1")),
            CustomBonus("Trauma", Decimal("75"), Decimal("2")),
        ],
        streak_bonus=Decimal("500"),
        expected_base=Decimal("500"),
        expected_total=Decimal("1550"),
    ),
    Case(
        name="nil/empty custom bonuses do not change total",
        pay_unit="perDay",
        base_amount=Decimal("1000"),
        day_fraction="full",
        streak_bonus=Decimal("500"),
        expected_base=Decimal("1000"),
        expected_total=Decimal("1500"),
    ),
]


QUARTER_SCENARIOS = [
    QuarterScenario(
        name="12-day threshold starts $200 bonus on day 13 in same quarter",
        rule=QuarterRule(required_days=12, per_day_bonus=Decimal("200")),
        shifts=[
            *[
                QuarterShift(
                    service_date=date(2026, 1, day),
                    day_fraction="full",
                    expected_progress_day_count=day,
                    expected_streak_bonus=Decimal("0"),
                )
                for day in range(1, 13)
            ],
            QuarterShift(
                service_date=date(2026, 1, 13),
                day_fraction="full",
                expected_progress_day_count=13,
                expected_streak_bonus=Decimal("200"),
            ),
            QuarterShift(
                service_date=date(2026, 1, 14),
                day_fraction="full",
                expected_progress_day_count=14,
                expected_streak_bonus=Decimal("200"),
            ),
        ],
    ),
    QuarterScenario(
        name="partial days still count as full streak days toward threshold",
        rule=QuarterRule(required_days=3, per_day_bonus=Decimal("200")),
        shifts=[
            QuarterShift(date(2026, 4, 1), "quarter", 1, Decimal("0")),
            QuarterShift(date(2026, 4, 2), "half", 2, Decimal("0")),
            QuarterShift(date(2026, 4, 3), "threeQuarter", 3, Decimal("0")),
            QuarterShift(date(2026, 4, 4), "full", 4, Decimal("200")),
        ],
    ),
    QuarterScenario(
        name="quarter rollover resets streak progress and bonus earning",
        rule=QuarterRule(required_days=2, per_day_bonus=Decimal("200")),
        shifts=[
            QuarterShift(date(2026, 6, 29), "full", 1, Decimal("0")),
            QuarterShift(date(2026, 6, 30), "full", 2, Decimal("0")),
            QuarterShift(date(2026, 7, 1), "full", 1, Decimal("0")),
            QuarterShift(date(2026, 7, 2), "full", 2, Decimal("0")),
            QuarterShift(date(2026, 7, 3), "full", 3, Decimal("200")),
        ],
    ),
]


def run_standard_cases() -> list[str]:
    failures: list[str] = []
    for case in CASES:
        actual_base, actual_total = calculate(case)
        ok = actual_base == case.expected_base and actual_total == case.expected_total
        status = "PASS" if ok else "FAIL"
        print(
            f"{status}: {case.name} — "
            f"base {money(actual_base)} expected {money(case.expected_base)}, "
            f"total {money(actual_total)} expected {money(case.expected_total)}"
        )
        if not ok:
            failures.append(case.name)
    return failures


def run_quarter_scenarios() -> list[str]:
    failures: list[str] = []
    print("\nQuarter-based streak safety scenarios:")
    for scenario in QUARTER_SCENARIOS:
        actual = calculate_quarter_streak_progress(scenario.shifts, scenario.rule)
        scenario_ok = True
        if len(actual) != len(scenario.shifts):
            failures.append(f"{scenario.name} produced {len(actual)} rows for {len(scenario.shifts)} shifts")
            continue
        for shift, (actual_progress, actual_bonus) in zip(scenario.shifts, actual):
            row_ok = (
                actual_progress == shift.expected_progress_day_count
                and actual_bonus == shift.expected_streak_bonus
            )
            scenario_ok = scenario_ok and row_ok
            status = "PASS" if row_ok else "FAIL"
            print(
                f"{status}: {scenario.name} — {shift.service_date.isoformat()} "
                f"({shift.day_fraction}) progress {actual_progress} expected {shift.expected_progress_day_count}, "
                f"streak {money(actual_bonus)} expected {money(shift.expected_streak_bonus)}"
            )
        if not scenario_ok:
            failures.append(scenario.name)
    return failures


def main() -> int:
    failures = run_standard_cases()
    failures.extend(run_quarter_scenarios())

    if failures:
        print("\nFailed cases:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print(
        f"\nAll {len(CASES)} pay-calculation safety checks and "
        f"{len(QUARTER_SCENARIOS)} quarter-based streak scenarios passed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
