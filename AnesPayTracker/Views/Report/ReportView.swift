import SwiftUI
import SwiftData
import QuickLook

// MARK: - Report View

struct ReportView: View {
    @Query private var employers: [Employer]
    @Query(sort: \Shift.date) private var allShifts: [Shift]
    @Query(sort: \Site.name) private var allSites: [Site]

    @State private var reportMode: ReportMode = .earnings
    @State private var dateRange: ReportDateRange = .thisMonth
    @State private var bonusPayoutDateRange: BonusPayoutDateRange = .thisQuarter
    @State private var paycheckDateRange: BonusPayoutDateRange = .thisMonth
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var selectedEmployer: Employer?
    @State private var selectedSite: Site?
    @State private var pdfPreviewItem: PDFPreviewItem?
    @State private var expandedNote: Shift?

    var currentDateBounds: (Date, Date) {
        let cal = Calendar.current
        let today = Date()
        switch dateRange {
        case .thisMonth:
            return monthBounds(containing: today)
        case .lastMonth:
            let lastMonth = cal.date(byAdding: .month, value: -1, to: today) ?? today
            return monthBounds(containing: lastMonth)
        case .thisQuarter:
            return quarterBounds(containing: today)
        case .lastQuarter:
            let lastQuarter = cal.date(byAdding: .month, value: -3, to: today) ?? today
            return quarterBounds(containing: lastQuarter)
        case .ytd:
            let comps = cal.dateComponents([.year], from: today)
            let start = cal.date(from: comps) ?? today
            return (start, today)
        case .custom:
            return (cal.startOfDay(for: customStart), cal.endOfDay(for: customEnd))
        case .thisPayPeriod:
            if let emp = selectedEmployer ?? employers.first {
                return StreakEngine.payPeriodBounds(containing: today, employer: emp)
            }
            return (today, today)
        case .lastPayPeriod:
            if let emp = selectedEmployer ?? employers.first {
                let (currentStart, _) = StreakEngine.payPeriodBounds(containing: today, employer: emp)
                let dayBefore = cal.date(byAdding: .day, value: -1, to: currentStart) ?? today
                return StreakEngine.payPeriodBounds(containing: dayBefore, employer: emp)
            }
            return (today, today)
        }
    }

    var currentBonusPayoutBounds: (Date, Date) {
        let cal = Calendar.current
        let today = Date()
        switch bonusPayoutDateRange {
        case .thisMonth:
            return monthBounds(containing: today)
        case .lastMonth:
            let lastMonth = cal.date(byAdding: .month, value: -1, to: today) ?? today
            return monthBounds(containing: lastMonth)
        case .thisQuarter:
            return quarterBounds(containing: today)
        case .lastQuarter:
            let lastQuarter = cal.date(byAdding: .month, value: -3, to: today) ?? today
            return quarterBounds(containing: lastQuarter)
        case .custom:
            return (cal.startOfDay(for: customStart), cal.endOfDay(for: customEnd))
        }
    }

    var currentPaycheckBounds: (Date, Date) {
        let cal = Calendar.current
        let today = Date()
        switch paycheckDateRange {
        case .thisMonth:
            return monthBounds(containing: today)
        case .lastMonth:
            let lastMonth = cal.date(byAdding: .month, value: -1, to: today) ?? today
            return monthBounds(containing: lastMonth)
        case .thisQuarter:
            return quarterBounds(containing: today)
        case .lastQuarter:
            let lastQuarter = cal.date(byAdding: .month, value: -3, to: today) ?? today
            return quarterBounds(containing: lastQuarter)
        case .custom:
            return (cal.startOfDay(for: customStart), cal.endOfDay(for: customEnd))
        }
    }

    var filteredShifts: [Shift] {
        let (start, end) = currentDateBounds
        return allShifts.filter { shift in
            guard shift.date >= start && shift.date <= end else { return false }
            return matchesEmployerAndSite(shift)
        }
    }

    var bonusPayoutRows: [BonusPayoutRow] {
        let (start, end) = currentBonusPayoutBounds
        return allShifts
            .filter(matchesEmployerAndSite)
            .flatMap { BonusPayoutRow.rows(for: $0) }
            .filter { $0.payoutDate >= start && $0.payoutDate <= end }
            .sorted { lhs, rhs in
                if lhs.payoutDate != rhs.payoutDate { return lhs.payoutDate < rhs.payoutDate }
                return lhs.serviceDate < rhs.serviceDate
            }
    }

    var paycheckRows: [PaycheckAggregationRow] {
        let (start, end) = currentPaycheckBounds
        return allShifts
            .filter(matchesEmployerAndSite)
            .filter { $0.site?.employer?.paycheckAnchorDate != nil && $0.site?.employer?.payPeriodEndAnchorDate != nil }
            .flatMap { StreakEngine.paycheckAggregationRows(for: $0) }
            .filter { $0.paycheckDate >= start && $0.paycheckDate <= end }
            .sorted { lhs, rhs in
                if lhs.paycheckDate != rhs.paycheckDate { return lhs.paycheckDate < rhs.paycheckDate }
                if lhs.serviceDate != rhs.serviceDate { return lhs.serviceDate < rhs.serviceDate }
                return lhs.componentName < rhs.componentName
            }
    }

    var totalBase: Decimal { filteredShifts.reduce(0) { $0 + $1.basePay } }
    var totalBonus: Decimal { filteredShifts.reduce(0) { $0 + $1.bonusPay } }
    var totalStreak: Decimal { filteredShifts.reduce(0) { $0 + ($1.streakBonusAmount ?? 0) } }
    var grandTotal: Decimal { filteredShifts.reduce(0) { $0 + $1.totalPay } }
    var totalBonusPayout: Decimal { bonusPayoutRows.reduce(0) { $0 + $1.amount } }
    var totalPaycheckEstimate: Decimal { paycheckRows.reduce(0) { $0 + $1.amount } }

    var employersMissingPaycheckAnchor: [Employer] {
        let relevant = selectedEmployer.map { [$0] } ?? employers
        return relevant.filter { $0.paycheckAnchorDate == nil || $0.payPeriodEndAnchorDate == nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ReportFiltersCard(
                        reportMode: $reportMode,
                        dateRange: $dateRange,
                        bonusPayoutDateRange: $bonusPayoutDateRange,
                        paycheckDateRange: $paycheckDateRange,
                        customStart: $customStart,
                        customEnd: $customEnd,
                        selectedEmployer: $selectedEmployer,
                        selectedSite: $selectedSite,
                        employers: employers,
                        sites: allSites
                    )

                    if reportMode == .earnings {
                        earningsReportBody
                    } else if reportMode == .bonusPayouts {
                        bonusPayoutReportBody
                    } else {
                        paycheckEstimatorBody
                    }
                }
                .padding(16)
                .padding(.bottom, 180)
            }
            .navigationTitle("Report")
            .sheet(item: $pdfPreviewItem) { item in
                PDFPreviewSheet(url: item.url)
            }
        }
    }

    @ViewBuilder private var earningsReportBody: some View {
        if !filteredShifts.isEmpty {
            ReportRangeContextCard(
                title: dateRange.rawValue,
                subtitle: "Shift service dates included in this earnings report",
                startDate: currentDateBounds.0,
                endDate: currentDateBounds.1
            )
            ReportSummaryCard(
                shiftCount: filteredShifts.count,
                totalBase: totalBase,
                totalBonus: totalBonus,
                totalStreak: totalStreak,
                grandTotal: grandTotal
            )
            EarningsBreakdownCard(shifts: filteredShifts)
            ReportTableCard(shifts: filteredShifts, expandedNote: $expandedNote)
            exportButton
        } else {
            EmptyStateView(icon: "doc.text", title: "No shifts in range", message: "Try a different date range or filter.")
                .padding(.top, 40)
        }
    }

    @ViewBuilder private var bonusPayoutReportBody: some View {
        if !bonusPayoutRows.isEmpty {
            ReportRangeContextCard(
                title: bonusPayoutDateRange.rawValue,
                subtitle: "Bonus payout dates included here. Quarterly streak bonuses appear in the quarter they are paid, not necessarily the quarter they were worked.",
                startDate: currentBonusPayoutBounds.0,
                endDate: currentBonusPayoutBounds.1
            )
            BonusPayoutSummaryCard(rowCount: bonusPayoutRows.count, totalBonusPayout: totalBonusPayout)
            BonusPayoutBreakdownCard(rows: bonusPayoutRows)
            BonusPayoutTableCard(rows: bonusPayoutRows)
            exportButton
        } else {
            ReportRangeContextCard(
                title: bonusPayoutDateRange.rawValue,
                subtitle: "No bonus payouts are scheduled for this payout-date range. Streak bonuses are quarterly; try This Quarter, Last Quarter, or Custom if you are checking streak payouts.",
                startDate: currentBonusPayoutBounds.0,
                endDate: currentBonusPayoutBounds.1
            )
            EmptyStateView(icon: "calendar.badge.clock", title: "No bonus payouts in range", message: "Try this quarter, last quarter, or a custom payout period. Bonuses labeled Paid with shift are immediate shift-date bonuses, not base shift earnings.")
                .padding(.top, 40)
        }
    }

    @ViewBuilder private var paycheckEstimatorBody: some View {
        ReportRangeContextCard(
            title: paycheckDateRange.rawValue,
            subtitle: "Estimated paycheck dates in this range. Rows are grouped by the paycheck where the aggregate should appear, using each employer's known pay-period end date and actual paycheck date anchor.",
            startDate: currentPaycheckBounds.0,
            endDate: currentPaycheckBounds.1
        )

        if !employersMissingPaycheckAnchor.isEmpty {
            PaycheckAnchorWarningCard(employers: employersMissingPaycheckAnchor)
        }

        if !paycheckRows.isEmpty {
            PaycheckEstimatorSummaryCard(rowCount: paycheckRows.count, paycheckCount: paycheckGroups.count, totalEstimate: totalPaycheckEstimate)
            PaycheckEstimatorBreakdownCard(rows: paycheckRows)
            PaycheckEstimatorTableCard(groups: paycheckGroups)
            exportButton
        } else {
            EmptyStateView(icon: "banknote", title: "No paycheck estimates in range", message: employersMissingPaycheckAnchor.isEmpty ? "Try another paycheck date range or employer/site filter." : "Add pay-period end and paycheck date anchors in Employer setup, then return here to estimate checks.")
                .padding(.top, 40)
        }
    }

    private var paycheckGroups: [PaycheckGroup] {
        let grouped = Dictionary(grouping: paycheckRows, by: { $0.paycheckDate })
        return grouped.map { date, rows in
            PaycheckGroup(paycheckDate: date, rows: rows.sorted { lhs, rhs in
                if lhs.serviceDate != rhs.serviceDate { return lhs.serviceDate < rhs.serviceDate }
                return lhs.componentName < rhs.componentName
            })
        }
        .sorted { $0.paycheckDate < $1.paycheckDate }
    }

    private var exportButton: some View {
        Button {
            generateAndSharePDF()
        } label: {
            Label("Export PDF", systemImage: "square.and.arrow.up")
                .font(.body.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func generateAndSharePDF() {
        let generator = PDFReportGenerator()
        let generatedURL: URL?
        if reportMode == .earnings {
            let (start, end) = currentDateBounds
            generatedURL = generator.generate(
                shifts: filteredShifts,
                startDate: start,
                endDate: end,
                employerFilter: selectedEmployer?.name,
                siteFilter: selectedSite?.name
            )
        } else if reportMode == .bonusPayouts {
            let (start, end) = currentBonusPayoutBounds
            generatedURL = generator.generateBonusPayoutReport(
                rows: bonusPayoutRows,
                startDate: start,
                endDate: end,
                employerFilter: selectedEmployer?.name,
                siteFilter: selectedSite?.name
            )
        } else {
            let (start, end) = currentPaycheckBounds
            generatedURL = generator.generatePaycheckEstimatorReport(
                rows: paycheckRows,
                startDate: start,
                endDate: end,
                employerFilter: selectedEmployer?.name,
                siteFilter: selectedSite?.name
            )
        }
        if let generatedURL {
            pdfPreviewItem = PDFPreviewItem(url: generatedURL)
        }
    }

    private func matchesEmployerAndSite(_ shift: Shift) -> Bool {
        if let emp = selectedEmployer, shift.site?.employer?.id != emp.id { return false }
        if let site = selectedSite, shift.site?.id != site.id { return false }
        return true
    }

    private func monthBounds(containing date: Date) -> (Date, Date) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: date)
        let start = cal.date(from: comps) ?? date
        comps.month = (comps.month ?? 1) + 1
        let nextStart = cal.date(from: comps) ?? date
        return (start, cal.date(byAdding: .second, value: -1, to: nextStart) ?? date)
    }

    private func quarterBounds(containing date: Date) -> (Date, Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let month = comps.month ?? 1
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        var startComps = DateComponents()
        startComps.year = comps.year
        startComps.month = quarterStartMonth
        startComps.day = 1
        let start = cal.date(from: startComps) ?? date
        let nextQuarterStart = cal.date(byAdding: .month, value: 3, to: start) ?? date
        let end = cal.date(byAdding: .second, value: -1, to: nextQuarterStart) ?? date
        return (start, end)
    }
}

// MARK: - Report Modes / Ranges

enum ReportMode: String, CaseIterable {
    case earnings = "Earnings"
    case bonusPayouts = "Bonus Payouts"
    case paycheckEstimator = "Paycheck Estimator"
}

enum ReportDateRange: String, CaseIterable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisQuarter = "This Quarter"
    case lastQuarter = "Last Quarter"
    case ytd = "Year to Date"
    case thisPayPeriod = "This Pay Period"
    case lastPayPeriod = "Last Pay Period"
    case custom = "Custom"
}

enum BonusPayoutDateRange: String, CaseIterable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisQuarter = "This Quarter"
    case lastQuarter = "Last Quarter"
    case custom = "Custom"
}

// MARK: - Bonus Payout Rows

struct BonusPayoutRow: Identifiable {
    let id = UUID()
    let shiftID: UUID
    let serviceDate: Date
    let payoutDate: Date
    let employerName: String
    let siteName: String
    let bonusName: String
    let amount: Decimal
    let schedule: BonusPayoutSchedule

    static func rows(for shift: Shift) -> [BonusPayoutRow] {
        var rows: [BonusPayoutRow] = []
        let employerName = shift.site?.employer?.name ?? "—"
        let siteName = shift.site?.name ?? "—"

        for bonus in shift.customBonuses ?? [] where bonus.totalAmount > 0 {
            rows.append(BonusPayoutRow(
                shiftID: shift.id,
                serviceDate: shift.date,
                payoutDate: bonus.payoutSchedule.payoutDate(for: shift.date),
                employerName: employerName,
                siteName: siteName,
                bonusName: bonus.name,
                amount: bonus.totalAmount,
                schedule: bonus.payoutSchedule
            ))
        }

        if shift.hasOnCallBonus {
            rows.append(BonusPayoutRow(
                shiftID: shift.id,
                serviceDate: shift.date,
                payoutDate: BonusPayoutSchedule.serviceDate.payoutDate(for: shift.date),
                employerName: employerName,
                siteName: siteName,
                bonusName: "On-Call Bonus",
                amount: shift.onCallPay,
                schedule: .serviceDate
            ))
        }

        if let splash = shift.splashAmount, splash > 0 {
            rows.append(BonusPayoutRow(shiftID: shift.id, serviceDate: shift.date, payoutDate: BonusPayoutSchedule.serviceDate.payoutDate(for: shift.date), employerName: employerName, siteName: siteName, bonusName: "Splash Bonus", amount: splash, schedule: .serviceDate))
        }
        if let bonusSplash = shift.bonusSplashAmount, bonusSplash > 0 {
            rows.append(BonusPayoutRow(shiftID: shift.id, serviceDate: shift.date, payoutDate: BonusPayoutSchedule.serviceDate.payoutDate(for: shift.date), employerName: employerName, siteName: siteName, bonusName: "Bonus Splash", amount: bonusSplash, schedule: .serviceDate))
        }
        if let streak = shift.streakBonusAmount, streak > 0 {
            let payoutSchedule = shift.streakPayoutSchedule ?? .nextQuarterlyPayout
            rows.append(BonusPayoutRow(
                shiftID: shift.id,
                serviceDate: shift.date,
                payoutDate: payoutSchedule.payoutDate(for: shift.date),
                employerName: employerName,
                siteName: siteName,
                bonusName: "Streak Bonus",
                amount: streak,
                schedule: payoutSchedule
            ))
        }
        return rows
    }
}

// MARK: - Filters Card

struct ReportFiltersCard: View {
    @Binding var reportMode: ReportMode
    @Binding var dateRange: ReportDateRange
    @Binding var bonusPayoutDateRange: BonusPayoutDateRange
    @Binding var paycheckDateRange: BonusPayoutDateRange
    @Binding var customStart: Date
    @Binding var customEnd: Date
    @Binding var selectedEmployer: Employer?
    @Binding var selectedSite: Site?
    let employers: [Employer]
    let sites: [Site]

    var filteredSites: [Site] {
        if let emp = selectedEmployer {
            return sites.filter { $0.employer?.id == emp.id }
        }
        return sites
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filters")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Picker("Report type", selection: $reportMode) {
                ForEach(ReportMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                if reportMode == .earnings {
                    ForEach(ReportDateRange.allCases, id: \.self) { range in
                        FilterChip(label: range.rawValue, isSelected: dateRange == range) { dateRange = range }
                    }
                } else if reportMode == .bonusPayouts {
                    ForEach(BonusPayoutDateRange.allCases, id: \.self) { range in
                        FilterChip(label: range.rawValue, isSelected: bonusPayoutDateRange == range) { bonusPayoutDateRange = range }
                    }
                } else {
                    ForEach(BonusPayoutDateRange.allCases, id: \.self) { range in
                        FilterChip(label: range.rawValue, isSelected: paycheckDateRange == range) { paycheckDateRange = range }
                    }
                }
            }

            if (reportMode == .earnings && dateRange == .custom) || (reportMode == .bonusPayouts && bonusPayoutDateRange == .custom) || (reportMode == .paycheckEstimator && paycheckDateRange == .custom) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $customStart, displayedComponents: .date).labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $customEnd, displayedComponents: .date).labelsHidden()
                    }
                }
            }

            if employers.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Employer").font(.caption).foregroundStyle(.secondary)
                    Picker("Employer", selection: $selectedEmployer) {
                        Text("All").tag(Optional<Employer>.none)
                        ForEach(employers) { emp in
                            Text(emp.name).tag(Optional(emp))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if filteredSites.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Site / Location").font(.caption).foregroundStyle(.secondary)
                    Picker("Site", selection: $selectedSite) {
                        Text("All").tag(Optional<Site>.none)
                        ForEach(filteredSites) { site in
                            Text(site.name).tag(Optional(site))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Range Context

struct ReportRangeContextCard: View {
    let title: String
    let subtitle: String
    let startDate: Date
    let endDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text("\(startDate.formatted(.dateTime.month(.abbreviated).day().year())) – \(endDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                .font(.subheadline.bold())
                .foregroundStyle(Color.accent)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Summary Cards

struct ReportSummaryCard: View {
    let shiftCount: Int
    let totalBase: Decimal
    let totalBonus: Decimal
    let totalStreak: Decimal
    let grandTotal: Decimal

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(shiftCount) shift\(shiftCount == 1 ? "" : "s")")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(grandTotal.formatted(.currency(code: "USD")))
                    .font(.title2.bold())
                    .foregroundStyle(Color.accent)
            }
            Divider()
            HStack(spacing: 0) {
                SummaryCol(label: "Base", amount: totalBase)
                if totalBonus > 0 { SummaryCol(label: "Bonuses", amount: totalBonus) }
                if totalStreak > 0 { SummaryCol(label: "🎯 Streak", amount: totalStreak) }
            }
        }
        .padding(16)
        .background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct EarningsBreakdownCard: View {
    let shifts: [Shift]

    private var breakdown: [(String, Decimal)] {
        var totals: [String: Decimal] = [:]

        func add(_ label: String, _ amount: Decimal) {
            guard amount > 0 else { return }
            totals[label, default: 0] += amount
        }

        add("Base Pay", shifts.reduce(0) { $0 + $1.basePay })

        for shift in shifts {
            add("On-Call Bonus", shift.onCallPay)
            add("Splash Bonus", shift.splashAmount ?? 0)
            add("Bonus Splash", shift.bonusSplashAmount ?? 0)
            add("Streak Bonus", shift.streakBonusAmount ?? 0)
            for bonus in shift.customBonuses ?? [] {
                add(bonus.name, bonus.totalAmount)
            }
        }

        return totals.map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.0 == "Base Pay" { return true }
                if rhs.0 == "Base Pay" { return false }
                if lhs.0 == "Streak Bonus" { return true }
                if rhs.0 == "Streak Bonus" { return false }
                return lhs.0 < rhs.0
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earnings Breakdown")
                .font(.headline)
            Text("Shows base pay and each bonus type earned during this period. Quarterly streak bonuses and other scheduled bonuses are paid according to each employer's aggregation and payout rules — check the Paycheck Estimator for estimated paycheck dates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(breakdown, id: \.0) { label, amount in
                HStack {
                    Text(label).font(.footnote)
                    Spacer()
                    Text(amount.formatted(.currency(code: "USD"))).font(.footnote.bold())
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BonusPayoutSummaryCard: View {
    let rowCount: Int
    let totalBonusPayout: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bonus Payout Report")
                .font(.headline)
            Text("Bonuses expected to be paid in the selected payout period. This is separate from shift earnings by service date.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(rowCount) payout item\(rowCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totalBonusPayout.formatted(.currency(code: "USD")))
                    .font(.title2.bold())
                    .foregroundStyle(Color.accent)
            }
        }
        .padding(16)
        .background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BonusPayoutBreakdownCard: View {
    let rows: [BonusPayoutRow]

    private var bonusTypeBreakdown: [(String, Decimal)] {
        totals(groupedBy: { "\($0.bonusName) · \($0.schedule.shortLabel)" })
    }

    private var payoutScheduleBreakdown: [(String, Decimal)] {
        totals(groupedBy: { $0.schedule.shortLabel })
    }

    private var employerBreakdown: [(String, Decimal)] {
        totals(groupedBy: { $0.employerName })
    }

    private var siteBreakdown: [(String, Decimal)] {
        totals(groupedBy: { "\($0.employerName) · \($0.siteName)" })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Breakdown")
                .font(.headline)
            breakdownSection(title: "By Bonus Type", values: bonusTypeBreakdown)
            breakdownSection(title: "By Payout Schedule", values: payoutScheduleBreakdown)
            breakdownSection(title: "By Employer", values: employerBreakdown)
            breakdownSection(title: "By Site / Location", values: siteBreakdown)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func breakdownSection(title: String, values: [(String, Decimal)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(values, id: \.0) { label, amount in
                HStack {
                    Text(label).font(.footnote)
                    Spacer()
                    Text(amount.formatted(.currency(code: "USD"))).font(.footnote.bold())
                }
            }
        }
    }

    private func totals(groupedBy key: (BonusPayoutRow) -> String) -> [(String, Decimal)] {
        let grouped = Dictionary(grouping: rows, by: key)
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.0 < $1.0 }
    }
}

struct SummaryCol: View {
    let label: String
    let amount: Decimal

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(amount.formatted(.currency(code: "USD")))
                .font(.footnote.bold())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Earnings Report Table

struct ReportTableCard: View {
    let shifts: [Shift]
    @Binding var expandedNote: Shift?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReportTableHeader()
            Divider()
            ForEach(shifts) { shift in
                ReportTableRow(
                    shift: shift,
                    isExpanded: expandedNote?.id == shift.id,
                    onToggleNote: { expandedNote = expandedNote?.id == shift.id ? nil : shift }
                )
                if shift.id != shifts.last?.id { Divider() }
            }
            Divider()
            ReportTableTotals(shifts: shifts)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ReportTableHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Date").frame(width: 70, alignment: .leading)
            Text("Site").frame(maxWidth: .infinity, alignment: .leading)
            Text("Duration").frame(width: 54, alignment: .trailing)
            Text("Total").frame(width: 70, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }
}

struct ReportTableRow: View {
    let shift: Shift
    let isExpanded: Bool
    let onToggleNote: () -> Void

    var durationText: String {
        switch shift.payUnit {
        case .perDay: return shift.dayFraction?.label ?? "Full"
        case .perHour: return "\((shift.hoursWorked ?? 0).formatted())h"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(shift.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                    .frame(width: 70, alignment: .leading)
                    .font(.footnote)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(shift.site?.name ?? "—").font(.footnote.bold()).lineLimit(1)
                        if shift.hasStreakBonus { Text("🎯").font(.caption) }
                    }
                    if let emp = shift.site?.employer?.name {
                        Text(emp).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(durationText).frame(width: 54, alignment: .trailing).font(.footnote)
                Text(shift.totalPay.formatted(.currency(code: "USD")))
                    .frame(width: 70, alignment: .trailing)
                    .font(.footnote.bold())
                    .foregroundStyle(Color.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if let notes = shift.notes, !notes.isEmpty {
                Button(action: onToggleNote) {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption2)
                        Text(isExpanded ? "Hide notes" : notes.prefix(40) + (notes.count > 40 ? "…" : ""))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                if isExpanded {
                    Text(notes)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct ReportTableTotals: View {
    let shifts: [Shift]
    var total: Decimal { shifts.reduce(0) { $0 + $1.totalPay } }

    var body: some View {
        HStack(spacing: 4) {
            Text("Totals").font(.footnote.bold()).frame(width: 70, alignment: .leading)
            Spacer()
            Text(total.formatted(.currency(code: "USD")))
                .frame(width: 70, alignment: .trailing)
                .font(.footnote.bold())
                .foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
    }
}

// MARK: - Bonus Payout Table

struct BonusPayoutTableCard: View {
    let rows: [BonusPayoutRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Payout Date").frame(width: 84, alignment: .leading)
                Text("Bonus").frame(maxWidth: .infinity, alignment: .leading)
                Text("Service").frame(width: 58, alignment: .trailing)
                Text("Amount").frame(width: 78, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.payoutDate, format: .dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits))
                            .frame(width: 84, alignment: .leading)
                            .font(.footnote)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.bonusName).font(.footnote.bold()).lineLimit(1)
                            Text("\(row.employerName) · \(row.siteName) · \(row.schedule.shortLabel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.serviceDate, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .frame(width: 58, alignment: .trailing)
                            .font(.footnote)
                        Text(row.amount.formatted(.currency(code: "USD")))
                            .frame(width: 78, alignment: .trailing)
                            .font(.footnote.bold())
                            .foregroundStyle(Color.accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                if row.id != rows.last?.id { Divider() }
            }
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Paycheck Estimator

struct PaycheckGroup: Identifiable {
    var id: Date { paycheckDate }
    let paycheckDate: Date
    let rows: [PaycheckAggregationRow]

    var total: Decimal { rows.reduce(0) { $0 + $1.amount } }
}

struct PaycheckAnchorWarningCard: View {
    let employers: [Employer]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Paycheck anchor needed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("The paycheck estimator only includes employers with a known pay-period end date and actual paycheck date. Configure both anchors in Employer setup for: \(employers.map(\.name).joined(separator: ", ")).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PaycheckEstimatorSummaryCard: View {
    let rowCount: Int
    let paycheckCount: Int
    let totalEstimate: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paycheck Estimator")
                .font(.headline)
            Text("Groups base pay, on-call, custom bonuses, and streak bonuses by expected paycheck date using the employer's known pay-period end date and the paycheck date for that same period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(paycheckCount) paycheck\(paycheckCount == 1 ? "" : "s") · \(rowCount) line item\(rowCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totalEstimate.formatted(.currency(code: "USD")))
                    .font(.title2.bold())
                    .foregroundStyle(Color.accent)
            }
        }
        .padding(16)
        .background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PaycheckEstimatorBreakdownCard: View {
    let rows: [PaycheckAggregationRow]

    private var componentBreakdown: [(String, Decimal)] { totals(groupedBy: { $0.componentName }) }
    private var employerBreakdown: [(String, Decimal)] { totals(groupedBy: { $0.employerName }) }
    private var siteBreakdown: [(String, Decimal)] { totals(groupedBy: { "\($0.employerName) · \($0.siteName)" }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Estimated Check Breakdown")
                .font(.headline)
            breakdownSection(title: "By Pay Component", values: componentBreakdown)
            breakdownSection(title: "By Employer", values: employerBreakdown)
            breakdownSection(title: "By Site / Location", values: siteBreakdown)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func breakdownSection(title: String, values: [(String, Decimal)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(values, id: \.0) { label, amount in
                HStack {
                    Text(label).font(.footnote)
                    Spacer()
                    Text(amount.formatted(.currency(code: "USD"))).font(.footnote.bold())
                }
            }
        }
    }

    private func totals(groupedBy key: (PaycheckAggregationRow) -> String) -> [(String, Decimal)] {
        let grouped = Dictionary(grouping: rows, by: key)
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.0 < $1.0 }
    }
}

struct PaycheckEstimatorTableCard: View {
    let groups: [PaycheckGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paycheck")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(group.paycheckDate, format: .dateTime.month(.abbreviated).day().year())
                                .font(.headline)
                        }
                        Spacer()
                        Text(group.total.formatted(.currency(code: "USD")))
                            .font(.title3.bold())
                            .foregroundStyle(Color.accent)
                    }
                    .padding(12)
                    .background(Color.accent.opacity(0.06))

                    ForEach(group.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.componentName).font(.footnote.bold()).lineLimit(1)
                                    Text("\(row.employerName) · \(row.siteName)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(paycheckRowDetailText(row))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.amount.formatted(.currency(code: "USD")))
                                    .font(.footnote.bold())
                                    .foregroundStyle(Color.accent)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        if row.id != group.rows.last?.id { Divider() }
                    }
                }
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func paycheckRowDetailText(_ row: PaycheckAggregationRow) -> String {
        let worked = row.serviceDate.formatted(.dateTime.month(.abbreviated).day())
        let start = row.aggregationStart.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        let end = row.aggregationEnd.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        return "Worked \(worked) · Aggregates \(start)–\(end)"
    }
}

// MARK: - PDF Preview

struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct PDFPreviewSheet: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
