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
"""

from __future__ import annotations

from dataclasses import dataclass, field
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


def main() -> int:
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

    if failures:
        print("\nFailed cases:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print(f"\nAll {len(CASES)} pay-calculation safety checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
