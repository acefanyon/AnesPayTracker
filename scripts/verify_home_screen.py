#!/usr/bin/env python3
"""Static checks for the Home tab.

Home is a read-only summary. It must reuse existing pay logic (so it always
agrees with Pay Periods and the Paycheck Estimator report) and must never
modify data.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
HOME = (ROOT / "AnesPayTracker" / "Views" / "Home" / "HomeView.swift").read_text()
CONTENT = (ROOT / "AnesPayTracker" / "App" / "ContentView.swift").read_text()
STREAKS = (ROOT / "AnesPayTracker" / "Views" / "Review" / "StreakStatusView.swift").read_text()
PROJECT = (ROOT / "AnesPayTracker.xcodeproj" / "project.pbxproj").read_text()

tab_view = CONTENT.split("TabView(selection: $selectedTab)")[1].split(".overlay(")[0]
tab_tags = re.findall(r"\.tag\(AppTab\.(\w+)\)", tab_view)

checks = {
    "Home should be the first tab": tab_tags[:1] == ["home"] and "HomeView()" in tab_view,
    "The app should open on Home": "@State private var selectedTab: AppTab = .home" in CONTENT,
    "Tab bar should have at most 5 tabs (more pushes tabs into a 'More' menu)": len(tab_tags) <= 5,
    "Streak details should be reachable from Home": "StreakStatusContent()" in HOME,
    "StreakStatusView should still wrap the shared streak content": "StreakStatusContent()" in STREAKS,
    "Next paycheck should use the same engine rows as the Paycheck Estimator": "StreakEngine.paycheckAggregationRows(for:" in HOME,
    "Work period and payday should come from the engine": (
        "StreakEngine.payPeriodBounds(containing:" in HOME and "StreakEngine.paycheckDate(for:" in HOME
    ),
    "Shift amounts should come from Shift.totalPay, not recomputed rates": (
        ".totalPay" in HOME and "baseAmount" not in HOME and "multiplier" not in HOME
    ),
    "Payday cards should require both paycheck anchors (same rule as the report)": (
        "employer.payPeriodEndAnchorDate != nil && employer.paycheckAnchorDate != nil" in HOME
        and "PaycheckAnchorPromptCard" in HOME
    ),
    "Home must be read-only": (
        "modelContext" not in HOME and ".delete(" not in HOME and ".insert(" not in HOME and ".save()" not in HOME
    ),
    "Home should show cents so amounts match reports exactly": "fractionLength(0)" not in HOME,
    "HomeView.swift should be compiled into the app target": "B019 /* Views/Home/HomeView.swift in Sources */," in PROJECT,
}

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("Home screen verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("Home screen verifier passed.")
