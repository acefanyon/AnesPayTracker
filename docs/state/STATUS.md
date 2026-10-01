# AnesPayTracker Status

Last updated: 2026-10-01

## 2026-10-01 update

- The TestFlight tester has real pay data that exists only on her phone (the iCloud capability is not enabled). Treat her store as irreplaceable.
- Build 4 (data safety): launch never deletes data. The legacy sample-data cleanup was removed, the "delete the store and start fresh" migration fallback was replaced with an error screen, and the store files are copied to `Application Support/StoreBackups/before-build-<N>` (last 3 kept) before each new build opens them. Sample data is only inserted in DEBUG builds.
- Build 5 (Home tab): new first tab showing the current work period (earned so far, payday), the next paycheck (from `StreakEngine.paycheckAggregationRows`, same as the Paycheck Estimator), streak progress and recent shifts. Home replaces the Streaks tab, whose content (`StreakStatusContent`) is linked from Home. Verifier: `scripts/verify_home_screen.py`.
- CI: `.github/workflows/build.yml` runs every `scripts/verify_*.py` and builds Release and Debug for the iOS Simulator on pushes to `main`, `hermes/**` and `claude/**`.
- Build 5 also fixes: (1) editing a saved shift no longer reprices it to the site's current rate; (2) employers without a known pay-period end date no longer have guessed pay-period dates presented as fact (Home hides the work-period card, Pay Periods shows an "estimated" warning, setup warns). Verifier: `scripts/verify_history_and_pay_schedule_safety.py`.
- Test plan: `docs/QA_TEST_PLAN.md`.
- Build 5 adds declaration-level defaults to eight required model properties that were added after their entities were created (e.g. `Employer.defaultOnCallAmount`). Without them, stores from before June 1 failed to migrate; TestFlight stores (June 11+) were never affected. Verifier: `scripts/verify_model_migration_defaults.py`.
- The old sample employer still exists on the tester's phone. Do not delete it (or its sites, which cascade to shifts) until she confirms no real shifts are attached.

## TL;DR (2026-06-28)

AnesPayTracker is code-complete for the current feature set and is in TestFlight feedback iteration.

Current live verification from this resumption pass:

- TestFlight paycheck-calendar correction implemented: employer setup now asks for a known pay-period end date plus the actual paycheck date for that same period, instead of a whole-pay-period delay stepper.
- Oracle case added and passing: June 7–20 work period paid on June 26; next period pays July 10; prior period pays June 12.
- 14/14 `scripts/verify_*.py` scripts passed.
- Generic iOS compile succeeded with signing disabled.
- Build number incremented to `2` for the next TestFlight upload.

## Git state at resumption

Branch:

```text
hermes/initial-mac-plan
```

Remote status observed:

```text
ahead of origin/hermes/initial-mac-plan by 13 commits
```

Working tree before this documentation pass:

```text
?? build/
```

`build/` is local generated/archive output and should not be committed.

## Latest relevant commits observed

```text
c1b61ff chore: add screenshots/ to .gitignore
5392b5e docs: add App Store listing draft — names, description, keywords
b775f12 fix: quarterly payout is last day of month after quarter, not next quarter
b8d5495 fix: payout date defaults to last check of following period, not first
f61686c fix: restore stable BonusPayoutSchedule raw values, fix nil ID collision in calendar grid
287430b feat: add aggregation+payout descriptions to bonus/streak setup, improve earnings verbiage
42fcd07 fix: handle CoreData migration failure gracefully, add default for proratesPartialDay
1d3c1f7 feat: add week view toggle to calendar
```

## Feature status

Completed from prior work:

- Employer/site setup and editing
- Per-day, partial-day, and hourly shift pay
- Custom bonus types with flat/per-day and hourly units
- Bonus payout schedule labels and explanatory copy
- Streak rules and streak bonus reporting
- Single active streak safety rule
- On-call bonus support
- Quarter-hour ceiling rounding via clock-in/out entry
- Calendar month/week views
- Pay period breakdowns and employer filtering
- Earnings report with earned-period breakdowns
- Bonus payout report with bonus-type and payout-schedule breakdowns
- Paycheck Estimator mode with paycheck aggregation rows
- PDF export for earnings, bonus payouts, and paycheck estimator
- Quick Look PDF preview path for safer on-device viewing
- `.ics` file export from Shift Detail plus existing calendar sync path
- App Store listing draft
- App Store screenshots under `screenshots/appstore/`

## Current external/manual release blockers

These are outside normal source-code verification:

1. App Store Connect / TestFlight status check
   - App record and iOS archive/upload path were working as of the last release pass.
   - Previous saved state: version 1.0 uploaded to Apple, export compliance answered, and external TestFlight review was `Waiting for Review`.
   - Hermes could not inspect live review status in this session without App Store Connect authentication.

2. Tester install / real-device QA
   - If TestFlight review has cleared, invite/install for the intended tester set and run the manual real-device pass for scrolling, PDF preview/share, `.ics` export/share, clock-in/out entry, and paycheck estimator readability.

3. Provisioning / signed build maintenance for future uploads
   - Unsigned generic iOS compile succeeds.
   - Prior signed CLI generic build failed with `No profiles for 'com.anespay.tracker' were found`; Xcode Organizer upload was later proven working.
   - For future uploads, prefer Xcode Organizer/automatic signing or rerun CLI signing only after confirming App Store Connect credentials/provisioning setup.

Resolved since the older checklist:

- App icon asset now exists at `AnesPayTracker/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`.

## Verification commands last run

Verifiers:

```bash
for f in scripts/verify_*.py; do python3 "$f"; done
```

Result: all 14 passed on 2026-06-28.

Generic iOS compile without signing:

```bash
xcodebuild -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
```

Result: `BUILD SUCCEEDED` on 2026-06-28.

Older retained verification from previous full release pass:

Simulator build:

```bash
xcodebuild -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build CODE_SIGNING_ALLOWED=NO
```

Result: `BUILD SUCCEEDED`.

Mac Catalyst build:

```bash
xcodebuild -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  build CODE_SIGNING_ALLOWED=NO
```

Result: `BUILD SUCCEEDED`.

Generic iOS compile without signing:

```bash
xcodebuild -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
```

Result: `BUILD SUCCEEDED`.

Signed generic iOS build:

```bash
xcodebuild -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'generic/platform=iOS' \
  build
```

Result: failed due to missing provisioning profile for `com.anespay.tracker`.

## Recommended next slice

Best next low-risk work:

1. Have the user check App Store Connect → AnesPayTracker → TestFlight for the live external review status.
2. If approved, install via TestFlight on the target phone(s) and run the real-device smoke checklist in `docs/PRIVATE_TESTFLIGHT_CHECKLIST.md`.
3. If rejected or still waiting, capture Apple’s exact status/reviewer message before changing code.
4. For the next upload, increment the build number and use Xcode Organizer/automatic signing, since that path already succeeded once.

Best next user/manual step:

- Open App Store Connect and confirm whether external TestFlight review for version 1.0/build 1 is approved, rejected, or still waiting.
- If approved, send/install the TestFlight invite and run the first real-device QA pass.
