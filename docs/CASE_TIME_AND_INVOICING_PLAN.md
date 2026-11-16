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
4. **Daily minimum (optional).** An employer can guarantee a minimum number of paid hours on a light day. Off unless set. Confirmed by the employer 2026-11-14: the minimum for a half day is $2,000, which at $400/hr is entered as **5 hours**. Clarified 2026-11-14: there is no separate full-day minimum. The half-day minimum is the floor for a day scheduled as a full day that ends early. The app has one minimum per employer; it applies to each new shift by default and can be switched off on a single shift it doesn't cover (**Daily minimum applies** in Add/Edit Shift). A shift saved without the minimum stays without it.
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

## Phase 2 — invoices (built, build 7, not yet tested on a phone)

Where: Report tab → **Invoices**.

Rules:
- One PDF invoice per employer for a date range (she submits one every two weeks), covering all of that employer's sites. Any employer can be invoiced, not only case-time ones.
- The top shows the user's name, address, phone and email (kept in app settings on the device); "Invoice for" shows the employer's billing name and address.
- Each day names its site, then lists its cases in clock order as "Anesthesia services, case 1" with start and stop times and duration, then its charges (anesthesia time at the rate, on-call, each add-on such as a recovery fee) and a day total. A day raised to the daily minimum says so and shows the time worked.
- Streak bonuses are not invoiced: they are paid on their own schedule.
- Invoice number: two-character employer code and the date the invoice is made, as MMDDYY, for example `EN-041326`. The code is suggested from the employer's name, editable, and saved on the employer. If the number is already used, `-2`, `-3` … is added. (Decided 2026-11-14; an earlier draft also had a site code.)
- The due date is optional. When the employer's paycheck anchors are set it defaults to the payday for the last service date.
- A shift can be on only one invoice. A day with a running case cannot be invoiced. A day with nothing to bill is skipped.
- A created invoice is a frozen copy (`Invoice.snapshotData`, money in whole cents). Editing or deleting its shifts later does not change it; the invoice screen flags that they changed. To bill new amounts, delete the invoice and create it again.
- Deleting an invoice never touches shifts; they can be invoiced again.
- No patient information: case lines hold a generic label and times only.

Code: `Engine/InvoiceMath.swift` (numbering, cents, frozen content; Foundation only, run by `scripts/swift_tests/pay_math`), `Engine/InvoiceBuilder.swift` (shift → invoice day), `Views/Report/InvoicePDFGenerator.swift`, `Views/Invoices/`. Verifier: `scripts/verify_invoices.py`. Manual tests: section C13 of `docs/QA_TEST_PLAN.md`.

Open questions: payment-terms wording; whether the app should suggest the two-week invoice period automatically (today it defaults to everything not yet invoiced since the start of last month).

## Phase 3 — invoice tracking

Draft / sent / paid, paid date, "next invoice due" on Home. Pay cadence and invoice frequency are separate settings.

## Phase 4 — reports and year-end

Per-employer and productivity reports (days, cases, case hours, add-ons, earnings per hour) as PDF and CSV. Year-end income summary by employer and quarter for an accountant. The app does not produce official tax forms.

## Phase 5 — Apple Watch and Lock Screen

Start/end shift and start/stop case from the Watch and the iPhone Lock Screen, built on `CaseTracker`.

## App structure: the next major version (direction, not yet built)

The next major version is a UI overhaul, organised by how often each function is used: Today (start/stop, today's entry, earnings), Schedule (calendar), Admin (pay periods, invoices, reports, exports), with setup behind a gear icon. New features are placed where they will live after the tabs are merged.

Goal set by Jason on 2026-11-16: the overhaul is built to Apple's current Human Interface Guidelines and App Store Review Guidelines (see "Interface and Apple platform guidelines" in `AGENTS.md`). That means:

- Start by reviewing every existing screen against the current guidelines (screenshots or a Simulator session on a Mac) and listing the gaps. Fold those gaps into the overhaul instead of fixing them one at a time beforehand.
- Design the new screens from current guidelines, not from the existing screens.
- Test with the largest text size, Dark Mode and VoiceOver as part of the QA pass for the overhaul.
- The overhaul is also the natural point to prepare the public App Store release, which is reviewed against the same guidelines.
