#!/usr/bin/env python3
"""The UI tests' launch mode must never be able to touch real pay records.

UITestSupport gives the automated UI tests their own store of made-up data.
These checks keep it out of TestFlight/App Store builds, switched on only by
the tests' launch argument, and away from the real store; and keep the UI test
target, scheme and workflow wired up.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SUPPORT = (ROOT / "AnesPayTracker" / "App" / "UITestSupport.swift").read_text()
APP = (ROOT / "AnesPayTracker" / "App" / "AnesPayTrackerApp.swift").read_text()
PROJECT = (ROOT / "AnesPayTracker.xcodeproj" / "project.pbxproj").read_text()
SCHEME = (ROOT / "AnesPayTracker.xcodeproj" / "xcshareddata" / "xcschemes" / "AnesPayTrackerUITests.xcscheme").read_text()
WORKFLOW = (ROOT / ".github" / "workflows" / "ui-tests.yml").read_text()
TESTS = "\n".join(p.read_text() for p in (ROOT / "AnesPayTrackerUITests").glob("*.swift"))
ALL_APP = "\n".join(p.read_text() for p in (ROOT / "AnesPayTracker").rglob("*.swift"))

support_code = SUPPORT.strip()
init_body = APP.split("init() {", 1)[1].split("static let schema", 1)[0]
debug_block = init_body.split("#if DEBUG", 1)[1].split("#endif", 1)[0] if "#if DEBUG" in init_body else ""
after_debug = init_body.split("#endif", 1)[1] if "#endif" in init_body else ""

checks = {
    "UITestSupport is compiled into Debug builds only": (
        support_code.startswith("#if DEBUG") and support_code.endswith("#endif") and support_code.count("#endif") == 1
    ),
    "It switches on only with the tests' launch argument": (
        'static let scenarioArgument = "-UITestScenario"' in SUPPORT
        and "ProcessInfo.processInfo.arguments.contains(scenarioArgument)" in SUPPORT
    ),
    "The app uses it only inside #if DEBUG": (
        "UITestSupport" in debug_block
        and ALL_APP.replace(SUPPORT, "").count("UITestSupport") == APP.count("UITestSupport")
        and "UITestSupport" not in after_debug
    ),
    "Its store is separate from the real one and never synced": (
        "FileManager.default.temporaryDirectory" in SUPPORT
        and 'appendingPathComponent("uitest.store")' in SUPPORT
        and "cloudKitDatabase: .none" in SUPPORT
        and "default.store" not in SUPPORT
        and "applicationSupportDirectory" not in SUPPORT
        and "StoreSafety" not in SUPPORT
    ),
    "Normal launches still back up and open the real store": (
        "StoreSafety.backUpStoreIfNeeded()" in after_debug and "try Self.makeContainer()" in after_debug
    ),
    "The test mode is compiled into the app (Debug only, by its #if)": (
        "B034 /* App/UITestSupport.swift in Sources */," in PROJECT
    ),
    "The UI test target is in the project": (
        'productType = "com.apple.product-type.bundle.ui-testing";' in PROJECT
        and "TEST_TARGET_NAME = AnesPayTracker;" in PROJECT
        and "V001 /* InvoiceRemindersUITests.swift in Sources */," in PROJECT
    ),
    "The shared scheme tests that target in Debug": (
        'BlueprintIdentifier = "TARGET2"' in SCHEME and '<TestAction\n      buildConfiguration = "Debug"' in SCHEME
    ),
    "The app's own shared scheme exists (Xcode Cloud builds from it)": (
        (ROOT / "AnesPayTracker.xcodeproj" / "xcshareddata" / "xcschemes" / "AnesPayTracker.xcscheme").exists()
    ),
    "The workflow runs that scheme and keeps the screenshots": (
        "-scheme AnesPayTrackerUITests" in WORKFLOW
        and "xcresulttool export attachments" in WORKFLOW
        and "actions/upload-artifact" in WORKFLOW
    ),
    "Every UI test launches the app in its test mode": (
        '"-UITestScenario"' in TESTS and TESTS.count("XCUIApplication()") == 1
    ),
}

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("UI test mode safety verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("UI test mode safety verifier passed.")
