# AGENTS.md — AnesPayTracker

This is the model-agnostic entrypoint for agents resuming work on AnesPayTracker.

## Project

AnesPayTracker is a native SwiftUI / SwiftData iOS app for tracking contract anesthesiology shift pay, bonuses, streaks, pay periods, paycheck estimation, calendar exports, and reports.

Repository path:

```text
/Users/jasonvargas/Projects/AnesPayTracker
```

Current branch:

```text
hermes/initial-mac-plan
```

## Start here every session

1. Inspect live state, not memory alone:

```bash
cd /Users/jasonvargas/Projects/AnesPayTracker
git status --short --branch
git log --oneline -8
```

2. Read current status:

```text
docs/state/STATUS.md
```

3. If you need product/history context, read:

```text
docs/RUNTIME_FEEDBACK_BACKLOG.md
docs/APP_STORE_LISTING.md
docs/HERMES_SESSION_HANDOFF.md
README.md
```

Note: `docs/HERMES_SESSION_HANDOFF.md` is older historical context. Prefer `docs/state/STATUS.md` plus live git/test output for current state.

## Safety rules

- This is a money/pay app. Do not change pay, bonus, streak, payout, paycheck, or rounding rules without adding/updating a verifier.
- Preserve history safety: employer/site/rate/rule changes must not silently rewrite past shifts.
- Keep SwiftData migrations lightweight-safe. New non-optional `@Model` properties need declaration-level defaults or optional storage.
- Do not rename persisted `String` enum raw values after shipped/test data exists. Add `displayName`/`descriptiveLabel` instead.
- Do not commit local Xcode user data, `.DS_Store`, signing noise, or build archives.
- Keep product changes small and independently verifiable.

## Domain rules that have been corrected and must remain stable

- Per-day / flat bonuses can prorate for partial-day shifts via per-bonus toggle.
- On-call bonus does not prorate by day fraction.
- Streak bonus prorates by day fraction when earned on a partial-day shift.
- Clock-in / clock-out rounding uses ceiling to the next quarter hour.
- Paycheck estimator now stores two anchors for employer paycheck calendars: a known pay-period end date and the actual paycheck date for that same period. Example: work period Jun 7–20 paid on Jun 26 uses period-end anchor Jun 20 and paycheck anchor Jun 26. Do not model this as a whole-pay-period delay stepper.
- Monthly aggregation payout defaults to the last day/check of the following month.
- Quarterly aggregation payout defaults to the last day/check of the month after the quarter ends: Q1 → Apr 30, Q2 → Jul 31, Q3 → Oct 31, Q4 → Jan 31.

## Verification commands

Run all static/domain verifiers:

```bash
for f in scripts/verify_*.py; do python3 "$f"; done
```

Build iOS Simulator:

```bash
xcodebuild -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build CODE_SIGNING_ALLOWED=NO
```

Build Mac Catalyst without signing:

```bash
xcodebuild -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  build CODE_SIGNING_ALLOWED=NO
```

Compile generic iOS without signing:

```bash
xcodebuild -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
```

A signed generic/device/archive build may require Xcode-managed provisioning profiles and a connected/trusted device or App Store Connect setup.

## Release readiness notes

Already prepared:

- App Store listing draft: `docs/APP_STORE_LISTING.md`
- App Store screenshots: `screenshots/appstore/`
- Current bundle ID observed in builds: `com.anespay.tracker` for iOS, `maccatalyst.com.anespay.tracker` for Catalyst
- Team ID observed from Xcode build settings: configured locally, but provisioning can still fail from CLI if profiles are absent

Known likely remaining external/manual items:

- Real app icon in `AnesPayTracker/Assets.xcassets/AppIcon.appiconset/`
- Confirm Apple Developer/App Store Connect account path
- Create App Store Connect app record if submitting/TestFlighting
- Archive/upload via Xcode Organizer after provisioning is healthy
- Manual real-device QA for final scrolling/share/export feel

## Useful code map

- `AnesPayTracker/Model/Models.swift` — SwiftData models and pay-related enums/value types
- `AnesPayTracker/Engine/StreakEngine.swift` — streak computation, pay periods, bonus payout and paycheck aggregation logic
- `AnesPayTracker/Engine/CalendarSync.swift` — EventKit and `.ics` export
- `AnesPayTracker/Views/Entry/AddShiftView.swift` — shift entry, custom bonuses, clock-in/out rounding UI
- `AnesPayTracker/Views/Review/CalendarView.swift` — month/week calendar and day sheets
- `AnesPayTracker/Views/Review/PayPeriodView.swift` — pay period view/filtering/reconciliation UI
- `AnesPayTracker/Views/Review/ShiftDetailView.swift` — shift details, pay breakdown, `.ics` sharing
- `AnesPayTracker/Views/Report/ReportView.swift` — earnings, bonus payout, paycheck estimator UI
- `AnesPayTracker/Views/Report/PDFReportGenerator.swift` — report PDF generation
- `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift` — initial employer/pay/bonus/streak/paycheck setup
- `AnesPayTracker/Views/Settings/SettingsView.swift` — editing employers/sites/rules and calendar settings

## Commit guidance

Before committing:

```bash
git diff --check
git status --short
```

Commit only intentional source/docs/script changes. Avoid `build/`, `screenshots/`, `.DS_Store`, and Xcode `xcuserdata`.
