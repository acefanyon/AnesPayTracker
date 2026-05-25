# Hermes Session Handoff — AnesPayTracker

Date: 2026-05-24
Branch: `hermes/initial-mac-plan`

## Current status

The app builds for both iOS Simulator and Mac Catalyst, and the latest Mac Catalyst build was launched successfully.

Latest committed app-work commit:

- `1c50543 fix: refine modal scrolling and custom bonuses`

Recent useful commits:

- `1c50543 fix: refine modal scrolling and custom bonuses`
- `9a93ba6 docs: note sheet ux fix progress`
- `2bb9369 fix: improve modal controls and scrolling`
- `d5182cb docs: capture runtime feedback backlog`
- `25b9011 fix: verify iOS and Mac Catalyst builds`

## What was implemented most recently

### Sheet / popup interaction fixes

- Kept the clearer upper-left modal controls that Jason liked:
  - Cancel
  - Back
  - Save / Update
  - Close where applicable
- Added extra bottom scroll room to field-heavy sheets so footer/action bars do not hide the bottom content.
- Added full-height scroll container behavior in Add Shift and Employer Setup.
- On Mac Catalyst, stopped using interactive keyboard-dismiss scrolling because Jason reported sticky/delayed scrolling; iOS keeps interactive keyboard dismissal.

### Employer custom bonus setup

Add Employer now supports employer-level custom bonus types:

- custom bonus name
- per-day/flat or per-hour unit
- default amount/rate

This is in `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift` and persists through a new SwiftData model.

### Shift custom bonus entry

Add Shift now shows employer-configured custom bonuses after the user selects a site for that employer.

For each configured custom bonus, the user can:

- toggle it on/off for the shift
- adjust the amount
- adjust quantity/hours for per-hour bonuses

Enabled custom bonuses are included in the computed shift total and saved with the shift.

Primary files changed:

- `AnesPayTracker/Model/Models.swift`
- `AnesPayTracker/App/AnesPayTrackerApp.swift`
- `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift`
- `AnesPayTracker/Views/Entry/AddShiftView.swift`
- `docs/RUNTIME_FEEDBACK_BACKLOG.md`

## Migration note

A first attempt at custom bonuses compiled but crashed on launch because existing SwiftData stores could not migrate a new required `Shift.customBonuses` attribute.

Fix applied:

- `Shift.customBonuses` is optional (`[AppliedCustomBonus]?`) for backward-compatible migration.
- Total pay uses `(customBonuses ?? [])`.

After this fix, the Mac Catalyst app launched successfully.

## Verified commands

iOS Simulator build:

```bash
xcodebuild -project AnesPayTracker.xcodeproj -scheme AnesPayTracker -destination 'platform=iOS Simulator,name=iPhone 17' build CODE_SIGNING_ALLOWED=NO
```

Mac Catalyst build:

```bash
xcodebuild -project AnesPayTracker.xcodeproj -scheme AnesPayTracker -destination 'platform=macOS,variant=Mac Catalyst' build CODE_SIGNING_ALLOWED=NO
```

Both succeeded after the latest changes.

The Mac Catalyst app was launched from:

```text
/Users/jasonvargas/Library/Developer/Xcode/DerivedData/AnesPayTracker-dhixpulmbnioqnbwrqpfbtohgfaq/Build/Products/Debug-maccatalyst/AnesPayTracker.app
```

## Current git status caveat

Do not accidentally commit local Xcode/signing/user files unless Jason explicitly asks.

Current uncommitted/untracked local files at handoff:

- `AnesPayTracker.xcodeproj/project.pbxproj`
- `.DS_Store`
- `AnesPayTracker.xcodeproj/project.xcworkspace/xcuserdata/`
- `AnesPayTracker.xcodeproj/xcuserdata/`
- `AnesPayTracker/AnesPayTracker.entitlements`

These were intentionally left out of the previous app-work commits.

## Next manual retest Jason should do

1. Add Employer → scroll through every step, especially the bottom of Sites, Custom Bonus Types, and Streak Rules.
2. Add Employer → add a custom bonus, e.g. Holiday, Call Back, Weekend, Trauma.
3. Add Shift → select a site for that employer and confirm the custom bonus appears.
4. Toggle the custom bonus on and verify the total changes.
5. Confirm whether scrolling feels less sticky/delayed on Mac Catalyst.

## Likely next implementation areas

If scrolling/custom bonuses are acceptable:

1. Calendar improvements:
   - weekly view
   - larger date/icon proportions
   - employer breakdown in the “This month” panel

2. Pay-period workflow:
   - filter pay periods by employer
   - reconcile employer/pay-period with paycheck date
   - persistent visible reconciled icon/badge

3. Money-model safety:
   - add tests or a manual calculation checklist before deeper pay/reconciliation changes.

## Important skill/context for next session

If continuing this app, load these skills first:

- `swiftui-mac-catalyst-porting`
- `systematic-debugging`

Then inspect:

```bash
cd /Users/jasonvargas/Projects/AnesPayTracker
git status --short
git branch --show-current
git log --oneline -5
```

Use `docs/RUNTIME_FEEDBACK_BACKLOG.md` as the product backlog source of truth.
