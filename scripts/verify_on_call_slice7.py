#!/usr/bin/env python3
"""Static verifier for Slice 7 on-call model + UI wiring."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "AnesPayTracker" / "Model" / "Models.swift"
ADD_SHIFT = ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift"
DETAIL = ROOT / "AnesPayTracker" / "Views" / "Review" / "ShiftDetailView.swift"
CALENDAR = ROOT / "AnesPayTracker" / "Views" / "Review" / "CalendarView.swift"
PAY_PERIOD = ROOT / "AnesPayTracker" / "Views" / "Review" / "PayPeriodView.swift"
SETTINGS = ROOT / "AnesPayTracker" / "Views" / "Settings" / "SettingsView.swift"
WIZARD = ROOT / "AnesPayTracker" / "Views" / "Setup" / "EmployerSetupWizard.swift"
REPORT = ROOT / "AnesPayTracker" / "Views" / "Report" / "ReportView.swift"
SEED = ROOT / "AnesPayTracker" / "Engine" / "SeedData.swift"
PLAN = ROOT / "PLAN_STREAK_AND_UI.md"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    models = MODELS.read_text()
    add_shift = ADD_SHIFT.read_text()
    detail = DETAIL.read_text()
    calendar = CALENDAR.read_text()
    pay_period = PAY_PERIOD.read_text()
    settings = SETTINGS.read_text()
    wizard = WIZARD.read_text()
    report = REPORT.read_text()
    seed = SEED.read_text()
    plan = PLAN.read_text()
    failures: list[str] = []

    require("var defaultOnCallAmount: Decimal" in models, "Employer should store a default on-call amount", failures)
    require("var isOnCall: Bool" in models, "Shift should store whether it was on-call", failures)
    require("var onCallAmount: Decimal?" in models, "Shift should snapshot the on-call amount", failures)
    require("var onCallPay: Decimal" in models, "Shift should compute an on-call pay component", failures)
    require("var hasOnCallBonus: Bool" in models, "Shift should expose an on-call helper for UI/reporting", failures)
    require("onCallPay" in models and "var bonusPay: Decimal" in models, "On-call pay should flow into bonus pay", failures)

    require("@State private var isOnCall: Bool = false" in add_shift, "Add Shift should track an on-call toggle", failures)
    require("@State private var onCallAmount: Decimal = 0" in add_shift, "Add Shift should track an editable on-call amount", failures)
    require("OnCallSection(" in add_shift, "Add Shift should render an on-call section", failures)
    require("shift.isOnCall = isOnCall" in add_shift, "Saving a shift should persist the on-call flag", failures)
    require("shift.onCallAmount = isOnCall ? onCallAmount : nil" in add_shift, "Saving a shift should persist the on-call amount snapshot", failures)
    require("employerDefaultAmount: defaultOnCallAmount" in add_shift, "Add Shift should feed the employer default into the on-call editor", failures)
    require("MiniPayItem(label: \"On-Call\", amount: onCallBonus)" in add_shift, "Pay preview should show on-call pay separately", failures)

    require('Label("On-Call", systemImage: "phone.badge.clock")' in detail, "Shift detail header should visibly mark on-call shifts", failures)
    require('label: "On-Call Bonus"' in detail, "Shift detail breakdown should show an on-call line item", failures)
    require('MetaRow(label: "On-Call"' in detail, "Shift detail metadata should show on-call status", failures)

    require("if shift.isOnCall" in calendar, "Calendar should distinguish on-call shifts visually", failures)
    require('Text("OC")' in calendar, "Calendar day chips should mark on-call shifts", failures)
    require("phone.badge.clock" in calendar, "Calendar month summary should count on-call shifts", failures)

    require("var totalOnCall: Decimal" in pay_period, "Pay period totals should calculate on-call pay separately", failures)
    require('TotalColumn(label: "On-Call"' in pay_period, "Pay period totals should surface on-call pay", failures)
    require("private var onCallText: String?" in pay_period, "Pay period rows should explain the on-call component", failures)

    require('Text("Default On-Call Bonus")' in settings, "Employer settings should allow editing the on-call default", failures)
    require('defaultOnCallAmount: $defaultOnCallAmount' in wizard, "Employer setup should collect an on-call default", failures)
    require('ReviewRow(label: "On-Call Default", value: defaultOnCallAmount.formatted(.currency(code: "USD")))' in wizard, "Employer setup review should show the on-call default", failures)

    require('bonusName: "On-Call Bonus"' in report, "Bonus payout/report rows should include on-call bonus entries", failures)
    require("defaultOnCallAmount: 250" in seed, "Seed data should demonstrate an employer on-call default", failures)
    require("isOnCall: true" in seed and "onCallAmount: 250" in seed, "Seed data should demonstrate an on-call shift snapshot", failures)

    # Updated plan checks to reflect that we've now implemented slices 1-9
    require(("Slices 1-7 are implemented locally and verified." in plan) or 
            ("Slices 1-8 are implemented locally and verified." in plan) or 
            ("Slices 1-9 are implemented locally and verified." in plan), 
            "Plan should reflect Slice 7 completion", failures)
    require(("Remaining planned work starts at Slice 8" in plan) or 
            ("Remaining planned work starts at Slice 9" in plan) or 
            ("No further planned work." in plan), 
            "Plan should advance the next slice after on-call work", failures)

    if failures:
        print("Slice 7 on-call verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Slice 7 on-call verifier passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())