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
                        if !employer.streakRules.filter({ $0.isActive }).isEmpty {
                            EmployerStreakSection(
                                employer: employer,
                                allShifts: allShifts,
                                onSelectShift: { selectedShift = $0 }
                            )
                        }
                    }
                    
                    if employers.allSatisfy({ $0.streakRules.filter({ $0.isActive }).isEmpty }) {
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
            
            ForEach(employer.streakRules.filter { $0.isActive }) { rule in
                StreakRuleCard(
                    rule: rule,
                    progress: StreakEngine.progress(for: rule),
                    triggeredShifts: triggeredShifts(for: rule),
                    onSelectShift: onSelectShift
                )
            }
        }
    }
    
    private func triggeredShifts(for rule: StreakRule) -> [Shift] {
        allShifts
            .filter { $0.streakRuleTriggeredID == rule.id }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Streak Rule Card

struct StreakRuleCard: View {
    let rule: StreakRule
    let progress: StreakEngine.StreakProgress
    let triggeredShifts: [Shift]
    let onSelectShift: (Shift) -> Void
    
    @State private var showHistory = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Rule summary
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(rule.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rule.bonusAmount.formatted(.currency(code: "USD")))
                        .font(.body.bold())
                        .foregroundStyle(Color.accent)
                }
                
                // Progress bar
                StreakProgressBar(
                    current: progress.completedDays,
                    required: progress.requiredDays
                )
                
                // Status text
                Text(progress.displayText)
                    .font(.body.bold())
                    .foregroundStyle(progress.isComplete ? .green : .primary)
            }
            .padding(16)
            
            if !triggeredShifts.isEmpty {
                Divider()
                
                Button {
                    withAnimation { showHistory.toggle() }
                } label: {
                    HStack {
                        Text("History (\(triggeredShifts.count) earned)")
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
                    ForEach(triggeredShifts) { shift in
                        Button {
                            onSelectShift(shift)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("🎯 \(shift.site?.name ?? "—")")
                                        .font(.footnote.bold())
                                    Text(shift.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
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
