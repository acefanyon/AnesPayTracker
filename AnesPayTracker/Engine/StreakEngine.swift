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
                let dayMultiplier = shift.payUnit == .perDay ? (shift.dayFraction?.multiplier ?? 1) : 1
                shift.streakBonusAmount = earnedAmount * dayMultiplier
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
        let target = calendar.startOfDay(for: date)

        if let anchored = anchoredPayPeriodBounds(containing: target, employer: employer, calendar: calendar) {
            return anchored
        }

        switch employer.payCadence {
        case .weekly:
            let weekday = calendar.component(.weekday, from: target)
            let daysToMonday = (weekday == 1) ? -6 : 2 - weekday
            let start = calendar.date(byAdding: .day, value: daysToMonday, to: target) ?? target
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? target
            return (start, end)

        case .biweekly:
            // Legacy fallback for employers that have not configured a paycheck anchor yet.
            let comps = calendar.dateComponents([.year], from: target)
            let yearStart = calendar.date(from: comps) ?? target
            let daysDiff = calendar.dateComponents([.day], from: yearStart, to: target).day ?? 0
            let periodIndex = daysDiff / 14
            let start = calendar.date(byAdding: .day, value: periodIndex * 14, to: yearStart) ?? target
            let end = calendar.date(byAdding: .day, value: 13, to: start) ?? target
            return (start, end)

        case .monthly:
            var comps = calendar.dateComponents([.year, .month], from: target)
            let start = calendar.date(from: comps) ?? target
            comps.month! += 1
            let nextMonth = calendar.date(from: comps) ?? target
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? target
            return (start, end)

        case .custom:
            let days = employer.customCadenceDays ?? 14
            let comps = calendar.dateComponents([.year], from: target)
            let yearStart = calendar.date(from: comps) ?? target
            let daysDiff = calendar.dateComponents([.day], from: yearStart, to: target).day ?? 0
            let periodIndex = daysDiff / days
            let start = calendar.date(byAdding: .day, value: periodIndex * days, to: yearStart) ?? target
            let end = calendar.date(byAdding: .day, value: days - 1, to: start) ?? target
            return (start, end)
        }
    }

    static func paycheckDate(for serviceDate: Date, employer: Employer, calendar: Calendar = .current) -> Date {
        let (_, periodEnd) = payPeriodBounds(containing: serviceDate, employer: employer)
        let delayPeriods = max(0, employer.paycheckDelayPeriods)
        let referenceDate = dateByAddingPayPeriods(delayPeriods, to: periodEnd, employer: employer, calendar: calendar)
        return paycheckDate(onOrAfter: referenceDate, employer: employer, calendar: calendar)
    }

    static func paycheckAggregationWindow(for serviceDate: Date, employer: Employer, calendar: Calendar = .current) -> (start: Date, end: Date, paycheckDate: Date) {
        let (start, end) = payPeriodBounds(containing: serviceDate, employer: employer)
        let paycheck = paycheckDate(for: serviceDate, employer: employer, calendar: calendar)
        return (start, end, paycheck)
    }

    static func paycheckAggregationRows(for shift: Shift, calendar: Calendar = .current) -> [PaycheckAggregationRow] {
        guard let employer = shift.site?.employer else { return [] }
        let employerName = employer.name
        let siteName = shift.site?.name ?? "Unknown Site"

        func row(componentName: String, amount: Decimal, aggregationDate: Date) -> PaycheckAggregationRow? {
            guard amount > 0 else { return nil }
            let window = paycheckAggregationWindow(for: aggregationDate, employer: employer, calendar: calendar)
            return PaycheckAggregationRow(
                shiftID: shift.id,
                serviceDate: shift.date,
                aggregationStart: window.start,
                aggregationEnd: window.end,
                paycheckDate: window.paycheckDate,
                employerName: employerName,
                siteName: siteName,
                componentName: componentName,
                amount: amount
            )
        }

        var rows: [PaycheckAggregationRow] = []
        if let base = row(componentName: "Base Pay", amount: shift.basePay, aggregationDate: shift.date) {
            rows.append(base)
        }
        if let onCall = row(componentName: "On-Call Bonus", amount: shift.onCallPay, aggregationDate: shift.date) {
            rows.append(onCall)
        }
        for bonus in shift.customBonuses ?? [] {
            let payoutDate = bonus.payoutSchedule.payoutDate(for: shift.date, calendar: calendar)
            if let bonusRow = row(componentName: bonus.name, amount: bonus.totalAmount, aggregationDate: payoutDate) {
                rows.append(bonusRow)
            }
        }
        if let streak = shift.streakBonusAmount, streak > 0 {
            let schedule = shift.streakPayoutSchedule ?? .nextQuarterlyPayout
            let payoutDate = schedule.payoutDate(for: shift.date, calendar: calendar)
            if let streakRow = row(componentName: "Streak Bonus", amount: streak, aggregationDate: payoutDate) {
                rows.append(streakRow)
            }
        }
        return rows
    }

    private static func anchoredPayPeriodBounds(containing date: Date, employer: Employer, calendar: Calendar) -> (Date, Date)? {
        guard let anchor = employer.paycheckAnchorDate else { return nil }
        let anchorDay = calendar.startOfDay(for: anchor)

        switch employer.payCadence {
        case .weekly, .biweekly, .custom:
            guard let days = employer.payCadence.periodLengthDays(customDays: employer.customCadenceDays), days > 0 else { return nil }
            let daysFromAnchor = calendar.dateComponents([.day], from: anchorDay, to: date).day ?? 0
            let periodOffset = floorDiv(daysFromAnchor + days - 1, days)
            let end = calendar.date(byAdding: .day, value: periodOffset * days, to: anchorDay) ?? anchorDay
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
            if date < start {
                let priorEnd = calendar.date(byAdding: .day, value: -days, to: end) ?? end
                let priorStart = calendar.date(byAdding: .day, value: -(days - 1), to: priorEnd) ?? priorEnd
                return (priorStart, priorEnd)
            }
            return (start, end)
        case .monthly:
            return nil
        }
    }

    private static func paycheckDate(onOrAfter date: Date, employer: Employer, calendar: Calendar) -> Date {
        guard let anchor = employer.paycheckAnchorDate else { return date }
        let target = calendar.startOfDay(for: date)
        let anchorDay = calendar.startOfDay(for: anchor)

        switch employer.payCadence {
        case .weekly, .biweekly, .custom:
            guard let days = employer.payCadence.periodLengthDays(customDays: employer.customCadenceDays), days > 0 else { return target }
            let daysFromAnchor = calendar.dateComponents([.day], from: anchorDay, to: target).day ?? 0
            let offset = ceilDiv(daysFromAnchor, days)
            return calendar.date(byAdding: .day, value: offset * days, to: anchorDay) ?? target
        case .monthly:
            var candidate = anchorDay
            while candidate < target {
                candidate = calendar.date(byAdding: .month, value: 1, to: candidate) ?? target
            }
            return candidate
        }
    }

    private static func dateByAddingPayPeriods(_ count: Int, to date: Date, employer: Employer, calendar: Calendar) -> Date {
        switch employer.payCadence {
        case .weekly, .biweekly, .custom:
            let days = employer.payCadence.periodLengthDays(customDays: employer.customCadenceDays) ?? 14
            return calendar.date(byAdding: .day, value: days * count, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: count, to: date) ?? date
        }
    }

    private static func floorDiv(_ numerator: Int, _ denominator: Int) -> Int {
        precondition(denominator > 0)
        if numerator >= 0 { return numerator / denominator }
        return -((-numerator + denominator - 1) / denominator)
    }

    private static func ceilDiv(_ numerator: Int, _ denominator: Int) -> Int {
        precondition(denominator > 0)
        if numerator >= 0 { return (numerator + denominator - 1) / denominator }
        return -((-numerator) / denominator)
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
