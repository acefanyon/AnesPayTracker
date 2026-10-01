from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "AnesPayTracker" / "App" / "AnesPayTrackerApp.swift").read_text()
WIZARD = (ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift").read_text()
SEED = (ROOT / "AnesPayTracker" / "Engine" / "SeedData.swift").read_text()

backup_call = APP.find("StoreSafety.backUpStoreIfNeeded()")
open_call = APP.find("try Self.makeContainer()")

checks = {
    "Sample data should only be inserted in DEBUG builds, never TestFlight/release": (
        "#if DEBUG" in APP
        and "SeedData.insertIfNeeded(into: container.mainContext)" in APP
        and "#else" not in APP.split("SeedData.insertIfNeeded")[1].split("#endif")[0]
    ),
    # A tester's real shifts can live under the old sample employer/sites, and
    # deleting a site cascades to its shifts. Nothing may be deleted automatically.
    "Launch must never automatically delete sample-looking records": (
        "removeLegacyDemoDataIfNeeded" not in APP
        and "removeLegacyDemoDataIfNeeded" not in SEED
        and "context.delete(" not in SEED
    ),
    "A failed store open/migration must never delete the user's store": (
        "removeItem(at: storeURL" not in APP
        and "fatalError" not in APP
        and "StoreOpenFailedView" in APP
    ),
    "The store should be copied aside before it is opened (and possibly migrated)": (
        backup_call != -1 and open_call != -1 and backup_call < open_call
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
