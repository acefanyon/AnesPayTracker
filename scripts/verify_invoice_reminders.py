#!/usr/bin/env python3
"""Invoice reminders and payment tracking: worked examples plus wiring checks.

Rules:
- each employer can have an invoice schedule (off by default): every week or
  every 2 weeks from a known period end date, twice a month (1st-15th and
  16th-end), every month, or the employer's own pay periods;
- a finished period with worked shifts that aren't on an invoice is "due":
  Home shows it, and a notification goes out at 9 AM the day after the
  period ends, then weekly until an invoice is created;
- reminders only cover shifts from the period containing the reminders' start
  date, so turning them on doesn't flag history;
- payment tracking is one app-wide switch, off by default; when it is on,
  unpaid invoices are reminded weekly from the due date (or a week after the
  invoice date) until marked paid;
- notifications never show amounts, permission is asked only when a reminder
  is turned on, and only the app's own invoice notifications are replaced.

The Swift schedule math is executed by scripts/swift_tests/pay_math in CI; this
script keeps an independent oracle and guards the wiring. Dates are examples.
"""
from datetime import date, datetime, timedelta
from pathlib import Path
import calendar as cal
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "AnesPayTracker"
MATH = (APP / "Engine" / "InvoiceScheduleMath.swift").read_text()
REMINDERS = (APP / "Engine" / "InvoiceReminders.swift").read_text()
MODELS = (APP / "Model" / "Models.swift").read_text()
CONTENT = (APP / "App" / "ContentView.swift").read_text()
HOME = (APP / "Views" / "Home" / "HomeView.swift").read_text()
CARDS = (APP / "Views" / "Invoices" / "InvoiceHomeCards.swift").read_text()
SETTINGS = (APP / "Views" / "Invoices" / "InvoiceSettingsView.swift").read_text()
SETTINGS_ROOT = (APP / "Views" / "Settings" / "SettingsView.swift").read_text()
LIST = (APP / "Views" / "Invoices" / "InvoiceListView.swift").read_text()
DETAIL = (APP / "Views" / "Invoices" / "InvoiceDetailView.swift").read_text()
EDITOR = (APP / "Views" / "Invoices" / "InvoiceEditorView.swift").read_text()
PROJECT = (ROOT / "AnesPayTracker.xcodeproj" / "project.pbxproj").read_text()
WORKFLOW = (ROOT / ".github" / "workflows" / "build.yml").read_text()
SWIFT_TESTS = (ROOT / "scripts" / "swift_tests" / "pay_math" / "main.swift").read_text()
ALL_SWIFT = "\n".join(path.read_text() for path in APP.rglob("*.swift"))


def anchored(day: date, anchor_end: date, length: int):
    offset = (day - anchor_end).days
    k = -((-offset) // length)  # ceiling division
    end = anchor_end + timedelta(days=k * length)
    return end - timedelta(days=length - 1), end


def twice_monthly(day: date):
    if day.day <= 15:
        return day.replace(day=1), day.replace(day=15)
    return day.replace(day=16), day.replace(day=cal.monthrange(day.year, day.month)[1])


def weekly_reminders(first_day: date, now: datetime, limit: int, hour: int = 9):
    first = datetime(first_day.year, first_day.month, first_day.day, hour)
    out, week = [], 0
    while len(out) < limit:
        candidate = first + timedelta(days=7 * week)
        if candidate > now:
            out.append(candidate)
        week += 1
    return out


def first_unpaid_day(issued: date, due):
    return due if due else issued + timedelta(days=7)


oracle = {
    "every 2 weeks, inside the anchor's period": (anchored(date(2026, 11, 19), date(2026, 11, 22), 14), (date(2026, 11, 9), date(2026, 11, 22))),
    "every 2 weeks, day after the anchor": (anchored(date(2026, 11, 23), date(2026, 11, 22), 14), (date(2026, 11, 23), date(2026, 12, 6))),
    "every 2 weeks, before the anchor": (anchored(date(2026, 11, 8), date(2026, 11, 22), 14), (date(2026, 10, 26), date(2026, 11, 8))),
    "every 2 weeks, future anchor": (anchored(date(2026, 11, 19), date(2026, 12, 20), 14), (date(2026, 11, 9), date(2026, 11, 22))),
    "weekly from a Saturday anchor": (anchored(date(2026, 11, 19), date(2026, 11, 21), 7), (date(2026, 11, 15), date(2026, 11, 21))),
    "twice a month, first half": (twice_monthly(date(2026, 11, 15)), (date(2026, 11, 1), date(2026, 11, 15))),
    "twice a month, second half of February": (twice_monthly(date(2027, 2, 20)), (date(2027, 2, 16), date(2027, 2, 28))),
    "twice a month, leap February": (twice_monthly(date(2028, 2, 20)), (date(2028, 2, 16), date(2028, 2, 29))),
    "reminders at 9 AM then weekly": (
        weekly_reminders(date(2026, 11, 23), datetime(2026, 11, 19, 12), 3),
        [datetime(2026, 11, 23, 9), datetime(2026, 11, 30, 9), datetime(2026, 12, 7, 9)],
    ),
    "a reminder already past is skipped": (
        weekly_reminders(date(2026, 11, 23), datetime(2026, 11, 23, 10), 1), [datetime(2026, 11, 30, 9)],
    ),
    "long-overdue reminders keep their weekday": (
        weekly_reminders(date(2026, 1, 1), datetime(2026, 11, 19, 12), 1), [datetime(2026, 11, 26, 9)],
    ),
    "unpaid reminders start on the due date": (first_unpaid_day(date(2026, 11, 23), date(2026, 12, 15)), date(2026, 12, 15)),
    "or a week after the invoice date": (first_unpaid_day(date(2026, 11, 23), None), date(2026, 11, 30)),
}

scheduler = REMINDERS.split("enum InvoiceNotificationScheduler")[1] if "enum InvoiceNotificationScheduler" in REMINDERS else ""
reminder_logic = REMINDERS.split("enum InvoiceNotificationScheduler")[0]
bodies = " ".join(re.findall(r"(?:title|body): \"[^\"]*\"", scheduler))

checks = {name: actual == expected for name, (actual, expected) in oracle.items()}
checks.update({
    "Schedule math stays Foundation-only so it can be tested outside the app": (
        re.findall(r"^import (\w+)", MATH, re.M) == ["Foundation"]
    ),
    "Saved schedule names are stable": all(
        f"case {name}\n" in MATH for name in ("weekly", "everyTwoWeeks", "twiceMonthly", "monthly", "payPeriod")
    ) and "enum InvoiceCadence: String, Codable" in MATH,
    "New saved fields are optional, so existing data opens unchanged": all(
        field in MODELS for field in (
            "var invoiceCadence: InvoiceCadence?",
            "var invoicePeriodEndAnchor: Date?",
            "var invoiceRemindersStartDate: Date?",
            "var paidOn: Date?",
        )
    ),
    "Working out what is due never changes data": (
        all(token not in REMINDERS for token in (".save()", ".delete(", ".insert("))
        and not re.search(r"\.(paidOn|invoiceCadence|invoicePeriodEndAnchor|invoiceRemindersStartDate) = ", REMINDERS)
    ),
    "Reminders cover shifts from the start date's period only": (
        "employer.invoiceRemindersStartDate ?? now" in reminder_logic
        and "shift.date >= firstPeriod.start" in reminder_logic
    ),
    "Only worked shifts with something to bill, not already invoiced, count": (
        "shift.date <= endOfToday" in reminder_logic
        and "!invoicedShiftIDs.contains(shift.id)" in reminder_logic
        and "InvoiceBuilder.day(for: shift).totalCents > 0" in reminder_logic
    ),
    "Pay-period schedules are used only when the pay periods are real": (
        "guard employer.hasReliablePayPeriods else { return nil }" in reminder_logic
    ),
    "Payment tracking is off by default everywhere": (
        ALL_SWIFT.count("@AppStorage(InvoiceSettingsKey.tracksPayments) private var tracksPayments = false")
        == ALL_SWIFT.count("@AppStorage(InvoiceSettingsKey.tracksPayments)")
        and "UserDefaults.standard.bool(forKey: InvoiceSettingsKey.tracksPayments)" in scheduler
        and "if tracksPayments {" in scheduler
    ),
    "Only the app's own invoice notifications are replaced": (
        'identifierPrefix = "invoice-reminder."' in scheduler
        and ".filter { $0.hasPrefix(identifierPrefix) }" in scheduler
        and "removePendingNotificationRequests(withIdentifiers: ours)" in scheduler
        and "removeAllPendingNotificationRequests" not in ALL_SWIFT
    ),
    "Pending notifications stay under iOS's limit of 64": "static let maximumPending = 60" in scheduler,
    "Notifications never show amounts": (
        "money" not in scheduler and "totalCents" not in scheduler and "$" not in bodies
    ),
    "Permission is asked only when the user turns a reminder on": (
        "requestAuthorization(options:" in scheduler
        and ALL_SWIFT.count("InvoiceNotificationScheduler.requestAuthorization()") == 2
        and SETTINGS.count("InvoiceNotificationScheduler.requestAuthorization()") == 2
    ),
    "Notifications are rebuilt when the app opens or is left": (
        "@Environment(\\.scenePhase) private var scenePhase" in CONTENT
        and "phase == .active || phase == .background" in CONTENT
        and "InvoiceNotificationScheduler.reschedule(context: modelContext)" in CONTENT
    ),
    "Home shows due and unpaid invoices without changing data": (
        "InvoiceHomeCards()" in HOME
        and "InvoiceReminders.duePeriods(" in CARDS
        and "modelContext" not in CARDS
        and "InvoiceEditorView(prefill: prefill)" in CARDS
    ),
    "The invoice form can open with a reminder's employer and dates": (
        "let prefill: InvoicePrefill?" in EDITOR
        and "periodStart = prefill.period.start" in EDITOR
        and "periodEnd = prefill.period.end" in EDITOR
    ),
    "Settings links to reminders and payments": "InvoiceSettingsView()" in SETTINGS_ROOT,
    "Turning tracking on offers to mark existing invoices paid": (
        "Mark existing invoices as paid?" in SETTINGS and "Leave Them Unpaid" in SETTINGS
    ),
    "Saving a payment reports failures and refreshes reminders": (
        "private func setPaid(_ invoice: Invoice, on date: Date?)" in LIST
        and "invoice.paidOn = date" in LIST
        and "modelContext.rollback()" in LIST
        and "InvoiceNotificationScheduler.reschedule(context: modelContext)" in LIST
    ),
    "The invoice screen shows the Paid switch only when tracking is on": (
        "if tracksPayments {\n                    paymentCard" in DETAIL and ".delete(" not in DETAIL
    ),
    "New files are compiled into the app": all(
        f"{path} in Sources */," in PROJECT
        for path in (
            "Engine/InvoiceScheduleMath.swift",
            "Engine/InvoiceReminders.swift",
            "Views/Invoices/InvoiceSettingsView.swift",
            "Views/Invoices/InvoiceHomeCards.swift",
        )
    ),
    "CI runs the Swift schedule tests": "AnesPayTracker/Engine/InvoiceScheduleMath.swift" in WORKFLOW,
    "Swift tests cover the worked examples": (
        "span(2026, 11, 9, 2026, 11, 22)" in SWIFT_TESTS
        and "span(2028, 2, 16, 2028, 2, 29)" in SWIFT_TESTS
        and "[at(2026, 11, 26, 9)]" in SWIFT_TESTS
    ),
})

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("Invoice reminders verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("Invoice reminders verifier passed.")
