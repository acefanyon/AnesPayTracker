#!/usr/bin/env python3
"""Lists whose rows edit array elements must bind them by ID, not index.

`ForEach($array) { $item in ... }` gives each row an index-based binding. When
the array shrinks while row controls are updating, a control reads past the end
and the app crashes with "Index out of range". This crashed Add Shift when
switching to a site from another employer (2026-10-01 QA run, Test Group).
Use `ForEach(array) { item in ... $array.element(item) ... }` instead.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "AnesPayTracker"
CONTENT = (APP / "App" / "ContentView.swift").read_text()
ADD = (APP / "Views" / "Entry" / "AddShiftView.swift").read_text()

offenders = []
for path in sorted(APP.rglob("*.swift")):
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        code = line.split("//", 1)[0]
        if re.search(r"ForEach\(\$", code):
            offenders.append(f"{path.relative_to(ROOT)}:{number}")

checks = {
    "No index-based ForEach($array) bindings: " + (", ".join(offenders) or "none"): not offenders,
    "Shared ID-based element binding should exist": "func element<Element: Identifiable>(_ element: Element) -> Binding<Element>" in CONTENT,
    "Add Shift bonus rows should bind by ID": "$customBonuses.element(bonus)" in ADD,
}

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("List binding safety verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("List binding safety verifier passed.")
