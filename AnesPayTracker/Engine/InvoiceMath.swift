import Foundation

// Foundation only: this file is also compiled on its own by
// scripts/swift_tests/pay_math, so it must not import SwiftUI or SwiftData.

// MARK: - Frozen invoice content

/// One case on an invoice: a generic label and its times. No patient details.
struct InvoiceCaseLine: Codable, Equatable {
    var label: String
    var startAt: Date
    var endAt: Date
    var minutes: Int
}

/// One billed amount for a day. Money is whole cents so a saved invoice
/// reads back exactly as it was written.
struct InvoiceCharge: Codable, Equatable {
    var label: String
    var detail: String
    var amountCents: Int
}

struct InvoiceDay: Codable, Equatable, Identifiable {
    /// The shift this day was built from.
    var id: UUID
    var date: Date
    /// Where the work was done. One invoice can cover several sites.
    var siteName: String
    var caseLines: [InvoiceCaseLine]
    var charges: [InvoiceCharge]

    var totalCents: Int { charges.reduce(0) { $0 + $1.amountCents } }
}

/// Everything printed on an invoice, copied when the invoice is created so
/// later edits to shifts, rates or addresses never change it.
struct InvoiceSnapshot: Codable, Equatable {
    var senderName: String
    var senderAddress: String
    var senderPhone: String
    var senderEmail: String
    var billToName: String
    var billToAddress: String
    var days: [InvoiceDay]

    var totalCents: Int { days.reduce(0) { $0 + $1.totalCents } }

    /// The sites worked, each once, in the order they first appear.
    var siteNames: [String] {
        var names: [String] = []
        for day in days where !day.siteName.isEmpty && !names.contains(day.siteName) {
            names.append(day.siteName)
        }
        return names
    }
}

// MARK: - Invoice Math

enum InvoiceMath {

    // MARK: Numbering — EMPLOYER-MMDDYY from the invoice date, for example EN-041326

    /// Up to two letters or digits, uppercased.
    static func sanitizedCode(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(2))
    }

    /// Initials of the first two words, or the first two letters of a single word.
    static func suggestedCode(from name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return sanitizedCode(String([first, second]))
        }
        return sanitizedCode(String(words.first ?? ""))
    }

    static func dateCode(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d%02d%02d", parts.month ?? 0, parts.day ?? 0, (parts.year ?? 0) % 100)
    }

    static func invoiceNumber(employerCode: String, date: Date, calendar: Calendar) -> String {
        [sanitizedCode(employerCode), dateCode(date, calendar: calendar)].joined(separator: "-")
    }

    /// The base number, or the base with -2, -3 … when it is already taken.
    static func uniqueNumber(base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        var suffix = 2
        while existing.contains("\(base)-\(suffix)") { suffix += 1 }
        return "\(base)-\(suffix)"
    }

    // MARK: Money

    static func cents(_ amount: Decimal) -> Int {
        var scaled = amount * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func dollars(cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    // MARK: Content

    static func caseLabel(_ number: Int) -> String {
        "Anesthesia services, case \(number)"
    }

    /// An address split into exactly `count` entry fields. Extra lines are
    /// folded into the last field so nothing typed is ever dropped.
    static func addressFields(_ text: String, count: Int = 3) -> [String] {
        var parts = text.components(separatedBy: "\n")
        if parts.count > count {
            let extra = parts[(count - 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            parts = Array(parts[..<(count - 1)]) + [extra.joined(separator: ", ")]
        }
        while parts.count < count { parts.append("") }
        return parts
    }

    /// The address with one entry field replaced.
    static func address(_ text: String, settingField index: Int, to value: String, count: Int = 3) -> String {
        var fields = addressFields(text, count: count)
        guard fields.indices.contains(index) else { return text }
        fields[index] = value.replacingOccurrences(of: "\n", with: " ")
        return fields.joined(separator: "\n")
    }

    static func addressLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// What a day bills, to the minute and the cent. Two days with the same
    /// fingerprint print identically, so it tells whether a shift changed
    /// after its invoice was created.
    static func fingerprint(of day: InvoiceDay) -> String {
        func minute(_ date: Date) -> Int { Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down)) }
        let cases = day.caseLines.map { "\($0.label)|\(minute($0.startAt))|\(minute($0.endAt))|\($0.minutes)" }
        let charges = day.charges.map { "\($0.label)|\($0.detail)|\($0.amountCents)" }
        return ([day.id.uuidString, "\(minute(day.date))", day.siteName] + cases + charges).joined(separator: ";")
    }
}
