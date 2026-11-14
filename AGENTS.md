# AGENTS.md — AnesPayTracker

This is the tool-agnostic entrypoint for anyone resuming work on AnesPayTracker: people, and coding agents such as Codex, Claude Code and Hermes. Tools that look for their own file name (for example `CLAUDE.md`) are pointed here; keep project instructions in this file only.

## Project

AnesPayTracker is a native SwiftUI / SwiftData iOS app for tracking contract anesthesiology shift pay, bonuses, streaks, pay periods, paycheck estimation, calendar exports, and reports.

## Source of truth and syncing

- The GitHub repository `acefanyon/AnesPayTracker` is the source of truth. Every computer and agent works in its own clone and syncs only through GitHub.
- Work on the `main` branch. Short-lived feature branches are fine, but merge them back into `main` promptly.
- Clone locations differ per machine (on Jason's Macs it is usually `~/Projects/AnesPayTracker`). Run every command in this file from the repository root, wherever that is.
- **Pull before starting, push when done.** Unpushed work exists only on that one machine; another computer or agent cannot see it.

```bash
git pull --ff-only     # before starting
git push               # after committing
```

If `git pull --ff-only` refuses, the clone has local commits that are not on GitHub: stop and reconcile them rather than discarding them.

## Building, by platform

- The source is plain text (Swift, a standard Xcode project, Markdown, Python verifiers); any editor or agent can read and change it.
- **Building and running the app requires macOS with Xcode.** Agents on Linux or other non-macOS hosts (for example cloud sandboxes) cannot compile it. They must run the verifier scripts below and rely on GitHub Actions (`.github/workflows/build.yml`), which runs every verifier and compiles Release and Debug for the iOS Simulator on each push to `main`, `hermes/**` and `claude/**`.
- A pushed change is not done until that workflow passes.

## Start here every session

1. Inspect live state, not memory alone, from the repository root:

```bash
git fetch origin
git status --short --branch
git pull --ff-only
git log --oneline -8
```

2. Read current status:

```text
docs/state/STATUS.md
```

3. If you need product/history context, read:

```text
docs/CASE_TIME_AND_INVOICING_PLAN.md   (current feature work: case time, invoices)
docs/QA_TEST_PLAN.md
docs/RUNTIME_FEEDBACK_BACKLOG.md
docs/APP_STORE_LISTING.md
docs/HERMES_SESSION_HANDOFF.md
README.md
```

Note: `docs/HERMES_SESSION_HANDOFF.md` is older historical context. Prefer `docs/state/STATUS.md` plus live git/test output for current state.

## Safety rules

- This is a money/pay app. Do not change pay, bonus, streak, payout, paycheck, or rounding rules without adding/updating a verifier.
- Preserve history safety: employer/site/rate/rule changes must not silently rewrite past shifts.
- Testers' pay records exist only on their phones (the iCloud capability is not enabled). Launch must never delete or reset the store: a store that cannot be opened shows `StoreOpenFailedView`, and `StoreSafety` copies the store aside before each new build opens it.
- Keep SwiftData migrations lightweight-safe. New non-optional `@Model` properties need declaration-level defaults or optional storage (`scripts/verify_model_migration_defaults.py`).
- Editing a saved shift keeps its saved rate (`Shift.baseAmount`); only a new shift or a site change takes the site's current rate.
- Bind list rows by ID (`$array.element(item)`), never `ForEach($array)`; index-based row bindings crash when the list shrinks (`scripts/verify_list_binding_safety.py`).
- Never store patient information. Cases hold times only, and nothing identifying goes on an invoice.
- Do not commit real names, addresses, phone numbers or employer names; examples and tests use made-up data.
- Do not rename persisted `String` enum raw values after shipped/test data exists. Add `displayName`/`descriptiveLabel` instead.
- Do not commit local Xcode user data, `.DS_Store`, signing noise, or build archives.
- Keep product changes small and independently verifiable.

## Domain rules that have been corrected and must remain stable

- Per-day / flat bonuses can prorate for partial-day shifts via per-bonus toggle.
- On-call bonus does not prorate by day fraction.
- Streak bonus prorates by day fraction when earned on a partial-day shift.
- Clock-in / clock-out rounding uses ceiling to the next quarter hour.
- Paycheck estimator now stores two anchors for employer paycheck calendars: a known pay-period end date and the actual paycheck date for that same period. Example: work period Jun 7–20 paid on Jun 26 uses period-end anchor Jun 20 and paycheck anchor Jun 26. Do not model this as a whole-pay-period delay stepper.
- Monthly pay cadence with both anchors keeps the anchor pairing month to month: period ending Oct 31 paid Nov 15 means period ending Nov 30 is paid Dec 15 (`PaycheckDateMath`).
- Case-time sites (employer "paid for case time only"): each case counts whole minutes from start to stop, a running case counts nothing, the day's minutes are summed and raised to the employer's daily minimum if set, and base pay is rate × minutes ÷ 60 rounded to the nearest cent. Example: 7 h 31 m at $400/hr = $3,006.67. A shift keeps its saved cases, rate and minimum.
- Invoices: number is employer code, site code and invoice date as MMDDYY (`EN-BM-041326`), with `-2`, `-3` … when taken. A created invoice is a frozen copy in whole cents; later shift edits never change it, and deleting an invoice never touches shifts. Streak bonuses are not invoiced. A shift is on at most one invoice.
- Monthly aggregation payout defaults to the last day/check of the following month.
- Quarterly aggregation payout defaults to the last day/check of the month after the quarter ends: Q1 → Apr 30, Q2 → Jul 31, Q3 → Oct 31, Q4 → Jan 31.

## Verification commands

Run all static/domain verifiers:

```bash
for f in scripts/verify_*.py; do python3 "$f"; done
```

These run on any platform with Python 3. Add or update a verifier with every behavior change.

Run the real Swift pay math (case time, monthly paydays) outside the app; needs a Swift toolchain, and CI runs it on every push:

```bash
swiftc -o /tmp/pay_math_tests \
  AnesPayTracker/Engine/CaseTimeCalculator.swift \
  AnesPayTracker/Engine/PaycheckDateMath.swift \
  AnesPayTracker/Engine/InvoiceMath.swift \
  scripts/swift_tests/pay_math/main.swift && /tmp/pay_math_tests
```

Keep pay math in Foundation-only files like these so it can be tested this way.

Build for the iOS Simulator exactly as CI does (works on a fresh clone; macOS only):

```bash
xcodebuild -project AnesPayTracker.xcodeproj -target AnesPayTracker \
  -sdk iphonesimulator -configuration Release build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" ARCHS=arm64
```

The `-scheme` commands below need a scheme; on a fresh clone, open the project in Xcode once if `xcodebuild` reports that the scheme is missing.

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

- App icon, App Store Connect app record and TestFlight distribution are in place; 1.1 (6) is installed on the testers' phones (see `docs/state/STATUS.md`).
- Build numbers: Xcode Organizer can auto-assign the next unused build number on upload, so App Store Connect can be ahead of the source. Check App Store Connect's TestFlight build list before choosing the next number.
- Archiving and uploading need Xcode on a Mac signed in to the Apple developer account (Xcode → Settings → Accounts) on that Mac.

Remaining before a public App Store release: privacy policy page, App Privacy questionnaire, age rating, review submission.

## Useful code map

- `AnesPayTracker/Model/Models.swift` — SwiftData models and pay-related enums/value types
- `AnesPayTracker/Engine/StreakEngine.swift` — streak computation, pay periods, bonus payout and paycheck aggregation logic
- `AnesPayTracker/Engine/CaseTimeCalculator.swift` — `ShiftCase` and case-time pay math (Foundation only)
- `AnesPayTracker/Engine/PaycheckDateMath.swift` — monthly payday math (Foundation only)
- `AnesPayTracker/Engine/InvoiceMath.swift` — invoice numbering, cents and frozen invoice content (Foundation only)
- `AnesPayTracker/Engine/InvoiceBuilder.swift` — turns saved shifts into invoice days
- `AnesPayTracker/Engine/CalendarSync.swift` — EventKit and `.ics` export
- `AnesPayTracker/Views/Entry/AddShiftView.swift` — shift entry, custom bonuses, clock-in/out rounding UI
- `AnesPayTracker/Views/Entry/CaseTimeEntry.swift` — case list editor inside Add/Edit Shift
- `AnesPayTracker/Views/Entry/CaseTrackerCard.swift` — Start/Stop Case on Home (`CaseTracker`)
- `AnesPayTracker/Views/Home/HomeView.swift` — Home tab: work period, next paycheck, streaks, recent shifts
- `AnesPayTracker/Views/Review/CalendarView.swift` — month/week calendar and day sheets
- `AnesPayTracker/Views/Review/PayPeriodView.swift` — pay period view/filtering/reconciliation UI
- `AnesPayTracker/Views/Review/ShiftDetailView.swift` — shift details, pay breakdown, `.ics` sharing
- `AnesPayTracker/Views/Report/ReportView.swift` — earnings, bonus payout, paycheck estimator UI
- `AnesPayTracker/Views/Report/PDFReportGenerator.swift` — report PDF generation
- `AnesPayTracker/Views/Report/InvoicePDFGenerator.swift` — invoice PDF layout
- `AnesPayTracker/Views/Invoices/` — invoice list, new-invoice form and invoice detail (opened from Report)
- `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift` — initial employer/pay/bonus/streak/paycheck setup
- `AnesPayTracker/Views/Settings/SettingsView.swift` — editing employers/sites/rules and calendar settings

## Commit guidance

Before committing:

```bash
git diff --check
git status --short
```

Commit only intentional source/docs/script changes. Avoid `build/`, `screenshots/`, `.DS_Store`, and Xcode `xcuserdata`. Then `git push`, and check that the GitHub Actions run passes.
