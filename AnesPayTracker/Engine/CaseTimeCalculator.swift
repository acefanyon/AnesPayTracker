import Foundation

// Foundation only: this file is also compiled on its own by
// scripts/swift_tests/pay_math, so it must not import SwiftUI or SwiftData.

// MARK: - Shift Case

/// One anesthesia case within a shift, paid from start to stop.
/// Stored in `Shift.cases`. It holds no patient information by design.
struct ShiftCase: Codable, Identifiable, Equatable {
    var id: UUID
    var startAt: Date
    /// Equal to `startAt` while the case is still running.
    var endAt: Date
    var isRunning: Bool

    init(id: UUID = UUID(), startAt: Date, endAt: Date, isRunning: Bool = false) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.isRunning = isRunning
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startAt
        case endAt
        case isRunning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startAt = try container.decode(Date.self, forKey: .startAt)
        endAt = try container.decodeIfPresent(Date.self, forKey: .endAt) ?? startAt
        isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
    }
}

// MARK: - Case Time Calculator

/// Pay rules for sites that pay for case time only:
/// - each case counts whole minutes from its start to its stop;
/// - the day's minutes are added up, then raised to the daily minimum if one applies;
/// - pay is rate × minutes ÷ 60, rounded to the nearest cent.
enum CaseTimeCalculator {

    // MARK: Minutes

    static func truncatedToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    /// A running case counts nothing until it is stopped.
    static func minutes(of shiftCase: ShiftCase) -> Int {
        guard !shiftCase.isRunning else { return 0 }
        let start = truncatedToMinute(shiftCase.startAt)
        let end = truncatedToMinute(shiftCase.endAt)
        return max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    static func totalMinutes(_ cases: [ShiftCase]) -> Int {
        cases.reduce(0) { $0 + minutes(of: $1) }
    }

    static func minimumMinutes(_ minimumHours: Double?) -> Int {
        guard let minimumHours, minimumHours > 0 else { return 0 }
        return Int((minimumHours * 60).rounded())
    }

    static func paidMinutes(caseMinutes: Int, minimumHours: Double?) -> Int {
        max(caseMinutes, minimumMinutes(minimumHours))
    }

    // MARK: Pay

    static func pay(rate: Decimal, paidMinutes: Int) -> Decimal {
        var exact = rate * Decimal(paidMinutes) / Decimal(60)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 2, .plain)
        return rounded
    }

    // MARK: Ordering and validation

    static func sorted(_ cases: [ShiftCase]) -> [ShiftCase] {
        cases.sorted { $0.startAt < $1.startAt }
    }

    /// A problem that would make the day's time wrong, or nil. Saving is blocked while one exists.
    static func blockingProblem(in cases: [ShiftCase]) -> String? {
        let ordered = sorted(cases)
        if ordered.filter(\.isRunning).count > 1 {
            return "Only one case can be running at a time."
        }
        if let runningIndex = ordered.firstIndex(where: \.isRunning), runningIndex != ordered.count - 1 {
            return "The running case must be the last case of the day. Stop it or fix its start time."
        }
        for (index, pair) in zip(ordered, ordered.dropFirst()).enumerated() {
            if truncatedToMinute(pair.1.startAt) < truncatedToMinute(pair.0.endAt) {
                return "Case \(index + 1) and case \(index + 2) overlap. Fix their times so the same minutes aren't counted twice."
            }
        }
        return nil
    }

    /// A likely typo that does not block saving.
    static func warning(in cases: [ShiftCase]) -> String? {
        let ordered = sorted(cases)
        for (index, shiftCase) in ordered.enumerated() where minutes(of: shiftCase) > 12 * 60 {
            return "Case \(index + 1) is longer than 12 hours. Check its times."
        }
        return nil
    }

    // MARK: Time editing

    /// The picked hour and minute, placed on the same day as `reference`.
    static func time(of picked: Date, onDayOf reference: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: picked)
        var day = calendar.dateComponents([.year, .month, .day], from: reference)
        day.hour = time.hour
        day.minute = time.minute
        return calendar.date(from: day) ?? truncatedToMinute(picked)
    }

    /// The picked end time on the start's day, or on the next day when the case runs past midnight.
    static func end(atTimeOf picked: Date, forStart start: Date, calendar: Calendar) -> Date {
        let candidate = time(of: picked, onDayOf: start, calendar: calendar)
        if candidate < truncatedToMinute(start) {
            return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    /// Moves every case by whole days so the earliest one starts on `day`, keeping all clock times.
    static func moving(_ cases: [ShiftCase], toDay day: Date, calendar: Calendar) -> [ShiftCase] {
        guard let earliest = cases.map(\.startAt).min() else { return cases }
        let from = calendar.startOfDay(for: earliest)
        let to = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        guard days != 0 else { return cases }
        return cases.map { shiftCase in
            var moved = shiftCase
            moved.startAt = calendar.date(byAdding: .day, value: days, to: shiftCase.startAt) ?? shiftCase.startAt
            moved.endAt = calendar.date(byAdding: .day, value: days, to: shiftCase.endAt) ?? shiftCase.endAt
            return moved
        }
    }

    // MARK: Labels

    /// "7 h 31 m", or "7h 31m" when compact.
    static func durationLabel(minutes: Int, compact: Bool = false) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        let separator = compact ? "" : " "
        if hours == 0 { return "\(remainder)\(separator)m" }
        if remainder == 0 { return "\(hours)\(separator)h" }
        return "\(hours)\(separator)h \(remainder)\(separator)m"
    }
}
