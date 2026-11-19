#!/usr/bin/env python3
"""Summarise a UI test run for people and agents.

Usage: ui_test_summary.py REPORT_DIR

REPORT_DIR holds tests.json (from `xcrun xcresulttool get test-results tests`)
and screenshots/ (from `xcrun xcresulttool export attachments`, which writes
manifest.json). Prints a Markdown summary and copies each screenshot to
REPORT_DIR/named/ as "<test>__<screenshot name>.png" so they are easy to find.
Best effort: missing or unexpected files are reported, never fatal.
"""
import json
import re
import shutil
import sys
from pathlib import Path


def walk(node, out):
    if node.get("nodeType") == "Test Case":
        failures = [child.get("name", "") for child in node.get("children", []) if child.get("nodeType") == "Failure Message"]
        out.append((node.get("name", "?"), node.get("result", "?"), node.get("duration", ""), failures))
    for child in node.get("children", []):
        walk(child, out)


def main(report_dir: Path) -> None:
    cases = []
    tests_file = report_dir / "tests.json"
    if tests_file.exists():
        try:
            data = json.loads(tests_file.read_text())
            for node in data.get("testNodes", []):
                walk(node, cases)
        except (json.JSONDecodeError, AttributeError) as error:
            print(f"Could not read tests.json: {error}")
    else:
        print("No tests.json: the tests may not have run (see the build log).")

    passed = sum(1 for case in cases if case[1] == "Passed")
    print(f"# UI test results: {passed} of {len(cases)} passed\n")
    for name, result, duration, failures in cases:
        mark = "PASS" if result == "Passed" else result.upper()
        print(f"- {mark} {name} {duration}".rstrip())
        for failure in failures:
            print(f"    - {failure}")

    manifest_file = report_dir / "screenshots" / "manifest.json"
    if not manifest_file.exists():
        print("\nNo screenshot manifest found.")
        return
    named = report_dir / "named"
    named.mkdir(exist_ok=True)
    count = 0
    try:
        entries = json.loads(manifest_file.read_text())
    except json.JSONDecodeError as error:
        print(f"\nCould not read the screenshot manifest: {error}")
        return
    for entry in entries:
        test = re.sub(r"[^A-Za-z0-9_]+", "_", entry.get("testIdentifier", "test")).strip("_")
        for attachment in entry.get("attachments", []):
            source = report_dir / "screenshots" / attachment.get("exportedFileName", "")
            if not source.is_file():
                continue
            label = attachment.get("suggestedHumanReadableName", source.stem)
            label = re.sub(r"_\d+_[0-9A-F-]{36}", "", label)  # drop Xcode's index and UUID
            label = re.sub(r"[^A-Za-z0-9 ._&-]+", "", Path(label).stem).strip()
            shutil.copy(source, named / f"{test}__{label}{source.suffix}")
            count += 1
    print(f"\n{count} screenshots saved in named/.")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "ui-test-report"))
