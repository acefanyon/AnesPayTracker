import Foundation
import SwiftData

// MARK: - Streak Engine

struct StreakEngine {
    
    /// Recomputes streak bonuses for all shifts under an employer.
    /// Called after any shift is saved or edited.
    static func recomputeStreaks(for employer: Employer) {
        let rules = employer.streakRules.filter { $0.isActive }
        guard !rules.isEmpty else { return }
        
        // Collect all shifts for this employer, sorted ascending
        let allShifts = employer.sites
            .flatMap { $0.shifts }
            .sorted { $0.date < $1.date }
        
        // Clear existing streak bonuses
        for shift in allShifts {
            shift.streakBonusAmount = nil
            shift.streakRuleTriggeredID = nil
        }
        
        // Apply each rule
        for rule in rules {
            applyRule(rule, to: allShifts)
        }
    }
    
    private static func applyRule(_ rule: StreakRule, to shifts: [Shift]) {
        var alreadyTriggered: Set<UUID> = []
        
        for (index, shift) in shifts.enumerated() {
            let windowShifts = shiftsInWindow(before: shift.date, rule: rule, allShifts: shifts)
            
            if windowShifts.count >= rule.requiredDays {
                // Find the triggering shift (the one that completed the count)
                let triggerShift = windowShifts.sorted { $0.date < $1.date }.last!
                
                if !alreadyTriggered.contains(triggerShift.id) {
                    alreadyTriggered.insert(triggerShift.id)
                    let existing = triggerShift.streakBonusAmount ?? 0
                    triggerShift.streakBonusAmount = existing + rule.bonusAmount
                    triggerShift.streakRuleTriggeredID = rule.id
                }
            }
            
            _ = index
        }
    }
    
    private static func shiftsInWindow(before date: Date, rule: StreakRule, allShifts: [Shift]) -> [Shift] {
        let calendar = Calendar.current
        
        switch rule.windowType {
        case .rollingDays:
            let days = rule.windowDays ?? 14
            let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: date) ?? date
            return allShifts.filter { $0.date >= calendar.startOfDay(for: windowStart) && $0.date <= calendar.endOfDay(for: date) }
            
        case .calendarMonth:
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let monthStart = calendar.date(from: components),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
            return allShifts.filter { $0.date >= monthStart && $0.date < monthEnd }
            
        case .payPeriod:
            guard let employer = rule.employer else { return [] }
            let (start, end) = payPeriodBounds(containing: date, employer: employer)
            return allShifts.filter { $0.date >= start && $0.date <= end }
        }
    }
    
    // MARK: - Progress Tracking
    
    struct StreakProgress {
        let rule: StreakRule
        let completedDays: Int
        let requiredDays: Int
        let deadline: Date?
        let isComplete: Bool
        
        var remaining: Int { max(0, requiredDays - completedDays) }
        
        var displayText: String {
            if isComplete {
                return "✓ Streak complete — \(rule.bonusAmount.formatted(.currency(code: "USD"))) earned"
            }
            let deadlineText: String
            if let d = deadline {
                deadlineText = " by \(d.formatted(.dateTime.month(.abbreviated).day()))"
            } else {
                deadlineText = ""
            }
            return "\(completedDays) of \(requiredDays) days toward \(rule.bonusAmount.formatted(.currency(code: "USD")))\(deadlineText)"
        }
    }
    
    static func progress(for rule: StreakRule, relativeTo date: Date = Date()) -> StreakProgress {
        guard let employer = rule.employer else {
            return StreakProgress(rule: rule, completedDays: 0, requiredDays: rule.requiredDays, deadline: nil, isComplete: false)
        }
        
        let calendar = Calendar.current
        let allShifts = employer.sites.flatMap { $0.shifts }.sorted { $0.date < $1.date }
        let windowShifts = shiftsInWindow(before: date, rule: rule, allShifts: allShifts)
        let count = windowShifts.count
        
        let deadline: Date?
        switch rule.windowType {
        case .rollingDays:
            let days = rule.windowDays ?? 14
            let earliestInWindow = windowShifts.first?.date ?? date
            deadline = calendar.date(byAdding: .day, value: days - 1, to: earliestInWindow)
        case .calendarMonth:
            var comps = calendar.dateComponents([.year, .month], from: date)
            comps.month! += 1
            comps.day = 1
            deadline = calendar.date(from: comps).flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
        case .payPeriod:
            let (_, end) = payPeriodBounds(containing: date, employer: employer)
            deadline = end
        }
        
        return StreakProgress(
            rule: rule,
            completedDays: count,
            requiredDays: rule.requiredDays,
            deadline: deadline,
            isComplete: count >= rule.requiredDays
        )
    }
    
    // MARK: - Pay Period Utilities
    
    static func payPeriodBounds(containing date: Date, employer: Employer) -> (Date, Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        switch employer.payCadence {
        case .weekly:
            return anchoredBounds(containing: today, lengthDays: 7, anchor: employer.payPeriodAnchor, calendar: calendar)

        case .biweekly:
            return anchoredBounds(containing: today, lengthDays: 14, anchor: employer.payPeriodAnchor, calendar: calendar)

        case .monthly:
            var comps = calendar.dateComponents([.year, .month], from: today)
            let start = calendar.date(from: comps) ?? today
            comps.month! += 1
            let nextMonth = calendar.date(from: comps) ?? today
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? today
            return (start, end)

        case .custom:
            return anchoredBounds(containing: today, lengthDays: employer.customCadenceDays ?? 14, anchor: employer.payPeriodAnchor, calendar: calendar)
        }
    }

    /// Fixed-length periods counted from the anchor (the first day of any pay
    /// period the user knows), in both directions — so periods never re-shuffle
    /// at a year boundary. Without an anchor, falls back to a fixed epoch
    /// (Jan 1, 2001 — a Monday, which keeps un-anchored weekly periods
    /// Monday-based like before).
    private static func anchoredBounds(containing day: Date, lengthDays: Int, anchor: Date?, calendar: Calendar) -> (Date, Date) {
        let length = max(1, lengthDays)
        let anchorDay = calendar.startOfDay(for: anchor ?? Date(timeIntervalSinceReferenceDate: 0))
        let daysDiff = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0
        // Floored division so dates before the anchor land in the right period
        let periodIndex = daysDiff >= 0 ? daysDiff / length : -((-daysDiff + length - 1) / length)
        let start = calendar.date(byAdding: .day, value: periodIndex * length, to: anchorDay) ?? day
        let end = calendar.date(byAdding: .day, value: length - 1, to: start) ?? day
        return (start, end)
    }

    /// The day payment for a period actually lands. Payment lags the work it
    /// covers by `payDelayDays` — often into a later period entirely (work the
    /// first half of January, get paid in early February). nil when the
    /// employer doesn't track paydays.
    static func payday(forPeriodEnding end: Date, employer: Employer) -> Date? {
        guard let delay = employer.payDelayDays else { return nil }
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: delay, to: calendar.startOfDay(for: end))
    }
    
    static func allPayPeriods(for employer: Employer, in year: Int) -> [(Date, Date)] {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = year
        comps.month = 1
        comps.day = 1
        guard let yearStart = calendar.date(from: comps),
              comps.year != nil else { return [] }
        comps.year = year + 1
        guard let yearEnd = calendar.date(from: comps) else { return [] }
        
        var periods: [(Date, Date)] = []
        var current = yearStart
        while current < yearEnd {
            let (start, end) = payPeriodBounds(containing: current, employer: employer)
            periods.append((start, end))
            current = calendar.date(byAdding: .day, value: 1, to: end) ?? yearEnd
        }
        return periods
    }
}

// MARK: - Calendar Extension

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        var comps = dateComponents([.year, .month, .day], from: date)
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        return self.date(from: comps) ?? date
    }
}
