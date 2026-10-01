from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "AnesPayTracker" / "App" / "AnesPayTrackerApp.swift").read_text()
WIZARD = (ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift").read_text()
SEED = (ROOT / "AnesPayTracker" / "Engine" / "SeedData.swift").read_text()

checks = {
    "TestFlight/release builds should not auto-seed sample employers on first launch": (
        "#if DEBUG" in APP
        and "SeedData.insertIfNeeded(into: container.mainContext)" in APP
        and "#else\n            // One-time safety cleanup for TestFlight/release users" in APP
        and "SeedData.removeLegacyDemoDataIfNeeded(into: container.mainContext)" in APP
    ),
    "There should be no unconditional seed call in the app initializer body": (
        "// Seed on first launch\n            SeedData.insertIfNeeded(into: container.mainContext)" not in APP
        and "SeedData.insertIfNeeded(into: container.mainContext)\n            } catch" not in APP
    ),
    "Legacy sample cleanup should remove known demo records without wiping user-created employers": (
        "static func removeLegacyDemoDataIfNeeded(into context: ModelContext)" in SEED
        and "legacyDemoContactNames" in SEED
        and "legacyDemoSiteNames" in SEED
        and "legacyDemoBonusNames" in SEED
        and "context.delete(employer)" in SEED
    ),
    "Saving an existing employer should let contact deletions persist instead of re-appending sample contacts": (
        "syncContacts(for: employer, allowDeletes: true, insertNewObjects: insertNewObjects)" in WIZARD
    ),
    "Edit mode should still protect imported sites/rules/bonuses from destructive wizard deletion": (
        "canDelete: !(isEditingExistingEmployer && site.sourceID != nil)" in WIZARD
        and "canDelete: !(isEditingExistingEmployer && rule.sourceID != nil)" in WIZARD
        and "canDelete: !(isEditingExistingEmployer && bonus.sourceID != nil)" in WIZARD
    ),
}

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("TestFlight seed/employer edit verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("TestFlight seed/employer edit verifier passed.")
