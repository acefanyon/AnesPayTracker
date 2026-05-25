#!/usr/bin/env python3
"""Static safety checks for the bonus entry workflow.

These checks cover the intended product behavior from client interview notes:
- Sites/rates should not configure a default splash bonus.
- Employer setup should still support named bonus types.
- Add/Edit Shift should allow an on-the-fly named bonus, even when no employer
  bonus type was predefined.
- New shift saves should store named bonuses in customBonuses rather than the
  legacy splash/bonusSplash fields.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETUP = ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift"
SETTINGS = ROOT / "AnesPayTracker" / "Views" / "Settings" / "SettingsView.swift"
ADD_SHIFT = ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift"
SEED = ROOT / "AnesPayTracker" / "Engine" / "SeedData.swift"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    setup = SETUP.read_text()
    settings = SETTINGS.read_text()
    add_shift = ADD_SHIFT.read_text()
    seed = SEED.read_text()
    failures: list[str] = []

    site_setup_surfaces = setup + settings
    require("Default Splash" not in site_setup_surfaces, "Site setup/settings must not expose Default Splash fields", failures)
    require("hasDefaultSplash" not in setup, "DraftSite must not track hasDefaultSplash", failures)
    require("defaultSplashAmount" not in setup, "Employer setup must not save site.defaultSplashAmount", failures)
    require("defaultSplashAmount:" not in seed, "Seed data must not configure site default splash bonuses", failures)
    require("defaultSplash" not in add_shift, "Add Shift must not depend on site default splash bonuses", failures)
    require("SplashSection" not in add_shift, "Add Shift should use named bonus UI rather than the old splash section", failures)

    require("CustomBonusesStep" in setup, "Employer setup must keep named custom bonus types", failures)
    require("Bonus name" in setup, "Employer setup must let user name employer bonus types", failures)

    require("Add One-Time Bonus" in add_shift, "Add Shift must offer an on-the-fly one-time bonus action", failures)
    require("One-time Bonus" in add_shift, "On-the-fly bonus should have a clear default name", failures)
    require("Add custom bonus" in add_shift, "Add Shift must have accessible add-custom-bonus control", failures)

    save_start = add_shift.find("private func saveShift()")
    save_end = add_shift.find("private func syncCustomBonusesForSelectedSite()")
    save_block = add_shift[save_start:save_end]
    require("shift.splashAmount = nil" in save_block, "New saves should not persist legacy splashAmount from the bonus UI", failures)
    require("shift.bonusSplashAmount = nil" in save_block, "New saves should not persist legacy bonusSplashAmount from the bonus UI", failures)

    if failures:
        print("Bonus entry workflow checks failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Bonus entry workflow checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
