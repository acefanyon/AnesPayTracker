import Foundation
import SwiftData

// MARK: - Streak Engine

struct StreakEngine {

    /// Recomputes streak bonuses for all shifts under an employer.
    /// Called after any shift is saved or edited.
    static func recomputeStreaks(for employer: Employer) {
        let allShifts = employer.sites
            .flatMap { $0.shifts }
            .sorted { $0.date < $1.date }

        clearStreakSnapshots(on: allShifts)
        employer.keepOnlyNewestActiveStreakRule()

        guard let rule = employer.activeStreakRule else { return }
        applyRule(rule, to: allShifts)
    }

    private static func clearStreakSnapshots(on shifts: [Shift]) {
        for shift in shifts {
            shift.streakBonusAmount = nil
            shift.streakRuleTriggeredID = nil
            shift.streakQualifiedShiftCount = nil
            shift.streakPerDayBonusAmount = nil
            shift.streakPayoutSchedule = nil
            shift.streakQualifiedForPayout = false
        }
    }

    private static func applyRule(_ rule: StreakRule, to shifts: [Shift]) {
        for shift in shifts {
            let windowShifts = shiftsInWindow(before: shift.date, rule: rule, allShifts: shifts)
                .sorted { $0.date < $1.date }
            let currentCount = windowShifts.count
            let earnedAmount = rule.postThresholdPerDayAmount ?? rule.bonusAmount
            let qualifiesForPayout = currentCount > rule.requiredDays

            shift.streakQualifiedShiftCount = currentCount
            shift.streakPerDayBonusAmount = earnedAmount > 0 ? earnedAmount : nil
            shift.streakPayoutSchedule = rule.payoutSchedule
            shift.streakQualifiedForPayout = currentCount > rule.requiredDays

            if qualifiesForPayout, earnedAmount > 0 {
                shift.streakBonusAmount = earnedAmount
                shift.streakRuleTriggeredID = rule.id
            }
        }
    }

    private static func shiftsInWindow(before date: Date, rule: StreakRule, allShifts: [Shift]) -> [Shift] {
        let calendar = Calendar.current
        let windowEnd = calendar.endOfDay(for: date)

        switch rule.windowType {
        case .rollingDays:
            let days = rule.windowDays ?? 14
            let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: date) ?? date
            return allShifts.filter { $0.date >= calendar.startOfDay(for: windowStart) && $0.date <= windowEnd }

        case .calendarMonth:
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let monthStart = calendar.date(from: components),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
            return allShifts.filter { $0.date >= monthStart && $0.date < monthEnd && $0.date <= windowEnd }

        case .calendarQuarter:
            let components = calendar.dateComponents([.year, .month], from: date)
            let month = components.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var startComponents = DateComponents()
            startComponents.year = components.year
            startComponents.month = quarterStartMonth
            startComponents.day = 1
            guard let quarterStart = calendar.date(from: startComponents),
                  let quarterEnd = calendar.date(byAdding: .month, value: 3, to: quarterStart) else { return [] }
            return allShifts.filter { $0.date >= quarterStart && $0.date < quarterEnd && $0.date <= windowEnd }

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
        let isEarning: Bool
        let earnedBonusDays: Int

        var remaining: Int { max(0, requiredDays - completedDays) }

        var displayText: String {
            let rewardText: String
            if let perDayAmount = rule.postThresholdPerDayAmount {
                rewardText = "\(perDayAmount.formatted(.currency(code: "USD")))/day"
            } else {
                rewardText = rule.bonusAmount.formatted(.currency(code: "USD"))
            }

            if isEarning {
                return "✓ Threshold reached — now earning \(rewardText) for the rest of this quarter"
            }

            if isComplete {
                return "✓ Threshold reached — next qualifying shift earns \(rewardText)"
            }

            let deadlineText: String
            if let d = deadline {
                deadlineText = " by \(d.formatted(.dateTime.month(.abbreviated).day()))"
            } else {
                deadlineText = ""
            }
            return "\(completedDays) of \(requiredDays) days toward \(rewardText)\(deadlineText)"
        }
    }

    static func progress(for rule: StreakRule, relativeTo date: Date = Date()) -> StreakProgress {
        guard let employer = rule.employer else {
            return StreakProgress(rule: rule, completedDays: 0, requiredDays: rule.requiredDays, deadline: nil, isComplete: false, isEarning: false, earnedBonusDays: 0)
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
        case .calendarQuarter:
            let comps = calendar.dateComponents([.year, .month], from: date)
            let month = comps.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var startComps = DateComponents()
            startComps.year = comps.year
            startComps.month = quarterStartMonth
            startComps.day = 1
            let quarterStart = calendar.date(from: startComps) ?? date
            deadline = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 3, to: quarterStart) ?? date)
        case .payPeriod:
            let (_, end) = payPeriodBounds(containing: date, employer: employer)
            deadline = end
        }

        return StreakProgress(
            rule: rule,
            completedDays: count,
            requiredDays: rule.requiredDays,
            deadline: deadline,
            isComplete: count >= rule.requiredDays,
            isEarning: count > rule.requiredDays,
            earnedBonusDays: max(0, count - rule.requiredDays)
        )
    }

    // MARK: - Pay Period Utilities

    static func payPeriodBounds(containing date: Date, employer: Employer) -> (Date, Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        switch employer.payCadence {
        case .weekly:
            let weekday = calendar.component(.weekday, from: today)
            let daysToMonday = (weekday == 1) ? -6 : 2 - weekday
            let start = calendar.date(byAdding: .day, value: daysToMonday, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? today
            return (start, end)

        case .biweekly:
            // Anchor: Jan 1 of current year, biweekly from there
            let comps = calendar.dateComponents([.year], from: today)
            let yearStart = calendar.date(from: comps) ?? today
            let daysDiff = calendar.dateComponents([.day], from: yearStart, to: today).day ?? 0
            let periodIndex = daysDiff / 14
            let start = calendar.date(byAdding: .day, value: periodIndex * 14, to: yearStart) ?? today
            let end = calendar.date(byAdding: .day, value: 13, to: start) ?? today
            return (start, end)

        case .monthly:
            var comps = calendar.dateComponents([.year, .month], from: today)
            let start = calendar.date(from: comps) ?? today
            comps.month! += 1
            let nextMonth = calendar.date(from: comps) ?? today
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? today
            return (start, end)

        case .custom:
            let days = employer.customCadenceDays ?? 14
            let comps = calendar.dateComponents([.year], from: today)
            let yearStart = calendar.date(from: comps) ?? today
            let daysDiff = calendar.dateComponents([.day], from: yearStart, to: today).day ?? 0
            let periodIndex = daysDiff / days
            let start = calendar.date(byAdding: .day, value: periodIndex * days, to: yearStart) ?? today
            let end = calendar.date(byAdding: .day, value: days - 1, to: start) ?? today
            return (start, end)
        }
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
