# AnesPayTracker Runtime Feedback Backlog

> **For Hermes:** Use `subagent-driven-development` or a focused implementation pass to work through this backlog in priority order. Keep changes small, verify with iOS Simulator and Mac Catalyst builds, and avoid committing local Apple signing/user-data files.

**Goal:** Capture Jason's first hands-on app review after the Mac Catalyst app opened successfully, then convert the notes into a prioritized implementation backlog.

**Context:** The app now builds for iOS Simulator and Mac Catalyst. This feedback is from manual runtime/UX review, so the next phase should improve usability and product fit rather than only compile success.

---

## Source feedback captured

Date captured: 2026-05-24

Jason observed:

1. Calendar view needs an option to switch to weekly view.
2. Calendar date font/icon proportions look too small compared with surrounding UI.
3. The lower panel labeled "This month" should show which employers are included.
4. Pop-ups / sheets freeze when scrolling in fields.
5. Pop-up upper-left buttons are ambiguous, shown like a `C` with dots; if the function is back/cancel, use a clear back arrow or explicit label.
6. Pay periods look good, but need employer filtering.
7. Pay periods need a reconcile action per employer/pay period.
8. Reconcile action should collect paycheck date.
9. Reconciled pay periods should show a persistent outside/visible reconciled icon so the user does not re-check completed items.
10. Reports should export as CSV or PDF.
11. Add Employers needs to be more robust.
12. Employer pay setup must define whether pay rate is per hour or per day.
13. Employer setup must support splash bonus rate.
14. Employer setup must support additional bonus rates that can be per hour or per day.
15. Bonus labels should be customizable; user should be able to rename "splash" or name other bonus types.
16. Employer setup needs a streak bonus option.
17. If streak bonus is enabled, app should ask how streak is defined: days per period, what period means, and how the bonus pays out: per pay period, per quarter, per month, etc.

---

## Recommended priority order

### Priority 0 — Safety before feature expansion

Before implementing new money features, add or prepare tests around the existing calculation model.

Reason: this app is about pay, bonuses, and reconciliation. New employer/bonus options will be risky without tests.

Candidate files:

- `AnesPayTracker/Model/Models.swift`
- `AnesPayTracker/Engine/StreakEngine.swift`
- future test files under `AnesPayTrackerTests/`

Acceptance criteria:

- There is a repeatable test path for pay calculations.
- Full-day, half-day, hourly, bonus, and streak calculations can be verified automatically or with a documented manual test checklist if test target setup is deferred.

Initial safety pass added 2026-05-25:

- Added `scripts/verify_pay_calculation_cases.py`, a lightweight repeatable calculation oracle for the current `Shift.basePay`, `Shift.totalPay`, and `AppliedCustomBonus.totalAmount` formulas.
- Added `docs/PAY_CALCULATION_SAFETY_CHECKLIST.md` with expected values and manual UI spot-check paths.
- Current script covers full-day, half-day, quarter-day, three-quarter day, hourly, splash, bonus splash, flat/per-day custom bonus, per-hour custom bonus, combined streak/custom/bonus totals, and empty custom-bonus behavior.
- Latest run: `python3 scripts/verify_pay_calculation_cases.py` passed all 10 checks.
- Next improvement: convert the oracle/checklist into a formal XCTest target when project-file test-target setup is safe.

---

### Priority 1 — Fix blocking UX issues in sheets/pop-ups

Status: Initial implementation committed in `2bb9369 fix: improve modal controls and scrolling`.

Client interview follow-up captured 2026-05-25:

- Shift Detail has an odd, non-functional label/control in the upper-left corner.
- Added detailed checklist item in `docs/CLIENT_INTERVIEW_APP_CHECKLIST.md` as `CI-001`.
- Initial fix: Shift Detail now removes the upper-left cancellation toolbar control and uses clear upper-right `Edit` and `Done` actions instead.
- Sticky or delayed scrolling was reported while editing a shift from Calendar.
- Added detailed checklist item in `docs/CLIENT_INTERVIEW_APP_CHECKLIST.md` as `CI-002`.
- Source-level investigation suggests a likely app-level risk in the Calendar edit path: Calendar presents Shift Detail as a sheet, then Shift Detail presents Edit Shift as another sheet. This nested sheet flow should be runtime-tested before changing code; if confirmed, prioritize removing the nested modal flow.

Implemented:

- Replaced ambiguous sheet toolbar controls with labeled icon controls for Cancel, Close, Back, Save, and Update.
- Replaced field-heavy `Form` sheets for Add Contact, Add Site, and Add Streak Rule with explicit `ScrollView` layouts plus bottom action bars.
- Added interactive keyboard dismissal to the field-heavy Add Shift and setup/settings sheets.
- Changed Employer Setup wizard's upper-left control to a real Back control after the first step, while keeping Cancel only on the first step.
- Verified both iOS Simulator and Mac Catalyst builds after the change.

Latest follow-up from Jason:

- Scrolling is improved but still sticky/delayed.
- Some employer screens still do not allow scrolling far enough to see the bottom.
- The clearer upper-left pop-up buttons are good and should be kept.
- Add Employer still needs custom bonus setup.

Second implementation pass:

- Kept the clearer upper-left Cancel/Back controls.
- Added extra bottom scroll room and full-height scroll containers to Employer Setup and Add Shift so bottom content is reachable above footer/action areas.
- Stopped applying interactive keyboard-dismiss scrolling on Mac Catalyst; Catalyst now uses plain scrolling while iOS keeps interactive keyboard dismissal.
- Added employer-level custom bonus types to Add Employer:
  - custom bonus name
  - per-day/flat or per-hour unit
  - default amount/rate
- Added shift-entry support for those employer custom bonuses so the user can toggle configured bonuses on a shift and include them in the total.

Third implementation pass after Jason's follow-up:

- Jason confirmed the upper-left buttons are clear and should be kept.
- Moved custom bonus setup out of the crowded Employer Info screen into its own dedicated Add Employer wizard step.
- Put a prominent Add Custom Bonus button at the top of that step so it is immediately visible instead of hidden below other fields.
- Changed Employer Setup navigation from a fixed sibling footer to a bottom safe-area inset, with extra bottom padding, to reduce Mac Catalyst clipping and unreachable-bottom behavior.
- Reset the wizard scroll position to the top when moving between steps so Back/Next does not preserve a confusing old scroll offset.
- Removed interactive keyboard-dismiss behavior from Settings add-site/add-streak sheets on Mac Catalyst through the shared Catalyst-friendly scroll modifier.
- Fixed Add Shift pay preview so enabled custom bonuses are included in the displayed total and shown as a Custom line item.
- Verified both iOS Simulator and Mac Catalyst builds after these changes.
- Automated runtime clicking was initially blocked by macOS Accessibility control, then re-run after permissions were granted.

Fourth verification pass:

- Rebuilt Mac Catalyst and iOS Simulator successfully.
- Used macOS Accessibility automation to walk through the live Mac Catalyst UI:
  - opened Settings → Add Employer
  - entered `Hermes UI Test Employer`
  - added site `Hermes Main OR` at `$1,000/day`
  - confirmed the dedicated Custom Bonuses step appears between Sites and Streak Rules
  - confirmed `Add Custom Bonus` is immediately visible before any backtracking
  - added `Holiday` at `$250 flat/per day`
  - confirmed the Review screen shows the employer, site, and `Holiday: $250.00 flat/per day`
  - saved the employer
  - opened Add Shift, selected `Hermes Main OR`, toggled `Holiday`, and confirmed the visible pay preview changed from `$1,000.00` to `$1,250.00` with a `CUSTOM $250.00` line item and `Adds $250.00`
  - saved the shift successfully
- Added a small safety fix so per-hour custom bonus quantities stay aligned with edited shift hours unless the user has manually overridden an enabled bonus quantity.

Still needs manual runtime confirmation from Jason:

- Confirm scrolling feels natural by hand on Mac Catalyst, especially with trackpad/mouse-wheel input.

Problem:

Sheets/pop-ups freeze when scrolling in fields, and the upper-left control is ambiguous.

Likely files:

- `AnesPayTracker/Views/Entry/AddShiftView.swift`
- `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift`
- `AnesPayTracker/Views/Settings/SettingsView.swift`
- `AnesPayTracker/Views/Review/ShiftDetailView.swift`

Implementation notes:

- Identify each `.sheet`, `NavigationStack`, `ToolbarItem`, and form containing text fields or pickers.
- Replace ambiguous icon-only controls with clear text labels or standard back/cancel icons.
- For back/cancel actions, prefer labels like `Cancel`, `Back`, `Done`, or a clear `chevron.left` icon with text.
- Investigate whether nested `ScrollView` + `Form` + sheet presentation is causing scroll/focus problems.
- Test each field-heavy pop-up on Mac Catalyst and iPhone Simulator.

Acceptance criteria:

- User can scroll and edit all fields in Add Shift, Employer Setup, Settings, and Shift Detail sheets without freezing.
- Every upper-left sheet/pop-up button has an obvious meaning.
- Mac Catalyst and iOS Simulator still build.

---

### Priority 2 — Employer model expansion for real pay rules

Problem:

Employer setup needs to handle real anesthesia contract pay structures, not just simple default values.

Likely files:

- `AnesPayTracker/Model/Models.swift`
- `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift`
- `AnesPayTracker/Views/Settings/SettingsView.swift`
- `AnesPayTracker/Views/Entry/AddShiftView.swift`
- `AnesPayTracker/Engine/StreakEngine.swift`

Feature requirements:

1. Employer pay rate can be defined as:
   - per hour
   - per day

2. Employer can define a splash bonus rate.

3. Employer can define additional bonus rates:
   - custom bonus name
   - per-hour or per-day unit
   - default amount/rate

4. The label "splash" should be customizable or replaceable by a named bonus type.

5. Employer can enable/disable streak bonus.

6. If streak bonus is enabled, setup asks:
   - how many days/shifts are required
   - what period/window is used, e.g. pay period, month, quarter, rolling period
   - how bonus is paid out, e.g. per pay period, monthly, quarterly, once when achieved
   - bonus amount

Acceptance criteria:

- A user can create an employer whose pay is per-hour or per-day.
- A user can name and configure multiple bonus types.
- Streak bonus settings are visible only when enabled.
- Existing shift entry and calculations still work after migration/model changes.
- iOS Simulator and Mac Catalyst builds succeed.

Open design question:

- Should existing demo/seed employers be migrated to the new bonus model or replaced with new seed data?

---

### Priority 3 — Pay period filtering and reconciliation workflow

Problem:

Pay periods look good, but need employer filtering and a way to mark employer/pay-period combinations as reconciled.

Likely files:

- `AnesPayTracker/Views/Review/PayPeriodView.swift`
- `AnesPayTracker/Model/Models.swift`

Feature requirements:

1. Pay Period screen can filter by employer.
2. Each employer/pay-period row or section has a `Reconcile` button.
3. Pressing `Reconcile` opens a small form asking for paycheck date.
4. Reconciled state is saved persistently.
5. Reconciled items show a clear icon/badge outside the detail flow.
6. User can tell at a glance which employer/pay-periods have already been checked.
7. Ideally user can edit/unreconcile if a mistake was made.

Suggested model concept:

- Add a persistent `PayPeriodReconciliation` model or fields equivalent to:
  - employer/site reference
  - pay period start/end
  - paycheck date
  - reconciled date/time
  - optional notes

Acceptance criteria:

- User can filter pay periods by employer.
- User can mark a specific employer/pay-period as reconciled.
- Reconciled indicator remains after closing/reopening the app.
- The app does not require the user to drill into a pay period to know whether it was already checked.

---

### Priority 4 — Calendar view improvements

Problem:

Calendar view needs better navigation and visual scaling.

Likely file:

- `AnesPayTracker/Views/Review/CalendarView.swift`

Feature requirements:

1. Add toggle/segmented control for:
   - Month view
   - Week view

2. Week view should show the selected week with shifts grouped by day.

3. Increase date font/icon proportions so they match the rest of the screen.

4. Lower panel currently labeled "This month" should also show employer context, such as:
   - all employers
   - selected employer
   - employer breakdown

Acceptance criteria:

- User can switch between month and week views.
- Week view makes near-term schedule review easier.
- Dates/icons are visually balanced on Mac Catalyst.
- Summary panel makes clear which employer(s) are included.

---

### Priority 5 — Report export options

Problem:

Reports should export as CSV as well as PDF.

Likely files:

- `AnesPayTracker/Views/Report/ReportView.swift`
- `AnesPayTracker/Views/Report/PDFReportGenerator.swift`
- New file candidate: `AnesPayTracker/Views/Report/CSVReportGenerator.swift`

Feature requirements:

1. Report export menu offers:
   - PDF
   - CSV

2. CSV includes enough data for spreadsheet review:
   - date
   - employer
   - site/location if applicable
   - shift type or hours/day fraction
   - base pay
   - bonus/splash amounts
   - streak bonus
   - total pay
   - pay period
   - reconciliation status if available

Acceptance criteria:

- User can export PDF as before.
- User can export CSV and open it in Numbers/Excel.
- CSV values match on-screen report totals.

---

## Suggested implementation phases

### Phase A — Stabilize current UI

1. Fix pop-up/sheet scrolling and ambiguous controls.
2. Rebuild iOS Simulator.
3. Rebuild Mac Catalyst.
4. Manually retest setup, add shift, settings, and shift details.

### Phase B — Employer/pay model redesign

1. Inspect existing SwiftData models.
2. Design model changes for pay units, bonus rules, and streak definitions.
3. Add tests or manual calculation checklist.
4. Update employer setup UI.
5. Update shift entry/calculation logic.
6. Verify existing demo/seed data still loads or is migrated.

### Phase C — Pay period reconciliation

1. Add model for reconciliation.
2. Add employer filter.
3. Add reconcile form.
4. Add visible reconciled indicator.
5. Verify persistence after app restart.

### Phase D — Calendar and reports polish

1. Add calendar week/month toggle.
2. Improve calendar sizing and employer summary.
3. Add CSV export.
4. Verify PDF still works.

---

## Verification commands

Use these after meaningful code changes:

```bash
cd /Users/jasonvargas/Projects/AnesPayTracker

xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build

xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Also manually verify the running app after each user-visible feature change.

---

## Do not commit without review

Xcode may create local signing/user files while Jason experiments in the UI. Avoid committing unless intentionally needed:

- `.DS_Store`
- `*.xcuserstate`
- `xcuserdata/`
- personal Apple `DEVELOPMENT_TEAM` settings
- personal signing entitlements unless reviewed
