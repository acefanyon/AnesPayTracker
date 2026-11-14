import SwiftUI
import SwiftData

// MARK: - Case Tracker

/// One-tap start/stop capture for case-time sites. Besides Add/Edit Shift,
/// this is the only place that writes shifts.
enum CaseTracker {

    /// A running case that has been going this long was probably never stopped.
    static let forgottenAfterHours: Double = 16

    static func todaysShift(at site: Site, now: Date = Date(), calendar: Calendar = .current) -> Shift? {
        site.shifts
            .filter { $0.isCaseTracked && calendar.isDate($0.date, inSameDayAs: now) }
            .min { $0.createdAt < $1.createdAt }
    }

    /// The shift with a case still running, on any day (a case can run past midnight).
    static func runningShift(in sites: [Site]) -> Shift? {
        sites
            .flatMap(\.shifts)
            .filter { $0.isCaseTracked && $0.runningCase != nil }
            .max { $0.date < $1.date }
    }

    /// Starts a case now, creating today's shift at the site if there isn't one.
    static func startCase(at site: Site, in context: ModelContext, now: Date = Date()) throws {
        let shift: Shift
        var isNewShift = false
        if let existing = todaysShift(at: site, now: now) {
            guard existing.runningCase == nil else { return }
            shift = existing
        } else {
            shift = Shift(
                site: site,
                date: now,
                payUnit: .perHour,
                dayFraction: nil,
                hoursWorked: 0,
                cases: [],
                guaranteedMinimumHours: site.employer?.dailyMinimumHours,
                baseAmount: site.baseAmount
            )
            context.insert(shift)
            isNewShift = true
        }

        // A case can't start before the previous one ended.
        let tappedAt = CaseTimeCalculator.truncatedToMinute(now)
        let startAt = max(tappedAt, shift.sortedCases.last?.endAt ?? tappedAt)
        var cases = shift.cases ?? []
        cases.append(ShiftCase(startAt: startAt, endAt: startAt, isRunning: true))
        apply(cases, to: shift)

        if isNewShift, let employer = site.employer {
            StreakEngine.recomputeStreaks(for: employer)
        }
        syncCalendar(for: shift, isNew: isNewShift)
        try context.save()
    }

    static func stopRunningCase(on shift: Shift, in context: ModelContext, now: Date = Date()) throws {
        guard var cases = shift.cases, let index = cases.firstIndex(where: \.isRunning) else { return }
        let stop = CaseTimeCalculator.truncatedToMinute(now)
        cases[index].endAt = max(stop, cases[index].startAt)
        cases[index].isRunning = false
        apply(cases, to: shift)
        syncCalendar(for: shift, isNew: false)
        try context.save()
    }

    private static func apply(_ cases: [ShiftCase], to shift: Shift) {
        let oldHours = shift.hoursWorked ?? 0
        let ordered = CaseTimeCalculator.sorted(cases)
        let newHours = Double(CaseTimeCalculator.totalMinutes(ordered)) / 60
        shift.cases = ordered
        shift.hoursWorked = newHours
        // Per-hour bonuses that followed the shift's hours keep following them.
        if var bonuses = shift.customBonuses {
            for index in bonuses.indices where bonuses[index].payUnit == .perHour && bonuses[index].quantity == oldHours {
                bonuses[index].quantity = newHours
            }
            shift.customBonuses = bonuses
        }
    }

    private static func syncCalendar(for shift: Shift, isNew: Bool) {
        let calendarSync = CalendarSyncManager.shared
        guard calendarSync.isOptedIn else { return }
        if isNew {
            shift.calendarEventID = calendarSync.addEvent(for: shift)
        } else {
            calendarSync.updateEvent(for: shift)
        }
    }
}

// MARK: - Case Tracker Card

struct CaseTrackerCard: View {
    /// The case-time sites, never empty.
    let sites: [Site]
    let onOpenShift: (Shift) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selectedSiteID: UUID?
    @State private var errorMessage: String?

    private var runningShift: Shift? { CaseTracker.runningShift(in: sites) }

    /// The running shift's site, else the picked site, else the one with a
    /// shift today, else the most recently used.
    private var site: Site? {
        if let runningSite = runningShift?.site { return runningSite }
        if let picked = sites.first(where: { $0.id == selectedSiteID }) { return picked }
        if let today = sites.first(where: { CaseTracker.todaysShift(at: $0) != nil }) { return today }
        return sites.max {
            ($0.shifts.map(\.date).max() ?? .distantPast) < ($1.shifts.map(\.date).max() ?? .distantPast)
        }
    }

    private var activeShift: Shift? {
        if let runningShift { return runningShift }
        guard let site else { return nil }
        return CaseTracker.todaysShift(at: site)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Case tracker")
                    .font(.footnote.bold())
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                sitePicker
            }

            if let shift = runningShift, let running = shift.runningCase {
                runningView(shift: shift, running: running)
            } else if let site {
                Button {
                    perform { try CaseTracker.startCase(at: site, in: modelContext) }
                } label: {
                    Label("Start Case", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }

            if let shift = activeShift {
                Button {
                    onOpenShift(shift)
                } label: {
                    HStack {
                        Text(summary(of: shift))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(shift.totalPay.formatted(.currency(code: "USD")))
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.accent)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the shift to review or correct case times")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var sitePicker: some View {
        if sites.count > 1 && runningShift == nil {
            Menu {
                ForEach(sites) { option in
                    Button(siteLabel(option)) { selectedSiteID = option.id }
                }
            } label: {
                Label(site?.name ?? "Choose site", systemImage: "chevron.up.chevron.down")
                    .font(.subheadline)
            }
        } else if let site {
            Text(site.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func runningView(shift: Shift, running: ShiftCase) -> some View {
        let number = (shift.sortedCases.firstIndex { $0.id == running.id } ?? 0) + 1
        let hoursRunning = Date().timeIntervalSince(running.startAt) / 3600
        let looksForgotten = hoursRunning > CaseTracker.forgottenAfterHours

        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Case \(number) running")
                    .font(.title3.bold())
                Text("Started \(startLabel(running.startAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !looksForgotten {
                Text(running.startAt, style: .timer)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.green)
            }
        }

        if looksForgotten {
            Text("This case has been running a long time. If it was never stopped, enter its real stop time instead of stopping it now.")
                .font(.footnote)
                .foregroundStyle(.orange)
            Button {
                onOpenShift(shift)
            } label: {
                Label("Enter Stop Time", systemImage: "pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                perform { try CaseTracker.stopRunningCase(on: shift, in: modelContext) }
            } label: {
                Label("Stop Case", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = "Your tap wasn't saved. Please try again. (\(error.localizedDescription))"
        }
    }

    private func summary(of shift: Shift) -> String {
        let count = shift.cases?.count ?? 0
        let day = Calendar.current.isDateInToday(shift.date)
            ? "Today"
            : shift.date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day): \(count) case\(count == 1 ? "" : "s") · \(CaseTimeCalculator.durationLabel(minutes: shift.caseMinutes))"
    }

    private func startLabel(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(.dateTime.hour().minute())
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func siteLabel(_ site: Site) -> String {
        if let employerName = site.employer?.name { return "\(site.name) · \(employerName)" }
        return site.name
    }
}
