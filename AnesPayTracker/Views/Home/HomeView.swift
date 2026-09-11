import SwiftUI
import SwiftData

// MARK: - Home View

/// The answer screen: what have I earned this period, when does it get paid,
/// and how close is the next streak bonus — without leaving the first tab.
struct HomeView: View {
    @Query private var employers: [Employer]
    @Query(sort: \Shift.date, order: .reverse) private var allShifts: [Shift]

    @State private var selectedShift: Shift?

    private var activeRules: [(employer: Employer, rule: StreakRule)] {
        employers.flatMap { emp in
            emp.streakRules.filter(\.isActive).map { (emp, $0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(employers) { employer in
                        CurrentPeriodCard(
                            employer: employer,
                            allShifts: allShifts,
                            showEmployerName: employers.count > 1
                        )
                    }

                    if !activeRules.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Streaks")
                                    .font(.headline)
                                Spacer()
                                NavigationLink {
                                    StreakStatusView()
                                } label: {
                                    Text("History")
                                        .font(.footnote.bold())
                                        .foregroundStyle(Color.accent)
                                }
                            }
                            ForEach(activeRules, id: \.rule.id) { pair in
                                HomeStreakCard(
                                    rule: pair.rule,
                                    employerName: employers.count > 1 ? pair.employer.name : nil
                                )
                            }
                        }
                    }

                    if allShifts.isEmpty {
                        EmptyStateView(
                            icon: "cross.case",
                            title: "No shifts yet",
                            message: "Tap the + button to log your first shift."
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        RecentShiftsCard(
                            shifts: Array(allShifts.prefix(5)),
                            onSelect: { selectedShift = $0 }
                        )
                    }
                }
                .padding(16)
            }
            .navigationTitle("Today")
            .sheet(item: $selectedShift) { shift in
                ShiftDetailView(shift: shift)
            }
        }
    }
}

// MARK: - Current Pay Period Card

struct CurrentPeriodCard: View {
    let employer: Employer
    let allShifts: [Shift]
    let showEmployerName: Bool

    private var bounds: (start: Date, end: Date) {
        StreakEngine.payPeriodBounds(containing: Date(), employer: employer)
    }

    private var periodShifts: [Shift] {
        allShifts.filter {
            $0.site?.employer?.id == employer.id
            && $0.date >= bounds.start
            && $0.date <= Calendar.current.endOfDay(for: bounds.end)
        }
    }

    private var totalPay: Decimal {
        periodShifts.reduce(0) { $0 + $1.totalPay }
    }

    private var periodLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: bounds.start)) – \(fmt.string(from: bounds.end))"
    }

    private var dayProgress: (current: Int, total: Int) {
        let calendar = Calendar.current
        let total = (calendar.dateComponents([.day], from: bounds.start, to: bounds.end).day ?? 13) + 1
        let current = (calendar.dateComponents([.day], from: bounds.start, to: calendar.startOfDay(for: Date())).day ?? 0) + 1
        return (min(current, total), total)
    }

    private var payday: Date? {
        StreakEngine.payday(forPeriodEnding: bounds.end, employer: employer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This pay period · \(periodLabel)")
                .font(.footnote.bold())
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.75))

            Text(totalPay.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(periodShifts.isEmpty
                 ? "No shifts yet this period"
                 : "\(periodShifts.count) shift\(periodShifts.count == 1 ? "" : "s")\(showEmployerName ? " · \(employer.name)" : "")")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                    Capsule()
                        .fill(.white)
                        .frame(width: geo.size.width * CGFloat(dayProgress.current) / CGFloat(max(1, dayProgress.total)))
                }
            }
            .frame(height: 5)
            .padding(.top, 8)

            HStack {
                Text("Day \(dayProgress.current) of \(dayProgress.total)")
                Spacer()
                if let payday {
                    Text("Payday · \(payday.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Streak Card (compact)

struct HomeStreakCard: View {
    let rule: StreakRule
    let employerName: String?

    private var progress: StreakEngine.StreakProgress {
        StreakEngine.progress(for: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let employerName {
                        Text(employerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(progress.displayText)
                        .font(.subheadline.bold())
                        .foregroundStyle(progress.isComplete ? .green : .primary)
                }
                Spacer()
                Text(rule.bonusAmount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(.body.bold())
                    .foregroundStyle(.orange)
            }

            StreakProgressBar(
                current: progress.completedDays,
                required: progress.requiredDays
            )
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
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
                                HStack(spacing: 4) {
                                    Text(shift.site?.name ?? "—")
                                        .font(.body.bold())
                                        .foregroundStyle(.primary)
                                    if shift.hasStreakBonus {
                                        Image(systemName: "target")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Text("\(shift.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(durationText(shift))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(shift.totalPay.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                .font(.body.bold())
                                .foregroundStyle(Color.accent)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if shift.id != shifts.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
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
