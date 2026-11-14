# Case-Time Pay and Invoicing Plan

Started 2026-11-14. Owner: Jason. Primary user: his wife, who has a new employer that pays by the hour for case time only and needs invoices.

Do not put real names, addresses, phone numbers or employer names in this repository. Examples below use made-up amounts.

## Rules (decided)

Source: the employer agreement, as read by Jason on 2026-11-14.

1. **Case time.** The employer pays an hourly rate for time spent providing anesthesia, not for time between cases.
   - A shift is a list of cases, each with a start and stop time.
   - Each case counts whole minutes (seconds are dropped). A case still running counts nothing.
   - The day's minutes are added up. Base pay = rate × minutes ÷ 60, rounded to the nearest cent.
   - Example: 7 h 31 m at $400/hr = $3,006.67.
   - Confirmed by the user 2026-11-14: exact minutes, no rounding to quarter or half hours.
2. **Employer-level setting.** "Paid for case time only" is set on the employer and applies to all of its per-hour sites. A site can turn it off.
3. **Flat add-ons.** Extra duties (for example staying to recover the last patient) are flat fees the user marks herself. These are the existing custom bonus types: flat, not prorated, paid with the shift.
4. **Daily minimum (optional).** An employer can guarantee a minimum number of paid hours on a light day. Off unless set. Confirmed by the employer 2026-11-14: the minimum for a half day is $2,000, which at $400/hr is entered as **5 hours**. Open: whether a full day has its own, higher minimum. The app has one minimum per employer, applied to every shift.
5. **Pay timing.** Paid by the 15th of each month for the prior month: monthly cadence, period-end anchor on a month end, paycheck anchor on the following 15th. The user's other employers pay every two weeks, so the monthly payday fix does not change their paydays.
6. **History safety.** A shift keeps how it was saved (cases or plain hours), its rate and its minimum. Changing employer settings never changes past shifts.
7. **Privacy.** Cases store times only. No patient information anywhere, including invoices.

## Phase 1 — case-time pay (built 2026-11-14, build 7)

- `Engine/CaseTimeCalculator.swift`: `ShiftCase` and all case-time math (Foundation only).
- `Engine/PaycheckDateMath.swift`: monthly payday from the two anchors. This fixed monthly employers with anchors, whose paydays were a month late.
- `Employer.paysCaseTimeOnly`, `Employer.dailyMinimumHours`, `Site.optsOutOfCaseTime`, `Shift.cases`, `Shift.guaranteedMinimumHours`.
- `Views/Entry/CaseTimeEntry.swift`: case list in Add/Edit Shift (type times, correct them, Start Now / Stop Now).
- `Views/Entry/CaseTrackerCard.swift`: Start Case / Stop Case on Home.
- Shift detail lists the cases; reports, PDFs and calendar exports show paid time as "7 h 31 m".
- Checks: `scripts/verify_case_time_pay.py`, and `scripts/swift_tests/pay_math` (runs the real Swift math in CI).

Known limits:
- The daily minimum is applied per shift. Two shifts on one day for the same employer would each get it.
- A case that runs past midnight stays on the shift's start day.

## Phase 2 — invoices (next)

Decided:
- One PDF invoice for a date range, employer and site.
- Shows the user's name and address, and the employer's name and address.
- Each day lists its cases in clock order as "Anesthesia services, case 1" with start and stop times and duration, then add-ons, any minimum adjustment, and a daily total.
- Invoice number: employer code, site code, date as MMDDYY, for example `EN-BM-041326`. Two-letter codes are stored on the employer and the site and are editable. A letter suffix is added if the number is already used.
- A sent invoice is frozen: later edits to shifts do not change it; the app flags that the shifts changed.

Needs: a "my details" settings screen (name, address, phone), employer billing address, employer and site codes, an `Invoice` record (number, range, issued date, status, frozen line items).

Open questions: which date the number uses (invoice date assumed); payment terms text; whether one invoice may cover more than one site.

## Phase 3 — invoice tracking

Draft / sent / paid, paid date, "next invoice due" on Home. Pay cadence and invoice frequency are separate settings.

## Phase 4 — reports and year-end

Per-employer and productivity reports (days, cases, case hours, add-ons, earnings per hour) as PDF and CSV. Year-end income summary by employer and quarter for an accountant. The app does not produce official tax forms.

## Phase 5 — Apple Watch and Lock Screen

Start/end shift and start/stop case from the Watch and the iPhone Lock Screen, built on `CaseTracker`.

## App structure (direction, not yet built)

By how often each function is used: Today (start/stop, today's entry, earnings), Schedule (calendar), Admin (pay periods, invoices, reports, exports), with setup behind a gear icon. New features are placed where they will live after the tabs are merged.
