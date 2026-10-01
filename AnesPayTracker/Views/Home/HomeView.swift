import SwiftUI
import SwiftData

// MARK: - Home View

/// The first tab. Answers, without navigating: what has been earned in the
/// current work period, when is the next paycheck and how much is on it, and
/// how close the next streak bonus is.
///
/// All money figures come from existing engine/model logic (`Shift.totalPay`,
/// `StreakEngine.paycheckAggregationRows`, `StreakEngine.paycheckDate`) so Home
/// always agrees with the Pay Periods tab and the Paycheck Estimator report.
struct HomeView: View {
    @Query(sort: \Employer.name) private var employers: [Employer]
    @Query(sort: \Shift.date, order: .reverse) private var allShifts: [Shift]

    @State private var selectedShift: Shift?
    @State private var employerToSetUp: Employer?

    private var recentShifts: [Shift] {
        let endOfToday = Calendar.current.endOfDay(for: Date())
        return Array(allShifts.filter { $0.date <= endOfToday }.prefix(5))
    }

    private var employersWithStreaks: [Employer] {
        employers.filter { $0.activeStreakRule != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(employers) { employer in
                        EmployerPayOverview(
                            employer: employer,
                            showEmployerName: employers.count > 1,
                            onSetUpPaySchedule: { employerToSetUp = employer }
                        )
                    }

                    if !employersWithStreaks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Streaks")
                                    .font(.headline)
                                Spacer()
                                NavigationLink {
                                    StreakStatusContent()
                                } label: {
                                    Text("Details")
                                        .font(.subheadline.bold())
                                }
                            }
                            ForEach(employersWithStreaks) { employer in
                                if let rule = employer.activeStreakRule {
                                    HomeStreakCard(
                                        rule: rule,
                                        employerName: employers.count > 1 ? employer.name : nil
                                    )
                                }
                            }
                        }
                    }

                    if recentShifts.isEmpty {
                        EmptyStateView(
                            icon: "calendar.badge.plus",
                            title: "No shifts yet",
                            message: "Tap + to log your first shift."
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        RecentShiftsCard(shifts: recentShifts) { selectedShift = $0 }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Home")
            .addShiftToolbarButton()
            .sheet(item: $selectedShift) { shift in
                ShiftDetailView(shift: shift)
            }
            .sheet(item: $employerToSetUp) { employer in
                EmployerSetupWizard(mode: .edit, sourceEmployer: employer)
            }
        }
    }
}

// MARK: - Employer Pay Overview

/// Two cards per employer, kept deliberately separate because pay lags work:
/// the current *work* period (earning now, paid later) and the next *paycheck*
/// (usually for an earlier work period, plus any bonuses scheduled onto it).
struct EmployerPayOverview: View {
    let employer: Employer
    let showEmployerName: Bool
    let onSetUpPaySchedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showEmployerName {
                Text(employer.name)
                    .font(.headline)
            }
            // Without a known period end date the engine's period dates are
            // guesses, so don't present them as fact.
            if employer.hasReliablePayPeriods {
                CurrentWorkPeriodCard(employer: employer, showsPaycheckDate: employer.hasPaycheckAnchors)
            }
            if employer.hasPaycheckAnchors {
                NextPaycheckCard(employer: employer)
            } else {
                PayScheduleReminderRow(
                    title: employer.hasReliablePayPeriods ? "Set up paydays" : "Set up pay schedule",
                    action: onSetUpPaySchedule
                )
            }
        }
    }
}

// MARK: - Current Work Period

struct CurrentWorkPeriodCard: View {
    let employer: Employer
    let showsPaycheckDate: Bool

    private let calendar = Calendar.current

    private var bounds: (start: Date, end: Date) {
        StreakEngine.payPeriodBounds(containing: Date(), employer: employer)
    }

    private var periodShifts: [Shift] {
        let (start, end) = bounds
        let endOfPeriod = calendar.endOfDay(for: end)
        return employer.sites
            .flatMap(\.shifts)
            .filter { $0.date >= start && $0.date <= endOfPeriod }
    }

    private var workedShifts: [Shift] {
        let endOfToday = calendar.endOfDay(for: Date())
        return periodShifts.filter { $0.date <= endOfToday }
    }

    private var scheduledShifts: [Shift] {
        let endOfToday = calendar.endOfDay(for: Date())
        return periodShifts.filter { $0.date > endOfToday }
    }

    private var earnedSoFar: Decimal { workedShifts.reduce(0) { $0 + $1.totalPay } }
    private var scheduledPay: Decimal { scheduledShifts.reduce(0) { $0 + $1.totalPay } }

    private var dayProgress: (current: Int, total: Int) {
        let (start, end) = bounds
        let total = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let current = (calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: Date())).day ?? 0) + 1
        return (min(max(current, 1), total), max(total, 1))
    }

    private var paycheckDate: Date {
        StreakEngine.paycheckDate(for: Date(), employer: employer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This work period · \(HomeFormat.range(bounds.start, bounds.end))")
                .font(.footnote.bold())
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))

            Text(HomeFormat.dollars(earnedSoFar))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text(summaryText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(.white)
                        .frame(width: geo.size.width * CGFloat(dayProgress.current) / CGFloat(dayProgress.total))
                }
            }
            .frame(height: 5)
            .padding(.top, 8)
            .accessibilityHidden(true)

            HStack {
                Text("Day \(dayProgress.current) of \(dayProgress.total)")
                Spacer()
                if showsPaycheckDate {
                    Text("Paid \(HomeFormat.weekdayDate(paycheckDate))")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var summaryText: String {
        let count = workedShifts.count
        var text = count == 0
            ? "No shifts worked yet this period"
            : "Earned so far · \(count) shift\(count == 1 ? "" : "s")"
        if !scheduledShifts.isEmpty {
            text += " · \(HomeFormat.dollars(scheduledPay)) more scheduled"
        }
        return text
    }
}

// MARK: - Next Paycheck

struct NextPaycheckCard: View {
    let employer: Employer

    /// Rows from the same engine the Paycheck Estimator report uses, so the two
    /// always agree. Bonuses can land on a different paycheck than the base pay
    /// they were earned with (e.g. quarterly streak payouts).
    private var nextPaycheckRows: [PaycheckAggregationRow] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let upcoming = employer.sites
            .flatMap(\.shifts)
            .flatMap { StreakEngine.paycheckAggregationRows(for: $0) }
            .filter { $0.paycheckDate >= startOfToday }
        guard let next = upcoming.map(\.paycheckDate).min() else { return [] }
        return upcoming.filter { Calendar.current.isDate($0.paycheckDate, inSameDayAs: next) }
    }

    var body: some View {
        let rows = nextPaycheckRows
        VStack(alignment: .leading, spacing: 8) {
            Text("Next paycheck")
                .font(.footnote.bold())
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            if let date = rows.first?.paycheckDate {
                HStack(alignment: .firstTextBaseline) {
                    Text(HomeFormat.weekdayDate(date))
                        .font(.title3.bold())
                    Spacer()
                    Text(HomeFormat.dollars(total(rows)))
                        .font(.title3.bold())
                        .foregroundStyle(Color.accent)
                }

                if let coverage = coverageText(rows) {
                    Text(coverage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                let bonusTotal = total(rows.filter { $0.componentName != "Base Pay" })
                if bonusTotal > 0 {
                    Text("Includes \(HomeFormat.dollars(bonusTotal)) in bonuses")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Text("Estimate based on logged shifts")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No upcoming paychecks from logged shifts yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func total(_ rows: [PaycheckAggregationRow]) -> Decimal {
        rows.reduce(0) { $0 + $1.amount }
    }

    private func coverageText(_ rows: [PaycheckAggregationRow]) -> String? {
        let baseRows = rows.filter { $0.componentName == "Base Pay" }
        guard let start = baseRows.map(\.aggregationStart).min(),
              let end = baseRows.map(\.aggregationEnd).max() else { return nil }
        return "For work \(HomeFormat.range(start, end))"
    }
}

// MARK: - Pay Schedule Reminder

/// One compact, tappable line instead of a paragraph of directions. Opens the
/// employer editor, where "Use paycheck calendar anchors" lives.
struct PayScheduleReminderRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text("Add a pay-period end date and its paycheck date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the employer editor")
    }
}

// MARK: - Streak Card

struct HomeStreakCard: View {
    let rule: StreakRule
    let employerName: String?

    var body: some View {
        let progress = StreakEngine.progress(for: rule)
        VStack(alignment: .leading, spacing: 10) {
            if let employerName {
                Text(employerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(progress.displayText)
                .font(.subheadline.bold())
                .foregroundStyle(progress.isComplete ? .green : .primary)
            StreakProgressBar(current: progress.completedDays, required: progress.requiredDays)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Recent Shifts

struct RecentShiftsCard: View {
    let shifts: [Shift]
    let onSelect: (Shift) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent shifts")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(shifts) { shift in
                    Button {
                        onSelect(shift)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shift.site?.name ?? "—")
                                    .font(.body.bold())
                                    .foregroundStyle(.primary)
                                Text("\(HomeFormat.weekdayDate(shift.date)) · \(durationText(shift))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(HomeFormat.dollars(shift.totalPay))
                                .font(.body.bold())
                                .foregroundStyle(Color.accent)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if shift.id != shifts.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func durationText(_ shift: Shift) -> String {
        switch shift.payUnit {
        case .perDay:
            let fraction = shift.dayFraction ?? .full
            return fraction == .full ? "Full day" : "\(fraction.label) day"
        case .perHour:
            return "\((shift.hoursWorked ?? 0).formatted()) hrs"
        }
    }
}

// MARK: - Formatting

enum HomeFormat {
    static func dollars(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "USD"))
    }

    static func weekdayDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func range(_ start: Date, _ end: Date) -> String {
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }
}
