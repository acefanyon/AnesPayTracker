#!/usr/bin/env python3
"""Invoices: worked examples plus checks that the app is wired to the rules.

Rules:
- one invoice bills one employer for a date range, across all of its sites;
- an invoice number is EMPLOYER-MMDDYY from a two-character employer code and
  the invoice date (EN-041326 = April 13, 2026); a taken number gets -2, -3 ...;
- each billed day names its site and lists its cases in order as "Anesthesia
  services, case N" with times, then its charges (base pay, on-call, add-ons)
  and a day total;
- streak bonuses are not invoiced; nothing identifying a patient is stored;
- money is whole cents, each charge rounded half-up, and totals are sums;
- a created invoice is a frozen copy: editing shifts later never changes it;
- deleting an invoice never touches shifts.

The Swift helpers themselves are executed by scripts/swift_tests/pay_math in
CI; this script keeps an independent oracle and guards the wiring.
All names and amounts are examples.
"""
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "AnesPayTracker"
MATH = (APP / "Engine" / "InvoiceMath.swift").read_text()
BUILDER = (APP / "Engine" / "InvoiceBuilder.swift").read_text()
MODELS = (APP / "Model" / "Models.swift").read_text()
APP_ENTRY = (APP / "App" / "AnesPayTrackerApp.swift").read_text()
PDF = (APP / "Views" / "Report" / "InvoicePDFGenerator.swift").read_text()
REPORT = (APP / "Views" / "Report" / "ReportView.swift").read_text()
LIST = (APP / "Views" / "Invoices" / "InvoiceListView.swift").read_text()
EDITOR = (APP / "Views" / "Invoices" / "InvoiceEditorView.swift").read_text()
DETAIL = (APP / "Views" / "Invoices" / "InvoiceDetailView.swift").read_text()
PROJECT = (ROOT / "AnesPayTracker.xcodeproj" / "project.pbxproj").read_text()
WORKFLOW = (ROOT / ".github" / "workflows" / "build.yml").read_text()
SWIFT_TESTS = (ROOT / "scripts" / "swift_tests" / "pay_math" / "main.swift").read_text()


def code(text: str) -> str:
    return "".join(ch for ch in text.upper() if ch.isalnum())[:2]


def number(employer: str, year: int, month: int, day: int) -> str:
    return f"{code(employer)}-{month:02d}{day:02d}{year % 100:02d}"


def unique(base: str, existing: set) -> str:
    if base not in existing:
        return base
    suffix = 2
    while f"{base}-{suffix}" in existing:
        suffix += 1
    return f"{base}-{suffix}"


def cents(amount: str) -> int:
    return int((Decimal(amount) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


oracle = {
    "April 13, 2026 for employer EN": (number("EN", 2026, 4, 13), "EN-041326"),
    "the code is cleaned to two uppercase characters": (number("e-n3", 2026, 11, 3), "EN-110326"),
    "a second invoice on the same date gets -2": (unique("EN-041326", {"EN-041326"}), "EN-041326-2"),
    "a third gets -3": (unique("EN-041326", {"EN-041326", "EN-041326-2"}), "EN-041326-3"),
    "7 h 31 m at $400/hr in cents": (cents("3006.67"), 300667),
    "that day with a $200 flat recovery fee": (cents("3006.67") + cents("200"), 320667),
    "two such days": (2 * 320667, 641334),
    "half a cent rounds up": (cents("0.005"), 1),
}

case_line = re.search(r"struct InvoiceCaseLine[^{]*\{(.*?)\n\}", MATH, re.S)
case_line_fields = sorted(re.findall(r"var (\w+):", case_line.group(1))) if case_line else []
invoice_model = re.search(r"@Model\s+final class Invoice \{(.*?)\n    init\(", MODELS, re.S)
invoice_fields = set(re.findall(r"^    var (\w+):", invoice_model.group(1), re.M)) if invoice_model else set()
day_builder = re.search(r"static func day\(for shift: Shift\) -> InvoiceDay \{(.*?)\n    \}\n", BUILDER, re.S)
day_builder_body = day_builder.group(1) if day_builder else ""
delete_body = re.search(r"private func delete\(_ invoice: Invoice\) \{(.*?)\n    \}\n", LIST, re.S)

checks = {name: actual == expected for name, (actual, expected) in oracle.items()}
checks.update({
    "Invoice math stays Foundation-only so it can be tested outside the app": (
        re.findall(r"^import (\w+)", MATH, re.M) == ["Foundation"]
    ),
    "The Swift numbering matches the oracle's shape": (
        '[sanitizedCode(employerCode), dateCode(date, calendar: calendar)].joined(separator: "-")' in MATH
        and 'String(format: "%02d%02d%02d", parts.month ?? 0, parts.day ?? 0, (parts.year ?? 0) % 100)' in MATH
        and "prefix(2)" in MATH
        and 'while existing.contains("\\(base)-\\(suffix)")' in MATH
    ),
    "Charges round half-up to whole cents": "NSDecimalRound(&rounded, &scaled, 0, .plain)" in MATH,
    "Case lines hold a generic label and times only (no patient details)": (
        case_line_fields == ["endAt", "label", "minutes", "startAt"]
        and '"Anesthesia services, case \\(number)"' in MATH
        and "label: InvoiceMath.caseLabel(index + 1)" in BUILDER
    ),
    "Cases are listed in time order": "shift.sortedCases.enumerated()" in BUILDER,
    "Streak bonuses are not invoiced": "streak" not in day_builder_body.lower().replace("streak bonuses are", ""),
    "An invoice bills base pay, on-call and add-ons": (
        "shift.basePay" in day_builder_body
        and "shift.onCallPay" in day_builder_body
        and "bonus.totalAmount" in day_builder_body
        and "(shift.splashAmount ?? 0) + (shift.bonusSplashAmount ?? 0)" in day_builder_body
    ),
    "The invoice model is registered with the store": "Invoice.self" in APP_ENTRY,
    "An invoice stores a frozen copy, not links to shifts": (
        "snapshotData" in invoice_fields
        and "totalCents" in invoice_fields
        and "@Relationship" not in (invoice_model.group(1) if invoice_model else "@Relationship")
        and "var snapshotData: Data" in MODELS
    ),
    "New employer fields are optional, so existing data opens unchanged": (
        MODELS.count("var invoiceCode: String?") == 1
        and "var billingName: String?" in MODELS
        and "var billingAddress: String?" in MODELS
    ),
    "The PDF and the detail screen print the frozen copy": (
        "document.snapshot.days" in PDF
        and "InvoiceDocument(invoice: invoice)" in DETAIL
        and "shift." not in PDF
    ),
    "One invoice covers all of the employer's sites, and each day names its site": (
        "static func candidateShifts(for employer: Employer" in BUILDER
        and "employer.sites\n            .flatMap(\\.shifts)" in BUILDER
        and 'siteName: shift.site?.name ?? ""' in BUILDER
        and "InvoiceBuilder.candidateShifts(for: employer" in EDITOR
        and "day.siteName" in PDF
        and "day.siteName" in DETAIL
    ),
    "A shift already on an invoice cannot be billed twice": (
        "InvoiceBuilder.invoiceNumbersByShift(invoices)" in EDITOR
        and "invoicedOn == nil && day.totalCents > 0" in EDITOR
    ),
    "A running case blocks invoicing that day": "$0.shift.runningCase != nil" in EDITOR,
    "Invoice numbers are unique across saved invoices": (
        "InvoiceMath.uniqueNumber(" in EDITOR and "existing: Set(invoices.map(\\.number))" in EDITOR
    ),
    "Creating reports a failed save instead of dropping it": (
        "try modelContext.save()" in EDITOR and "try? " not in EDITOR
    ),
    "Deleting an invoice removes only the invoice and reports failures": (
        delete_body is not None
        and "modelContext.delete(invoice)" in delete_body.group(1)
        and "try modelContext.save()" in delete_body.group(1)
        and "modelContext.rollback()" in delete_body.group(1)
        and LIST.count(".delete(") == 1
        and ".delete(" not in DETAIL
        and ".delete(" not in EDITOR
    ),
    "Deleting asks first": "confirmationDialog(" in DETAIL and "role: .destructive" in DETAIL,
    "A changed shift is flagged on its invoice": (
        "InvoiceBuilder.changedDays(in: snapshot, shifts: shifts)" in DETAIL
        and "InvoiceMath.fingerprint(of: InvoiceBuilder.day(for: shift)) != InvoiceMath.fingerprint(of: day)" in BUILDER
    ),
    "Invoices open from the Report tab": "InvoicesLinkCard()" in REPORT and "InvoiceListView()" in REPORT,
    "New files are compiled into the app": all(
        f"{path} in Sources */," in PROJECT
        for path in (
            "Engine/InvoiceMath.swift",
            "Engine/InvoiceBuilder.swift",
            "Views/Report/InvoicePDFGenerator.swift",
            "Views/Invoices/InvoiceListView.swift",
            "Views/Invoices/InvoiceEditorView.swift",
            "Views/Invoices/InvoiceDetailView.swift",
        )
    ),
    "CI runs the Swift invoice tests": "AnesPayTracker/Engine/InvoiceMath.swift" in WORKFLOW,
    "Swift tests cover the worked examples": (
        '"EN-041326"' in SWIFT_TESTS and '"EN-041326-2"' in SWIFT_TESTS and "641334" in SWIFT_TESTS
    ),
})

failed = [message for message, ok in checks.items() if not ok]
if failed:
    print("Invoice verifier failed:")
    for message in failed:
        print(f"- {message}")
    sys.exit(1)

print("Invoice verifier passed.")
