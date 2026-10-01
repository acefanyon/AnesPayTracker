#!/usr/bin/env python3
"""SwiftData lightweight-migration safety check.

A non-optional stored property added to an existing @Model without a
declaration-level default makes every older store fail to open
("missing attribute values on mandatory destination attribute"). AGENTS.md
requires such properties to have a default or be optional.

The allowlist below is the set of required properties that existed when their
entity was first created; they never need a default. Any other required stored
property must declare one.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MODELS = (ROOT / "AnesPayTracker" / "Model" / "Models.swift").read_text()

ORIGINAL_REQUIRED = {
    "ContactPerson": {"id", "name"},
    "CustomBonusType": {"id", "name", "payUnit", "createdAt"},
    "Employer": {"id", "name", "contactPersons", "payCadence", "createdAt", "sites", "streakRules", "customBonusTypes"},
    "Shift": {"id", "date", "payUnit", "baseAmount", "editHistory", "createdAt"},
    "Site": {"id", "name", "payUnit", "baseAmount", "createdAt", "shifts"},
    "StreakRule": {"id", "requiredDays", "windowType", "bonusAmount", "isActive", "createdAt"},
}

failures = []
current_class = None
in_model = False
for line in MODELS.splitlines():
    if line.startswith("@Model"):
        in_model = True
        continue
    match = re.match(r"final class (\w+)", line)
    if in_model and match:
        current_class = match.group(1)
        continue
    if line.startswith("}"):
        in_model = False
        current_class = None
        continue
    if not current_class:
        continue
    prop = re.match(r"    var (\w+): ([^=?{]+)$", line)
    if prop and prop.group(1) not in ORIGINAL_REQUIRED.get(current_class, set()):
        failures.append(f"{current_class}.{prop.group(1)} is required but has no default; add `= <default>` or make it optional")

if failures:
    print("Model migration defaults verifier failed:")
    for message in failures:
        print(f"- {message}")
    sys.exit(1)

print("Model migration defaults verifier passed.")
