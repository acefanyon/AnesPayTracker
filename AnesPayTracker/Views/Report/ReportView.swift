import SwiftUI
import SwiftData

// MARK: - Report View

struct ReportView: View {
    @Query private var employers: [Employer]
    @Query(sort: \Shift.date) private var allShifts: [Shift]
    @Query(sort: \Site.name) private var allSites: [Site]

    @State private var reportMode: ReportMode = .earnings
    @State private var dateRange: ReportDateRange = .thisMonth
    @State private var bonusPayoutDateRange: BonusPayoutDateRange = .thisMonth
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var selectedEmployer: Employer?
    @State private var selectedSite: Site?
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
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
        case .ytd:
            var comps = cal.dateComponents([.year], from: today)
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

    var totalBase: Decimal { filteredShifts.reduce(0) { $0 + $1.basePay } }
    var totalBonus: Decimal { filteredShifts.reduce(0) { $0 + $1.bonusPay } }
    var totalStreak: Decimal { filteredShifts.reduce(0) { $0 + ($1.streakBonusAmount ?? 0) } }
    var grandTotal: Decimal { filteredShifts.reduce(0) { $0 + $1.totalPay } }
    var totalBonusPayout: Decimal { bonusPayoutRows.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ReportFiltersCard(
                        reportMode: $reportMode,
                        dateRange: $dateRange,
                        bonusPayoutDateRange: $bonusPayoutDateRange,
                        customStart: $customStart,
                        customEnd: $customEnd,
                        selectedEmployer: $selectedEmployer,
                        selectedSite: $selectedSite,
                        employers: employers,
                        sites: allSites
                    )

                    if reportMode == .earnings {
                        earningsReportBody
                    } else {
                        bonusPayoutReportBody
                    }
                }
                .padding(16)
            }
            .navigationTitle("Report")
            .sheet(isPresented: $showShareSheet) {
                if let url = pdfURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    @ViewBuilder private var earningsReportBody: some View {
        if !filteredShifts.isEmpty {
            ReportSummaryCard(
                shiftCount: filteredShifts.count,
                totalBase: totalBase,
                totalBonus: totalBonus,
                totalStreak: totalStreak,
                grandTotal: grandTotal
            )
            ReportTableCard(shifts: filteredShifts, expandedNote: $expandedNote)
            exportButton
        } else {
            EmptyStateView(icon: "doc.text", title: "No shifts in range", message: "Try a different date range or filter.")
                .padding(.top, 40)
        }
    }

    @ViewBuilder private var bonusPayoutReportBody: some View {
        if !bonusPayoutRows.isEmpty {
            BonusPayoutSummaryCard(rowCount: bonusPayoutRows.count, totalBonusPayout: totalBonusPayout)
            BonusPayoutBreakdownCard(rows: bonusPayoutRows)
            BonusPayoutTableCard(rows: bonusPayoutRows)
            exportButton
        } else {
            EmptyStateView(icon: "calendar.badge.clock", title: "No bonus payouts in range", message: "Try this month, this quarter, or a custom payout period.")
                .padding(.top, 40)
        }
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
        if reportMode == .earnings {
            let (start, end) = currentDateBounds
            pdfURL = generator.generate(
                shifts: filteredShifts,
                startDate: start,
                endDate: end,
                employerFilter: selectedEmployer?.name,
                siteFilter: selectedSite?.name
            )
        } else {
            let (start, end) = currentBonusPayoutBounds
            pdfURL = generator.generateBonusPayoutReport(
                rows: bonusPayoutRows,
                startDate: start,
                endDate: end,
                employerFilter: selectedEmployer?.name,
                siteFilter: selectedSite?.name
            )
        }
        showShareSheet = pdfURL != nil
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
}

enum ReportDateRange: String, CaseIterable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if reportMode == .earnings {
                        ForEach(ReportDateRange.allCases, id: \.self) { range in
                            FilterChip(label: range.rawValue, isSelected: dateRange == range) { dateRange = range }
                        }
                    } else {
                        ForEach(BonusPayoutDateRange.allCases, id: \.self) { range in
                            FilterChip(label: range.rawValue, isSelected: bonusPayoutDateRange == range) { bonusPayoutDateRange = range }
                        }
                    }
                }
            }

            if (reportMode == .earnings && dateRange == .custom) || (reportMode == .bonusPayouts && bonusPayoutDateRange == .custom) {
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
