import SwiftUI

// MARK: - Pay Breakdown Card
struct PayBreakdownCard: View {
    let shift: Shift

    private var streakPayoutDetail: String {
        let schedule = shift.streakPayoutSchedule ?? .nextQuarterlyPayout
        let payoutDate = schedule.payoutDate(for: shift.date)
        return "Earned on this shift, paid \(payoutDate.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    var body: some View {
        InfoCard(title: "Pay Breakdown") {
            VStack(spacing: 0) {
                switch shift.payUnit {
                case .perDay:
                    BreakdownRow(
                        label: "\(shift.baseAmount.formatted(.currency(code: "USD"))) × \(shift.dayFraction?.label ?? "Full")",
                        value: shift.basePay,
                        isBase: true
                    )
                case .perHour:
                    let hrs = shift.hoursWorked ?? 0
                    BreakdownRow(
                        label: "\(shift.baseAmount.formatted(.currency(code: "USD")))/hr × \(hrs.formatted()) hrs",
                        value: shift.basePay,
                        isBase: true
                    )
                }

                if let splash = shift.splashAmount, splash > 0 {
                    Divider()
                    BreakdownRow(label: "Splash Bonus", value: splash)
                }

                if let bonus = shift.bonusSplashAmount, bonus > 0 {
                    Divider()
                    BreakdownRow(label: "Bonus Splash", value: bonus)
                }

                if shift.hasOnCallBonus {
                    Divider()
                    BreakdownRow(
                        label: "On-Call Bonus",
                        detail: "Paid with this shift on the service date",
                        value: shift.onCallPay,
                        highlight: true
                    )
                }

                ForEach(shift.customBonuses ?? []) { bonus in
                    if bonus.totalAmount > 0 {
                        Divider()
                        BreakdownRow(label: bonus.name, value: bonus.totalAmount)
                    }
                }

                if let streak = shift.streakBonusAmount, streak > 0 {
                    Divider()
                    BreakdownRow(
                        label: "🎯 Streak Bonus",
                        detail: streakPayoutDetail,
                        value: streak,
                        highlight: true
                    )
                }

                Divider()
                BreakdownRow(label: "Total", value: shift.totalPay, isTotal: true)
            }
        }
    }
}

struct BreakdownRow: View {
    let label: String
    var detail: String? = nil
    let value: Decimal
    var isBase: Bool = false
    var isTotal: Bool = false
    var highlight: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(isTotal ? .body.bold() : .body)
                    .foregroundStyle(highlight ? .orange : (isBase ? .secondary : .primary))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value.formatted(.currency(code: "USD")))
                .font(isTotal ? .title3.bold() : .body)
                .foregroundStyle(isTotal ? Color.accent : (highlight ? .orange : .primary))
        }
        .padding(.vertical, 10)
    }
}

// MARK: - InfoCard (shared style)
struct InfoCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            content
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.06)))
    }
}