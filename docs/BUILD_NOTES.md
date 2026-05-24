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
