# Build Notes

## 2026-05-23 — Initial Hermes inspection

Local path:

```text
/Users/jasonvargas/Projects/AnesPayTracker
```

GitHub repo:

```text
acefanyon/AnesPayTracker
```

Branch:

```text
hermes/initial-mac-plan
```

## Environment finding

A local build could not be run because full Xcode is not installed/selected.

Command attempted:

```bash
xcodebuild -list -project AnesPayTracker.xcodeproj
```

Output:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

Current developer directory:

```text
/Library/Developer/CommandLineTools
```

## 2026-05-23 — Catalyst project setting change

Hermes enabled Mac Catalyst support in `AnesPayTracker.xcodeproj/project.pbxproj` by adding/updating these app target settings in Debug and Release:

```text
DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = YES;
MACOSX_DEPLOYMENT_TARGET = 14.0;
SUPPORTS_MACCATALYST = YES;
TARGETED_DEVICE_FAMILY = "1,2,6";
```

Plain-English meaning:

- `SUPPORTS_MACCATALYST = YES` tells Xcode this iPad/iPhone app is allowed to build as a Mac app through Catalyst.
- `TARGETED_DEVICE_FAMILY = "1,2,6"` means iPhone, iPad, and Mac Catalyst are supported device families.
- `MACOSX_DEPLOYMENT_TARGET = 14.0` means the Mac version expects macOS 14 or newer.
- `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = YES` lets Xcode derive a Mac-specific bundle identifier from the iOS bundle identifier.

Verification completed without full Xcode:

```bash
plutil -lint AnesPayTracker.xcodeproj/project.pbxproj
```

Result:

```text
AnesPayTracker.xcodeproj/project.pbxproj: OK
```

Important limitation: this only proves the project file syntax is valid. It does not prove the app compiles. A real compile still requires full Xcode.

## 2026-05-23 17:02 MST — Follow-up verification attempt

Hermes checked again whether full Xcode is installed and selected.

Result:

```text
No /Applications/Xcode.app
xcode-select:
/Library/Developer/CommandLineTools
```

Commands attempted:

```bash
xcodebuild -version
xcodebuild -list -project AnesPayTracker.xcodeproj
xcrun simctl list devices available
```

Outputs:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
xcrun: error: unable to find utility "simctl", not a developer tool or in PATH
```

Meaning:

- Full Xcode is still not installed at `/Applications/Xcode.app`.
- The selected Apple developer directory is still Command Line Tools only.
- iOS Simulator tooling is unavailable because `simctl` comes with full Xcode.
- Baseline iOS and Mac Catalyst builds still cannot be truthfully verified on this machine yet.

## Next verification steps after installing Xcode

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
cd /Users/jasonvargas/Projects/AnesPayTracker
xcodebuild -list -project AnesPayTracker.xcodeproj
```

Then run baseline iOS build:

```bash
xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

If `iPhone 15` is not available, list simulator names after Xcode is installed:

```bash
xcrun simctl list devices available
```

Then run Mac Catalyst build:

```bash
xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  build
```

## 2026-05-23 20:58 MST — Xcode installed; iOS and Mac Catalyst builds verified

Environment:

```text
Xcode 26.5
Build version 17F42
Developer directory: /Applications/Xcode.app/Contents/Developer
```

Project discovery succeeded:

```text
Target: AnesPayTracker
Scheme: AnesPayTracker
Build configurations: Debug, Release
```

Fixes made before successful builds:

1. Updated Xcode project file references so the project points to the real Swift file locations under folders such as `App`, `Model`, `Engine`, and `Views`.
2. Fixed `AnesPayTrackerApp.swift` initialization so seed data is inserted using the newly-created local `ModelContainer` value instead of capturing `self` before initialization completed.
3. Replaced the unsupported `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER` build setting with a conditional Mac Catalyst bundle identifier:

```text
PRODUCT_BUNDLE_IDENTIFIER = com.anespay.tracker;
"PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]" = maccatalyst.com.anespay.tracker;
```

Verified iOS Simulator build:

```bash
xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Result:

```text
** BUILD SUCCEEDED **
```

Verified Mac Catalyst build, unsigned for local compiler verification:

```bash
xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result:

```text
** BUILD SUCCEEDED **
```

Why `CODE_SIGNING_ALLOWED=NO` was used:

- A normal Mac Catalyst build now reaches the signing step, but this machine/project does not yet have an Apple Development Team selected.
- Disabling signing lets Hermes verify the code compiles and links as a Mac Catalyst app.
- For normal Xcode Run/Archive workflows, select a Development Team in Xcode's Signing & Capabilities tab.

Local generated Mac app bundle from the successful unsigned build:

```text
/Users/jasonvargas/Library/Developer/Xcode/DerivedData/AnesPayTracker-dhixpulmbnioqnbwrqpfbtohgfaq/Build/Products/Debug-maccatalyst/AnesPayTracker.app
```

Remaining warnings seen in the successful iOS build:

```text
Models.swift:224:9: warning: will never be executed
ReportView.swift:54:17: warning: variable 'comps' was never mutated; consider changing to 'let' constant
StreakEngine.swift:151:17: warning: variable 'comps' was never mutated; consider changing to 'let' constant
StreakEngine.swift:169:17: warning: variable 'comps' was never mutated; consider changing to 'let' constant
```

Recommended next work:

1. Select an Apple Development Team in Xcode so Mac Catalyst can build/run normally without `CODE_SIGNING_ALLOWED=NO`.
2. Launch the app on iPhone Simulator and as Mac Catalyst to check runtime behavior, not just compile success.
3. Fix the remaining Swift warnings.
4. Add tests around pay/streak calculation logic before broader UI polish.
