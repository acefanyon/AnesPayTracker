# AnesPayTracker Status

Last updated: 2026-06-11 10:06 MST

## TL;DR

AnesPayTracker is code-complete for the current feature set and is in release-polish / TestFlight-App Store preparation state.

Current live verification from this resumption pass:

- 14/14 `scripts/verify_*.py` scripts passed.
- iOS Simulator build for `iPhone 17` succeeded with signing disabled.
- Mac Catalyst build succeeded with signing disabled.
- Generic iOS compile succeeded with signing disabled.
- Signed generic iOS CLI build is currently blocked by missing provisioning profile for `com.anespay.tracker` unless Xcode is allowed to create/update provisioning.

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

1. App icon
   - `AnesPayTracker/Assets.xcassets/AppIcon.appiconset/` currently only has metadata, not a finished 1024x1024 icon set.

2. Provisioning / signed device build
   - Unsigned generic iOS compile succeeds.
   - Signed CLI generic build failed with:

```text
No profiles for 'com.anespay.tracker' were found
```

   - Likely resolution: use Xcode with automatic signing/provisioning, or rerun with `-allowProvisioningUpdates` only after confirming Apple ID/team setup.

3. App Store Connect / TestFlight setup
   - Create app record using current bundle ID if not already created.
   - Archive/upload through Xcode Organizer once provisioning is healthy.

4. Final human QA
   - Manual real-device pass for scrolling, PDF preview/share, `.ics` export/share, clock-in/out entry, and paycheck estimator readability.

## Verification commands last run

Verifiers:

```bash
for f in scripts/verify_*.py; do python3 "$f"; done
```

Result: all 14 passed.

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

1. Add/keep repo-local agent entrypoint and status docs so future sessions resume cleanly.
2. Ignore local `build/` output so archive products do not dirty git status.
3. After docs are committed, choose one release path:
   - Private TestFlight first, if the goal is real use by a small number of testers.
   - Full public App Store submission, if branding/icon/legal metadata are ready.

Best next user/manual step:

- Decide whether to proceed as private TestFlight first or public App Store submission.
- Provide or approve an app icon direction.
- In Xcode, verify signing/provisioning under `Target → Signing & Capabilities` and create/upload an archive.
