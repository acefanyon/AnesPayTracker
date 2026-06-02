from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
settings = (root / "AnesPayTracker/Views/Settings/SettingsView.swift").read_text()
wizard = (root / "AnesPayTracker/Views/Setup/EmployerSetupWizard.swift").read_text()
shift_detail = (root / "AnesPayTracker/Views/Review/ShiftDetailView.swift").read_text()
plan = (root / "PLAN_STREAK_AND_UI.md").read_text()

checks = {
    "Settings should expose a full employer editor action": 'EmployerSetupWizard(mode: .edit, sourceEmployer: employer)' in settings,
    "Settings should expose a versioned employer copy action": 'EmployerSetupWizard(mode: .duplicateVersion, sourceEmployer: employer)' in settings,
    "Settings should explain that saved shifts keep snapshots": 'Saved shifts keep their existing pay snapshots' in settings,
    "Wizard should support duplicate-version mode": 'case duplicateVersion' in wizard,
    "Wizard edit mode must preserve existing records instead of deleting omitted drafts": 'syncEmployer(sourceEmployer, allowDeletes: false, insertNewObjects: true)' in wizard,
    "Wizard should prefill from the source employer": 'DraftSite(site: $0)' in wizard and 'DraftStreakRule(rule: $0)' in wizard,
    "Wizard review should warn about history protection": 'Existing shifts keep their saved pay snapshots' in wizard,
    "Editing existing employers should not allow deleting imported sites/rules/bonuses from the wizard": 'canDelete: !(isEditingExistingEmployer && site.sourceID != nil)' in wizard and 'canDelete: !(isEditingExistingEmployer && rule.sourceID != nil)' in wizard and 'canDelete: !(isEditingExistingEmployer && bonus.sourceID != nil)' in wizard,
    "Shift detail must show base-rate labels from the shift snapshot, not the mutable site": 'shift.baseAmount.formatted(.currency(code: "USD"))' in shift_detail and 'shift.site?.baseAmount' not in shift_detail,
    "Plan should still describe duplicate/version fallback": 'duplicate/version employer fallback path' in plan or 'duplicate/version employer' in plan,
}

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("Slice 8 employer editing verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("Slice 8 employer editing verifier passed.")
