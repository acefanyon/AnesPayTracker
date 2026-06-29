import SwiftUI
import SwiftData

// MARK: - Calendar View Mode

enum CalendarViewMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
}

// MARK: - Calendar View

struct CalendarView: View {
    @Query(sort: \Shift.date, order: .reverse) private var allShifts: [Shift]
    @State private var viewMode: CalendarViewMode = .month
    @State private var displayedDate: Date = Date()
    @State private var selectedDate: Date?
    @State private var activeSheet: CalendarSheet?

    private let calendar = Calendar.current

    private var displayedTitle: String {
        switch viewMode {
        case .month:
            return displayedDate.formatted(.dateTime.month(.wide).year())
        case .week:
            let start = weekStart
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            let startStr = fmt.string(from: start)
            let endStr: String = {
                let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
                if sameMonth {
                    fmt.dateFormat = "d"
                }
                return fmt.string(from: end)
            }()
            return "\(startStr) – \(endStr)"
        }
    }

    private var weekStart: Date {
        let weekday = calendar.component(.weekday, from: displayedDate)
        let offset = weekday - calendar.firstWeekday
        let adjustedOffset = offset >= 0 ? offset : offset + 7
        return calendar.date(byAdding: .day, value: -adjustedOffset, to: calendar.startOfDay(for: displayedDate)) ?? displayedDate
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode toggle
                Picker("View", selection: $viewMode) {
                    ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Navigation header
                CalendarNavigationHeader(
                    title: displayedTitle,
                    onPrevious: {
                        withAnimation {
                            switch viewMode {
                            case .month:
                                displayedDate = calendar.date(byAdding: .month, value: -1, to: displayedDate) ?? displayedDate
                            case .week:
                                displayedDate = calendar.date(byAdding: .day, value: -7, to: displayedDate) ?? displayedDate
                            }
                        }
                    },
                    onNext: {
                        withAnimation {
                            switch viewMode {
                            case .month:
                                displayedDate = calendar.date(byAdding: .month, value: 1, to: displayedDate) ?? displayedDate
                            case .week:
                                displayedDate = calendar.date(byAdding: .day, value: 7, to: displayedDate) ?? displayedDate
                            }
                        }
                    }
                )

                // Weekday headers
                WeekdayHeader()

                Divider()

                // Calendar grid
                ScrollView {
                    if viewMode == .month {
                        monthGrid
                    } else {
                        weekContent
                    }

                    // Summary card
                    if !visibleShifts.isEmpty {
                        CalendarSummaryCard(
                            title: viewMode == .month ? "This Month" : "This Week",
                            shifts: visibleShifts
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Today") {
                        withAnimation { displayedDate = Date() }
                    }
                    .font(.body)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addShift(let date):
                    AddShiftView(initialDate: date)
                case .daySheet(let date):
                    CalendarDaySheet(
                        date: date,
                        shifts: shiftsOn(date: date)
                    )
                }
            }
        }
    }

    // MARK: - Month Grid

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    CalendarDayCell(
                        date: date,
                        shifts: shiftsOn(date: date),
                        isToday: calendar.isDateInToday(date),
                        compact: true
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
    }

    // MARK: - Week Content

    private var weekContent: some View {
        VStack(spacing: 0) {
            // Week day headers as a row of day cells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(weekDays, id: \.self) { date in
                    CalendarDayCell(
                        date: date,
                        shifts: shiftsOn(date: date),
                        isToday: calendar.isDateInToday(date),
                        compact: false
                    ) {
                        handleDayTap(date)
                    }
                }
            }
            .padding(8)

            // Day-by-day detail list below the grid
            ForEach(weekDays, id: \.self) { date in
                let dayShifts = shiftsOn(date: date)
                if !dayShifts.isEmpty {
                    WeekDayRow(date: date, shifts: dayShifts) {
                        handleDayTap(date)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Calendar Grid Computation

    private var calendarDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedDate) else { return [] }

        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: offset)

        var current = firstDay
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private var weekDays: [Date] {
        let start = weekStart
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func shiftsOn(date: Date) -> [Shift] {
        allShifts.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private var visibleShifts: [Shift] {
        switch viewMode {
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: displayedDate) else { return [] }
            return allShifts.filter { $0.date >= interval.start && $0.date < interval.end }
        case .week:
            let start = weekStart
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
            return allShifts.filter { $0.date >= start && $0.date < end }
        }
    }

    private func handleDayTap(_ date: Date) {
        activeSheet = shiftsOn(date: date).isEmpty ? .addShift(date) : .daySheet(date)
    }
}

private enum CalendarSheet: Identifiable {
    case addShift(Date)
    case daySheet(Date)

    var id: String {
        switch self {
        case .addShift(let date): return "add-\(date.timeIntervalSinceReferenceDate)"
        case .daySheet(let date): return "day-\(date.timeIntervalSinceReferenceDate)"
        }
    }
}

// MARK: - Calendar Navigation Header

struct CalendarNavigationHeader: View {
    let title: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(title)
                .font(.title2.bold())

            Spacer()

            Button(action: onNext) {
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
    let compact: Bool
    let onTapDay: () -> Void

    private let calendar = Calendar.current

    private var cellHeight: CGFloat { compact ? 82 : 118 }
    private var dayFont: Font { .system(size: compact ? 20 : 24, weight: .bold, design: .rounded) }
    private var dayCircleSize: CGFloat { compact ? 34 : 38 }
    private var shiftFont: Font { compact ? .system(size: 9, weight: .bold) : .system(size: 10, weight: .bold) }
    private var badgeFont: Font { compact ? .system(size: 7, weight: .black) : .system(size: 8, weight: .black) }
    private var emblemFont: Font { compact ? .system(size: 8) : .system(size: 10) }

    var body: some View {
        Button(action: onTapDay) {
            VStack(spacing: 3) {
                // Day number
                Text(calendar.component(.day, from: date).description)
                    .font(dayFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .dynamicTypeSize(.xSmall ... .accessibility1)
                    .foregroundStyle(isToday ? .white : .primary)
                    .frame(width: dayCircleSize, height: dayCircleSize)
                    .background(isToday ? Color.accent : Color.clear, in: Circle())

                // Shift chips
                ForEach(shifts.prefix(compact ? 2 : 4)) { shift in
                    HStack(spacing: 2) {
                        Text(shift.site?.initials ?? "?")
                            .font(shiftFont)
                            .lineLimit(1)
                        if shift.isOnCall {
                            Text("OC")
                                .font(badgeFont)
                        }
                        if shift.hasStreakBonus {
                            Text("🎯")
                                .font(emblemFont)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                    .background((shift.isOnCall ? Color.blue : Color.accent).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(shift.isOnCall ? Color.blue : Color.accent)
                }

                if shifts.count > (compact ? 2 : 4) {
                    Text("+\(shifts.count - (compact ? 2 : 4))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .frame(height: cellHeight, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(shifts.isEmpty ? Color.clear : Color.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Week Day Row

struct WeekDayRow: View {
    let date: Date
    let shifts: [Shift]
    let onTap: () -> Void

    private var dayLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayLabel)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ForEach(shifts) { shift in
                Button(action: onTap) {
                    CalendarDayShiftRow(shift: shift)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        Divider()
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

// MARK: - Calendar Summary Card

struct CalendarSummaryCard: View {
    let title: String
    let shifts: [Shift]

    var totalPay: Decimal { shifts.reduce(0) { $0 + $1.totalPay } }
    var totalBase: Decimal { shifts.reduce(0) { $0 + $1.basePay } }
    var totalBonuses: Decimal { totalPay - totalBase }
    var onCallCount: Int { shifts.filter { $0.isOnCall }.count }
    var streakCount: Int { shifts.filter { $0.hasStreakBonus }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
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