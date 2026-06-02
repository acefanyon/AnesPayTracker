import SwiftUI
import SwiftData

// MARK: - Streak Status View

struct StreakStatusView: View {
    @Query private var employers: [Employer]
    @Query(sort: \Shift.date, order: .reverse) private var allShifts: [Shift]

    @State private var selectedShift: Shift?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(employers) { employer in
                        if employer.activeStreakRule != nil {
                            EmployerStreakSection(
                                employer: employer,
                                allShifts: allShifts,
                                onSelectShift: { selectedShift = $0 }
                            )
                        }
                    }

                    if employers.allSatisfy({ $0.activeStreakRule == nil }) {
                        EmptyStateView(
                            icon: "flame",
                            title: "No streak rules",
                            message: "Add streak rules in your employer settings to track bonus progress."
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Streaks")
            .sheet(item: $selectedShift) { shift in
                ShiftDetailView(shift: shift)
            }
        }
    }
}

// MARK: - Employer Streak Section

struct EmployerStreakSection: View {
    let employer: Employer
    let allShifts: [Shift]
    let onSelectShift: (Shift) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(employer.name)
                .font(.title3.bold())
                .padding(.horizontal, 4)

            if let rule = employer.activeStreakRule {
                StreakRuleCard(
                    rule: rule,
                    progress: StreakEngine.progress(for: rule),
                    earnedShifts: earnedShifts(for: rule),
                    onSelectShift: onSelectShift
                )
            }
        }
    }

    private func earnedShifts(for rule: StreakRule) -> [Shift] {
        allShifts
            .filter { $0.streakRuleTriggeredID == rule.id && $0.streakQualifiedForPayout }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Streak Rule Card

struct StreakRuleCard: View {
    let rule: StreakRule
    let progress: StreakEngine.StreakProgress
    let earnedShifts: [Shift]
    let onSelectShift: (Shift) -> Void

    @State private var showHistory = false

    private var perDayAmount: Decimal {
        rule.postThresholdPerDayAmount ?? rule.bonusAmount
    }

    private var payoutText: String {
        switch rule.payoutSchedule {
        case .serviceDate:
            return "Paid with the shift"
        case .nextMonthlyPayout:
            return "Paid at next monthly payout"
        case .nextQuarterlyPayout:
            return "Paid at next quarterly payout"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(progress.completedDays) of \(progress.requiredDays) days toward +\(perDayAmount.formatted(.currency(code: "USD")))/day")
                            .font(.body.bold())
                    }
                    Spacer()
                    Text("+\(perDayAmount.formatted(.currency(code: "USD")))/day")
                        .font(.body.bold())
                        .foregroundStyle(Color.accent)
                }

                StreakProgressBar(
                    current: progress.completedDays,
                    required: progress.requiredDays
                )

                Text(progress.displayText)
                    .font(.body.bold())
                    .foregroundStyle(progress.isComplete ? .green : .primary)

                HStack(spacing: 8) {
                    StatusChip(
                        label: progress.isEarning ? "Earning now" : (progress.isComplete ? "Threshold met" : "In progress"),
                        systemImage: progress.isEarning ? "flame.fill" : (progress.isComplete ? "checkmark.circle.fill" : "calendar.badge.clock"),
                        tint: progress.isEarning ? .green : (progress.isComplete ? .mint : .accentColor)
                    )

                    StatusChip(
                        label: "\(progress.earnedBonusDays) earning day\(progress.earnedBonusDays == 1 ? "" : "s")",
                        systemImage: "dollarsign.circle",
                        tint: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(payoutText, systemImage: "clock.arrow.circlepath")
                    if let deadline = progress.deadline {
                        Label("Quarter resets after \(deadline.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "calendar")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(16)

            if !earnedShifts.isEmpty {
                Divider()

                Button {
                    withAnimation { showHistory.toggle() }
                } label: {
                    HStack {
                        Text("History (\(earnedShifts.count) earned)")
                            .font(.footnote.bold())
                        Spacer()
                        Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if showHistory {
                    Divider()
                    ForEach(earnedShifts) { shift in
                        Button {
                            onSelectShift(shift)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("🎯 \(shift.site?.name ?? "—")")
                                        .font(.footnote.bold())
                                    Text(shift.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Paid quarterly later")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text((shift.streakBonusAmount ?? 0).formatted(.currency(code: "USD")))
                                    .font(.footnote.bold())
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StatusChip: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Progress Bar

struct StreakProgressBar: View {
    let current: Int
    let required: Int

    var fraction: Double { min(1.0, Double(current) / Double(max(1, required))) }
    var isComplete: Bool { current >= required }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(isComplete ? Color.green : Color.accent)
                        .frame(width: geo.size.width * fraction, height: 10)
                        .animation(.spring(response: 0.5), value: fraction)
                }
            }
            .frame(height: 10)

            HStack {
                ForEach(0..<required, id: \.self) { i in
                    Circle()
                        .fill(i < current ? (isComplete ? Color.green : Color.accent) : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                Spacer()
            }
        }
    }
}
