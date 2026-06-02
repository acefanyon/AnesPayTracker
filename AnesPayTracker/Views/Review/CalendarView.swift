import SwiftUI
import SwiftData

// MARK: - Calendar View

struct CalendarView: View {
    @Query(sort: \Shift.date, order: .reverse) private var allShifts: [Shift]
    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date?
    @State private var activeSheet: CalendarSheet?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month navigation
                MonthNavigationHeader(displayedMonth: $displayedMonth)

                // Weekday headers
                WeekdayHeader()

                Divider()

                // Month grid
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                        ForEach(calendarDays, id: \.self) { date in
                            if let date = date {
                                CalendarDayCell(
                                    date: date,
                                    shifts: shiftsOn(date: date),
                                    isToday: calendar.isDateInToday(date)
                                ) {
                                    handleDayTap(date)
                                }
                            } else {
                                Color.clear
                                    .frame(height: 72)
                            }
                        }
                    }
                    .padding(8)

                    // Summary for month
                    if !monthShifts.isEmpty {
                        MonthSummaryCard(shifts: monthShifts)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Today") {
                        withAnimation { displayedMonth = Date() }
                    }
                    .font(.body)
                }
            }
            .sheet(item: $activeSheet, onDismiss: {
                selectedDate = nil
            }) { sheet in
                switch sheet {
                case .addShift:
                    if let selectedDate {
                        AddShiftView(initialDate: selectedDate)
                    }
                case .daySheet:
                    if let selectedDate {
                        CalendarDaySheet(
                            date: selectedDate,
                            shifts: shiftsOn(date: selectedDate)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Calendar Grid Computation

    private var calendarDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }

        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: offset)

        var current = firstDay
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }

        // Pad to complete grid
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private func shiftsOn(date: Date) -> [Shift] {
        allShifts.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private var monthShifts: [Shift] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        return allShifts.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private func handleDayTap(_ date: Date) {
        selectedDate = date
        activeSheet = shiftsOn(date: date).isEmpty ? .addShift : .daySheet
    }
}

private enum CalendarSheet: String, Identifiable {
    case addShift
    case daySheet

    var id: String { rawValue }
}

// MARK: - Month Navigation

struct MonthNavigationHeader: View {
    @Binding var displayedMonth: Date
    private let calendar = Calendar.current

    var body: some View {
        HStack {
            Button {
                withAnimation { displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.title2.bold())

            Spacer()

            Button {
                withAnimation { displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Weekday Header

struct WeekdayHeader: View {
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(days, id: \.self) { day in
                Text(day)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let date: Date
    let shifts: [Shift]
    let isToday: Bool
    let onTapDay: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: onTapDay) {
            VStack(spacing: 3) {
                // Day number
                Text(calendar.component(.day, from: date).description)
                    .font(.footnote.bold())
                    .foregroundStyle(isToday ? .white : .primary)
                    .frame(width: 26, height: 26)
                    .background(isToday ? Color.accent : Color.clear, in: Circle())

                // Shift chips
                ForEach(shifts.prefix(2)) { shift in
                    HStack(spacing: 2) {
                        Text(shift.site?.initials ?? "?")
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                        if shift.isOnCall {
                            Text("OC")
                                .font(.system(size: 7, weight: .black))
                        }
                        if shift.hasStreakBonus {
                            Text("🎯")
                                .font(.system(size: 8))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                    .background((shift.isOnCall ? Color.blue : Color.accent).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(shift.isOnCall ? Color.blue : Color.accent)
                }

                if shifts.count > 2 {
                    Text("+\(shifts.count - 2)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .frame(height: 72, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(shifts.isEmpty ? Color.clear : Color.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Day Sheet

struct CalendarDaySheet: View {
    let date: Date
    let shifts: [Shift]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedShift: Shift?
    @State private var showAddShift = false

    private var sortedShifts: [Shift] {
        shifts.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedShifts) { shift in
                        Button {
                            selectedShift = shift
                        } label: {
                            CalendarDayShiftRow(shift: shift)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(sortedShifts.count) shift\(sortedShifts.count == 1 ? "" : "s")")
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showAddShift = true
                    } label: {
                        Label("Add Shift", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $selectedShift) { shift in
                ShiftDetailView(shift: shift)
            }
            .sheet(isPresented: $showAddShift) {
                AddShiftView(initialDate: date)
            }
        }
    }
}

struct CalendarDayShiftRow: View {
    let shift: Shift

    private var streakBadgeText: String? {
        guard shift.hasStreakBonus else { return nil }
        return "Streak"
    }

    private var onCallBadgeText: String? {
        guard shift.isOnCall else { return nil }
        return shift.hasOnCallBonus ? "On-Call \(shift.onCallPay.formatted(.currency(code: "USD")))" : "On-Call"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shift.site?.name ?? "Unknown Site")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(shift.totalPay.formatted(.currency(code: "USD")))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accent)

                HStack(spacing: 6) {
                    if let onCallBadgeText {
                        Text(onCallBadgeText)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.blue)
                    }

                    if let streakBadgeText {
                        Text(streakBadgeText)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.orange)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Month Summary Card

struct MonthSummaryCard: View {
    let shifts: [Shift]

    var totalPay: Decimal { shifts.reduce(0) { $0 + $1.totalPay } }
    var totalBase: Decimal { shifts.reduce(0) { $0 + $1.basePay } }
    var totalBonuses: Decimal { totalPay - totalBase }
    var onCallCount: Int { shifts.filter { $0.isOnCall }.count }
    var streakCount: Int { shifts.filter { $0.hasStreakBonus }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Month")
                .font(.headline)

            HStack {
                StatPill(label: "\(shifts.count) shifts", icon: "calendar")
                Spacer()
                StatPill(label: totalPay.formatted(.currency(code: "USD")), icon: "dollarsign", highlight: true)
            }

            if totalBonuses > 0 {
                HStack {
                    StatPill(label: "Base: \(totalBase.formatted(.currency(code: "USD")))", icon: "banknote")
                    Spacer()
                    StatPill(label: "Bonuses: \(totalBonuses.formatted(.currency(code: "USD")))", icon: "star")
                }
            }

            if onCallCount > 0 || streakCount > 0 {
                HStack {
                    if onCallCount > 0 {
                        StatPill(label: "\(onCallCount) on-call", icon: "phone.badge.clock")
                    }
                    Spacer()
                    if streakCount > 0 {
                        StatPill(label: "\(streakCount) streak", icon: "target")
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StatPill: View {
    let label: String
    let icon: String
    var highlight: Bool = false

    var body: some View {
        Label(label, systemImage: icon)
            .font(.footnote.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(highlight ? Color.accent.opacity(0.15) : Color.secondary.opacity(0.1), in: Capsule())
            .foregroundStyle(highlight ? Color.accent : .primary)
    }
}
