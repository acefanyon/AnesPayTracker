#if DEBUG
import Foundation
import SwiftData

// MARK: - UI Test Support

/// Test-only launch mode for the automated UI tests (`AnesPayTrackerUITests`).
///
/// Compiled into Debug builds only, so TestFlight and App Store builds can
/// never use it. It switches on only when the app is launched with
/// `-UITestScenario`, which only the UI tests pass. It then uses its own
/// store in the app's temporary folder, filled with made-up data, and never
/// opens or touches the real store or its backups.
@MainActor
enum UITestSupport {
    static let scenarioArgument = "-UITestScenario"
    /// Reuse the test store from the previous launch (for "still there after
    /// relaunch" checks) instead of starting fresh.
    static let keepStoreArgument = "-UITestKeepStore"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(scenarioArgument)
    }

    private static var keepsStore: Bool {
        ProcessInfo.processInfo.arguments.contains(keepStoreArgument)
    }

    private static var storeDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("UITestStore", isDirectory: true)
    }

    static func makeContainer(schema: Schema) throws -> ModelContainer {
        let fileManager = FileManager.default
        let fresh = !keepsStore
        if fresh {
            try? fileManager.removeItem(at: storeDirectory)
            resetSettings()
        }
        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let config = ModelConfiguration(
            schema: schema,
            url: storeDirectory.appendingPathComponent("uitest.store"),
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        if fresh {
            seedInvoiceScenario(into: container.mainContext)
        }
        return container
    }

    /// Settings the tests depend on, set to known values. Your details on
    /// invoices are filled in so tests don't have to type them.
    private static func resetSettings() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: InvoiceSettingsKey.tracksPayments)
        defaults.set("Sample Physician, MD", forKey: InvoiceSenderKey.name)
        defaults.set("1 Example St\n\nAnytown, ST 00000", forKey: InvoiceSenderKey.address)
        defaults.set("", forKey: InvoiceSenderKey.phone)
        defaults.set("", forKey: InvoiceSenderKey.email)
    }

    // MARK: Scenario

    /// Dates are relative to today so the scenario never goes stale:
    /// - "Case Group" pays $400/hr for case time only (5 h minimum) with a
    ///   $200 Recovery fee, and is invoiced every 2 weeks. Its last two-week
    ///   period ended 3 days ago and has two shifts not yet invoiced
    ///   ($3,206.67 and $2,000.00). An older shift is on an existing invoice
    ///   whose due date has passed.
    /// - "Day Rate Partners" pays $1,800/day and has no invoice reminders.
    /// All names, places and amounts are made up.
    private static func seedInvoiceScenario(into context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int, from base: Date) -> Date {
            calendar.date(byAdding: .day, value: offset, to: base) ?? base
        }
        func time(_ date: Date, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        let periodEnd = day(-3, from: today)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let lastMonthEnd = day(-1, from: monthStart)

        let caseGroup = Employer(
            name: "Case Group",
            payCadence: .monthly,
            payPeriodEndAnchorDate: lastMonthEnd,
            paycheckAnchorDate: day(15, from: lastMonthEnd)
        )
        caseGroup.paysCaseTimeOnly = true
        caseGroup.dailyMinimumHours = 5
        caseGroup.invoiceCode = "CG"
        caseGroup.billingName = "Case Group PLLC"
        caseGroup.billingAddress = "PO Box 1\n\nAnytown, ST 00000"
        caseGroup.invoiceCadence = .everyTwoWeeks
        caseGroup.invoicePeriodEndAnchor = periodEnd
        caseGroup.invoiceRemindersStartDate = day(-27, from: periodEnd)

        let caseCenter = Site(name: "Case Center", employer: caseGroup, payUnit: .perHour, baseAmount: 400)
        caseGroup.sites = [caseCenter]
        let recovery = CustomBonusType(employer: caseGroup, name: "Recovery", payUnit: .perDay, defaultAmount: 200, proratesPartialDay: false)
        caseGroup.customBonusTypes = [recovery]

        func caseShift(on date: Date, _ spans: [(Int, Int, Int, Int)], recoveryFee: Bool) -> Shift {
            let cases = spans.map { ShiftCase(startAt: time(date, $0.0, $0.1), endAt: time(date, $0.2, $0.3)) }
            return Shift(
                site: caseCenter,
                date: date,
                payUnit: .perHour,
                dayFraction: nil,
                hoursWorked: Double(CaseTimeCalculator.totalMinutes(cases)) / 60,
                cases: cases,
                guaranteedMinimumHours: 5,
                baseAmount: 400,
                customBonuses: recoveryFee
                    ? [AppliedCustomBonus(name: "Recovery", payUnit: .perDay, amount: 200, quantity: 1)]
                    : nil
            )
        }
        // 7 h 31 m = $3,006.67, plus Recovery $200.00.
        let longDay = caseShift(on: day(-5, from: periodEnd), [(7, 30, 9, 14), (9, 40, 11, 5), (11, 30, 13, 52), (14, 10, 16, 10)], recoveryFee: true)
        // 30 m raised to the 5 h minimum = $2,000.00.
        let lightDay = caseShift(on: day(-2, from: periodEnd), [(8, 0, 8, 30)], recoveryFee: false)
        // Previous period, already invoiced.
        let invoicedDay = caseShift(on: day(-20, from: periodEnd), [(7, 0, 12, 0)], recoveryFee: false)

        let dayRate = Employer(name: "Day Rate Partners", payCadence: .biweekly)
        let dayCenter = Site(name: "Day Center", employer: dayRate, payUnit: .perDay, baseAmount: 1800)
        dayRate.sites = [dayCenter]
        let dayShift = Shift(site: dayCenter, date: day(-4, from: periodEnd), payUnit: .perDay, dayFraction: .full, baseAmount: 1800)

        for object in [caseGroup, dayRate] { context.insert(object) }
        for site in [caseCenter, dayCenter] { context.insert(site) }
        context.insert(recovery)
        for shift in [longDay, lightDay, invoicedDay, dayShift] { context.insert(shift) }

        let issuedOn = day(-12, from: periodEnd)
        let snapshot = InvoiceSnapshot(
            senderName: "Sample Physician, MD",
            senderAddress: "1 Example St\n\nAnytown, ST 00000",
            senderPhone: "",
            senderEmail: "",
            billToName: "Case Group PLLC",
            billToAddress: "PO Box 1\n\nAnytown, ST 00000",
            days: [InvoiceBuilder.day(for: invoicedDay)]
        )
        if let invoice = try? InvoiceBuilder.makeInvoice(
            number: InvoiceMath.invoiceNumber(employerCode: "CG", date: issuedOn, calendar: calendar),
            employer: caseGroup,
            periodStart: day(-27, from: periodEnd),
            periodEnd: day(-14, from: periodEnd),
            issuedOn: issuedOn,
            dueOn: day(-1, from: periodEnd),
            notes: nil,
            snapshot: snapshot
        ) {
            context.insert(invoice)
        }
        try? context.save()
    }
}
#endif
