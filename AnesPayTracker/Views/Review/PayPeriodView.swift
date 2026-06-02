import SwiftUI
import SwiftData

// MARK: - Pay Period View

struct PayPeriodView: View {
    @Query private var employers: [Employer]
    @Query(sort: \Shift.date, order: .reverse) private var allShifts: [Shift]
    
    @State private var selectedEmployer: Employer?
    @State private var displayedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedShift: Shift?
    
    var filteredShifts: [Shift] {
        if let emp = selectedEmployer {
            return allShifts.filter { $0.site?.employer?.id == emp.id }
        }
        return allShifts
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Employer filter
                if employers.count > 1 {
                    EmployerFilterBar(employers: employers, selected: $selectedEmployer)
                }
                
                ScrollView {
                    VStack(spacing: 16) {
                        if let employer = selectedEmployer ?? employers.first {
                            let periods = payPeriodGroups(for: employer)
                            if periods.isEmpty {
                                EmptyStateView(
                                    icon: "dollarsign.circle",
                                    title: "No pay periods yet",
                                    message: "Shifts will appear here once you add them."
                                )
                                .padding(.top, 60)
                            } else {
                                ForEach(periods, id: \.start) { period in
                                    PayPeriodCard(
                                        period: period,
                                        employer: employer,
                                        onSelectShift: { selectedShift = $0 }
                                    )
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Pay Periods")
            .sheet(item: $selectedShift) { shift in
                ShiftDetailView(shift: shift)
            }
        }
    }
    
    struct PeriodGroup {
        let start: Date
        let end: Date
        let shifts: [Shift]
        
        var totalBase: Decimal { shifts.reduce(0) { $0 + $1.basePay } }
        var totalOnCall: Decimal { shifts.reduce(0) { $0 + $1.onCallPay } }
        var totalBonus: Decimal { shifts.reduce(0) { $0 + $1.bonusPay } }
        var totalStreak: Decimal { shifts.reduce(0) { $0 + ($1.streakBonusAmount ?? 0) } }
        var totalImmediate: Decimal { totalBase + totalBonus }
        var grandTotal: Decimal { shifts.reduce(0) { $0 + $1.totalPay } }
        
        var label: String {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
        }
    }
    
    private func payPeriodGroups(for employer: Employer) -> [PeriodGroup] {
        let shiftsForEmployer = filteredShifts.filter { $0.site?.employer?.id == employer.id }
        guard !shiftsForEmployer.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let allDates = shiftsForEmployer.map { $0.date }
        guard let earliest = allDates.min(), let latest = allDates.max() else { return [] }
        
        var groups: [PeriodGroup] = []
        var current = earliest
        
        while current <= latest {
            let (start, end) = StreakEngine.payPeriodBounds(containing: current, employer: employer)
            let periodShifts = shiftsForEmployer.filter { $0.date >= start && $0.date <= end }
            
            if !periodShifts.isEmpty {
                // Avoid duplicates
                if !groups.contains(where: { calendar.isDate($0.start, inSameDayAs: start) }) {
                    groups.append(PeriodGroup(start: start, end: end, shifts: periodShifts.sorted { $0.date > $1.date }))
                }
            }
            
            current = calendar.date(byAdding: .day, value: 1, to: end) ?? latest
        }
        
        return groups.sorted { $0.start > $1.start }
    }
}

// MARK: - Employer Filter Bar

struct EmployerFilterBar: View {
    let employers: [Employer]
    @Binding var selected: Employer?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selected == nil) {
                    selected = nil
                }
                ForEach(employers) { emp in
                    FilterChip(label: emp.name, isSelected: selected?.id == emp.id) {
                        selected = emp
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.secondary.opacity(0.04))
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accent : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pay Period Card

struct PayPeriodCard: View {
    let period: PayPeriodView.PeriodGroup
    let employer: Employer
    let onSelectShift: (Shift) -> Void
    
    @State private var isExpanded: Bool = false
    
    // Is current period
    private var isCurrent: Bool {
        let today = Date()
        return today >= period.start && today <= period.end
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(period.label)
                                .font(.body.bold())
                            if isCurrent {
                                Text("Current")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.accent.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color.accent)
                            }
                        }
                        Text("\(period.shifts.count) shift\(period.shifts.count == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(period.grandTotal.formatted(.currency(code: "USD")))
                            .font(.title3.bold())
                            .foregroundStyle(Color.accent)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                
                // Totals breakdown
                PayPeriodTotalsRow(period: period)
                
                Divider()
                
                // Shift list
                VStack(spacing: 0) {
                    ForEach(period.shifts) { shift in
                        Button {
                            onSelectShift(shift)
                        } label: {
                             PayBreakdownCard(shift: shift)
                        }
                        .buttonStyle(.plain)

                        if shift.id != period.shifts.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isCurrent ? Color.accent.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
        )
    }
}

// MARK: - Pay Period Totals

struct PayPeriodTotalsRow: View {
    let period: PayPeriodView.PeriodGroup

    private var otherBonusTotal: Decimal {
        period.totalBonus - period.totalOnCall
    }
    
    var body: some View {
        HStack(spacing: 0) {
            TotalColumn(label: "Base", amount: period.totalBase)
            if period.totalOnCall > 0 {
                Divider()
                TotalColumn(label: "On-Call", amount: period.totalOnCall)
            }
            if otherBonusTotal > 0 {
                Divider()
                TotalColumn(label: period.totalOnCall > 0 ? "Other Bonuses" : "Bonuses", amount: otherBonusTotal)
            }
            if period.totalStreak > 0 {
                Divider()
                TotalColumn(label: "🎯 Deferred Streak", amount: period.totalStreak)
            }
            Divider()
            TotalColumn(label: "Total", amount: period.grandTotal, highlight: true)
        }
        .padding(.vertical, 10)
    }
}

struct TotalColumn: View {
    let label: String
    let amount: Decimal
    var highlight: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(amount.formatted(.currency(code: "USD")))
                .font(.footnote.bold())
                .foregroundStyle(highlight ? Color.accent : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Shift Row in Pay Period

struct PayPeriodShiftRow: View {
    let shift: Shift

    private var immediatePayText: String {
        let immediatePay = shift.basePay + shift.bonusPay
        return "Paid with shift: \(immediatePay.formatted(.currency(code: "USD")))"
    }

    private var onCallText: String? {
        guard shift.isOnCall else { return nil }
        return "On-call: \(shift.onCallPay.formatted(.currency(code: "USD")))"
    }

    private var deferredPayText: String? {
        guard let streak = shift.streakBonusAmount, streak > 0 else { return nil }
        let payoutDate = (shift.streakPayoutSchedule ?? .nextQuarterlyPayout).payoutDate(for: shift.date)
        return "Quarterly streak: \(streak.formatted(.currency(code: "USD"))) on \(payoutDate.formatted(.dateTime.month(.abbreviated).day()))"
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(shift.site?.name ?? "—")
                        .font(.body.bold())
                    if shift.hasStreakBonus {
                        Text("🎯")
                    }
                    if shift.isEdited {
                        Image(systemName: "pencil.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Text(shift.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(immediatePayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let onCallText {
                    Text(onCallText)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if let deferredPayText {
                    Text(deferredPayText)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            Text(shift.totalPay.formatted(.currency(code: "USD")))
                .font(.body.bold())
                .foregroundStyle(Color.accent)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.accent.opacity(0.5))
            Text(title).font(.title3.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
