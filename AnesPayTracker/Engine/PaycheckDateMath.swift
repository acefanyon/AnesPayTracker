import Foundation

// Foundation only: this file is also compiled on its own by
// scripts/swift_tests/pay_math, so it must not import SwiftUI or SwiftData.

enum PaycheckDateMath {

    /// Monthly pay with a known pairing of period end and paycheck date keeps
    /// that pairing every month. Example: the period ending Oct 31 was paid
    /// Nov 15, so the period ending Nov 30 is paid Dec 15.
    static func monthlyPaycheckDate(
        periodEnd: Date,
        periodEndAnchor: Date,
        paycheckAnchor: Date,
        calendar: Calendar
    ) -> Date? {
        let anchor = calendar.dateComponents([.year, .month], from: periodEndAnchor)
        let period = calendar.dateComponents([.year, .month], from: periodEnd)
        guard let anchorYear = anchor.year, let anchorMonth = anchor.month,
              let periodYear = period.year, let periodMonth = period.month else { return nil }
        let months = (periodYear - anchorYear) * 12 + (periodMonth - anchorMonth)
        return calendar.date(byAdding: .month, value: months, to: calendar.startOfDay(for: paycheckAnchor))
    }
}
