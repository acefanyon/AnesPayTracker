#!/usr/bin/env python3
"""Settings → About must describe the installed build truthfully.

- Version comes from the bundle, so testers can tell which TestFlight build is
  installed (it was hardcoded "1.0.0" through build 1.1 (6) source).
- Data storage must not claim iCloud while the iCloud capability is off: the
  user's pay records exist only on the device.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "AnesPayTracker" / "Views" / "Settings" / "SettingsView.swift").read_text()
PROJECT = (ROOT / "AnesPayTracker.xcodeproj" / "project.pbxproj").read_text()
icloud_enabled = "com.apple.developer.icloud" in PROJECT or "CODE_SIGN_ENTITLEMENTS" in PROJECT

checks = {
    "Version must come from the app bundle, not a hardcoded string": (
        'Text("1.0.0")' not in SETTINGS
        and "CFBundleShortVersionString" in SETTINGS
        and "CFBundleVersion" in SETTINGS
    ),
    "Data Storage must not mention iCloud while iCloud is not enabled": (
        icloud_enabled or 'Text("On-device + iCloud")' not in SETTINGS
    ),
}

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("Settings About verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("Settings About verifier passed.")
