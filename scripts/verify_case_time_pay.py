#!/usr/bin/env python3
"""Case-time pay: worked examples plus checks that the app is wired to the rule.

Rule (sites where the employer "pays for case time only"):
- each case counts whole minutes from start to stop; a running case counts 0;
- the day's minutes are summed, then raised to the daily minimum if one is set
  (the minimum can be switched off on a single shift it doesn't cover);
- base pay = hourly rate x paid minutes / 60, rounded half-up to the cent;
- flat add-ons (for example a recovery fee) are ordinary custom bonuses on top.

The Swift implementation itself is executed by scripts/swift_tests/pay_math
in CI; this script keeps an independent oracle and guards the wiring.
All amounts are examples.
"""
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "AnesPayTracker"
CALC = (APP / "Engine" / "CaseTimeCalculator.swift").read_text()
PAYDATE = (APP / "Engine" / "PaycheckDateMath.swift").read_text()
ENGINE = (APP / "Engine" / "StreakEngine.swift").read_text()
MODELS = (APP / "Model" / "Models.swift").read_text()
ADD = (APP / "Views" / "Entry" / "AddShiftView.swift").read_text()
TRACKER = (APP / "Views" / "Entry" / "CaseTrackerCard.swift").read_text()
HOME = (APP / "Views" / "Home" / "HomeView.swift").read_text()
PROJECT = (ROOT / "AnesPayTracker.xcodeproj" / "project.pbxproj").read_text()
WORKFLOW = (ROOT / ".github" / "workflows" / "build.yml").read_text()
SWIFT_TESTS = (ROOT / "scripts" / "swift_tests" / "pay_math" / "main.swift").read_text()


def paid_minutes(case_minutes: int, minimum_hours=None) -> int:
    minimum = int(round(minimum_hours * 60)) if minimum_hours and minimum_hours > 0 else 0
    return max(case_minutes, minimum)


def pay(rate: str, minutes: int) -> Decimal:
    return (Decimal(rate) * minutes / 60).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def monthly_payday(period_end, end_anchor, pay_anchor):
    """(year, month) tuples in, (year, month, day) out: keep the anchor pairing."""
    months = (period_end[0] - end_anchor[0]) * 12 + (period_end[1] - end_anchor[1])
    index = pay_anchor[0] * 12 + (pay_anchor[1] - 1) + months
    return (index // 12, index % 12 + 1, pay_anchor[2])


oracle = {
    "7 h 31 m at $400/hr": (pay("400", 451), Decimal("3006.67")),
    "that day plus a $200 flat recovery fee": (pay("400", 451) + Decimal("200"), Decimal("3206.67")),
    "7 h 30 m at $400/hr": (pay("400", 450), Decimal("3000.00")),
    "one minute at $400/hr": (pay("400", 1), Decimal("6.67")),
    "half a cent rounds up": (pay("0.30", 1), Decimal("0.01")),
    "light day raised to a 4 h minimum": (pay("400", paid_minutes(150, 4)), Decimal("1600.00")),
    "full day unaffected by the minimum": (paid_minutes(451, 4), 451),
    "no minimum set": (paid_minutes(150, None), 150),
    "half-day minimum of $2,000 is 5 h at $400/hr": (pay("400", paid_minutes(150, 5)), Decimal("2000.00")),
    "minimum switched off for the day": (pay("400", paid_minutes(150, None)), Decimal("1000.00")),
    "November work paid December 15": (monthly_payday((2026, 11), (2026, 10), (2026, 11, 15)), (2026, 12, 15)),
    "December work paid January 15": (monthly_payday((2026, 12), (2026, 10), (2026, 11, 15)), (2027, 1, 15)),
}

case_keys = re.search(r"struct ShiftCase.*?enum CodingKeys: String, CodingKey \{(.*?)\}", CALC, re.S)
case_fields = sorted(re.findall(r"case (\w+)", case_keys.group(1))) if case_keys else []

checks = {name: actual == expected for name, (actual, expected) in oracle.items()}
checks.update({
    "Pay math files must stay Foundation-only so they can be tested outside the app": all(
        re.findall(r"^import (\w+)", text, re.M) == ["Foundation"] for text in (CALC, PAYDATE)
    ),
    "Case pay = rate x minutes / 60, rounded half-up to cents": (
        "rate * Decimal(paidMinutes) / Decimal(60)" in CALC and "NSDecimalRound(&rounded, &exact, 2, .plain)" in CALC
    ),
    "A running case counts nothing until stopped": "guard !shiftCase.isRunning else { return 0 }" in CALC,
    "Cases store times only (no patient details)": case_fields == ["endAt", "id", "isRunning", "startAt"],
    "Shift.basePay uses case pay for case-time shifts": (
        "if isCaseTracked {\n                return CaseTimeCalculator.pay(rate: baseAmount, paidMinutes: paidCaseMinutes)" in MODELS
    ),
    "Non-case hourly pay is unchanged": "return baseAmount * Decimal(hoursWorked ?? 0)" in MODELS,
    "Case time is an employer setting that per-hour sites follow unless they opt out": (
        "payUnit == .perHour && (employer?.paysCaseTimeOnly ?? false) && !optsOutOfCaseTime" in MODELS
    ),
    "New model fields are migration-safe": (
        "var paysCaseTimeOnly: Bool = false" in MODELS
        and "var dailyMinimumHours: Double?" in MODELS
        and "var optsOutOfCaseTime: Bool = false" in MODELS
        and "var cases: [ShiftCase]?" in MODELS
        and "var guaranteedMinimumHours: Double?" in MODELS
    ),
    "Editing keeps how a shift was saved (cases or plain hours) and its saved minimum": (
        "return existing.cases != nil" in ADD
        and "let saved = existing.guaranteedMinimumHours" in ADD
        and "appliesMinimum = shift.cases == nil || shift.guaranteedMinimumHours != nil" in ADD
    ),
    "The minimum can be switched off for one shift, and is on by default": (
        "@State private var appliesMinimum: Bool = true" in ADD
        and "appliesMinimum ? availableMinimumHours : nil" in ADD
        and "Toggle(isOn: $appliesMinimum)" in ADD
        and "daily minimum switched off" in ADD
    ),
    "The minimum is snapshotted onto the shift when saved": "shift.guaranteedMinimumHours = minimumHours" in ADD,
    "Overlapping or inconsistent cases block saving": (
        "isSaving || caseProblem != nil" in ADD and "caseProblem == nil else { return }" in ADD
    ),
    "The tracker snapshots rate and minimum when it creates a shift": (
        "guaranteedMinimumHours: site.employer?.dailyMinimumHours" in TRACKER and "baseAmount: site.baseAmount" in TRACKER
    ),
    "The tracker reports failed saves instead of dropping them": "try context.save()" in TRACKER and "try? " not in TRACKER,
    "Home shows the tracker only for case-time sites": "if !caseTimeSites.isEmpty {\n                        CaseTrackerCard(" in HOME,
    "Monthly paydays keep the anchor pairing": "PaycheckDateMath.monthlyPaycheckDate(" in ENGINE,
    "New files are compiled into the app": all(
        f"{path} in Sources */," in PROJECT
        for path in (
            "Engine/CaseTimeCalculator.swift",
            "Engine/PaycheckDateMath.swift",
            "Views/Entry/CaseTimeEntry.swift",
            "Views/Entry/CaseTrackerCard.swift",
        )
    ),
    "CI runs the Swift pay-math tests": (
        "scripts/swift_tests/pay_math/main.swift" in WORKFLOW
        and "AnesPayTracker/Engine/CaseTimeCalculator.swift" in WORKFLOW
        and "AnesPayTracker/Engine/PaycheckDateMath.swift" in WORKFLOW
    ),
    "Swift tests cover the worked examples": 'money("3006.67")' in SWIFT_TESTS and 'money("1600")' in SWIFT_TESTS,
})

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("Case-time pay verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("Case-time pay verifier passed.")
