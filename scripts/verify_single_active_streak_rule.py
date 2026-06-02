#!/usr/bin/env python3
"""Static verifier for single-active-streak-rule enforcement."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "AnesPayTracker" / "Model" / "Models.swift"
ENGINE = ROOT / "AnesPayTracker" / "Engine" / "StreakEngine.swift"
SETTINGS = ROOT / "AnesPayTracker" / "Views" / "Settings" / "SettingsView.swift"
WIZARD = ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift"
STATUS = ROOT / "AnesPayTracker" / "Views" / "Review" / "StreakStatusView.swift"
PLAN = ROOT / "PLAN_STREAK_AND_UI.md"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    models = MODELS.read_text()
    engine = ENGINE.read_text()
    settings = SETTINGS.read_text()
    wizard = WIZARD.read_text()
    status = STATUS.read_text()
    plan = PLAN.read_text()
    failures: list[str] = []

    require("var activeStreakRule: StreakRule?" in models, "Employer model should expose a single activeStreakRule helper", failures)
    require("func activateOnlyStreakRule(_ selectedRule: StreakRule)" in models, "Employer model should provide a helper that deactivates competing rules", failures)
    require("func keepOnlyNewestActiveStreakRule()" in models, "Employer model should normalize legacy multi-active data", failures)

    require("employer.keepOnlyNewestActiveStreakRule()" in engine, "Streak engine should collapse legacy multi-active rules before recompute", failures)
    require("guard let rule = employer.activeStreakRule else { return }" in engine, "Streak engine should compute against exactly one active rule", failures)

    require("Only one streak rule should be active per employer" in settings, "Settings should explain the one-active-rule constraint", failures)
    require("Only one streak rule can be active per employer. Turning this on automatically turns the others off." in settings, "Rule editor should explain toggle behavior", failures)
    require("rule.employer?.activateOnlyStreakRule(rule)" in settings, "Activating a rule in settings should deactivate peers", failures)
    require("employer.activateOnlyStreakRule(rule)" in settings, "Saving a new streak rule should make it the sole active rule", failures)

    require("Only one streak rule can be active per employer." in wizard, "Setup wizard should describe the one-active-rule constraint", failures)
    require("isActive: index == lastRuleIndex" in wizard, "Setup wizard should save at most one active streak rule", failures)

    require("if employer.activeStreakRule != nil" in status, "Streak status UI should render employers through the single active rule helper", failures)
    require("if let rule = employer.activeStreakRule" in status, "Employer streak section should display only one active rule card", failures)

    require("Only one streak rule may be active per employer at a time." in plan, "Plan should lock the one-active-rule business rule", failures)
    require("automatically deactivate the previous one" in plan, "Plan should document how switching active rules behaves", failures)

    if failures:
        print("Single-active-streak-rule verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Single-active-streak-rule verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
