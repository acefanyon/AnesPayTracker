# Private TestFlight Checklist — AnesPayTracker

Purpose: get AnesPayTracker onto one or a few real iPhones quickly without doing a full public App Store launch first.

This checklist assumes the preferred path is:

- same app identity
- same bundle ID
- private/internal testing first
- minimal marketing overhead
- keep existing local data continuity intact

## Current known project state

Verified from the repo/machine during the latest resumption pass:

- Project path: `/Users/jasonvargas/Projects/AnesPayTracker`
- Branch: `hermes/initial-mac-plan`
- iOS bundle ID in current project history: `com.anespay.tracker`
- Mac Catalyst bundle ID in current project history: `maccatalyst.com.anespay.tracker`
- Version: `1.0`
- Build number: `1`
- Code signing style: `Automatic`
- Development Team configured locally: present in Xcode build settings
- Static/domain verifiers: passing
- iOS Simulator build: passing
- Mac Catalyst build: passing
- Generic iOS compile with signing disabled: passing
- Signed CLI generic iOS build: blocked by provisioning profile creation/availability

Already prepared:

- App Store listing draft: `docs/APP_STORE_LISTING.md`
- Screenshots: `screenshots/appstore/`

Still missing before a clean upload:

- final app icon in `AnesPayTracker/Assets.xcassets/AppIcon.appiconset/`
- healthy Xcode provisioning/archive path
- App Store Connect app record

## Recommended path

For this app, private TestFlight is the fastest safe release path.

Why:

- you can install the real app on a small set of phones
- you keep the same bundle ID and app identity
- you avoid premature public release work
- you can keep shipping updates without creating a second app

## Part 1 — Pre-flight assets and decisions

### 1. Lock the app identity

Keep using the same iOS bundle ID unless you intentionally want a different app identity:

```text
com.anespay.tracker
```

Do not change the bundle ID casually once you start using TestFlight with real data.

### 2. Choose the app name

Pick one name from:

- `AnesPayTracker`
- `AnesPay`
- `ShiftLedger`
- `PayCheck`
- `CaseCount`

Recommendation for continuity: `AnesPayTracker`

### 3. Add the real app icon

Current state:

- `AppIcon.appiconset/Contents.json` exists
- no actual 1024×1024 icon image is present yet

Before upload:

- create a 1024×1024 PNG
- in Xcode, open `AnesPayTracker/Assets.xcassets/AppIcon.appiconset/`
- drag the icon into the App Store / universal 1024 slot

### 4. Confirm the testing goal

Write down the immediate goal before uploading:

- just your phone
- your phone + spouse
- a few trusted testers

That decision affects whether you use only internal testers or also add external testers later.

## Part 2 — Xcode signing and archive checklist

### 5. Open the project in Xcode

Open:

```text
/Users/jasonvargas/Projects/AnesPayTracker/AnesPayTracker.xcodeproj
```

### 6. Confirm signing in Xcode

In Xcode:

1. Click the project navigator item `AnesPayTracker`
2. Under `TARGETS`, click `AnesPayTracker`
3. Open the `Signing & Capabilities` tab
4. Confirm `Automatically manage signing` is checked
5. Confirm the correct Team is selected
6. Confirm the bundle identifier is still `com.anespay.tracker`

If Xcode shows a provisioning or signing warning here, fix it before archiving.

### 7. Confirm Apple account and app capabilities

Still in Xcode, verify:

- your Apple ID/team is the intended one for this app
- if using iCloud/CloudKit for production sync, capabilities are configured the way you want before release

Important: do not add random capabilities just to make warnings disappear.

### 8. Set version/build if needed

In Xcode target settings, confirm:

- Version = `1.0`
- Build = `1`

If you already archived/uploaded build 1 before, increment Build to `2`.

Rule:

- Version changes when the release meaning changes for humans
- Build changes every upload attempt

### 9. Archive the app

In Xcode menu:

1. `Product` → `Destination` → `Any iOS Device (arm64)` or a connected real iPhone
2. `Product` → `Archive`

Wait for Organizer to open.

Expected result:

- archive completes successfully
- Organizer shows the new AnesPayTracker archive

If archive fails:

- fix signing/profile issues in Xcode first
- do not change bundle ID unless you explicitly intend a new app identity

## Part 3 — App Store Connect setup

### 10. Create the app record if it does not exist yet

In App Store Connect:

1. Go to `Apps`
2. Click the `+` button
3. Choose `New App`
4. Fill in:
   - Platform: `iOS`
   - Name: your chosen app name
   - Primary language: your choice, likely `English (U.S.)`
   - Bundle ID: `com.anespay.tracker`
   - SKU: simple internal identifier, e.g. `anespaytracker-ios-001`
5. Click `Create`

### 11. Fill only the minimum metadata needed for TestFlight-first progress

Use `docs/APP_STORE_LISTING.md` as the source.

Minimum items to prepare now:

- app name
- subtitle if needed
- description draft
- keywords
- privacy policy URL
- support URL if Apple requires it in your flow

Important: TestFlight-first does not require you to perfect the full public marketing page before proceeding.

### 12. Privacy policy

Current repo note says a simple hosted privacy page is enough because data is local and calendar access is opt-in.

Before public/external flows, make sure you have a real URL for:

- privacy policy

If you do not already have one, create a simple hosted page before going too far with external testing.

## Part 4 — Upload and TestFlight setup

### 13. Upload from Xcode Organizer

In Organizer:

1. Select the archive
2. Click `Distribute App`
3. Choose `App Store Connect`
4. Choose `Upload`
5. Keep defaults unless Xcode shows a specific issue you understand
6. Complete validation and upload

Expected result:

- upload succeeds
- build appears in App Store Connect after processing

### 14. Wait for processing

In App Store Connect:

- open your app
- open `TestFlight`
- wait for the uploaded build to finish processing

This can take a while.

### 15. Add internal testers first

Best first move:

- add only yourself or a very small internal group first

Why:

- fastest path
- lowest friction
- easiest way to verify install/update behavior

### 16. Install from TestFlight on the target phone

On the iPhone:

1. Install Apple’s `TestFlight` app if needed
2. Accept the invite
3. Install AnesPayTracker
4. Open the app and verify it launches cleanly

## Part 5 — First real-device TestFlight smoke checklist

After install, manually check these high-value flows:

### 17. App launch and seeded data

- app launches without crash
- seed/demo data behavior is as expected
- no obvious layout break on the target phone

### 18. Shift entry

- create a shift
- choose employer/site
- use partial-day or hourly entry
- if using hourly, verify clock-in/clock-out and quarter-hour ceiling behavior
- save successfully

### 19. Reports

- open Earnings
- open Bonus Payouts
- open Paycheck Estimator
- verify filters and visible tables feel good on-device
- generate PDF and confirm preview/share path still works

### 20. Calendar export

- open a shift detail
- create `.ics` file
- share/export it successfully

### 21. Settings/editing

- edit employer/site/streak related settings
- verify no obvious scroll or save regressions

### 22. Update/install confidence

After a later TestFlight build:

- update the app from TestFlight instead of reinstalling
- confirm existing data remains intact

## Part 6 — Common blockers and what they mean

### Archive fails before upload

Usually means one of:

- signing/team mismatch
- provisioning profile issue
- capability mismatch
- missing required metadata/certificate state

### Upload fails in Organizer

Usually means one of:

- bundle ID/app record mismatch
- version/build duplication
- missing icon or asset requirement
- signing/archive issue

### Build processes forever in App Store Connect

Usually just needs time, but if it later errors:

- read the exact processing message
- fix the specific issue instead of changing unrelated settings

### TestFlight install works but the app feels wrong on device

That is a product QA issue, not a signing issue.

Record the exact screen, action, and symptom, then patch the app and upload a new build number.

## Part 7 — Suggested first-pass execution order

If you want the least-risk order, do it like this:

1. Add real app icon
2. Open Xcode and confirm Signing & Capabilities
3. Archive successfully
4. Create App Store Connect app record if needed
5. Upload archive to App Store Connect
6. Wait for TestFlight processing
7. Install on your phone through TestFlight
8. Run the smoke checklist above

## Part 8 — What to avoid

- Do not change bundle ID casually
- Do not create a second “practice” app unless you intentionally want separate data/app identity
- Do not uninstall/reinstall a live app casually once real data matters
- Do not solve signing errors by random capability toggling
- Do not treat a successful simulator build as equivalent to TestFlight/device readiness

## Repo files to use during this phase

- `docs/APP_STORE_LISTING.md`
- `docs/state/STATUS.md`
- `screenshots/appstore/`
- `AnesPayTracker/Assets.xcassets/AppIcon.appiconset/`

## Suggested next Hermes step after this checklist

After you work through the first 4–6 checklist items manually, the best next Hermes task is:

- review the archive/signing error if one appears, or
- prepare a final real-device TestFlight smoke script/checklist tied to your phone-based QA pass
