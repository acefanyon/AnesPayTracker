# Client Interview App Checklist — AnesPayTracker

Date started: 2026-05-25

Purpose: collect client-interview clarifications before turning them into implementation tasks. Keep this as the human-readable checklist, then promote items into `docs/RUNTIME_FEEDBACK_BACKLOG.md` when ready to implement.

## Intake rules

For each client clarification, capture:

1. What the client/user noticed or requested.
2. Where it appears in the app.
3. Why it matters for workflow or trust.
4. Proposed app behavior.
5. Acceptance criteria.
6. Implementation priority.

---

## Captured items

### CI-001 — Shift Detail upper-left label is odd and non-functional

Status: implementation started
Priority: High, small UX/trust fix
Area: Shift Detail
Likely file: `AnesPayTracker/Views/Review/ShiftDetailView.swift`

Observation:

- There is an odd, non-functional Shift Detail label/control in the upper-left corner.
- This appears to be the old toolbar close control in the `.cancellationAction` position.

Why it matters:

- Shift Detail is a review screen. Ambiguous or non-working controls reduce user confidence when checking pay.
- The screen already has an Edit action; closing the detail view should be obvious and reliable.

Proposed behavior:

- Remove the odd upper-left close label/control from Shift Detail.
- Put clear actions in the upper-right area:
  - `Edit` to edit the shift.
  - `Done` to close/dismiss Shift Detail.

Acceptance criteria:

- Shift Detail no longer shows an odd/non-functional label in the upper-left corner.
- User can still close Shift Detail with a clear `Done` button.
- User can still edit the shift with `Edit`.
- iOS Simulator and Mac Catalyst builds still pass.

Implementation note:

- Initial code change made in `ShiftDetailView.swift`: replaced the `.cancellationAction` close toolbar item with a `.confirmationAction` toolbar group containing `Edit` and `Done`.
- Needs runtime confirmation in the Mac Catalyst app.

---

### CI-002 — Sticky or delayed scrolling when editing a shift from Calendar

Status: captured, investigated at source level, not fixed yet
Priority: High if reproducible outside simulator; Medium if simulator-only
Area: Calendar → Shift Detail → Edit Shift
Likely files:

- `AnesPayTracker/Views/Review/CalendarView.swift`
- `AnesPayTracker/Views/Review/ShiftDetailView.swift`
- `AnesPayTracker/Views/Entry/AddShiftView.swift`

Observation:

- Client noticed sticking or delayed scrolling when scrolling down while editing a shift from the Calendar.
- It is not yet clear whether this is true stickiness, delayed input handling, a simulator artifact, or a Mac Catalyst nested-sheet behavior.

Source-level investigation notes:

- Calendar presents Shift Detail with `.sheet(item: $selectedShift)`.
- Shift Detail currently opens Edit Shift with another `.sheet(isPresented: $showEdit)` containing `AddShiftView(editingShift: shift)`.
- That means the Calendar edit path is effectively a sheet opened from inside another sheet.
- `AddShiftView` already uses `ScrollView`, full-height framing, bottom padding, and `CatalystFriendlyScrollDismiss()`, so the most likely app-level cause is not the old `Form` layout.
- A plausible app-level root cause is nested modal presentation on Mac Catalyst/simulator: Calendar sheet → Shift Detail sheet → Edit Shift sheet.
- It may also be worsened by animated expandable sections in Add/Edit Shift, especially Notes, Source Note, custom bonuses, and keyboard/focus handling.

Why it matters:

- Editing a shift is a high-frequency correction workflow.
- If scrolling sticks while editing pay data, the user may think the app is frozen or unreliable.

Proposed behavior options to test before implementing:

1. Reproduce on actual Mac Catalyst build, not only iOS Simulator.
2. Reproduce on iOS Simulator directly from Add Shift and from Calendar → Shift Detail → Edit to compare.
3. If the problem mainly occurs in Calendar → Shift Detail → Edit, avoid nested sheets by changing the edit flow to one of:
   - dismiss Shift Detail and open Edit Shift as a single top-level sheet, or
   - replace nested edit sheet with in-place edit mode inside Shift Detail, or
   - present edit using a full-screen/large modal style that does not stack sheet-on-sheet.
4. If the problem occurs everywhere in Add/Edit Shift, simplify `AddShiftView` scroll behavior further and reduce animated expanding sections.

Acceptance criteria:

- From Calendar, user can open a shift, tap Edit, scroll to the bottom of Edit Shift smoothly, and reach Notes/Source Note/Save controls.
- Same behavior works in Mac Catalyst and iOS Simulator.
- If delay is simulator-only, document that result and verify real Mac Catalyst is acceptable.
- No regression to pay calculation checks or builds.

Recommended next implementation step:

- Do a focused runtime reproduction pass before changing code. If reproduced specifically in the Calendar edit path, prioritize removing the nested sheet flow.

---

### CI-003 — Bonuses should be named and shift-specific, not default site splash bonuses

Status: implemented
Priority: High workflow fit
Area: Employer setup, Add/Edit Shift, reports, pay calculation
Likely files:

- `AnesPayTracker/Model/Models.swift`
- `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift`
- `AnesPayTracker/Views/Settings/SettingsView.swift`
- `AnesPayTracker/Views/Entry/AddShiftView.swift`
- `AnesPayTracker/Views/Review/ShiftDetailView.swift`
- `AnesPayTracker/Views/Report/ReportView.swift`
- `AnesPayTracker/Views/Report/PDFReportGenerator.swift`

Observation:

- The app should not presume that certain sites have a default splash bonus.
- Employers should support named bonus types.
- Add/Edit Shift should also support adding a named one-time bonus on the fly for high-need or hard-to-fill shifts.

Why it matters:

- Real bonuses may be temporary, negotiated, or assigned only to a specific shift.
- Named bonuses are clearer than generic splash/bonus-splash fields when reviewing pay.

Implemented behavior:

- Removed default site splash configuration from the active data model and site setup flows.
- Kept employer-level named custom bonus types.
- Added `Add One-Time Bonus` in Add/Edit Shift for ad hoc high-need bonuses.
- New shift saves store enabled named bonuses in `customBonuses` and clear the legacy splash fields.
- Pay preview, Shift Detail, Pay Period totals, Report totals, PDF reports, and calendar notes now surface named/custom bonus totals.

Acceptance criteria:

- Employer/site setup no longer asks for a default splash bonus.
- Employer setup still lets the user define named bonus types.
- Add/Edit Shift lets the user add, name, and price a one-time bonus without predefining it on the employer.
- Shift totals include named employer bonuses and one-time bonuses exactly once.
- Build and verification scripts pass.

Verification:

- `python3 scripts/verify_bonus_entry_flow.py`
- `python3 scripts/verify_pay_calculation_cases.py`
- `xcodebuild -project AnesPayTracker.xcodeproj -scheme AnesPayTracker -destination 'platform=macOS,variant=Mac Catalyst' build`

---

### CI-004 — Bonus payout reports need payout-period filtering separate from shift earnings

Status: implemented
Priority: High reporting/trust fit
Area: Reports, employer bonus setup, Add/Edit Shift, PDF export
Likely files:

- `AnesPayTracker/Model/Models.swift`
- `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift`
- `AnesPayTracker/Views/Entry/AddShiftView.swift`
- `AnesPayTracker/Views/Report/ReportView.swift`
- `AnesPayTracker/Views/Report/PDFReportGenerator.swift`

Observation:

- It is useful to see what was earned on each shift date, but real pay components do not always pay synchronously.
- Some employer bonuses are paid monthly with a month delay.
- Streak bonuses are usually determined and paid quarterly.
- Calendar quarters are January-March, April-June, July-September, and October-December.

Why it matters:

- Reports that only group by shift/service date can overstate what should actually be expected in a given pay month or quarter.
- The user needs to reconcile bonus payouts separately from regular shift pay.
- Bonus payout reports should still be filterable by employer and site/location.

Implemented behavior:

- Added `BonusPayoutSchedule` for service-date, next monthly payout, and next quarterly payout behavior.
- Employer custom bonus setup and Add/Edit Shift now expose a `When paid` picker.
- Applied custom bonuses persist their payout schedule.
- Reports now have an `Earnings` vs `Bonus Payouts` mode selector.
- Bonus payout reports support This Month, Last Month, This Quarter, Last Quarter, and Custom ranges.
- Bonus payout rows include employer and site/location data and can be filtered/broken down by those dimensions.
- Streak bonuses are included in bonus payout reporting as quarterly payouts.
- PDF export now supports a dedicated `Bonus Payout Report` with payout date, service date, schedule, and amount.

Acceptance criteria:

- User can report bonuses by payout month, payout quarter, or custom payout date range.
- Bonus payout reports can be filtered by employer and site/location.
- Bonus payout reports show a breakdown by employer and by site/location.
- Regular earnings reports by shift date remain available.
- Build and verification scripts pass.

Verification:

- `python3 scripts/verify_bonus_payout_reports.py`
- `python3 scripts/verify_bonus_entry_flow.py`
- `python3 scripts/verify_pay_calculation_cases.py`
- `xcodebuild -project AnesPayTracker.xcodeproj -scheme AnesPayTracker -destination 'platform=macOS,variant=Mac Catalyst' build`

---

## Pending interview notes to add

Add additional client clarifications below as they come in, then promote them into the runtime backlog before coding larger changes.
