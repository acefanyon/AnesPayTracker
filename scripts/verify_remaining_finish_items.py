#!/usr/bin/env python3
"""Static verifier for final AnesPayTracker finish-line features."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADD_SHIFT = ROOT / "AnesPayTracker" / "Views" / "Entry" / "AddShiftView.swift"
MODELS = ROOT / "AnesPayTracker" / "Model" / "Models.swift"
CALENDAR = ROOT / "AnesPayTracker" / "Engine" / "CalendarSync.swift"
DETAIL = ROOT / "AnesPayTracker" / "Views" / "Review" / "ShiftDetailView.swift"
REPORT = ROOT / "AnesPayTracker" / "Views" / "Report" / "ReportView.swift"
PDF = ROOT / "AnesPayTracker" / "Views" / "Report" / "PDFReportGenerator.swift"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    add_shift = ADD_SHIFT.read_text()
    models = MODELS.read_text()
    calendar = CALENDAR.read_text()
    detail = DETAIL.read_text()
    report = REPORT.read_text()
    pdf = PDF.read_text()
    failures: list[str] = []

    require("var clockInAt: Date?" in models and "var clockOutAt: Date?" in models, "Shift model must persist optional clock-in/out timestamps", failures)
    require("ClockTimeCalculator" in add_shift, "Clock time calculator must exist", failures)
    require("ceil(minutes / 15.0) * 0.25" in add_shift, "Clock rounding must ceiling to nearest quarter hour", failures)
    require("Example: 8.01 hours becomes 8.25" in add_shift, "Clock UI must disclose ceiling quarter-hour behavior", failures)
    require("shift.clockInAt = site.payUnit == .perHour && usesClockTimes ? clockInAt : nil" in add_shift, "Save path must snapshot clock-in time", failures)
    require("shift.clockOutAt = site.payUnit == .perHour && usesClockTimes ? clockOutAt : nil" in add_shift, "Save path must snapshot clock-out time", failures)
    require("Clock In/Out" in add_shift, "Hourly entry UI must expose Clock In/Out toggle", failures)

    require("func exportICSFile(for shift: Shift) -> URL?" in calendar, "CalendarSync must generate .ics files", failures)
    require("BEGIN:VCALENDAR" in calendar and "BEGIN:VEVENT" in calendar and "DTSTART;VALUE=DATE" in calendar, "ICS output must contain VCALENDAR/VEVENT/all-day date fields", failures)
    require("SUMMARY:" in calendar and "DESCRIPTION:" in calendar, "ICS output must include summary and description", failures)
    require("CalendarExportCard" in detail and "ShareLink(item: icsExportURL)" in detail, "Shift detail must expose .ics export/share UI", failures)

    require("generatePaycheckEstimatorReport" in pdf, "PDF generator must support Paycheck Estimator", failures)
    require("AnesPay_Paycheck_Estimator" in pdf, "Paycheck Estimator PDF should use a distinct file name", failures)
    require("BREAKDOWN BY PAY COMPONENT" in pdf, "Paycheck Estimator PDF must include component breakdown", failures)
    require("generator.generatePaycheckEstimatorReport" in report, "Report export path must call Paycheck Estimator PDF generator", failures)
    require("reportMode == .bonusPayouts" in report and "else {" in report, "Report export must distinguish earnings, bonus payouts, and paycheck estimator", failures)

    if failures:
        print("Remaining finish-items verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Remaining finish-items verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
