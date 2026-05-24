# AnesPayTracker Mac App Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task after Xcode is installed/selected. Follow TDD where tests can be added without fighting Xcode project generation.

**Goal:** Turn the current Replit-generated SwiftUI iOS/iPad app into a working Mac app suitable for local use and later packaging for Jason's wife.

**Architecture:** The fastest reliable path is Mac Catalyst first, because the app already uses SwiftUI plus UIKit-only report/share code (`UIGraphicsPDFRenderer`, `UIFont`, `UIColor`, `UIActivityViewController`). A fully native macOS target is possible later, but it would require AppKit replacements for PDF rendering/share flows and more platform conditionals.

**Tech Stack:** SwiftUI, SwiftData, EventKit, CloudKit optional, Mac Catalyst, Xcode 15+/16+, macOS 14+.

---

## Current Repository State

Local path:

```text
/Users/jasonvargas/Projects/AnesPayTracker
```

GitHub repo:

```text
acefanyon/AnesPayTracker
```

Current branch created by Hermes:

```text
hermes/initial-mac-plan
```

Important findings:

- The repo contains an Xcode project: `AnesPayTracker.xcodeproj`.
- The project currently targets iOS/iPad only: `TARGETED_DEVICE_FAMILY = "1,2"`.
- The README explicitly lists Mac Catalyst/native macOS as unfinished work.
- No Xcode installation is active on this machine. `xcodebuild` currently points to Command Line Tools and fails with:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

- There are no test targets or test files yet.
- The generated app claims feature completeness, but it has not been build-verified locally.

---

## Key Technical Choice

### Recommended first milestone: Mac Catalyst

Use Mac Catalyst rather than a separate native AppKit macOS target for the first working Mac build.

Why:

- Existing PDF code imports UIKit.
- Existing share sheet uses `UIViewControllerRepresentable` and `UIActivityViewController`.
- Existing project settings are iOS-family oriented.
- Catalyst can reuse most of the generated app with fewer rewrites.
- It gets a real `.app` for Mac faster, which is the immediate goal.

### Later milestone: native macOS polish

After Catalyst works, optionally add native macOS refinements:

- `NavigationSplitView` layout for wider screens.
- AppKit-native PDF/share handling.
- Menu commands for Add Shift, Export Report, Settings.
- Keyboard shortcuts.
- Better window sizing.

---

## Phase 0 — Local Xcode prerequisite

### Task 0.1: Install/select full Xcode

**Objective:** Make local builds possible.

**Files:** none.

**Steps:**

1. Install Xcode from the Mac App Store or Apple Developer site.
2. Select it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Expected:

```text
Xcode <version>
Build version <build>
```

3. Accept license if prompted:

```bash
sudo xcodebuild -license accept
```

**Verification:**

```bash
cd /Users/jasonvargas/Projects/AnesPayTracker
xcodebuild -list -project AnesPayTracker.xcodeproj
```

Expected: list of project targets/schemes.

---

## Phase 1 — Build verification before changes

### Task 1.1: Baseline iOS simulator build

**Objective:** Confirm the generated project builds as-is for iOS before Mac conversion.

**Files:** none.

**Command:**

```bash
cd /Users/jasonvargas/Projects/AnesPayTracker
xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

If destination names differ, list simulators:

```bash
xcrun simctl list devices available
```

**Expected:** Build succeeds or produces concrete compile errors to fix first.

### Task 1.2: Add a build log note

**Objective:** Preserve what happened so Hermes can continue across sessions.

**Files:**

- Create or update: `docs/BUILD_NOTES.md`

**Content to record:**

- Xcode version.
- iOS simulator destination used.
- Build result.
- Compile errors, if any.
- Warnings worth addressing.

---

## Phase 2 — Enable Mac Catalyst

### Task 2.1: Update Xcode project settings for Catalyst

**Objective:** Add Mac Catalyst as a supported destination.

**Files:**

- Modify: `AnesPayTracker.xcodeproj/project.pbxproj`

**Settings to add/update for both Debug and Release app build configurations:**

```text
TARGETED_DEVICE_FAMILY = "1,2,6";
SUPPORTS_MACCATALYST = YES;
DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = YES;
MACOSX_DEPLOYMENT_TARGET = 14.0;
```

Current known lines:

```text
TARGETED_DEVICE_FAMILY = "1,2";
```

appear in both Debug and Release app target build settings.

**Verification:**

```bash
xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  build
```

Expected initially: either build succeeds or reveals Catalyst-specific compile errors.

### Task 2.2: Fix platform-specific compile errors

**Objective:** Make the code compile under Mac Catalyst.

**Likely files:**

- `AnesPayTracker/Views/Report/PDFReportGenerator.swift`
- `AnesPayTracker/Views/Report/ReportView.swift`
- `AnesPayTracker/Views/Settings/SettingsView.swift`
- `AnesPayTracker/Engine/CalendarSync.swift`

Known platform-sensitive code:

- `PDFReportGenerator.swift` imports UIKit and uses `UIGraphicsPDFRenderer`, `UIFont`, `UIColor`, `UIBezierPath`.
- `ReportView.swift` defines `ShareSheet: UIViewControllerRepresentable` using `UIActivityViewController`.
- `SettingsView.swift` uses `UIApplication.openSettingsURLString`.
- `CalendarSync.swift` uses EventKit.

For Catalyst these may be okay, but they need an actual Catalyst build to verify.

---

## Phase 3 — Add automated tests around core money logic

### Task 3.1: Add a test target

**Objective:** Create a foundation for safe iteration.

**Files:**

- Modify: `AnesPayTracker.xcodeproj/project.pbxproj`
- Create: `AnesPayTrackerTests/PayCalculationTests.swift`
- Create: `AnesPayTrackerTests/StreakEngineTests.swift`

**Important:** Prefer adding the test target in Xcode UI first if possible, then let Hermes edit test files. Manual `.pbxproj` test target creation is error-prone.

### Task 3.2: Test Shift pay calculations

**Objective:** Protect the most important user-facing math.

**Behaviors to test:**

- Full-day per-day shift pays full base amount.
- Half-day per-day shift pays half base amount.
- Per-hour shift pays rate × hours.
- Splash and bonus splash are included in total.
- Streak bonus is included in total.

**Example test intent:**

```swift
func testHalfDayShiftPaysHalfBaseAmount() {
    let shift = Shift(payUnit: .perDay, dayFraction: .half, baseAmount: 1200)
    XCTAssertEqual(shift.basePay, Decimal(600))
}
```

### Task 3.3: Test StreakEngine rules

**Objective:** Protect bonus attribution logic.

**Behaviors to test:**

- Rolling-window streak triggers on the shift that completes required count.
- Streak bonus does not duplicate on recompute.
- Calendar-month streak only counts shifts in the same month.
- Pay-period streak respects employer cadence.
- Deleting/editing a shift and recomputing removes stale bonus attribution.

---

## Phase 4 — Mac UX pass

### Task 4.1: Add Mac-specific commands

**Objective:** Make it feel like a Mac app, not just an enlarged iPad app.

**Files:**

- Modify: `AnesPayTracker/App/AnesPayTrackerApp.swift`
- Possibly modify: `AnesPayTracker/App/ContentView.swift`

Potential commands:

- `⌘N` Add Shift
- Export Report
- Open Settings

Need a shared app state/router so menu commands can open the add-shift sheet from the root view.

### Task 4.2: Improve wide-screen layout

**Objective:** Make dashboard/review screens efficient on Mac.

**Files:**

- `ContentView.swift`
- review/report views as needed

Approach:

- Keep existing `TabView` for phone/iPad.
- Add `#if targetEnvironment(macCatalyst)` or horizontal-size-class based layout only if the app feels cramped.
- Consider `NavigationSplitView` later, not before first Mac build.

---

## Phase 5 — Production readiness for wife's use

### Task 5.1: Replace seed/demo behavior with onboarding-safe behavior

**Objective:** Avoid demo data polluting real use.

Current behavior:

- `AnesPayTrackerApp.swift` always runs `SeedData.insertIfNeeded` on first launch if there are no employers.

Risk:

- Real first launch may populate fake employer/sites/shifts, making the app feel untrustworthy.

Options:

1. Keep seed data only in Debug builds:

```swift
#if DEBUG
SeedData.insertIfNeeded(into: modelContainer.mainContext)
#endif
```

2. Add a first-run choice: "Load demo data" vs "Start blank".

Recommendation: option 2 for user-friendliness.

### Task 5.2: Improve error handling

**Objective:** Avoid silent failures in money/calendar persistence.

Known code uses `try?` in several places:

- saving shifts
- setup wizard save
- delete shift
- settings saves
- calendar event update/remove

Replace critical `try?` calls with do/catch and visible alerts for:

- shift save failure
- employer/site/rule save failure
- calendar sync failure

### Task 5.3: Signing, bundle ID, icon, CloudKit

**Objective:** Prepare a personal distributable app.

Xcode tasks:

- Set your Apple Development Team.
- Choose final bundle ID, e.g. `com.<yourdomain>.anespaytracker`.
- Add app icon.
- Decide whether CloudKit sync is needed. For a single-user Mac app, local-only may be simpler initially.

---

## Immediate Next Step

Full Xcode is now installed and both iOS Simulator and Mac Catalyst compile/link verification have succeeded. The next implementation phase should use the runtime feedback backlog as the source of truth:

```text
docs/RUNTIME_FEEDBACK_BACKLOG.md
```

Recommended next implementation order:

1. Fix sheet/pop-up scrolling and ambiguous controls.
2. Expand employer/pay rule setup for per-hour/per-day rates, customizable bonus types, and configurable streak bonuses.
3. Add employer filtering and reconciliation workflow to Pay Periods.
4. Add calendar week view and improve calendar visual scale/employer summary.
5. Add CSV export alongside PDF export.
6. Add tests or a documented manual calculation checklist before broad money-logic changes.

Continue verifying with both:

```bash
xcodebuild -project AnesPayTracker.xcodeproj -scheme AnesPayTracker -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project AnesPayTracker.xcodeproj -scheme AnesPayTracker -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build
```
