# Pay Calculation Safety Checklist

Date started: 2026-05-25

Purpose: give AnesPayTracker a repeatable safety net before deeper pay-period reconciliation and employer/pay-model changes.

Current app formula source of truth:

- `AnesPayTracker/Model/Models.swift`
- `Shift.basePay`
- `Shift.totalPay`
- `AppliedCustomBonus.totalAmount`

Current formulas:

```text
per-day base pay = baseAmount × dayFraction.multiplier
per-hour base pay = baseAmount × hoursWorked
custom bonus amount = custom bonus amount × quantity
total pay = base pay + splash + bonus splash + custom bonuses + streak bonus
```

Repeatable command-line check:

```bash
cd /Users/jasonvargas/Projects/AnesPayTracker
python3 scripts/verify_pay_calculation_cases.py
```

This script is intentionally lightweight and independent of SwiftData/Xcode test-target setup. It is a calculation oracle for the current formulas and expected values. A formal XCTest target can replace or wrap it later.

## Safety cases covered by the script

1. Full-day per-day base pay
   - Input: `$1,000/day`, full day
   - Expected base: `$1,000`
   - Expected total: `$1,000`

2. Half-day per-day base pay
   - Input: `$1,000/day`, half day
   - Expected base: `$500`
   - Expected total: `$500`

3. Quarter-day per-day base pay
   - Input: `$1,000/day`, quarter day
   - Expected base: `$250`
   - Expected total: `$250`

4. Three-quarter-day per-day base pay
   - Input: `$1,000/day`, three-quarter day
   - Expected base: `$750`
   - Expected total: `$750`

5. Hourly base pay
   - Input: `$150/hour × 8 hours`
   - Expected base: `$1,200`
   - Expected total: `$1,200`

6. Per-day base plus splash and bonus splash
   - Input: `$1,000/day + $100 splash + $200 bonus splash`
   - Expected base: `$1,000`
   - Expected total: `$1,300`

7. Custom flat/per-day bonus included
   - Input: `$1,000/day + Holiday $250 × 1`
   - Expected base: `$1,000`
   - Expected total: `$1,250`

8. Custom per-hour bonus included
   - Input: `$150/hour × 8 hours + Call Back $25 × 8 hours`
   - Expected base: `$1,200`
   - Expected total: `$1,400`

9. Base, splash, custom bonuses, and streak bonus combine once
   - Input: half day at `$1,000/day`, `$100 splash`, `$50 bonus splash`, `Holiday $250 × 1`, `Trauma $75 × 2`, `$500 streak bonus`
   - Expected base: `$500`
   - Expected total: `$1,550`

10. Empty custom bonuses do not change total
    - Input: `$1,000/day + $500 streak bonus`, no custom bonuses
    - Expected base: `$1,000`
    - Expected total: `$1,500`

## Manual UI spot-check path

Use this after app UI changes that could affect calculation previews:

1. Add or use an employer with a site paying `$1,000/day`.
2. Add a flat/per-day custom bonus named `Holiday` with default amount `$250`.
3. Open Add Shift.
4. Select the site.
5. Confirm initial preview total is `$1,000.00`.
6. Toggle `Holiday`.
7. Confirm preview total changes to `$1,250.00`.
8. Confirm a `CUSTOM` line item appears with `$250.00`.
9. Save the shift.
10. Confirm saved shift detail/report total remains `$1,250.00`.

Per-hour custom-bonus manual spot check:

1. Add or use a site paying `$150/hour`.
2. Add a per-hour custom bonus named `Call Back` with default amount `$25/hour`.
3. Open Add Shift and enter `8` hours.
4. Toggle `Call Back`.
5. Confirm preview total is `$1,400.00` (`$1,200 base + $200 custom`).
6. Change hours to `10` before manually editing the bonus quantity.
7. Confirm custom bonus quantity stays aligned to `10` and total becomes `$1,750.00` (`$1,500 base + $250 custom`).

## When to update this checklist

Update this file and `scripts/verify_pay_calculation_cases.py` whenever any of these change:

- Day fraction multipliers
- Hourly/per-day pay formulas
- Splash/bonus splash behavior
- Custom bonus units or quantity behavior
- Streak bonus attribution rules
- Reconciliation-visible totals
